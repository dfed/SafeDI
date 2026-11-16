#!/usr/bin/env python3
"""Measures the code two `SafeDITool` builds generate, and `generate` itself, on a directory of fixture shapes.

Usage (Scripts/benchmark-2-3-1.sh wraps this):
  python3 -I bench.py [options] TOOL_A TOOL_B FIXTURES
  python3 -I bench.py --compare RUN1.json RUN2.json

TOOL_A and TOOL_B are `SafeDITool` executables, each inside the bin directory of a release build of its whole package
(`swift build -c release`), which also holds `SafeDI`'s module and objects and the `SafeDIMacros` executable: the
generated code of each tool compiles and links against its own SafeDI. TOOL_A is the baseline; ratios are B / A.

FIXTURES holds one directory per shape:
  <shape>/modules.txt   one module per line, in build order: `<Module> generate|plain [<Dependency>…]`
                        (`generate` modules run `SafeDITool generate`; `plain` modules only compile)
  <shape>/<Module>/     the module's Swift files (searched recursively)
  <shape>/bench/        optional: Swift files compiled into the bench module for the runtime measure only; they define
                        `func benchmarkIteration() -> Int`, which builds one root (or `mock()`) and returns how many
                        values it built
  <shape>/shape.txt     optional `key=value` lines: `bench_module=<Module>` (default: the last module),
                        `package=<name>` (default `Benchmark`), `description=…`

For each shape and tool, as a build system would (the Bazel rule of the tool's own version):
  generate  each `generate` module in order, with its direct dependencies' `.safedi` files as
            `--dependent-module-info-file-path` and every module beneath as `--transitive-module-info-file-path`
            where the tool takes it (else every module beneath as dependent module info, as 2.2.0's plugin passes
            them), and `--module-name` and `--package-name` where the tool takes them; the measure is the summed wall
            time over modules, the largest peak resident memory of one `generate`, and on macOS the summed
            instructions retired (`/usr/bin/time -l`); generated lines are the combined outputs' line count
  compile   each module with `swiftc -wmo -emit-module` at `-Onone` and at `-O`, then reruns the `-frontend -c` job of
            every `generate` module and sums their wall times (the driver run is untimed)
  runtime   builds every module at `-O` with the bench files, links, and runs the driver, which repeats
            `benchmarkIteration()` for at least 300 ms after one warm-up and prints nanoseconds per iteration
Every measure is taken RUNS times (default 5), the tools interleaved run by run, after one untimed warm-up of each
tool; the table shows medians with min–max. Every compile passes `-DDEBUG`, and `generate` gets the condition `DEBUG`.
"""

import argparse
import json
import os
import platform
import re
import shlex
import shutil
import statistics
import subprocess
import sys
import time

DRIVER = """// Added by bench.py: runs benchmarkIteration() for at least 300 ms after a warm-up.
@main enum BenchmarkDriver {
	static func main() {
		let clock = ContinuousClock()
		var values = benchmarkIteration()
		var iterations = 0
		let start = clock.now
		var elapsed = Duration.zero
		while elapsed < .milliseconds(300) {
			values = benchmarkIteration()
			iterations += 1
			elapsed = clock.now - start
		}
		let (seconds, attoseconds) = elapsed.components
		let nanoseconds = Double(seconds) * 1e9 + Double(attoseconds) / 1e9
		print("BENCHMARK \\(nanoseconds / Double(iterations)) \\(values)")
	}
}
"""

IS_DARWIN = platform.system() == "Darwin"


def log(message):
	print(message, file=sys.stderr, flush=True)


class Tool:
	def __init__(self, label, path):
		self.label = label
		self.path = os.path.realpath(path)
		self.bin = os.path.dirname(self.path)
		self.macros = next((c for c in (f"{self.bin}/SafeDIMacros-tool", f"{self.bin}/SafeDIMacros") if os.path.isfile(c)), None)
		self.modules = f"{self.bin}/Modules" if os.path.exists(f"{self.bin}/Modules/SafeDI.swiftmodule") else self.bin
		self.objects = sorted(os.path.join(f"{self.bin}/SafeDI.build", f) for f in os.listdir(f"{self.bin}/SafeDI.build") if f.endswith(".o")) if os.path.isdir(f"{self.bin}/SafeDI.build") else []
		missing = [what for what, ok in (("SafeDIMacros", self.macros), ("SafeDI.swiftmodule", os.path.exists(f"{self.modules}/SafeDI.swiftmodule")), ("SafeDI.build/*.o", self.objects)) if not ok]
		if missing:
			sys.exit(f"{path}: {', '.join(missing)} missing beside the tool; build the whole package with `swift build -c release`")
		help_text = subprocess.run([self.path, "generate", "--help"], capture_output=True, text=True).stdout
		self.takes_module_name = "--module-name" in help_text
		self.takes_transitive = "--transitive-module-info-file-path" in help_text
		self.version = subprocess.run(["git", "-C", self.bin, "describe", "--tags", "--always", "--dirty"], capture_output=True, text=True).stdout.strip() or "unknown"


