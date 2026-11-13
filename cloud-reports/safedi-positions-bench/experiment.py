#!/usr/bin/env python3
"""experiment.py FIXTURE WORK TOOL TARGET [--split] [--repeats N] [--edits a,b]

Copies FIXTURE to WORK, builds every module, then for each edit to TARGET's first file reruns what Bazel would rerun and
reports, per input model, how many actions rerun, how many of those change no output, and the time those spend.
"""
import json, os, re, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bazel_sim import Graph, Runner, parse_time, sha

fixture, work, tool, target = sys.argv[1:5]
split = "--split" in sys.argv
repeats = int(sys.argv[sys.argv.index("--repeats") + 1]) if "--repeats" in sys.argv else 3
selected = sys.argv[sys.argv.index("--edits") + 1].split(",") if "--edits" in sys.argv else None
MODELS = ["current", "split+unused"] if split else ["current", "unused"]

shutil.rmtree(work, ignore_errors=True)
shutil.copytree(fixture, work)
graph = Graph(work)
runner = Runner(graph, tool, ".out", split)
out = os.path.join(work, ".out")
first_file = os.path.join(work, target, "Sources", "File00.swift")
pristine = open(first_file).read()

for m in graph.order:
	runner.run(m)
baseline_outputs = {m: runner.outputs(m) for m in graph.order}
baseline_unused = {m: runner.unused_list(m) for m in graph.order}
baseline_digests = {m: runner.input_digests(m, baseline_unused[m]) for m in graph.order}
baseline_dir = os.path.join(work, ".baseline-out")
shutil.rmtree(baseline_dir, ignore_errors=True)
shutil.copytree(out, baseline_dir)

def first_type_span(text):
	starts = [m.start() for m in re.finditer(r"^@Instantiable", text, re.M)]
	return starts[0], starts[1]

def insert_before_first_type(text, insertion):
	start, _ = first_type_span(text)
	return text[:start] + insertion + text[start:]

def in_first_type(text, old, new):
	start, end = first_type_span(text)
	body = text[start:end]
	assert old in body, old
	return text[:start] + body.replace(old, new, 1) + text[end:]

def add_dependency(text):
	start, end = first_type_span(text)
	body = text[start:end]
	body = re.sub(r"public init\((.*?)\) \{", lambda mm: "public init(" + (mm.group(1) + ", " if mm.group(1) else "") + "addedDependency: L0M0T1) {\n\t\tself.addedDependency = addedDependency", body, count=1)
	body = body.replace("\tprivate var counter = 0", "\t@Instantiated let addedDependency: L0M0T1\n\tprivate var counter = 0", 1)
	return text[:start] + body + text[end:]

def reorder(text):
	starts = [m.start() for m in re.finditer(r"^@Instantiable", text, re.M)]
	first, second = text[starts[0]:starts[1]], text[starts[1]:(starts[2] if len(starts) > 2 else len(text))]
	if not second.endswith("\n\n"):
		second, first = second.rstrip("\n") + "\n\n", first.rstrip("\n") + "\n"
	return text[:starts[0]] + second + first + text[(starts[2] if len(starts) > 2 else len(text)):]

def rename_local(text):
	start, end = first_type_span(text)
	body = text[start:end].replace("let prefix =", "let typePrefix =").replace("return prefix +", "return typePrefix +")
	return text[:start] + body + text[end:]

NEW_TYPE = """
@Instantiable
public final class AddedType: Instantiable {
	public init() {}
}
"""

