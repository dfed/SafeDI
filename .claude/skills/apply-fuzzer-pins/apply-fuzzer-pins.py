#!/usr/bin/env python3
"""Write the graph fuzzer's new pins into the test sources, from the analysis of a corpus run.

  python3 -I apply-fuzzer-pins.py PINS.json [--checkout DIRECTORY] [--dry-run]
  python3 -I apply-fuzzer-pins.py --self-test DIRECTORY

PINS.json is the `pins.json` the analysis of a corpus run writes (schema 1): the commit the run built, where the
reports came from (`provenance`), and under `pins` every pinned value the run moved, each with the Swift constant that
holds it, its key in that constant (none, a key of the report, or an index), the value pinned and the value the run
derived. The script replaces each pinned literal with the derived one, in the files under `Tests/SafeDIToolFuzzerTests`
and `Tests/SafeDIToolTestSupport` of the checkout, and changes nothing else.

It refuses the whole file, and writes nothing (status 2), unless all of these hold:
  - `schema` is 1, and `provenance.validForHead` is exactly `true`: the reports are known to be of the commit itself,
    not of a merge with a base that has moved, and not of a directory nobody can vouch for;
  - `commit` and `provenance.headSha` are one full SHA, and it is the checkout's `HEAD`;
  - the checkout has no uncommitted change to a tracked file, and each file it would write is byte for byte the
    commit's, so the source it edits is the commit's;
  - the analysis is whole: `complete` is exactly `true`, and `unparsed`, `ambiguousSplit`, `shardsDisagree`,
    `duplicateShard`, `incompleteCorpora` and `rejectedKnownIssueLists` are present and empty. A crashed shard makes
    its corpus incomplete, so it is refused here;
  - every entry of `pins` is an object whose key is absent, a string or an index;
  - every literal it would replace holds the value the report says is pinned. One that does not means the report is
    of another source, so nothing from it is written.

A pin it cannot place is listed and left for a person, and the others are written: a value the source does not hold as
one whole literal (a dictionary built by `reduce`, a key no literal lists, a default of `Corpus`, a number inside a
larger expression such as `max(1_234, floor)` or after a `-`), and a constant that only names another, unless that
one is written to the same value. A constant another constant names (`static let x = y`) is written only when the run
moved that other one to the same value, since writing it moves both; otherwise it is left. What the analysis lists
beside the pins is never applied and is listed too: unknown failures, combine problems nothing accounts for, stale and
misfiled known-issue seeds, and floors a count fell below.

Status 0 means the run moved nothing and the analysis lists nothing. Status 1 means there is work left, which every
run that moved a pin has: the analysis does not derive the pins its `notDerived` names (the smoke and known-issue
hashes, the draw-feature counts of the smoke batches, the smoke seeds), which the unit suite's failures in the same
run give, and a moved fixture or partition hash means the corpus's graphs changed, so its known issues and smoke
seeds are to be derived again. The output names each.

How a key of the report names a literal:
  - no key: the constant's expression holds exactly one number.
  - an index: the constant is an array literal of numbers.
  - `name`: an argument `name:`, `nameCount:` or (for `names`) `nameCount:` of the constant's initializer call, and for
    the retention counts `drawJudged` and `handWrittenJudged`, `judgedDrawingRetentionShape:` and
    `judgedThroughHandWrittenBuilder:`; or, in a dictionary literal, the case whose raw value is `name`.
  - `skip.name`, `shape.name`, `override.name`: that case in the dictionary argument `skipCounts:`, `shapeCounts:`,
    `overrideFieldKindCounts:`.
A number written as `GraphFuzzerSeedSetSum(value: 0x…)` is the argument that call is passed to. Counts are written with
`_` between groups of three digits, sums and hashes as `0x` and upper-case digits, as wide as the literal they replace
(a `_` inside a hexadecimal literal is not kept).
"""

import json
import os
import io
import re
import shutil
import subprocess
import sys

