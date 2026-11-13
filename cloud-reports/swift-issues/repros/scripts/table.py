#!/usr/bin/env python3
"""table.py LOGDIR: one Markdown row per matrix build (logs named TOOLCHAIN-BUILDSYSTEM-nN-KIND.log)."""
import collections, glob, os, re, sys
rows = []
for path in sorted(glob.glob(os.path.join(sys.argv[1], "6.*-n*-*.log"))):
    m = re.match(r"(6\.\d\.\d)-(\w+)-n(\d+)-(.+)\.log$", os.path.basename(path))
    if not m: continue
    toolchain, system, n, kind = m.groups()
    expansions = collections.Counter(); cpu = {}; sizes = []; configuration = set()
    for line in open(path):
        p = line.rstrip("\n").split("\t")
        if p[0] == "expand":
            expansions["emit-module" if p[3].startswith("emit-module") else "compile"] += 1
            if len(p) > 5: cpu[p[4]] = max(cpu.get(p[4], 0), int(p[5]))
        elif p[0] == "message" and p[1].startswith("expand"):
            sizes.append(int(p[2])); configuration.add(p[3])
    text = open(path[:-4] + ".build.txt").read()
    seconds = re.search(r"build_seconds=([\d.]+)", text)
    system_name = {"default": "Swift Build" if toolchain == "6.4.2" else "native", "native": "native"}[system]
    rows.append((toolchain, system_name, int(n), kind, sum(expansions.values()), expansions["emit-module"], expansions["compile"],
                 len(cpu), sum(cpu.values()) / 1000, float(seconds.group(1)) if seconds else None,
                 sum(sizes) / len(sizes) if sizes else 0, ",".join(sorted(configuration))))
order = {"debug-clean": 0, "debug-touchT0": 1, "debug-touchUse": 2, "release-clean": 3}
rows.sort(key=lambda r: (r[0], r[1], r[2], order.get(r[3], 9)))
print("| Swift | Build system | Types | Build | Expansions | in emit-module | in compile jobs | Plugin processes | Plugin CPU (ms) | Wall (s) | Request bytes (mean) | Configuration bytes |")
print("|---|---|---|---|---|---|---|---|---|---|---|---|")
for r in rows:
    print(f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]} | {r[5]} | {r[6]} | {r[7]} | {r[8]:.0f} | {'' if r[9] is None else f'{r[9]:.1f}'} | {r[10]:.0f} | {r[11]} |")