def swiftc():
	return ["xcrun", "swiftc"] if IS_DARWIN and shutil.which("xcrun") else ["swiftc"]


def run_measured(command, cwd=None, timeout=3600):
	"""Runs command; returns (wall seconds, peak resident bytes, instructions or None, returncode, output tail)."""
	instructions = None
	if IS_DARWIN:
		command = ["/usr/bin/time", "-l"] + command
	start = time.perf_counter()
	process = subprocess.Popen(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
	try:
		stdout, stderr = process.communicate(timeout=timeout)
	except subprocess.TimeoutExpired:
		process.kill()
		stdout, stderr = process.communicate()
		return None, None, None, "timeout", (stdout + stderr)[-3000:]
	wall = time.perf_counter() - start
	# communicate() reaped the child; its rusage is gone, so read it through `resource` deltas would mix children.
	# Peak memory comes from /proc on Linux (VmHWM is unavailable after exit), so take it from GNU time instead.
	peak = None
	if IS_DARWIN:
		match = re.search(r"(\d+)\s+maximum resident set size", stderr)
		peak = int(match.group(1)) if match else None
		match = re.search(r"(\d+)\s+instructions retired", stderr)
		instructions = int(match.group(1)) if match else None
	return wall, peak, instructions, process.returncode, (stdout + stderr)[-3000:]


def run_generate(command):
	"""Runs one `generate`; on Linux, peak memory from os.wait4's rusage (kilobytes)."""
	if IS_DARWIN:
		return run_measured(command)
	start = time.perf_counter()
	process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
	output = process.stdout.read()
	_, status, usage = os.wait4(process.pid, 0)
	wall = time.perf_counter() - start
	process.returncode = os.waitstatus_to_exitcode(status)
	return wall, usage.ru_maxrss * 1024, None, process.returncode, output.decode(errors="replace")[-3000:]


COMPILE_TIMEOUT = 1800
# The largest generated modules (hundreds of thousands of lines) can take more memory than a small machine has; a cap
# on address space turns that into a reported failure rather than an out-of-memory kill. Linux only (macOS ignores it).
COMPILE_ADDRESS_SPACE = int(os.environ.get("BENCHMARK_COMPILE_MEMORY_LIMIT_GB", "11")) << 30


def limit_memory():
	try:
		import resource
		resource.setrlimit(resource.RLIMIT_AS, (COMPILE_ADDRESS_SPACE, COMPILE_ADDRESS_SPACE))
	except (ValueError, OSError):
		pass


def run_compile(command, text=True):
	"""Runs a compile with the memory cap and a timeout; returns (returncode or "timeout", output)."""
	try:
		process = subprocess.run(command, capture_output=True, text=text, timeout=COMPILE_TIMEOUT, preexec_fn=None if IS_DARWIN else limit_memory)
	except subprocess.TimeoutExpired:
		return "timeout", f"exceeded {COMPILE_TIMEOUT} s"
	return process.returncode, process.stdout + process.stderr if text else ""


class Shape:
	def __init__(self, directory):
		self.directory = directory
		self.name = os.path.basename(directory)
		self.options = {}
		if os.path.exists(f"{directory}/shape.txt"):
			for line in open(f"{directory}/shape.txt"):
				if "=" in line:
					key, value = line.rstrip("\n").split("=", 1)
					self.options[key.strip()] = value.strip()
		self.modules = []  # (name, generates, dependencies)
		for line in open(f"{directory}/modules.txt"):
			words = line.split()
			if words:
				self.modules.append((words[0], words[1] == "generate", words[2:]))
		self.dependencies = {name: dependencies for name, _, dependencies in self.modules}
		self.package = self.options.get("package", "Benchmark")
		# `measures=generate` limits a shape whose generated module is too large to compile on a small machine.
		self.measures = self.options.get("measures", "generate,compile,runtime").split(",")
		self.bench_module = self.options.get("bench_module", self.modules[-1][0])
		self.bench_files = sorted(os.path.join(dp, f) for dp, _, fs in os.walk(f"{directory}/bench") for f in fs if f.endswith(".swift")) if os.path.isdir(f"{directory}/bench") else []

	def sources(self, module):
		return sorted(os.path.join(dp, f) for dp, _, fs in os.walk(f"{self.directory}/{module}") for f in fs if f.endswith(".swift"))

	def beneath(self, module):
		result, stack = set(), list(self.dependencies[module])
		while stack:
			dependency = stack.pop()
			if dependency not in result:
				result.add(dependency)
				stack += self.dependencies[dependency]
		return [name for name, _, _ in self.modules if name in result]


class Run:
	"""One shape built with one tool, in WORK/<shape>/<label>."""

	def __init__(self, shape, tool, work):
		self.shape, self.tool = shape, tool
		self.out = os.path.join(work, shape.name, tool.label)
		shutil.rmtree(self.out, ignore_errors=True)
		os.makedirs(self.out)
		self.failure = None

	def generate_commands(self):
		commands = []
		for module, generates, dependencies in self.shape.modules:
			if not generates:
				continue
			out = self.out
			with open(f"{out}/{module}.csv", "w") as handle:
				handle.write(",".join(self.shape.sources(module)))
			command = [self.tool.path, "generate", f"{out}/{module}.csv", "--combined-output", f"{out}/{module}.gen.swift",
					   "--module-info-output", f"{out}/{module}.safedi", "--active-compilation-conditions", "DEBUG"]
			if self.tool.takes_module_name:
				command += ["--module-name", module, "--package-name", self.shape.package]
			# A tool that takes `--transitive-module-info-file-path` gets its direct dependencies' files there and every
			# module beneath in that option, as its Bazel rule passes them. An older tool gets every module beneath as
			# dependent module info, as its SwiftPM plugin passes them (its Bazel rule's direct-only list cannot
			# resolve a type two modules down).
			direct = [d for d in (dependencies if self.tool.takes_transitive else self.shape.beneath(module)) if self.generates(d)]
			if direct:
				with open(f"{out}/{module}.dependencies.csv", "w") as handle:
					handle.write(",".join(f"{out}/{d}.safedi" for d in direct))
				command += ["--dependent-module-info-file-path", f"{out}/{module}.dependencies.csv"]
				if self.tool.takes_transitive:
					with open(f"{out}/{module}.transitive.csv", "w") as handle:
						handle.write(",".join(f"{out}/{d}.safedi" for d in self.shape.beneath(module) if self.generates(d)))
					command += ["--transitive-module-info-file-path", f"{out}/{module}.transitive.csv"]
			commands.append(command)
		return commands

	def generates(self, module):
		return next(generates for name, generates, _ in self.shape.modules if name == module)

	def generate_once(self):
		wall, peak, instructions = 0.0, 0, 0
		for command in self.generate_commands():
			w, p, i, status, output = run_generate(command)
			if status != 0:
				self.failure = f"generate failed ({shlex.join(command[1:3])}…): {output.strip()[-1500:]}"
				return None
			wall += w
			peak = max(peak, p or 0)
			instructions = instructions + i if (i is not None and instructions is not None) else None
		return {"wall": wall, "peak": peak, "instructions": instructions}

	def generated_lines(self):
		return sum(open(f"{self.out}/{m}.gen.swift").read().count("\n") for m, generates, _ in self.shape.modules if generates)

	def compile_command(self, module, optimization, with_bench=False):
		sources = self.shape.sources(module)
		if self.generates(module):
			sources.append(f"{self.out}/{module}.gen.swift")
		if with_bench and module == self.shape.bench_module:
			sources += self.shape.bench_files + [f"{self.out}/BenchmarkDriver.swift"]
		directory = f"{self.out}/{optimization}{'-bench' if with_bench else ''}"
		return directory, (swiftc() + ["-emit-object", "-whole-module-optimization", "-parse-as-library", f"-{optimization}",
										"-o", f"{directory}/{module}.o", "-module-name", module, "-package-name", self.shape.package,
										"-emit-module", "-emit-module-path", f"{directory}/{module}.swiftmodule",
										"-I", self.tool.modules, "-I", directory, "-load-plugin-executable", f"{self.tool.macros}#SafeDIMacros",
										"-swift-version", "6", "-DDEBUG"] + sources)

	def build_all(self, optimization, with_bench=False):
		"""Compiles every module through the driver; returns {module: frontend -c command} for generate modules."""
		frontends = {}
		if with_bench:
			with open(f"{self.out}/BenchmarkDriver.swift", "w") as handle:
				handle.write(DRIVER)
		for module, generates, _ in self.shape.modules:
			directory, command = self.compile_command(module, optimization, with_bench)
			os.makedirs(directory, exist_ok=True)
			status, output = run_compile(command)
			if status != 0:
				self.failure = f"{module} did not compile at -{optimization}: {output.strip()[-1500:]}"
				return None
			if generates and not with_bench:
				jobs = subprocess.run(command + ["-###"], capture_output=True, text=True, check=True).stdout.strip().splitlines()
				frontend = [shlex.split(job) for job in jobs if " -frontend -c " in job]
				if len(frontend) != 1:
					self.failure = f"{module}: expected one `-frontend -c` job, found {len(frontend)}"
					return None
				frontends[module] = frontend[0]
		return frontends

	def link(self):
		directory = f"{self.out}/O-bench"
		objects = [f"{directory}/{module}.o" for module, _, _ in self.shape.modules]
		command = swiftc() + ["-O", "-o", f"{directory}/benchmark"] + objects + self.tool.objects
		process = subprocess.run(command, capture_output=True, text=True)
		if process.returncode != 0:
			self.failure = f"link failed: {(process.stdout + process.stderr).strip()[-1500:]}"
			return None
		return f"{directory}/benchmark"


def summary(values):
	values = [v for v in values if v is not None]
	if not values:
		return None
	return {"median": statistics.median(values), "min": min(values), "max": max(values), "samples": values}


def measure_shape(shape, tools, work, runs, measures):
	result = {"description": shape.options.get("description", ""), "tools": {}}
	measures = [m for m in measures if m in shape.measures]
	live = {}
	for tool in tools:
		run = Run(shape, tool, work)
		log(f"[{shape.name}] {tool.label}: generate (warm-up)")
		if run.generate_once() is None:
			result["tools"][tool.label] = {"failure": run.failure}
			log(f"[{shape.name}] {tool.label}: {run.failure[:300]}")
			continue
		live[tool.label] = run
		result["tools"][tool.label] = {"generated_lines": run.generated_lines()}

	def interleaved(name, measure_one):
		samples = {label: [] for label in live}
		for index in range(runs):
			for label, run in list(live.items()):
				samples[label].append(measure_one(run))
		return samples

	if "generate" in measures and live:
		log(f"[{shape.name}] generate ×{runs}")
		samples = interleaved("generate", lambda run: run.generate_once())
		for label, values in samples.items():
			values = [v for v in values if v is not None]
			result["tools"][label]["generate_wall"] = summary([v["wall"] for v in values])
			result["tools"][label]["generate_peak_bytes"] = summary([v["peak"] for v in values])
			result["tools"][label]["generate_instructions"] = summary([v["instructions"] for v in values])

	if "compile" in measures:
		for optimization in ("Onone", "O"):
			frontends = {}
			for label, run in list(live.items()):
				log(f"[{shape.name}] {label}: build at -{optimization}")
				built = run.build_all(optimization)
				if built is None:
					result["tools"][label][f"compile_{optimization}"] = {"failure": run.failure}
					log(f"[{shape.name}] {label}: {run.failure[:300]}")
					continue
				frontends[label] = built
			log(f"[{shape.name}] compile -{optimization} ×{runs}")
			samples = {label: [] for label in frontends}
			for index in range(runs + 1):
				for label, jobs in frontends.items():
					total = 0.0
					for module, job in jobs.items():
						start = time.perf_counter()
						status, _ = run_compile(job, text=False)
						total += time.perf_counter() - start
						if status != 0:
							total = None
							break
					if index > 0:  # run 0 is the warm-up
						samples[label].append(total)
			for label, values in samples.items():
				result["tools"][label][f"compile_{optimization}"] = summary(values)

	if "runtime" in measures and shape.bench_files:
		binaries = {}
		for label, run in list(live.items()):
			log(f"[{shape.name}] {label}: build the bench driver at -O")
			if run.build_all("O", with_bench=True) is None or (binary := run.link()) is None:
				result["tools"][label]["runtime_ns"] = {"failure": run.failure}
				log(f"[{shape.name}] {label}: {run.failure[:300]}")
				continue
			binaries[label] = binary
		log(f"[{shape.name}] runtime ×{runs}")
		samples = {label: [] for label in binaries}
		values_per_iteration = {}
		for index in range(runs + 1):
			for label, binary in binaries.items():
				process = subprocess.run([binary], capture_output=True, text=True, timeout=600)
				match = re.search(r"BENCHMARK (\S+) (\d+)", process.stdout)
				if index > 0:
					samples[label].append(float(match.group(1)) if match else None)
				if match:
					values_per_iteration[label] = int(match.group(2))
		for label, values in samples.items():
			result["tools"][label]["runtime_ns"] = summary(values)
			result["tools"][label]["values_per_iteration"] = values_per_iteration.get(label)
	for label, entry in result["tools"].items():
		failures = [value["failure"] for value in entry.values() if isinstance(value, dict) and "failure" in value]
		if failures and "failure" not in entry:
			# A shape this tool cannot build has no figures: its generate time would compare unlike work.
			entry.clear()
			entry["failure"] = failures[0]
	return result


MEASURES = [
	("generated_lines", "generated lines", None),
	("generate_wall", "generate wall (s)", 1),
	("generate_peak_bytes", "generate peak memory (MB)", 1 / 1e6),
	("generate_instructions", "generate instructions (billions)", 1 / 1e9),
	("compile_Onone", "compile -Onone (s)", 1),
	("compile_O", "compile -O (s)", 1),
	("runtime_ns", "runtime (ns per iteration)", 1),
	("runtime_ns_per_value", "runtime (ns per value)", 1),
]


def figure(entry, key, scale):
	if entry is None or "failure" in entry:
		return None
	if key == "runtime_ns_per_value":
		runtime, values = entry.get("runtime_ns"), entry.get("values_per_iteration")
		if not runtime or "median" not in runtime or not values:
			return None
		return {k: runtime[k] / values for k in ("median", "min", "max")}
	value = entry.get(key)
	if value is None:
		return None
	if isinstance(value, (int, float)):
		return {"median": value, "min": value, "max": value}
	if "failure" in value:
		return None
	return {k: value[k] * scale for k in ("median", "min", "max")}


def format_figure(value, key):
	if value is None:
		return "n/a"
	digits = 0 if key in ("generated_lines",) or value["median"] >= 1000 else 3 if value["median"] < 10 else 1
	if value["min"] == value["max"]:
		return f"{value['median']:,.{digits}f}"
	return f"{value['median']:,.{digits}f} ({value['min']:,.{digits}f}–{value['max']:,.{digits}f})"


def table(report):
	labels = report["tools"]
	lines = [f"| Shape | Measure | {labels[0]} | {labels[1]} | {labels[1]} / {labels[0]} |", "|---|---|---|---|---|"]
	slower = []
	for name, shape in report["shapes"].items():
		entries = [shape["tools"].get(label) for label in labels]
		failures = [f"{label}: {entry['failure'][:120]}" for label, entry in zip(labels, entries) if entry and "failure" in entry]
		for key, title, scale in MEASURES:
			figures = [figure(entry, key, scale) for entry in entries]
			if all(f is None for f in figures):
				continue
			ratio = figures[1]["median"] / figures[0]["median"] if all(figures) and figures[0]["median"] else None
			lines.append(f"| {name} | {title} | {format_figure(figures[0], key)} | {format_figure(figures[1], key)} | {f'{ratio:.2f}' if ratio else 'n/a'} |")
			if ratio and ratio > 1 and key != "generated_lines":
				slower.append((ratio, name, title))
		for failure in failures:
			lines.append(f"| {name} | did not build | {failure.replace('|', '/').replace(chr(10), ' ')} | | |")
	lines.append("")
	lines.append(f"Where {labels[1]} is slower than {labels[0]} (median ratio above 1), ranked:")
	lines.append("")
	lines.append("| Ratio | Shape | Measure |")
	lines.append("|---|---|---|")
	for ratio, name, title in sorted(slower, reverse=True):
		lines.append(f"| {ratio:.2f} | {name} | {title} |")
	return "\n".join(lines)


def compare(first, second, tolerance=0.03):
	"""Prints every wall-time median two runs disagree on by more than the tolerance."""
	a, b = json.load(open(first)), json.load(open(second))
	print(f"| Shape | Tool | Measure | Run 1 | Run 2 | Difference |\n|---|---|---|---|---|---|")
	disagreements = 0
	for name, shape in a["shapes"].items():
		for label, entry in shape["tools"].items():
			other = b["shapes"].get(name, {}).get("tools", {}).get(label)
			for key in ("generate_wall", "compile_Onone", "compile_O", "runtime_ns"):
				x, y = figure(entry, key, 1), figure(other, key, 1)
				if not x or not y:
					continue
				difference = y["median"] / x["median"] - 1
				mark = " **over 3%**" if abs(difference) > tolerance else ""
				disagreements += bool(mark)
				print(f"| {name} | {label} | {key} | {x['median']:.4g} | {y['median']:.4g} | {difference * 100:+.1f}%{mark} |")
	print(f"\n{disagreements} wall-time medians differ by more than {tolerance * 100:.0f}%.")


def machine():
	info = {"platform": platform.platform(), "processor": platform.processor() or platform.machine(), "cpus": os.cpu_count()}
	if os.path.exists("/proc/cpuinfo"):
		model = re.search(r"model name\s*:\s*(.*)", open("/proc/cpuinfo").read())
		info["processor"] = model.group(1) if model else info["processor"]
	elif IS_DARWIN:
		info["processor"] = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], capture_output=True, text=True).stdout.strip()
	info["compiler"] = subprocess.run(swiftc() + ["--version"], capture_output=True, text=True).stdout.strip().splitlines()[0]
	info["load_at_start"] = os.getloadavg()
	return info


