#!/usr/bin/env python3
"""Usage: regenerate-expectations.py --write-manifest RECORD_DIR --checkout DIR
       regenerate-expectations.py --base-records DIR --head-records DIR --rules FILE --report DIR --checkout DIR
                                  [--dry-run] [--sample N]
       regenerate-expectations.py --self-test DIR

Rewrites the expected literals of SafeDITool's tests from what the test helpers recorded, and sorts every changed
expectation into one a change's predicted transform explains and one it does not. Run it with `python3 -I`.

Recording. `executeSafeDIToolTest`, `executeSafeDIToolMultiModuleTest`, `assertThrowsError(_:)`,
`assertThrowsError(diagnostics:)` and `assertThrowsMultiModuleError` write records into the directory the
SAFEDI_TEST_RECORD_DIRECTORY environment variable names (outside the checkout and the system temporary directory):
every output of a generation helper, and every mismatch of an assertion helper. Record twice, over the same Tests/:
  1. base records: a run on the old generator, such as the commit that adds a change's failing tests;
  2. head records: a run on the new generator.
After each run, write that directory's manifest of Tests/:
  python3 -I Scripts/regenerate-expectations.py --write-manifest RECORD_DIR --checkout .
SAFEDI_SKIP_COMPILE_CHECK=1 may skip compiles in a record run.

Applying. With both record directories, the change's rules file and an empty report directory:
  python3 -I Scripts/regenerate-expectations.py --base-records BASE --head-records HEAD --rules RULES.json \\
      --report REPORT --checkout .
A string literal is rewritten only when it equalled a base record exactly (or after `generatedFileHeader`), within
the test function whose call recorded it, or the test function at the location of the test the record carries
(`Test.current`'s source location, which names its file and line, so its suite too), as for a call made through a
helper function of any file (or anywhere in the file, for a literal outside every test function), or, for an
assertion record, when it is the literal the failing assertion call compared and it evaluates to the recorded
expected value. Its new value is the head record of the same key. An interpolated literal is matched as a pattern,
each `\\(…)` a capture, and an expression spelled twice capturing one value; one whose captures stand for more of
the output than its one-line text does, such as `"\\(self)"`, matches nothing. Each interpolation is put back only
where its captured text lies in a part of the output the change left alone, and otherwise the literal is left for a
person (manual). A literal whose value did not change is never touched. Then read every item the report lists, and
run the tests again without the variable, so compile verification checks the new expectations.

Rules file. JSON with three lists, each entry with a unique "name":
  "rename":    {"name", "table": {"old": "new", …}, "wordBoundaries": true|false}. Every rename of every rule is
               applied at once, as one alternation, longest key first, so renames never chain.
  "rewrite":   {"name", "pattern", "replacement", "flags": ["MULTILINE", "DOTALL", "IGNORECASE", "VERBOSE"]},
               Python regular expressions, applied in order to the old value after the renames.
  "normalize": {"name", "pattern", "replacement", "flags"}, applied to both sides, for opaque values such as a
               guard hash.
A changed literal is explained when normalize(rewrite(rename(old))) == normalize(new); otherwise the report shows
the residual difference of those two strings, which is what no rule predicts. A rules file whose pattern can match
the empty string, whose rename key is empty, or whose names repeat is rejected.

Report. REPORT/report.txt, in path and line order: counts, changed outputs no literal matched, each rule's hits,
unexplained residual diffs, manual items with their reasons, base records no literal matched, changed literals
whose call skipped compile verification, a sample of N explained literals (--sample, default 5), and how many test
functions and records were mapped. Two runs over the same inputs write the same bytes.

Exit status: 0 when every changed literal is explained; 1 when some are unexplained or manual (read the report).
An output that changed but matched no literal, such as one a test assembles from fragments or never compares,
is listed first in the report and leaves the status alone, since the script cannot tell whether a
test compares it. 2 on an error, with nothing written: the two manifests differ or the checkout's Tests/ differs
from them (as it does once the records are applied), a record's fileID names no single file under Tests/, a rule is
rejected, a rewrite fails its own check, or a file cannot be parsed. --dry-run writes the report and no test file.

--self-test DIR writes fixture checkouts, records and rules into DIR, which must not exist, and checks each case.
"""
import argparse
import difflib
import hashlib
import json
import os
import re
import sys

MANIFEST_NAME = "tests-manifest.json"
HEADER_NAME = "generated-file-header.txt"
UUID = r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
ASSERTION_FUNCTIONS = {
    "plain": "assertThrowsError",
    "diagnostics": "assertThrowsError",
    "multiModuleDiagnostics": "assertThrowsMultiModuleError",
}
MODIFIERS = {
    "public", "private", "fileprivate", "internal", "package", "open", "static", "class", "final", "mutating",
    "nonmutating", "override", "nonisolated", "convenience", "required", "dynamic", "isolated", "consuming",
    "borrowing", "async",
}
WRITTEN_FOR_THE_NEW_OUTPUT = "the head output matches a literal (a test written for the new output)"
# The placeholders `ExpectationRecording.PathNormalization` puts in place of run-specific paths. Keep in step with
# Tests/SafeDIToolTestSupport/ExpectationRecording.swift and its callers. A literal's own text can never spell one
# that a run fills in, so a rewrite that would write one outside an interpolation is left for a person.
RUN_PATH_PLACEHOLDER = re.compile(
    r"\$(?:TARGET_DIRECTORY|ADDITIONAL_DIRECTORY|OUTPUT_DIRECTORY|REPORTED_TARGET_DIRECTORY|REPORTED_PROJECT_ROOT"
    r"|FIXTURE_ROOT|TEST_TEMPORARY_DIRECTORY|FIXTURE_PARENT_DIRECTORY|CURRENT_DIRECTORY|RUN_DIRECTORY)(?![A-Z_])"
)


# The fewest characters other than whitespace an interpolated literal's own text must spell to match an output.
SHORTEST_ANCHOR = 8


def non_whitespace_count(text):
    return sum(1 for character in text if not character.isspace())


def placeholder_count(parts):
    """How many run-path placeholders the literal's own text spells."""
    return sum(len(RUN_PATH_PLACEHOLDER.findall(text)) for kind, text in parts if kind == "text")
# The longest changed region whose characters are aligned to place interpolations; a longer one is manual.
LONGEST_CHARACTER_ALIGNMENT = 20000


class ApplyError(Exception):
    """An error that stops the script with exit status 2 before it writes anything."""


class EncodeError(Exception):
    """A value a literal of its kind cannot spell."""


# MARK: Swift lexing


class StringLiteral:
    def __init__(self, source, start, end, hashes, multiline, parts, indentation):
        self.source = source
        self.start = start
        self.end = end
        self.hashes = hashes
        self.multiline = multiline
        # Each part is ("text", decoded text) or ("interpolation", expression source).
        self.parts = parts
        self.indentation = indentation
        # The lazy and greedy patterns `match_literal` matches an interpolated literal with, made on first use.
        self.patterns = None
        # The literal's texts joined, which is its value when it interpolates nothing.
        self.plain_text = "".join(text for kind, text in parts if kind == "text")
        self.interpolation_count = sum(1 for kind, _ in parts if kind == "interpolation")


class Token:
    def __init__(self, kind, text, start, end, literal=None):
        self.kind = kind
        self.text = text
        self.start = start
        self.end = end
        self.literal = literal


class SwiftParseError(Exception):
    pass


def is_identifier_start(character):
    return character == "_" or character == "$" or character.isalpha()


def is_identifier_character(character):
    return character == "_" or character == "$" or character.isalnum()


def skip_block_comment(source, index):
    """The index after the nested block comment that starts at `index`."""
    depth = 0
    while index < len(source):
        if source.startswith("/*", index):
            depth += 1
            index += 2
        elif source.startswith("*/", index):
            depth -= 1
            index += 2
            if depth == 0:
                return index
        else:
            index += 1
    raise SwiftParseError("unterminated block comment")


def string_literal_hashes(source, index):
    """The number of `#` of a string literal starting at `index`, or None when none starts there."""
    hashes = 0
    while index + hashes < len(source) and source[index + hashes] == "#":
        hashes += 1
    if index + hashes < len(source) and source[index + hashes] == '"':
        return hashes
    return None


def regex_literal_end(source, index):
    """The index after an extended regex literal (`#/…/#`, `##/…/##`) starting at `index`, or None when none starts
    there. Its content is no string, though it may hold quotation marks. A bare `/…/` regex literal is not
    recognized; a test file holding one whose content holds a quotation mark cannot be parsed."""
    hashes = 0
    while index + hashes < len(source) and source[index + hashes] == "#":
        hashes += 1
    if hashes == 0 or index + hashes >= len(source) or source[index + hashes] != "/":
        return None
    closing = source.find("/" + "#" * hashes, index + hashes + 1)
    if closing < 0:
        raise SwiftParseError("unterminated regex literal")
    return closing + 1 + hashes


def skip_expression(source, index):
    """The index of the `)` that closes an interpolation whose expression starts at `index`."""
    depth = 1
    while index < len(source):
        character = source[index]
        if source.startswith("//", index):
            newline = source.find("\n", index)
            index = len(source) if newline < 0 else newline
        elif source.startswith("/*", index):
            index = skip_block_comment(source, index)
        elif character in '#"' and string_literal_hashes(source, index) is not None:
            index = lex_string(source, index).end
        elif character == "#" and regex_literal_end(source, index) is not None:
            index = regex_literal_end(source, index)
        elif character == "(":
            depth += 1
            index += 1
        elif character == ")":
            depth -= 1
            if depth == 0:
                return index
            index += 1
        else:
            index += 1
    raise SwiftParseError("unterminated interpolation")


def lex_string(source, start):
    """The string literal that starts at `start`, decoded."""
    hashes = string_literal_hashes(source, start)
    index = start + hashes
    multiline = source.startswith('"""', index)
    closing = ('"""' if multiline else '"') + "#" * hashes
    escape = "\\" + "#" * hashes
    if multiline:
        index += 3
        newline = source.find("\n", index)
        if newline < 0 or source[index:newline].strip(" \t\r"):
            raise SwiftParseError("a multi-line string literal’s content must start on a new line")
        index = newline + 1
    else:
        index += 1
    content_start = index
    pieces = []  # ("text", start, end) or ("interpolation", start, end) source ranges
    text_start = index
    while True:
        if index >= len(source):
            raise SwiftParseError("unterminated string literal")
        if source.startswith(closing, index):
            if multiline:
                line_start = source.rfind("\n", 0, index) + 1
                if source[line_start:index].strip(" \t"):
                    index += 1
                    continue
            pieces.append(("text", text_start, index))
            content_end = index
            end = index + len(closing)
            break
        if not multiline and source[index] == "\n":
            raise SwiftParseError("unterminated string literal")
        if source.startswith(escape, index):
            after = index + len(escape)
            if after < len(source) and source[after] == "(":
                pieces.append(("text", text_start, index))
                expression_end = skip_expression(source, after + 1)
                pieces.append(("interpolation", after + 1, expression_end))
                index = expression_end + 1
                text_start = index
                continue
            index = after + 1
            continue
        index += 1
    indentation = ""
    if multiline:
        line_start = source.rfind("\n", 0, content_end) + 1
        indentation = source[line_start:content_end]
        # The newline before the closing delimiter's line ends the content.
        content_limit = max(content_start, line_start - 1)
        pieces = [(kind, piece_start, min(piece_end, content_limit)) for kind, piece_start, piece_end in pieces if piece_start < content_limit or (kind == "text" and piece_start == piece_end == content_start)]
    parts = decode_pieces(source, pieces, hashes, multiline, indentation)
    return StringLiteral(source, start, end, hashes, multiline, parts, indentation)


