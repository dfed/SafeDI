#!/usr/bin/env -S python3 -I
"""analyze-graph-fuzzer-pins.py OUT
analyze-graph-fuzzer-pins.py --in-run OUT REPORTS
analyze-graph-fuzzer-pins.py --self-test DIRECTORY

Reads the graph fuzzer's shard reports in OUT/reports/, maps each value the long run pins to its Swift constant in the
commit's own SafeDIToolGraphFuzzerTests.swift, runs the commit's own combine script over them, and writes OUT/report.md
and OUT/pins.json, which `.claude/skills/apply-fuzzer-pins/apply-fuzzer-pins.py` writes into the test sources. It
decides nothing: it lists what moved, and whoever reads it judges whether the change explains each move. Run it as
`python3 -I`. The analysis never touches the network or git.

`--in-run` is how "Check Graph Fuzzer Corpus on Linux" runs it, from the root of the checkout the run built: it fills
OUT from REPORTS (the directory the shard reports were downloaded into) and from the checkout, writes context.json
from the environment (`PINS_EVENT`, `PINS_HEAD_SHA`, `PINS_BASE_REF`, `PINS_BASE_SHA`, `PINS_MERGE_SHA`,
`PINS_VALID_FOR_HEAD` as `true`, `false` or `unknown`, `PINS_RUN_ID`, `PINS_RUN_URL`), and then analyzes OUT.
`--self-test` checks that filling, the statuses of missing inputs, and the analysis itself over a recorded run, in a
new directory it removes afterwards. The recorded run is `fixtures/graph-fuzzer-pins-run-44871895586.tar.xz` beside
this script: everything the analysis read for one Verify run whose corpora moved one pin (its 22 shard reports, its
context.json, and tools/, the combine script and Swift sources of the commit the run built), and what the analysis
wrote for it then (`expected/pins.json`, and report.md's section (a) as `expected/pins-that-differ.md`). The self-test
analyzes it and expects exactly that section and that pins.json, so it checks this script's rules and nothing else: a
pin that moves in the repository's own sources does not touch it. A change that teaches the analysis a new shape of
pin adds a second recorded run that holds it.

Inputs, all inside OUT:
  reports/**/report.txt      the shard reports (untrusted data: only read, never run)
  tools/combine.py           the commit's .github/scripts/combine-graph-fuzzer-reports.py
  tools/*.swift              the commit's Tests/SafeDIToolFuzzerTests/SafeDIToolGraphFuzzerTests.swift and
                             Tests/SafeDIToolTestSupport/GraphFuzzer*.swift
  context.json               {commit, mode, provenance, runs, statement}: what is established about the runs

Outputs, in OUT:
  canonical/<corpus>-<starting seed>/report.txt   each report under a key that names no path or run id, so that the
                             combine script's problems, which embed each report's path, read the same in every OUT
  combine-summary.md, combine.log                 the combine script's summary, and its exit status and output
  report.md, pins.json                            the analysis; byte-identical for the same reports, commit and context

Rules this script states:
  - The canonical key of a report is `<corpus>-<starting seed>` from its `shard` line, else from its `corpus` line and its
    smallest `seed` line (the first batch's first seed, whichever batch wrote first), else the name of the report's
    artifact directory with characters outside [A-Za-z0-9._-] replaced by `_`. A report with no corpus line takes its
    corpus from that directory name (`graph-fuzzer-report-<corpus>-<seed>`) or, failing that, from the other reports of
    its run's directory when they all name one corpus. Two reports with one key: the first in path order is kept, the
    other listed as `duplicateShard`.
  - A `failure` line is `failure <seed> <kind>` or `failure <seed> <kind>: <details>`. It is split at the end of the
    longest `GraphFuzzerFailure.Kind` raw value (read from the commit) that is the whole rest or is followed by ": ". So
    a details text holding ": " stays whole.
  - A `stale` line is `stale <seed> <reason>; <remedy>`. Reasons contain "; " ("X; and Y"), so it is split where the rest
    ends with "; " followed by the longest of its corpus's `staleSeedRemedy` string literals (read from the commit); at
    247598444 every remedy is a literal and none contains "; ". A line no remedy ends is `ambiguousSplit`.
  - A line the rule cannot split goes to integrity as `ambiguousSplit`, and is still reported in its section with its
    whole rest as the kind or reason.
  - Shard values the combine script adds up are summed as it sums them; the accepted seed-set sum and the value oracle's
    `...Sum` keys wrap at 2^64. Values every shard repeats (pins, floors, the hashes the long run checks before its
    batches) are reported once per corpus; shards that disagree are listed as `shardsDisagree`.
  - Totals are compared only for a complete corpus: complete shards cover 0..<seed count exactly once and no shard of it
    crashed. The hashes, which every shard computes over the whole corpus, are compared for any corpus.
  - A reproduction command's SAFEDI_GRAPH_FUZZER_FEATURES is the `features:` argument of the corpus's `Corpus(...)` in
    the commit, its cases' raw values sorted and joined by commas, as `GraphFuzzerFailure.reproductionCommand` spells
    them (none for an empty list). A report names no features, so a corpus whose declaration is missing, or whose
    `features:` is not an array literal of `GraphFuzzerGeneratorFeature` cases, gets `<unknown: …>` in their place,
    never a guess from its name.
  - A draw-count constant that is not a dictionary literal but `E.allCases.filter(\\.p).reduce(into: …)` (or
    `filter { $0.p }`, or no filter) holds every case of `E` that `p` keeps, when `p` is `rawValue.hasPrefix("…")` in
    `E` or an extension of it; without a filter, every case of `E`. Its pins say it is built by `reduce`.

Exit: 0 combine green and nothing to report; 1 anything to report; 69 some corpus has no complete report (report.md is
still written when there are reports); 64 a missing input.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tarfile

MASK = (1 << 64) - 1

KNOWN_WORDS = {
    "shard", "corpus", "corpora", "features", "inspected", "compared", "retention", "gating", "gating-shapes",
    "read-twins", "omitted-values", "spellings", "draws", "errors", "outputs", "value-oracle", "remedies", "partitions",
    "cpu", "builder-surface", "seam-mock-builders", "level-captures", "failure", "stale", "misfiled", "known", "renamed", "multimodule", "problem", "seed", "finished", "completed",
    # Counted against no pin, so nothing is derived from it.
    "clean-subtree-skips",
    "per-type-plan",
    "parameter-facts",
}

NOT_DERIVED = [
    "smokeAndKnownIssueFixtureHash",
    "seamSmokeAndKnownIssueFixtureHash",
    "publicMockSmokeAndKnownIssueFixtureHash",
    "smokeAndKnownIssuePartitionHash",
    "seamCorpusDrawFeatureCounts",
    "publicMockCorpusDrawFeatureCounts",
    "the smoke seeds (smokeSeeds, seamSmokeSeeds, publicMockSmokeSeeds)",
]


# MARK: Swift source reading


def skip_string(source, index):
    """Returns the index just past the string literal starting at `index` (a `"`), skipping escapes and interpolation."""
    if source.startswith('"""', index):
        end = index + 3
        while end < len(source):
            if source[end] == "\\":
                if source.startswith("\\(", end):
                    end = matching(source, end + 1) + 1
                    continue
                end += 2
                continue
            if source.startswith('"""', end):
                return end + 3
            end += 1
        return end
    end = index + 1
    while end < len(source):
        character = source[end]
        if character == "\\":
            if source.startswith("\\(", end):
                end = matching(source, end + 1) + 1
                continue
            end += 2
            continue
        if character == '"':
            return end + 1
        if character == "\n":
            return end
        end += 1
    return end


def skip_comment(source, index):
    if source.startswith("//", index):
        newline = source.find("\n", index)
        return len(source) if newline < 0 else newline
    if source.startswith("/*", index):
        end = source.find("*/", index + 2)
        return len(source) if end < 0 else end + 2
    return index


OPENERS = {"(": ")", "[": "]", "{": "}"}


def matching(source, index):
    """The index of the bracket closing the one at `index`."""
    stack = [OPENERS[source[index]]]
    position = index + 1
    while position < len(source):
        character = source[position]
        if character == '"':
            position = skip_string(source, position)
            continue
        if source.startswith("//", position) or source.startswith("/*", position):
            position = skip_comment(source, position)
            continue
        if character in OPENERS:
            stack.append(OPENERS[character])
        elif character in ")]}":
            if not stack or stack[-1] != character:
                return position
            stack.pop()
            if not stack:
                return position
        position += 1
    return len(source) - 1


def split_top_level(text):
    """Splits `text` at commas outside brackets, strings and comments."""
    parts = []
    start = 0
    position = 0
    while position < len(text):
        character = text[position]
        if character == '"':
            position = skip_string(text, position)
            continue
        if text.startswith("//", position) or text.startswith("/*", position):
            position = skip_comment(text, position)
            continue
        if character in OPENERS:
            position = matching(text, position) + 1
            continue
        if character == ",":
            parts.append(text[start:position])
            start = position + 1
        position += 1
    parts.append(text[start:])
    return [part for part in (strip_comments(part).strip() for part in parts) if part]


def strip_comments(text):
    result = []
    position = 0
    while position < len(text):
        if text[position] == '"':
            end = skip_string(text, position)
            result.append(text[position:end])
            position = end
            continue
        if text.startswith("//", position) or text.startswith("/*", position):
            position = skip_comment(text, position)
            continue
        result.append(text[position])
        position += 1
    return "".join(result)


def top_level_text(text):
    """`text` without its comments and without the contents of its `{…}` blocks (each replaced by a space)."""
    result = []
    position = 0
    while position < len(text):
        character = text[position]
        if character == '"':
            end = skip_string(text, position)
            result.append(text[position:end])
            position = end
            continue
        if text.startswith("//", position) or text.startswith("/*", position):
            position = skip_comment(text, position)
            continue
        if character == "{":
            position = matching(text, position) + 1
            result.append(" ")
            continue
        result.append(character)
        position += 1
    return "".join(result)


# A dictionary built from an enum's cases: `E.allCases.filter(\.p).reduce(into: …)`, `filter { $0.p }`, or no filter.
REDUCED_DICTIONARY = re.compile(r"^(\w+)\.allCases(?:\.filter(?:\(\s*\\\.(\w+)\s*\)|\s*\{\s*\$0\.(\w+)\s*\}))?\.reduce\(\s*into\s*:")


def expression_end(source, index):
    """The end of the expression starting at `index`: the first newline outside brackets and strings."""
    position = index
    while position < len(source):
        character = source[position]
        if character == '"':
            position = skip_string(source, position)
            continue
        if source.startswith("//", position):
            return position
        if source.startswith("/*", position):
            position = skip_comment(source, position)
            continue
        if character in OPENERS:
            position = matching(source, position) + 1
            continue
        if character == "\n":
            return position
        position += 1
    return position


