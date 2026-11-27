#!/usr/bin/env python3
"""Usage: review-expectation-diffs.py --base-records DIR --head-records DIR --approved FILE --report DIR
                                   [--failed-tests FILE] [--expected-classes FILE] [--examples N]
       review-expectation-diffs.py --self-test DIR

Sorts every generated output a change alters into classes, accepts the classes an approved-differences file
lists, and shows a person only the classes nobody approved yet: one example of each and how many tests have it.
Run it with `python3 -I`, on the same record directories `regenerate-expectations.py` reads (a run on the old
generator and a run on the new one, each with SAFEDI_TEST_RECORD_DIRECTORY set).

How an output is compared. The records of both runs are joined by key; every generation record whose content
differs is one changed output, and every assertion record of the head run (a diagnostic the test did not expect)
is one too, its expected text against its actual text. Each side is split into top-level members (a line indented
four spaces opens one), and inside each member:
  1. the approved file's rewrites are applied in order, each to the side it names (`base`, `head` or `both`):
     `text` (a regular expression over the member's text, MULTILINE), `line` (over each stripped line), `dropLine`
     (drops each stripped line it matches);
  2. every function whose header matches an entry's `hoistFunctions` pattern is lifted out of its nesting into a
     map from its name to the set of its bodies, its own nested functions lifted the same way, so that where a
     function is declared, and how many times, no longer shows;
  3. what is left of the member (its statements, in order) must be equal on both sides, and every body a head
     function has must equal one of the bodies the base gave that name, and every base name must be a head name.
Then indentation is gone and nothing else is. An output with nothing left over is accepted; the entries it needed
are found by taking each one out in turn (in file order) and keeping it out while the output stays accepted.

Classes. What is left over is cut into shapes: a line changed in place becomes its token difference with one token
of context each side, a line added or removed becomes the whole line, a line removed in one place and added in
another becomes `moved`, a function only one side has becomes `function added` or `function removed`. Identifiers
are numbered by first appearance within a shape (`X1`, `X2`, keeping `__safeDI_` and trailing underscores), and
Swift keywords and SafeDI's own names stay as they are, so one shape stands for the same change in any test. An
entry's `shapes` list accepts exactly those shapes. A test's class is the set of its shapes that no entry accepts;
tests with one set are one class.

Approved file. JSON: {"entries": [{"id", "ruling", "summary", "steps": [...], "shapes": [...]}]}. Each step is one
of {"text"|"line"|"dropLine": PATTERN, "replacement": STRING, "side": "base"|"head"|"both"} or
{"hoistFunctions": PATTERN} (the pattern matches a stripped header line and its group "name" names the function).
An entry with only `shapes` approves what the tool printed for a class a person read; copy the class's `approve`
snippet from the report into the file. Ids are unique; a pattern that can match the empty string is rejected.

Report. REPORT/report.txt and REPORT/classes.json: the counts, every accepted test with the entries it needed,
every new class (its shapes, how many tests and outputs, its tests, one example's leftover lines and its raw
difference, an `approve` snippet), and, with --failed-tests (one test name per line), each failed test with no
changed output or only accepted ones, which fails for a reason no output shows (read the test). With
--expected-classes (JSON: test name -> label) the report also prints how the tool's classes match those labels.
Two runs over the same inputs write the same bytes.

Exit status: 0 when every changed output is accepted, 1 when some class is new, 2 on an error.
"""
import argparse
import collections
import difflib
import json
import os
import re
import sys
import threading