def decode_pieces(source, pieces, hashes, multiline, indentation):
    escape = "\\" + "#" * hashes
    parts = []
    at_line_start = multiline
    for kind, piece_start, piece_end in pieces:
        if kind == "interpolation":
            parts.append(("interpolation", source[piece_start:piece_end]))
            at_line_start = False
            continue
        text = []
        index = piece_start
        while index < piece_end:
            if at_line_start:
                at_line_start = False
                line_end = source.find("\n", index, piece_end)
                line_end = piece_end if line_end < 0 else line_end
                if source.startswith(indentation, index) and index + len(indentation) <= piece_end:
                    index += len(indentation)
                elif not source[index:line_end].strip(" \t"):
                    index = line_end
                else:
                    raise SwiftParseError("a line of a multi-line string literal is indented less than its closing delimiter")
                continue
            character = source[index]
            if character == "\n":
                text.append("\n")
                index += 1
                at_line_start = True
                continue
            if source.startswith(escape, index):
                index += len(escape)
                escaped = source[index] if index < len(source) else ""
                if multiline and escaped in " \t\n":
                    # A line continuation: the backslash, any spaces after it and the newline spell nothing.
                    newline = source.find("\n", index)
                    if newline < 0 or source[index:newline].strip(" \t"):
                        raise SwiftParseError("invalid escape in a string literal")
                    index = newline + 1
                    at_line_start = True
                    continue
                simple = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", "\\": "\\", '"': '"', "'": "'"}
                if escaped in simple:
                    text.append(simple[escaped])
                    index += 1
                elif escaped == "u" and source.startswith("{", index + 1):
                    closing = source.find("}", index + 2)
                    if closing < 0:
                        raise SwiftParseError("unterminated unicode escape")
                    text.append(chr(int(source[index + 2:closing], 16)))
                    index = closing + 1
                else:
                    raise SwiftParseError("invalid escape in a string literal")
                continue
            text.append(character)
            index += 1
        parts.append(("text", "".join(text)))
    merged = []
    for part in parts:
        if merged and part[0] == "text" and merged[-1][0] == "text":
            merged[-1] = ("text", merged[-1][1] + part[1])
        else:
            merged.append(part)
    if not merged or merged[0][0] != "text":
        merged.insert(0, ("text", ""))
    if merged[-1][0] != "text":
        merged.append(("text", ""))
    return merged


def tokenize(source):
    tokens = []
    index = 0
    while index < len(source):
        character = source[index]
        if character in " \t\r\n":
            index += 1
        elif source.startswith("//", index):
            newline = source.find("\n", index)
            index = len(source) if newline < 0 else newline
        elif source.startswith("/*", index):
            index = skip_block_comment(source, index)
        elif character in '#"' and string_literal_hashes(source, index) is not None:
            literal = lex_string(source, index)
            tokens.append(Token("string", source[index:literal.end], index, literal.end, literal))
            index = literal.end
        elif character == "#" and regex_literal_end(source, index) is not None:
            end = regex_literal_end(source, index)
            tokens.append(Token("regex", source[index:end], index, end))
            index = end
        elif character == "`":
            closing = source.find("`", index + 1)
            if closing < 0:
                raise SwiftParseError("unterminated escaped identifier")
            tokens.append(Token("identifier", source[index + 1:closing], index, closing + 1))
            index = closing + 1
        elif is_identifier_start(character):
            end = index + 1
            while end < len(source) and is_identifier_character(source[end]):
                end += 1
            tokens.append(Token("identifier", source[index:end], index, end))
            index = end
        elif character.isdigit():
            end = index + 1
            while end < len(source) and (source[end].isalnum() or source[end] in "._"):
                end += 1
            tokens.append(Token("number", source[index:end], index, end))
            index = end
        else:
            tokens.append(Token("punctuation", character, index, index + 1))
            index += 1
    return tokens


class SwiftFile:
    """A test source file: its tokens, string literals and functions."""

    def __init__(self, path, relative_path, source):
        self.path = path
        self.relative_path = relative_path
        self.source = source
        try:
            self.tokens = tokenize(source)
        except SwiftParseError as error:
            raise ApplyError(f"cannot parse {relative_path}: {error}")
        self.line_starts = [0] + [index + 1 for index, character in enumerate(source) if character == "\n"]
        self.matching = self._match_brackets()
        self.functions = self._functions()
        self.literals = [token.literal for token in self.tokens if token.kind == "string"]

    def line_of(self, offset):
        low, high = 0, len(self.line_starts)
        while high - low > 1:
            middle = (low + high) // 2
            if self.line_starts[middle] <= offset:
                low = middle
            else:
                high = middle
        return low + 1

    def _match_brackets(self):
        matching = {}
        stack = []
        pairs = {")": "(", "]": "[", "}": "{"}
        for position, token in enumerate(self.tokens):
            if token.kind != "punctuation":
                continue
            if token.text in "([{":
                stack.append(position)
            elif token.text in ")]}":
                if not stack or self.tokens[stack[-1]].text != pairs[token.text]:
                    raise ApplyError(f"cannot parse {self.relative_path}: unbalanced {token.text} on line {self.line_of(token.start)}")
                opening = stack.pop()
                matching[opening] = position
                matching[position] = opening
        if stack:
            raise ApplyError(f"cannot parse {self.relative_path}: unbalanced {self.tokens[stack[-1]].text}")
        return matching

    def _test_attribute_line(self, function_position):
        """The line of the first attribute of the function whose `func` is at `function_position`, when `@Test` is among
        its attributes, else None. Swift Testing locates a test at its `@Test` attribute."""
        position = function_position - 1
        first_line = None
        is_test = False
        while position >= 0:
            token = self.tokens[position]
            if token.kind == "identifier" and token.text in MODIFIERS:
                first_line = self.line_of(token.start)
                position -= 1
            elif token.kind == "punctuation" and token.text == ")" and position in self.matching:
                opening = self.matching[position]
                if opening >= 2 and self.tokens[opening - 1].kind == "identifier" and self.tokens[opening - 2].text == "@":
                    is_test = is_test or self.tokens[opening - 1].text == "Test"
                    first_line = self.line_of(self.tokens[opening - 2].start)
                    position = opening - 3
                elif opening >= 1 and self.tokens[opening - 1].kind == "identifier" and self.tokens[opening - 1].text in MODIFIERS:
                    # `private(set)` and the like.
                    first_line = self.line_of(self.tokens[opening - 1].start)
                    position = opening - 2
                else:
                    break
            elif token.kind == "identifier" and position >= 1 and self.tokens[position - 1].text == "@":
                is_test = is_test or token.text == "Test"
                first_line = self.line_of(self.tokens[position - 1].start)
                position -= 2
            else:
                break
        return first_line if is_test else None

    def _functions(self):
        """Each function with a body: (first line, last line, body start offset, body end offset, is a test, the line
        of its first attribute when it is a test)."""
        functions = []
        for position, token in enumerate(self.tokens):
            if token.kind != "identifier" or token.text != "func":
                continue
            depth = 0
            body = None
            for later in range(position + 1, len(self.tokens)):
                candidate = self.tokens[later]
                if candidate.kind == "punctuation" and candidate.text in "([":
                    depth += 1
                elif candidate.kind == "punctuation" and candidate.text in ")]":
                    depth -= 1
                elif depth == 0 and candidate.kind == "punctuation" and candidate.text == "{":
                    body = later
                    break
                elif depth == 0 and (candidate.text == "}" or (candidate.kind == "identifier" and candidate.text in ("func", "var", "let", "init", "struct", "class", "enum", "extension"))):
                    break
            if body is None:
                continue
            closing = self.tokens[self.matching[body]]
            attribute_line = self._test_attribute_line(position)
            functions.append((self.line_of(token.start), self.line_of(closing.end - 1), self.tokens[body].start, closing.end, attribute_line is not None, attribute_line))
        return functions

    def test_function_of_offset(self, offset):
        """The outermost test function whose body holds `offset`, or None."""
        for function in self.functions:
            if function[4] and function[2] <= offset < function[3]:
                return function
        return None

    def test_function_declared_at(self, line):
        """The outermost test function whose attributes or body hold `line`, as Swift Testing's location of a test does."""
        for function in self.functions:
            if function[4] and function[5] <= line <= function[1]:
                return function
        return None

    def test_function_of_line(self, line):
        for function in self.functions:
            if function[4] and function[0] <= line <= function[1]:
                return function
        return None


# MARK: Encoding literals


def escape_text(text, literal):
    hashes = literal.hashes
    output = []
    quote_run = 0
    for character in text:
        if hashes:
            output.append(character)
            continue
        if character == "\\":
            output.append("\\\\")
            quote_run = 0
        elif character == '"':
            if not literal.multiline or quote_run == 2:
                output.append('\\"')
                quote_run = 0
            else:
                output.append('"')
                quote_run += 1
        elif character == "\t" and not literal.multiline:
            output.append("\\t")
            quote_run = 0
        elif character == "\n" and not literal.multiline:
            output.append("\\n")
            quote_run = 0
        elif character == "\r":
            output.append("\\r")
            quote_run = 0
        elif character == "\0":
            output.append("\\0")
            quote_run = 0
        elif ord(character) < 0x20 and character != "\t":
            output.append("\\u{%X}" % ord(character))
            quote_run = 0
        else:
            output.append(character)
            quote_run = 0
    spelled = "".join(output)
    if hashes:
        delimiter = '"' + "#" * hashes
        escape = "\\" + "#" * hashes
        if escape in spelled or (delimiter in spelled and not literal.multiline) or ('"""' + "#" * hashes) in spelled:
            raise EncodeError("a raw string literal cannot spell this value")
        if any(ord(character) < 0x20 and character not in "\t" for character in spelled):
            raise EncodeError("a raw string literal cannot spell a control character")
    return spelled


