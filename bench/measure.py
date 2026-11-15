#!/usr/bin/env python3
"""Compare SafeDI variants on generated size, compile time, runtime and creation traces.

Spike tooling for one generated function per type. Runs unchanged on macOS and Linux, with Python 3.9 or later and no
packages beyond the standard library. Timing uses `time.perf_counter` and `resource.getrusage(RUSAGE_CHILDREN)`.

Each `--variant NAME=PATH` names a `SafeDITool` binary or a SafeDI checkout (built here with
`swift build -c release --product SafeDITool --traits sourceBuild` when its binary is missing).

CSV mode
    measure.py csv FILES.csv [--driver main.swift] --variant base=PATH --variant spike=PATH [options]

    Runs `SafeDITool generate FILES.csv --combined-output Generated.swift` per variant, then builds one driver package
    with an executable target per variant (the listed files, `Generated.swift` and the driver; Swift 6 mode, warnings as
    errors) against `--safedi` (a checkout; default: the first variant that is a checkout). Measures:
      - generated lines and bytes, and `generate` wall time;
      - compile CPU and wall at -Onone (the batch frontend invocation whose primary file is `Generated.swift`) and at -O
        (the module's whole-module frontend invocation), each rerun alone without `-supplementary-output-file-map`,
        alternating variants, plus one run per variant with `-stats-output-dir`;
      - runtime: the release executable (built with `-Xswiftc -DNO_TRACE`) run with `--time N`, construction and walk;
      - traces: the debug executable's output, compared byte for byte between variants (`--trace`).

Package mode
    measure.py package PACKAGE_DIR --variant base=CHECKOUT --variant spike=CHECKOUT [options]

    PACKAGE_DIR is a multi-module SwiftPM package using the `SafeDIGenerator` plugin and depending on a SafeDI checkout by
    `.package(path: …)`. Each variant gets a copy of the package whose `path:` names the variant's checkout. Each copy is
    built with `swift build --disable-sandbox -v` (debug, and `-c release` for -O); every generated root file in the
    plugin output is found, and each module's frontend command is timed as in CSV mode.

Common options
    --configs onone,o      which compile configurations to time (default both)
    --compile-runs N       runs per variant and configuration (default 5)
    --runtime-runs N       `--time N` repeats per run, and runs per variant (default 11)
    --workdir DIR          where packages and outputs go (default ./measure-work)
    --json PATH            write every figure as JSON
    --no-runtime / --no-compile / --trace
"""
import argparse
import json
import os
import platform
import re
import resource
import shlex
import shutil
import statistics
import subprocess
import sys
import time


def log(*parts):
    print(*parts, file=sys.stderr, flush=True)


def run(command, cwd=None, env=None, capture=True, check=True):
    """Runs a command; returns (stdout, stderr, wall seconds, user CPU seconds, system CPU seconds)."""
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    start = time.perf_counter()
    result = subprocess.run(command, cwd=cwd, env=env, stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None, text=True)
    wall = time.perf_counter() - start
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    if check and result.returncode != 0:
        log("command failed:", shlex.join(command) if isinstance(command, list) else command)
        if capture:
            log((result.stdout or "")[-4000:])
            log((result.stderr or "")[-8000:])
        raise SystemExit(1)
    return result.stdout or "", result.stderr or "", wall, after.ru_utime - before.ru_utime, after.ru_stime - before.ru_stime


def summary(values):
    values = sorted(values)
    if not values:
        return {}
    return {"median": statistics.median(values), "min": values[0], "max": values[-1], "n": len(values), "all": values}


def tool_binary(path):
    if os.path.isfile(path):
        return os.path.abspath(path)
    binary = os.path.join(path, ".build", "release", "SafeDITool")
    if not os.path.isfile(binary):
        log(f"building SafeDITool in {path}")
        run(["swift", "build", "-c", "release", "--product", "SafeDITool", "--traits", "sourceBuild"], cwd=path, capture=False)
    return os.path.abspath(binary)


def parse_variants(values):
    variants = []
    for value in values:
        name, _, path = value.partition("=")
        if not name or not path:
            raise SystemExit(f"--variant takes NAME=PATH, not {value}")
        variants.append((name, os.path.abspath(path)))
    return variants


def frontend_commands(verbose_output):
    """The `swift-frontend -frontend -c` commands of a `swift build -v` log."""
    commands = []
    for line in verbose_output.splitlines():
        if "-frontend" in line and " -c " in line and "swift-frontend" in line:
            try:
                commands.append(shlex.split(line.strip()))
            except ValueError:
                continue
    return commands


