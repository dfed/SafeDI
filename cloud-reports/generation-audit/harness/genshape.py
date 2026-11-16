"""genshape.py TOOL SHAPE_DIR OUT [--top N]: runs generate per module (as bench.py does), prints per-module wall
seconds sorted, total, and writes OUT/commands.txt (one shell command per module) for profiling."""
import sys, os, time, shlex, importlib.util
spec = importlib.util.spec_from_file_location("bench", "/home/user/bench/Scripts/benchmark-2-3-1/bench.py")
bench = importlib.util.module_from_spec(spec); spec.loader.exec_module(bench)
tool = bench.Tool.__new__(bench.Tool); tool.label="t"; tool.path=os.path.realpath(sys.argv[1])
import subprocess
h = subprocess.run([tool.path, "generate", "--help"], capture_output=True, text=True).stdout
tool.takes_module_name = "--module-name" in h; tool.takes_transitive = "--transitive-module-info-file-path" in h
shape = bench.Shape(os.path.abspath(sys.argv[2]))
os.makedirs(sys.argv[3], exist_ok=True)
run = bench.Run(shape, tool, sys.argv[3])
cmds = run.generate_commands()
open(os.path.join(run.out, "commands.txt"), "w").write("\n".join(shlex.join(c) for c in cmds) + "\n")
times = []
for c in cmds:
    s = time.perf_counter(); p = subprocess.run(c, capture_output=True, text=True); w = time.perf_counter() - s
    if p.returncode: print("FAIL", c[2], (p.stdout+p.stderr)[-800:]); sys.exit(1)
    times.append((w, os.path.basename(c[2])))
import statistics
print("median", round(statistics.median(t for t,_ in times),3), "max", round(max(t for t,_ in times),3))
lines = sum(open(c[4]).read().count("\n") for c in cmds)
print(f"{shape.name}: modules={len(cmds)} total={sum(t for t,_ in times):.2f}s lines={lines}")
for w, m in sorted(times, reverse=True)[:int(sys.argv[sys.argv.index('--top')+1]) if '--top' in sys.argv else 5]:
    print(f"  {w:8.3f}s {m}")