SOURCE_DIRECTORIES = ("Tests/SafeDIToolFuzzerTests", "Tests/SafeDIToolTestSupport")
INTEGRITY_LISTS = ("unparsed", "ambiguousSplit", "shardsDisagree", "duplicateShard", "incompleteCorpora", "rejectedKnownIssueLists")
OTHER_WORK = (("unknownFailures", "unknown failures"), ("unclassified", "combine problems nothing accounts for"), ("stale", "stale known-issue seeds"), ("misfiled", "misfiled known-issue seeds"), ("floors", "counts below their floor"))
LABEL_ALIASES = {"drawJudged": "judgedDrawingRetentionShape", "handWrittenJudged": "judgedThroughHandWrittenBuilder"}
GROUPS = {"skip": "skipCounts", "shape": "shapeCounts", "override": "overrideFieldKindCounts"}
HASH_LABELS = ("fixtureHash", "corpusPartitionHash")
LITERAL = r"(?:0x[0-9A-Fa-f_]+|\d[\d_]*)"
SINGLE_LITERAL = re.compile(r"%s|\w+\(\s*value\s*:\s*%s\s*\)" % (LITERAL, LITERAL))
NUMBER = re.compile(r"(?<![\w.])(0x[0-9A-Fa-f_]+|\d[\d_]*)(?![\w.])")
NAME_BEFORE = re.compile(r"(\.?\w+)\s*:\s*(?:\w+\(\s*value\s*:\s*)?$")
OPENERS = {"(": ")", "[": "]", "{": "}"}


class Refusal(Exception):
    pass


class Follows(LookupError):
    """The constant only names another constant."""

    def __init__(self, expression):
        super().__init__("it is `%s`, and follows it" % expression)
        self.expression = expression


def string_end(text, index):
    """The index after the string literal that starts at `index`, whose interpolations may hold literals of their own."""
    length = len(text)
    hashes = len(re.match(r"#*", text[index:]).group(0))
    index += hashes
    quote = '"""' if text.startswith('"""', index) else '"'
    index += len(quote)
    closing = quote + "#" * hashes
    escape = "\\" + "#" * hashes
    while index < length and not text.startswith(closing, index):
        if text.startswith(escape + "(", index):
            index += len(escape) + 1
            depth = 1
            while index < length and depth:
                if text[index] == '"' or re.match(r'#+"', text[index:]):
                    index = string_end(text, index)
                    continue
                depth += {"(": 1, ")": -1}.get(text[index], 0)
                index += 1
        elif text.startswith(escape, index):
            index += len(escape) + 1
        else:
            index += 1
    return min(length, index + len(closing))


def masked(text):
    """`text` with every comment and string literal's characters replaced by spaces, so that offsets stay."""
    out = list(text)
    index = 0
    length = len(text)

    def blank(start, end):
        for position in range(start, end):
            if out[position] != "\n":
                out[position] = " "

    while index < length:
        if text.startswith("//", index):
            end = text.find("\n", index)
            end = length if end < 0 else end
            blank(index, end)
            index = end
        elif text.startswith("/*", index):
            depth, end = 1, index + 2
            while end < length and depth:
                if text.startswith("/*", end):
                    depth, end = depth + 1, end + 2
                elif text.startswith("*/", end):
                    depth, end = depth - 1, end + 2
                else:
                    end += 1
            blank(index, end)
            index = end
        elif text[index] == '"' or (text[index] == "#" and re.match(r'#+"', text[index:])):
            end = string_end(text, index)
            blank(index, end)
            index = end
        else:
            index += 1
    return "".join(out)


def grouped(value):
    digits = str(abs(value))
    parts = []
    while len(digits) > 3:
        parts.insert(0, digits[-3:])
        digits = digits[:-3]
    parts.insert(0, digits)
    return ("-" if value < 0 else "") + "_".join(parts)