def main():
	parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("--compare", nargs=2, metavar="RUN.json")
	parser.add_argument("--runs", type=int, default=5)
	parser.add_argument("--shapes", help="comma-separated shape names (default: every shape directory)")
	parser.add_argument("--skip-shapes", help="comma-separated shape names to leave out")
	parser.add_argument("--measures", default="generate,compile,runtime")
	parser.add_argument("--labels", default="A,B", help="names for the two tools in the table")
	parser.add_argument("--work", default=os.path.expanduser("~/.cache/safedi-benchmark-2-3-1"))
	parser.add_argument("--json", help="also write every sample to this file")
	parser.add_argument("--table", help="read a JSON report and print its table")
	parser.add_argument("tools", nargs="*")
	arguments = parser.parse_args()
	if arguments.compare:
		compare(*arguments.compare)
		return
	if arguments.table:
		print(table(json.load(open(arguments.table))))
		return
	if len(arguments.tools) != 3:
		parser.error("expected TOOL_A TOOL_B FIXTURES")
	labels = arguments.labels.split(",")
	tools = [Tool(label, path) for label, path in zip(labels, arguments.tools[:2])]
	fixtures = os.path.abspath(arguments.tools[2])
	names = sorted(n for n in os.listdir(fixtures) if os.path.exists(f"{fixtures}/{n}/modules.txt"))
	if arguments.shapes:
		wanted = arguments.shapes.split(",")
		names = [n for n in wanted if n in names] or sys.exit(f"no shape among {wanted}")
	if arguments.skip_shapes:
		names = [n for n in names if n not in arguments.skip_shapes.split(",")]
	report = {"tools": labels, "tool_paths": [t.path for t in tools], "tool_versions": [t.version for t in tools],
			  "machine": machine(), "runs": arguments.runs, "started": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "shapes": {}, "load": {}}
	for name in names:
		report["load"][name] = os.getloadavg()[0]
		report["shapes"][name] = measure_shape(Shape(f"{fixtures}/{name}"), tools, arguments.work, arguments.runs, arguments.measures.split(","))
		if arguments.json:
			with open(arguments.json, "w") as handle:
				json.dump(report, handle, indent=1)
	report["finished"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
	report["machine"]["load_at_end"] = os.getloadavg()
	if arguments.json:
		with open(arguments.json, "w") as handle:
			json.dump(report, handle, indent=1)
	m = report["machine"]
	print(f"Machine: {m['processor']}, {m['cpus']} CPUs, {m['platform']}; {m['compiler']}")
	print(f"Load (1-minute average) at start {m['load_at_start'][0]:.2f}, at end {m['load_at_end'][0]:.2f}, before each shape at most {max(report['load'].values() or [0]):.2f}")
	print(f"{labels[0]}: {tools[0].path} ({tools[0].version}); {labels[1]}: {tools[1].path} ({tools[1].version}); medians of {arguments.runs} with min–max")
	print()
	print(table(report))


if __name__ == "__main__":
	main()
