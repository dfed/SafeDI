#!/usr/bin/env python3
"""Rewrites an expected generated file a test assembles from fragments into one literal that spells the whole file.

usage: write-out-expectations.py --records DIR --checkout DIR --report FILE [--dry-run] [--only PATH_PART]

`.claude/rules/test-design.md` asks that a test compare a generated file with one string literal. A test written
before that rule may hand fragments to a helper that joins them with the header and the import blocks. This script
finds each such expression from the records of one run (see `regenerate-expectations.py --help` for recording):
an output the test's literals tile, as the regenerator's fragment mapping finds them, names the literals, and the
smallest expression that holds them all and is one side of a comparison is what the test expects. That expression is
replaced with what it evaluates to, spelled out: the recorded output, with every interpolation of a fragment put back
where the fragment had it.

- A file is `generatedFileHeader + \"\"\"…\"\"\"`; an expression that stands for several files is a dictionary literal of them.
- A test that takes a `MultiModuleIntegration` and whose expression evaluates to other text under each integration
  gets `let expectedFiles: … = switch integration { … }` before the statement, with each case's files written out.
- Nothing is evaluated. Run the tests afterwards: a wrong rewrite fails its test, since the old expression equalled
  the output the records hold. Then run `./CLI/lint.sh`, which indents what this script writes.

Every output it leaves alone is listed in the report with the reason. Exit status 0 when it wrote (or would write)
without leaving anything, 1 when it left something, 2 on an error.
"""

import argparse
import importlib.util
import os
import re
import sys

SINKS = {"expect", "require", "expectGeneratedFiles"}
# Helpers of a test file, called as a statement, that compare `output.modules[module]?.generatedFiles` with files
# they build from their other arguments.
STATEMENT_HELPERS = {"expectGeneratedCode"}
INTEGRATION_CASES = ["moduleInfo", "swiftPackagePlugin"]


