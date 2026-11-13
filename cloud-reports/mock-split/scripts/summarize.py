#!/usr/bin/env python3
"""Prints Markdown tables from results.jsonl: per fixture and mode, each step's compile wall and user CPU time for
every configuration, each run listed, with the median and the spread (max - min)."""
import json
import statistics
import sys
from collections import defaultdict

records = [json.loads(line) for line in open(sys.argv[1])]
groups = defaultdict(list)
for record in records:
    groups[(record["fixture"], record["mode"], str(record.get("jobs", "default")), record["step"], record["mock_files"])].append(record)

mode_titles = {
    ("bazel", "default"): "rules_swift without the worker (sandboxed or remote): not incremental, no -j",
    ("incremental-touch", "default"): "rules_swift with its persistent worker: -incremental, no -j, every generated file rewritten",
    ("incremental", "default"): "rules_swift worker with file hashing (rules_swift's default from Swift 6.4 / Xcode 27): -incremental, no -j, unchanged generated files untouched",
    ("incremental", "4"): "custom build or Xcode-like: -incremental, -j 4, generated files written only when changed",
}
steps = ["clean", "private-method", "add-dependency"]


def label(mock_files):
    return "combined" if mock_files == 0 else f"{mock_files} files"


def cell(values):
    values = sorted(values)
    runs = " / ".join(f"{v:.2f}" for v in values)
    return f"**{statistics.median(values):.2f}** ({runs}; ±{(values[-1] - values[0]) / 2:.2f})"


fixtures = sorted({key[0] for key in groups}, key=lambda name: int(name.replace("fixture", "")))
for fixture in fixtures:
    for (mode, jobs), title in mode_titles.items():
        keys = [key for key in groups if key[0] == fixture and key[1] == mode and key[2] == jobs]
        if not keys:
            continue
        mock_file_counts = sorted({key[4] for key in keys})
        print(f"\n### {fixture.replace('fixture', '')} types — {title}\n")
        for metric, unit in [("wall", "compile wall s"), ("user", "compile user CPU s")]:
            print(f"| {unit} | " + " | ".join(steps) + " |")
            print("|---|" + "---|" * len(steps))
            for mock_files in mock_file_counts:
                row = [cell([r["compile"][metric] for r in groups[(fixture, mode, jobs, step, mock_files)]]) for step in steps]
                print(f"| {label(mock_files)} | " + " | ".join(row) + " |")
            print()
        print("| generate wall s · files changed · files compiled (generated) | " + " | ".join(steps) + " |")
        print("|---|" + "---|" * len(steps))
        for mock_files in mock_file_counts:
            row = []
            for step in steps:
                runs = groups[(fixture, mode, jobs, step, mock_files)]
                generate_wall = statistics.median(r["generate"]["wall"] for r in runs)
                changed = runs[0]["generate"]["generated_files_changed"]
                total = runs[0]["generate"]["generated_files"]
                compiled = runs[0]["compile"]["objects_rebuilt"]
                compiled_generated = runs[0]["compile"]["generated_objects_rebuilt"]
                row.append(f"{generate_wall:.2f} · {changed}/{total} · {compiled} ({compiled_generated})")
            print(f"| {label(mock_files)} | " + " | ".join(row) + " |")
