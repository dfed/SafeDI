#!/usr/bin/env python3
# Scripts/sweep-apostrophes.py [--check] [--list]
#
# Spells every apostrophe in the text SafeDI emits as ’ (U+2019), never '. The text SafeDI emits (diagnostics, fix-its,
# notes, remedies, help, and the comments of generated code) is written in string literals under Sources and Plugins,
# and the tests compare it in full, so the script rewrites two places:
#
# 1. Each string literal under Sources and Plugins. Only the literal's text is read: comments and code are skipped, and
#    so is each interpolation's code (though a string literal inside an interpolation is a literal of its own). Within
#    that text, a ' is an apostrophe when
#    - a letter follows it, and a letter, a digit, a backtick or an interpolation precedes it (`type's`, `don't`,
#      "`Feed`'s", "\(name)'s"), or
#    - an `s` precedes it, no letter or digit follows it, and it does not close a quotation the literal opened with a '
#      (`types' declarations`, but not `'--include'` or `'paths'`).
#    Any other ' is not an apostrophe and is kept: a quotation mark ('\(path)', 'swift-sources-file-path') or Swift
#    code (`character == "'"`).
# 2. The text that repeats one of those literals: string literals under Tests, and the Swift code blocks of
#    Documentation, which tests compare with generated code. Most of that text is a fixture's own source, which SafeDI
#    reads and never rewrites, so the script changes a ' there only where its context is an apostrophe's context in
#    Sources. An apostrophe's context is the text of its Sources literal around it, at most 40 characters each way,
#    stopping at the literal's ends and after three interpolations, each of which matches any text on one line. A '
#    in a test's literal or a code block becomes ’ when the text before it and after it match some context's. A
#    context with fewer than 8 characters of text, such as "`\(type)`'s `\(label)`", could match a fixture's comment
#    by chance, so it is not used: `--list` prints each, and a test that compares such a message is updated by hand.
#    `SourceRuleTests`, whose literals are SafeDI's own source, spelling a straight apostrophe on purpose, is skipped.
#
# Contexts come from the apostrophes Sources already spells ’ as well as those this run rewrites, so a run converges:
# after a rebase brings a test that still expects ', running the script again rewrites it, and a second run in a row
# changes nothing. Files are read and written in path order, so a run is deterministic.
#
# --check changes nothing and exits 1 when a run would change a file. --list prints each Sources apostrophe it finds
# and each context too short to use.

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIRECTORIES = ["Sources", "Plugins"]
EXPECTATION_DIRECTORIES = ["Tests"]
DOCUMENTATION_DIRECTORIES = ["Documentation"]
# The tests whose literals are SafeDI's own source, which spell a straight apostrophe on purpose.
SOURCE_FIXTURE_FILES = ["Tests/SafeDIGeneratorPluginTests/SourceRuleTests.swift"]
CURLY = "’"
CONTEXT_LENGTH = 40
MINIMUM_CONTEXT_LENGTH = 8


class Segment:
	"""A run of a string literal's text between interpolations, at `start..<end` in the file."""

	def __init__(self, start, end, after_interpolation, before_interpolation):
		self.start = start
		self.end = end
		self.after_interpolation = after_interpolation
		self.before_interpolation = before_interpolation


class SwiftStringLiteralScanner:
	"""Finds the text of every string literal in a Swift file, skipping comments and code."""

	def __init__(self, text):
		self.text = text
		self.literals = []

	def scan(self):
		self.scan_code(0, terminator=None)
		return self.literals

	def scan_code(self, index, terminator):
		"""Scans code from `index` and returns the index after `terminator` (a `)` closing an interpolation), or the
		end of the file."""
		text = self.text
		depth = 0
		while index < len(text):
			character = text[index]
			if text.startswith("//", index):
				newline = text.find("\n", index)
				index = len(text) if newline == -1 else newline
			elif text.startswith("/*", index):
				index = self.skip_block_comment(index)
			elif character == "#" or character == '"':
				hashes = 0
				while index + hashes < len(text) and text[index + hashes] == "#":
					hashes += 1
				if index + hashes < len(text) and text[index + hashes] == '"':
					index = self.scan_literal(index + hashes, hashes)
				elif hashes > 0 and index + hashes < len(text) and text[index + hashes] == "/":
					index = self.skip_regex(index + hashes, hashes)
				else:
					index += max(hashes, 1)
			elif terminator is not None and character == "(":
				depth += 1
				index += 1
			elif terminator is not None and character == ")":
				if depth == 0:
					return index + 1
				depth -= 1
				index += 1
			else:
				index += 1
		return index

	def skip_block_comment(self, index):
		text = self.text
		depth = 0
		while index < len(text):
			if text.startswith("/*", index):
				depth += 1
				index += 2
			elif text.startswith("*/", index):
				depth -= 1
				index += 2
				if depth == 0:
					return index
			else:
				index += 1
		return index

	def skip_regex(self, index, hashes):
		closing = "/" + "#" * hashes
		end = self.text.find(closing, index + 1)
		return len(self.text) if end == -1 else end + len(closing)

	def scan_literal(self, quote_index, hashes):
		"""Scans the literal whose opening quote is at `quote_index`, after `hashes` number signs, records its
		segments, and returns the index after it."""
		text = self.text
		multiline = text.startswith('"""', quote_index)
		index = quote_index + (3 if multiline else 1)
		closing = ('"""' if multiline else '"') + "#" * hashes
		escape = "\\" + "#" * hashes
		segments = []
		segment_start = index
		after_interpolation = False
		while index < len(text):
			if text.startswith(closing, index):
				segments.append(Segment(segment_start, index, after_interpolation, False))
				self.literals.append(segments)
				return index + len(closing)
			if text.startswith(escape, index):
				after_escape = index + len(escape)
				if after_escape < len(text) and text[after_escape] == "(":
					segments.append(Segment(segment_start, index, after_interpolation, True))
					index = self.scan_code(after_escape + 1, terminator=")")
					segment_start = index
					after_interpolation = True
				else:
					# An escape such as `\"` or `\n` is part of the text: skip the escaped character so a `\"` does
					# not end the literal.
					index = after_escape + 1
			elif not multiline and text[index] == "\n":
				# An unterminated literal, which the compiler rejects: stop at the line's end.
				segments.append(Segment(segment_start, index, after_interpolation, False))
				self.literals.append(segments)
				return index
			else:
				index += 1
		segments.append(Segment(segment_start, index, after_interpolation, False))
		self.literals.append(segments)
		return index