def module_of(command):
    return command[command.index("-module-name") + 1] if "-module-name" in command else None


def primary_files(command):
    return [command[i + 1] for i, argument in enumerate(command) if argument == "-primary-file"]


def standalone(command):
    """The command without its supplementary output file map, which a rerun does not need."""
    result, skip = [], False
    for argument in command:
        if skip:
            skip = False
            continue
        if argument == "-supplementary-output-file-map":
            skip = True
            continue
        result.append(argument)
    return result


def time_commands(commands_by_variant, runs, cwd_by_variant, stats_dir):
    """Times each variant's commands alternately; returns per variant a summary of wall and CPU (user + system)."""
    results = {name: {"wall": [], "cpu": [], "user": []} for name in commands_by_variant}
    for run_index in range(runs):
        order = list(commands_by_variant) if run_index % 2 == 0 else list(reversed(list(commands_by_variant)))
        for name in order:
            wall_total = cpu_total = user_total = 0.0
            for command in commands_by_variant[name]:
                _, _, wall, user, system = run(standalone(command), cwd=cwd_by_variant[name])
                wall_total += wall
                cpu_total += user + system
                user_total += user
            results[name]["wall"].append(wall_total)
            results[name]["cpu"].append(cpu_total)
            results[name]["user"].append(user_total)
            log(f"  {name} run {run_index + 1}: wall {wall_total:.3f}s cpu {cpu_total:.3f}s")
    counters = {}
    for name, commands in commands_by_variant.items():
        directory = os.path.join(stats_dir, name)
        shutil.rmtree(directory, ignore_errors=True)
        os.makedirs(directory)
        for command in commands:
            run(standalone(command) + ["-stats-output-dir", directory], cwd=cwd_by_variant[name])
        counters[name] = read_counters(directory)
    return {name: {key: summary(value) for key, value in result.items()} | {"counters": counters[name],
            "commands": [shlex.join(standalone(c)) for c in commands_by_variant[name]]}
            for name, result in results.items()}


def read_counters(directory):
    totals = {}
    for file_name in sorted(os.listdir(directory)):
        if not file_name.endswith(".json"):
            continue
        with open(os.path.join(directory, file_name)) as handle:
            try:
                data = json.load(handle)
            except ValueError:
                continue
        for key, value in data.items():
            if isinstance(value, (int, float)) and (key.startswith("time.swift") or key.startswith("Frontend.") or key.startswith("AST.") or key.startswith("SILModule.") or key.startswith("IRModule.") or key.startswith("LLVM.") or key.startswith("Sema.")):
                totals[key] = totals.get(key, 0) + value
    return totals


def counter_differences(counters, base, other, limit=12):
    keys = set(counters[base]) | set(counters[other])
    rows = []
    for key in keys:
        a, b = counters[base].get(key, 0), counters[other].get(key, 0)
        if a or b:
            rows.append((abs(b - a) / max(abs(a), 1e-9), key, a, b))
    rows.sort(reverse=True)
    return [{"counter": key, base: a, other: b} for _, key, a, b in rows[:limit]]


def runtime(executables, runs, repeats):
    results = {name: {"build": [], "walk": []} for name in executables}
    pattern = re.compile(r"build median (\S+) (\w+) walk median (\S+) (\w+)")
    scale = {"seconds": 1.0, "milliseconds": 1e-3, "microseconds": 1e-6, "nanoseconds": 1e-9, "attoseconds": 1e-18}
    for run_index in range(runs):
        order = list(executables) if run_index % 2 == 0 else list(reversed(list(executables)))
        for name in order:
            output, _, _, _, _ = run([executables[name], "--time", str(repeats)])
            match = pattern.search(output)
            if not match:
                raise SystemExit(f"unexpected runtime output: {output}")
            results[name]["build"].append(float(match.group(1)) * scale[match.group(2)])
            results[name]["walk"].append(float(match.group(3)) * scale[match.group(4)])
    return {name: {key: summary(value) for key, value in result.items()} for name, result in results.items()}


DRIVER_MANIFEST = """// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeasureDriver",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [.package(path: {safedi})],
    targets: [
{targets}
    ]
)
"""
DRIVER_TARGET = """        .executableTarget(
            name: "{name}",
            dependencies: [.product(name: "SafeDI", package: "SafeDI")],
            path: "Sources/{name}",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),"""


def target_name(variant):
    return "Driver_" + re.sub(r"[^A-Za-z0-9]", "_", variant)


