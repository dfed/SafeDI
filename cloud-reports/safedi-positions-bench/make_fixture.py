#!/usr/bin/env python3
"""Creates a layered multi-module SafeDI fixture.

Layout: ROOT/<Module>/Sources/*.swift, ROOT/<Module>/dependencies.txt (direct deps), ROOT/order.txt (topological order).
Layers (bottom to top): 8, 8, 8, 8, 6, 2 modules = 40. Every module depends on L0M0 (declares AppLogger).
Seams: last type of each L3/L4 module and of about half the L2 modules. Public mocks: two types per L1/L2 module. Roots: one per L5 module. About 15% of the types that receive `logger` also receive it renamed as `sink: LogSink`.
"""
import os, random, shutil, sys

root = sys.argv[1]
seed = int(sys.argv[2]) if len(sys.argv) > 2 else 7
rng = random.Random(seed)
shutil.rmtree(root, ignore_errors=True)
layer_sizes = [8, 8, 8, 8, 6, 2]
modules = []  # (name, layer)
for layer, size in enumerate(layer_sizes):
	for index in range(size):
		modules.append((f"L{layer}M{index}", layer))
by_layer = {}
for name, layer in modules:
	by_layer.setdefault(layer, []).append(name)

dependencies = {}
for name, layer in modules:
	if name == "L0M0":
		dependencies[name] = []
		continue
	deps = {"L0M0"}
	if layer >= 1:
		deps.update(rng.sample(by_layer[layer - 1], 2 if layer < 5 else min(4, len(by_layer[layer - 1]))))
	if layer >= 2 and rng.random() < 0.5:
		deps.add(rng.choice(by_layer[layer - 2]))
	dependencies[name] = sorted(deps)

types = {}  # module -> list of dict(name, seam, root, mock)
for name, layer in modules:
	count = rng.randint(10, 30)
	module_types = []
	for k in range(count):
		module_types.append({"name": f"{name}T{k}", "seam": False, "root": False, "mock": None})
	if layer in (3, 4) or (layer == 2 and rng.random() < 0.5):
		module_types[-1]["seam"] = True
		module_types[-1]["name"] = f"{name}Feature"
	if layer == 5:
		module_types[-1]["root"] = True
		module_types[-1]["name"] = f"{name}Root"
	if layer in (1, 2):
		for t in rng.sample(module_types[:-1], 2):
			t["mock"] = ".public"
	for t in module_types:
		if t["mock"] is None and not t["root"] and rng.random() < 0.3:
			t["mock"] = "true"
	for t in module_types:
		t["access"] = "public"
	if layer == 1:
		# A public mock whose tree holds a `package` type of another package ("core") than its callers' ("features"), so
		# the callers' mocks cannot build it inline and call the public mock instead.
		for t in [u for u in module_types if u["mock"] == ".public"]:
			helper = {"name": t["name"] + "Helper", "seam": False, "root": False, "mock": None, "access": "package", "helper": True}
			module_types.insert(module_types.index(t), helper)
			t["helper"] = helper["name"]
	if layer in (2, 3):
		module_types.insert(len(module_types) - 1, {"name": f"{name}Preview", "seam": False, "root": False, "mock": "true", "access": "public", "preview": True})
	types[name] = module_types

def buildable(t):
	"""Whether production trees may instantiate t: not a root, a public mock, its helper or a preview host."""
	return not (t["root"] or t["mock"] == ".public" or t.get("helper") is True or t.get("preview"))

def exported(module):
	"""Types other modules' production trees may instantiate."""
	return [t for t in types[module] if buildable(t)]