def number(value):
    """The integer a pins.json value or a Swift literal spells, or None."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, str) and NUMBER.fullmatch(value):
        return int(value.replace("_", ""), 0)
    return None


def spelled(value, old_literal):
    if old_literal.lower().startswith("0x"):
        return "0x%0*X" % (len(old_literal.replace("_", "")) - 2, value)
    return grouped(value)


class Token:
    def __init__(self, start, end, text, name, group, wrapped):
        self.start, self.end, self.text, self.name, self.group, self.wrapped = start, end, text, name, group, wrapped
        self.value = int(text.replace("_", ""), 0)


class Sources:
    def __init__(self, checkout):
        self.checkout = checkout
        self.text = {}
        for directory in SOURCE_DIRECTORIES:
            full = os.path.join(checkout, directory)
            for name in sorted(os.listdir(full)) if os.path.isdir(full) else []:
                if name.endswith(".swift"):
                    with open(os.path.join(full, name), encoding="utf-8") as file:
                        self.text[os.path.join(directory, name)] = file.read()
        self.masked = {path: masked(text) for path, text in self.text.items()}
        self.case_names = {}  # raw value -> the names of the cases that have it
        for path, text in self.text.items():
            for match in re.finditer(r'\bcase\s+(\w+)\s*=\s*"((?:[^"\\\n]|\\.)*)"', text):
                if self.masked[path][match.start()] == "c":
                    self.case_names.setdefault(match.group(2), set()).add(match.group(1))

    def declarations(self, constant):
        """[(path, start, end)] of the expressions `static let <constant> … =` is given."""
        found = []
        pattern = re.compile(r"\bstatic\s+let\s+%s\b(?:\s*:\s*[^=\n]+?)?\s*=[ \t]*" % re.escape(constant))
        for path, text in self.masked.items():
            for match in pattern.finditer(text):
                index, stack = match.end(), []
                while index < len(text) and not (text[index] == "\n" and not stack):
                    if text[index] in OPENERS:
                        stack.append(OPENERS[text[index]])
                    elif stack and text[index] == stack[-1]:
                        stack.pop()
                    index += 1
                found.append((path, match.end(), index))
        return found

    def followers(self, constant):
        """The constants that only name `constant`: `static let x = constant` and `static let x = Self.constant`."""
        pattern = re.compile(r"\bstatic\s+let\s+(\w+)\b(?:\s*:\s*[^=\n]+?)?\s*=[ \t]*(?:Self\.)?%s[ \t]*$" % re.escape(constant), re.M)
        return sorted({match.group(1) for text in self.masked.values() for match in pattern.finditer(text)})

    def tokens(self, path, start, end):
        """The numbers of an expression, each with the label or case before it and the label of the bracket it is in."""
        text = self.masked[path]
        tokens = []
        stack = []  # the label before each open bracket
        position = start
        for match in NUMBER.finditer(text, start, end):
            for index in range(position, match.start()):
                if text[index] in OPENERS:
                    before = re.search(r"(\w+)\s*:\s*$", text[start:index])
                    stack.append(before.group(1) if before else None)
                elif text[index] in ")]}" and stack:
                    stack.pop()
            position = match.start()
            before = NAME_BEFORE.search(text[start:match.start()])
            wrapped = bool(before and re.search(r"\(\s*value\s*:\s*$", text[start:match.start()]))
            group = stack[-2] if wrapped and len(stack) > 1 else (stack[-1] if stack and not wrapped else None)
            tokens.append(Token(match.start(), match.end(), match.group(1), before.group(1) if before else None, group, wrapped))
        return tokens


def names_of(key, sources):
    """(group prefix or None, the labels and cases a report key may be spelled as)."""
    group = None
    if "." in key:
        group, key = key.split(".", 1)
    names = {"." + name for name in sources.case_names.get(key, set()) | {key}}
    if group is None:
        names |= {key, key + "Count", LABEL_ALIASES.get(key, key)}
        if key.endswith("s"):
            names.add(key[:-1] + "Count")
    return GROUPS.get(group, "") if group is not None else None, names


def place(pin, sources):
    """(path, token) of the literal `pin` replaces. Raises Refusal when the source disagrees with the report, and
    LookupError, with the reason, when the pin has no literal to replace."""
    constant, key, pinned, actual = pin.get("constant"), pin.get("key"), number(pin.get("pinned")), number(pin.get("actual"))
    if actual is None:
        raise LookupError("the run derived no value")
    if pinned is None:
        raise LookupError("nothing pins it yet: add it by hand")
    if not isinstance(constant, str) or not re.fullmatch(r"[A-Za-z_]\w*", constant):
        raise LookupError("no constant of its own holds it (%s)" % (pin.get("note") or constant))
    declarations = sources.declarations(constant)
    if len(declarations) != 1:
        raise LookupError("%d declarations of `static let %s`" % (len(declarations), constant))
    path, start, end = declarations[0]
    tokens = sources.tokens(path, start, end)
    expression = sources.masked[path][start:end].strip()
    if not tokens and re.fullmatch(r"[A-Za-z_][\w.]*", expression):
        raise Follows(expression[5:] if expression.startswith("Self.") else expression)
    if key is None:
        if not SINGLE_LITERAL.fullmatch(expression):
            raise LookupError("`%s` is not a single literal" % constant)
        candidates = tokens
    elif isinstance(key, int):
        if not re.fullmatch(r"\[[\d_,\s]*\]", expression):
            raise LookupError("`%s` is not an array literal of numbers" % constant)
        candidates = tokens[key:key + 1]
    else:
        group, names = names_of(str(key), sources)
        if group == "":
            raise LookupError("no dictionary argument is known for the group of `%s`" % key)
        candidates = [token for token in tokens if token.name in names and (group is None or token.group == group)]
        if len(candidates) == 1 and not re.match(r"\s*\)\s*(?:[,)\]]|$)" if candidates[0].wrapped else r"\s*(?:[,)\]]|$)", sources.masked[path][candidates[0].end:end]):
            raise LookupError("the literal of `%s` that holds it is part of a larger expression" % constant)
    if len(candidates) != 1:
        raise LookupError("%d literals of `%s` could hold it" % (len(candidates), constant))
    token = candidates[0]
    if token.value != pinned:
        raise Refusal("`%s`%s holds %s, and the report says %s is pinned: the report is not of this source" % (constant, "" if key is None else "[%s]" % key, token.text, pin.get("pinned")))
    return path, token


def git(checkout, *arguments):
    result = subprocess.run(("git", "-C", checkout) + arguments, capture_output=True, text=True)
    if result.returncode != 0:
        raise Refusal("git %s failed in %s: %s" % (" ".join(arguments), checkout, result.stderr.strip()))
    return result.stdout


def check_provenance(document, checkout):
    if document.get("schema") != 1:
        raise Refusal("schema %r: this script reads schema 1" % (document.get("schema"),))
    provenance = document.get("provenance") or {}
    if provenance.get("validForHead") is not True:
        raise Refusal("validForHead is %s: the values are for judging moves only and must not be committed (%s)" % (json.dumps(provenance.get("validForHead")), document.get("statement") or "no statement"))
    commit = document.get("commit")
    if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit) or provenance.get("headSha") != commit:
        raise Refusal("commit %r and provenance.headSha %r are not one full SHA" % (commit, provenance.get("headSha")))
    head = git(checkout, "rev-parse", "HEAD").strip()
    if head != commit:
        raise Refusal("the values are of %s and the checkout is at %s: a rebase or a new commit invalidates every value" % (commit, head))
    if git(checkout, "status", "--porcelain", "--untracked-files=no").strip():
        raise Refusal("the checkout has uncommitted changes, so its source is not %s" % commit)
    if document.get("complete") is not True:
        raise Refusal("complete is %s: the analysis did not read a whole run" % json.dumps(document.get("complete")))
    for name in INTEGRITY_LISTS:
        if not isinstance(document.get(name), list):
            raise Refusal("the analysis has no list `%s`, so nothing says its reports were whole" % name)
        if document[name]:
            raise Refusal("the analysis could not read every report (`%s` lists %d): its sums may be partial" % (name, len(document[name])))


def apply(pins_path, checkout, dry_run, out=sys.stdout):
    try:
        with open(pins_path, encoding="utf-8") as file:
            document = json.load(file)
        if not isinstance(document, dict) or not isinstance(document.get("pins"), list):
            raise Refusal("no `pins` list")
        check_provenance(document, checkout)
        sources = Sources(checkout)
        if not sources.text:
            raise Refusal("no Swift file under %s: not a SafeDI checkout" % " or ".join(SOURCE_DIRECTORIES))
        edits = {}  # path -> [(token, new text, description)]
        left = []
        following = []
        for pin in document["pins"]:
            if not isinstance(pin, dict):
                raise Refusal("a pin that is not an object")
            if isinstance(pin.get("key"), bool) or not isinstance(pin.get("key"), (type(None), str, int)):
                raise Refusal("a pin whose key is %r" % (pin.get("key"),))
            title = "%s `%s`%s" % (pin.get("corpus"), pin.get("constant"), "" if pin.get("key") is None else "[%s]" % pin.get("key"))
            try:
                path, token = place(pin, sources)
            except Follows as error:
                following.append((title, pin, error))
                continue
            except LookupError as error:
                left.append("%s: %s -> %s: %s" % (title, pin.get("pinned"), pin.get("actual"), error))
                continue
            new = spelled(number(pin["actual"]), token.text)
            if any(edit[0].start == token.start for edit in edits.get(path, [])):
                raise Refusal("%s: two pins name one literal" % title)
            edits.setdefault(path, []).append((token, new, "%s: %s -> %s" % (title, token.text, new), pin, title))
        # Writing a constant moves every constant that only names it, so it is written only when the run moved each of
        # those to the same value; and a constant that names another needs nothing once that one is written to its value.
        for path in sorted(edits):
            for edit in list(edits[path]):
                pin = edit[3]
                if pin.get("key") is not None:
                    continue
                moved = {follower[1].get("constant") for follower in following if follower[2].expression == pin["constant"] and number(follower[1].get("actual")) == number(pin["actual"])}
                unmoved = [name for name in sources.followers(pin["constant"]) if name not in moved]
                if unmoved:
                    edits[path].remove(edit)
                    left.append("%s: %s -> %s: `%s` names it, and the run did not move `%s` to that value" % (edit[4], pin.get("pinned"), pin.get("actual"), unmoved[0], unmoved[0]))
        written_values = {(edit[3].get("constant"), number(edit[3].get("actual"))) for edits_of in edits.values() for edit in edits_of if edit[3].get("key") is None}
        for title, pin, error in following:
            if (error.expression, number(pin.get("actual"))) not in written_values:
                left.append("%s: %s -> %s: %s" % (title, pin.get("pinned"), pin.get("actual"), error))
        for path in sorted(path for path in edits if edits[path]):
            if git(checkout, "hash-object", "--", path).strip() != git(checkout, "rev-parse", "HEAD:" + path).strip():
                raise Refusal("%s is not the commit's file" % path)
    except Exception as error:  # Before any write: whatever went wrong, nothing is written.
        print("refused, nothing written: %s" % error, file=sys.stderr)
        return 2
    written = 0
    for path in sorted(edits):
        text = sources.text[path]
        for token, new, description, _, _ in sorted(edits[path], key=lambda edit: -edit[0].start):
            text = text[:token.start] + new + text[token.end:]
        for token, new, description, _, _ in sorted(edits[path], key=lambda edit: edit[0].start):
            print("%s %s" % ("would write" if dry_run else "wrote", description), file=out)
            written += 1
        if not dry_run and edits[path]:
            with open(os.path.join(checkout, path), "w", encoding="utf-8") as file:
                file.write(text)
    for line in left:
        print("left: %s" % line, file=out)
    other = 0
    for name, words in OTHER_WORK:
        if document.get(name):
            other += len(document[name])
            print("not a pin, left to you: %d %s (see the analysis's report.md)" % (len(document[name]), words), file=out)
    moved = bool(document["pins"])
    if moved:
        not_derived = [str(name) for name in document.get("notDerived") or []]
        print("not derived by the analysis, read from the unit suite's failures in the same run: %s" % (", ".join(not_derived) or "the smoke and known-issue hashes, the smoke batches' draw-feature counts and the smoke seeds"), file=out)
        changed = sorted({str(pin.get("corpus")) for pin in document["pins"] if pin.get("corpusLabel") in HASH_LABELS})
        if changed:
            print("not a pin, left to you: the graphs of %s changed; derive its known issues and smoke seeds again, and the pins the line above names" % ", ".join(changed), file=out)
    print("%d pins %s for %s, %d left" % (written, "would be written" if dry_run else "written", document["commit"], len(left)), file=out)
    return 1 if moved or other else 0


# MARK: Self-test

SELF_TEST_SOURCE = '''enum Kind: String {
	case plain
	case renamed = "re-named"
}

struct Tests {
	static let fixtureHash: UInt64 = 0x00AB // 0x00AB and 7 in a comment
	static let acceptedCount = 1_234
	static let inspectedCount = acceptedCount
	static let plainCount = 321
	static let qualifiedCount = Self.plainCount
	static let errorCounts = [4, 11, 0, 26]
	static let featureCounts: [Kind: Int] = [
		.plain: 7,
		.renamed: 7,
	]
	static let retention = Retention(judged: 62, judgedDrawingRetentionShape: 45, judgedThroughHandWrittenBuilder: 40, unpairedExperiments: 0)
	static let oracle = Oracle(
		rootPairCount: 4_668,
		rootPairsSum: GraphFuzzerSeedSetSum(value: 0x083562835D94C2BE),
		skipCounts: [
			.plain: 5,
		],
		skippedCounts: [
			.plain: 5,
		],
		shapeCounts: [
			.plain: 5,
		],
		forwardedPropertiesSampleCount: 9,
		label: "7 \\(names.joined(separator: " ( "))",
	)
	static let built = Kind.allCases.reduce(into: [Kind: Int]()) { $0[$1] = 3 }
	static let guarded = max(1_111, Self.floor)
	static let summed = Self.base + 2_222
	static let negative = -3_333
	static let sums = Sums(rootPairCount: 4_668, judged: 77 + extra, drawn: -78, total: GraphFuzzerSeedSetSum(value: 0x4F) + other)
}
'''


def self_test(root):
    if os.path.exists(root):
        print("%s exists; --self-test writes a new directory" % root, file=sys.stderr)
        return 2
    failures = []
    counter = [0]

    def run(pins, expected_status, expected_changes, name, mutate=None, dirty=False, dry_run=False, says=(), prepare=None, without_sources=False):
        counter[0] += 1
        checkout = os.path.join(root, "%02d" % counter[0])
        directory = os.path.join(checkout, SOURCE_DIRECTORIES[0])
        os.makedirs(directory)
        source_path = os.path.join(directory, "Pins.swift")
        with open(source_path, "w", encoding="utf-8") as file:
            file.write(SELF_TEST_SOURCE)
        with open(os.path.join(checkout, "Other.swift"), "w", encoding="utf-8") as file:
            file.write("// another tracked file\n")
        for arguments in (("init", "-q"), ("add", "-A"), ("-c", "user.name=self-test", "-c", "user.email=self-test@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-q", "-m", "fixture")):
            git(checkout, *arguments)
        if without_sources:
            os.rename(os.path.join(checkout, "Tests"), os.path.join(checkout, "Other"))
            source_path = os.path.join(checkout, "Other", os.path.basename(SOURCE_DIRECTORIES[0]), "Pins.swift")
            git(checkout, "add", "-A")
            git(checkout, "-c", "user.name=self-test", "-c", "user.email=self-test@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-q", "-m", "moved")
        head = git(checkout, "rev-parse", "HEAD").strip()
        document = {"schema": 1, "commit": head, "provenance": {"event": "workflow_dispatch", "headSha": head, "validForHead": True}, "statement": "statement", "pins": pins, "complete": True, "notDerived": ["smokeHash"]}
        document.update({name: [] for name in INTEGRITY_LISTS})
        if mutate:
            mutate(document)
        pins_path = os.path.join(root, "%02d.json" % counter[0])
        with open(pins_path, "w", encoding="utf-8") as file:
            json.dump(document, file)
        if dirty:
            with open(source_path, "a", encoding="utf-8") as file:
                file.write("// edited\n")
        if prepare:
            prepare(checkout, source_path)
        before = open(source_path, encoding="utf-8").read()
        output = io.StringIO()
        saved, sys.stderr = sys.stderr, output
        try:
            status = apply(pins_path, checkout, dry_run, out=output)
        finally:
            sys.stderr = saved
        after = open(source_path, encoding="utf-8").read()
        expected = before
        for old, new in expected_changes:
            if expected.count(old) != 1:
                failures.append("%s: the fixture holds `%s` %d times" % (name, old, expected.count(old)))
            expected = expected.replace(old, new)
        if status != expected_status:
            failures.append("%s: status %d, expected %d: %s" % (name, status, expected_status, output.getvalue().strip()))
        if after != expected:
            failures.append("%s: the source is not the expected one" % name)
        for words in says:
            if words not in output.getvalue():
                failures.append("%s: the output does not say “%s”: %s" % (name, words, output.getvalue().strip()))

    def pin(constant, key, pinned, actual, note="", label="label"):
        return {"corpus": "base", "constant": constant, "corpusLabel": label, "key": key, "pinned": pinned, "actual": actual, "note": note}

    one = [pin("plainCount", None, 321, 5), pin("qualifiedCount", None, 321, 5)]
    one_change = [("plainCount = 321", "plainCount = 5")]
    everything = [
        pin("fixtureHash", None, "0xAB", "0x1CD"),
        pin("acceptedCount", None, 1234, 12345),
        pin("inspectedCount", None, 1234, 12345, "derived from `acceptedCount`"),
        pin("errorCounts", 2, 0, 1000),
        pin("featureCounts", "re-named", 7, 8),
        pin("retention", "drawJudged", 45, 46),
        pin("retention", "unpairedExperiments", 0, 1),
        pin("oracle", "rootPairs", 4668, 999),
        pin("oracle", "rootPairsSum", "0x83562835D94C2BE", "0x1"),
        pin("oracle", "shape.plain", 5, 6),
        pin("oracle", "forwardedPropertiesSamples", 9, 10),
    ]
    changes = [
        ("0x00AB //", "0x01CD //"), ("1_234", "12_345"), ("[4, 11, 0, 26]", "[4, 11, 1_000, 26]"), (".renamed: 7", ".renamed: 8"),
        ("judgedDrawingRetentionShape: 45", "judgedDrawingRetentionShape: 46"), ("unpairedExperiments: 0", "unpairedExperiments: 1"),
        ("\t\trootPairCount: 4_668", "\t\trootPairCount: 999"), ("0x083562835D94C2BE", "0x0000000000000001"),
        ("shapeCounts: [\n\t\t\t.plain: 5", "shapeCounts: [\n\t\t\t.plain: 6"), ("SampleCount: 9", "SampleCount: 10"),
    ]
    written = "10 pins written"
    run(everything, 1, changes, "every kind of key", says=[written, ", 0 left", "not derived by the analysis, read from the unit suite's failures in the same run: smokeHash"])
    run(everything, 1, [], "a dry run writes nothing", dry_run=True, says=["10 pins would be written"])
    run([], 0, [], "a run that moved nothing", says=["0 pins written"])
    run([], 1, [], "a run that moved nothing but lists other work", mutate=lambda document: document.update(stale=[{"seed": 1}]), says=["1 stale known-issue seeds"])
    run(one, 1, one_change, "combine problems nothing accounts for are listed", mutate=lambda document: document.update(unclassified=["problem"]), says=["1 combine problems nothing accounts for", "1 pins written"])
    run([pin("fixtureHash", None, "0xAB", "0x1CD", label="fixtureHash")], 1, [("0x00AB //", "0x01CD //")], "a moved fixture hash names what to derive again", says=["the graphs of base changed"])
    run([pin("fixtureHash", None, "0xAB", "0x1CD", label="corpusPartitionHash")], 1, [("0x00AB //", "0x01CD //")], "a moved partition hash names what to derive again", says=["the graphs of base changed"])
    # Refusals: where the values came from.
    run(one, 2, [], "validForHead false", mutate=lambda document: document["provenance"].update(validForHead=False))
    run(one, 2, [], "validForHead unknown", mutate=lambda document: document["provenance"].update(validForHead="unknown"))
    run(one, 2, [], "validForHead 1", mutate=lambda document: document["provenance"].update(validForHead=1))
    run(one, 2, [], "no validForHead", mutate=lambda document: document["provenance"].pop("validForHead"))
    run(one, 2, [], "another commit", mutate=lambda document: (document.update(commit="0" * 40), document["provenance"].update(headSha="0" * 40)))
    run(one, 2, [], "headSha differs from commit", mutate=lambda document: document["provenance"].update(headSha="0" * 40))
    run(one, 2, [], "another schema", mutate=lambda document: document.update(schema=2))
    run(one, 2, [], "an uncommitted change", dirty=True)

    def edit_another_file(checkout, source_path):
        with open(os.path.join(checkout, "Other.swift"), "a", encoding="utf-8") as file:
            file.write("// edited\n")

    run(one, 2, [], "an uncommitted change to a file it would not write", prepare=edit_another_file, says=["uncommitted changes"])

    def hide_an_edit(checkout, source_path):
        relative = os.path.relpath(source_path, checkout)
        git(checkout, "update-index", "--assume-unchanged", relative)
        with open(source_path, "a", encoding="utf-8") as file:
            file.write("// edited\n")

    run(one, 2, [], "an edit git status does not show", prepare=hide_an_edit, says=["is not the commit's file"])
    run(one, 2, [], "no Swift source", without_sources=True, says=["not a SafeDI checkout"])
    # Refusals: an analysis that is not whole.
    run(one, 2, [], "complete false", mutate=lambda document: document.update(complete=False))
    run(one, 2, [], "no complete", mutate=lambda document: document.pop("complete"))
    for name in INTEGRITY_LISTS:
        run(one, 2, [], "%s lists an entry" % name, mutate=lambda document, name=name: document.update({name: [{"corpus": "base"}]}))
        run(one, 2, [], "no %s" % name, mutate=lambda document, name=name: document.pop(name), says=["has no list"])
    # Refusals: malformed pins, and a report of another source.
    run(one + ["text"], 2, [], "a pin that is not an object", says=["a pin that is not an object"])
    run(one + [pin("errorCounts", True, 11, 5)], 2, [], "a key that is a boolean")
    run(one + [pin("errorCounts", 1.0, 11, 5)], 2, [], "a key that is a fraction")
    run([], 2, [], "pins that are not a list", mutate=lambda document: document.update(pins={}))
    run(one + [pin("errorCounts", 1, 12, 13)], 2, [], "a pinned value the source does not hold refuses every pin")
    run(one + [pin("plainCount", None, 321, 6)], 2, [], "two pins of one literal")
    # Constants that name another.
    run([pin("acceptedCount", None, 1234, 5), pin("inspectedCount", None, 1234, 5, "derived from `acceptedCount`")], 1, [("1_234", "5")], "a constant that names another follows it", says=["1 pins written", ", 0 left"])
    run(one, 1, one_change, "a constant that names another through Self follows it", says=["1 pins written", ", 0 left"])
    run([pin("inspectedCount", None, 1234, 5, "derived from `acceptedCount`")], 1, [], "a constant that names another is left when that one is not written", says=["0 pins written", ", 1 left"])
    run([pin("acceptedCount", None, 1234, 5)], 1, [], "a constant another names is left when that one did not move", says=["`inspectedCount` names it", "0 pins written", ", 1 left"])
    run([pin("acceptedCount", None, 1234, 5), pin("inspectedCount", None, 1234, 6, "derived from `acceptedCount`")], 1, [], "a constant another names is left when that one moved elsewhere", says=["0 pins written", ", 2 left"])
    # Pins with no whole literal of their own.
    run([pin("built", "plain", 3, 4, "built by `reduce`"), pin("featureCounts", "plain", 7, 9)], 1, [(".plain: 7", ".plain: 9")], "a dictionary built by reduce is left", says=["1 pins written", ", 1 left"])
    run([pin("featureCounts", "missing", "(no pin)", 4), pin("(no pin)", "plain", 7, 4), pin("oracle", "plain", 5, 4), pin("errorCounts", 4, "(no pin)", 2), pin("errorCounts", 9, 1, 2), pin("errorCounts", -1, 26, 2), pin("absent", None, 1, 2), pin("oracle", "other.plain", 5, 4)], 1, [], "pins with no literal of their own are left", says=["0 pins written", ", 8 left"])
    run([pin("guarded", None, 1111, 5), pin("summed", None, 2222, 5), pin("negative", None, 3333, 5), pin("negative", None, -3333, 5)], 1, [], "a number inside an expression or after a sign is left", says=["0 pins written", ", 4 left", "not a single literal"])
    run([pin("sums", "judged", 77, 5), pin("sums", "drawn", 78, 5), pin("sums", "total", "0x4F", "0x5")], 1, [], "an argument that is more than a literal is left", says=["0 pins written", ", 3 left"])
    run([pin("oracle", "skip.plain", 5, 4)], 1, [("skipCounts: [\n\t\t\t.plain: 5", "skipCounts: [\n\t\t\t.plain: 4")], "a group picks its dictionary and no other that starts alike", says=["1 pins written", ", 0 left"])
    run(one, 1, one_change, "other work in the analysis", mutate=lambda document: document.update(stale=[{"seed": 1}]), says=["1 stale known-issue seeds"])
    for failure in failures:
        print("self-test: %s" % failure, file=sys.stderr)
    print("self-test: %d cases, %d failures" % (counter[0], len(failures)))
    if failures:
        print("self-test: the cases are kept in %s" % root, file=sys.stderr)
    else:
        shutil.rmtree(root)
    return 1 if failures else 0


def main(arguments):
    if len(arguments) == 2 and arguments[0] == "--self-test":
        return self_test(arguments[1])
    dry_run = "--dry-run" in arguments
    arguments = [argument for argument in arguments if argument != "--dry-run"]
    checkout = "."
    if "--checkout" in arguments:
        index = arguments.index("--checkout")
        if index + 1 >= len(arguments):
            print(__doc__, file=sys.stderr)
            return 2
        checkout = arguments[index + 1]
        del arguments[index:index + 2]
    if len(arguments) != 1 or arguments[0].startswith("-"):
        print(__doc__, file=sys.stderr if arguments != ["--help"] else sys.stdout)
        return 0 if arguments == ["--help"] else 2
    return apply(arguments[0], checkout, dry_run)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
