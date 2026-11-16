#!/usr/bin/env python3
"""Writes the synthetic benchmark shapes into OUTPUT in bench.py's fixture layout.

Usage: python3 -I make_fixtures.py OUTPUT [--repository CHECKOUT]

Every shape is synthetic, with invented names:
  issue646-12, issue646-16       #646's generator (make_screens.py), seed 1; runtime walks 4 screens deep from Root()
  issue646-mock-12               the same with `mock` and seed 5; runtime walks from Root.mock()
  E8 … E32-inline                spike 2's growth shape E built inline in one module (2.2.0 can build it)
  E8 … E32-seam                  the same with the seam in a module of its own (no 2.2.0 counterpart)
  L60, L240-inline / -seam       spike 2's low-sharing shape L, likewise
  D8 … D24                       the mock-overrides spike's shape D: one public seam per module, App's Root.mock()
                                 inlines them all, every init builds its children (no 2.2.0 counterpart)
  layered100                     100 modules in six layers, generate once per module (see layered.py)
  layered100-seams               the same graph with seams and public mocks (no 2.2.0 counterpart)
  example-package                Examples/Example Package Integration, generate and compile only
"""

import importlib.util
import json
import os
import random
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def write(path, text):
	os.makedirs(os.path.dirname(path), exist_ok=True)
	with open(path, "w") as handle:
		handle.write(text)


def load(name, path):
	spec = importlib.util.spec_from_file_location(name, path)
	module = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(module)
	return module


# MARK: #646


def issue646(output, name, screens, seed, mock):
	shape = f"{output}/{name}"
	arguments = [sys.executable, "-I", f"{HERE}/make_screens.py", f"{shape}/App", str(screens), str(seed)] + (["mock"] if mock else [])
	subprocess.run(arguments, check=True)
	# The issue's script writes classes without the `Instantiable` conformance, which `generate` does not need but the
	# compiler does: add it, so that the generated code compiles.
	for file in os.listdir(f"{shape}/App"):
		path = f"{shape}/App/{file}"
		text = open(path).read()
		write(path, re.sub(r"^public final class (\w+) \{", r"public final class \1: Instantiable {", text, flags=re.M))
	builders = {}
	for index in range(screens):
		text = open(f"{shape}/App/Screen{index}.swift").read()
		builders[index] = [(label, int(target)) for label, target in re.findall(r"let (screen\d+Builder): Instantiator<Screen(\d+)>", text)]
	lines = ["nonisolated(unsafe) var benchmarkValues = 0", ""]
	for index, children in builders.items():
		lines.append(f"func walk(_ value: Screen{index}, _ depth: Int) {{")
		lines.append("\tbenchmarkValues += 1")
		lines.append("\tguard depth > 0 else { return }")
		lines += [f'\twalk(value.{label}.instantiate("id"), depth - 1)' for label, _ in children]
		lines.append("}")
		lines.append("")
	root = "Root.mock()" if mock else "Root()"
	lines.append("func benchmarkIteration() -> Int {")
	lines.append("\tbenchmarkValues = 0")
	lines.append(f"\tlet root = {root}")
	lines.append('\twalk(root.screen0Builder.instantiate("id"), 4)')
	lines.append("\treturn benchmarkValues + 1")
	lines.append("}")
	write(f"{shape}/bench/Walk.swift", "\n".join(lines) + "\n")
	write(f"{shape}/modules.txt", "App generate\n")
	description = f"#646's generator, {screens} screens, seed {seed}{', mock' if mock else ''}; runtime: {root} and a walk 4 screens deep, per screen"
	# The mock variant generates about 340,000 lines, which a 16 GB machine cannot compile; #646 measures its generate only.
	measures = "measures=generate\n" if mock else ""
	write(f"{shape}/shape.txt", f"description={description}\n{measures}")


# MARK: Spike 2 (E and L)


HARNESS = "// A stand-in for the spike's counting harness, whose types the fixtures use only under SPIKE_TRACE.\npublic enum Harness {}\n"


