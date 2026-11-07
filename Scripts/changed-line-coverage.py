#!/usr/bin/env python3
"""Usage: git diff -U0 BASE -- 'Sources/*.swift' 'Plugins/*.swift' | changed-line-coverage.py LCOV

Prints `path:line: source` for every added or changed line the lcov report records as executed zero times, and a
total; exits 1 when the total is not zero. Files are matched through `os.path.realpath`, so a file the plugin
compiles through a symbolic link and the file it links to are one file, whose counts are summed. Lines with no
`DA` record (comments, declarations) are skipped, as Codecov skips them.
"""
import collections
import os
import re
import sys


def read_coverage(lcov_path):
    counts = collections.defaultdict(lambda: collections.defaultdict(int))
    current = None
    with open(lcov_path, encoding="utf-8") as lcov:
        for record in lcov:
            record = record.rstrip("\n")
            if record.startswith("SF:"):
                current = counts[os.path.realpath(record[3:])]
            elif record.startswith("DA:") and current is not None:
                line_number, count = record[3:].split(",")[:2]
                current[int(line_number)] += int(count)
            elif record == "end_of_record":
                current = None
    return counts


def read_changed_lines(diff):
    changed = collections.defaultdict(list)
    path = None
    new_line = 0
    for line in diff:
        line = line.rstrip("\n")
        if line.startswith("+++ "):
            path = None if line == "+++ /dev/null" else line[len("+++ b/"):]
        elif line.startswith("@@"):
            match = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", line)
            new_line = int(match.group(1)) if match else 0
        elif path is not None and line.startswith("+"):
            changed[path].append(new_line)
            new_line += 1
    return changed


def main():
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    coverage = read_coverage(sys.argv[1])
    changed = read_changed_lines(sys.stdin)
    unexecuted = 0
    for path in sorted(changed):
        file_counts = coverage.get(os.path.realpath(path))
        if file_counts is None:
            continue
        with open(path, encoding="utf-8") as source:
            source_lines = source.read().split("\n")
        for line_number in changed[path]:
            if file_counts.get(line_number) == 0:
                unexecuted += 1
                print(f"{path}:{line_number}: {source_lines[line_number - 1].strip()}")
    print(f"{unexecuted} changed line(s) no test executed")
    return 1 if unexecuted else 0


if __name__ == "__main__":
    sys.exit(main())