def encode_literal(literal, parts):
    """The source of a literal of `literal`'s kind and indentation whose parts are `parts`."""
    hashes = "#" * literal.hashes
    escape = "\\" + hashes
    if not literal.multiline:
        body = []
        for kind, value in parts:
            if kind == "text":
                if "\n" in value and literal.hashes:
                    raise EncodeError("a raw single-line literal cannot spell a newline")
                body.append(escape_text(value, literal))
            else:
                body.append(f"{escape}({value})")
        return f'{hashes}"{"".join(body)}"{hashes}'
    lines = [[]]
    for kind, value in parts:
        if kind == "text":
            segments = value.split("\n")
            for index, segment in enumerate(segments):
                if index > 0:
                    lines.append([])
                if segment:
                    lines[-1].append(escape_text(segment, literal))
        else:
            lines[-1].append(f"{escape}({value})")
    output = [f'{hashes}"""\n']
    for line in lines:
        spelled = "".join(line)
        output.append((literal.indentation + spelled if spelled else "") + "\n")
    output.append(f'{literal.indentation}"""{hashes}')
    return "".join(output)


def decode_source(source):
    tokens = [token for token in tokenize(source) if token.kind == "string"]
    if len(tokens) != 1:
        raise SwiftParseError("expected one literal")
    return tokens[0].literal.parts


def normalized_parts(parts):
    merged = []
    for part in parts:
        if merged and part[0] == "text" and merged[-1][0] == "text":
            merged[-1] = ("text", merged[-1][1] + part[1])
        elif part != ("text", "") or not merged:
            merged.append(part)
    if not merged or merged[0][0] != "text":
        merged.insert(0, ("text", ""))
    if merged[-1][0] != "text":
        merged.append(("text", ""))
    return merged


def checked_encoding(literal, parts):
    """`encode_literal`'s source, after checking that it decodes to `parts`."""
    source = encode_literal(literal, parts)
    try:
        decoded = decode_source(literal.indentation + "_ = " + source if literal.multiline else source)
    except SwiftParseError as error:
        raise ApplyError(f"a rewritten literal does not parse: {error}")
    if normalized_parts(decoded) != normalized_parts(parts):
        raise ApplyError("a rewritten literal does not decode to its new value")
    return source


# MARK: Matching


def literal_pattern(parts):
    """The lazy and greedy patterns of an interpolated literal. Each interpolation is a numbered group, so group N is
    the Nth interpolation; an expression spelled again must capture what it captured first, as it evaluates alike."""

    def pattern(wildcard):
        expression = []
        first_group_by_expression = {}
        for kind, value in parts:
            if kind == "text":
                expression.append(re.escape(value))
            elif value in first_group_by_expression:
                expression.append(f"((?P=first{first_group_by_expression[value]}))")
            else:
                first_group_by_expression[value] = len(first_group_by_expression)
                expression.append(f"(?P<first{first_group_by_expression[value]}>{wildcard})")
        return re.compile("".join(expression), re.DOTALL)

    return pattern(".*?"), pattern(".*")


def match_literal(literal, content, header):
    """How `content` matches `literal`: (mode, body, capture spans, ambiguous), or None. `mode` is "whole" or
    "header", the latter when the literal is the content after `generatedFileHeader`."""
    candidates = [("whole", content)]
    if header and content.startswith(header):
        candidates.append(("header", content[len(header):]))
    for mode, body in candidates:
        if literal.interpolation_count == 0:
            if literal.plain_text == body and (body or mode == "whole") and content:
                return mode, body, [], False
            continue
        first, last = literal.parts[0][1], literal.parts[-1][1]
        if not body.startswith(first) or not body.endswith(last) or len(body) < len(first) + len(last):
            continue
        # Each of the literal's texts must appear in order before the regular expressions run, which is far faster.
        position = len(first)
        for kind, text in literal.parts[1:-1]:
            if kind == "text" and text:
                position = body.find(text, position)
                if position < 0:
                    break
                position += len(text)
        if position < 0 or position > len(body) - len(last):
            continue
        if literal.patterns is None:
            literal.patterns = literal_pattern(literal.parts)
        lazy, greedy = literal.patterns
        lazy_match = lazy.fullmatch(body)
        if lazy_match is None:
            continue
        greedy_match = greedy.fullmatch(body)
        spans = [lazy_match.span(group) for group in range(1, lazy.groups + 1)]
        # A literal whose own text spells little, or less than its interpolations stand for, such as `"\(self)"` or
        # `"\(a)\n\(b)"`, matches outputs it was never written for, so it proves nothing. Only characters other than
        # whitespace count, so line breaks and indentation anchor nothing.
        anchor = non_whitespace_count(literal.plain_text)
        captured = sum(non_whitespace_count(body[start:end]) for start, end in spans)
        if anchor < SHORTEST_ANCHOR or captured > anchor:
            continue
        greedy_spans = [greedy_match.span(group) for group in range(1, greedy.groups + 1)]
        return mode, body, spans, spans != greedy_spans
    return None


def map_spans(old, new, spans):
    """Each span of `old`, moved to where the same text lies in `new`, or None when a span lies in a part the change
    touched."""
    old_lines = old.splitlines(keepends=True)
    new_lines = new.splitlines(keepends=True)
    old_offsets = [0]
    for line in old_lines:
        old_offsets.append(old_offsets[-1] + len(line))
    new_offsets = [0]
    for line in new_lines:
        new_offsets.append(new_offsets[-1] + len(line))
    equal_blocks = []  # (old start, old end, new start)
    matcher = difflib.SequenceMatcher(None, old_lines, new_lines, autojunk=False)
    for tag, old_first, old_last, new_first, new_last in matcher.get_opcodes():
        old_start, old_end = old_offsets[old_first], old_offsets[old_last]
        new_start, new_end = new_offsets[new_first], new_offsets[new_last]
        if tag == "equal":
            equal_blocks.append((old_start, old_end, new_start))
        elif tag == "replace" and any(old_start <= span_start and span_end <= old_end for span_start, span_end in spans):
            if old_end - old_start > LONGEST_CHARACTER_ALIGNMENT or new_end - new_start > LONGEST_CHARACTER_ALIGNMENT:
                continue
            characters = difflib.SequenceMatcher(None, old[old_start:old_end], new[new_start:new_end], autojunk=False)
            for block in characters.get_matching_blocks():
                if block.size:
                    equal_blocks.append((old_start + block.a, old_start + block.a + block.size, new_start + block.b))
    mapped = []
    for span_start, span_end in spans:
        for block_start, block_end, new_start in equal_blocks:
            if block_start <= span_start and span_end <= block_end and (span_start < block_end or span_start == span_end):
                mapped.append((new_start + span_start - block_start, new_start + span_end - block_start))
                break
        else:
            return None
    for (previous_start, previous_end), (next_start, next_end) in zip(mapped, mapped[1:]):
        if next_start < previous_end:
            return None
    for (old_start, old_end), (new_start, new_end) in zip(spans, mapped):
        if old[old_start:old_end] != new[new_start:new_end]:
            return None
    return mapped


def rebuilt_parts(literal, new_body, mapped_spans):
    expressions = [value for kind, value in literal.parts if kind == "interpolation"]
    parts = []
    position = 0
    for expression, (start, end) in zip(expressions, mapped_spans):
        parts.append(("text", new_body[position:start]))
        parts.append(("interpolation", expression))
        position = end
    parts.append(("text", new_body[position:]))
    return parts


# MARK: Rules


FLAG_NAMES = {"IGNORECASE": re.IGNORECASE, "MULTILINE": re.MULTILINE, "DOTALL": re.DOTALL, "VERBOSE": re.VERBOSE}


class Rules:
    def __init__(self, document):
        if not isinstance(document, dict) or set(document) - {"rename", "rewrite", "normalize"}:
            raise ApplyError("the rules file must be an object of `rename`, `rewrite` and `normalize` lists")
        names = []
        self.rename_rules = []
        self.rewrite_rules = []
        self.normalize_rules = []
        rename_value_by_key = {}
        rule_by_key = {}
        word_boundary_by_key = {}
        for entry in document.get("rename", []):
            name = self._name(entry, names)
            table = entry.get("table")
            if not isinstance(table, dict) or not table:
                raise ApplyError(f"rename rule {name} needs a non-empty table")
            for key, value in table.items():
                if not key:
                    raise ApplyError(f"rename rule {name} has an empty key")
                if key in rename_value_by_key and rename_value_by_key[key] != value:
                    raise ApplyError(f"rename rules {rule_by_key[key]} and {name} rename {key} differently")
                rename_value_by_key[key] = value
                rule_by_key[key] = name
                word_boundary_by_key[key] = bool(entry.get("wordBoundaries", False))
            self.rename_rules.append(name)
        self.rename_value_by_key = rename_value_by_key
        self.rename_rule_by_key = rule_by_key
        if rename_value_by_key:
            alternatives = []
            for key in sorted(rename_value_by_key, key=lambda key: (-len(key), key)):
                alternative = re.escape(key)
                if word_boundary_by_key[key]:
                    alternative = r"(?<![A-Za-z0-9_])" + alternative + r"(?![A-Za-z0-9_])"
                alternatives.append(alternative)
            self.rename_expression = re.compile("|".join(alternatives))
        else:
            self.rename_expression = None
        for list_name, destination in (("rewrite", self.rewrite_rules), ("normalize", self.normalize_rules)):
            for entry in document.get(list_name, []):
                name = self._name(entry, names)
                pattern = entry.get("pattern")
                replacement = entry.get("replacement")
                if not isinstance(pattern, str) or not isinstance(replacement, str):
                    raise ApplyError(f"{list_name} rule {name} needs a pattern and a replacement")
                flags = 0
                for flag in entry.get("flags", []):
                    if flag not in FLAG_NAMES:
                        raise ApplyError(f"{list_name} rule {name} names an unknown flag {flag}")
                    flags |= FLAG_NAMES[flag]
                try:
                    expression = re.compile(pattern, flags)
                except re.error as error:
                    raise ApplyError(f"{list_name} rule {name} does not compile: {error}")
                if expression.search("") is not None:
                    raise ApplyError(f"{list_name} rule {name} can match the empty string")
                # Expand the replacement against an empty match with the pattern's groups, so a reference to a group
                # the pattern lacks is rejected now rather than on the rule's first hit.
                group_names = {index: group_name for group_name, index in expression.groupindex.items()}
                groups = "".join(f"(?P<{group_names[index]}>)" if index in group_names else "()" for index in range(1, expression.groups + 1))
                try:
                    re.compile(groups).fullmatch("").expand(replacement)
                except (re.error, IndexError) as error:
                    # An unknown group name raises `IndexError`, an unknown group number `re.error`.
                    raise ApplyError(f"{list_name} rule {name} has an invalid replacement: {error}")
                destination.append((name, expression, replacement))
        self.names = names

    @staticmethod
    def _name(entry, names):
        name = entry.get("name") if isinstance(entry, dict) else None
        if not isinstance(name, str) or not name:
            raise ApplyError("every rule needs a name")
        if name in names:
            raise ApplyError(f"two rules are named {name}")
        names.append(name)
        return name

    @staticmethod
    def _substitute(expression, replacement, text, name):
        hits = 0

        def replace(match):
            nonlocal hits
            if match.end() == match.start():
                raise ApplyError(f"rule {name} matched the empty string")
            hits += 1
            try:
                return match.expand(replacement)
            except (re.error, IndexError) as error:
                raise ApplyError(f"rule {name} has an invalid replacement: {error}")

        return expression.sub(replace, text), hits

    def normalize(self, text):
        for name, expression, replacement in self.normalize_rules:
            text, _ = self._substitute(expression, replacement, text, name)
        return text

    def predict(self, old, hits):
        """`old` after every rename and rewrite, counting each rule's hits in `hits`."""
        text = old
        if self.rename_expression is not None:
            def rename(match):
                key = match.group(0)
                hits[self.rename_rule_by_key[key]] = hits.get(self.rename_rule_by_key[key], 0) + 1
                return self.rename_value_by_key[key]

            text = self.rename_expression.sub(rename, text)
        for name, expression, replacement in self.rewrite_rules:
            text, count = self._substitute(expression, replacement, text, name)
            hits[name] = hits.get(name, 0) + count
        return text

    def classify(self, old, new, hits):
        """None when the rules explain old → new, else the residual diff."""
        predicted = self.normalize(self.predict(old, hits))
        actual = self.normalize(new)
        if predicted == actual:
            return None
        return residual_diff(predicted, actual)