def spike2(output, name, spec_script, size):
	emit = load("emit", f"{HERE}/spike2/emit.py")
	raw = json.loads(subprocess.run([sys.executable, "-I", f"{HERE}/spike2/{spec_script}", str(size)], check=True, capture_output=True, text=True).stdout)
	spec = emit.Spec(raw)
	header = "import Harness\nimport SafeDI\n\n"
	walker = emit.main_swift(spec).split("let arguments")[0]
	walker = walker.replace("import App\n", "")
	bench = walker + "func benchmarkIteration() -> Int {\n\tbuilt = 0\n\twalkEveryPath(Root())\n\treturn built + 1\n}\n"
	inline = f"{output}/{name}-inline"
	write(f"{inline}/Harness/Harness.swift", HARNESS)
	write(f"{inline}/App/Types.swift", header + emit.protocols(spec) + "".join(emit.feature_types(spec, seam=False)) + "".join(emit.app_types(spec)))
	write(f"{inline}/bench/Walk.swift", bench)
	write(f"{inline}/modules.txt", "Harness plain\nApp generate Harness\n")
	write(f"{inline}/shape.txt", f"description=spike 2 shape {name} built inline in one module; runtime: Root() and every path, per value\n")
	seam = f"{output}/{name}-seam"
	configuration = "#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n\n"
	write(f"{seam}/Harness/Harness.swift", HARNESS)
	write(f"{seam}/Feature/Types.swift", header + emit.protocols(spec) + configuration + "".join(emit.feature_types(spec)))
	write(f"{seam}/App/Types.swift", "import Feature\n" + header + "".join(emit.app_types(spec)))
	write(f"{seam}/bench/Walk.swift", bench)
	write(f"{seam}/modules.txt", "Harness plain\nFeature generate Harness\nApp generate Feature Harness\n")
	write(f"{seam}/shape.txt", f"description=spike 2 shape {name} with its seam in module Feature (no 2.2.0 counterpart); runtime: Root() and every path, per value\n")


# MARK: Shape D