FUNCTION_NAME = re.compile(r"\bfunc (?P<name>[A-Za-z_][A-Za-z0-9_]*)\(")
TOKEN = re.compile(
    r"//.*$|\"(?:[^\"\\]|\\.)*\"|`[^`]*`|[A-Za-z_][A-Za-z0-9_]*|[0-9]+(?:\.[0-9]+)?|->|\.\.\.|\.\.<|[^\sA-Za-z0-9_]"
)
# Words a shape keeps, so that a shape says which construct changed: Swift's keywords and SafeDI's own names.
KEPT_WORDS = {
    "let", "var", "func", "return", "if", "else", "guard", "switch", "case", "default", "for", "in", "while", "try",
    "await", "async", "throws", "rethrows", "some", "any", "nil", "true", "false", "self", "Self", "init", "static",
    "public", "package", "internal", "fileprivate", "private", "open", "nonisolated", "isolated", "inout", "where",
    "extension", "struct", "class", "enum", "actor", "protocol", "typealias", "import", "do", "catch", "_", "Sendable",
    "escaping", "MainActor", "instance", "safeDIOverrides", "safeDIBuilder", "SafeDIOverrides",
    "SafeDIMockConfiguration", "Instantiator", "SendableInstantiator", "ErasedInstantiator",
    "SendableErasedInstantiator", "LazilyInstantiated", "mock", "instantiate", "Optional", "Void",
}
SIDES = ("base", "head", "both")
SCOPES = ("mock", "production", "any")
# A member that opens a mock: a static function, which is how SafeDI spells `mock()`, a custom mock and their helpers.
MOCK_MEMBER = re.compile(r"^(?:(?:public|package|internal|fileprivate|private|nonisolated|@\w+) )*static func ")
# A member that continues the one before it: the rest of a signature that spans lines.
CONTINUED_MEMBER = re.compile(r"^[)\]]")
# Tokens of context a changed line's shape keeps on each side of a change.
CONTEXT = 2


class ApprovedFileError(Exception):
    pass


def compile_pattern(pattern, where):
    try:
        expression = re.compile(pattern, re.MULTILINE)
    except re.error as error:
        raise ApprovedFileError("%s: %s" % (where, error))
    if expression.fullmatch(""):
        raise ApprovedFileError("%s: the pattern matches the empty string" % where)
    return expression


def load_approved(path):
    with open(path, encoding="utf-8") as file:
        document = json.load(file)
    entries = []
    seen = set()
    for index, entry in enumerate(document.get("entries", [])):
        identifier = entry.get("id")
        if not identifier or identifier in seen:
            raise ApprovedFileError("entry %d: a missing or repeated id %r" % (index, identifier))
        seen.add(identifier)
        scope = entry.get("scope", "any")
        if scope not in SCOPES:
            raise ApprovedFileError("%s: scope is mock, production or any" % identifier)
        steps = []
        for step_index, step in enumerate(entry.get("steps", [])):
            where = "%s step %d" % (identifier, step_index)
            if "hoistFunctions" in step:
                expression = compile_pattern(step["hoistFunctions"], where)
                if "name" not in expression.groupindex:
                    raise ApprovedFileError("%s: hoistFunctions needs a group named name" % where)
                steps.append(("hoist", expression, None, "both", scope))
                continue
            kinds = [kind for kind in ("text", "line", "dropLine") if kind in step]
            if len(kinds) != 1:
                raise ApprovedFileError("%s: one of text, line, dropLine or hoistFunctions" % where)
            side = step.get("side", "both")
            if side not in SIDES:
                raise ApprovedFileError("%s: side is base, head or both" % where)
            replacement = step.get("replacement", "")
            kind = kinds[0] + ("*" if step.get("repeat") else "")
            steps.append((kind, compile_pattern(step[kinds[0]], where), replacement, side, scope))
        status = entry.get("status", "approved")
        if status not in ("approved", "withdrawn", "notApproved"):
            raise ApprovedFileError("%s: status is approved, withdrawn or notApproved" % identifier)
        if status == "notApproved" and steps:
            raise ApprovedFileError("%s: a notApproved entry names shapes, not steps" % identifier)
        tests = entry.get("tests")
        entries.append({"id": identifier, "steps": steps, "shapes": set(entry.get("shapes", [])), "status": status,
                        "tests": set(tests) if tests is not None else None})
    return entries


# Records.


def load_records(directory):
    records = {}
    for name in sorted(os.listdir(directory)):
        if not (name.endswith(".json") and len(name) == 69):
            continue
        with open(os.path.join(directory, name), encoding="utf-8") as file:
            record = json.load(file)
        records[record["key"]] = record
    return records


def test_name(record):
    return record.get("testName", "").split("(")[0]