def residual_diff(expected, actual, labels=("predicted", "actual")):
    def lines(text):
        split = text.splitlines(keepends=True)
        if split and not split[-1].endswith("\n"):
            split[-1] += "\n"
        return split

    diff = "".join(difflib.unified_diff(lines(expected), lines(actual), labels[0], labels[1], n=1))
    if not diff and expected != actual:
        diff = f"--- {labels[0]}\n+++ {labels[1]}\n(the two differ only in a final newline or in line endings)\n"
    return diff


def change_diff(old, new):
    """The difference between what a literal expected and what it expects now."""
    return residual_diff(old, new, ("base", "head"))


# MARK: Records and manifests


def tests_manifest(checkout):
    tests = os.path.join(checkout, "Tests")
    files = {}
    for directory, directory_names, file_names in os.walk(tests):
        directory_names.sort()
        for file_name in sorted(file_names):
            path = os.path.join(directory, file_name)
            with open(path, "rb") as test_file:
                files[os.path.relpath(path, checkout).replace(os.sep, "/")] = hashlib.sha256(test_file.read()).hexdigest()
    return {"files": files}


def write_manifest(record_directory, checkout):
    if not os.path.isdir(record_directory):
        raise ApplyError(f"{record_directory} is not a directory")
    with open(os.path.join(record_directory, MANIFEST_NAME), "w", encoding="utf-8") as manifest_file:
        json.dump(tests_manifest(checkout), manifest_file, indent=1, sort_keys=True)
        manifest_file.write("\n")


def read_manifest(record_directory):
    path = os.path.join(record_directory, MANIFEST_NAME)
    if not os.path.exists(path):
        raise ApplyError(f"{record_directory} has no {MANIFEST_NAME}: run --write-manifest after recording")
    with open(path, encoding="utf-8") as manifest_file:
        return json.load(manifest_file)


def manifest_difference(first, second):
    names = sorted(set(first["files"]) ^ set(second["files"]) | {name for name in set(first["files"]) & set(second["files"]) if first["files"][name] != second["files"][name]})
    return names


def read_records(record_directory):
    records = []
    for file_name in sorted(os.listdir(record_directory)):
        if not file_name.endswith(".json") or file_name == MANIFEST_NAME:
            continue
        with open(os.path.join(record_directory, file_name), encoding="utf-8") as record_file:
            record = json.load(record_file)
        if record.get("kind") not in ("generation", "assertion"):
            raise ApplyError(f"{file_name} is not a record")
        records.append(record)
    return records


def read_header(*record_directories):
    headers = set()
    for record_directory in record_directories:
        path = os.path.join(record_directory, HEADER_NAME)
        if os.path.exists(path):
            with open(path, encoding="utf-8") as header_file:
                headers.add(header_file.read())
    if len(headers) > 1:
        raise ApplyError("the record directories hold different generated-file headers")
    return headers.pop() if headers else ""


class FileResolver:
    def __init__(self, checkout):
        self.checkout = checkout
        self.paths_by_name = {}
        for directory, directory_names, file_names in os.walk(os.path.join(checkout, "Tests")):
            directory_names.sort()
            for file_name in sorted(file_names):
                if file_name.endswith(".swift"):
                    relative = os.path.relpath(os.path.join(directory, file_name), checkout).replace(os.sep, "/")
                    self.paths_by_name.setdefault(file_name, []).append(relative)

    def resolve(self, file_id):
        module, _, file_name = file_id.rpartition("/")
        candidates = [path for path in self.paths_by_name.get(file_name, []) if module in path.split("/")[:-1]]
        if len(candidates) != 1:
            raise ApplyError(f"the fileID {file_id} names {len(candidates)} files under Tests/: {', '.join(candidates) or 'none'}")
        return candidates[0]


# MARK: Applying


class LiteralOutcome:
    def __init__(self, swift_file, literal):
        self.swift_file = swift_file
        self.literal = literal
        self.matches = []  # (record, mode, old body, spans, ambiguous, head body or None, test name)
        self.line = swift_file.line_of(literal.start)


def find_assertion_literal(swift_file, record):
    """The literal an assertion call compared, or a reason it has none."""
    name = ASSERTION_FUNCTIONS.get(record.get("overload"))
    calls = [position for position, token in enumerate(swift_file.tokens) if token.kind == "identifier" and token.text == name and swift_file.line_of(token.start) == record["line"]]
    if len(calls) != 1 or calls[0] + 1 >= len(swift_file.tokens) or swift_file.tokens[calls[0] + 1].text != "(":
        return None, "no single assertion call at the recorded line"
    opening = calls[0] + 1
    closing = swift_file.matching[opening]
    arguments = []
    current = []
    position = opening + 1
    while position < closing:
        token = swift_file.tokens[position]
        if token.kind == "punctuation" and token.text in "([{":
            current.extend(swift_file.tokens[position:swift_file.matching[position] + 1])
            position = swift_file.matching[position] + 1
            continue
        if token.kind == "punctuation" and token.text == ",":
            arguments.append(current)
            current = []
        else:
            current.append(token)
        position += 1
    if current:
        arguments.append(current)
    if record["overload"] == "plain":
        if not arguments or (len(arguments[0]) >= 2 and arguments[0][1].text == ":"):
            return None, "non-literal expected value"
        value = arguments[0]
    else:
        labeled = [argument for argument in arguments if len(argument) >= 2 and argument[0].text == "diagnostics" and argument[1].text == ":"]
        if len(labeled) != 1:
            return None, "non-literal expected value"
        closure = labeled[0][2:]
        if len(closure) < 3 or closure[0].text != "{" or closure[-1].text != "}":
            return None, "non-literal expected value"
        body = closure[1:-1]
        in_positions = [index for index, token in enumerate(body) if token.kind == "identifier" and token.text == "in"]
        if in_positions:
            body = body[in_positions[0] + 1:]
        if body and body[0].kind == "identifier" and body[0].text == "return":
            body = body[1:]
        value = body
    if len(value) != 1 or value[0].kind != "string":
        return None, "non-literal expected value"
    return value[0].literal, None


