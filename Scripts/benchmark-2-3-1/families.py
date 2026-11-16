#!/usr/bin/env python3
"""Counts the types a generated file builds in both families: inside a `@Sendable` builder function (or closure) and
outside one.

Usage: python3 -I families.py GENERATED.swift…

A text scan of SafeDI's generated code, not a parse: a construction is a line `let … = Type(…`, `let … : … = Type(…`
or `return Type(…` (SafeDI's wrappers such as `Instantiator` and `LazilyInstantiated` are skipped); its family is
whether any enclosing brace was opened on a line that declares a `@Sendable` function or closure. Prints the counts
and the types built in both families.
"""

import re
import sys

WRAPPERS = {"Instantiator", "SendableInstantiator", "ErasedInstantiator", "SendableErasedInstantiator", "LazilyInstantiated", "Optional"}
CONSTRUCTION = re.compile(r"^\s*(?:let\s+\w+(?:\s*:\s*[^=]+)?\s*=\s*|return\s+)([A-Z][\w.]*)\(")


def scan(path, inside, outside):
	stack = []  # one entry per open brace: whether it opened a @Sendable scope
	for line in open(path):
		match = CONSTRUCTION.match(line)
		if match:
			name = match.group(1)
			if name.split(".")[-1] not in WRAPPERS and not name.startswith("__safeDI"):
				(inside if any(stack) else outside).add(name)
		sendable = "@Sendable" in line
		for character in line:
			if character == "{":
				stack.append(sendable)
				sendable = False  # only the first brace on the declaring line opens the @Sendable body
			elif character == "}" and stack:
				stack.pop()


def main():
	inside, outside = set(), set()
	for path in sys.argv[1:]:
		scan(path, inside, outside)
	both = sorted(inside & outside)
	print(f"types built inside a @Sendable builder: {len(inside)}; outside: {len(outside)}; in both families: {len(both)}")
	for name in both:
		print(f"  {name}")


if __name__ == "__main__":
	main()