def is_word(character):
	return character.isalpha() or character.isdigit()


def apostrophe_indices(text, segments):
	"""The indices in `text` of the apostrophes, ' or ’, in a literal's `segments`."""
	indices = []
	open_quotation = False
	for segment in segments:
		for index in range(segment.start, segment.end):
			character = text[index]
			if character not in ("'", CURLY):
				continue
			previous = text[index - 1] if index > segment.start else None
			following = text[index + 1] if index + 1 < segment.end else None
			preceded_by_word = (previous is not None and (is_word(previous) or previous == "`")) or (previous is None and segment.after_interpolation)
			followed_by_letter = following is not None and following.isalpha()
			followed_by_word = (following is not None and is_word(following)) or (following is None and segment.before_interpolation)
			if character == CURLY:
				# A ’ is an apostrophe or a closing quotation mark; either way it closes no quotation a ' opened.
				if preceded_by_word and followed_by_letter:
					indices.append(index)
			elif preceded_by_word and followed_by_letter:
				indices.append(index)
			elif not open_quotation and previous == "s" and not followed_by_word:
				indices.append(index)
			elif not preceded_by_word and following is not None and following != " " or (following is None and segment.before_interpolation and not preceded_by_word):
				open_quotation = True
			else:
				open_quotation = False
	return indices


def swift_files(directories):
	paths = []
	for directory in directories:
		for root, _, names in os.walk(os.path.join(ROOT, directory)):
			for name in names:
				path = os.path.join(root, name)
				if name.endswith(".swift") and not os.path.islink(path):
					paths.append(path)
	return sorted(paths)


def markdown_files(directories):
	paths = []
	for directory in directories:
		for root, _, names in os.walk(os.path.join(ROOT, directory)):
			for name in names:
				if name.endswith(".md"):
					paths.append(os.path.join(root, name))
	return sorted(paths)


def read(path):
	with open(path, encoding="utf-8") as file:
		return file.read()


def write(path, text):
	with open(path, "w", encoding="utf-8", newline="") as file:
		file.write(text)


def relative(path):
	return os.path.relpath(path, ROOT)


def replace_at(text, indices):
	characters = list(text)
	for index in indices:
		characters[index] = CURLY
	return "".join(characters)


INTERPOLATION = None
MAXIMUM_INTERPOLATIONS = 3


def context(text, segments, index):
	"""The context of the apostrophe at `index` in a literal's `segments`: the literal's text before it and after it,
	each up to `CONTEXT_LENGTH` characters and up to `MAXIMUM_INTERPOLATIONS` interpolations, which match any text. The
	text before is listed nearest first, each run of it reversed. Every ' in the context is spelled ’."""
	segment_index = next(position for position, segment in enumerate(segments) if segment.start <= index < segment.end)

	def collect(step):
		pieces = []
		remaining = CONTEXT_LENGTH
		interpolations = 0
		position = segment_index
		cursor = index
		while True:
			segment = segments[position]
			if step < 0:
				run = text[max(segment.start, cursor - remaining):cursor][::-1]
				crosses = segment.after_interpolation and position > 0
			else:
				run = text[cursor + 1:min(segment.end, cursor + 1 + remaining)]
				crosses = segment.before_interpolation and position + 1 < len(segments)
			if run:
				pieces.append(run.replace("'", CURLY))
				remaining -= len(run)
			if remaining <= 0 or not crosses or interpolations == MAXIMUM_INTERPOLATIONS:
				return tuple(pieces)
			pieces.append(INTERPOLATION)
			interpolations += 1
			position += step
			cursor = segments[position].end if step < 0 else segments[position].start - 1

	return collect(-1), collect(1)