def apply(arguments):
    """Applies the head records and writes the report. Returns (exit status, summary)."""
    with open(arguments.rules, encoding="utf-8") as rules_file:
        try:
            rules = Rules(json.load(rules_file))
        except json.JSONDecodeError as error:
            raise ApplyError(f"the rules file is not JSON: {error}")
    base_manifest = read_manifest(arguments.base_records)
    head_manifest = read_manifest(arguments.head_records)
    difference = manifest_difference(base_manifest, head_manifest)
    if difference:
        raise ApplyError("the base and head records were made over different Tests/: " + ", ".join(difference[:5]))
    difference = manifest_difference(base_manifest, tests_manifest(arguments.checkout))
    if difference:
        raise ApplyError("the checkout’s Tests/ changed since recording: " + ", ".join(difference[:5]))
    header = read_header(arguments.base_records, arguments.head_records)
    base_records = read_records(arguments.base_records)
    head_records = read_records(arguments.head_records)
    head_by_key = {record["key"]: record for record in head_records}
    base_keys = {record["key"] for record in base_records}
    resolver = FileResolver(arguments.checkout)
    files = {}

    def swift_file(file_id):
        relative_path = resolver.resolve(file_id)
        if relative_path not in files:
            path = os.path.join(arguments.checkout, relative_path)
            with open(path, encoding="utf-8") as source_file:
                files[relative_path] = SwiftFile(path, relative_path, source_file.read())
        return files[relative_path]

    base_generation = [record for record in base_records if record["kind"] == "generation"]
    head_assertions = [record for record in head_records if record["kind"] == "assertion"]
    for record in base_generation + head_assertions:
        swift_file(record["fileID"])

    outcomes = {}  # (path, literal start) → LiteralOutcome
    records_by_file = {}
    for record in base_generation:
        records_by_file.setdefault(resolver.resolve(record["fileID"]), []).append(record)
    # A record names the test that made its call (`Test.current`'s location). A call made through a helper function
    # records the helper's line, so the test's location is what ties it to the literal the test compares.
    records_by_test_file = {}
    for record in base_generation:
        if record.get("testFileID") and record.get("testLine"):
            records_by_test_file.setdefault(resolver.resolve(record["testFileID"]), []).append(record)
    for relative_path in sorted(records_by_test_file):
        if relative_path not in files:
            path = os.path.join(arguments.checkout, relative_path)
            with open(path, encoding="utf-8") as source_file:
                files[relative_path] = SwiftFile(path, relative_path, source_file.read())
    mapped_record_keys = set()
    for relative_path in sorted(set(records_by_file) | set(records_by_test_file)):
        current = files[relative_path]
        file_records = records_by_file.get(relative_path, [])
        records_by_function = {}
        for record in file_records:
            records_by_function.setdefault(current.test_function_of_line(record["line"]), {})[record["key"]] = record
        for record in records_by_test_file.get(relative_path, []):
            function = current.test_function_declared_at(record["testLine"])
            if function is not None:
                records_by_function.setdefault(function, {})[record["key"]] = record
        for literal in current.literals:
            function = current.test_function_of_offset(literal.start)
            if function is None:
                candidates = file_records
            else:
                candidates = [records_by_function.get(function, {})[key] for key in sorted(records_by_function.get(function, {}))]
            for record in candidates:
                matched = match_literal(literal, record["content"], header)
                if matched is None:
                    continue
                mode, body, spans, ambiguous = matched
                outcome = outcomes.setdefault((relative_path, literal.start), LiteralOutcome(current, literal))
                head = head_by_key.get(record["key"])
                head_body = None
                if head is not None:
                    if mode == "header":
                        head_body = head["content"][len(header):] if head["content"].startswith(header) else False
                    else:
                        head_body = head["content"]
                outcome.matches.append((record, mode, body, spans, ambiguous, head_body, record.get("testName", "")))
                mapped_record_keys.add(record["key"])
    unmapped_reasons = {}
    for relative_path in sorted(records_by_file):
        current = files[relative_path]
        for record in records_by_file[relative_path]:
            if record["key"] in mapped_record_keys:
                continue
            head = head_by_key.get(record["key"])
            reason = None
            if current.test_function_of_line(record["line"]) is None:
                reason = "call site outside every test function"
            if head is not None and head["content"] != record["content"]:
                function = current.test_function_of_line(record["line"])
                for literal in current.literals:
                    literal_function = current.test_function_of_offset(literal.start)
                    if literal_function in (None, function) and match_literal(literal, head["content"], header) is not None:
                        reason = WRITTEN_FOR_THE_NEW_OUTPUT
                        break
            unmapped_reasons[record["key"]] = (relative_path, record, reason)

    assertion_outcomes = []
    for record in sorted(head_assertions, key=lambda record: (resolver.resolve(record["fileID"]), record["line"], record["key"])):
        relative_path = resolver.resolve(record["fileID"])
        current = files[relative_path]
        literal, reason = find_assertion_literal(current, record)
        if literal is None:
            assertion_outcomes.append((relative_path, record, reason))
            continue
        if record["key"] in base_keys:
            assertion_outcomes.append((relative_path, record, "already failing on the base"))
            continue
        matched = match_literal(literal, record["expected"], "")
        if matched is None:
            assertion_outcomes.append((relative_path, record, "the literal does not evaluate to the recorded expected value"))
            continue
        _, body, spans, ambiguous = matched
        outcome = outcomes.setdefault((relative_path, literal.start), LiteralOutcome(current, literal))
        outcome.matches.append((record, "whole", body, spans, ambiguous, record["actual"], record.get("testName", "")))

    hits = {}
    edits = {}  # path → [(start, end, source)]
    explained, unexplained, manual, no_head = [], [], [], []
    for key in sorted(outcomes):
        outcome = outcomes[key]
        literal = outcome.literal
        relative_path = outcome.swift_file.relative_path
        test_names = sorted({match[6] for match in outcome.matches})
        changes = [match for match in outcome.matches if match[5] is not None and match[5] is not False and match[5] != match[2]]
        if any(match[5] is None for match in outcome.matches):
            no_head.append((relative_path, outcome.line, test_names))
        if any(match[5] is False for match in outcome.matches):
            manual.append((relative_path, outcome.line, test_names, "the head output no longer starts with the generated file header", None))
            continue
        if not changes:
            continue
        sources = set()
        reason = None
        detail = None
        for record, mode, body, spans, ambiguous, head_body, _ in outcome.matches:
            if head_body is None:
                continue
            if literal.interpolation_count and ambiguous:
                reason, detail = "ambiguous interpolation captures", change_diff(body, head_body)
                break
            if head_body == body:
                sources.add(literal.source[literal.start:literal.end])
                continue
            mapped = map_spans(body, head_body, spans) if literal.interpolation_count else []
            if mapped is None:
                reason, detail = "interpolation in a changed region", change_diff(body, head_body)
                break
            parts = rebuilt_parts(literal, head_body, mapped)
            if placeholder_count(parts) > placeholder_count(literal.parts):
                reason, detail = "the new value names a run directory outside its interpolations", change_diff(body, head_body)
                break
            try:
                sources.add(checked_encoding(literal, parts))
            except EncodeError as error:
                reason, detail = f"the new value cannot be spelled: {error}", change_diff(body, head_body)
                break
        if reason is None and len(sources) > 1:
            reason, detail = "records that map to this literal disagree on its new value", None
        if reason is not None:
            manual.append((relative_path, outcome.line, test_names, reason, detail))
            continue
        source = sources.pop()
        edits.setdefault(relative_path, []).append((literal.start, literal.end, source))
        residuals = []
        for record, mode, body, spans, ambiguous, head_body, _ in changes:
            residual = rules.classify(body, head_body, hits)
            if residual is not None:
                residuals.append(residual)
        skips_compile = any(match[0].get("skipsCompileVerification") for match in changes)
        item = (relative_path, outcome.line, test_names, residuals[0] if residuals else change_diff(changes[0][2], changes[0][5]), skips_compile)
        (unexplained if residuals else explained).append(item)

    # A base record whose output changed but that no literal matched leaves its test failing, unless a literal already
    # expects the new output.
    changed_without_literal = sorted(
        (relative_path, record["line"], record.get("testName", ""), record["outputName"], record.get("module"), record.get("integration"))
        for key, (relative_path, record, reason) in unmapped_reasons.items()
        if reason != WRITTEN_FOR_THE_NEW_OUTPUT and key in head_by_key and head_by_key[key]["content"] != record["content"]
    )
    summary = {
        "rewritten": len(explained) + len(unexplained),
        "explained": len(explained),
        "unexplained": len(unexplained),
        "manual": len(manual) + sum(1 for outcome in assertion_outcomes if outcome[2] is not None),
        "changedWithoutLiteral": len(changed_without_literal),
        "hits": {name: hits.get(name, 0) for name in rules.names},
    }
    if not arguments.dry_run:
        for relative_path in sorted(edits):
            current = files[relative_path]
            source = current.source
            for start, end, replacement in sorted(edits[relative_path], reverse=True):
                source = source[:start] + replacement + source[end:]
            with open(current.path, "w", encoding="utf-8") as source_file:
                source_file.write(source)
    write_report(arguments, rules, summary, explained, unexplained, manual, assertion_outcomes, no_head, unmapped_reasons, changed_without_literal, base_generation, mapped_record_keys, outcomes, resolver)
    summary["manualReasons"] = sorted(item[3] for item in manual) + sorted(outcome[2] for outcome in assertion_outcomes if outcome[2] is not None)
    status = 0 if not unexplained and summary["manual"] == 0 else 1
    return status, summary


def write_report(arguments, rules, summary, explained, unexplained, manual, assertion_outcomes, no_head, unmapped_reasons, changed_without_literal, base_generation, mapped_record_keys, outcomes, resolver):
    lines = []
    lines.append("Expectation regeneration report")
    lines.append("")
    lines.append(f"Literals rewritten: {summary['rewritten']}")
    lines.append(f"Explained by the rules: {summary['explained']}")
    lines.append(f"Unexplained (read each residual diff): {summary['unexplained']}")
    lines.append(f"Manual (not rewritten): {summary['manual']}")
    lines.append(f"Changed outputs no literal matched (read the list below): {summary['changedWithoutLiteral']}")
    lines.append("")
    lines.append("Changed outputs no literal matched: a test that compares one still fails, so update it by hand")
    counts = {}
    for relative_path, line, test_name, output_name, module, integration in changed_without_literal:
        entry = f"{relative_path}:{line} ({test_name}) {output_name}" + (f" [{module}, {integration}]" if module else "")
        counts[entry] = counts.get(entry, 0) + 1
    for entry in counts:
        lines.append(f"  {entry}" + (f" ({counts[entry]} records)" if counts[entry] > 1 else ""))
    lines.append("")
    lines.append("Rule hits")
    for name in rules.names:
        count = summary["hits"][name]
        lines.append(f"  {name}: {count}" + ("  (fired nowhere)" if count == 0 else ""))
    lines.append("")
    lines.append("Unexplained literals: the residual diff of predicted and actual, after normalizing")
    for relative_path, line, test_names, residual, _ in unexplained:
        lines.append(f"--- {relative_path}:{line} ({', '.join(test_names)})")
        lines.append(residual.rstrip("\n"))
    lines.append("")
    lines.append("Manual items: left unchanged")
    for relative_path, line, test_names, reason, detail in manual:
        lines.append(f"--- {relative_path}:{line} ({', '.join(test_names)}): {reason}")
        if detail:
            lines.append(detail.rstrip("\n"))
    for relative_path, record, reason in assertion_outcomes:
        if reason is not None:
            lines.append(f"--- {relative_path}:{record['line']} ({record.get('testName', '')}): assertion, {reason}")
            lines.append(change_diff(record["expected"], record["actual"]).rstrip("\n"))
    lines.append("")
    lines.append("Base records no literal matched")
    grouped = {}
    for key in sorted(unmapped_reasons, key=lambda key: (unmapped_reasons[key][0], unmapped_reasons[key][1]["line"], key)):
        relative_path, record, reason = unmapped_reasons[key]
        grouped.setdefault(reason or "no literal in scope equals the output (an output no test compares whole, or a test already failing on the base)", []).append(f"{relative_path}:{record['line']} ({record.get('testName', '')}) {record['outputName']}" + (f" [{record['module']}, {record['integration']}]" if record.get("module") else ""))
    for reason in sorted(grouped):
        lines.append(f"  {reason}: {len(grouped[reason])}")
        counts = {}
        for entry in grouped[reason]:
            counts[entry] = counts.get(entry, 0) + 1
        for entry in counts:
            lines.append(f"    {entry}" + (f" ({counts[entry]} records)" if counts[entry] > 1 else ""))
    lines.append("")
    lines.append("Matched literals with no head record (counted, not an error)")
    for relative_path, line, test_names in no_head:
        lines.append(f"  {relative_path}:{line} ({', '.join(test_names)})")
    lines.append("")
    lines.append("Changed literals whose call skipped compile verification: read each for compiling")
    for relative_path, line, test_names, _, skips_compile in explained + unexplained:
        if skips_compile:
            lines.append(f"  {relative_path}:{line} ({', '.join(test_names)})")
    lines.append("")
    sample = sorted(explained, key=lambda item: hashlib.sha256(f"{item[0]}:{item[1]}".encode()).hexdigest())[:arguments.sample]
    lines.append(f"Sample of explained literals ({len(sample)} of {len(explained)})")
    for relative_path, line, test_names, diff, _ in sorted(sample, key=lambda item: (item[0], item[1])):
        lines.append(f"--- {relative_path}:{line} ({', '.join(test_names)})")
        lines.append(diff.rstrip("\n"))
    lines.append("")
    lines.extend(mapping_statistics(base_generation, mapped_record_keys, unmapped_reasons, outcomes, resolver))
    os.makedirs(arguments.report, exist_ok=True)
    with open(os.path.join(arguments.report, "report.txt"), "w", encoding="utf-8") as report_file:
        report_file.write("\n".join(lines) + "\n")