def changed_outputs(base, head):
    """(test, output name, base text, head text) for every output the change alters, in key order."""
    changes = []
    for key in sorted(head):
        record = head[key]
        if record.get("kind") == "generation":
            old = base.get(key)
            if old is not None and old["content"] != record["content"]:
                changes.append((test_name(record), record["outputName"], old["content"], record["content"]))
        elif record.get("kind") == "assertion":
            changes.append((test_name(record), "diagnostics", record["expected"], record["actual"]))
    return changes


# Canonical form.


def members(text):
    """The text split at each line indented exactly four spaces that is not a closing brace."""
    out = [[]]
    for line in text.split("\n"):
        if line.startswith("    ") and not line.startswith("     ") and line.strip() != "}":
            out.append([])
        out[-1].append(line)
    return ["\n".join(lines) for lines in out]


def member_scopes(texts):
    """Whether each member belongs to a mock (`mock`) or to anything else (`production`): a static function opens a
    mock, a member that continues a signature keeps the scope of the one before it, and any other member opens
    production code."""
    scopes = []
    for text in texts:
        first = text.lstrip("\n").split("\n")[0].strip()
        if CONTINUED_MEMBER.match(first) and scopes:
            scopes.append(scopes[-1])
        else:
            scopes.append("mock" if MOCK_MEMBER.match(first) else "production")
    return scopes


def substitute(expression, replacement, text, repeat):
    """`text` with the expression replaced, again and again until nothing changes when `repeat` is set."""
    while True:
        rewritten = expression.sub(replacement, text)
        if not repeat or rewritten == text:
            return rewritten
        text = rewritten


def rewrite(text, steps, side):
    for kind, expression, replacement, step_side, _ in steps:
        if step_side not in (side, "both"):
            continue
        repeat = kind.endswith("*")
        kind = kind.rstrip("*")
        if kind == "text":
            text = substitute(expression, replacement, text, repeat)
        elif kind in ("line", "dropLine"):
            lines = []
            for line in text.split("\n"):
                stripped = line.strip()
                if kind == "dropLine":
                    if not expression.search(stripped):
                        lines.append(line)
                else:
                    lines.append(substitute(expression, replacement, stripped, repeat))
            text = "\n".join(lines)
    return text


def canonical(text, steps, side):
    """(statements, functions) of one member: functions maps a name to the set of its bodies."""
    hoists = [expression for kind, expression, _, _, _ in steps if kind == "hoist"]
    lines = [line.strip() for line in rewrite(text, steps, side).split("\n")]
    functions = collections.defaultdict(set)

    def header_name(line):
        for expression in hoists:
            match = expression.search(line)
            if match and line.endswith("{"):
                return match.group("name")
        return None

    def block(start, end):
        statements = []
        index = start
        while index < end:
            line = lines[index]
            name = header_name(line)
            if name is None:
                if line:
                    statements.append(line)
                index += 1
                continue
            depth = 0
            close = index
            while close < end:
                depth += lines[close].count("{") - lines[close].count("}")
                if depth <= 0:
                    break
                close += 1
            body = block(index + 1, min(close, end))
            functions[name].add((line,) + tuple(body))
            index = close + 1
        return statements

    return block(0, len(lines)), functions


