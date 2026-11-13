#!/usr/bin/env python3
"""Measures `generate --combined-output` with mocks in the combined file against mocks split into N files.

Every timed command runs under `/usr/bin/time -v`; its user CPU time includes every frontend job the
driver waits for. Configurations alternate within each run (run 1: combined, 8, 32, 64; run 2: …).

Usage: bench.py --fixture DIR --mode {bazel,incremental,incremental-touch} --runs 3 --out results.jsonl
  bazel             : one swiftc per module, not incremental, outputs removed before each compile (a
                      Bazel action without the persistent worker: sandboxed or remote).
  incremental       : `-incremental` with an output file map; SafeDITool rewrites a generated file only
                      when its bytes change (a custom build or an Xcode script phase).
  incremental-touch : as `incremental`, but every generated file gets a new modification time on every
                      run, as Bazel's persistent worker sees it: Bazel deletes an action's outputs
                      before it runs, and Swift 6.2's driver has no file hashing.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time

TOOLCHAIN = "/opt/swift-6.2.4/usr/bin"
SWIFTC = os.path.join(TOOLCHAIN, "swiftc")

parser = argparse.ArgumentParser()
parser.add_argument("--fixture", required=True)
parser.add_argument("--mode", required=True, choices=["bazel", "incremental", "incremental-touch"])
parser.add_argument("--runs", type=int, default=3)
parser.add_argument("--configs", default="0,8,32,64")
parser.add_argument("--tool", required=True)
parser.add_argument("--safedi-modules", required=True)
parser.add_argument("--macro-plugin", required=True)
parser.add_argument("--module-cache", required=True)
parser.add_argument("--work", required=True)
parser.add_argument("--out", required=True)
parser.add_argument("--jobs", default=None, help="-j to pass; default: the driver's default")
args = parser.parse_args()

configs = [int(c) for c in args.configs.split(",")]
fixture = os.path.abspath(args.fixture)
edit_target, new_service = open(os.path.join(fixture, "edit-target.txt")).read().split()


def timed(command, cwd, env=None):
    """Runs command under /usr/bin/time -v; returns (user, system, wall, maxrss_kb, stdout+stderr)."""
    full = ["/usr/bin/time", "-v"] + command
    result = subprocess.run(full, cwd=cwd, capture_output=True, text=True, env=env)
    output = result.stdout + result.stderr
    if result.returncode != 0:
        sys.stderr.write(f"FAILED ({result.returncode}): {' '.join(command)}\n{output[-4000:]}\n")
        raise SystemExit(1)
    user = float(re.search(r"User time \(seconds\): ([\d.]+)", output).group(1))
    system = float(re.search(r"System time \(seconds\): ([\d.]+)", output).group(1))
    wall_text = re.search(r"Elapsed \(wall clock\) time \(h:mm:ss or m:ss\): ([\d:.]+)", output).group(1)
    parts = [float(p) for p in wall_text.split(":")]
    wall = sum(p * 60 ** i for i, p in enumerate(reversed(parts)))
    maxrss = int(re.search(r"Maximum resident set size \(kbytes\): (\d+)", output).group(1))
    return user, system, wall, maxrss, output


def generated_files(work):
    directory = os.path.join(work, "Generated")
    return sorted(os.path.join("Generated", name) for name in os.listdir(directory) if name.endswith(".swift"))


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def generate(work, mock_files):
    command = [args.tool, "generate", "sources.csv",
               "--combined-output", "Generated/SafeDIGenerated.swift",
               "--module-info-output", "Generated/Fixture.safedi",
               "--compiler-receives-input-paths-unchanged",
               "--active-compilation-conditions", "DEBUG",
               "--module-name", "Fixture"]
    if mock_files:
        command += ["--combined-output-mock-file-count", str(mock_files)]
    before = {path: digest(os.path.join(work, path)) for path in generated_files(work)} if os.listdir(os.path.join(work, "Generated")) else {}
    if args.mode == "bazel" or args.mode == "incremental-touch":
        # Bazel removes an action's declared outputs before running it.
        for path in generated_files(work):
            os.remove(os.path.join(work, path))
    user, system, wall, maxrss, _ = timed(command, work)
    after = {path: digest(os.path.join(work, path)) for path in generated_files(work)}
    changed = [path for path in after if before.get(path) != after[path]]
    return {"user": user, "sys": system, "wall": wall, "maxrss_kb": maxrss,
            "generated_files": len(after), "generated_files_changed": len(changed) if before else len(after)}


def compile_module(work):
    build = os.path.join(work, "Build")
    if args.mode == "bazel":
        shutil.rmtree(build, ignore_errors=True)
    os.makedirs(build, exist_ok=True)
    sources = [os.path.join("Sources", name) for name in sorted(os.listdir(os.path.join(work, "Sources")))]
    sources += generated_files(work)
    output_file_map = {"": {"swift-dependencies": "Build/Fixture.swiftdeps"}}
    for source in sources:
        stem = os.path.basename(source)[:-len(".swift")]
        output_file_map[source] = {"object": f"Build/{stem}.o", "swift-dependencies": f"Build/{stem}.swiftdeps"}
    with open(os.path.join(build, "output-file-map.json"), "w") as handle:
        json.dump(output_file_map, handle, indent=1)
    # rules_swift's defaults for a `fastbuild` swift_library compile (swift/toolchains/config/compile_config.bzl):
    # -Onone, -DDEBUG, -enable-testing, -gline-tables-only, -enable-batch-mode, an output file map, one
    # driver invocation per module, no -j (the driver's default, the machine's core count).
    command = [SWIFTC, "-module-name", "Fixture", "-parse-as-library",
               "-emit-object", "-emit-module", "-emit-module-path", "Build/Fixture.swiftmodule",
               "-output-file-map", "Build/output-file-map.json",
               "-Onone", "-DDEBUG", "-enable-testing", "-gline-tables-only", "-enable-batch-mode",
               "-module-cache-path", args.module_cache,
               "-I", args.safedi_modules,
               "-load-plugin-executable", f"{args.macro_plugin}#SafeDIMacros",
               "-driver-show-job-lifecycle"]
    if args.jobs:
        command += ["-j", args.jobs]
    if args.mode != "bazel":
        command += ["-incremental"]
    user, system, wall, maxrss, output = timed(command + sources, work)
    # The driver's job lifecycle names each file a compile job compiles. (An object's modification time says
    # nothing: the frontend leaves an object whose bytes did not change untouched.)
    started = re.findall(r"^remark: Starting Compiling (.*)$", output, re.MULTILINE)
    frontend_jobs = len(started)
    recompiled = [name.strip() for line in started for name in line.split(", ")]
    return {"user": user, "sys": system, "wall": wall, "maxrss_kb": maxrss,
            "objects_rebuilt": len(recompiled),
            "generated_objects_rebuilt": sum(1 for s in recompiled if s.startswith("SafeDIGenerated")),
            "frontend_compile_jobs": frontend_jobs}


def touch_generated(work):
    # Bazel's worker sees a freshly written output (new mtime) even when its bytes did not change.
    now = time.time()
    for path in generated_files(work):
        os.utime(os.path.join(work, path), (now, now))


def edit_add_private_method(work):
    path = os.path.join(work, "Sources", edit_target + ".swift")
    text = open(path).read()
    marker = "    func render() -> [String] {"
    text = text.replace(marker, "    private func debugSummary() -> String {\n        \"\\(Self.self) summary\"\n    }\n\n" + marker, 1)
    open(path, "w").write(text)


def edit_add_dependency(work):
    path = os.path.join(work, "Sources", edit_target + ".swift")
    text = open(path).read()
    label = new_service[0].lower() + new_service[1:]
    text = text.replace("    init(", f"    init({label}: {new_service}, ", 1)
    text = text.replace("    }\n", f"        self.{label} = {label}\n    }}\n", 1)
    text = text.rstrip("\n")
    assert text.endswith("}")
    text = text[:-1] + f"    @Received private let {label}: {new_service}\n}}\n"
    open(path, "w").write(text)


results = open(args.out, "a")
for run in range(1, args.runs + 1):
    for mock_files in configs:
        work = os.path.join(args.work, f"{os.path.basename(fixture)}-{args.mode}-j{args.jobs or 0}-{mock_files}")
        shutil.rmtree(work, ignore_errors=True)
        os.makedirs(os.path.join(work, "Generated"))
        shutil.copytree(os.path.join(fixture, "Sources"), os.path.join(work, "Sources"))
        with open(os.path.join(work, "sources.csv"), "w") as handle:
            handle.write(",".join(os.path.join("Sources", name) for name in sorted(os.listdir(os.path.join(work, "Sources")))))
        steps = [("clean", None), ("private-method", edit_add_private_method), ("add-dependency", edit_add_dependency)]
        for step, edit in steps:
            if edit:
                edit(work)
            generation = generate(work, mock_files)
            if args.mode == "incremental-touch":
                touch_generated(work)
            compilation = compile_module(work)
            record = {"fixture": os.path.basename(fixture), "mode": args.mode, "jobs": args.jobs or "default", "run": run, "mock_files": mock_files,
                      "step": step, "generate": generation, "compile": compilation}
            results.write(json.dumps(record) + "\n")
            results.flush()
            print(f"run {run} mock_files={mock_files:>2} {step:<15} generate {generation['wall']:6.2f}s wall "
                  f"({generation['generated_files_changed']}/{generation['generated_files']} files changed)  "
                  f"compile {compilation['wall']:6.2f}s wall {compilation['user']:7.2f}s user "
                  f"({compilation['objects_rebuilt']} objects, {compilation['generated_objects_rebuilt']} generated, "
                  f"{compilation['frontend_compile_jobs']} jobs)", flush=True)
