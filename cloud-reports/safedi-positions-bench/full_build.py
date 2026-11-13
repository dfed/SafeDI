#!/usr/bin/env python3
"""full_build.py FIXTURE WORK TOOL [--split]: times one generate per module, in order, three times."""
import os, shutil, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bazel_sim import Graph, Runner, parse_time
fixture, work, tool = sys.argv[1:4]
split = "--split" in sys.argv
for repeat in range(3):
	shutil.rmtree(work, ignore_errors=True); shutil.copytree(fixture, work)
	g = Graph(work); r = Runner(g, tool, ".out", split)
	user = wall = 0.0
	for m in g.order:
		t = os.path.abspath(os.path.join(work, ".time.txt")); r.run(m, t); u, w = parse_time(t); user += u; wall += wall * 0 + w
	sizes = sum(os.path.getsize(os.path.join(work, ".out", f)) for f in os.listdir(os.path.join(work, ".out")) if f.endswith(".safedi"))
	sidecars = sum(os.path.getsize(os.path.join(work, ".out", f)) for f in os.listdir(os.path.join(work, ".out")) if f.endswith(".safedipositions"))
	print(f"repeat {repeat + 1}: user {user:.2f}s wall {wall:.2f}s  .safedi bytes {sizes}  sidecar bytes {sidecars}")