def shape_d(output, n):
	"""The mock-overrides spike's shape_d.py with --walk, written as a fixture rather than generated in place."""
	shape = f"{output}/D{n}"
	rng = random.Random(1000 + n * 10 + 3)

	def walk_lines(properties):
		base = "id" if any(label == "id" for _, label, _ in properties) else "0"
		builders = [label for _, label, type_ in properties if type_.startswith("Instantiator<")]
		return [f"_ = {label}.instantiate({base} * 4 + {k + 1})" for k, label in enumerate(builders)]

	def declaration(attribute, name, superclass, initializer, properties, access="public"):
		body = [f"self.{label} = {label}" for _, label, _ in properties] + walk_lines(properties) + ["super.init()"] * bool(superclass)
		return (f"{attribute} {access} final class {name}: {superclass}Instantiable {{ {initializer} init({', '.join(f'{label}: {type_}' for _, label, type_ in properties)}) {{ "
				+ "; ".join(body) + " }\n" + "".join(f"    {a} let {label}: {type_}\n" for a, label, type_ in properties) + "}\n")

	edges = {i: sorted(rng.sample(range((i // 4 + 1) * 4, (i // 4 + 2) * 4), 3)) if i // 4 < n // 4 - 1 else [] for i in range(n)}
	plain = lambda c: ("@Instantiated", f"screen{c}Builder", f"Instantiator<Screen{c}>")
	modules = [("Core", [], "@Instantiable public final class Service: Instantiable { public init() {} }\nopen class Screen { public init() {} }\npublic protocol Api {}\n")]
	for i in sorted(edges, reverse=True):
		properties = [("@Forwarded", "id", "Int"), ("@Received", "service", "Service"), ("@Instantiated", f"model{i}", f"Model{i}")] + [plain(c) for c in edges[i]]
		source = declaration("@Instantiable(generateDependencyTree: true)", f"Screen{i}", "Screen, ", "public", properties)
		source += declaration("@Instantiable", f"Model{i}", "", "public", [("@Received", "id", "Int"), ("@Received", "service", "Service")])
		modules.append((f"M{i}", ["Core"] + [f"M{c}" for c in edges[i]], source))
	modules.append(("App", [m for m, _, _ in modules], "@Instantiable(fulfillingAdditionalTypes: [Api.self]) final class LiveApi: Api, Instantiable { init() {} }\n"
					+ declaration("@Instantiable(isRoot: true, generateMock: true)", "Root", "", "", [("@Instantiated", "service", "Service")] + [plain(i) for i in range(4)])))
	dependencies = {m: d for m, d, _ in modules}

	def below(m):
		return sorted({y for x in dependencies[m] for y in [x] + below(x)})

	for m, _, source in modules:
		write(f"{shape}/{m}/{m}.swift", "import SafeDI\n" + "".join(f"import {x}\n" for x in below(m)) + source)
	# Values one Root.mock() builds: Root, Service, and per screen built (on every path) the screen and its model.
	def built(screen):
		return 2 + sum(built(c) for c in edges[screen])

	values = 2 + sum(built(r) for r in range(4))
	write(f"{shape}/bench/Mock.swift", f"func benchmarkIteration() -> Int {{\n\twithExtendedLifetime(Root.mock()) {{}}\n\treturn {values}\n}}\n")
	write(f"{shape}/modules.txt", "".join(f"{m} generate {' '.join(dependencies[m])}\n" for m, _, _ in modules))
	write(f"{shape}/shape.txt", f"description=mock-overrides spike shape D, {n} screens, each a public seam in its own module (no 2.2.0 counterpart); runtime: Root.mock() building every screen, per value\n")


# MARK: Example package


def example_package(output, repository):
	source = f"{repository}/Examples/Example Package Integration/Sources"
	shape = f"{output}/example-package"
	order = ["SharedModule", "GrandchildrenModule", "ChildAModule", "ChildBModule", "ChildCModule", "RootModule"]
	dependencies = {"SharedModule": [], "GrandchildrenModule": ["SharedModule"], "ChildAModule": ["SharedModule", "GrandchildrenModule"],
					"ChildBModule": ["SharedModule", "GrandchildrenModule"], "ChildCModule": ["SharedModule", "GrandchildrenModule"],
					"RootModule": ["SharedModule", "ChildAModule", "ChildBModule", "ChildCModule"]}
	for module in order:
		shutil.copytree(f"{source}/{module}", f"{shape}/{module}")
	write(f"{shape}/modules.txt", "".join(f"{m} generate {' '.join(dependencies[m])}\n" for m in order))
	write(f"{shape}/shape.txt", "description=Examples/Example Package Integration (six modules), generate and compile only\n")


def main():
	output = os.path.abspath(sys.argv[1])
	repository = sys.argv[sys.argv.index("--repository") + 1] if "--repository" in sys.argv else os.path.dirname(os.path.dirname(HERE))
	shutil.rmtree(output, ignore_errors=True)
	os.makedirs(output)
	issue646(output, "issue646-12", 12, 1, False)
	issue646(output, "issue646-16", 16, 1, False)
	issue646(output, "issue646-mock-12", 12, 5, True)
	for n in (8, 16, 24, 32):
		spike2(output, f"E{n}", "spec_e.py", n)
	for n in (60, 240):
		spike2(output, f"L{n}", "spec_l.py", n)
	for n in (8, 12, 16, 20, 24):
		shape_d(output, n)
	layered = load("layered", f"{HERE}/layered.py")
	layered.write_shape(f"{output}/layered100", seams=False)
	layered.write_shape(f"{output}/layered100-seams", seams=True)
	example_package(output, repository)
	print("\n".join(sorted(os.listdir(output))))


if __name__ == "__main__":
	main()
