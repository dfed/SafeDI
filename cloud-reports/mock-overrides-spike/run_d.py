#!/usr/bin/env python3
"""Generate, compile, time and run shape D (shape_d.py) with one SafeDITool.

python3 run_d.py --tool T --bin B --screens N [--walk | --trace] [--opt Onone|O] [--rewrite R.py]
                 [--repeats K] [--modes layout,stack,time:100,trace,trace-overrides] [--work DIR] [--app-flags ...]

- Writes the fixture with shape_d.py into DIR/out-D-N (DIR defaults to ~/work/<tool name>).
- --rewrite R.py runs `python3 R.py DIR/out-D-N/App.gen.swift` before compiling (the D1 shared form).
- Compiles Core, M<n-1> … M0, App with swiftc as Scripts/multi-module-repro.sh does, at -Onone or -O, always -DDEBUG.
- Times App's compile K times by rerunning its swift-frontend command (from `swiftc -###`), without Driver.swift:
  wall and user CPU of the frontend process, and App.o's size.
- Then compiles App again with Driver.swift, links every object with SafeDI's, and runs each mode.
Prints one JSON object on its last line.
"""
import argparse, glob, json, os, resource, shlex, subprocess, sys, time

here = os.path.dirname(os.path.abspath(__file__))
p = argparse.ArgumentParser()
p.add_argument("--tool", required=True)
p.add_argument("--bin", required=True)
p.add_argument("--screens", type=int, required=True)
p.add_argument("--walk", action="store_true")
p.add_argument("--trace", action="store_true")
p.add_argument("--opt", default="Onone")
p.add_argument("--rewrite")
p.add_argument("--repeats", type=int, default=0)
p.add_argument("--modes", default="")
p.add_argument("--work")
p.add_argument("--app-flags", default="")
p.add_argument("--module-flags", default="", help="flags for every module, App included")
p.add_argument("--nonisolated", action="store_true", help="add the planned nonisolated to every internal SafeDIOverrides and SafeDIMockConfiguration")
p.add_argument("--skip-generate", action="store_true")
p.add_argument("--timeout", type=int, default=900)
a = p.parse_args()

work = a.work or os.path.expanduser(f"~/work/{os.path.basename(a.tool)}")
os.makedirs(work, exist_ok=True)
n = a.screens
out = os.path.join(work, f"out-D-{n}")
macros = next(c for c in (f"{a.bin}/SafeDIMacros-tool", f"{a.bin}/SafeDIMacros") if os.path.exists(c))
modules_path = f"{a.bin}/Modules" if os.path.exists(f"{a.bin}/Modules/SafeDI.swiftmodule") else a.bin
result = {"tool": a.tool, "screens": n, "walk": a.walk, "trace": a.trace, "opt": a.opt, "rewrite": a.rewrite}

if not a.skip_generate:
    flags = (["--trace"] if a.trace else []) + (["--walk"] if a.walk else [])
    t = time.time()
    g = subprocess.run([sys.executable, os.path.join(here, "shape_d.py"), a.tool, str(n)] + flags, cwd=work, check=True, capture_output=True, text=True)
    result["generate_output"] = g.stdout.strip()
    if a.nonisolated:
        for g in glob.glob(f"{out}/*.gen.swift"):
            subprocess.run(["sed", "-i", "-E", r"s/^( *)struct (SafeDIOverrides|SafeDIMockConfiguration) \{/\1nonisolated struct \2 {/", g], check=True)
    if a.rewrite:
        subprocess.run([sys.executable, a.rewrite, f"{out}/App.gen.swift"], check=True)
result["app_gen_lines"] = open(f"{out}/App.gen.swift").read().count("\n")

modules = ["Core"] + [f"M{i}" for i in reversed(range(n))] + ["App"]
extra_app = shlex.split(a.app_flags)
extra_all = shlex.split(a.module_flags)

def command(module, with_driver=False, opt=a.opt):
    sources = [f"{out}/{module}.swift", f"{out}/{module}.gen.swift"] + ([f"{out}/Driver.swift"] if with_driver else [])
    return (["swiftc", "-emit-object", "-whole-module-optimization", "-parse-as-library", f"-{opt}",
             "-o", f"{out}/{module}.o", "-module-name", module, "-package-name", f"p{module}",
             "-emit-module", "-emit-module-path", f"{out}/{module}.swiftmodule",
             "-I", modules_path, "-I", out, "-load-plugin-executable", f"{macros}#SafeDIMacros",
             "-swift-version", "6", "-DDEBUG"] + extra_all + (extra_app if module == "App" else []) + sources)

def run_with_rusage(cmd):
    """Runs cmd and returns (wall, user CPU of the child and its children, returncode, output)."""
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    start = time.time()
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=a.timeout)
    except subprocess.TimeoutExpired:
        return {"wall": None, "user": None, "status": "exceeded"}
    wall = time.time() - start
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    return {"wall": wall, "user": after.ru_utime - before.ru_utime, "status": proc.returncode, "output": (proc.stdout + proc.stderr)[-4000:]}

for module in modules[:-1]:
    r = run_with_rusage(command(module))
    if r["status"] != 0:
        print(r.get("output")); sys.exit(f"{module} failed to compile")

# App without Driver.swift, once through the driver (to check it compiles), then K frontend reruns.
r = run_with_rusage(command("App"))
result["app_compile_status"] = r["status"]
if r["status"] != 0:
    result["app_compile_error"] = r.get("output")
    print(json.dumps(result)); sys.exit(1)
result["app_object_bytes"] = os.path.getsize(f"{out}/App.o")
if a.repeats:
    jobs = subprocess.run(command("App") + ["-###"], capture_output=True, text=True, check=True).stdout.strip().splitlines()
    frontend = [shlex.split(j) for j in jobs if "-frontend" in j]
    assert len(frontend) == 1, jobs
    result["frontend_command"] = shlex.join(frontend[0])
    samples = []
    for _ in range(a.repeats):
        s = run_with_rusage(frontend[0])
        samples.append(s)
        if s["status"] == "exceeded":
            break
    result["app_compile_samples"] = [{"wall": s["wall"], "user": s["user"]} for s in samples]

if a.modes:
    r = run_with_rusage(command("App", with_driver=True))
    if r["status"] != 0:
        result["driver_compile_error"] = r.get("output"); print(json.dumps(result)); sys.exit(1)
    safedi_objects = sorted(glob.glob(f"{a.bin}/SafeDI.build/*.o")) or [f"{a.bin}/libSafeDI.a"]
    link = ["swiftc", f"-{a.opt}", "-o", f"{out}/driver"] + [f"{out}/{m}.o" for m in modules] + safedi_objects
    result["link_command"] = shlex.join(link)
    subprocess.run(link, check=True)
    result["modes"] = {}
    for mode in a.modes.split(","):
        argv = mode.split(":")
        proc = subprocess.run([f"{out}/driver"] + argv, capture_output=True, text=True, timeout=a.timeout)
        text = proc.stdout + (f"\n[exit {proc.returncode}] {proc.stderr[-2000:]}" if proc.returncode else "")
        if argv[0].startswith("trace"):
            path = f"{out}/{argv[0]}.txt"
            open(path, "w").write(proc.stdout)
            result["modes"][mode] = {"file": path, "lines": proc.stdout.count("\n"), "exit": proc.returncode}
        else:
            result["modes"][mode] = text.strip()
print(json.dumps(result))
