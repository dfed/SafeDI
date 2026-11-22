#!/usr/bin/env python3
"""Scratch harness (not for merging): time `swiftc -O -wmo` on the code SafeDITool generates for a benchmark shape.

compile_time.py SAFEDITOOL SAFEDI_BUILD FIXTURES SHAPE OUT [RUNS]
  SAFEDITOOL    the SafeDITool binary to generate with (main's or #930's release build)
  SAFEDI_BUILD  a release build directory of this package holding Modules/SafeDI.swiftmodule and SafeDIMacros-tool
                (`swift build -c release --product SafeDI --scratch-path DIR`, then DIR/release; on macOS the
                directory is DIR/arm64-apple-macosx/release)
  FIXTURES      the output of .claude/skills/generate-benchmark/make_fixtures.sh
  SHAPE         e.g. issue646-16, N5inline-8
Per module in modules.txt order: runs `generate` as the benchmark does (DEBUG, module and package names, upstream .safedi
files), then compiles the fixture's sources plus the generated file into an object and a module, RUNS times, and prints
the median wall time and the generated line count. The generated code links against SafeDI only through the module
(`-I SAFEDI_BUILD/Modules`), and the fixture's @Instantiable macros expand through
`-load-plugin-executable SAFEDI_BUILD/SafeDIMacros-tool#SafeDIMacros`; nothing is linked, since `-c` stops at objects.
A compile error fails the run, so a pass means every root type's generated initializer type-checks.
issue646 fixtures declare `@Instantiable public final class X {` without `: Instantiable`; the harness copies the
fixture and adds the conformance (the macro requires it) before compiling, and generates from the copy.
"""
import os, re, shutil, statistics, subprocess, sys, time

tool, build, fixtures, shape, out = sys.argv[1:6]
runs = int(sys.argv[6]) if len(sys.argv) > 6 else 3
source = os.path.join(fixtures, shape)
fixture = os.path.join(out, "fixture")
shutil.rmtree(out, ignore_errors=True)
shutil.copytree(source, fixture)
for directory, _, names in os.walk(fixture):
    for name in names:
        if name.endswith(".swift"):
            path = os.path.join(directory, name)
            text = open(path).read()
            fixed = re.sub(r"^(public final class \w+) \{", r"\1: Instantiable {", text, flags=re.M)
            if "import SafeDI" not in fixed:
                fixed = "import SafeDI\n" + fixed
            if fixed != text:
                open(path, "w").write(fixed)
for line in open(os.path.join(fixture, "modules.txt")):
    parts = line.split()
    if not parts:
        continue
    module, dependencies = parts[0], (parts[1].split(",") if len(parts) > 1 else [])
    files = sorted(os.path.join(d, f) for d, _, fs in os.walk(os.path.join(fixture, module)) for f in fs if f.endswith(".swift"))
    csv = os.path.join(out, f"{module}.csv")
    open(csv, "w").write(",".join(files))
    generated = os.path.join(out, f"{module}.generated.swift")
    arguments = [tool, "generate", csv, "--combined-output", generated, "--module-info-output", os.path.join(out, f"{module}.safedi"),
                 "--active-compilation-conditions", "DEBUG", "--module-name", module, "--package-name", "Bench"]
    if dependencies:
        dependencies_csv = os.path.join(out, f"{module}.deps.csv")
        open(dependencies_csv, "w").write(",".join(os.path.join(out, f"{d}.safedi") for d in dependencies))
        arguments += ["--dependent-module-info-file-path", dependencies_csv]
    subprocess.run(arguments, check=True)
    compile_command = ["swiftc", "-O", "-wmo", "-parse-as-library", "-module-name", module,
                       "-I", os.path.join(build, "Modules"), "-I", out,
                       "-load-plugin-executable", os.path.join(build, "SafeDIMacros-tool") + "#SafeDIMacros",
                       "-emit-module", "-emit-module-path", os.path.join(out, f"{module}.swiftmodule"),
                       "-c", "-o", os.path.join(out, f"{module}.o")] + files + [generated]
    times = []
    for _ in range(runs):
        start = time.monotonic()
        result = subprocess.run(compile_command, capture_output=True, text=True)
        times.append(time.monotonic() - start)
        if result.returncode != 0:
            sys.exit(f"{shape} {module}: compile failed\n{result.stderr[-4000:]}")
    lines = sum(1 for _ in open(generated))
    print(f"{shape} {module} lines={lines} compile_median={statistics.median(times):.2f}s runs={' '.join(f'{t:.2f}' for t in times)}")
