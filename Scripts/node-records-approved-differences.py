#!/usr/bin/env python3
"""Tallies the approved differences a run of the tests used.

Usage: Scripts/node-records-approved-differences.py REPORT [REPORT ...]

REPORT is a file a test run wrote where SAFEDI_NODE_RECORDS_REPORT named it: one line per root, whose seventh
column lists the entries of the approved differences that account for the root's differences from its tree
(NodeRecordsChecks.outcome). Prints how many roots each entry the check knows was used on, and fails for an entry
no root used: a rewrite nothing uses is removed, or its roots have stopped differing and the entry with them.
Also prints how often each rewrite took each choice it reads from the tree's text.
"""

import pathlib
import re
import sys

REGISTRY = pathlib.Path(__file__).resolve().parent.parent / "Tests" / "SafeDIToolTestSupport" / "ApprovedDifferences.swift"


def registered_entries():
    """The entries `ApprovedDifferences.all` lists, each a name declared `static let NAME = ApprovedDifference(…)`."""
    source = REGISTRY.read_text(encoding="utf-8")
    declared = {
        name: (int(entry), title)
        for name, entry, title in re.findall(r'static let (\w+) = ApprovedDifference\(entry: (\d+), name: "([^"]+)"', source)
    }
    listed = re.search(r"static let all: \[ApprovedDifference\] = \[(.*?)\]", source, re.S)
    if listed is None:
        raise SystemExit(f"{REGISTRY}: no list of approved differences")
    return [declared[name] for name in re.findall(r"\w+", listed.group(1))]


def main(arguments):
    if not arguments:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    roots_by_entry = {}
    choices_by_entry = {}
    for argument in arguments:
        for line in pathlib.Path(argument).read_text(encoding="utf-8").splitlines():
            columns = line.split("\t")
            if len(columns) < 7 or not columns[6]:
                continue
            for used in columns[6].split(","):
                entry, _, choices = used.rstrip("]").partition("[")
                roots_by_entry.setdefault(int(entry), set()).add((columns[0], columns[1]))
                for choice in filter(None, choices.split("+")):
                    choices_by_entry.setdefault(int(entry), {}).setdefault(choice, 0)
                    choices_by_entry[int(entry)][choice] += 1
    unused = []
    registered = registered_entries()
    for entry in sorted(set(roots_by_entry) - {entry for entry, _ in registered}):
        print(f"entry {entry} is used on {len(roots_by_entry[entry])} roots and is not listed", file=sys.stderr)
        unused.append(entry)
    for entry, name in registered:
        count = len(roots_by_entry.get(entry, ()))
        print(f"entry {entry} ({name}): {count} roots")
        for choice, taken in sorted(choices_by_entry.get(entry, {}).items()):
            print(f"  chose {choice}: {taken} times")
        if count == 0:
            unused.append(entry)
    if unused:
        print("Used on no root, or not listed: " + ", ".join(f"entry {entry}" for entry in unused), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
