#!/usr/bin/env python3
"""Splits a `perf record --call-graph dwarf` profile of `SafeDITool generate` into the generator's phases.

Usage: perf script -i PERF.data -F tid,ip,sym --no-demangle | swift demangle --simplified | python3 -I phases.py

Each sample counts once, toward the first phase in this order with a frame anywhere in its stack: validation walks,
`ScopeGenerator.init` (so init called from `createScopeGenerator` counts as init), `createScopeGenerator`, emission,
parsing. It also prints each phase's
inclusive share: the samples with a frame of that phase anywhere in their stack. A sample of an async function's
continuation shows only the frames since its last resumption, so emission (`generateCode`, async) is attributed by its
own frames, not by its callers. Samples are CPU time across every thread, not instructions.
"""

import re
import sys

PHASES = [
	("validation walks", re.compile(r"\bvalidate[A-Z]\w*\(|ChildrenRequiringEachOtherValidation")),
	("ScopeGenerator.init facts", re.compile(r"ScopeGenerator\.init\(")),
	("createScopeGenerator passes", re.compile(r"createScopeGenerator")),
	# Emission: the code generation entry points and every other `ScopeGenerator` method (its facts are init's),
	# which an async continuation of `generateCode` shows without its caller.
	("emission", re.compile(r"generateCode|generatePropertyCode|generateMockRootCode|generateSeamRootCode|generateMockCode|generatePerRootCodeTrees|ScopeGenerator(UnderConstruction)?\.(?!init\()\w+|ScopeGenerator(UnderConstruction)?\.\w+\(")),
	("parsing and scope maps", re.compile(r"FileVisitor|InstantiableVisitor|SwiftParser|createTypeDescriptionToScopeMapping|createMockTypeDescriptionToScopeMapping")),
]


def main():
	samples, current = [], []
	for line in sys.stdin:
		if not line.strip():
			if current:
				samples.append(current)
			current = []
		else:
			current.append(line.strip())
	if current:
		samples.append(current)
	nearest = {name: 0 for name, _ in PHASES}
	nearest["other"] = 0
	nearest["unattributed (no frame unwound past the runtime)"] = 0
	inclusive = {name: 0 for name, _ in PHASES}
	for sample in samples:
		frames = sample[1:]  # the first line is the thread
		# The first phase, in PHASES's order, with a frame anywhere in the stack: a helper `ScopeGenerator` method that
		# `ScopeGenerator.init` calls counts as init, not emission.
		found = next((name for name, pattern in PHASES if any(pattern.search(frame) for frame in frames)), None)
		if found is None and not any("SafeDI" in frame or "Scope" in frame or "Instantiable" in frame for frame in frames):
			found = "unattributed (no frame unwound past the runtime)"
		nearest[found or "other"] += 1
		for name, pattern in PHASES:
			if any(pattern.search(frame) for frame in frames):
				inclusive[name] += 1
	total = len(samples) or 1
	print(f"{len(samples)} samples")
	print("| Phase | Share (each sample once) | Share (anywhere in stack) |")
	print("|---|---|---|")
	for name in list(nearest):
		share = f"{inclusive[name] / total * 100:.1f}%" if name in inclusive else ""
		print(f"| {name} | {nearest[name] / total * 100:.1f}% | {share} |")


if __name__ == "__main__":
	main()