def csv_mode(arguments, variants):
    files_csv = os.path.abspath(arguments.input)
    with open(files_csv) as handle:
        sources = [path.strip() for path in handle.read().replace("\n", ",").split(",") if path.strip()]
    driver = os.path.abspath(arguments.driver or os.path.join(os.path.dirname(files_csv), "main.swift"))
    safedi = arguments.safedi or next((path for _, path in variants if os.path.isdir(path)), None)
    if not safedi:
        raise SystemExit("--safedi names a checkout for the SafeDI library when every variant is a binary")
    work = os.path.abspath(arguments.workdir)
    package = os.path.join(work, "driver")
    shutil.rmtree(package, ignore_errors=True)
    os.makedirs(package)
    report = {"mode": "csv", "input": files_csv, "machine": machine(), "variants": {}}
    for name, path in variants:
        binary = tool_binary(path)
        source_directory = os.path.join(package, "Sources", target_name(name))
        os.makedirs(source_directory)
        for source in sources:
            shutil.copy(source, source_directory)
        shutil.copy(driver, os.path.join(source_directory, "main.swift"))
        generated = os.path.join(source_directory, "Generated.swift")
        walls = []
        for _ in range(arguments.generate_runs):
            _, _, wall, _, _ = run([binary, "generate", files_csv, "--combined-output", generated])
            walls.append(wall)
        with open(generated, "rb") as handle:
            content = handle.read()
        report["variants"][name] = {"tool": binary, "generated_lines": content.count(b"\n"), "generated_bytes": len(content),
                                    "generate_wall": summary(walls), "generate_command": shlex.join([binary, "generate", files_csv, "--combined-output", generated])}
        log(f"{name}: {content.count(chr(10).encode())} lines, {len(content)} bytes")
    with open(os.path.join(package, "Package.swift"), "w") as handle:
        handle.write(DRIVER_MANIFEST.replace("{safedi}", json.dumps(os.path.abspath(safedi)))
                     .replace("{targets}", "\n".join(DRIVER_TARGET.replace("{name}", target_name(n)) for n, _ in variants)))
    configurations = arguments.configs.split(",")
    builds = {}
    if "onone" in configurations or arguments.trace:
        log("building debug")
        stdout, stderr, wall, user, system = run(["swift", "build", "-v"], cwd=package)
        builds["onone"] = stdout + stderr
    if "o" in configurations or not arguments.no_runtime:
        log("building release")
        stdout, stderr, _, _, _ = run(["swift", "build", "-c", "release", "-v", "-Xswiftc", "-DNO_TRACE"], cwd=package)
        builds["o"] = stdout + stderr
    if not arguments.no_compile:
        for configuration in configurations:
            commands = frontend_commands(builds[configuration])
            by_variant = {}
            for name, _ in variants:
                module = target_name(name)
                if configuration == "onone":
                    selected = [c for c in commands if module_of(c) == module and any(p.endswith(os.sep + "Generated.swift") and os.sep + module + os.sep in p for p in primary_files(c))]
                else:
                    selected = [c for c in commands if module_of(c) == module]
                if not selected:
                    raise SystemExit(f"no frontend command found for {module} at {configuration}")
                by_variant[name] = selected
            log(f"timing compile at {configuration}")
            timing = time_commands(by_variant, arguments.compile_runs, {n: package for n, _ in variants}, os.path.join(work, "stats-" + configuration))
            base = variants[0][0]
            for name, _ in variants:
                report["variants"][name]["compile_" + configuration] = timing[name]
            for name, _ in variants[1:]:
                report.setdefault("counter_differences_" + configuration, {})[name] = counter_differences({n: timing[n]["counters"] for n, _ in variants}, base, name)
    if not arguments.no_runtime:
        executables = {name: os.path.join(package, ".build", "release", target_name(name)) for name, _ in variants}
        log("timing runtime")
        result = runtime(executables, arguments.runtime_runs, arguments.runtime_runs)
        for name, _ in variants:
            report["variants"][name]["runtime"] = result[name] | {"command": f"{executables[name]} --time {arguments.runtime_runs}"}
    if arguments.trace:
        traces = {}
        for name, _ in variants:
            output, _, _, _, _ = run([os.path.join(package, ".build", "debug", target_name(name))])
            traces[name] = output
            with open(os.path.join(work, f"trace-{name}.txt"), "w") as handle:
                handle.write(output)
        base = variants[0][0]
        report["traces"] = {name: compare_traces(traces[base], traces[name]) for name, _ in variants[1:]}
    return report