EDITS = {
	"blank-line": lambda t: insert_before_first_type(t, "\n"),
	"comment": lambda t: insert_before_first_type(t, "// Explains the type below.\n"),
	"add-import": lambda t: "import Foundation\n" + t,
	"add-method": lambda t: in_first_type(t, "\tpublic func describe()", "\tpublic func reset() {\n\t\tcounter = 0\n\t}\n\n\tpublic func describe()"),
	"init-body-line": lambda t: in_first_type(t, "\t}\n\n\tpublic func describe()", "\t\tprecondition(counter == 0)\n\t}\n\n\tpublic func describe()"),
	"stored-property": lambda t: in_first_type(t, "\tprivate var counter = 0", "\tprivate var counter = 0\n\tprivate var label = \"label\""),
	"rename-local": rename_local,
	"reorder-types": reorder,
	"add-type-at-end": lambda t: t + NEW_TYPE,
	"add-dependency": add_dependency,
}

def restore():
	shutil.rmtree(out)
	shutil.copytree(baseline_dir, out)

results = []
for name, edit in EDITS.items():
	if selected and name not in selected:
		continue
	timings = []
	for repeat in range(repeats):
		restore()
		with open(first_file, "w") as handle:
			handle.write(edit(pristine))
		reruns = {model: [] for model in MODELS}
		wasted = {model: [] for model in MODELS}
		unsound = {model: [] for model in MODELS}
		changed_outputs = {}
		times = {}
		safedi_changed = None
		for m in graph.order:
			digests = runner.input_digests(m, baseline_unused[m])
			if digests["current"] == baseline_digests[m]["current"]:
				continue
			timing_file = os.path.abspath(os.path.join(work, f".time-{m}.txt"))
			runner.run(m, timing_file)
			times[m] = parse_time(timing_file)
			outputs = runner.outputs(m)
			# The unused list is bookkeeping, not an output a dependent reads.
			changed = sorted(s for s in outputs if s != ".unused" and outputs[s] != baseline_outputs[m].get(s))
			changed_outputs[m] = changed
			if m == target:
				safedi_changed = changed
			for model in MODELS:
				if digests[model] != baseline_digests[m][model]:
					reruns[model].append(m)
					if not changed:
						wasted[model].append(m)
				elif changed:
					unsound[model].append((m, changed))
		timings.append(times)
	if "--keep" in sys.argv:
		shutil.rmtree(os.path.join(work, ".out-" + name), ignore_errors=True)
		shutil.copytree(out, os.path.join(work, ".out-" + name))
	# Average each rerun's time over the repeats.
	average = {m: tuple(sum(t[m][i] for t in timings) / len(timings) for i in range(2)) for m in timings[0]}
	row = {"edit": name, "target_outputs_changed": safedi_changed, "models": {}}
	for model in MODELS:
		row["models"][model] = {
			"reruns": len(reruns[model]),
			"reruns_excluding_target": len([m for m in reruns[model] if m != target]),
			"wasted": len(wasted[model]),
			"wasted_user_s": round(sum(average[m][0] for m in wasted[model]), 3),
			"wasted_wall_s": round(sum(average[m][1] for m in wasted[model]), 3),
			"rerun_user_s": round(sum(average[m][0] for m in reruns[model]), 3),
			"rerun_wall_s": round(sum(average[m][1] for m in reruns[model]), 3),
			"unsound": unsound[model],
		}
	row["dependents_whose_output_changed"] = sorted(m for m, c in changed_outputs.items() if c and m != target)
	row["dependents_whose_swift_changed"] = sorted(m for m, c in changed_outputs.items() if ".swift" in c and m != target)
	row["dependents_whose_safedi_changed"] = sorted(m for m, c in changed_outputs.items() if ".safedi" in c and m != target)
	row["per_repeat_total_user_s"] = [round(sum(v[0] for v in t.values()), 3) for t in timings]
	row["per_repeat_total_wall_s"] = [round(sum(v[1] for v in t.values()), 3) for t in timings]
	results.append(row)
	print(json.dumps(row), flush=True)

with open(first_file, "w") as handle:
	handle.write(pristine)
restore()
json.dump(results, open(os.path.join(os.path.dirname(os.path.abspath(work)), os.path.basename(work) + "-results.json"), "w"), indent=1)
print(f"target {target}: {len(graph.dependents(target))} transitive dependents of {len(graph.order)} modules")
