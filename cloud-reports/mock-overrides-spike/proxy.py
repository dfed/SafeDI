#!/usr/bin/env python3
"""python3 proxy.py --tool T --bin B [--opt Onone|O] [--repeats K] [--calls N] [--stats DIR] [--nonisolated] [--work DIR]

The compile-cost proxy (section C), a proxy and not the gate: one module, `Proxy`, with
- 30 services in a received chain (`Service<k>` receives `service<k-1>`), every one instantiated by `Root`;
- 195 features in 15 trees of depth 3 and fanout 3 (1 + 3 + 9 each), each feature receiving 6 services drawn with a
  fixed seed and taking one default-valued init parameter (`retries: Int = <k>`), each instantiating its children;
- every type `generateMock: true`; nothing built twice.
It generates with T, compiles the module once to check it, then K times through its swift-frontend command (wall, user
CPU, object bytes), optionally with -stats-output-dir, and links a driver that times N calls of the deepest feature's
`mock()` (a leaf's parent in the last tree, whose mock promotes its services' chain). Prints JSON on its last line.
"""
import argparse, glob, json, os, random, resource, shlex, subprocess, sys, time

p = argparse.ArgumentParser()
p.add_argument("--tool", required=True); p.add_argument("--bin", required=True)
p.add_argument("--opt", default="Onone"); p.add_argument("--repeats", type=int, default=0)
p.add_argument("--calls", type=int, default=0); p.add_argument("--stats")
p.add_argument("--nonisolated", action="store_true"); p.add_argument("--work")
a = p.parse_args()
out = a.work or os.path.expanduser(f"~/work/proxy-{os.path.basename(a.tool)}")
os.makedirs(out, exist_ok=True)

rng = random.Random(2026)
S = 30
src = ["import SafeDI", ""]
for k in range(S):
    if k == 0:
        src.append("@Instantiable(generateMock: true) final class Service0: Instantiable { init() {} }")
    else:
        src.append(f"@Instantiable(generateMock: true) final class Service{k}: Instantiable {{ init(service{k-1}: Service{k-1}) {{ self.service{k-1} = service{k-1} }}; @Received let service{k-1}: Service{k-1} }}")
features, trees = [], []
counter = 0
def feature(depth):
    global counter
    me = counter; counter += 1
    kids = [feature(depth + 1) for _ in range(3)] if depth < 2 else []
    services = sorted(rng.sample(range(S), 6))
    params = [f"service{s}: Service{s}" for s in services] + [f"feature{c}: Feature{c}" for c in kids] + [f"retries: Int = {me % 7}"]
    assigns = [f"self.service{s} = service{s}" for s in services] + [f"self.feature{c} = feature{c}" for c in kids] + ["self.retries = retries"]
    props = [f"    @Received let service{s}: Service{s}" for s in services] + [f"    @Instantiated let feature{c}: Feature{c}" for c in kids] + ["    let retries: Int"]
    features.append(f"@Instantiable(generateMock: true) final class Feature{me}: Instantiable {{\n    init({', '.join(params)}) {{ {'; '.join(assigns)} }}\n" + "\n".join(props) + "\n}")
    return me
for _ in range(15):
    trees.append(feature(0))
src += features
root_params = [f"service{k}: Service{k}" for k in range(S)] + [f"feature{t}: Feature{t}" for t in trees]
src.append("@Instantiable(isRoot: true, generateMock: true) final class Root: Instantiable {\n"
           f"    init({', '.join(root_params)}) {{ {'; '.join(f'self.{x.split(':')[0]} = {x.split(':')[0]}' for x in root_params)} }}\n"
           + "\n".join(f"    @Instantiated let {x.split(':')[0]}: {x.split(': ')[1]}" for x in root_params) + "\n}")