def mapping_statistics(base_generation, mapped_record_keys, unmapped_reasons, outcomes, resolver):
    functions = {}
    for record in base_generation:
        functions.setdefault((resolver.resolve(record["fileID"]), record.get("testName", "")), []).append(record)
    mapped_functions = sum(1 for records in functions.values() if any(record["key"] in mapped_record_keys for record in records))
    named = sum(1 for _, _, reason in unmapped_reasons.values() if reason is not None)
    mapped_records = len({record["key"] for record in base_generation} & mapped_record_keys)
    record_count = len({record["key"] for record in base_generation})
    plain = [outcome for outcome in outcomes.values() if outcome.literal.interpolation_count == 0]
    interpolated = [outcome for outcome in outcomes.values() if outcome.literal.interpolation_count]
    ambiguous = sum(1 for outcome in interpolated if any(match[4] for match in outcome.matches))
    disagreeing = sum(1 for outcome in outcomes.values() if len({match[2] for match in outcome.matches}) > 1)
    unencodable = 0
    for outcome in outcomes.values():
        try:
            checked_encoding(outcome.literal, outcome.literal.parts)
        except (ApplyError, EncodeError):
            unencodable += 1

    def share(numerator, denominator):
        return f"{numerator} of {denominator} ({100.0 * numerator / denominator:.1f}%)" if denominator else f"{numerator} of 0"

    return [
        "Mapping statistics",
        f"  Test functions with a base record that have a literal mapped: {share(mapped_functions, len(functions))}",
        f"  Base records mapped to a literal: {share(mapped_records, record_count)}",
        f"  Base records mapped, of those not unmapped for a named reason: {share(mapped_records, record_count - named)}",
        f"  Literals matched: {len(outcomes)} ({len(plain)} plain, {len(interpolated)} interpolated, holding {sum(outcome.literal.interpolation_count for outcome in interpolated)} interpolations)",
        "  Matched literals that would be manual if they changed:",
        f"    ambiguous interpolation captures: {ambiguous}",
        f"    records whose base contents differ (they disagree unless they change alike): {disagreeing}",
        f"    literals this script cannot spell again: {unencodable}",
    ]


# MARK: Self-test


SELF_TEST_HEADER = "// header\n\n"


def write_file(path, content):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as output_file:
        output_file.write(content)


def generation_record(key, line, content, test_name="test()", file_id="Mod/FileTests.swift", skips=False, module=None, test_file_id=None, test_line=None):
    return {
        "kind": "generation", "fileID": file_id, "line": line, "column": 9, "testName": test_name, "integration": None,
        "module": module, "outputName": "Root+SafeDI.swift", "content": content, "skipsCompileVerification": skips,
        "inputsDigest": "digest", "key": key, "testFileID": test_file_id, "testLine": test_line,
    }


def assertion_record(key, line, overload, expected, actual, test_name="test()"):
    return {
        "kind": "assertion", "fileID": "Mod/FileTests.swift", "line": line, "column": 9, "testName": test_name,
        "overload": overload, "module": None, "expected": expected, "actual": actual, "key": key,
    }


class SelfTestCase:
    def __init__(self, root, name):
        self.directory = os.path.join(root, name)
        self.checkout = os.path.join(self.directory, "checkout")
        self.base = os.path.join(self.directory, "base")
        self.head = os.path.join(self.directory, "head")
        self.report = os.path.join(self.directory, "report")
        self.rules = os.path.join(self.directory, "rules.json")
        os.makedirs(self.base)
        os.makedirs(self.head)

    def test_file(self, content, relative_path="Tests/Mod/FileTests.swift"):
        write_file(os.path.join(self.checkout, relative_path), content)

    def records(self, base, head, rules=None):
        for directory, records in ((self.base, base), (self.head, head)):
            write_file(os.path.join(directory, HEADER_NAME), SELF_TEST_HEADER)
            for record in records:
                write_file(os.path.join(directory, record["key"] + ".json"), json.dumps(record))
            write_manifest(directory, self.checkout)
        write_file(self.rules, json.dumps(rules or {}))

    def run(self, dry_run=False, sample=5):
        arguments = argparse.Namespace(
            base_records=self.base, head_records=self.head, rules=self.rules, report=self.report,
            checkout=self.checkout, dry_run=dry_run, sample=sample,
        )
        try:
            status, summary = apply(arguments)
        except ApplyError as error:
            return 2, {"error": str(error)}
        return status, summary

    def source(self, relative_path="Tests/Mod/FileTests.swift"):
        with open(os.path.join(self.checkout, relative_path), encoding="utf-8") as source_file:
            return source_file.read()

    def report_text(self):
        with open(os.path.join(self.report, "report.txt"), encoding="utf-8") as report_file:
            return report_file.read()


def test_function(body, name="test"):
    return f"struct FileTests {{\n\t@Test\n\tfunc {name}() {{\n{body}\n\t}}\n}}\n"