def compare_traces(base, other):
    if base == other:
        return {"identical": True, "lines": base.count("\n")}
    base_lines, other_lines = base.splitlines(), other.splitlines()
    creations = lambda lines: [line for line in lines if line.startswith("+")]
    releases = lambda lines: [line for line in lines if line.startswith("-")]
    alive = lambda lines: alive_at_end(lines)
    return {
        "identical": False,
        "creations_identical": creations(base_lines) == creations(other_lines),
        "release_multiset_identical": sorted(releases(base_lines)) == sorted(releases(other_lines)),
        "alive_at_end": {"base": alive(base_lines), "other": alive(other_lines)},
        "first_difference": next((i for i, (a, b) in enumerate(zip(base_lines, other_lines)) if a != b), min(len(base_lines), len(other_lines))),
        "release_order_differences": release_order_differences(base_lines, other_lines),
    }


def alive_at_end(lines):
    alive = set()
    for line in lines:
        if line.startswith("+"):
            alive.add(line[1:].split(" ")[0])
        elif line.startswith("-"):
            alive.discard(line[1:].split(" ")[0])
    return sorted(alive)


def release_order_differences(base_lines, other_lines):
    """Positions where the two traces differ only by the order of releases within one burst of consecutive releases."""
    differences = []
    index = 0
    length = min(len(base_lines), len(other_lines))
    while index < length:
        if base_lines[index] != other_lines[index]:
            start = index
            while index < length and base_lines[index].startswith("-") and other_lines[index].startswith("-"):
                index += 1
            burst_ok = sorted(base_lines[start:index]) == sorted(other_lines[start:index]) and index > start
            differences.append({"line": start, "burst_length": index - start, "same_set": burst_ok})
            if not burst_ok:
                break
        index += 1
    return differences[:50]


def package_mode(arguments, variants):
    source = os.path.abspath(arguments.input)
    work = os.path.abspath(arguments.workdir)
    report = {"mode": "package", "input": source, "machine": machine(), "variants": {}}
    configurations = arguments.configs.split(",")
    copies = {}
    for name, path in variants:
        if not os.path.isdir(path):
            raise SystemExit("package mode takes checkouts")
        copy = os.path.join(work, "package-" + name)
        shutil.rmtree(copy, ignore_errors=True)
        shutil.copytree(source, copy, ignore=shutil.ignore_patterns(".build", ".swiftpm"))
        manifest_path = os.path.join(copy, "Package.swift")
        with open(manifest_path) as handle:
            manifest = handle.read()
        replaced = 0

        def replace(match):
            nonlocal replaced
            literal = match.group(2)
            resolved = os.path.normpath(os.path.join(source, literal))
            package_manifest = os.path.join(resolved, "Package.swift")
            if os.path.isfile(package_manifest) and 'name: "SafeDI"' in open(package_manifest).read():
                replaced += 1
                return match.group(1) + json.dumps(path)
            return match.group(0)

        manifest = re.sub(r'(\.package\(\s*path:\s*)"([^"]*)"', replace, manifest)
        if not replaced:
            raise SystemExit("found no .package(path:) that names a SafeDI checkout")
        with open(manifest_path, "w") as handle:
            handle.write(manifest)
        copies[name] = copy
    builds = {}
    for name, _ in variants:
        for configuration in configurations:
            command = ["swift", "build", "--disable-sandbox", "-v"] + (["-c", "release"] if configuration == "o" else [])
            log(f"building {name} at {configuration}")
            stdout, stderr, wall, user, system = run(command, cwd=copies[name])
            builds[(name, configuration)] = stdout + stderr
            report["variants"].setdefault(name, {})["build_" + configuration] = {"wall": wall, "cpu": user + system, "command": shlex.join(command)}
    for name, _ in variants:
        roots = generated_root_files(copies[name])
        report["variants"][name]["generated_root_files"] = {os.path.relpath(path, copies[name]): count_lines(path) for path in roots}
        report["variants"][name]["generated_lines"] = sum(count_lines(path) for path in roots)
        report["variants"][name]["generated_bytes"] = sum(os.path.getsize(path) for path in roots)
    if not arguments.no_compile:
        for configuration in configurations:
            per_module = {}
            for name, _ in variants:
                commands = frontend_commands(builds[(name, configuration)])
                roots = set(os.path.realpath(path) for path in generated_root_files(copies[name]))
                modules = {}
                for command in commands:
                    module = module_of(command)
                    if configuration == "onone":
                        if any(os.path.realpath(p) in roots for p in primary_files(command)):
                            modules.setdefault(module, []).append(command)
                    else:
                        files = [a for a in command if a.endswith(".swift")]
                        if any(os.path.realpath(f) in roots for f in files):
                            modules.setdefault(module, []).append(command)
                per_module[name] = modules
            module_names = sorted(set.intersection(*(set(m) for m in per_module.values())))
            for module in module_names:
                log(f"timing {module} at {configuration}")
                timing = time_commands({name: per_module[name][module] for name, _ in variants}, arguments.compile_runs, copies,
                                       os.path.join(work, f"stats-{configuration}-{module}"))
                for name, _ in variants:
                    report["variants"][name].setdefault("compile_" + configuration, {})[module] = timing[name]
    return report