def residual(base_text, head_text, steps):
    """The leftover differences of one output after the steps, as (kind, base lines, head lines) triples."""
    leftovers = []
    base_members = members(base_text)
    head_members = members(head_text)
    if len(base_members) != len(head_members):
        matcher = difflib.SequenceMatcher(None, base_members, head_members, autojunk=False)
        pairs = []
        for tag, a0, a1, b0, b1 in matcher.get_opcodes():
            if tag == "equal":
                continue
            if tag == "replace" and a1 - a0 == b1 - b0:
                pairs += list(zip(base_members[a0:a1], head_members[b0:b1]))
            else:
                leftovers.append(("lines", [l.strip() for m in base_members[a0:a1] for l in m.split("\n") if l.strip()],
                                  [l.strip() for m in head_members[b0:b1] for l in m.split("\n") if l.strip()]))
    else:
        pairs = [(a, b) for a, b in zip(base_members, head_members) if a != b]
    scope_of = dict(zip(base_members, member_scopes(base_members)))
    for base_member, head_member in pairs:
        scoped = [step for step in steps if step[4] in ("any", scope_of[base_member])]
        base_statements, base_functions = canonical(base_member, scoped, "base")
        head_statements, head_functions = canonical(head_member, scoped, "head")
        if base_statements != head_statements:
            leftovers.append(("lines", base_statements, head_statements))
        for name in sorted(set(base_functions) | set(head_functions)):
            base_bodies = base_functions.get(name, set())
            head_bodies = head_functions.get(name, set())
            if not head_bodies:
                leftovers.append(("function removed", [sorted(base_bodies)[0][0]], []))
                continue
            if not base_bodies:
                leftovers.append(("function added", [], [sorted(head_bodies)[0][0]]))
                continue
            for body in sorted(head_bodies - base_bodies):
                closest = max(sorted(base_bodies), key=lambda candidate: difflib.SequenceMatcher(
                    None, candidate, body, autojunk=False).ratio())
                leftovers.append(("lines", list(closest), list(body)))
    return leftovers


# Shapes.


def tokens(line):
    return TOKEN.findall(line)


def abstract(token_list):
    numbers = {}
    out = []
    for token in token_list:
        if token.startswith("//"):
            out.append("//…")
            continue
        if token.startswith('"'):
            out.append('"…"')
            continue
        quoted = token.startswith("`")
        word = token.strip("`")
        if not re.match(r"[A-Za-z_]", word) or word in KEPT_WORDS:
            out.append(token)
            continue
        prefix = "__safeDI_" if word.startswith("__safeDI_") else ""
        core = word[len(prefix):]
        trailing = len(core) - len(core.rstrip("_"))
        core = core.strip("_") or "_"
        if core in KEPT_WORDS and not prefix:
            number = core
        else:
            number = numbers.setdefault(core, "X%d" % (len(numbers) + 1))
        spelled = prefix + number + "_" * trailing
        out.append("`%s`" % spelled if quoted else spelled)
    return out


def token_shape(old_line, new_line):
    old, new = tokens(old_line), tokens(new_line)
    matcher = difflib.SequenceMatcher(None, old, new, autojunk=False)
    pieces = []
    for tag, a0, a1, b0, b1 in matcher.get_opcodes():
        if tag == "equal":
            continue
        before = old[max(a0 - CONTEXT, 0):a0]
        after = old[a1:a1 + CONTEXT]
        pieces.append((before, old[a0:a1], new[b0:b1], after))
    # Identifiers are numbered across the whole shape, so a rename's two sides share a number.
    flat = [token for before, removed, added, after in pieces for token in before + removed + added + after]
    abstracted = iter(abstract(flat))
    parts = []
    for before, removed, added, after in pieces:
        words = [next(abstracted) for _ in before]
        gone = [next(abstracted) for _ in removed]
        new = [next(abstracted) for _ in added]
        words.append(("{- " + " ".join(gone) + " -}" if gone else "") + ("{+ " + " ".join(new) + " +}" if new else ""))
        words += [next(abstracted) for _ in after]
        parts.append(" ".join(words))
    text = " … ".join(parts)
    return "changed: " + text


def line_shape(line):
    return " ".join(abstract(tokens(line)))


def shapes_of(leftovers):
    """The shapes of one output's leftovers. A line removed in one place and added in another, of any leftover of
    the output, is one moved shape."""
    shapes = set()
    removed = []
    added = []
    for kind, old, new in leftovers:
        if kind == "function removed":
            shapes.add("function removed: " + line_shape(old[0]))
            continue
        if kind == "function added":
            shapes.add("function added: " + line_shape(new[0]))
            continue
        matcher = difflib.SequenceMatcher(None, old, new, autojunk=False)
        for tag, a0, a1, b0, b1 in matcher.get_opcodes():
            if tag == "equal":
                continue
            if tag == "replace" and a1 - a0 == b1 - b0:
                for old_line, new_line in zip(old[a0:a1], new[b0:b1]):
                    shapes.add(token_shape(old_line, new_line))
                continue
            removed += old[a0:a1]
            added += new[b0:b1]
    removed_shapes = collections.Counter(line_shape(line) for line in removed)
    added_shapes = collections.Counter(line_shape(line) for line in added)
    for shape in sorted(removed_shapes | added_shapes):
        moved = min(removed_shapes[shape], added_shapes[shape])
        if moved:
            shapes.add("moved: " + shape)
        if removed_shapes[shape] > moved:
            shapes.add("removed: " + shape)
        if added_shapes[shape] > moved:
            shapes.add("added: " + shape)
    return shapes