def string_value(literal, constants, depth=0):
    """The value of a Swift string literal whose interpolations name string constants, or None."""
    literal = literal.strip()
    if not (literal.startswith('"') and literal.endswith('"')) or literal.startswith('"""'):
        return None
    body = literal[1:-1]
    result = []
    position = 0
    while position < len(body):
        character = body[position]
        if character == "\\" and position + 1 < len(body):
            following = body[position + 1]
            if following == "(":
                end = matching(body, position + 1)
                name = body[position + 2:end].strip()
                value = constant_string(name, constants, depth + 1)
                if value is None:
                    return None
                result.append(value)
                position = end + 1
                continue
            result.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'", "0": "\0"}.get(following, following))
            position += 2
            continue
        result.append(character)
        position += 1
    return "".join(result)


def constant_string(name, constants, depth=0):
    if depth > 10 or name not in constants:
        return None
    return string_value(constants[name], constants, depth)


class SwiftSources:
    def __init__(self, paths):
        self.text = {}
        for path in sorted(paths):
            with open(path, encoding="utf-8", errors="replace") as file:
                self.text[os.path.basename(path)] = file.read()
        self.tests = next((text for name, text in self.text.items() if name.startswith("SafeDIToolGraphFuzzerTests")), "")
        self.constants = {}  # name -> right-hand side
        for text in self.text.values():
            for match in re.finditer(r"^[ \t]*(?:(?:private|fileprivate|internal|public|nonisolated)\s+)*static let (\w+)(?:\s*:\s*[^=\n]+?)?\s*=\s*", text, re.M):
                end = expression_end(text, match.end())
                self.constants.setdefault(match.group(1), text[match.end():end].strip())
        self.corpus_labels = self._corpus_labels()
        self.corpora = self._corpora()
        self.failure_kinds = self._failure_kinds()

    def _corpus_labels(self):
        match = re.search(r"\bstruct Corpus\s*\{", self.tests)
        if not match:
            return []
        body = self.tests[match.end():matching(self.tests, match.end() - 1)]
        labels = []
        depth = 0
        for line in body.split("\n"):
            stripped = line.strip()
            if depth == 0:
                field = re.match(r"(?:let|var)\s+(\w+)\s*(?::|=)", stripped)
                if field and not re.match(r"var\s+\w+\s*:\s*[^=]*\{\s*$", stripped):
                    labels.append(field.group(1))
            depth += line.count("{") - line.count("}")
        return labels

    def _corpora(self):
        corpora = {}
        for match in re.finditer(r"static let (\w+) = Corpus\(", self.tests):
            open_index = match.end() - 1
            close_index = matching(self.tests, open_index)
            arguments = {}
            order = []
            for part in split_top_level(self.tests[open_index + 1:close_index]):
                labelled = re.match(r"(\w+)\s*:\s*(.*)$", part, re.S)
                if labelled:
                    arguments[labelled.group(1)] = labelled.group(2).strip()
                    order.append(labelled.group(1))
            name_expression = arguments.get("name", "")
            name = string_value(name_expression, self.constants)
            if name is None:
                feature = re.search(r"\.(\w+)\.rawValue$", name_expression)
                name = feature.group(1) if feature else match.group(1)
            remedies = []
            for literal in re.finditer(r'"(?:[^"\\\n]|\\.)*"', arguments.get("staleSeedRemedy", "")):
                value = string_value(literal.group(0), self.constants)
                if value is not None:
                    remedies.append(value)
            corpora[name] = {
                "variable": match.group(1),
                "arguments": arguments,
                "features": self.feature_raw_values(arguments.get("features")),
                "knownIssuesName": string_value(arguments.get("knownIssuesName", '""'), self.constants) or "",
                "remedies": sorted(set(remedies), key=lambda remedy: (-len(remedy), remedy)),
            }
        return corpora

    def enum_declaration_bodies(self, enum_name, extensions=False):
        """The bodies of `enum <enum_name>`'s declaration (and of its extensions when `extensions`), in file order."""
        keyword = "(?:enum|extension)" if extensions else "enum"
        pattern = re.compile(r"^[ \t]*(?:(?:private|fileprivate|internal|public|package|indirect|nonisolated)\s+)*%s\s+%s\b[^{\n]*\{" % (keyword, re.escape(enum_name)), re.M)
        bodies = []
        for text in self.text.values():
            for match in pattern.finditer(text):
                open_index = match.end() - 1
                bodies.append(text[open_index + 1:matching(text, open_index)])
        return bodies

    def enum_cases(self, enum_name):
        """[(case name, raw value)] of `enum <enum_name>`'s cases without associated values, in declaration order (a case
        without an explicit raw value has its name as its raw value), or None when no file declares the enum."""
        bodies = self.enum_declaration_bodies(enum_name)
        if not bodies:
            return None
        cases = []
        for clause in re.finditer(r"\bcase\s+([^\n;]+)", top_level_text(bodies[0])):
            for element in split_top_level(clause.group(1)):
                case = re.fullmatch(r'(\w+)(?:\s*=\s*("(?:[^"\\\n]|\\.)*"))?', element)
                if case is None:
                    continue
                raw = string_value(case.group(2), self.constants) if case.group(2) else case.group(1)
                if raw is not None:
                    cases.append((case.group(1), raw))
        return cases

    def raw_value_prefix(self, enum_name, predicate):
        """The literal of `var <predicate>: Bool { rawValue.hasPrefix("…") }` in `enum <enum_name>` or an extension of it,
        or None."""
        for body in self.enum_declaration_bodies(enum_name, extensions=True):
            found = re.search(r"\bvar\s+%s\s*:\s*Bool\s*\{" % re.escape(predicate), body)
            if not found:
                continue
            inner = strip_comments(body[found.end():matching(body, found.end() - 1)]).strip()
            prefix = re.fullmatch(r'(?:return\s+)?rawValue\.hasPrefix\(\s*("(?:[^"\\\n]|\\.)*")\s*\)', inner)
            if prefix:
                return string_value(prefix.group(1), self.constants)
        return None

    def feature_raw_values(self, expression):
        """The sorted raw values of a `features:` argument, an array literal of `GraphFuzzerGeneratorFeature` cases, or
        None when it is missing or anything else."""
        if expression is None:
            return None
        expression = expression.strip()
        if not expression.startswith("[") or matching(expression, 0) != len(expression) - 1:
            return None
        cases = self.enum_cases("GraphFuzzerGeneratorFeature")
        raw_by_name = dict(cases) if cases is not None else None
        values = set()
        for element in split_top_level(expression[1:-1]):
            case = re.fullmatch(r"(?:GraphFuzzerGeneratorFeature)?\.(\w+)", element)
            if case is None:
                return None
            if raw_by_name is None:
                values.add(case.group(1))
            elif case.group(1) in raw_by_name:
                values.add(raw_by_name[case.group(1)])
            else:
                return None
        return sorted(values)

    def _failure_kinds(self):
        for text in self.text.values():
            match = re.search(r"struct GraphFuzzerFailure\b[^{]*\{", text)
            if not match:
                continue
            body = text[match.end():matching(text, match.end() - 1)]
            kind = re.search(r"enum Kind\s*:\s*String[^{]*\{", body)
            if not kind:
                continue
            kind_body = body[kind.end():matching(body, kind.end() - 1)]
            kinds = []
            for case in re.finditer(r'case\s+\w+\s*=\s*("(?:[^"\\\n]|\\.)*")', kind_body):
                value = string_value(case.group(1), self.constants)
                if value is not None:
                    kinds.append(value)
            return sorted(set(kinds), key=lambda value: (-len(value), value))
        return []

    def string_array(self, expression):
        """The strings of an array expression: a literal, a constant naming one, or a sum of such (`A.b + [c]`)."""
        result = []
        for term in re.split(r"\s\+\s", expression.strip()):
            term = term.strip()
            if term.startswith("["):
                for element in split_top_level(term[1:matching(term, 0)]):
                    value = string_value(element, self.constants)
                    if value is None:
                        value = self.constant_reference_string(element)
                    if value is None:
                        return None
                    result.append(value)
            else:
                name = term.split(".")[-1]
                if name not in self.constants:
                    return None
                values = self.string_array(self.constants[name])
                if values is None:
                    value = self.constant_reference_string(term)
                    if value is None:
                        return None
                    values = [value]
                result.extend(values)
        return result

    def constant_reference_string(self, expression):
        name = expression.strip().split(".")[-1]
        return constant_string(name, self.constants)

    def reduced_dictionary(self, constant):
        """(source, raw values) for a constant built by `reduce` over an enum's filtered cases (`REDUCED_DICTIONARY`):
        the source up to `.reduce`, and the raw values of the cases it keeps; None for any other constant, or when the
        filter is not a `rawValue.hasPrefix` predicate of the enum."""
        expression = self.constants.get(constant, "")
        built = REDUCED_DICTIONARY.match(expression)
        if not built:
            return None
        cases = self.enum_cases(built.group(1))
        if cases is None:
            return None
        predicate = built.group(2) or built.group(3)
        if predicate is None:
            kept = [raw for _, raw in cases]
        else:
            prefix = self.raw_value_prefix(built.group(1), predicate)
            if prefix is None:
                return None
            kept = [raw for _, raw in cases if raw.startswith(prefix)]
        return expression[:expression.index(".reduce")], kept

    def dictionary_keys(self, constant):
        expression = self.constants.get(constant, "")
        if not expression.startswith("["):
            reduced = self.reduced_dictionary(constant)
            return reduced[1] if reduced else None
        keys = []
        for element in split_top_level(expression[1:matching(expression, 0)]):
            key = re.match(r"\.(\w+)\s*:", element)
            if key:
                keys.append(key.group(1))
        return keys

    def pin_source(self, corpus, label):
        """(constant, note, propose) for a Corpus label of a corpus: the Swift constant that holds its pin."""
        record = self.corpora.get(corpus)
        if record is None:
            return "(unknown corpus)", "the commit declares no corpus named %s" % corpus, False
        expression = record["arguments"].get(label)
        variable = record["variable"]
        if expression is None:
            return "%s.%s" % (variable, label), "default of `Corpus.%s`; `Corpus(%s)` passes no `%s:`" % (label, variable, label), True
        if re.fullmatch(r"\w+", expression) and not re.fullmatch(r"\d[\d_]*", expression):
            right = self.constants.get(expression, "")
            if re.fullmatch(r"[A-Za-z_]\w*", right):
                return expression, "derived from `%s`" % right, False
            return expression, "", True
        return "%s.%s" % (variable, label), "literal in `Corpus(%s)`" % variable, True


# MARK: Formatting