def static_length(pieces):
	return sum(len(piece) for piece in pieces if piece is not INTERPOLATION)


def spelled(context):
	before, after = context
	text = "".join("\\(…)" if piece is INTERPOLATION else piece[::-1] for piece in reversed(before))
	return text + CURLY + "".join("\\(…)" if piece is INTERPOLATION else piece for piece in after)


def sweep_sources(check, listing):
	"""Rewrites the apostrophes of Sources' literals and returns the contexts of every apostrophe, the number of
	apostrophes rewritten, and the paths that change."""
	contexts = set()
	short_contexts = []
	rewritten = 0
	changed_paths = []
	for path in swift_files(SOURCE_DIRECTORIES):
		text = read(path)
		straight = []
		for segments in SwiftStringLiteralScanner(text).scan():
			for index in apostrophe_indices(text, segments):
				apostrophe_context = context(text, segments, index)
				line = text.count("\n", 0, index) + 1
				if static_length(apostrophe_context[0]) + static_length(apostrophe_context[1]) >= MINIMUM_CONTEXT_LENGTH:
					contexts.add(apostrophe_context)
				else:
					short_contexts.append(f"{relative(path)}:{line}: {spelled(apostrophe_context)}")
				if text[index] == "'":
					straight.append(index)
					if listing:
						print(f"{relative(path)}:{line}: {spelled(apostrophe_context)}")
		if straight:
			rewritten += len(straight)
			changed_paths.append(relative(path))
			if not check:
				write(path, replace_at(text, straight))
	if listing:
		for short_context in short_contexts:
			print(f"short context, not used: {short_context}")
	return contexts, rewritten, changed_paths


class ContextMatcher:
	"""Says whether the ' at an index of a text is in one of the contexts of Sources' apostrophes."""

	def __init__(self, contexts):
		# Sorted, so the order of the checks never depends on the set's.
		self.patterns = [(self.pattern(before), self.pattern(after)) for before, after in sorted(contexts, key=lambda context: repr(context))]

	@staticmethod
	def pattern(pieces):
		# An interpolation matches any text on one line, the shortest that lets the rest match.
		return re.compile("".join("[^\\n]*?" if piece is INTERPOLATION else re.escape(piece) for piece in pieces))

	def indices(self, text, start, end):
		"""The indices of the ' in `text[start:end]` that are in a context."""
		normalized = text[start:end].replace("'", CURLY)
		reversed_text = normalized[::-1]
		indices = []
		for offset, character in enumerate(text[start:end]):
			if character != "'":
				continue
			for before, after in self.patterns:
				if after.match(normalized, offset + 1) and before.match(reversed_text, len(normalized) - offset):
					indices.append(start + offset)
					break
		return indices


def sweep_expectations(contexts, check):
	"""Rewrites each ' in Tests' literals and Documentation's Swift code blocks whose context is an apostrophe's
	context in Sources, and returns the number rewritten and the paths that change."""
	matcher = ContextMatcher(contexts)
	rewritten = 0
	changed_paths = []
	for path in swift_files(EXPECTATION_DIRECTORIES) + markdown_files(DOCUMENTATION_DIRECTORIES):
		if relative(path) in SOURCE_FIXTURE_FILES:
			continue
		text = read(path)
		if path.endswith(".swift"):
			spans = [(segments[0].start, segments[-1].end) for segments in SwiftStringLiteralScanner(text).scan()]
		else:
			spans = [(block.start(1), block.end(1)) for block in re.finditer(r"^```swift\n(.*?)^```", text, re.DOTALL | re.MULTILINE)]
		indices = []
		for start, end in spans:
			if "'" in text[start:end]:
				indices.extend(matcher.indices(text, start, end))
		if indices:
			rewritten += len(indices)
			changed_paths.append(relative(path))
			if not check:
				write(path, replace_at(text, indices))
	return rewritten, changed_paths


def main(arguments):
	check = "--check" in arguments
	listing = "--list" in arguments
	unknown = [argument for argument in arguments if argument not in ("--check", "--list")]
	if unknown:
		print(f"usage: {sys.argv[0]} [--check] [--list]", file=sys.stderr)
		return 2
	contexts, source_count, source_paths = sweep_sources(check, listing)
	expectation_count, expectation_paths = sweep_expectations(contexts, check)
	verb = "would rewrite" if check else "rewrote"
	print(f"{verb} {source_count} apostrophes in {len(source_paths)} files under Sources and Plugins")
	print(f"{verb} {expectation_count} apostrophes in {len(expectation_paths)} files under Tests and Documentation")
	for path in source_paths + expectation_paths:
		print(f"  {path}")
	if check and (source_count or expectation_count):
		return 1
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))