# Classification.


def judge(base_text, head_text, entries):
    """(accepted, shapes no entry accepts, every leftover shape) for one output under the given entries."""
    steps = [step for entry in entries for step in entry["steps"]]
    approved_shapes = set().union(*(entry["shapes"] for entry in entries)) if entries else set()
    leftovers = residual(base_text, head_text, steps)
    shapes = shapes_of(leftovers)
    return not (shapes - approved_shapes), shapes - approved_shapes, shapes, leftovers


def needed_entries(base_text, head_text, entries):
    kept = list(entries)
    for entry in entries:
        trial = [candidate for candidate in kept if candidate is not entry]
        if judge(base_text, head_text, trial)[0]:
            kept = trial
    return [entry["id"] for entry in kept]


def classify(changes, entries, only_tests=None):
    """Each test's outputs judged under the entries that apply to it. An output the approved entries do not accept is
    judged again with the withdrawn ones; its shapes a notApproved entry lists are labeled with that entry."""
    by_test = collections.OrderedDict()
    for test, output, base_text, head_text in changes:
        if only_tests is not None and test not in only_tests:
            continue
        applying = [entry for entry in entries if entry["tests"] is None or test in entry["tests"]]
        approved = [entry for entry in applying if entry["status"] == "approved"]
        withdrawn = [entry for entry in applying if entry["status"] == "withdrawn"]
        item = by_test.setdefault(test, {"outputs": 0, "needed": set(), "new": set(), "labels": set(), "examples": []})
        item["outputs"] += 1
        accepted, new_shapes, _, leftovers = judge(base_text, head_text, approved)
        if accepted:
            item["needed"] |= set(needed_entries(base_text, head_text, approved))
            continue
        # In the file's order, since a withdrawn entry's steps may need to run before an approved one's.
        approved_or_withdrawn = [entry for entry in applying if entry["status"] != "notApproved"]
        if withdrawn and judge(base_text, head_text, approved_or_withdrawn)[0]:
            needed = needed_entries(base_text, head_text, approved_or_withdrawn)
            item["labels"] |= {"withdrawn " + entry["id"] for entry in withdrawn if entry["id"] in needed}
        for entry in applying:
            if entry["status"] == "notApproved" and new_shapes & entry["shapes"]:
                item["labels"].add("not approved: " + entry["id"])
        item["new"] |= new_shapes
        item["examples"].append((output, base_text, head_text, leftovers))
    return by_test


def raw_difference(base_text, head_text, limit=60):
    lines = [line for line in difflib.unified_diff(base_text.split("\n"), head_text.split("\n"), lineterm="", n=0)
             if not line.startswith(("---", "+++"))]
    return lines[:limit] + (["… %d more lines" % (len(lines) - limit)] if len(lines) > limit else [])