def generated_root_files(package):
    outputs = os.path.join(package, ".build")
    found = []
    for directory, _, files in os.walk(outputs):
        if "plugins" not in directory or "outputs" not in directory:
            continue
        for file_name in files:
            if not file_name.endswith(".swift"):
                continue
            path = os.path.join(directory, file_name)
            with open(path, errors="replace") as handle:
                text = handle.read()
            if re.search(r"^    .*public (convenience )?init\(\) \{", text, re.M):
                found.append(path)
    # One build directory per configuration holds a copy of each file: keep each path once by its name within the plugin output.
    unique = {}
    for path in sorted(found):
        key = path.split(os.sep + "plugins" + os.sep, 1)[-1]
        unique.setdefault(key, path)
    return sorted(unique.values())


def count_lines(path):
    with open(path, "rb") as handle:
        return handle.read().count(b"\n")


def machine():
    swift_version = subprocess.run(["swift", "--version"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True).stdout.strip()
    return {"platform": platform.platform(), "processor": platform.processor() or platform.machine(), "cpus": os.cpu_count(),
            "swift": swift_version, "load_average": os.getloadavg()}


def print_tables(report):
    variants = report["variants"]
    print(f"\n{report['mode']} mode: {report['input']}")
    print(f"{'variant':<12}{'lines':>10}{'bytes':>12}")
    for name, figures in variants.items():
        print(f"{name:<12}{figures.get('generated_lines', 0):>10}{figures.get('generated_bytes', 0):>12}")
    for configuration in ("onone", "o"):
        key = "compile_" + configuration
        rows = [(name, figures[key]) for name, figures in variants.items() if key in figures]
        if not rows:
            continue
        print(f"\ncompile {configuration}: median (min–max) seconds")
        for name, figures in rows:
            if "cpu" in figures:
                print(f"  {name:<12} cpu {fmt(figures['cpu'])}  wall {fmt(figures['wall'])}")
            else:
                for module, module_figures in sorted(figures.items()):
                    print(f"  {name:<12} {module:<24} cpu {fmt(module_figures['cpu'])}  wall {fmt(module_figures['wall'])}")
    rows = [(name, figures["runtime"]) for name, figures in variants.items() if "runtime" in figures]
    if rows:
        print("\nruntime (release, NO_TRACE): median (min–max) seconds")
        for name, figures in rows:
            print(f"  {name:<12} build {fmt(figures['build'], 6)}  walk {fmt(figures['walk'], 6)}")
    if "traces" in report:
        print("\ntraces:", json.dumps(report["traces"]))


def fmt(figure, digits=3):
    return f"{figure['median']:.{digits}f} ({figure['min']:.{digits}f}–{figure['max']:.{digits}f})"


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mode", choices=["csv", "package"])
    parser.add_argument("input")
    parser.add_argument("--variant", action="append", required=True)
    parser.add_argument("--driver")
    parser.add_argument("--safedi")
    parser.add_argument("--configs", default="onone,o")
    parser.add_argument("--compile-runs", type=int, default=5)
    parser.add_argument("--runtime-runs", type=int, default=11)
    parser.add_argument("--generate-runs", type=int, default=3)
    parser.add_argument("--workdir", default="measure-work")
    parser.add_argument("--json")
    parser.add_argument("--no-runtime", action="store_true")
    parser.add_argument("--no-compile", action="store_true")
    parser.add_argument("--trace", action="store_true")
    arguments = parser.parse_args()
    variants = parse_variants(arguments.variant)
    os.makedirs(arguments.workdir, exist_ok=True)
    report = csv_mode(arguments, variants) if arguments.mode == "csv" else package_mode(arguments, variants)
    print_tables(report)
    if arguments.json:
        with open(arguments.json, "w") as handle:
            json.dump(report, handle, indent=1)


if __name__ == "__main__":
    main()