def load_regenerator():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "regenerate-expectations.py")
    spec = importlib.util.spec_from_file_location("regenerate_expectations", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


regenerator = load_regenerator()


LET = object()  # In place of the other side's text: the expression is the value of a `let`.


class Statement:
    """In place of the other side's text: the expression is a whole statement, a call of a helper that compares the
    files of `module` in `output` with files it builds from its other arguments."""

    def __init__(self, output, module):
        self.output = output
        self.module = module

    def comparison(self, value):
        return f"#expect({self.output}.modules[{self.module}]?.generatedFiles == {value})"


class Left(Exception):
    """Why an output's expression is left as it is."""


class Structure:
    """A file's tokens with, for each, the opening bracket that holds it."""

    def __init__(self, swift_file):
        self.file = swift_file
        self.tokens = swift_file.tokens
        self.parent = []
        stack = []
        for position, token in enumerate(self.tokens):
            if token.kind == "punctuation" and token.text in ")]}":
                stack.pop()
            self.parent.append(stack[-1] if stack else None)
            if token.kind == "punctuation" and token.text in "([{":
                stack.append(position)
        self.position_of_literal = {token.literal.start: position for position, token in enumerate(self.tokens) if token.kind == "string"}

    def text(self, position):
        return self.tokens[position].text

    def is_punctuation(self, position, text):
        return 0 <= position < len(self.tokens) and self.tokens[position].kind == "punctuation" and self.tokens[position].text == text

    def closing(self, opening):
        return self.file.matching[opening]

    def ancestors(self, position):
        chain = []
        opening = self.parent[position]
        while opening is not None:
            chain.append(opening)
            opening = self.parent[opening]
        return chain

    def callee_start(self, opening):
        """The first token of the call whose arguments `opening` starts, or None when it starts no call."""
        position = opening - 1
        if position < 0 or self.tokens[position].kind != "identifier":
            return None
        while position >= 2 and self.is_punctuation(position - 1, ".") and self.tokens[position - 2].kind == "identifier":
            position -= 2
        if self.is_punctuation(position - 1, "#"):
            position -= 1
        return position

    def elements(self, opening):
        """The token ranges of the comma-separated elements directly inside the bracket at `opening`."""
        closing = self.closing(opening)
        ranges = []
        first = opening + 1
        for position in range(opening + 1, closing):
            if self.parent[position] == opening and self.is_punctuation(position, ","):
                ranges.append((first, position - 1))
                first = position + 1
        if first <= closing - 1:
            ranges.append((first, closing - 1))
        return ranges

    def element_holding(self, opening, first, last):
        for start, end in self.elements(opening):
            if start <= first and last <= end:
                return start, end
        raise Left("its fragments are in several arguments of one comparison")

    def after_label(self, opening, start, end, first):
        """`start` moved past a `label:` or `key:` directly inside the bracket, when one comes before `first`."""
        for position in range(start, first):
            if self.parent[position] == opening and self.is_punctuation(position, ":"):
                return position + 1, True
        return start, False

    def side_of_comparison(self, opening, start, end, first, last):
        """The side of a `==` directly inside the bracket that holds first…last, and the other side's text."""
        for position in range(start, end):
            if self.parent[position] == opening and self.is_punctuation(position, "=") and self.is_punctuation(position + 1, "=") and self.tokens[position].end == self.tokens[position + 1].start:
                if last < position:
                    return start, position - 1, self.source(position + 2, end)
                if first > position + 1:
                    return position + 2, end, self.source(start, position - 1)
                raise Left("its fragments are on both sides of a comparison")
        return start, end, None

    def source(self, first, last):
        return self.file.source[self.tokens[first].start:self.tokens[last].end] if first <= last else ""

    def operand_end(self, position):
        """The last token of the operand that starts at `position`: a literal, or a name with its calls and members."""
        if self.tokens[position].kind == "string":
            return position
        if self.tokens[position].kind != "identifier":
            raise Left("its fragments are joined in a statement this script does not follow")
        end = position
        while True:
            if self.is_punctuation(end + 1, ".") and end + 2 < len(self.tokens) and self.tokens[end + 2].kind == "identifier":
                end += 2
            elif (self.is_punctuation(end + 1, "(") or self.is_punctuation(end + 1, "[")) and self.tokens[end].end == self.tokens[end + 1].start:
                end = self.closing(end + 1)
            else:
                return end

    def operand_start(self, position):
        if self.tokens[position].kind == "string":
            return position
        start = position
        while True:
            if self.is_punctuation(start, ")") or self.is_punctuation(start, "]"):
                start = self.closing(start) - 1
            elif self.tokens[start].kind == "identifier" and self.is_punctuation(start - 1, ".") and (self.tokens[start - 2].kind == "identifier" or self.text(start - 2) in ")]"):
                start -= 2
            elif self.tokens[start].kind == "identifier":
                return start
            else:
                raise Left("its fragments are joined in a statement this script does not follow")

    def statement_value(self, first, last):
        """The whole right-hand side of the `let name = a + b + …` that first…last is part of."""
        start, end = first, last
        while self.is_punctuation(start - 1, "+"):
            start = self.operand_start(start - 2)
        while self.is_punctuation(end + 1, "+"):
            end = self.operand_end(end + 2)
        if self.let_before(start) is None:
            raise Left("its fragments are not in a comparison, an argument or a `let`")
        return start, end

    def let_before(self, start):
        """(the `let` token, the name token) of `let name =` or `let name: String =` just before `start`, or None."""
        if not self.is_punctuation(start - 1, "="):
            return None
        name = start - 2
        if self.tokens[name].kind == "identifier" and self.text(name) == "String" and self.is_punctuation(name - 1, ":"):
            name -= 2
        if self.tokens[name].kind == "identifier" and self.text(name - 1) == "let":
            return name - 1, name
        return None

    def constant_name(self, literal_position):
        """The name of the stored constant whose whole value is the literal at `literal_position`, or None."""
        position = literal_position - 1
        if not self.is_punctuation(position, "="):
            return None
        position -= 1
        if self.tokens[position].kind == "identifier" and self.text(position) == "String" and self.is_punctuation(position - 1, ":"):
            position -= 2
        if self.tokens[position].kind == "identifier" and self.text(position - 1) == "let":
            after = self.tokens[literal_position + 1] if literal_position + 1 < len(self.tokens) else None
            if after is None or not (after.kind == "punctuation" and after.text in "+.("):
                return self.text(position)
        return None

    def references(self, name, function):
        """The token ranges in `function`'s body that read the constant `name`, as `name`, `Self.name` or `Type.name`."""
        ranges = []
        for position, token in enumerate(self.tokens):
            if token.kind != "identifier" or token.text != name or not function[2] <= token.start < function[3]:
                continue
            if self.is_punctuation(position + 1, ":") or self.text(position - 1) in ("let", "var", "func"):
                continue
            first = position
            if self.is_punctuation(position - 1, ".") and self.tokens[position - 2].kind == "identifier":
                first = position - 2
            ranges.append((first, position))
        return ranges

    def helper_comparisons(self, function):
        """(first token, last token, the output's variable, the module or None) of each expected side in `function`
        that calls a helper and is compared with the generated files of a module."""
        found = []
        for position, token in enumerate(self.tokens):
            if token.kind != "identifier" or token.text not in ("expect", "expectGeneratedFiles") or not function[2] <= token.start < function[3]:
                continue
            opening = position + 1
            if not self.is_punctuation(opening, "("):
                continue
            elements = self.elements(opening)
            if token.text == "expect":
                if not self.is_punctuation(position - 1, "#") or not elements:
                    continue
                start, end = elements[0]
                equals = [candidate for candidate in range(start, end) if self.parent[candidate] == opening and self.is_punctuation(candidate, "=") and self.is_punctuation(candidate + 1, "=") and self.tokens[candidate].end == self.tokens[candidate + 1].start]
                if len(equals) != 1:
                    continue
                actual, expected = (start, equals[0] - 1), (equals[0] + 2, end)
            else:
                if len(elements) < 2 or self.is_punctuation(position - 1, "func"):
                    continue
                actual, expected = elements[0], elements[1]
            match = re.fullmatch(r'(?:try #require\()?(\w+)(?:\.modules\[\s*"([^"\\]+)"\s*\]\)?\??)?\.generatedFiles', self.source(*actual))
            if match is None and actual[0] == actual[1] and self.tokens[actual[0]].kind == "identifier":
                # A constant the test unwrapped the files into.
                body = self.file.source[function[2]:token.start]
                declared = re.findall(r'let ' + re.escape(self.text(actual[0])) + r' = try #require\((\w+)\.modules\[\s*"([^"\\]+)"\s*\](?:\?\.generatedFiles\)|\)\.generatedFiles)', body)
                match = re.fullmatch(r'(\w+)\.modules\["([^"]+)"\]\.generatedFiles', f'{declared[-1][0]}.modules["{declared[-1][1]}"].generatedFiles') if declared else None
            if match is None:
                continue
            calls_helper = any(
                self.tokens[candidate].kind == "identifier" and (self.text(candidate) == "Self" or self.text(candidate)[:1].isupper())
                and self.is_punctuation(candidate + 1, ".") and self.tokens[candidate + 2].kind == "identifier" and self.is_punctuation(candidate + 3, "(")
                for candidate in range(expected[0], expected[1] - 2)
            )
            if calls_helper:
                found.append((expected[0], expected[1], match.group(1), match.group(2)))
        return found

    def line_of_let(self, name, before, function):
        """The line of the nearest `let name` before the token at `before` in `function`, or None."""
        for position in range(before, 0, -1):
            if self.tokens[position].start < function[2]:
                return None
            if self.tokens[position].kind == "identifier" and self.text(position) == name and self.text(position - 1) == "let":
                return self.file.line_of(self.tokens[position].start)
        return None

    def case_of(self, position):
        """The integration whose `case .name:` of a `switch` holds the token at `position`, or None."""
        for brace in self.ancestors(position):
            if self.text(brace) != "{":
                continue
            for candidate in range(position, brace, -1):
                if self.parent[candidate] == brace and self.tokens[candidate].kind == "identifier" and self.text(candidate) == "case":
                    if self.is_punctuation(candidate + 1, ".") and self.text(candidate + 2) in INTEGRATION_CASES and self.is_punctuation(candidate + 3, ":"):
                        return self.text(candidate + 2)
                    return None
        return None

    def expression(self, ranges):
        """The expression the test compares with the output tiled by the literals (or the constants read) at these
        token ranges: (first token, last token, kind, the other side's text). `kind` is "file", "files" or None when
        the expression's place does not say."""
        first, last = min(start for start, _ in ranges), max(end for _, end in ranges)
        chains = [self.ancestors(start) for start, _ in ranges]
        common = [opening for opening in chains[0] if all(opening in chain for chain in chains[1:])]
        if len(ranges) > 1:
            if not common or self.text(common[0]) == "{":
                raise Left("its fragments are in several statements")
            opening = common[0]
            start = self.callee_start(opening) if self.text(opening) == "(" else opening
            if start is None:
                start = opening
            first, last = start, self.closing(opening)
        kind = None
        while True:
            opening = self.parent[first]
            if opening is None or self.text(opening) == "{":
                first, last = self.statement_value(first, last)
                return first, last, kind or "file", LET
            if self.text(opening) == "(":
                start = self.callee_start(opening)
                name = self.text(opening - 1) if start is not None else None
                if name in STATEMENT_HELPERS and start == opening - 1 and self.parent[start] is not None and self.text(self.parent[start]) == "{":
                    before = self.tokens[start - 1]
                    labels = {}
                    for element_start, element_end in self.elements(opening):
                        if self.is_punctuation(element_start + 1, ":"):
                            labels[self.text(element_start)] = (element_start + 2, element_end)
                    if before.text in ("=", "return", "try", "await", ".") or "of" not in labels or "module" not in labels:
                        raise Left("a helper that compares is called in a way this script does not read")
                    module_start, module_end = labels["module"]
                    if module_start != module_end or self.tokens[module_start].kind != "string":
                        raise Left("a helper that compares takes a module name that is not a literal")
                    return start, self.closing(opening), "files", Statement(self.source(*labels["of"]), self.source(module_start, module_end))
                if name in SINKS:
                    start, end = self.element_holding(opening, first, last)
                    start, _ = self.after_label(opening, start, end, first)
                    start, end, other = self.side_of_comparison(opening, start, end, first, last)
                    if (start, end) != (first, last):
                        # More than the expression is on this side, such as `header + helper(…)`.
                        position = start
                        while position < first:
                            position = self.operand_end(position) + 1
                            if position < first and not self.is_punctuation(position, "+"):
                                raise Left("its side of the comparison is more than a sum of operands")
                            position += 1
                        first, last = start, end
                    if name == "expectGeneratedFiles":
                        kind = "files"
                    return first, last, kind, other
                first, last = (start if start is not None else opening), self.closing(opening)
                kind = None
                continue
            # A dictionary or array literal, or a subscript.
            if self.tokens[opening - 1].kind == "identifier" and self.tokens[opening - 1].end == self.tokens[opening].start:
                raise Left("its fragments are inside a subscript")
            closing = self.closing(opening)
            if self.is_punctuation(closing + 1, ".") and closing + 4 < len(self.tokens) and self.text(closing + 2) == "joined" and self.is_punctuation(closing + 3, "(") and self.is_punctuation(closing + 4, ")"):
                # `[header, imports, """…"""].joined()`: the array's elements are the file's fragments.
                first, last = opening, closing + 4
                continue
            outer = self.parent[opening]
            start, end = self.element_holding(opening, first, last)
            start, is_value = self.after_label(opening, start, end, first)
            in_helper_call = outer is not None and self.text(outer) == "(" and self.callee_start(outer) is not None and self.text(outer - 1) not in SINKS
            if in_helper_call:
                first, last = opening, self.closing(opening)
                kind = None
                continue
            if (start, end) != (first, last):
                position = start
                while position < first:
                    position = self.operand_end(position) + 1
                    if position < first and not self.is_punctuation(position, "+"):
                        raise Left("its dictionary value is more than a sum of operands")
                    position += 1
                first, last = start, end
            return first, last, "file" if is_value else kind, None


def file_parts(content, header, fragments):
    """(whether the content starts with the header, the parts of the rest with the fragments' interpolations)."""
    has_header = bool(header) and content.startswith(header)
    offset = len(header) if has_header else 0
    spans = []
    for literal, start, _, captures, ambiguous in fragments:
        if ambiguous:
            raise Left("ambiguous interpolation captures")
        expressions = [value for kind, value in literal.parts if kind == "interpolation"]
        for expression, (capture_start, capture_end) in zip(expressions, captures):
            spans.append((start + capture_start, start + capture_end, expression))
    spans.sort()
    parts = []
    position = offset
    for start, end, expression in spans:
        if start < position:
            raise Left("its interpolations overlap")
        parts.append(("text", content[position:start]))
        parts.append(("interpolation", expression))
        position = end
    parts.append(("text", content[position:]))
    if regenerator.placeholder_count(parts):
        raise Left("the output names a run directory outside the fragments’ interpolations")
    return has_header, parts


def file_source(has_header, parts, indentation):
    template = regenerator.StringLiteral("", 0, 0, 0, True, [], indentation)
    try:
        literal = regenerator.checked_encoding(template, parts)
    except (regenerator.EncodeError, regenerator.ApplyError) as error:
        raise Left(f"the output cannot be spelled: {error}")
    return ("generatedFileHeader + " if has_header else "") + literal


def value_source(files, kind, indentation):
    """The source of one case: `files` is {output name: (has header, parts)}."""
    inner = indentation + "\t"
    if kind == "file":
        if len(files) != 1:
            raise Left("an expression for one file stands for several outputs")
        return file_source(*next(iter(files.values())), indentation)
    lines = ["["]
    for name in sorted(files):
        if '"' in name or "\\" in name:
            raise Left("an output name this script does not spell")
        lines.append(f'{inner}"{name}": {file_source(*files[name], inner)},')
    lines.append(indentation + "]")
    return "\n".join(lines)


MODULE_INFO_SEAM_CALL_COMMENT = re.compile(r" // If this line does not compile, compile the code SafeDI generates for module (\S+) into \1: under Bazel, add \1’s safedi_compile rule to the srcs of its swift_library; under Tuist, add SafeDI\.generatedSource to the sources of its target; in a custom build, compile the file its SafeDITool generate run writes\.$", re.MULTILINE)
PLUGIN_SEAM_CALL_COMMENT = re.compile(r" // If this line does not compile, add the SafeDI plugin to the target that declares (.+)\.$", re.MULTILINE)


def merged_for_integrations(first, second, parameter):
    """One file's (has header, parts) that stands for `first` under `.moduleInfo` and `second` under
    `.swiftPackagePlugin`: the two are the same but for the comments on calls of a seam, which become
    `\\(parameter.seamCallComment(type:declaringModule:))`. None when they differ in more."""
    if first == second:
        return first
    if first[0] != second[0] or len(first[1]) != len(second[1]):
        return None
    parts = []
    for (kind, value), (other_kind, other_value) in zip(first[1], second[1]):
        if kind != other_kind:
            return None
        if kind != "text":
            if value != other_value:
                return None
            parts.append((kind, value))
            continue
        pieces, other_pieces = MODULE_INFO_SEAM_CALL_COMMENT.split(value), PLUGIN_SEAM_CALL_COMMENT.split(other_value)
        if len(pieces) != len(other_pieces) or pieces[0::2] != other_pieces[0::2]:
            return None
        for index, piece in enumerate(pieces):
            if index % 2 == 0:
                parts.append(("text", piece))
            else:
                if any(character in name for name in (piece, other_pieces[index]) for character in '"\\'):
                    return None
                parts.append(("interpolation", f'{parameter}.seamCallComment(type: "{other_pieces[index]}", declaringModule: "{piece}")'))
    return first[0], parts


def keyed_by_integration(cases, indentation, parameter):
    """The source of one dictionary for both integrations, when their files differ only in name and in the comments
    on calls of a seam: such a key is chosen by the integration, and such a comment interpolated. None when the
    files differ in more."""
    first, second = (cases[case] for case in INTEGRATION_CASES)
    if len(first) != len(second):
        return None
    inner = indentation + "\t"
    lines = ["["]
    unpaired = dict(second)
    for name in sorted(first):
        partners = [other for other in sorted(unpaired) if merged_for_integrations(first[name], unpaired[other], parameter) is not None]
        if name in partners:
            partner = name
        elif len(partners) == 1:
            partner = partners[0]
        else:
            return None
        merged = merged_for_integrations(first[name], unpaired.pop(partner), parameter)
        if any('"' in text or "\\" in text for text in (name, partner)):
            return None
        key = f'"{name}"' if partner == name else f'({parameter} == .{INTEGRATION_CASES[0]} ? "{name}" : "{partner}")'
        lines.append(f"{inner}{key}: {file_source(*merged, inner)},")
    lines.append(indentation + "]")
    return "\n".join(lines)


def migrate(arguments):
    manifest = regenerator.read_manifest(arguments.records)
    difference = regenerator.manifest_difference(manifest, regenerator.tests_manifest(arguments.checkout))
    if difference:
        raise regenerator.ApplyError("the checkout’s Tests/ changed since recording: " + ", ".join(difference[:5]))
    header = regenerator.read_header(arguments.records)
    records = [record for record in regenerator.read_records(arguments.records) if record["kind"] == "generation"]
    resolver = regenerator.FileResolver(arguments.checkout)

    def generation_of(record):
        return tuple(record.get(field) for field in ("fileID", "line", "column", "testFileID", "testLine", "testName", "integration", "module", "inputsDigest"))

    def site_of(record):
        return tuple(record.get(field) for field in ("fileID", "line", "column", "testFileID", "testLine", "testName", "module"))

    records_of_generation = {}
    generations_of_site = {}
    for record in records:
        records_of_generation.setdefault(generation_of(record), []).append(record)
        generations_of_site.setdefault(site_of(record), set()).add(generation_of(record))
    files = {}
    structures = {}

    def swift_file(file_id):
        relative_path = resolver.resolve(file_id)
        if relative_path not in files:
            path = os.path.join(arguments.checkout, relative_path)
            with open(path, encoding="utf-8") as source_file:
                files[relative_path] = regenerator.SwiftFile(path, relative_path, source_file.read())
            structures[relative_path] = Structure(files[relative_path])
        return relative_path

    literals_by_scope = {}

    def literals_in(relative_path, function):
        if relative_path not in literals_by_scope:
            by_function = {}
            for literal in files[relative_path].literals:
                by_function.setdefault(files[relative_path].test_function_of_offset(literal.start), []).append(literal)
            literals_by_scope[relative_path] = by_function
        return literals_by_scope[relative_path].get(function, [])

    left = []  # (path, line, test name, output name, reason)
    records_of_function = {}  # (test path, test function) → its generation records
    groups = {}  # (path, first token, last token) → {"kind", "other", "function", "records": [(record, fragments)]}
    for record in sorted(records, key=lambda record: record["key"]):
        call_path = swift_file(record["fileID"])
        if arguments.only and arguments.only not in call_path and arguments.only not in record.get("testFileID", ""):
            continue
        scopes = [(call_path, files[call_path].test_function_of_line(record["line"]))]
        if record.get("testFileID") and record.get("testLine"):
            test_path = swift_file(record["testFileID"])
            scopes.append((test_path, files[test_path].test_function_declared_at(record["testLine"])))
        if scopes[-1][1] is not None:
            records_of_function.setdefault(scopes[-1], []).append(record)
        if arguments.helpers_only:
            continue
        path_of_literal = {}
        for relative_path, function in scopes:
            for literal in literals_in(relative_path, function) + (literals_in(relative_path, None) if function is not None else []):
                path_of_literal.setdefault(id(literal), (relative_path, literal))
        candidates = sorted(path_of_literal.values(), key=lambda candidate: (candidate[0], candidate[1].start))
        if any(regenerator.match_literal(literal, record["content"], header) is not None for _, literal in candidates):
            continue  # Already one literal.
        tiling, reason = regenerator.tile_fragments([literal for _, literal in candidates], record["content"], header)
        if tiling is None:
            continue  # Not built from fragments: no literal of the test spells it.
        test_path, function = scopes[-1]
        where = (test_path, function[0] if function else record["line"], record.get("testName", ""), record["outputName"])
        if reason is not None:
            left.append(where + (reason,))
            continue
        try:
            paths = {path_of_literal[id(fragment[0])][0] for fragment in tiling}
            if len(paths) != 1:
                raise Left("its fragments are in several files")
            path = paths.pop()
            structure = structures[path]
            functions = {files[path].test_function_of_offset(fragment[0].start) for fragment in tiling} - {None}
            if len(functions) > 1:
                raise Left("its fragments are in several test functions")
            if not functions:
                if function is None or test_path != path:
                    raise Left("its fragments are constants and the test function is not known")
                functions = {function}
            test_function = next(iter(functions))
            ranges = set()
            for fragment in tiling:
                position = structure.position_of_literal[fragment[0].start]
                if files[path].test_function_of_offset(fragment[0].start) is not None:
                    ranges.add((position, position))
                    continue
                if fragment[0].interpolation_count:
                    raise Left("a fragment outside the test function interpolates")
                name = structure.constant_name(position)
                if name is None:
                    raise Left("a fragment outside the test function is not a stored constant")
                references = structure.references(name, test_function)
                if len(references) != 1:
                    raise Left(f"a fragment is a constant the test reads {len(references)} times")
                ranges.add(references[0])
            first, last, kind, other = structure.expression(sorted(ranges))
            if isinstance(other, Statement):
                if any(json_module != record["module"] for json_module in [other.module.strip('"')]):
                    raise Left("a helper that compares names another module than the output’s")
            let = None
            if other is LET:
                other = None
                # Nothing shows what else the test joins to a `let`, so its fragments must spell the whole output.
                position = len(header) if header and record["content"].startswith(header) else 0
                for _, start, end, _, _ in sorted(tiling, key=lambda fragment: fragment[1]):
                    if start != position:
                        break
                    position = end
                if position != len(record["content"]):
                    # Code joins the rest where the test reads the `let`: the expression is there.
                    let_token, name_token = structure.let_before(first)
                    name = structure.text(name_token)
                    references = structure.references(name, test_function)
                    chosen = [reference for reference in references if structure.case_of(reference[0]) == record.get("integration")]
                    if not chosen:
                        chosen = [reference for reference in references if structure.case_of(reference[0]) is None]
                    if len(chosen) != 1:
                        raise Left("a `let` holds part of the output and code joins the rest")
                    let = (let_token, last, len(references), chosen[0])
                    ranges = {(start, end) for start, end in ranges if not first <= start <= last} | {chosen[0]}
                    first, last, kind, other = structure.expression(sorted(ranges))
                    if not isinstance(other, str) and other is not None:
                        raise Left("a `let` holds part of the output and another `let` joins the rest")
            after = structure.tokens[last + 1] if last + 1 < len(structure.tokens) else None
            if after is not None and after.kind == "punctuation" and after.text in ".[!?" and after.start == structure.tokens[last].end:
                raise Left("the expression is read through a member or a subscript")
            group = groups.setdefault((path, first, last), {"kind": kind, "other": other, "function": test_function, "records": [], "where": where, "case": structure.case_of(first), "lets": set()})
            if let is not None:
                group["lets"].add(let)
            group["records"].append((record, tiling))
        except Left as reason:
            left.append(where + (str(reason),))

    # Second pass: a comparison of a module's generated files with an expression that calls a helper, which no
    # fragment of the test tiles (the helper spells the file, or builds it from arguments that are not literals).
    # The expression stands for every file the compared generation wrote.
    for (path, function), function_records in sorted(records_of_function.items(), key=lambda item: (item[0][0], item[0][1][0])):
        structure = structures[path]
        for first, last, variable, module in structure.helper_comparisons(function):
            if any(group_path == path and group_first <= last and first <= group_last for group_path, group_first, group_last in groups):
                continue
            where = (path, function[0], function_records[0].get("testName", ""), f"the files of {module or variable}")
            try:
                chosen = [record for record in function_records if module is None or record.get("module") == module]
                case = structure.case_of(first)
                if case is not None:
                    chosen = [record for record in chosen if record.get("integration") == case]
                sites = sorted({(record["fileID"], record["line"]) for record in chosen})
                if len(sites) > 1:
                    line = structure.line_of_let(variable, first, function)
                    sites = [site for site in sites if resolver.resolve(site[0]) == path and site[1] == line]
                    chosen = [record for record in chosen if (record["fileID"], record["line"]) in sites]
                if len(sites) != 1:
                    raise Left("a helper builds the files, and which generation they are compared with is not clear")
                if any(regenerator.placeholder_count([("text", record["content"])]) for record in chosen):
                    raise Left("a helper builds the files, and the output names a run directory")
                group = groups.setdefault((path, first, last), {"kind": "files", "other": None, "function": function, "records": [], "where": where, "case": case, "lets": set()})
                group["records"] = [(record, []) for record in chosen]
            except Left as reason:
                left.append(where + (str(reason),))

    # An expression inside another's range would be replaced twice.
    by_path = {}
    for (path, first, last) in groups:
        by_path.setdefault(path, []).append((first, last))
    for path, ranges in by_path.items():
        ranges.sort()
        for (first, last), (next_first, next_last) in zip(ranges, ranges[1:]):
            if next_first <= last:
                for key in ((path, first, last), (path, next_first, next_last)):
                    if key in groups:
                        group = groups.pop(key)
                        left.append(group["where"] + ("its expression overlaps another output’s",))

    edits = {}  # path → [(start, end, replacement)]
    reads_replaced = {}  # (path, a `let`'s first token, its last, how often the test reads it) → the reads replaced
    names_used = {}
    written = 0
    for (path, first, last) in sorted(groups):
        group = groups[(path, first, last)]
        structure = structures[path]
        current = files[path]
        try:
            line_start = current.line_starts[current.line_of(structure.tokens[first].start) - 1]
            indentation = re.match(r"[ \t]*", current.source[line_start:]).group(0)
            # Every run of the generation the expression is compared with must be spelled by it: a run whose output
            # these fragments do not tile takes its text from code this script did not read.
            spelled = {generation_of(record) for record, _ in group["records"]}
            for record, _ in group["records"]:
                missing = generations_of_site[site_of(record)] - spelled
                if group["case"] is not None:
                    # Inside `case .name:` the expression stands for that integration's runs alone.
                    missing = {generation for generation in missing if generation[6] == group["case"]}
                if missing:
                    raise Left("these fragments spell the output for only some of the test’s arguments")
            cases = {}  # integration → {output name: (has header, parts)}
            for record, tiling in group["records"]:
                parts = file_parts(record["content"], header, tiling)
                case = cases.setdefault(record.get("integration"), {})
                if record["outputName"] in case and case[record["outputName"]] != parts:
                    raise Left("it evaluates to other text for another argument of the test than the integration")
                case[record["outputName"]] = parts
            kind = group["kind"]
            if kind is None:
                other = (group["other"] if isinstance(group["other"], str) else "").strip()
                if any(len(case) > 1 for case in cases.values()) or re.search(r"generatedFiles\??$", other):
                    kind = "files"
                elif re.search(r"generatedFiles\??\[", other):
                    kind = "file"
                if kind is None and all(len(case) == 1 for case in cases.values()) and not re.search(r"[Ff]iles\b", other):
                    # One output per run, compared with a value not named as files: a wrong guess does not compile.
                    kind = "file"
                if kind is None:
                    raise Left("its place does not say whether it stands for one file or several")
            if kind == "files":
                # The expression stands for every file of the generation, also those no fragment of the test spells.
                for record, _ in group["records"]:
                    case = cases[record.get("integration")]
                    for sibling in records_of_generation[generation_of(record)]:
                        if sibling["outputName"] not in case:
                            case[sibling["outputName"]] = file_parts(sibling["content"], header, [])
            expression_source = structure.source(first, last)
            signature = current.source[current.line_starts[group["function"][0] - 1]:group["function"][2]]
            parameter = re.search(r"(\w+): MultiModuleIntegration\b", signature)
            sources = {case: value_source(case_files, kind, indentation) for case, case_files in cases.items()}
            keyed = keyed_by_integration(cases, indentation, parameter.group(1)) if kind == "files" and len(set(sources.values())) > 1 and parameter and sorted(cases, key=str) == INTEGRATION_CASES else None
            if keyed is not None:
                sources = {None: keyed}
            if len(set(sources.values())) == 1:
                if parameter and len(cases) == 1 and re.search(rf"\b{parameter.group(1)}\b", expression_source) and next(iter(cases)) is not None and group["case"] is None:
                    raise Left("only one integration’s output is built from these fragments")
                replacement = next(iter(sources.values()))
                if isinstance(group["other"], Statement):
                    replacement = group["other"].comparison(replacement)
                edits.setdefault(path, []).append((structure.tokens[first].start, structure.tokens[last].end, replacement))
            else:
                if not parameter or sorted(cases, key=str) != INTEGRATION_CASES:
                    raise Left("it evaluates to other text per case, and the cases are not the two integrations")
                # The statement starts on the line of the outermost bracket that holds the expression in this body.
                statement_token = first
                for opening in structure.ancestors(first):
                    if structure.text(opening) == "{":
                        break
                    statement_token = opening
                statement_line_start = current.line_starts[current.line_of(structure.tokens[statement_token].start) - 1]
                statement_indentation = re.match(r"[ \t]*", current.source[statement_line_start:]).group(0)
                count = names_used.get((path, group["function"][0]), 0) + 1
                names_used[(path, group["function"][0])] = count
                name = ("expectedFiles" if kind == "files" else "expectedFile") + (str(count) if count > 1 else "")
                body = current.source[group["function"][2]:group["function"][3]]
                if re.search(rf"\b{name}\b", body):
                    raise Left(f"the test already declares {name}")
                type_name = "[String: String]" if kind == "files" else "String"
                lines = [f"{statement_indentation}let {name}: {type_name} = switch {parameter.group(1)} {{"]
                for case in INTEGRATION_CASES:
                    lines.append(f"{statement_indentation}case .{case}:")
                    lines.append(statement_indentation + "\t" + value_source(cases[case], kind, statement_indentation + "\t"))
                lines.append(statement_indentation + "}")
                edits.setdefault(path, []).append((statement_line_start, statement_line_start, "\n".join(lines) + "\n"))
                edits[path].append((structure.tokens[first].start, structure.tokens[last].end, group["other"].comparison(name) if isinstance(group["other"], Statement) else name))
            written += 1
            for let_first, let_last, reference_count, reference in group["lets"]:
                reads_replaced.setdefault((path, let_first, let_last, reference_count), set()).add(reference)
        except Left as reason:
            left.append(group["where"] + (str(reason),))

    # A `let` every read of which was replaced holds nothing the test still uses.
    for (path, let_first, let_last, reference_count), replaced in reads_replaced.items():
        if len(replaced) == reference_count:
            current = files[path]
            structure = structures[path]
            start = current.line_starts[current.line_of(structure.tokens[let_first].start) - 1]
            end = current.source.index("\n", structure.tokens[let_last].end) + 1
            edits[path].append((start, end, ""))

    if not arguments.dry_run:
        for path in sorted(edits):
            current = files[path]
            source = current.source
            for start, end, replacement in sorted(edits[path], key=lambda edit: (edit[0], edit[1]), reverse=True):
                source = source[:start] + replacement + source[end:]
            with open(current.path, "w", encoding="utf-8") as source_file:
                source_file.write(source)
    with open(arguments.report, "w", encoding="utf-8") as report:
        report.write(f"Expressions written out: {written}\nOutputs left as they are: {len(left)}\n\n")
        reasons = {}
        for path, line, test_name, output_name, reason in sorted(left):
            reasons.setdefault(reason, []).append(f"  {path}:{line} ({test_name}) {output_name}")
        for reason in sorted(reasons):
            report.write(f"{reason}: {len(reasons[reason])}\n" + "\n".join(reasons[reason]) + "\n\n")
    print(f"written out {written}, left {len(left)}; see {arguments.report}")
    return 1 if left else 0


def emit(arguments):
    """Prints, for a hand edit, the whole files each generation of the tests named `--emit` wrote."""
    header = regenerator.read_header(arguments.records)
    indentation = "\t" * arguments.tabs
    generations = {}
    for record in regenerator.read_records(arguments.records):
        if record["kind"] == "generation" and arguments.emit in record.get("testName", ""):
            key = (record.get("testName"), record["line"], record.get("module"), record.get("integration"), record.get("inputsDigest"))
            generations.setdefault(key, {})[record["outputName"]] = file_parts(record["content"], header, [])
    for key in sorted(generations, key=str):
        print(f"// {key[0]} line {key[1]} module {key[2]} integration {key[3]} inputs {str(key[4])[:8]}")
        print(indentation + value_source(generations[key], "files", indentation))
    return 0


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--records", required=True)
    parser.add_argument("--checkout", required=True)
    parser.add_argument("--report")
    parser.add_argument("--emit", help="print the files of the tests whose name holds this text, and change nothing")
    parser.add_argument("--tabs", type=int, default=2)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--only")
    parser.add_argument("--helpers-only", action="store_true", help="only rewrite comparisons whose expected side calls a helper, whole, from the records")
    arguments = parser.parse_args(argv)
    try:
        if arguments.emit:
            return emit(arguments)
        return migrate(arguments)
    except regenerator.ApplyError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
