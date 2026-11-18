#!/usr/bin/env python3
"""Usage: linux-coverage-report.py LCOV ROOT OUT_DIRECTORY [CHANGED_LINES_DIFF]

bin/linux-coverage runs this on the GitHub runner, in the checkout ROOT, after the suite ran with coverage.

Prints `path:line: source` for every line under ROOT/Sources/ and ROOT/Plugins/ that LCOV records as executed zero
times, then a summary line, and exits 1 when there is any such line (0 otherwise). With CHANGED_LINES_DIFF (the
output of `git diff -U0 BASE HEAD -- 'Sources/*.swift' 'Plugins/*.swift'`), only added or changed lines count.

As Scripts/changed-line-coverage.py does: a file the plugin compiles through a symbolic link and the file it links to
are one file (matched through os.path.realpath), whose counts are summed, and lines with no `DA` record (comments,
declarations) are skipped, as Codecov skips them. Also writes OUT_DIRECTORY/missed.json ({path: [line, ...]}, every
unexecuted line whatever the diff) for comparing with Codecov.

Two of Codecov's rules, measured against its report of 59879ebe3 (2026-11-14), shape the output:
- Codecov drops every line that is blank or whose only text is `{` or `}` (it keeps `)`, `},` and the like). llvm-cov
  marks a lone `}` unexecuted when a function's end follows a loop it only leaves by returning, so these lines are not
  counted here either; the summary says how many unexecuted ones were skipped. With them dropped, the line total
  under Sources/ equals Codecov's (32,266 lines at 59879ebe3).
- Codecov ignores Tests/, so a file compiled only through a symbolic link under Tests/ (the plugin files that
  SafeDIGeneratorPluginTests links in) is never in its number. Such lines are counted here, tagged
  `[Codecov does not count this file]`, and the summary counts them apart.
"""
import collections
import json
import os
import re
import sys

COUNTED_DIRECTORIES = ("Sources/", "Plugins/")
SKIPPED_TEXTS = ("", "{", "}")


def read_coverage(lcov_path, root):
    counts = collections.defaultdict(lambda: collections.defaultdict(int))
    codecov_counted = set()
    current = None
    with open(lcov_path, encoding="utf-8") as lcov:
        for record in lcov:
            record = record.rstrip("\n")
            if record.startswith("SF:"):
                relative = os.path.relpath(os.path.realpath(record[3:]), root)
                current = counts[relative] if relative.startswith(COUNTED_DIRECTORIES) else None
                if current is not None and not os.path.relpath(record[3:], root).startswith("Tests/"):
                    codecov_counted.add(relative)
            elif record.startswith("DA:") and current is not None:
                line_number, count = record[3:].split(",")[:2]
                current[int(line_number)] += int(count)
            elif record == "end_of_record":
                current = None
    return counts, codecov_counted


def read_changed_lines(diff_path, root):
    changed = collections.defaultdict(set)
    path = None
    new_line = 0
    with open(diff_path, encoding="utf-8") as diff:
        for line in diff:
            line = line.rstrip("\n")
            if line.startswith("+++ "):
                path = None if line == "+++ /dev/null" else line[len("+++ b/"):]
                # A symbolic link's diff is its target's text, not lines of Swift.
                if path is not None and os.path.islink(os.path.join(root, path)):
                    path = None
            elif line.startswith("@@"):
                match = re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", line)
                new_line = int(match.group(1)) if match else 0
            elif path is not None and line.startswith("+"):
                changed[os.path.relpath(os.path.realpath(os.path.join(root, path)), root)].add(new_line)
                new_line += 1
    return changed


def main():
    if len(sys.argv) not in (4, 5):
        print(__doc__, file=sys.stderr)
        return 2
    lcov_path, root, out_directory = sys.argv[1], os.path.realpath(sys.argv[2]), sys.argv[3]
    coverage, codecov_counted = read_coverage(lcov_path, root)
    changed = read_changed_lines(sys.argv[4], root) if len(sys.argv) == 5 else None
    instrumented = 0
    counted_instrumented = 0
    missed = {}
    sources = {}
    lone_braces = 0
    for path in sorted(coverage):
        with open(os.path.join(root, path), encoding="utf-8") as source:
            sources[path] = source.read().split("\n")
        file_counts = {line: count for line, count in coverage[path].items() if sources[path][line - 1].strip() not in SKIPPED_TEXTS}
        lone_braces += sum(1 for line, count in coverage[path].items() if count == 0 and line not in file_counts)
        instrumented += len(file_counts)
        counted_instrumented += len(file_counts) if path in codecov_counted else 0
        lines = sorted(line for line, count in file_counts.items() if count == 0)
        if lines:
            missed[path] = lines
    with open(os.path.join(out_directory, "missed.json"), "w", encoding="utf-8") as output:
        json.dump(missed, output, indent=1, sort_keys=True)
    reported = 0
    reported_uncounted = 0
    for path in sorted(missed):
        lines = [line for line in missed[path] if changed is None or line in changed.get(path, ())]
        tag = "" if path in codecov_counted else "  [Codecov does not count this file]"
        for line in lines:
            reported += 1
            reported_uncounted += 0 if path in codecov_counted else 1
            print("%s:%d: %s%s" % (path, line, sources[path][line - 1].strip(), tag))
    total_missed = sum(len(lines) for lines in missed.values())
    counted_missed = sum(len(lines) for path, lines in missed.items() if path in codecov_counted)
    percent = 100.0 * (instrumented - total_missed) / instrumented if instrumented else 0.0
    print(
        "linux-coverage: %d instrumented lines under Sources/ and Plugins/ in %d files, %d not executed (%.2f%%); "
        "in files Codecov counts: %d lines, %d not executed"
        % (instrumented, len(coverage), total_missed, percent, counted_instrumented, counted_missed)
    )
    print("skipped %d unexecuted line(s) that are blank or a lone brace, as Codecov skips them" % lone_braces)
    split = "%d in files Codecov counts, %d in files it does not" % (reported - reported_uncounted, reported_uncounted)
    if changed is None:
        print("%d line(s) no test executed (%s)" % (reported, split))
    else:
        print("%d changed line(s) no test executed (%s; of %d changed lines)" % (reported, split, sum(len(lines) for lines in changed.values())))
    return 1 if reported else 0


if __name__ == "__main__":
    sys.exit(main())