def report(by_test, entries, failed_tests, passing, expected, examples, directory):
    order = [entry["id"] for entry in entries]
    accepted = {test: item for test, item in by_test.items() if not item["new"]}
    classes = collections.defaultdict(list)
    for test, item in by_test.items():
        if item["new"]:
            classes[(tuple(sorted(item["labels"])), tuple(sorted(item["new"])))].append(test)
    class_list = sorted(classes.items(), key=lambda pair: (-len(pair[1]), pair[0]))
    class_number = {test: number for number, (_, tests) in enumerate(class_list, 1) for test in tests}
    out = []
    out.append("%d tests changed %d outputs: %d tests accepted, %d tests in %d new classes."
               % (len(by_test), sum(item["outputs"] for item in by_test.values()), len(accepted),
                  sum(len(tests) for _, tests in class_list), len(class_list)))
    combinations = collections.Counter(
        ", ".join(sorted(item["needed"], key=order.index)) or "(no entry: the outputs are equal once normalized)"
        for item in accepted.values())
    out.append("")
    out.append("Accepted, by the entries each test needed:")
    for combination, count in sorted(combinations.items(), key=lambda pair: (-pair[1], pair[0])):
        out.append("  %4d  %s" % (count, combination))
    json_classes = []
    for number, ((labels, shapes), tests) in enumerate(class_list, 1):
        tests = sorted(tests)
        outputs = sum(by_test[test]["outputs"] for test in tests)
        out.append("")
        out.append("== New class %d: %d tests, %d outputs%s" % (number, len(tests), outputs,
                                                             "".join("; " + label for label in labels)))
        for shape in shapes:
            out.append("   shape: " + shape)
        out.append("   tests: " + ", ".join(tests[:12]) + (" … and %d more" % (len(tests) - 12) if len(tests) > 12 else ""))
        for test in tests[:examples]:
            output, base_text, head_text, leftovers = by_test[test]["examples"][0]
            out.append("   example: %s, %s" % (test, output))
            for kind, old, new in leftovers[:6]:
                out.append("     leftover (%s):" % kind)
                for line in difflib.unified_diff(old, new, lineterm="", n=1):
                    if not line.startswith(("---", "+++", "@@")):
                        out.append("       " + line)
        approve = {"id": "class-%d" % number, "ruling": "who approved it, when", "summary": "what the class is",
                   "shapes": list(shapes)}
        out.append("   approve: " + json.dumps(approve, ensure_ascii=False))
        json_classes.append({"labels": list(labels), "shapes": list(shapes), "tests": tests, "outputs": outputs})
    if failed_tests is not None:
        quiet = sorted(test for test in failed_tests if test not in by_test)
        out.append("")
        out.append("== Failed tests with no changed output (%d): they fail for a reason no output shows, read each"
                   % len(quiet))
        for test in quiet:
            out.append("   " + test)
        out.append("== Tests whose outputs changed and that did not fail (%d): no literal compares those outputs, "
                   "so they are not classified" % len(passing))
    if expected is not None:
        out.append("")
        out.append("== Against the expected labels")
        tool_label = {}
        for test, item in by_test.items():
            tool_label[test] = ("new class %d" % class_number[test] if item["new"]
                                else "accepted: " + ", ".join(sorted(item["needed"], key=order.index)))
        table = collections.Counter((label, tool_label.get(test, "(no changed output)"))
                                    for test, label in expected.items())
        for (label, mine), count in sorted(table.items()):
            out.append("  %4d  %-60s -> %s" % (count, label, mine))
    os.makedirs(directory, exist_ok=True)
    with open(os.path.join(directory, "report.txt"), "w", encoding="utf-8") as file:
        file.write("\n".join(out) + "\n")
    with open(os.path.join(directory, "classes.json"), "w", encoding="utf-8") as file:
        json.dump({"accepted": {test: sorted(item["needed"], key=order.index) for test, item in sorted(accepted.items())},
                   "classes": json_classes}, file, indent=1, ensure_ascii=False, sort_keys=True)
        file.write("\n")
    return len(class_list)


def main(arguments):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base-records")
    parser.add_argument("--head-records")
    parser.add_argument("--approved")
    parser.add_argument("--report")
    parser.add_argument("--failed-tests")
    parser.add_argument("--expected-classes")
    parser.add_argument("--examples", type=int, default=1)
    parser.add_argument("--self-test")
    options = parser.parse_args(arguments)
    if options.self_test:
        return self_test(options.self_test)
    if not all([options.base_records, options.head_records, options.approved, options.report]):
        parser.error("--base-records, --head-records, --approved and --report are required")
    try:
        entries = load_approved(options.approved)
    except (ApprovedFileError, ValueError, OSError) as error:
        print("error: %s: %s" % (options.approved, error), file=sys.stderr)
        return 2
    changes = changed_outputs(load_records(options.base_records), load_records(options.head_records))
    failed = None
    if options.failed_tests:
        with open(options.failed_tests, encoding="utf-8") as file:
            failed = sorted({line.strip().split("(")[0] for line in file if line.strip()})
    expected = None
    if options.expected_classes:
        with open(options.expected_classes, encoding="utf-8") as file:
            expected = json.load(file)
    by_test = classify(changes, entries, set(failed) if failed is not None else None)
    passing = sorted({change[0] for change in changes} - set(failed)) if failed is not None else []
    new = report(by_test, entries, failed, passing, expected, options.examples, options.report)
    with open(os.path.join(options.report, "report.txt"), encoding="utf-8") as file:
        print(file.read().split("\n\n")[0])
    return 1 if new else 0


