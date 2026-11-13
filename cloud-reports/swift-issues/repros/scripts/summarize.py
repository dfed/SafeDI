#!/usr/bin/env python3
"""summarize.py LOG... : per log, expansions by role and by job kind, message sizes."""
import collections, re, sys

# Plugin CPU: per plugin process, the cumulative CPU time at its last expansion.
def plugin_cpu_ms(path):
    last = {}
    for line in open(path):
        p = line.rstrip("\n").split("\t")
        if p[0] == "expand" and len(p) > 5:
            last[p[4]] = max(last.get(p[4], 0), int(p[5]))
    return sum(last.values()) / 1000, len(last)

for path in sys.argv[1:]:
    roles = collections.Counter(); jobs = collections.Counter(); per_job_files = collections.Counter()
    sizes = []; config = []
    for line in open(path):
        p = line.rstrip("\n").split("\t")
        if p[0] == "expand":
            roles[p[1]] += 1
            kind = re.sub(r"\[.*", "", p[3]); jobs[(kind, p[1])] += 1
        elif p[0] == "message" and p[1].startswith("expand"):
            sizes.append(int(p[2])); config.append(0 if p[3] == 'dropped' else int(p[3]))
    total = sum(roles.values())
    print(f"{path.split('/')[-1]}: total={total} " + " ".join(f"{r}={c}" for r, c in sorted(roles.items())))
    for (k, r), c in sorted(jobs.items()):
        print(f"    {k:16s} {r:7s} {c}")
    cpu, processes = plugin_cpu_ms(path)
    print(f"    plugin processes with expansions={processes}, their CPU through last expansion={cpu:.0f} ms")
    if sizes:
        print(f"    messages={len(sizes)} bytes: min={min(sizes)} max={max(sizes)} mean={sum(sizes)/len(sizes):.0f}; staticBuildConfiguration: min={min(config)} max={max(config)}; total MB={sum(sizes)/1e6:.2f}")