def grouped(value):
    if not isinstance(value, int):
        return str(value)
    sign = "-" if value < 0 else ""
    digits = str(abs(value))
    parts = []
    while len(digits) > 3:
        parts.insert(0, digits[-3:])
        digits = digits[:-3]
    parts.insert(0, digits)
    return sign + "_".join(parts)


def hexadecimal(value):
    return "0x%X" % value


def sanitized(name):
    return re.sub(r"[^A-Za-z0-9._-]", "_", name)


def fields_of(text):
    """`k=v,…` as an ordered list of (key, value string)."""
    pairs = []
    for item in filter(None, text.split(",")):
        if "=" not in item:
            raise ValueError(item)
        key, value = item.split("=", 1)
        pairs.append((key, value))
    return pairs


# MARK: Reading reports


class Report:
    def __init__(self, path, relative):
        self.path = path
        self.relative = relative
        self.artifact = os.path.basename(os.path.dirname(path))
        self.run_directory = os.path.dirname(os.path.dirname(relative))
        self.lines = []
        with open(path, encoding="utf-8", errors="replace") as file:
            for raw in file:
                line = raw.rstrip("\n").rstrip("\r")
                if line.strip():
                    self.lines.append(line)
        self.shard_lines = []
        self.corpus_lines = []
        self.seeds = set()
        self.finished = set()
        self.completed = False
        self.problems = []
        self.unparsed = []
        self.parsed = {}  # word -> list of fields
        for line in self.lines:
            word = line.split(" ", 1)[0]
            if word not in KNOWN_WORDS:
                self.unparsed.append(line)
                continue
            fields = line.split(" ")
            ok = True
            try:
                if word == "shard":
                    ok = len(fields) == 6
                    if ok:
                        self.shard_lines.append((fields[5], int(fields[1]), int(fields[2]), int(fields[3]), int(fields[4], 16)))
                elif word == "corpus":
                    ok = len(fields) == 5
                    if ok:
                        self.corpus_lines.append((fields[4], int(fields[1]), int(fields[2]), int(fields[3], 16)))
                elif word == "seed":
                    ok = len(fields) == 2
                    if ok:
                        self.seeds.add(int(fields[1]))
                elif word == "finished":
                    ok = len(fields) == 2
                    if ok:
                        self.finished.add(int(fields[1]))
                elif word == "completed":
                    self.completed = True
                elif word == "problem":
                    self.problems.append(line[len("problem "):])
                else:
                    self.parsed.setdefault(word, []).append(fields)
            except ValueError:
                ok = False
            if not ok:
                self.unparsed.append(line)
        self.corpus = (self.shard_lines or self.corpus_lines or [(None,)])[0][0]
        self.starting_seed = self.shard_lines[0][1] if self.shard_lines else (min(self.seeds) if self.seeds else None)

    @property
    def is_complete(self):
        return len(self.shard_lines) == 1 and self.completed


def find_reports(reports_directory, out):
    reports = []
    for root, directories, files in os.walk(reports_directory):
        directories.sort()
        if "report.txt" in files:
            path = os.path.join(root, "report.txt")
            reports.append(Report(path, os.path.relpath(path, out)))
    reports.sort(key=lambda report: report.relative)
    return reports


def attribute_corpora(reports, corpus_names):
    by_run = {}
    for report in reports:
        if report.corpus:
            by_run.setdefault(report.run_directory, set()).add(report.corpus)
    for report in reports:
        if report.corpus:
            continue
        artifact = re.match(r"graph-fuzzer-report-(.+)-(\d+)$", report.artifact)
        if artifact and artifact.group(1) in corpus_names:
            report.corpus = artifact.group(1)
            if report.starting_seed is None:
                report.starting_seed = int(artifact.group(2))
            report.corpus_from = "artifact name"
            continue
        siblings = by_run.get(report.run_directory, set())
        if len(siblings) == 1:
            report.corpus = next(iter(siblings))
            report.corpus_from = "the other reports of its run"


# MARK: The analysis


def wrap_add(values):
    total = 0
    for value in values:
        total = (total + value) & MASK
    return total


HASH_FIXTURE = re.compile(r"^The generator's graphs for seeds 0\.\.<(\d+) of the (\S+) corpus changed \(fixture hash (0x[0-9A-Fa-f]+), pinned (0x[0-9A-Fa-f]+)\)")
HASH_PARTITION = re.compile(r"^The partition of the graphs for seeds 0\.\.<(\d+) across modules changed \(partition hash (0x[0-9A-Fa-f]+), pinned (0x[0-9A-Fa-f]+)\)")
LIST_PROBLEMS = [
    re.compile(r'^The known issue ".*" lists no seeds or no signatures\.$'),
    re.compile(r'^The seeds of ".*" are not in increasing order\.$'),
    re.compile(r"^Seed \d+ is listed as a known issue more than once\.$"),
    re.compile(r"^Seed \d+ is a known issue outside the corpus, seeds 0\.\.<\d+\.$"),
]
STOPPED = re.compile(r"^The long run stopped after \d+ graphs")
# Prose (the long run's and the combine script's) that repeats a structured mismatch, by category.
TOTALS = [
    ("accepted", re.compile(r"^The tool accepted \d+ of seeds 0\.\.<\d+ of the (\S+) corpus \(sum")),
    ("features", re.compile(r"^The accepted graphs of the (\S+) corpus show these features in other numbers than pinned")),
    ("inspected", re.compile(r"^The value oracle inspected \d+ graphs of the (\S+) corpus, but")),
    ("valueOracle", re.compile(r"^The value oracle (?:compared and skipped, over the (\S+) corpus,|of the (\S+) corpus compared and skipped other pairs)")),
    ("readTwins", re.compile(r"^The oracle compared \d+ graphs of the (\S+) corpus with their read twin")),
    ("retention", re.compile(r"^The retention oracle judged, over the (\S+) corpus,")),
    # The long run says "oracle", the combine script "check".
    ("levelCaptures", re.compile(r"^The level function capture (?:oracle|check) judged, over the (\S+) corpus,")),
    ("levelCapturesFloor", re.compile(r"^The level function capture check judged fewer than \d+ graphs of the (\S+) corpus: ")),
    ("gating", re.compile(r"^The oracles judged fewer than \d+ graphs of the (\S+) corpus that draw")),
    ("omitted", re.compile(r"^The tool rejected \d+ graphs of the (\S+) corpus because a caller holds")),
    ("spellings", re.compile(r"^No accepted graph of the (\S+) corpus draws")),
    ("errors", re.compile(r"^The tool rejected \[[^\]]*\] graphs of the (\S+) corpus with each error it pins")),
    ("draws", re.compile(r"^The accepted graphs of the (\S+) corpus show these draws in other numbers than pinned")),
    ("outputs", re.compile(r"^The generated code of \d+ of the \d+ (?:accepted )?graphs of the (\S+) corpus (?:the tool accepts )?shows (\S+), fewer than the pinned")),
    ("builderSurface", re.compile(r"^The builder surface judged \d+ graphs of the (\S+) corpus as (\S+), below its floor")),
]
COMBINE_PATH_LINE = re.compile(r"^(canonical/\S+/report\.txt): (failure|stale|misfiled|problem) (.*)$")
COMBINE_INCOMPLETE = re.compile(r"^(canonical/\S+/report\.txt) has no complete shard result")
COMBINE_DISAGREE = re.compile(r"^The shards of the (\S+) corpus disagree about ")
COMBINE_NO_REPORT = re.compile(r"^The (\S+) corpus has no report: ")
COMBINE_COVERAGE = re.compile(r"^The shards (?:do not cover the (\S+) corpus|cover 0\.\.<\d+ of the (\S+) corpus)")


def classify_total(text):
    for category, pattern in TOTALS:
        match = pattern.match(text)
        if match:
            corpus = next(group for group in match.groups() if group)
            extra = match.group(2) if category in ("outputs", "builderSurface") else None
            return category, corpus, extra
    return None


SWIFT_SOURCES = ("Tests/SafeDIToolFuzzerTests/SafeDIToolGraphFuzzerTests.swift",)
SWIFT_SOURCE_DIRECTORY = "Tests/SafeDIToolTestSupport"
SWIFT_SOURCE_PREFIX = "GraphFuzzer"
COMBINE_SCRIPT = ".github/scripts/combine-graph-fuzzer-reports.py"
RECORDED_RUN = "fixtures/graph-fuzzer-pins-run-44871895586.tar.xz"


def context_of(environment):
    """What a run knows of itself, as context.json states it, or a sentence saying what is missing."""
    event = environment.get("PINS_EVENT") or ""
    head = environment.get("PINS_HEAD_SHA") or ""
    if not event or not re.fullmatch(r"[0-9a-f]{40}", head):
        return None, "PINS_EVENT and a full PINS_HEAD_SHA are required"
    base_ref = environment.get("PINS_BASE_REF") or None
    base = environment.get("PINS_BASE_SHA") or None
    provenance = {"event": event, "headSha": head, "baseRef": base_ref, "baseSha": base}
    if event == "pull_request":
        # A pull request's run builds the merge of the head into its base, so its values are the head's only when
        # that base was an ancestor of the head. Anything but a stated `true` or `false` is unknown.
        valid = {"true": True, "false": False}.get(environment.get("PINS_VALID_FOR_HEAD") or "", "unknown")
        merge = environment.get("PINS_MERGE_SHA") or None
        provenance["mergeSha"] = merge
        statement = "values are for the merge of `%s` into `%s` at `%s`; they hold for `%s` only if that base was an ancestor of it (validForHead: %s)" % (head, base_ref or "an unknown base ref", base or "an unknown base", head, json.dumps(valid))
        if valid is not True:
            statement += ". Until validForHead is true, these values are for judging moves only and must not be committed"
    else:
        valid = True
        statement = "valid only for `%s`; a rebase invalidates every value" % head
    provenance["validForHead"] = valid
    runs = []
    if (environment.get("PINS_RUN_ID") or "").isdigit():
        runs.append({"corpus": "all", "id": int(environment["PINS_RUN_ID"]), "url": environment.get("PINS_RUN_URL") or None, "conclusion": "in progress", "wallSeconds": None})
    return {"commit": head, "mode": "in-run", "provenance": provenance, "runs": runs, "statement": statement}, None


