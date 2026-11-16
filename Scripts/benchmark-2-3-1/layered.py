"""A layered multi-module shape for bench.py, generated once per module as Bazel does.

Adapted from the safedi-positions benchmark's make_fixture.py, scaled from 40 to 100 modules. The proportions are that
script's invented ones, not an app's measured statistics:
  layers, bottom to top: 20, 20, 20, 20, 15, 5 modules; every module depends on L0M0 (which declares AppLogger), on two
  modules of the layer below (four for the top layer), and half the time on one module two layers below;
  10 to 30 types per module, 2 to 4 per file;
  a type receives `logger` 60% of the time, 15% of those also receive it renamed (`fulfilledByDependencyNamed:`);
  a type instantiates 0 to 2 types of its own module and 0 to 2 of a dependency (`0, 0, 1, 1, 2`); seams and roots
  instantiate 4 and 3, preferring seams of dependencies;
  30% of the other types generate a mock; each top-layer module has one root.
With seams=True (no 2.2.0 counterpart), the last type of each layer 3 and 4 module and of about half the layer 2 modules is a
seam (`generateDependencyTree: true`), two types per layer 1 and 2 module have public mocks, and each layer 2 and 3 module
has a preview type whose mock instantiates two public mocks. Both variants draw the same module graph from seed 7.
The bench module `Bench` builds every root once per iteration."""

import os
import random

LAYER_SIZES = [20, 20, 20, 20, 15, 5]


def lower_first(name):
	return name[0].lower() + name[1:]


