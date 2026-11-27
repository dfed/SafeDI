#!/usr/bin/env python3
"""Tallies the approved differences a run of the tests used.

Usage: Scripts/node-records-approved-differences.py REPORT [REPORT ...]

REPORT is a file a test run wrote where SAFEDI_NODE_RECORDS_REPORT named it: one line per root, whose seventh
column lists the entries of the approved differences that account for the root's differences from its tree
(NodeRecordsChecks.outcome). Prints how many roots each entry the check knows was used on, and fails for an entry
no root used: a rewrite nothing uses is removed, or its roots have stopped differing and the entry with them.
"""

import pathlib
import re
import sys

REGISTRY = pathlib.Path(__file__).resolve().parent.parent / "Tests" / "SafeDIToolTestSupport" / "ApprovedDifferences.swift"


def registered_entries():
    pattern = re.compile(r'ApprovedDifference\(entry: (\d+), name: "([^"]+)"')
    return [(int(entry), name) for entry, name in pattern.findall(REGISTRY.read_text(encoding="utf-8"))]


def main(arguments):
    if not arguments:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    roots_by_entry = {}
    for argument in arguments:
        for line in pathlib.Path(argument).read_text(encoding="utf-8").splitlines():
            columns = line.split("\t")
            if len(columns) < 7 or not columns[6]:
                continue
            for entry in columns[6].split(","):
                roots_by_entry.setdefault(int(entry), set()).add((columns[0], columns[1]))
    unused = []
    for entry, name in registered_entries():
        count = len(roots_by_entry.get(entry, ()))
        print(f"entry {entry} ({name}): {count} roots")
        if count == 0:
            unused.append(entry)
    if unused:
        print("No root used: " + ", ".join(f"entry {entry}" for entry in unused), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