def self_test(root):
    if os.path.exists(root):
        print(f"{root} exists; --self-test writes a new directory", file=sys.stderr)
        return 2
    os.makedirs(root)
    failures = []

    def expect(condition, description):
        if not condition:
            failures.append(description)

    def case(name):
        return SelfTestCase(root, name)

    # plain: a whole literal, explained by a rename.
    test = case("plain")
    test.test_file(test_function('\t\tlet output = run()\n\t\t#expect(output == """\n\t\tlet a = Old()\n\t\t""")'))
    test.records([generation_record("k", 5, "let a = Old()")], [generation_record("k", 5, "let a = New()")], {"rename": [{"name": "Old to New", "table": {"Old": "New"}, "wordBoundaries": True}]})
    status, summary = test.run()
    expect(status == 0 and summary["explained"] == 1, f"plain: {status} {summary}")
    expect(test.source() == test_function('\t\tlet output = run()\n\t\t#expect(output == """\n\t\tlet a = New()\n\t\t""")'), "plain: rewritten source")

    # generatedFileHeader +: the literal is the content after the header.
    test = case("header")
    test.test_file(test_function('\t\t#expect(run() == generatedFileHeader + """\n\t\tbody\n\n\t\tmore\n\t\t""")'))
    test.records([generation_record("k", 4, SELF_TEST_HEADER + "body\n\nmore")], [generation_record("k", 4, SELF_TEST_HEADER + "body\n\nchanged")], {"rewrite": [{"name": "more", "pattern": "more", "replacement": "changed"}]})
    status, summary = test.run()
    expect(status == 0 and summary["explained"] == 1, f"header: {status} {summary}")
    expect(test.source() == test_function('\t\t#expect(run() == generatedFileHeader + """\n\t\tbody\n\n\t\tchanged\n\t\t""")'), "header: blank line stays empty and the header is kept")

    # raw: a raw literal keeps its backslashes and hashes.
    test = case("raw")
    test.test_file(test_function('\t\t#expect(run() == #"""\n\t\tpath\\to "q" \\#(name)\n\t\t"""#)'))
    test.records([generation_record("k", 4, 'path\\to "q" Name')], [generation_record("k", 4, 'path\\from "q" Name')], {"rewrite": [{"name": "to", "pattern": "to", "replacement": "from"}]})
    status, summary = test.run()
    expect(status == 0 and summary["explained"] == 1, f"raw: {status} {summary}")
    expect(test.source() == test_function('\t\t#expect(run() == #"""\n\t\tpath\\from "q" \\#(name)\n\t\t"""#)'), "raw: rewritten source")

    # escapes and \u{…}: decoded as Swift decodes them.
    test = case("escapes")
    test.test_file(test_function('\t\t#expect(run() == "a\\tb\\u{2019}c\\\\d\\"e\\n")'))
    test.records([generation_record("k", 4, 'a\tb\u2019c\\d"e\n')], [generation_record("k", 4, 'a\tb\u2019c\\d"f\n')], {"rewrite": [{"name": "e", "pattern": "e", "replacement": "f"}]})
    status, summary = test.run()
    expect(status == 0 and summary["explained"] == 1, f"escapes: {status} {summary}")
    expect(test.source() == test_function('\t\t#expect(run() == "a\\tb\u2019c\\\\d\\"f\\n")'), "escapes: rewritten source")

    # line continuation: a backslash at a line's end spells no newline.
    test = case("continuation")
    test.test_file(test_function('\t\t#expect(run() == """\n\t\tone \\\n\t\ttwo\n\t\t""")'))
    test.records([generation_record("k", 4, "one two")], [generation_record("k", 4, "one three")], {"rewrite": [{"name": "two", "pattern": "two", "replacement": "three"}]})
    status, summary = test.run()
    expect(status == 0 and summary["explained"] == 1, f"continuation: {status} {summary}")
    expect(test.source() == test_function('\t\t#expect(run() == """\n\t\tone three\n\t\t""")'), "continuation: rewritten source")

    # interpolation in an unchanged region: rebuilt with the interpolation in place.
    test = case("interpolation-unchanged-region")
    test.test_file(test_function('\t\t#expect(run() == """\n\t\tlet value = Old(configuration: .standard)\n\t\t// at \\(fixtures["A.swift"]):7\n\t\t""")'))
    test.records([generation_record("k", 4, "let value = Old(configuration: .standard)\n// at $TARGET_DIRECTORY/A.swift:7")], [generation_record("k", 4, "let value = New(configuration: .standard)\n// at $TARGET_DIRECTORY/A.swift:7")], {"rename": [{"name": "rename", "table": {"Old": "New"}}]})
    status, summary = test.run()
    expect(status == 0 and summary["explained"] == 1, f"interpolation in an unchanged region: {status} {summary}")
    expect(test.source() == test_function('\t\t#expect(run() == """\n\t\tlet value = New(configuration: .standard)\n\t\t// at \\(fixtures["A.swift"]):7\n\t\t""")'), "interpolation in an unchanged region: rebuilt source")

    # a literal whose own text is mostly line breaks anchors nothing: neither a helper's `"\(a)\n\(b)"` outside every
    # test nor a test's `"\(path)\n"` matches an output.
    test = case("weak-anchor")
    original = 'struct FileTests {\n\tfunc joined(_ a: String, _ b: String) -> String {\n\t\t"\\(a)\\n\\(b)"\n\t}\n\n\t@Test\n\tfunc test() {\n\t\tlet path = run()\n\t\t#expect(read() == "\\(path)\\n")\n\t}\n}\n'
    test.test_file(original)
    test.records([generation_record("k", 9, "first line\nsecond line\n")], [generation_record("k", 9, "first line\ninserted\nsecond line\n")])
    status, summary = test.run()
    expect(status == 0 and summary["rewritten"] == 0 and summary["manual"] == 0 and summary["changedWithoutLiteral"] == 1 and test.source() == original, f"weak anchor: {status} {summary}")

    # interpolation in a changed region: manual.
    test = case("interpolation-changed-region")
    original = test_function('\t\t#expect(run() == """\n\t\tlet value = \\(name)(configuration: .standard)\n\t\t""")')
    test.test_file(original)
    test.records([generation_record("k", 4, "let value = Old(configuration: .standard)")], [generation_record("k", 4, "let value = Gone(configuration: .standard)")])
    status, summary = test.run()
    expect(status == 1 and summary["manualReasons"] == ["interpolation in a changed region"], f"interpolation in a changed region: {status} {summary}")
    expect(test.source() == original, "interpolation in a changed region: left unchanged")

    # ambiguous captures: manual when the literal changes.
    test = case("ambiguous-changed")
    original = test_function('\t\t#expect(run() == "the values x\\(a) \\(b)y in order")')
    test.test_file(original)
    test.records([generation_record("k", 4, "the values x1 2 3y in order")], [generation_record("k", 4, "the values x1 2 3z in order")])
    status, summary = test.run()
    expect(status == 1 and summary["manualReasons"] == ["ambiguous interpolation captures"], f"ambiguous captures: {status} {summary}")
    expect(test.source() == original, "ambiguous captures: left unchanged")

    # ambiguous captures on an unchanged literal: not manual.
    test = case("ambiguous-unchanged")
    test.test_file(original)
    test.records([generation_record("k", 4, "the values x1 2 3y in order")], [generation_record("k", 4, "the values x1 2 3y in order")])
    status, summary = test.run()
    expect(status == 0 and summary["manual"] == 0 and summary["rewritten"] == 0, f"ambiguous captures, unchanged: {status} {summary}")

    # an expression spelled twice captures one value, which settles captures that would otherwise be ambiguous.
    test = case("repeated-interpolation")
    test.test_file(test_function('\t\t#expect(run() == "name \\(x) and \\(y) then \\(x) end")'))
    test.records([generation_record("k", 4, "name a and b and c then a and b end")], [generation_record("k", 4, "name a and b and c then a and b stop")], {"rewrite": [{"name": "stop", "pattern": " end", "replacement": " stop"}]})
    status, summary = test.run()
    expect(status == 0 and summary["explained"] == 1, f"repeated interpolation: {status} {summary}")
    expect(test.source() == test_function('\t\t#expect(run() == "name \\(x) and \\(y) then \\(x) stop")'), f"repeated interpolation: rewritten source {test.source()!r}")

    # a literal that is mostly interpolation, such as `"\(self)"`, matches nothing.
    test = case("unanchored-interpolation")
    original = 'struct FileTests {\n\tvar description: String {\n\t\t"\\(self)"\n\t}\n\n\t@Test\n\tfunc test() {\n\t\t_ = run()\n\t}\n}\n'
    test.test_file(original)
    test.records([generation_record("k", 8, "line one\nline two")], [generation_record("k", 8, "line one\nline 2")])
    status, summary = test.run()
    expect(status == 0 and summary["rewritten"] == 0 and summary["manual"] == 0 and summary["changedWithoutLiteral"] == 1 and test.source() == original, f"unanchored interpolation: {status} {summary}")

    # two integrations with equal base content: both records map to one literal, which changes once.
    test = case("two-integrations")
    test.test_file(test_function('\t\t#expect(run(integration) == """\n\t\tOld\n\t\t""")'))
    test.records([generation_record("k1", 4, "Old", module="App"), generation_record("k2", 4, "Old", module="App2")], [generation_record("k1", 4, "New", module="App"), generation_record("k2", 4, "New", module="App2")], {"rename": [{"name": "rename", "table": {"Old": "New"}}]})
    status, summary = test.run()
    expect(status == 0 and summary["rewritten"] == 1, f"two integrations: {status} {summary}")
    expect(test.source() == test_function('\t\t#expect(run(integration) == """\n\t\tNew\n\t\t""")'), "two integrations: rewritten source")

    # records that disagree: manual.
    test = case("disagree")
    original = test_function('\t\t#expect(run(integration) == """\n\t\tOld\n\t\t""")')
    test.test_file(original)
    test.records([generation_record("k1", 4, "Old"), generation_record("k2", 4, "Old")], [generation_record("k1", 4, "New"), generation_record("k2", 4, "Other")])
    status, summary = test.run()
    expect(status == 1 and summary["manualReasons"] == ["records that map to this literal disagree on its new value"], f"records that disagree: {status} {summary}")
    expect(test.source() == original, "records that disagree: left unchanged")

    # shared static let: a literal outside every test function matches records from the whole file.
    test = case("shared-literal")
    test.test_file('struct FileTests {\n\tstatic let expected = """\n\tOld\n\t"""\n\n\t@Test\n\tfunc test() {\n\t\t#expect(run() == Self.expected)\n\t}\n}\n')
    test.records([generation_record("k", 8, "Old")], [generation_record("k", 8, "New")], {"rename": [{"name": "rename", "table": {"Old": "New"}}]})
    status, summary = test.run()
    expect(status == 0 and summary["explained"] == 1, f"shared literal: {status} {summary}")
    expect(test.source() == 'struct FileTests {\n\tstatic let expected = """\n\tNew\n\t"""\n\n\t@Test\n\tfunc test() {\n\t\t#expect(run() == Self.expected)\n\t}\n}\n', "shared literal: rewritten source")

    # a literal in a test function is matched only by records whose call is in that function.
    test = case("scope")
    original = 'struct FileTests {\n\t@Test\n\tfunc first() {\n\t\t#expect(run() == "Old")\n\t}\n\n\t@Test\n\tfunc second() {\n\t\t_ = run()\n\t}\n}\n'
    test.test_file(original)
    test.records([generation_record("k", 9, "Old")], [generation_record("k", 9, "New")])
    status, summary = test.run()
    expect(status == 0 and summary["rewritten"] == 0 and summary["changedWithoutLiteral"] == 1 and test.source() == original, f"scope: {status} {summary}")

    # a call made through a helper function of the file maps to the literal of the test whose name its record carries.
    test = case("helper-call-site")
    helper = '\tfunc check() -> String {\n\t\trun()\n\t}\n'
    test.test_file('struct FileTests {\n' + helper + '\n\t@Test(arguments: [1])\n\tfunc test(value: Int) {\n\t\t#expect(check() == "Old")\n\t}\n}\n')
    test.records([generation_record("k", 3, "Old", test_name="test(value:)", test_file_id="Mod/FileTests.swift", test_line=6)], [generation_record("k", 3, "New", test_name="test(value:)", test_file_id="Mod/FileTests.swift", test_line=6)], {"rename": [{"name": "rename", "table": {"Old": "New"}}]})
    status, summary = test.run()
    expect(status == 0 and summary["explained"] == 1, f"helper call site: {status} {summary}")
    expect(test.source() == 'struct FileTests {\n' + helper + '\n\t@Test(arguments: [1])\n\tfunc test(value: Int) {\n\t\t#expect(check() == "New")\n\t}\n}\n', "helper call site: rewritten source")

    # two tests of one name in two suites: the record's test location picks the one that made the call.
    test = case("helper-call-site-shared-name")
    original = 'struct FileTests {\n' + helper + '\n\t@Test\n\tfunc test() {\n\t\t#expect(check() == "Old")\n\t}\n}\n\nextension Other {\n\t@Test\n\tfunc test() {\n\t\t#expect(check() == "Old")\n\t}\n}\n'
    test.test_file(original)
    test.records([generation_record("k", 3, "Old", test_file_id="Mod/FileTests.swift", test_line=13)], [generation_record("k", 3, "New", test_file_id="Mod/FileTests.swift", test_line=13)], {"rename": [{"name": "rename", "table": {"Old": "New"}}]})
    status, summary = test.run()
    expect(status == 0 and summary["rewritten"] == 1 and test.source() == '"New"'.join(original.rsplit('"Old"', 1)), f"helper call site, shared name: {status} {summary}")

    # a test in another file that calls this file's helper: its record maps to that file's literal, never to an equal
    # literal of this file's same-named test.
    test = case("helper-call-site-other-file")
    local = 'struct FileTests {\n' + helper + '\n\t@Test\n\tfunc test() {\n\t\t#expect(somethingElse() == "Old")\n\t}\n}\n'
    other = 'struct OtherTests {\n\t@Test\n\tfunc test() {\n\t\t#expect(FileTests().check() == "Old")\n\t}\n}\n'
    test.test_file(local)
    test.test_file(other, "Tests/Mod/OtherTests.swift")
    test.records([generation_record("k", 3, "Old", test_file_id="Mod/OtherTests.swift", test_line=2)], [generation_record("k", 3, "New", test_file_id="Mod/OtherTests.swift", test_line=2)], {"rename": [{"name": "rename", "table": {"Old": "New"}}]})
    status, summary = test.run()
    expect(status == 0 and summary["rewritten"] == 1 and test.source() == local and test.source("Tests/Mod/OtherTests.swift") == other.replace('"Old"', '"New"'), f"helper call site, other file: {status} {summary}")

    # a base record with no literal: listed, not an error.
    test = case("record-without-literal")
    test.test_file(test_function("\t\t_ = run()"))
    test.records([generation_record("k", 4, "Unmatched")], [generation_record("k", 4, "Unmatched")])
    status, summary = test.run()
    expect(status == 0 and summary["rewritten"] == 0, f"record without literal: {status} {summary}")
    expect("Base records no literal matched\n  no literal in scope equals the output" in test.report_text(), "record without literal: reported")

    # a base record with no literal whose output changed: its test still fails, so a person updates it.
    test = case("changed-record-without-literal")
    test.test_file(test_function("\t\t_ = run()"))
    test.records([generation_record("k", 4, "Unmatched")], [generation_record("k", 4, "Unmatched too")])
    status, summary = test.run()
    expect(status == 0 and summary["rewritten"] == 0 and summary["changedWithoutLiteral"] == 1, f"changed record without literal: {status} {summary}")
    expect("Changed outputs no literal matched: a test that compares one still fails, so update it by hand\n  Tests/Mod/FileTests.swift:4 (test()) Root+SafeDI.swift\n" in test.report_text(), "changed record without literal: reported")

    # a literal with no head record: counted, not an error.
    test = case("literal-without-head")
    original = test_function('\t\t#expect(run() == "Old")')
    test.test_file(original)
    test.records([generation_record("k", 4, "Old")], [])
    status, summary = test.run()
    expect(status == 0 and summary["rewritten"] == 0 and test.source() == original, f"literal without head: {status} {summary}")
    expect("Matched literals with no head record (counted, not an error)\n  Tests/Mod/FileTests.swift:4 (test())" in test.report_text(), "literal without head: counted")

    # manifest mismatch: exit 2, nothing written.
    test = case("manifest-mismatch")
    original = test_function('\t\t#expect(run() == "Old")')
    test.test_file(original)
    test.records([generation_record("k", 4, "Old")], [generation_record("k", 4, "New")])
    write_file(os.path.join(test.checkout, "Tests/Mod/Other.swift"), "// other\n")
    write_manifest(test.head, test.checkout)
    status, summary = test.run()
    expect(status == 2 and "different Tests/" in summary.get("error", "") and test.source() == original and not os.path.exists(test.report), f"manifest mismatch: {status} {summary}")

    # checkout changed since recording: exit 2.
    test = case("checkout-changed")
    test.test_file(original)
    test.records([generation_record("k", 4, "Old")], [generation_record("k", 4, "New")])
    test.test_file(original + "// edited\n")
    status, summary = test.run()
    expect(status == 2 and "changed since recording" in summary.get("error", "") and not os.path.exists(test.report), f"checkout changed: {status} {summary}")

    # ambiguous fileID: exit 2.
    test = case("ambiguous-file-id")
    test.test_file(original)
    test.test_file(original, "Tests/Mod/Nested/Mod/FileTests.swift")
    test.records([generation_record("k", 4, "Old")], [generation_record("k", 4, "New")])
    status, summary = test.run()
    expect(status == 2 and "names 2 files" in summary.get("error", "") and test.source() == original, f"ambiguous fileID: {status} {summary}")

    # a rule that can match the empty string: rejected.
    test = case("empty-matching-rule")
    test.test_file(original)
    test.records([generation_record("k", 4, "Old")], [generation_record("k", 4, "New")], {"rewrite": [{"name": "anything", "pattern": "x*", "replacement": "y"}]})
    status, summary = test.run()
    expect(status == 2 and "empty string" in summary.get("error", "") and test.source() == original, f"empty-matching rule: {status} {summary}")
    for rules, message in (({"rename": [{"name": "r", "table": {"": "x"}}]}, "empty key"), ({"rename": [{"name": "r", "table": {"a": "b"}}], "normalize": [{"name": "r", "pattern": "a", "replacement": "b"}]}, "two rules are named"), ({"rewrite": [{"name": "r", "pattern": "Absent", "replacement": "\\2"}]}, "invalid replacement"), ({"normalize": [{"name": "r", "pattern": "(?P<word>Absent)", "replacement": "\\g<other>"}]}, "invalid replacement")):
        write_file(test.rules, json.dumps(rules))
        status, summary = test.run()
        expect(status == 2 and message in summary.get("error", ""), f"rejected rules {message}: {status} {summary}")

    # renames apply at once: A → B and B → C turn "A B" into "B C", never "C C".
    test = case("rename-simultaneous")
    test.test_file(test_function('\t\t#expect(run() == "A B")'))
    test.records([generation_record("k", 4, "A B")], [generation_record("k", 4, "B C")], {"rename": [{"name": "shift", "table": {"A": "B", "B": "C"}, "wordBoundaries": True}]})
    status, summary = test.run()
    expect(status == 0 and summary["explained"] == 1 and summary["hits"] == {"shift": 2}, f"simultaneous rename: {status} {summary}")

    # normalize: an opaque hash on both sides.
    test = case("normalize")
    test.test_file(test_function('\t\t#expect(run() == "enum __safeDI_Root_0123456789ABCDEF {}")'))
    test.records([generation_record("k", 4, "enum __safeDI_Root_0123456789ABCDEF {}")], [generation_record("k", 4, "enum __safeDI_Root_FEDCBA9876543210 {}")], {"normalize": [{"name": "guard hash", "pattern": "__safeDI_(\\w+?)_[0-9A-F]{16}", "replacement": "__safeDI_\\1_HASH"}]})
    status, summary = test.run()
    expect(status == 0 and summary["explained"] == 1 and test.source() == test_function('\t\t#expect(run() == "enum __safeDI_Root_FEDCBA9876543210 {}")'), f"normalize: {status} {summary}")

    # explained against unexplained: the residual shows only what no rule predicts.
    test = case("residual")
    test.test_file(test_function('\t\t#expect(run() == """\n\t\tlet a = Old()\n\t\tlet b = 1\n\t\t""")\n\t\t#expect(run2() == "Old")'))
    test.records([generation_record("k1", 4, "let a = Old()\nlet b = 1"), generation_record("k2", 7, "Old")], [generation_record("k1", 4, "let a = New()\nlet b = 2"), generation_record("k2", 7, "New")], {"rename": [{"name": "rename", "table": {"Old": "New"}}]})
    status, summary = test.run()
    report = test.report_text()
    expect(status == 1 and summary["explained"] == 1 and summary["unexplained"] == 1, f"residual: {status} {summary}")
    expect("--- predicted\n+++ actual\n@@ -1,2 +1,2 @@\n let a = New()\n-let b = 1\n+let b = 2\n" in report, "residual: only the unpredicted line differs")

    # assertion literals: a plain argument and a diagnostics closure's literal.
    test = case("assertion")
    test.test_file(test_function(
        '\t\tawait assertThrowsError("Old error.") {\n\t\t\ttry run()\n\t\t}\n'
        '\t\tawait assertThrowsError(diagnostics: { fixtures in\n\t\t\t"\\(fixtures["A.swift"]):1:1: error: Old message the run printed."\n\t\t}) {\n\t\t\ttry run()\n\t\t}'
    ))
    test.records([], [assertion_record("a1", 4, "plain", "Old error.", "New error."), assertion_record("a2", 7, "diagnostics", "$TARGET_DIRECTORY/A.swift:1:1: error: Old message the run printed.", "$TARGET_DIRECTORY/A.swift:1:1: error: New message the run printed.")], {"rename": [{"name": "rename", "table": {"Old": "New"}}]})
    status, summary = test.run()
    expect(status == 0 and summary["explained"] == 2, f"assertion: {status} {summary}")
    expect(test.source() == test_function(
        '\t\tawait assertThrowsError("New error.") {\n\t\t\ttry run()\n\t\t}\n'
        '\t\tawait assertThrowsError(diagnostics: { fixtures in\n\t\t\t"\\(fixtures["A.swift"]):1:1: error: New message the run printed."\n\t\t}) {\n\t\t\ttry run()\n\t\t}'
    ), "assertion: rewritten source")

    # a new value that spells a run path outside every interpolation could never equal the next run's output: manual.
    test = case("placeholder-outside-interpolation")
    original = test_function('\t\t#expect(run() == """\n\t\tlet a = Old()\n\t\t""")\n\t\tawait assertThrowsError("Old message the run printed.") {\n\t\t\ttry run()\n\t\t}')
    test.test_file(original)
    test.records([generation_record("k", 4, "let a = Old()")], [generation_record("k", 4, "// Declared at $TARGET_DIRECTORY/A.swift:3\nlet a = New()"), assertion_record("a", 7, "plain", "Old message the run printed.", "$FIXTURE_ROOT/App/A.swift:1:1: error: New message the run printed.")], {"rename": [{"name": "rename", "table": {"Old": "New"}}]})
    status, summary = test.run()
    expect(status == 1 and summary["rewritten"] == 0 and summary["manualReasons"] == ["the new value names a run directory outside its interpolations"] * 2 and test.source() == original, f"placeholder outside interpolation: {status} {summary}")

    # a wrapper's call site: its expected value is no literal there, so manual.
    test = case("wrapper")
    original = 'struct FileTests {\n\tfunc check(_ expected: String) async {\n\t\tawait assertThrowsError(expected) {\n\t\t\ttry run()\n\t\t}\n\t}\n}\n'
    test.test_file(original)
    test.records([], [assertion_record("a", 3, "plain", "Old", "New")])
    status, summary = test.run()
    expect(status == 1 and summary["manualReasons"] == ["non-literal expected value"] and test.source() == original, f"wrapper: {status} {summary}")

    # decode(encode(x)) == x for literals of every kind.
    values = ["", "a", "a\n", "\n", "\n\n", 'q"q', 'q"""q', "back\\slash", "tab\there", "\u2019", "trailing \n", "  indented\n\tline", "\\(not interpolation)", "\r\x01"]
    for kind_source in ('"x"', '"""\n\tx\n\t"""', '#"x"#', '#"""\n\tx\n\t"""#'):
        literal = tokenize("\t_ = " + kind_source)[2].literal
        for value in values:
            try:
                checked_encoding(literal, [("text", value)])
            except EncodeError:
                expect(literal.hashes > 0, f"round trip: {kind_source} cannot spell {value!r}")
            except ApplyError as error:
                expect(False, f"round trip: {kind_source} {value!r}: {error}")

    # blank lines and tabs stay lint-clean: no line of a rewritten multi-line literal ends in whitespace it did not hold.
    literal = tokenize('\t\t_ = """\n\t\tx\n\t\t"""')[2].literal
    source = checked_encoding(literal, [("text", "a\n\n\tb\n")])
    expect(source == '"""\n\t\ta\n\n\t\t\tb\n\n\t\t"""', f"lint-clean: {source!r}")

    # an extended regex literal holding quotation marks is no string: the file still parses and its literal is rewritten.
    test = case("regex-literal")
    test.test_file(test_function('\t\tlet pattern = #/"([^"]+)"/#\n\t\t#expect(run(pattern) == "Old")'))
    test.records([generation_record("k", 5, "Old")], [generation_record("k", 5, "New")], {"rename": [{"name": "rename", "table": {"Old": "New"}}]})
    status, summary = test.run()
    expect(status == 0 and summary.get("explained") == 1 and test.source() == test_function('\t\tlet pattern = #/"([^"]+)"/#\n\t\t#expect(run(pattern) == "New")'), f"regex literal: {status} {summary}")

    # two dry runs write the same report and no test file.
    test = case("idempotent")
    test.test_file(test_function('\t\t#expect(run() == "Old")'))
    test.records([generation_record("k", 4, "Old")], [generation_record("k", 4, "New")], {"rename": [{"name": "rename", "table": {"Old": "New"}}]})
    test.run(dry_run=True)
    first_report = test.report_text()
    test.run(dry_run=True)
    expect(test.report_text() == first_report and test.source() == test_function('\t\t#expect(run() == "Old")'), "idempotent: dry runs agree and write no test file")

    # applying for real, then again, edits once: the second apply finds Tests/ changed since recording and refuses.
    test = case("second-apply")
    test.test_file(test_function('\t\t#expect(run() == "Old")'))
    test.records([generation_record("k", 4, "Old")], [generation_record("k", 4, "New")], {"rename": [{"name": "rename", "table": {"Old": "New"}}]})
    first_status, _ = test.run()
    applied = test.source()
    second_status, summary = test.run()
    expect(first_status == 0 and applied == test_function('\t\t#expect(run() == "New")'), f"second apply: first apply {first_status}")
    expect(second_status == 2 and "changed since recording" in summary.get("error", "") and test.source() == applied, f"second apply: {second_status} {summary}")

    for failure in failures:
        print(f"self-test failed: {failure}")
    if not failures:
        print("self-test passed")
    return 1 if failures else 0


