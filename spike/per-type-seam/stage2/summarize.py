"""Summarizes measure.zsh's timing logs: per variant and module, the median and min–max of wall time, user CPU and peak
memory over the measured rounds (round 0 is the warm-up, dropped), and the runtime rounds (round 0 dropped).
Usage: python3 -I summarize.py TIMING_DIRECTORY RESULTS_DIRECTORY"""
import os
import re
import statistics
import sys

timing, results = sys.argv[1], sys.argv[2]


def parse(path):
    text = open(path).read()
    wall = re.search(r"Elapsed \(wall clock\) time \(h:mm:ss or m:ss\): (\S+)", text).group(1)
    parts = [float(p) for p in wall.split(":")]
    seconds = parts[-1] + 60 * parts[-2] + (3600 * parts[-3] if len(parts) > 2 else 0)
    user = float(re.search(r"User time \(seconds\): (\S+)", text).group(1))
    memory = int(re.search(r"Maximum resident set size \(kbytes\): (\d+)", text).group(1)) / 1024 / 1024
    status = int(re.search(r"Exit status: (\d+)", text).group(1)) if "Exit status" in text else 0
    signaled = "Command terminated by signal" in text
    return seconds, user, memory, status, signaled


def spread(values, unit):
    return f"{statistics.median(values):.2f}{unit} ({min(values):.2f}–{max(values):.2f})"


rows = {}
for entry in sorted(os.listdir(timing)):
    variant, optimization, round_ = entry.split("-")
    for file in sorted(os.listdir(os.path.join(timing, entry))):
        module = file.removesuffix(".time")
        if module not in ("Feature", "App"):
            continue
        rows.setdefault((optimization, variant, module), []).append((int(round_), parse(os.path.join(timing, entry, file))))

for optimization in ["Onone", "O"]:
    print(f"compile -{optimization} (whole module): median (min–max) over measured rounds")
    for (opt, variant, module), measurements in sorted(rows.items()):
        if opt != optimization:
            continue
        measured = [m for r, m in measurements if optimization == "O" or r > 0] or [m for _, m in measurements]
        failed = [m for m in measured if m[3] != 0 or m[4]]
        note = f", {len(failed)} of {len(measured)} failed or timed out (exit {failed[0][3]})" if failed else ""
        print(f"  {variant} {module}: wall {spread([m[0] for m in measured], ' s')}, user {spread([m[1] for m in measured], ' s')}, peak memory {spread([m[2] for m in measured], ' GB')}, rounds {len(measured)}{note}")

runtime = os.path.join(results, "runtime.txt")
if os.path.exists(runtime):
    per_variant = {}
    for line in open(runtime):
        match = re.match(r"round (\d+) (\S+): ([\d.e+]+) ns per walk, (\d+) walks, (\d+) values per walk", line)
        if match and int(match.group(1)) > 0:
            per_variant.setdefault(match.group(2), []).append((float(match.group(3)), int(match.group(5))))
    print("runtime (-O): ns per Root() plus walk of every path, median (min–max) of 7 rounds")
    for variant, values in sorted(per_variant.items()):
        print(f"  {variant}: {spread([v / 1000 for v, _ in values], ' µs')}, {values[0][1]} values per walk")