def fill(out, reports, checkout, environment):
    """Fills OUT for a run's own analysis. Returns a sentence when something it needs is missing."""
    context, problem = context_of(environment)
    if problem:
        return problem
    swift_paths = [os.path.join(checkout, path) for path in SWIFT_SOURCES]
    directory = os.path.join(checkout, SWIFT_SOURCE_DIRECTORY)
    if os.path.isdir(directory):
        swift_paths += [os.path.join(directory, name) for name in sorted(os.listdir(directory)) if name.startswith(SWIFT_SOURCE_PREFIX) and name.endswith(".swift")]
    combine = os.path.join(checkout, COMBINE_SCRIPT)
    missing = [path for path in swift_paths[:1] + [combine] if not os.path.isfile(path)]
    if missing:
        return "the checkout lacks %s" % ", ".join(missing)
    if not os.path.isdir(reports):
        return "no directory of reports at %s" % reports
    if os.path.exists(out):
        return "%s exists; --in-run writes a new directory" % out
    os.makedirs(os.path.join(out, "tools"))
    shutil.copytree(reports, os.path.join(out, "reports", str(context["runs"][0]["id"]) if context["runs"] else "run"))
    shutil.copyfile(combine, os.path.join(out, "tools", "combine.py"))
    for path in swift_paths:
        shutil.copyfile(path, os.path.join(out, "tools", os.path.basename(path)))
    with open(os.path.join(out, "context.json"), "w") as file:
        json.dump(context, file, indent=2)
    return None


def self_test(root):
    if os.path.exists(root):
        sys.stderr.write("%s exists; --self-test writes a new directory\n" % root)
        return 2
    failures = []

    def expect(name, actual, expected):
        if actual != expected:
            failures.append("%s: %r, expected %r" % (name, actual, expected))

    head, base, merge = "a" * 40, "b" * 40, "c" * 40
    context, problem = context_of({"PINS_EVENT": "workflow_dispatch", "PINS_HEAD_SHA": head, "PINS_RUN_ID": "12", "PINS_RUN_URL": "url"})
    expect("a dispatch is valid for its head", (problem, context["provenance"]["validForHead"], context["commit"], context["runs"][0]["id"]), (None, True, head, 12))
    expect("a dispatch has no merge", "mergeSha" in context["provenance"], False)
    pull = {"PINS_EVENT": "pull_request", "PINS_HEAD_SHA": head, "PINS_BASE_REF": "main", "PINS_BASE_SHA": base, "PINS_MERGE_SHA": merge}
    for stated, expected in (("true", True), ("false", False), ("unknown", "unknown"), ("", "unknown"), ("yes", "unknown")):
        context, problem = context_of(dict(pull, PINS_VALID_FOR_HEAD=stated))
        expect("a pull request stated %r" % stated, (problem, context["provenance"]["validForHead"], context["provenance"]["mergeSha"]), (None, expected, merge))
        expect("a pull request stated %r says whether to commit" % stated, "must not be committed" in context["statement"], expected is not True)
    expect("no event", context_of({"PINS_HEAD_SHA": head})[0], None)
    expect("a short commit", context_of({"PINS_EVENT": "push", "PINS_HEAD_SHA": head[:9]})[0], None)

    checkout = os.path.join(root, "checkout")
    for path, text in ((SWIFT_SOURCES[0], "// tests\n"), (os.path.join(SWIFT_SOURCE_DIRECTORY, "GraphFuzzerOne.swift"), "// one\n"), (os.path.join(SWIFT_SOURCE_DIRECTORY, "Other.swift"), "// other\n"), (COMBINE_SCRIPT, "import sys\n")):
        os.makedirs(os.path.dirname(os.path.join(checkout, path)), exist_ok=True)
        with open(os.path.join(checkout, path), "w") as file:
            file.write(text)
    reports = os.path.join(root, "reports")
    os.makedirs(os.path.join(reports, "graph-fuzzer-report-base-0"))
    with open(os.path.join(reports, "graph-fuzzer-report-base-0", "report.txt"), "w") as file:
        file.write("seed 0\n")
    with open(os.path.join(root, "words.txt"), "w") as file:
        file.write("seed 0\nclean-subtree-skips 5 base\nper-type-plan cyclic-roots=1 twin-roots=0 bodies=2\nseed zero\nunheard-of 1 base\n")
    expect("the lines a report leaves unparsed", Report(os.path.join(root, "words.txt"), "run/artifact/words.txt").unparsed, ["seed zero", "unheard-of 1 base"])
    environment = {"PINS_EVENT": "push", "PINS_HEAD_SHA": head, "PINS_RUN_ID": "12"}
    out = os.path.join(root, "out")
    expect("filling", fill(out, reports, checkout, environment), None)
    expect("the files it fills", sorted(os.path.relpath(os.path.join(directory, name), out) for directory, _, names in os.walk(out) for name in names), ["context.json", "reports/12/graph-fuzzer-report-base-0/report.txt", "tools/GraphFuzzerOne.swift", "tools/SafeDIToolGraphFuzzerTests.swift", "tools/combine.py"])
    expect("filling twice", fill(out, reports, checkout, environment), "%s exists; --in-run writes a new directory" % out)
    expect("no reports", fill(os.path.join(root, "out-2"), os.path.join(root, "none"), checkout, environment), "no directory of reports at %s" % os.path.join(root, "none"))
    expect("no checkout", (fill(os.path.join(root, "out-3"), reports, root, environment) or "").startswith("the checkout lacks "), True)
    expect("no context", fill(os.path.join(root, "out-4"), reports, checkout, {}), "PINS_EVENT and a full PINS_HEAD_SHA are required")
    expect("nothing is written when filling is refused", [name for name in os.listdir(root) if name.startswith("out-")], [])
    empty = os.path.join(root, "empty")
    os.makedirs(empty)
    saved, sys.stderr = sys.stderr, open(os.devnull, "w")
    try:
        expect("an OUT with no context", analyze(empty), 64)
        with open(os.path.join(empty, "context.json"), "w") as file:
            json.dump({}, file)
        expect("an OUT with no tools", analyze(empty), 64)
    finally:
        sys.stderr.close()
        sys.stderr = saved
    # The analysis itself, over a recorded run: its reports, its context, and its commit's combine script and sources.
    analyzed = os.path.join(root, "analyzed")
    recorded = os.path.join(root, "recorded")
    with tarfile.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), RECORDED_RUN)) as archive:
        for member in archive.getmembers():
            parts = member.name.split("/")
            if not member.isfile() or member.name.startswith("/") or ".." in parts:
                failures.append("the recorded run holds %s, which is not a plain file inside it" % member.name)
                continue
            directory = recorded if parts[0] == "expected" else analyzed
            os.makedirs(os.path.join(directory, *parts[:-1]), exist_ok=True)
            with open(os.path.join(directory, *parts), "wb") as file:
                file.write(archive.extractfile(member).read())
    expect("the recorded run's status", analyze(analyzed), 1)
    with open(os.path.join(analyzed, "report.md"), encoding="utf-8") as file:
        report = file.read()
    with open(os.path.join(recorded, "expected", "pins-that-differ.md"), encoding="utf-8") as file:
        expected_section = file.read()
    start, end = report.find("## (a) "), report.find("## (b) ")
    expect("the recorded run's pins that differ", report[start:end] if 0 <= start < end else report[:200], expected_section)
    with open(os.path.join(analyzed, "pins.json"), encoding="utf-8") as file:
        actual_document = json.load(file)
    with open(os.path.join(recorded, "expected", "pins.json"), encoding="utf-8") as file:
        expected_document = json.load(file)
    for key in sorted(set(actual_document) | set(expected_document)):
        if actual_document.get(key) != expected_document.get(key):
            failures.append("the recorded run's pins.json differs at `%s`: %s, expected %s" % (key, json.dumps(actual_document.get(key))[:300], json.dumps(expected_document.get(key))[:300]))
    for failure in failures:
        sys.stderr.write("self-test: %s\n" % failure)
    print("self-test: %d failures" % len(failures))
    if failures:
        sys.stderr.write("self-test: the cases are kept in %s\n" % root)
    else:
        shutil.rmtree(root)
    return 1 if failures else 0


def main():
    arguments = sys.argv[1:]
    if len(arguments) == 2 and arguments[0] == "--self-test":
        return self_test(arguments[1])
    elif len(arguments) == 3 and arguments[0] == "--in-run":
        problem = fill(arguments[1], arguments[2], ".", os.environ)
        if problem:
            sys.stderr.write("analyze-graph-fuzzer-pins: %s\n" % problem)
            return 64
        else:
            return analyze(arguments[1])
    elif len(arguments) == 1 and not arguments[0].startswith("-"):
        return analyze(arguments[0])
    else:
        sys.stderr.write(__doc__)
        return 64