for name, layer in modules:
	module_types = types[name]
	declarations = []
	for k, t in enumerate(module_types):
		received = []
		instantiated = []
		if name == "L0M0" and k == 0:
			t["name"] = "AppLogger"
		elif t["root"]:
			instantiated.append(("logger", "AppLogger"))
		else:
			if t["seam"] or rng.random() < 0.6:
				received.append(("logger", "AppLogger"))
		if not (name == "L0M0" and k == 0):
			local = [u for u in module_types[:k] if buildable(u) and u["name"] != "AppLogger"]
			intra = 4 if (t["seam"] or t["root"]) else rng.randint(0, 2)
			if t.get("helper") is True:
				intra = 0
			for u in rng.sample(local, min(intra, len(local))):
				instantiated.append((u["name"][0].lower() + u["name"][1:], u["name"]))
			foreign = 3 if (t["seam"] or t["root"]) else rng.choice([0, 0, 1, 1, 2])
			if t.get("helper") is True:
				foreign = 0
			if isinstance(t.get("helper"), str):
				instantiated.append((t["helper"][0].lower() + t["helper"][1:], t["helper"]))
			if t.get("preview"):
				public_mocks = [u for dep in dependencies[name] for u in types[dep] if u["mock"] == ".public"]
				for u in rng.sample(public_mocks, min(2, len(public_mocks))):
					instantiated.append((u["name"][0].lower() + u["name"][1:], u["name"]))
			candidates = [u for dep in dependencies[name] for u in exported(dep) if u["name"] != "AppLogger"]
			# Prefer seams for the trees of seams and roots, so seams call seams.
			if t["seam"] or t["root"]:
				seams = [u for u in candidates if u["seam"]]
				chosen = rng.sample(seams, min(2, len(seams)))
				chosen += rng.sample([u for u in candidates if u not in chosen], min(foreign - len(chosen), len(candidates) - len(chosen)))
			else:
				chosen = rng.sample(candidates, min(foreign, len(candidates)))
			for u in chosen:
				instantiated.append((u["name"][0].lower() + u["name"][1:], u["name"]))
		arguments = []
		if t["root"]:
			arguments.append("isRoot: true")
		if t["seam"]:
			arguments.append("generateDependencyTree: true")
		if t["mock"]:
			arguments.append(f"generateMock: {t['mock']}")
		attribute = "@Instantiable" + (f"({', '.join(arguments)})" if arguments else "")
		renamed = []
		if received and not t["seam"] and rng.random() < 0.15:
			# A rename, whose generated assignment names its declaration's line.
			renamed.append(("sink", "LogSink"))
		parameters = received + renamed + instantiated
		access = t["access"]
		lines = [attribute, f"{access} final class {t['name']}: Instantiable {{"]
		lines.append(f"\t{access} init({', '.join(f'{label}: {typ}' for label, typ in parameters)}) {{")
		for label, _ in parameters:
			lines.append(f"\t\tself.{label} = {label}")
		lines.append("\t}")
		lines.append("")
		lines.append("\tpublic func describe() -> String {")
		lines.append(f"\t\tlet prefix = \"{t['name']}\"")
		lines.append("\t\treturn prefix + String(counter)")
		lines.append("\t}")
		lines.append("")
		for label, typ in received:
			lines.append(f"\t@Received let {label}: {typ}")
		for label, typ in renamed:
			lines.append(f"\t@Received(fulfilledByDependencyNamed: \"logger\", ofType: AppLogger.self) let {label}: {typ}")
		for label, typ in instantiated:
			lines.append(f"\t@Instantiated let {label}: {typ}")
		lines.append("\tprivate var counter = 0")
		lines.append("}")
		if t["name"] == "AppLogger":
			lines.append("")
			lines.append("public protocol LogSink: AnyObject {}")
			lines.append("extension AppLogger: LogSink {}")
		declarations.append("\n".join(lines))
	# 2-4 types per file.
	directory = os.path.join(root, name, "Sources")
	os.makedirs(directory)
	imports = "import SafeDI\n" + "".join(f"import {d}\n" for d in dependencies[name])
	index = 0
	file_number = 0
	while index < len(declarations):
		size = rng.randint(2, 4)
		chunk = declarations[index:index + size]
		with open(os.path.join(directory, f"File{file_number:02d}.swift"), "w") as handle:
			handle.write(imports + "\n" + "\n\n".join(chunk) + "\n")
		index += size
		file_number += 1
	with open(os.path.join(root, name, "package.txt"), "w") as handle:
		handle.write("core\n" if layer <= 1 else "features\n")
	with open(os.path.join(root, name, "dependencies.txt"), "w") as handle:
		handle.write("".join(d + "\n" for d in dependencies[name]))

with open(os.path.join(root, "order.txt"), "w") as handle:
	handle.write("".join(name + "\n" for name, _ in modules))
total = sum(len(v) for v in types.values())
print(f"{len(modules)} modules, {total} types, "
	f"{sum(t['seam'] for v in types.values() for t in v)} seams, "
	f"{sum(t['mock'] == '.public' for v in types.values() for t in v)} public mocks, "
	f"{sum(t['mock'] == 'true' for v in types.values() for t in v)} internal mocks, "
	f"{sum(t['root'] for v in types.values() for t in v)} roots, "
	f"{sum(open(os.path.join(dp, f)).read().count('fulfilledByDependencyNamed') for dp, _, fs in os.walk(root) for f in fs if f.endswith('.swift'))} renames")