def self_test(directory):
    if os.path.exists(directory):
        print("error: %s exists" % directory, file=sys.stderr)
        return 2
    os.makedirs(directory)
    failures = []

    def check(name, condition):
        if not condition:
            failures.append(name)

    hoist = {"hoistFunctions": r"\bfunc (?P<name>__safeDI_\w+)\("}
    path = os.path.join(directory, "approved.json")
    with open(path, "w", encoding="utf-8") as file:
        json.dump({"entries": [
            {"id": "hoist", "steps": [hoist]},
            {"id": "typed", "shapes": ["changed: let X1 {+ : X2 +} = __safeDI_X1"]},
        ]}, file)
    entries = load_approved(path)
    nested = "    func mock() -> A {\n        func __safeDI_b() -> B {\n            func __safeDI_c() -> C {\n" \
             "                C()\n            }\n            let c = __safeDI_c()\n            return B(c: c)\n" \
             "        }\n        return A(b: __safeDI_b())\n    }"
    flat = "    func mock() -> A {\n        func __safeDI_c() -> C {\n            C()\n        }\n" \
           "        func __safeDI_b() -> B {\n            let c = __safeDI_c()\n            return B(c: c)\n" \
           "        }\n        return A(b: __safeDI_b())\n    }"
    accepted, _, _, _ = judge(nested, flat, entries)
    check("hoisting accepts a function moved out of its parent", accepted)
    check("only the hoisting entry is needed", needed_entries(nested, flat, entries) == ["hoist"])
    typed = flat.replace("let c = ", "let c: C = ")
    check("an approved shape is accepted", judge(nested, typed, entries)[0])
    optional = flat.replace("let c = ", "let c: C? = ")
    accepted, new, _, _ = judge(nested, optional, entries)
    check("an optional type is a shape of its own", not accepted and new == {"changed: let X1 {+ : X2 ? +} = __safeDI_X1"})
    renamed = flat.replace("C()", "D()")
    accepted, new, _, _ = judge(nested, renamed, entries)
    check("a changed body is reported", not accepted and new == {"changed: {- X1 -}{+ X2 +} ( )"})
    moved = "    func mock() -> A {\n        func __safeDI_b() -> B {\n            _ = G.self // guard\n" \
            "            return B()\n        }\n        return A(b: __safeDI_b())\n    }"
    moved_head = "    func mock() -> A {\n        _ = G.self // guard\n        func __safeDI_b() -> B {\n" \
                 "            return B()\n        }\n        return A(b: __safeDI_b())\n    }"
    accepted, new, _, _ = judge(moved, moved_head, entries)
    check("a line that moves is one moved shape", new == {"moved: _ = X1 . self //…"})
    try:
        bad = os.path.join(directory, "bad.json")
        with open(bad, "w", encoding="utf-8") as file:
            json.dump({"entries": [{"id": "a", "steps": [{"line": "x*", "replacement": ""}]}]}, file)
        load_approved(bad)
        check("an empty-matching pattern is rejected", False)
    except ApprovedFileError:
        pass
    for name in failures:
        print("self-test failed: " + name, file=sys.stderr)
    print("self-test: %d of %d cases failed" % (len(failures), 7))
    return 1 if failures else 0


if __name__ == "__main__":
    # A chain of nested functions is as deep as the graph it was generated from.
    sys.setrecursionlimit(1_000_000)
    threading.stack_size(512 * 1024 * 1024)
    result = []
    worker = threading.Thread(target=lambda: result.append(main(sys.argv[1:])))
    worker.start()
    worker.join()
    sys.exit(result[0] if result else 2)