deep = trees[-1] + 1  # the first child of the last tree: depth 1, with three children of its own
open(f"{out}/Proxy.swift", "w").write("\n".join(src) + "\n")
open(f"{out}/Proxy.csv", "w").write(f"{out}/Proxy.swift")
subprocess.run([a.tool, "generate", f"{out}/Proxy.csv", "--combined-output", f"{out}/Proxy.gen.swift", "--module-name", "Proxy",
                "--module-info-output", f"{out}/Proxy.safedi", "--active-compilation-conditions", "DEBUG"], check=True)
if a.nonisolated:
    subprocess.run(["sed", "-i", "-E", r"s/^( *)struct (SafeDIOverrides|SafeDIMockConfiguration) \{/\1nonisolated struct \2 {/", f"{out}/Proxy.gen.swift"], check=True)
driver = f"""import Foundation
@main enum Driver {{
    nonisolated(unsafe) static var sink: AnyObject?
    static func main() {{
        let calls = Int(CommandLine.arguments.dropFirst().first ?? "1000") ?? 1000
        var samples = [UInt64]()
        for _ in 0..<calls {{ let start = DispatchTime.now().uptimeNanoseconds; sink = Feature{deep}.mock(); samples.append(DispatchTime.now().uptimeNanoseconds - start) }}
        samples.sort(); print("ns median", samples[samples.count / 2], "min", samples[0], "max", samples[samples.count - 1])
    }}
}}
"""
open(f"{out}/Driver.swift", "w").write(driver)
macros = f"{a.bin}/SafeDIMacros-tool"
def command(with_driver=False):
    return (["swiftc", "-emit-object", "-whole-module-optimization", "-parse-as-library", f"-{a.opt}", "-o", f"{out}/Proxy.o",
             "-module-name", "Proxy", "-I", f"{a.bin}/Modules", "-load-plugin-executable", f"{macros}#SafeDIMacros",
             "-swift-version", "6", "-DDEBUG", f"{out}/Proxy.swift", f"{out}/Proxy.gen.swift"] + ([f"{out}/Driver.swift"] if with_driver else []))
def rusage(cmd):
    before = resource.getrusage(resource.RUSAGE_CHILDREN); t = time.time()
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    if r.returncode: sys.exit(r.stdout + r.stderr)
    return {"wall": time.time() - t, "user": after.ru_utime - before.ru_utime}
result = {"tool": a.tool, "opt": a.opt, "nonisolated": a.nonisolated, "gen_lines": open(f"{out}/Proxy.gen.swift").read().count("\n"), "deep_feature": deep}
rusage(command())
result["object_bytes"] = os.path.getsize(f"{out}/Proxy.o")
jobs = subprocess.run(command() + ["-###"], capture_output=True, text=True, check=True).stdout.strip().splitlines()
frontend = shlex.split(next(j for j in jobs if "-frontend" in j))
result["frontend_command"] = shlex.join(frontend)
result["compile_samples"] = [rusage(frontend) for _ in range(a.repeats)]
if a.stats:
    os.makedirs(a.stats, exist_ok=True)
    for f in glob.glob(f"{a.stats}/*.json"): os.remove(f)
    rusage(frontend + ["-stats-output-dir", a.stats])
    stats = json.load(open(glob.glob(f"{a.stats}/*.json")[0]))
    keys = ["Frontend.NumInstructionsExecuted", "Sema.NumTypesDeserialized", "Sema.NumConstraintScopes", "SILModule.NumSILGenFunctions",
            "SILModule.NumSILOptFunctions", "IRModule.NumIRFunctions", "LLVM.NumLLVMBytesOutput", "Sema.NumDeclsTypechecked"]
    result["stats"] = {k: stats.get(k) for k in keys}
if a.calls:
    rusage(command(with_driver=True))
    subprocess.run(["swiftc", f"-{a.opt}", "-o", f"{out}/driver", f"{out}/Proxy.o"] + sorted(glob.glob(f"{a.bin}/SafeDI.build/*.o")), check=True)
    result["mock_time"] = subprocess.run([f"{out}/driver", str(a.calls)], capture_output=True, text=True, check=True).stdout.strip()
print(json.dumps(result))
