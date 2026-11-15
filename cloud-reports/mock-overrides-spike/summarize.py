#!/usr/bin/env python3
"""python3 summarize.py results/*.jsonl: one Markdown row per run_d.py or proxy.py result."""
import json, os, statistics, sys


def spread(samples, key):
    values = [s[key] for s in samples if s.get(key) is not None]
    if not values:
        return "exceeded" if samples else ""
    return f"{statistics.median(values):.2f} ({min(values):.2f}–{max(values):.2f})"


print("| file | tool | screens | opt | walk | rewrite | lines | compile wall s | compile user s | object bytes | modes |")
print("|---|---|---|---|---|---|---|---|---|---|---|")
for path in sys.argv[1:]:
    for line in open(path):
        d = json.loads(line)
        samples = d.get("app_compile_samples") or d.get("compile_samples") or []
        modes = d.get("modes") or {}
        mode_text = "; ".join(f"{k}: {v if not isinstance(v, dict) else str(v.get('lines')) + ' lines'}" for k, v in modes.items())
        if "mock_time" in d:
            mode_text = f"mock(): {d['mock_time']}"
        print(f"| {os.path.basename(path)} | {os.path.basename(d['tool'])} | {d.get('screens', 'proxy')} | {d['opt']} | {d.get('walk', '')} | "
              f"{os.path.basename(d.get('rewrite') or '') } | {d.get('app_gen_lines', d.get('gen_lines'))} | {spread(samples, 'wall')} | "
              f"{spread(samples, 'user')} | {d.get('app_object_bytes', d.get('object_bytes'))} | {mode_text} |")
