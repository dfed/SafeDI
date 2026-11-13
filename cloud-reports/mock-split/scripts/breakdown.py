#!/usr/bin/env python3
"""Where the compile time goes: per frontend job (-Xfrontend -stats-output-dir), for a clean build and a
private-method edit, -incremental. Swift 6.2's driver ignores -driver-time-compilation, so the frontend's own
timers are read instead.

Usage: breakdown.py BENCH_DIR FIXTURE MOCK_FILE_COUNT(0 = combined) JOBS(0 = driver default)
"""
import glob
import json
import os
import shutil
import subprocess
import sys
import time

bench, fixture, mock_files, jobs = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
release = "/home/user/SafeDI/.build/release"
work = os.path.join(bench, "breakdown", f"{fixture}-{mock_files}-j{jobs}")
shutil.rmtree(work, ignore_errors=True)
os.makedirs(os.path.join(work, "Generated"))
os.makedirs(os.path.join(work, "Build"))
shutil.copytree(os.path.join(bench, fixture, "Sources"), os.path.join(work, "Sources"))
os.chdir(work)
open("sources.csv", "w").write(",".join(sorted("Sources/" + f for f in os.listdir("Sources"))))


def generate():
    command = [os.path.expanduser("~/bin/SafeDITool-proto"), "generate", "sources.csv",
               "--combined-output", "Generated/SafeDIGenerated.swift", "--module-info-output", "Generated/Fixture.safedi",
               "--compiler-receives-input-paths-unchanged", "--active-compilation-conditions", "DEBUG", "--module-name", "Fixture"]
    if mock_files:
        command += ["--combined-output-mock-file-count", str(mock_files)]
    subprocess.run(command, check=True)


def build(label):
    sources = sorted("Sources/" + f for f in os.listdir("Sources")) + sorted("Generated/" + f for f in os.listdir("Generated") if f.endswith(".swift"))
    output_file_map = {"": {"swift-dependencies": "Build/Fixture.swiftdeps"}}
    for source in sources:
        stem = os.path.basename(source)[:-6]
        output_file_map[source] = {"object": f"Build/{stem}.o", "swift-dependencies": f"Build/{stem}.swiftdeps"}
    json.dump(output_file_map, open("Build/output-file-map.json", "w"))
    # One stats directory for every build: a different path would change the driver's arguments, which makes an
    # incremental build rebuild everything.
    stats = "Build/stats"
    shutil.rmtree(stats, ignore_errors=True)
    os.makedirs(stats)
    command = ["/opt/swift-6.2.4/usr/bin/swiftc", "-module-name", "Fixture", "-parse-as-library", "-emit-object", "-emit-module",
               "-emit-module-path", "Build/Fixture.swiftmodule", "-output-file-map", "Build/output-file-map.json",
               "-Onone", "-DDEBUG", "-enable-testing", "-gline-tables-only", "-enable-batch-mode",
               "-module-cache-path", os.path.join(bench, "modulecache"), "-I", release + "/Modules",
               "-load-plugin-executable", release + "/SafeDIMacros-tool#SafeDIMacros", "-incremental",
               "-driver-show-job-lifecycle", "-Xfrontend", "-stats-output-dir", "-Xfrontend", stats]
    if jobs:
        command += ["-j", str(jobs)]
    start = time.time()
    result = subprocess.run(command + sources, capture_output=True, text=True, check=True)
    wall = time.time() - start
    batches = {}
    for line in result.stderr.splitlines():
        if line.startswith("remark: Starting Compiling "):
            names = line[len("remark: Starting Compiling "):].split(", ")
            batches[names[0]] = names
    print(f"\n{fixture}, {'combined' if mock_files == 0 else f'{mock_files} mock files'}, -j {jobs or 'default (1)'}, {label}: build wall {wall:.2f}s")
    print("| job | primaries (generated) | frontend wall s | type-check s | SILGen+SIL opt s | IRGen s | rest (LLVM codegen, object) s |")
    print("|---|---|---|---|---|---|---|")
    total = {"wall": 0.0, "sema": 0.0, "sil": 0.0, "backend": 0.0, "rest": 0.0}
    for path in sorted(glob.glob(stats + "/*.json")):
        data = json.load(open(path))
        frontend_wall = next(v for k, v in data.items() if k.startswith("time.swift-frontend.") and k.endswith(".wall"))
        sema = data.get("time.swift.Type checking and Semantic analysis.wall", 0.0)
        sil = data.get("time.swift.SILGen.wall", 0.0) + data.get("time.swift.SIL optimization.wall", 0.0)
        backend = data.get("time.swift.IRGen.wall", 0.0)
        rest = frontend_wall - sema - sil - backend
        name = os.path.basename(path).split("-swift-frontend-Fixture-")[1].split("-x86_64")[0]
        if name == "all":
            job, primaries = "emit-module", "—"
        else:
            names = batches.get(name, [name])
            job = f"compile {name} …"
            primaries = f"{len(names)} ({sum(1 for n in names if n.startswith('SafeDIGenerated'))})"
        print(f"| {job} | {primaries} | {frontend_wall:.2f} | {sema:.2f} | {sil:.2f} | {backend:.2f} | {rest:.2f} |")
        for key, value in (("wall", frontend_wall), ("sema", sema), ("sil", sil), ("backend", backend), ("rest", rest)):
            total[key] += value
    print(f"| **sum** | | **{total['wall']:.2f}** | **{total['sema']:.2f}** | **{total['sil']:.2f}** | **{total['backend']:.2f}** | **{total['rest']:.2f}** |")


generate()
build("clean")
target = open(os.path.join(bench, fixture, "edit-target.txt")).read().split()[0]
path = f"Sources/{target}.swift"
text = open(path).read()
marker = "    func render() -> [String] {"
open(path, "w").write(text.replace(marker, "    private func debugSummary() -> String {\n        \"\\(Self.self) summary\"\n    }\n\n" + marker, 1))
generate()
build("private-method edit")
