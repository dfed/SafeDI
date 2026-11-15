#!/usr/bin/env python3
"""Compares two dump directories written by `executeSafeDIToolTest` under SAFEDI_SPIKE_DUMP_DIRECTORY.

python3 compare_dumps.py BASE_DUMP SPIKE_DUMP [--json OUT]

Counts, over every generated file that holds a root's `init()` (a root tree): total root-tree lines in each, the tests
whose files changed, the ten largest reductions, the share of root-tree lines removed (copies), and how many root
trees build a type in two or more builder functions.
"""
import json
import os
import re
import sys

TEMPORARY_PATH = re.compile(r"(?:/[\w.-]+)*/test-run-[\w-]+/[\w-]+/")
ROOT_INIT = re.compile(r"^    (?:@\S+ )*public (?:convenience )?init\(\) \{$", re.M)
FUNCTION = re.compile(r"^\s*(?:@Sendable )?func (__safeDI_\w+)\(.*\) -> (.+) \{$")


def root_bodies(text):
    """The bodies of every root `init()` in a file."""
    lines = text.split("\n")
    bodies = []
    index = 0
    while index < len(lines):
        if ROOT_INIT.match(lines[index]):
            end = index + 1
            while end < len(lines) and not lines[end].startswith("        self.init("):
                end += 1
            bodies.append(lines[index + 1:end + 1])
            index = end
        index += 1
    return bodies


def builds_a_type_twice(body):
    counts = {}
    for line in body:
        match = FUNCTION.match(line)
        if match:
            counts[match.group(2)] = counts.get(match.group(2), 0) + 1
    return any(count > 1 for count in counts.values())


def walk(root):
    files = {}
    for directory, _, names in os.walk(root):
        for name in names:
            if name.endswith(".swift"):
                path = os.path.join(directory, name)
                with open(path, errors="replace") as handle:
                    # Fixture paths hold a per-run temporary directory.
                    files[os.path.relpath(path, root)] = TEMPORARY_PATH.sub("<fixture>/", handle.read())
    return files


def main():
    base_root, spike_root = sys.argv[1], sys.argv[2]
    base, spike = walk(base_root), walk(spike_root)
    report = {"files_only_in_base": sorted(set(base) - set(spike)), "files_only_in_spike": sorted(set(spike) - set(base))}
    base_lines = spike_lines = 0
    trees = trees_twice_base = trees_twice_spike = 0
    changed_tests = set()
    changed_files = []
    reductions = []
    for path in sorted(set(base) & set(spike)):
        base_bodies, spike_bodies = root_bodies(base[path]), root_bodies(spike[path])
        if not base_bodies:
            if base[path] != spike[path]:
                changed_files.append((path, "non-root file changed"))
            continue
        b = sum(len(body) for body in base_bodies)
        s = sum(len(body) for body in spike_bodies)
        base_lines += b
        spike_lines += s
        trees += len(base_bodies)
        trees_twice_base += sum(1 for body in base_bodies if builds_a_type_twice(body))
        trees_twice_spike += sum(1 for body in spike_bodies if builds_a_type_twice(body))
        if base[path] != spike[path]:
            test = path.split(os.sep)[0]
            changed_tests.add(test)
            changed_files.append((path, f"{b} -> {s}"))
            reductions.append((b - s, path, b, s))
    reductions.sort(reverse=True)
    report.update({
        "root_trees": trees,
        "root_tree_lines_base": base_lines,
        "root_tree_lines_spike": spike_lines,
        "share_of_lines_that_are_copies": (base_lines - spike_lines) / base_lines if base_lines else 0,
        "trees_building_a_type_twice_base": trees_twice_base,
        "trees_building_a_type_twice_spike": trees_twice_spike,
        "tests_changed": len(changed_tests),
        "files_changed": len(changed_files),
        "largest_reductions": [{"file": p, "base": b, "spike": s, "removed": r} for r, p, b, s in reductions[:10]],
        "non_root_files_changed": [p for p, why in changed_files if why == "non-root file changed"],
        "changed_test_names": sorted(changed_tests),
    })
    print(json.dumps({k: v for k, v in report.items() if k != "changed_test_names"}, indent=1))
    if len(sys.argv) > 4 and sys.argv[3] == "--json":
        with open(sys.argv[4], "w") as handle:
            json.dump(report, handle, indent=1)


if __name__ == "__main__":
    main()