def analyze(out):
    out = os.path.abspath(out)
    try:
        with open(os.path.join(out, "context.json")) as file:
            context = json.load(file)
    except (OSError, ValueError) as error:
        sys.stderr.write("analyze-graph-fuzzer-pins: no readable context.json in %s (%s)\n" % (out, error))
        return 64
    tools = os.path.join(out, "tools")
    combine = os.path.join(tools, "combine.py")
    swift_paths = [os.path.join(tools, name) for name in os.listdir(tools) if name.endswith(".swift")] if os.path.isdir(tools) else []
    if not os.path.isfile(combine) or not swift_paths:
        sys.stderr.write("analyze-graph-fuzzer-pins: %s lacks combine.py or the commit's Swift sources\n" % tools)
        return 64
    sources = SwiftSources(swift_paths)
    with open(combine) as file:
        combine_source = file.read()
    floor_match = re.search(r"^BUILDER_SURFACE_FLOOR\s*=\s*(\d+)", combine_source, re.M)
    builder_surface_floor = int(floor_match.group(1)) if floor_match else None
    # The level function capture check’s floor: the combine script floors the named keys of one corpus's totals.
    level_captures_floor_match = re.search(r"^LEVEL_CAPTURES_FLOOR\s*=\s*(\d+)", combine_source, re.M)
    level_captures_keys_match = re.search(r"^LEVEL_CAPTURES_FLOORED_KEYS\s*=\s*\(([^)]*)\)", combine_source, re.M)
    level_captures_corpus_match = re.search(r'^SEAM_CORPUS\s*=\s*"([^"]+)"', combine_source, re.M)
    if level_captures_floor_match and level_captures_keys_match and level_captures_corpus_match:
        level_captures_floor = int(level_captures_floor_match.group(1))
        level_captures_floored_keys = re.findall(r'"([^"]*)"', level_captures_keys_match.group(1))
        level_captures_floored_corpus = level_captures_corpus_match.group(1)
    else:
        level_captures_floor, level_captures_floored_keys, level_captures_floored_corpus = None, [], None
    builder_surface = []  # per corpus: {corpus, counts: [[kind, count]], floored: [kinds], floor}
    corpus_names = list(sources.corpora)

    reports = find_reports(os.path.join(out, "reports"), out)
    attribute_corpora(reports, set(corpus_names))

    integrity = {"unclassified": [], "unparsed": [], "ambiguousSplit": [], "shardsDisagree": [], "duplicateShard": [], "rejectedKnownIssueLists": [], "incompleteCorpora": []}

    # Step 1: the canonical layout.
    canonical_root = os.path.join(out, "canonical")
    shutil.rmtree(canonical_root, ignore_errors=True)
    os.makedirs(canonical_root)
    kept = []
    by_key = {}
    for report in reports:
        if report.corpus and report.starting_seed is not None:
            key = "%s-%d" % (report.corpus, report.starting_seed)
        else:
            key = sanitized(report.artifact)
        report.key = key
        if key in by_key:
            integrity["duplicateShard"].append({"key": key, "kept": by_key[key].relative, "dropped": report.relative})
            continue
        by_key[key] = report
        report.canonical = "canonical/%s/report.txt" % key
        os.makedirs(os.path.join(out, "canonical", key))
        shutil.copyfile(report.path, os.path.join(out, report.canonical))
        kept.append(report)
    kept.sort(key=lambda report: report.canonical)
    by_canonical = {report.canonical: report for report in kept}

    # Step 2: the combine script's verdict.
    environment = {key: value for key, value in os.environ.items() if key != "GITHUB_STEP_SUMMARY"}
    arguments = ["python3", "-I", "tools/combine.py", "combine-summary.md"] + [report.canonical for report in kept]
    try:
        completed = subprocess.run(arguments, cwd=out, env=environment, capture_output=True, text=True, timeout=600)
        combine_exit = completed.returncode
        combine_output = completed.stdout + completed.stderr
    except (OSError, subprocess.TimeoutExpired) as error:
        combine_exit = 70
        combine_output = str(error)
    with open(os.path.join(out, "combine.log"), "w") as file:
        file.write("$ %s\n" % " ".join(arguments))
        file.write(combine_output)
        file.write("exit %d\n" % combine_exit)
    combine_problems = []
    try:
        with open(os.path.join(out, "combine-summary.md")) as file:
            for line in file:
                if line.startswith("- **Problem:** "):
                    combine_problems.append(line[len("- **Problem:** "):].rstrip("\n"))
    except OSError:
        pass

    # Order of corpora: the `corpora` line.
    corpora_values = {}
    for report in kept:
        for fields in report.parsed.get("corpora", []):
            corpora_values.setdefault(" ".join(fields[1:]), []).append(report.canonical)
    corpora_order = []
    for value in sorted(corpora_values):
        for name in value.split(" "):
            if name and name not in corpora_order:
                corpora_order.append(name)
    if len(corpora_values) > 1:
        integrity["shardsDisagree"].append({"corpus": "(all)", "value": "corpora", "values": [{"report": path, "value": value} for value in sorted(corpora_values) for path in corpora_values[value]]})
    for report in kept:
        if report.corpus and report.corpus not in corpora_order:
            corpora_order.append(report.corpus)

    def corpus_rank(corpus):
        return (corpora_order.index(corpus) if corpus in corpora_order else len(corpora_order), corpus or "")

    # Per-corpus groups of reports.
    groups = {}
    for report in kept:
        groups.setdefault(report.corpus, []).append(report)

    def repeated(corpus, name, entries):
        """Values every shard of a corpus repeats: one value, or a `shardsDisagree` entry. entries: [(report, value)]."""
        values = {}
        for report, value in entries:
            values.setdefault(value, []).append(report.canonical)
        if len(values) > 1:
            def shown(value):
                if isinstance(value, tuple) and len(value) == 2 and all(isinstance(part, str) for part in value):
                    return "%s (pinned %s)" % value
                return " ".join(str(part) for part in value) if isinstance(value, tuple) else str(value)
            integrity["shardsDisagree"].append({"corpus": corpus, "value": name, "values": [{"report": path, "value": shown(value)} for value in sorted(values, key=str) for path in sorted(values[value])]})
            return None
        return next(iter(values)) if values else None

    # Step 3 and 4: findings by seed.
    failures = {}  # corpus -> kind -> seed -> [details]
    stale = {}  # corpus -> reason -> {seeds, remedy}
    misfiled = []
    known = {}  # corpus -> reason -> count
    renamed = {}  # corpus -> [(seed, text)]
    multimodule = {}
    crashed = []
    details_by_seed = {}  # (corpus, seed) -> [details]
    for report in kept:
        corpus = report.corpus or "(unknown corpus)"
        for line in report.unparsed:
            integrity["unparsed"].append({"report": report.canonical, "line": line})
        for word, destination in (("renamed", renamed), ("multimodule", multimodule)):
            for fields in report.parsed.get(word, []):
                try:
                    seed = int(fields[1])
                except (IndexError, ValueError):
                    integrity["unparsed"].append({"report": report.canonical, "line": " ".join(fields)})
                    continue
                text = " ".join(fields[2:])
                destination.setdefault(corpus, []).append((seed, text))
                details_by_seed.setdefault((corpus, seed), []).append("%s: %s" % (word, text))
        for fields in report.parsed.get("known", []):
            reason = " ".join(fields[2:])
            known.setdefault(corpus, {}).setdefault(reason, 0)
            known[corpus][reason] += 1
        for fields in report.parsed.get("failure", []):
            line = " ".join(fields)
            try:
                seed = int(fields[1])
            except (IndexError, ValueError):
                integrity["unparsed"].append({"report": report.canonical, "line": line})
                continue
            rest = " ".join(fields[2:])
            kind, detail = None, None
            for candidate in sources.failure_kinds:
                if rest == candidate:
                    kind = candidate
                    break
                if rest.startswith(candidate + ": "):
                    kind, detail = candidate, rest[len(candidate) + 2:]
                    break
            if kind is None:
                integrity["ambiguousSplit"].append({"report": report.canonical, "line": line})
                kind = rest
            entry = failures.setdefault(corpus, {}).setdefault(kind, {}).setdefault(seed, [])
            if detail is not None:
                entry.append(detail)
        remedies = (sources.corpora.get(corpus) or {}).get("remedies", [])
        for fields in report.parsed.get("stale", []):
            line = " ".join(fields)
            try:
                seed = int(fields[1])
            except (IndexError, ValueError):
                integrity["unparsed"].append({"report": report.canonical, "line": line})
                continue
            rest = " ".join(fields[2:])
            reason, remedy = None, None
            for candidate in remedies:
                if rest.endswith("; " + candidate) and len(rest) > len(candidate) + 2:
                    reason, remedy = rest[:-(len(candidate) + 2)], candidate
                    break
            if reason is None:
                integrity["ambiguousSplit"].append({"report": report.canonical, "line": line})
                reason, remedy = rest, None
            group = stale.setdefault(corpus, {}).setdefault(reason, {"seeds": set(), "remedy": remedy})
            group["seeds"].add(seed)
        for fields in report.parsed.get("misfiled", []):
            try:
                seed = int(fields[1])
            except (IndexError, ValueError):
                integrity["unparsed"].append({"report": report.canonical, "line": " ".join(fields)})
                continue
            misfiled.append({"corpus": corpus, "seed": seed, "text": " ".join(fields[2:])})
        if not report.is_complete and not (not report.shard_lines and report.problems and all(any(pattern.match(problem) for pattern in LIST_PROBLEMS) for problem in report.problems)):
            suspects = sorted(report.seeds - report.finished)
            crashed.append({"corpus": corpus, "shard": report.key, "report": report.canonical, "suspectSeeds": suspects, "problems": [problem for problem in report.problems if STOPPED.match(problem)]})
        if not report.shard_lines and report.problems and all(any(pattern.match(problem) for pattern in LIST_PROBLEMS) for problem in report.problems):
            integrity["rejectedKnownIssueLists"].append({"corpus": corpus, "report": report.canonical, "problems": report.problems})

    # Completeness, per corpus.
    corpus_state = {}
    for corpus in sorted(groups, key=corpus_rank):
        reports_of = groups[corpus]
        name = corpus or "(unknown corpus)"
        seed_count = repeated(name, "corpus seed count", [(report, line[1]) for report in reports_of for line in report.corpus_lines])
        complete_reports = [report for report in reports_of if report.is_complete]
        ranges = sorted((report.shard_lines[0][1], report.shard_lines[0][1] + report.shard_lines[0][2]) for report in complete_reports)
        position = 0
        covered = True
        for start, end in ranges:
            if start != position:
                covered = False
                break
            position = end
        if seed_count is None or position != seed_count:
            covered = False
        is_complete = bool(corpus) and covered and all(report.is_complete for report in reports_of)
        corpus_state[name] = {"complete": is_complete, "seedCount": seed_count, "ranges": ranges}
        if not is_complete:
            reasons = []
            if not corpus:
                reasons.append("reports that name no corpus")
            incomplete = [report.canonical for report in reports_of if not report.is_complete]
            if incomplete:
                reasons.append("no complete shard result in %s" % ", ".join(incomplete))
            if not covered:
                if seed_count is None:
                    reasons.append("no complete report states the corpus\u2019s seed count")
                else:
                    reasons.append("complete shards cover %s of 0..<%d" % (", ".join("%d..<%d" % pair for pair in ranges) or "nothing", seed_count))
            integrity["incompleteCorpora"].append({"corpus": name, "reason": "; ".join(reasons)})
    for corpus in corpora_order:
        if corpus not in corpus_state:
            corpus_state[corpus] = {"complete": False, "seedCount": None, "ranges": []}
            integrity["incompleteCorpora"].append({"corpus": corpus, "reason": "no report names it"})

    # Step 5 and 6, and section (a): pins that differ.
    pins = []
    floors = []

    def add_pin(corpus, label, key, pinned, actual, kind):
        """kind: count, hex. key: None, a key, or an index."""
        if label == "corpusPartitionHash":
            constant, note, _ = "corpusPartitionHash", "a static, not a Corpus label", True
        else:
            constant, note, _ = sources.pin_source(corpus, label)
        pins.append({"corpus": corpus, "constant": constant, "corpusLabel": label, "key": key, "pinned": pinned, "actual": actual, "note": note, "kind": kind})

    label_order = {label: index for index, label in enumerate(sources.corpus_labels)}
    label_order["corpusPartitionHash"] = label_order.get("fixtureHash", -1) + 0.5

    hash_values = {}  # corpus -> (actual, pinned) from prose
    for corpus in sorted(groups, key=corpus_rank):
        reports_of = groups[corpus]
        name = corpus or "(unknown corpus)"
        state = corpus_state[name]
        # The hashes, from every shard's problem prose (each shard checks them before its batches).
        # A shard that started a seed, or finished, ran the check; a list the long run rejected stops before it.
        fixture_entries = []
        partition_entries = []
        for report in reports_of:
            if not (report.shard_lines or report.seeds):
                continue
            fixture = [match for match in (HASH_FIXTURE.match(problem) for problem in report.problems) if match]
            partition = [match for match in (HASH_PARTITION.match(problem) for problem in report.problems) if match]
            fixture_entries.append((report, ("0x" + fixture[0].group(3)[2:].upper(), "0x" + fixture[0].group(4)[2:].upper()) if fixture else "unchanged"))
            if name == "base" or partition:
                partition_entries.append((report, ("0x" + partition[0].group(2)[2:].upper(), "0x" + partition[0].group(3)[2:].upper()) if partition else "unchanged"))
        fixture_value = repeated(name, "fixtureHash", fixture_entries)
        if isinstance(fixture_value, tuple):
            add_pin(name, "fixtureHash", None, fixture_value[1], fixture_value[0], "hex")
            hash_values[name] = fixture_value
        partition_value = repeated(name, "corpusPartitionHash", partition_entries)
        if isinstance(partition_value, tuple):
            add_pin(name, "corpusPartitionHash", None, partition_value[1], partition_value[0], "hex")

        complete = [report for report in reports_of if report.is_complete]

        def lines(word):
            return [(report, fields) for report in complete for fields in report.parsed.get(word, [])]

        # Repeated pins, checked for every corpus whose shards report them.
        corpus_pin = repeated(name, "corpus pins", [(report, (line[1], line[2], line[3])) for report in complete for line in report.corpus_lines])
        if not state["complete"]:
            continue
        accepted_count = sum(report.shard_lines[0][3] for report in complete)
        accepted_sum = wrap_add(report.shard_lines[0][4] for report in complete)
        if corpus_pin is not None:
            if accepted_count != corpus_pin[1]:
                add_pin(name, "acceptedSeedCount", None, corpus_pin[1], accepted_count, "count")
            if accepted_sum != corpus_pin[2]:
                add_pin(name, "acceptedSeedsSum", None, hexadecimal(corpus_pin[2]), hexadecimal(accepted_sum), "hex")

        def keyed_totals(word, count_index, pin_index, label, wrap_sum_keys=False):
            entries = lines(word)
            if not entries:
                return {}
            pins_field = repeated(name, "%s pins" % word, [(report, fields[pin_index] if len(fields) > pin_index else "") for report, fields in entries])
            totals = {}
            order = []
            for report, fields in entries:
                try:
                    for key, value in fields_of(fields[count_index] if len(fields) > count_index else ""):
                        number = int(value, 0)
                        if key not in totals:
                            order.append(key)
                            totals[key] = 0
                        totals[key] = (totals[key] + number) & MASK if (wrap_sum_keys and key.endswith("Sum")) else totals[key] + number
                except ValueError:
                    integrity["unparsed"].append({"report": report.canonical, "line": " ".join(fields)})
            return {"pins": pins_field, "totals": totals, "order": order}

        features = keyed_totals("features", 2, 3, "acceptedFeatureCounts")
        if features and features["pins"]:
            pinned = dict(fields_of(features["pins"]))
            for key in features["order"] + [key for key in pinned if key not in features["totals"]]:
                actual = features["totals"].get(key, 0)
                if key not in pinned:
                    add_pin(name, "acceptedFeatureCounts", key, "(no pin)", actual, "count")
                elif actual != int(pinned[key]):
                    add_pin(name, "acceptedFeatureCounts", key, int(pinned[key]), actual, "count")

        # The builder surface (#714): informational counts, and the floored kinds, which the commit's combine script
        # checks against BUILDER_SURFACE_FLOOR when it has one; a kind below it goes to (d).
        surface = lines("builder-surface")
        if surface:
            floored = repeated(name, "builder-surface floored kinds", [(report, fields[3] if len(fields) > 3 else "") for report, fields in surface])
            totals, order = {}, []
            for report, fields in surface:
                try:
                    for key, value in fields_of(fields[2] if len(fields) > 2 else ""):
                        if key not in totals:
                            order.append(key)
                            totals[key] = 0
                        totals[key] += int(value)
                except ValueError:
                    integrity["unparsed"].append({"report": report.canonical, "line": " ".join(fields)})
            floored_kinds = [kind for kind in (floored or "").split(",") if kind]
            builder_surface.append({"corpus": name, "counts": [[key, totals[key]] for key in order], "floored": floored_kinds, "floor": builder_surface_floor})
            if builder_surface_floor is not None:
                for kind in floored_kinds:
                    if totals.get(kind, 0) < builder_surface_floor:
                        floors.append({"corpus": name, "kind": "builderSurface", "name": kind, "actual": totals.get(kind, 0), "floor": builder_surface_floor, "constant": "BUILDER_SURFACE_FLOOR (combine script) / builderSurfaceFloor"})

        for word, label in (("inspected", "valueOracleInspectedGraphCount"), ("read-twins", "readTwinGraphCount"), ("omitted-values", "omittedValueGraphCount")):
            entries = [(report, fields) for report, fields in lines(word) if len(fields) == 4]
            if not entries:
                continue
            pin = repeated(name, "%s pin" % word, [(report, int(fields[2])) for report, fields in entries])
            actual = sum(int(fields[1]) for _, fields in entries)
            if pin is not None and actual != pin:
                add_pin(name, label, None, pin, actual, "count")

        retention = keyed_totals("retention", 2, 3, "retentionCounts")
        if retention and retention["pins"] is not None:
            for key, value in fields_of(retention["pins"]):
                actual = retention["totals"].get(key, 0)
                if actual != int(value, 0):
                    add_pin(name, "retentionCounts", key, int(value, 0), actual, "count")

        level_captures = keyed_totals("level-captures", 2, 3, "levelFunctionCaptureCounts")
        if level_captures and level_captures["pins"] is not None:
            for key, value in fields_of(level_captures["pins"]):
                actual = level_captures["totals"].get(key, 0)
                if actual != int(value, 0):
                    add_pin(name, "levelFunctionCaptureCounts", key, int(value, 0), actual, "count")
        # The combine script floors these keys of its corpus whether or not a report wrote the line.
        if level_captures_floor is not None and name == level_captures_floored_corpus:
            for key in level_captures_floored_keys:
                actual = (level_captures or {}).get("totals", {}).get(key, 0)
                if actual < level_captures_floor:
                    floors.append({"corpus": name, "kind": "levelCaptures", "name": key, "actual": actual, "floor": level_captures_floor, "constant": "LEVEL_CAPTURES_FLOOR (combine script) / gatingDrawJudgedGraphFloor"})

        draws = keyed_totals("draws", 2, 3, "acceptedDrawFeatureCounts")
        if draws and draws["pins"] is not None:
            pinned = dict(fields_of(draws["pins"]))
            seam_keys = sources.dictionary_keys(sources.pin_source(name, "acceptedDrawFeatureCounts")[0]) or []
            public_keys = sources.dictionary_keys(sources.pin_source(name, "acceptedPublicMockDrawFeatureCounts")[0]) or []
            for key in draws["order"] + [key for key in pinned if key not in draws["totals"]]:
                actual = draws["totals"].get(key, 0)
                label = "acceptedPublicMockDrawFeatureCounts" if key in public_keys and key not in seam_keys else "acceptedDrawFeatureCounts"
                if key not in pinned:
                    # The corpus's own draws dictionary, which a pin for the key would join.
                    has_public = "acceptedPublicMockDrawFeatureCounts" in (sources.corpora.get(name) or {}).get("arguments", {})
                    label = "acceptedPublicMockDrawFeatureCounts" if has_public else "acceptedDrawFeatureCounts"
                    constant = sources.pin_source(name, label)[0]
                    pins.append({"corpus": name, "constant": constant, "corpusLabel": label, "key": key, "pinned": "(no pin)", "actual": actual, "note": "no pin: no pinned dictionary literal holds `.%s`" % key, "kind": "count"})
                elif actual != int(pinned[key]):
                    if key not in seam_keys and key not in public_keys:
                        pins.append({"corpus": name, "constant": "(no pin)", "corpusLabel": label, "key": key, "pinned": int(pinned[key]), "actual": actual, "note": "the report pins it, but no dictionary literal of the commit holds `.%s`" % key, "kind": "count"})
                    else:
                        add_pin(name, label, key, int(pinned[key]), actual, "count")
                        reduced = sources.reduced_dictionary(pins[-1]["constant"])
                        if reduced:
                            pins[-1]["note"] = "built by `reduce` over `%s`, which holds every key it keeps" % reduced[0] + ("; " + pins[-1]["note"] if pins[-1]["note"] else "")

        errors = lines("errors")
        if errors:
            pin_field = repeated(name, "errors pins", [(report, fields[3] if len(fields) > 3 else "") for report, fields in errors])
            totals = None
            for report, fields in errors:
                counts = [int(count) for count in (fields[2] if len(fields) > 2 else "").split(",") if count]
                totals = counts if totals is None else ([a + b for a, b in zip(totals, counts)] if len(totals) == len(counts) else counts)
            if pin_field:
                pinned = [int(count) for count in pin_field.split(",")]
                record = sources.corpora.get(name) or {}
                markers = sources.string_array(record.get("arguments", {}).get("errorMarkers", "[]")) or []
                for index in range(max(len(pinned), len(totals or []))):
                    actual = (totals or [])[index] if index < len(totals or []) else None
                    pin = pinned[index] if index < len(pinned) else "(no pin)"
                    if actual != pin:
                        add_pin(name, "errorGraphCounts", index, pin, actual, "count")
                        marker = markers[index] if index < len(markers) else None
                        pins[-1]["note"] = ("marker “%s”" % marker if marker is not None else "no marker at this index") + ("; " + pins[-1]["note"] if pins[-1]["note"] else "")

        value_oracle = keyed_totals("value-oracle", 2, 3, "valueOracleCounts", wrap_sum_keys=True)
        if value_oracle and value_oracle["pins"] is not None:
            pinned = fields_of(value_oracle["pins"])
            pinned_keys = [key for key, _ in pinned]
            for key, value in pinned:
                actual = value_oracle["totals"].get(key, 0)
                if actual != int(value, 0):
                    if key.endswith("Sum"):
                        add_pin(name, "valueOracleCounts", key, hexadecimal(int(value, 0)), hexadecimal(actual), "hex")
                    else:
                        add_pin(name, "valueOracleCounts", key, int(value, 0), actual, "count")
            for key in value_oracle["order"]:
                if key not in pinned_keys:
                    add_pin(name, "valueOracleCounts", key, "(no pin)", value_oracle["totals"][key], "hex" if key.endswith("Sum") else "count")

        # Section (d): floors.
        gating = lines("gating")
        if gating:
            floor = repeated(name, "gating floor", [(report, int(fields[-1])) for report, fields in gating if len(fields) in (3, 4)])
            totals = {}
            order = []
            for report, fields in gating:
                for key, value in fields_of(fields[2] if len(fields) == 4 else ""):
                    if key not in totals:
                        order.append(key)
                        totals[key] = 0
                    totals[key] += int(value)
            if floor is not None:
                for key in order:
                    if totals[key] < floor:
                        floors.append({"corpus": name, "kind": "gating", "name": key, "actual": totals[key], "floor": floor, "constant": "gatingDrawJudgedGraphFloor"})
        outputs = keyed_totals("outputs", 2, 3, "outputFeatureMinimumShares")
        if outputs and outputs["pins"]:
            for key, value in fields_of(outputs["pins"]):
                count = outputs["totals"].get(key, 0)
                if count * 100 < int(value) * accepted_count:
                    floors.append({"corpus": name, "kind": "outputShare", "name": key, "actual": count, "accepted": accepted_count, "floor": int(value), "constant": sources.pin_source(name, "outputFeatureMinimumShares")[0]})
        spellings = lines("spellings")
        if spellings:
            required = repeated(name, "spellings to draw", [(report, ",".join(sorted(filter(None, (fields[2] if len(fields) > 2 else "").split(","))))) for report, fields in spellings])
            accepted = set()
            for report, fields in spellings:
                accepted.update(filter(None, (fields[3] if len(fields) > 3 else "").split(",")))
            for spelling in sorted(set(filter(None, (required or "").split(","))) - accepted):
                floors.append({"corpus": name, "kind": "spelling", "name": spelling, "actual": 0, "floor": 1, "constant": "spellingDrawFeatures"})

    pins.sort(key=lambda pin: (corpus_rank(pin["corpus"]), label_order.get(pin["corpusLabel"], 1000), 0))
    # Within a label, keys keep report order (the sort is stable).

    # Classify the combine script's problems.
    pin_categories = {
        "accepted": {"acceptedSeedCount", "acceptedSeedsSum"}, "features": {"acceptedFeatureCounts"},
        "inspected": {"valueOracleInspectedGraphCount"}, "valueOracle": {"valueOracleCounts"},
        "readTwins": {"readTwinGraphCount"}, "retention": {"retentionCounts"}, "omitted": {"omittedValueGraphCount"},
        "levelCaptures": {"levelFunctionCaptureCounts"},
        "errors": {"errorGraphCounts"}, "draws": {"acceptedDrawFeatureCounts", "acceptedPublicMockDrawFeatureCounts"},
    }
    floor_categories = {"gating": "gating", "spellings": "spelling", "outputs": "outputShare", "builderSurface": "builderSurface", "levelCapturesFloor": "levelCaptures"}
    crashed_reports = {entry["report"] for entry in crashed}
    rejected_reports = {entry["report"] for entry in integrity["rejectedKnownIssueLists"]}
    disagreeing = {entry["corpus"] for entry in integrity["shardsDisagree"]}
    incomplete = {entry["corpus"] for entry in integrity["incompleteCorpora"]}

    def prose_accounted(corpus, text):
        if HASH_FIXTURE.match(text) or HASH_PARTITION.match(text):
            return True
        if any(pattern.match(text) for pattern in LIST_PROBLEMS):
            return True
        total = classify_total(text)
        if total is None:
            return False
        category, named_corpus, extra = total
        if named_corpus in incomplete:
            return True
        if category in pin_categories:
            return any(pin["corpus"] == named_corpus and pin["corpusLabel"] in pin_categories[category] for pin in pins)
        kind = floor_categories[category]
        return any(floor["corpus"] == named_corpus and floor["kind"] == kind and (extra is None or floor["name"] == extra) for floor in floors)

    for problem in combine_problems:
        accounted = False
        match = COMBINE_PATH_LINE.match(problem)
        if match:
            report = by_canonical.get(match.group(1))
            word, text = match.group(2), match.group(3)
            if word in ("failure", "stale", "misfiled"):
                accounted = report is not None
            else:
                accounted = (STOPPED.match(text) is not None and match.group(1) in crashed_reports) or prose_accounted(report.corpus if report else None, text)
        elif COMBINE_INCOMPLETE.match(problem):
            path = COMBINE_INCOMPLETE.match(problem).group(1)
            accounted = path in crashed_reports or path in rejected_reports
        elif COMBINE_DISAGREE.match(problem):
            accounted = COMBINE_DISAGREE.match(problem).group(1) in disagreeing
        elif COMBINE_NO_REPORT.match(problem):
            accounted = COMBINE_NO_REPORT.match(problem).group(1) in incomplete
        elif COMBINE_COVERAGE.match(problem):
            groups_matched = COMBINE_COVERAGE.match(problem).groups()
            accounted = next(group for group in groups_matched if group) in incomplete
        else:
            accounted = prose_accounted(None, problem)
        if not accounted:
            integrity["unclassified"].append(problem)
    # Long-run prose that no combine problem carried (combine lists every problem line, so this only catches lines it
    # did not see, such as those of a duplicate report).
    for report in kept:
        for problem in report.problems:
            if STOPPED.match(problem) and report.canonical in crashed_reports:
                continue
            if not prose_accounted(report.corpus, problem) and ("%s: problem %s" % (report.canonical, problem)) not in combine_problems:
                integrity["unclassified"].append("%s: problem %s" % (report.canonical, problem))

    # Shape the sections.
    def reproduction(corpus, seed):
        record = sources.corpora.get(corpus)
        features = record.get("features") if record else None
        if features is None:
            why = "the commit declares no corpus named %s" % corpus if record is None else "Corpus(%s) passes no array literal of feature cases as features:" % record["variable"]
            prefix = "SAFEDI_GRAPH_FUZZER_FEATURES=<unknown: %s> " % why
        else:
            prefix = "SAFEDI_GRAPH_FUZZER_FEATURES=%s " % ",".join(features) if features else ""
        return "%sSAFEDI_GRAPH_FUZZER_STARTING_SEED=%d SAFEDI_GRAPH_FUZZER_ITERATIONS=1 heavy swift test --traits sourceBuild --filter SafeDIToolGraphFuzzerTests/longRun" % (prefix, seed)

    unknown_failures = []
    for corpus in sorted(failures, key=corpus_rank):
        for kind in sorted(failures[corpus]):
            seeds = []
            for seed in sorted(failures[corpus][kind]):
                details = []
                for detail in failures[corpus][kind][seed]:
                    if detail not in details:
                        details.append(detail)
                # A `renamed` line repeats a renamed-graph failure's details with the sentence's period; only the
                # others (differences a known issue documents, multi-module differences) are added.
                failure_details = {detail for kinds in failures[corpus].values() for detail in kinds.get(seed, [])}
                for detail in details_by_seed.get((corpus, seed), []):
                    word, _, text = detail.partition(": ")
                    if word == "renamed" and text.endswith(".") and text[:-1] in failure_details:
                        continue
                    if detail not in details:
                        details.append(detail)
                seeds.append({"seed": seed, "details": details, "reproduction": reproduction(corpus, seed)})
            unknown_failures.append({"corpus": corpus, "kind": kind, "seeds": seeds})
    crashed_shards = sorted(({"corpus": entry["corpus"], "shard": entry["shard"], "suspectSeeds": entry["suspectSeeds"]} for entry in crashed), key=lambda entry: (corpus_rank(entry["corpus"]), entry["shard"]))

    stale_list = []
    for corpus in sorted(stale, key=corpus_rank):
        list_name = (sources.corpora.get(corpus) or {}).get("knownIssuesName", "")
        for reason in sorted(stale[corpus]):
            group = stale[corpus][reason]
            stale_list.append({"corpus": corpus, "list": list_name, "reason": reason, "seeds": sorted(group["seeds"]), "remedy": group["remedy"]})
    misfiled.sort(key=lambda entry: (corpus_rank(entry["corpus"]), entry["seed"], entry["text"]))

    observed_known = []
    for corpus in sorted(known, key=corpus_rank):
        list_name = (sources.corpora.get(corpus) or {}).get("knownIssuesName", "")
        for reason in sorted(known[corpus]):
            observed_known.append({"corpus": corpus, "list": list_name, "reason": reason, "count": known[corpus][reason]})
    observed_renamed = [{"corpus": corpus, "seed": seed, "text": text} for corpus in sorted(renamed, key=corpus_rank) for seed, text in sorted(renamed[corpus])]
    observed_multimodule = [{"corpus": corpus, "seed": seed, "text": text} for corpus in sorted(multimodule, key=corpus_rank) for seed, text in sorted(multimodule[corpus])]
    floors.sort(key=lambda floor: (corpus_rank(floor["corpus"]), ["gating", "outputShare", "spelling", "builderSurface", "levelCaptures"].index(floor["kind"])))

    integrity["unparsed"].sort(key=lambda entry: (entry["report"], entry["line"]))
    integrity["ambiguousSplit"].sort(key=lambda entry: (entry["report"], entry["line"]))
    integrity["shardsDisagree"].sort(key=lambda entry: (corpus_rank(entry["corpus"]), entry["value"]))
    integrity["incompleteCorpora"].sort(key=lambda entry: corpus_rank(entry["corpus"]))
    integrity["rejectedKnownIssueLists"].sort(key=lambda entry: (corpus_rank(entry["corpus"]), entry["report"]))
    integrity["duplicateShard"].sort(key=lambda entry: (entry["key"], entry["dropped"]))

    all_complete = bool(corpora_order) and all(corpus_state.get(corpus, {}).get("complete") for corpus in corpora_order) and all(state["complete"] for state in corpus_state.values())

    # Exit status.
    sections_empty = not (pins or unknown_failures or crashed_shards or stale_list or misfiled or floors)
    integrity_empty = not any(integrity[key] for key in integrity)
    if not all_complete:
        status = 69
    elif combine_exit == 0 and sections_empty and integrity_empty:
        status = 0
    else:
        status = 1

    # pins.json.
    def pin_value(value, kind):
        if isinstance(value, int) and kind == "count":
            return value
        return value

    provenance = context.get("provenance", {})
    document = {
        "schema": 1,
        "commit": context.get("commit"),
        "mode": context.get("mode"),
        "provenance": provenance,
        "statement": context.get("statement"),
        "runs": context.get("runs", []),
        "combine": {"exit": combine_exit, "problems": combine_problems},
        "pins": [{key: pin[key] for key in ("corpus", "constant", "corpusLabel", "key", "pinned", "actual", "note")} for pin in pins],
        "unknownFailures": unknown_failures,
        "crashedShards": crashed_shards,
        "stale": stale_list,
        "misfiled": misfiled,
        "floors": floors,
        "observed": {"known": observed_known, "renamed": observed_renamed, "multimodule": observed_multimodule},
        "builderSurface": builder_surface,
        "unclassified": integrity["unclassified"],
        "unparsed": integrity["unparsed"],
        "ambiguousSplit": integrity["ambiguousSplit"],
        "shardsDisagree": integrity["shardsDisagree"],
        "duplicateShard": integrity["duplicateShard"],
        "rejectedKnownIssueLists": integrity["rejectedKnownIssueLists"],
        "incompleteCorpora": integrity["incompleteCorpora"],
        "notDerived": NOT_DERIVED,
        "complete": all_complete,
        "exit": status,
    }
    for run in document["runs"]:
        if run.get("corpus") in (None, ""):
            directory = os.path.join("reports", str(run.get("id")))
            names = sorted({report.corpus for report in kept if report.relative.startswith(directory + os.sep) and report.corpus})
            run["corpus"] = names[0] if len(names) == 1 else "all"
    with open(os.path.join(out, "pins.json"), "w") as file:
        json.dump(document, file, indent=2, sort_keys=False, ensure_ascii=False)
        file.write("\n")

    # report.md.
    def show(value, kind):
        if kind == "count" and isinstance(value, int):
            return grouped(value)
        return str(value)

    commit = context.get("commit") or "?"
    markdown = []
    markdown.append("# Fuzzer pins for %s (%s)" % (commit[:9], context.get("mode")))
    markdown.append("")
    markdown.append("- Commit: `%s`" % commit)
    markdown.append("- Mode: %s" % context.get("mode"))
    markdown.append("- Provenance: event `%s`, head `%s`, base ref `%s`, base `%s`, valid for the head: `%s`" % (provenance.get("event"), provenance.get("headSha"), provenance.get("baseRef"), provenance.get("baseSha"), json.dumps(provenance.get("validForHead"))))
    markdown.append("- **%s**" % context.get("statement", ""))
    for run in document["runs"]:
        wall = run.get("wallSeconds")
        span = "from dispatch to completion" if context.get("mode") in ("corpora", "coverage") else "from the run\u2019s creation to its last update"
        markdown.append("- Run (%s): %s, %s%s" % (run.get("corpus"), run.get("url"), run.get("conclusion"), ", %d min %d s %s" % (wall // 60, wall % 60, span) if isinstance(wall, int) else ""))
    if not document["runs"]:
        markdown.append("- Runs: none (reports read from a directory)")
    markdown.append("- Combine verdict: exit %d (%s), %d problem%s" % (combine_exit, "green" if combine_exit == 0 else "red", len(combine_problems), "" if len(combine_problems) == 1 else "s"))
    markdown.append("- Complete: %s" % ("yes, every corpus the `corpora` line names has a complete report for every shard" if all_complete else "no: " + "; ".join("%s (%s)" % (entry["corpus"], entry["reason"]) for entry in integrity["incompleteCorpora"])))
    markdown.append("- Exit: %d" % status)
    markdown.append("")

    markdown.append("## (a) Pins that differ")
    markdown.append("")
    if pins:
        markdown.append("```")
        for pin in pins:
            key = "" if pin["key"] is None else ".%s" % pin["key"]
            markdown.append("%s %s%s pinned=%s actual=%s%s" % (pin["corpus"], pin["constant"], key, show(pin["pinned"], pin["kind"]), show(pin["actual"], pin["kind"]), " (%s)" % pin["note"] if pin["note"] else ""))
        markdown.append("```")
    else:
        markdown.append("None.")
    markdown.append("")

    markdown.append("## (b) Unknown failures")
    markdown.append("")
    if not unknown_failures and not crashed_shards:
        markdown.append("None.")
        markdown.append("")
    current = None
    for group in unknown_failures:
        if group["corpus"] != current:
            current = group["corpus"]
            markdown.append("### %s" % current)
            markdown.append("")
        markdown.append("#### %s" % group["kind"])
        markdown.append("")
        for seed in group["seeds"]:
            markdown.append("- Seed %d: `%s`" % (seed["seed"], seed["reproduction"]))
            for detail in seed["details"]:
                markdown.append("  - %s" % detail)
        markdown.append("")
    if crashed_shards:
        markdown.append("### Crashed shards (no `completed` line)")
        markdown.append("")
        for entry in crashed_shards:
            suspects = entry["suspectSeeds"]
            markdown.append("- %s, shard `%s`: suspect seeds %s" % (entry["corpus"], entry["shard"], ", ".join(str(seed) for seed in suspects) if suspects else "none (no seed started and did not finish)"))
            if suspects:
                markdown.append("  - `%s`" % reproduction(entry["corpus"], suspects[0]))
        markdown.append("")

    markdown.append("## (c) Stale known-issue seeds")
    markdown.append("")
    if not stale_list and not misfiled:
        markdown.append("None.")
        markdown.append("")
    current = None
    for group in stale_list:
        if group["corpus"] != current:
            current = group["corpus"]
            markdown.append("### %s (`%s`)" % (current, group["list"]))
            markdown.append("")
        markdown.append("- %s %s: %s" % ("Seed" if len(group["seeds"]) == 1 else "Seeds", ", ".join(str(seed) for seed in group["seeds"]), group["reason"]))
        markdown.append("  - Remedy: %s" % (group["remedy"] if group["remedy"] is not None else "(the line could not be split; see Integrity)"))
    if stale_list:
        markdown.append("")
    if misfiled:
        markdown.append("### Misfiled")
        markdown.append("")
        for entry in misfiled:
            markdown.append("- %s seed %d: %s" % (entry["corpus"], entry["seed"], entry["text"]))
        markdown.append("")

    markdown.append("## (d) Floors below their floor")
    markdown.append("")
    if floors:
        for floor in floors:
            if floor["kind"] == "gating":
                markdown.append("- %s gating draw `%s`: %s judged graphs, floor %s (`%s`)" % (floor["corpus"], floor["name"], grouped(floor["actual"]), grouped(floor["floor"]), floor["constant"]))
            elif floor["kind"] == "outputShare":
                markdown.append("- %s output `%s`: %s of %s accepted graphs (%.2f%%), minimum %d%% (`%s.%s`)" % (floor["corpus"], floor["name"], grouped(floor["actual"]), grouped(floor["accepted"]), 100.0 * floor["actual"] / floor["accepted"] if floor["accepted"] else 0.0, floor["floor"], floor["constant"], floor["name"]))
            elif floor["kind"] == "builderSurface":
                markdown.append("- %s builder surface `%s`: %s judged graphs, floor %s (`%s`)" % (floor["corpus"], floor["name"], grouped(floor["actual"]), grouped(floor["floor"]), floor["constant"]))
            elif floor["kind"] == "levelCaptures":
                markdown.append("- %s level function capture check `%s`: %s graphs, floor %s (`%s`)" % (floor["corpus"], floor["name"], grouped(floor["actual"]), grouped(floor["floor"]), floor["constant"]))
            else:
                markdown.append("- %s spelling `%s`: drawn in no accepted graph of any shard" % (floor["corpus"], floor["name"]))
    else:
        markdown.append("None.")
    markdown.append("")

    if builder_surface:
        markdown.append("## Builder surface (informational; a floored kind below its floor is in (d))")
        markdown.append("")
        for entry in builder_surface:
            markdown.append("### %s" % entry["corpus"])
            markdown.append("")
            floor_text = "floor %d, from the commit\u2019s combine script" % entry["floor"] if entry["floor"] is not None else "the commit\u2019s combine script states no floor"
            markdown.append("Floored kinds (the line\u2019s list; %s): %s" % (floor_text, ", ".join("`%s`" % kind for kind in entry["floored"]) or "none"))
            markdown.append("")
            markdown.append("| Kind | Graphs judged | Floored |")
            markdown.append("|---|---|---|")
            for kind, count in entry["counts"]:
                markdown.append("| `%s` | %s | %s |" % (kind, grouped(count), "yes" if kind in entry["floored"] else ""))
            for kind in entry["floored"]:
                if kind not in dict(entry["counts"]):
                    markdown.append("| `%s` | 0 (not reported) | yes |" % kind)
            markdown.append("")

    markdown.append("## Observed (informational; not counted for the exit status)")
    markdown.append("")
    if not observed_known and not observed_renamed and not observed_multimodule:
        markdown.append("Nothing.")
        markdown.append("")
    current = None
    for entry in observed_known:
        if entry["corpus"] != current:
            if current is not None:
                markdown.append("")
            current = entry["corpus"]
            markdown.append("### Known seeds, %s (`%s`)" % (current, entry["list"]))
            markdown.append("")
        markdown.append("- %s: %s" % (grouped(entry["count"]), entry["reason"]))
    if observed_known:
        markdown.append("")
    for title, entries in (("`renamed` lines", observed_renamed), ("`multimodule` lines", observed_multimodule)):
        if entries:
            markdown.append("### %s" % title)
            markdown.append("")
            for entry in entries:
                markdown.append("- %s seed %d: %s" % (entry["corpus"], entry["seed"], entry["text"]))
            markdown.append("")

    markdown.append("## Integrity")
    markdown.append("")
    if integrity_empty:
        markdown.append("Nothing.")
        markdown.append("")
    if integrity["incompleteCorpora"]:
        markdown.append("### Incomplete corpora (totals not compared)")
        markdown.append("")
        for entry in integrity["incompleteCorpora"]:
            markdown.append("- %s: %s" % (entry["corpus"], entry["reason"]))
        markdown.append("")
    if integrity["rejectedKnownIssueLists"]:
        markdown.append("### Known-issue lists the long run rejected (it stopped before writing a `shard` line)")
        markdown.append("")
        for entry in integrity["rejectedKnownIssueLists"]:
            markdown.append("- %s, %s:" % (entry["corpus"], entry["report"]))
            for problem in entry["problems"]:
                markdown.append("  - %s" % problem)
        markdown.append("")
    for key, title in (("unclassified", "Combine problems nothing above accounts for"), ("unparsed", "Unparsed lines"), ("ambiguousSplit", "Lines the splitting rule cannot split"), ("shardsDisagree", "Shards that disagree"), ("duplicateShard", "Duplicate shards (the first in path order is kept)")):
        entries = integrity[key]
        if not entries:
            continue
        markdown.append("### %s (`%s`)" % (title, key))
        markdown.append("")
        for entry in entries:
            if key == "unclassified":
                markdown.append("- %s" % entry)
            elif key in ("unparsed", "ambiguousSplit"):
                markdown.append("- %s: `%s`" % (entry["report"], entry["line"]))
            elif key == "shardsDisagree":
                markdown.append("- %s `%s`: %s" % (entry["corpus"], entry["value"], "; ".join("%s in %s" % (value["value"], value["report"]) for value in entry["values"])))
            else:
                markdown.append("- `%s`: kept %s, dropped %s" % (entry["key"], entry["kept"], entry["dropped"]))
        markdown.append("")

    markdown.append("## Not derived here")
    markdown.append("")
    markdown.append("Only the unit suite checks these pins; read them from the unit suite’s failures in a run on the same commit:")
    markdown.append("")
    for name in NOT_DERIVED:
        markdown.append("- `%s`" % name if not name.startswith("the ") else "- %s" % name)
    markdown.append("")
    markdown.append("A change to a known-issue list moves the smoke-and-known-issue hashes too, since they hash the smoke seeds and every listed seed.")
    with open(os.path.join(out, "report.md"), "w") as file:
        file.write("\n".join(markdown) + "\n")
    return status


if __name__ == "__main__":
    sys.exit(main())