def write_shape(root, seams, seed=7):
	rng = random.Random(seed)
	modules = [(f"L{layer}M{index}", layer) for layer, size in enumerate(LAYER_SIZES) for index in range(size)]
	by_layer = {}
	for name, layer in modules:
		by_layer.setdefault(layer, []).append(name)
	dependencies = {}
	for name, layer in modules:
		if name == "L0M0":
			dependencies[name] = []
			continue
		chosen = {"L0M0"}
		if layer >= 1:
			chosen.update(rng.sample(by_layer[layer - 1], 2 if layer < 5 else min(4, len(by_layer[layer - 1]))))
		if layer >= 2 and rng.random() < 0.5:
			chosen.add(rng.choice(by_layer[layer - 2]))
		dependencies[name] = sorted(chosen)

	types = {}
	for name, layer in modules:
		module_types = [{"name": f"{name}T{k}", "seam": False, "root": False, "mock": None} for k in range(rng.randint(10, 30))]
		seam_draw = rng.random()
		if seams and (layer in (3, 4) or (layer == 2 and seam_draw < 0.5)):
			module_types[-1]["seam"] = True
			module_types[-1]["name"] = f"{name}Feature"
		if layer == 5:
			module_types[-1]["root"] = True
			module_types[-1]["name"] = f"{name}Root"
		if seams and layer in (1, 2):
			for t in rng.sample(module_types[:-1], 2):
				t["mock"] = ".public"
		for t in module_types:
			if t["mock"] is None and not t["root"] and rng.random() < 0.3:
				t["mock"] = "true"
		if seams and layer in (2, 3):
			module_types.insert(len(module_types) - 1, {"name": f"{name}Preview", "seam": False, "root": False, "mock": "true", "preview": True})
		types[name] = module_types

	def buildable(t):
		return not (t["root"] or t["mock"] == ".public" or t.get("preview"))

	def exported(module):
		return [t for t in types[module] if buildable(t)]

	children = {}  # type name -> instantiated type names
	for name, layer in modules:
		module_types = types[name]
		declarations = []
		for k, t in enumerate(module_types):
			received, instantiated = [], []
			if name == "L0M0" and k == 0:
				t["name"] = "AppLogger"
			elif t["root"]:
				instantiated.append(("logger", "AppLogger"))
			elif t["seam"] or rng.random() < 0.6:
				received.append(("logger", "AppLogger"))
			if not (name == "L0M0" and k == 0):
				local = [u for u in module_types[:k] if buildable(u) and u["name"] != "AppLogger"]
				intra = 4 if (t["seam"] or t["root"]) else rng.randint(0, 2)
				for u in rng.sample(local, min(intra, len(local))):
					instantiated.append((lower_first(u["name"]), u["name"]))
				foreign = 3 if (t["seam"] or t["root"]) else rng.choice([0, 0, 1, 1, 2])
				if t.get("preview"):
					public_mocks = [u for dependency in dependencies[name] for u in types[dependency] if u["mock"] == ".public"]
					for u in rng.sample(public_mocks, min(2, len(public_mocks))):
						instantiated.append((lower_first(u["name"]), u["name"]))
				candidates = [u for dependency in dependencies[name] for u in exported(dependency) if u["name"] != "AppLogger"]
				if t["seam"] or t["root"]:
					preferred = [u for u in candidates if u["seam"]]
					chosen = rng.sample(preferred, min(2, len(preferred)))
					rest = [u for u in candidates if u not in chosen]
					chosen += rng.sample(rest, min(foreign - len(chosen), len(rest)))
				else:
					chosen = rng.sample(candidates, min(foreign, len(candidates)))
				for u in chosen:
					instantiated.append((lower_first(u["name"]), u["name"]))
			children[t["name"]] = [type_ for _, type_ in instantiated]
			arguments = []
			if t["root"]:
				arguments.append("isRoot: true")
			if t["seam"]:
				arguments.append("generateDependencyTree: true")
			if t["mock"]:
				arguments.append(f"generateMock: {t['mock']}")
			attribute = "@Instantiable" + (f"({', '.join(arguments)})" if arguments else "")
			renamed = [("sink", "LogSink")] if received and not t["seam"] and rng.random() < 0.15 else []
			parameters = received + renamed + instantiated
			lines = [attribute, f"public final class {t['name']}: Instantiable {{"]
			lines.append(f"\tpublic init({', '.join(f'{label}: {type_}' for label, type_ in parameters)}) {{")
			lines += [f"\t\tself.{label} = {label}" for label, _ in parameters]
			lines += ["\t}", "", "\tpublic func describe() -> String {", f"\t\tlet prefix = \"{t['name']}\"", "\t\treturn prefix + String(counter)", "\t}", ""]
			lines += [f"\t@Received let {label}: {type_}" for label, type_ in received]
			lines += [f"\t@Received(fulfilledByDependencyNamed: \"logger\", ofType: AppLogger.self) let {label}: {type_}" for label, type_ in renamed]
			lines += [f"\t@Instantiated let {label}: {type_}" for label, type_ in instantiated]
			lines += ["\tprivate var counter = 0", "}"]
			if t["name"] == "AppLogger":
				lines += ["", "public protocol LogSink: AnyObject {}", "extension AppLogger: LogSink {}"]
			declarations.append("\n".join(lines))
		directory = os.path.join(root, name)
		os.makedirs(directory)
		imports = "import SafeDI\n" + "".join(f"import {d}\n" for d in dependencies[name])
		index = file_number = 0
		while index < len(declarations):
			size = rng.randint(2, 4)
			with open(os.path.join(directory, f"File{file_number:02d}.swift"), "w") as handle:
				handle.write(imports + "\n" + "\n\n".join(declarations[index:index + size]) + "\n")
			index += size
			file_number += 1

	def size(type_name):
		return 1 + sum(size(child) for child in children[type_name])

	roots = [t["name"] for name, _ in modules for t in types[name] if t["root"]]
	values = sum(size(name) for name in roots)
	os.makedirs(os.path.join(root, "Bench"))
	top = by_layer[len(LAYER_SIZES) - 1]
	with open(os.path.join(root, "Bench", "Bench.swift"), "w") as handle:
		handle.write("".join(f"import {m}\n" for m in top) + "\n// The roots, built in bench/.\n")
	os.makedirs(os.path.join(root, "bench"))
	with open(os.path.join(root, "bench", "Roots.swift"), "w") as handle:
		handle.write("func benchmarkIteration() -> Int {\n" + "".join(f"\twithExtendedLifetime({name}()) {{}}\n" for name in roots) + f"\treturn {values}\n}}\n")
	with open(os.path.join(root, "modules.txt"), "w") as handle:
		handle.write("".join(f"{name} generate {' '.join(dependencies[name])}\n" for name, _ in modules))
		handle.write(f"Bench plain {' '.join(top)}\n")
	total = sum(len(v) for v in types.values())
	summary = (f"{len(modules)} modules, {total} types, {sum(t['seam'] for v in types.values() for t in v)} seams, "
			   f"{sum(t['mock'] == '.public' for v in types.values() for t in v)} public mocks, "
			   f"{sum(t['mock'] == 'true' for v in types.values() for t in v)} internal mocks, {len(roots)} roots, {values} values per iteration")
	with open(os.path.join(root, "shape.txt"), "w") as handle:
		handle.write(f"description=layered, generate once per module{' with seams and public mocks (no 2.2.0 counterpart)' if seams else ''}: {summary}\n")
	return summary