# MARK: Main


def main(argv):
    usage, _, description = __doc__.partition("\n\n")
    parser = argparse.ArgumentParser(usage=usage.removeprefix("Usage: "), description=description, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--write-manifest", metavar="RECORD_DIR")
    parser.add_argument("--base-records")
    parser.add_argument("--head-records")
    parser.add_argument("--rules")
    parser.add_argument("--report")
    parser.add_argument("--checkout")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--sample", type=int, default=5)
    parser.add_argument("--self-test", metavar="DIR")
    arguments = parser.parse_args(argv)
    try:
        if arguments.self_test:
            return self_test(arguments.self_test)
        if arguments.write_manifest:
            if not arguments.checkout:
                parser.error("--write-manifest needs --checkout")
            write_manifest(arguments.write_manifest, arguments.checkout)
            return 0
        if not all((arguments.base_records, arguments.head_records, arguments.rules, arguments.report, arguments.checkout)):
            parser.error("applying needs --base-records, --head-records, --rules, --report and --checkout")
        status, summary = apply(arguments)
        print(f"rewritten {summary['rewritten']}, explained {summary['explained']}, unexplained {summary['unexplained']}, manual {summary['manual']}; see {os.path.join(arguments.report, 'report.txt')}")
        return status
    except ApplyError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
