#!/usr/bin/env python3
"""Usage: git diff -U0 BASE HEAD -- 'Sources/SafeDICore/*.swift' 'Sources/SafeDIToolLibrary/*.swift' \\
    | fuzzer-changed-line-coverage.py --corpus CORPUS_LCOV --functions CORPUS_JSON [--suite SUITE_LCOV] \\
      [--suite-failed] [--compared BASE..HEAD] [--missing-shard NAME]...

Prints the added or changed generator lines that no graph of the fuzzer's corpora executed, in numbered runs of
consecutive executable lines, each with the function it is in. CORPUS_LCOV and CORPUS_JSON are `llvm-cov export`'s
lcov and JSON (`-format=text`) of the fuzzer's long run over every corpus; the JSON gives each function's range, so a
run names the innermost function that holds it. SUITE_LCOV, when given, is the unit suite's coverage, and splits the
lines, one by one, into those a unit test reaches (the corpus draws no graph for that shape) and those nothing reaches.
A run whose lines throw or build an error is tagged `[error path?]`; the tag only orders the list. The default value of
a stored property that every initializer passes explicitly runs nowhere, so such lines are counted and not listed.
`--suite-failed` says the unit suite failed in the run that wrote SUITE_LCOV, and each `--missing-shard` names a
shard that wrote no profile; the header reports both. Files are matched through
`os.path.realpath`, as changed-line-coverage.py matches them. Run it from the checkout the coverage was built from, at
the same commit. Exits 0; the report is the output.
"""
import argparse
import collections
import json
import os
import re
import subprocess
import sys


def read_line_counts(lcov_path):
    """The execution count of each line, per file, summed over the copies of a file that symbolic links compile."""
    counts = collections.defaultdict(dict)
    current = None
    with open(lcov_path, encoding="utf-8") as lcov:
        for record in lcov:
            record = record.rstrip("\n")
            if record.startswith("SF:"):
                current = counts[os.path.realpath(record[3:])]
            elif current is None:
                continue
            elif record.startswith("DA:"):
                line_number, count = record[3:].split(",")[:2]
                current[int(line_number)] = current.get(int(line_number), 0) + int(count)
            elif record == "end_of_record":
                current = None
    return counts


class Function:
    def __init__(self, start, end, name):
        self.start = start
        self.end = end
        self.name = name
        self.readable = name
        self.count = 0


def read_functions(json_path, wanted_paths):
    """Each function of the wanted files, with the lines its own file's regions span and how often it was entered.
    A function compiled twice (through a symbolic link) is one function, entered as often as both copies."""
    with open(json_path, encoding="utf-8") as export:
        data = json.load(export)
    functions = collections.defaultdict(dict)
    for export_data in data.get("data", []):
        for function in export_data.get("functions", []):
            filenames = function.get("filenames") or []
            if not filenames:
                continue
            path = os.path.realpath(filenames[0])
            if path not in wanted_paths:
                continue
            # A region is [line start, column start, line end, column end, count, file, expanded file, kind].
            lines = [(region[0], region[2]) for region in function.get("regions", []) if region[5] == 0]
            if not lines:
                continue
            key = (min(start for start, _ in lines), max(end for _, end in lines))
            entry = functions[path].get(key)
            if entry is None:
                entry = functions[path][key] = Function(key[0], key[1], function["name"])
            else:
                entry.name = min(entry.name, function["name"])
            entry.count += function.get("count", 0)
    return {path: sorted(by_range.values(), key=lambda function: (function.start, function.end)) for path, by_range in functions.items()}


def read_changed_lines(diff):
    changed = collections.defaultdict(set)
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
            changed[path].add(new_line)
            new_line += 1
    return changed


def demangle(names):
    names = sorted(set(names))
    if not names:
        return {}
    try:
        result = subprocess.run(
            ["swift", "demangle", "--simplified", "--compact"],
            input="\n".join(names) + "\n", capture_output=True, text=True, check=True,
        )
        demangled = result.stdout.rstrip("\n").split("\n")
        if len(demangled) == len(names):
            return dict(zip(names, demangled))
    except (OSError, subprocess.CalledProcessError):
        pass
    return {name: name for name in names}


def shortened(function):
    """Collapses long argument-label lists, so a run's heading stays one readable line."""
    return re.sub(r"\(([^()]{40,})\)", "(…)", function)


def innermost_function(functions, line_number, skipping_closures=False):
    """The function whose range holds the line and starts last, or ends first among those that start on one line;
    skipping closures, the innermost declared function, which names a run in the report."""
    found = None
    for function in functions:
        if function.start > line_number:
            break
        if skipping_closures and CLOSURE_PATTERN.match(function.readable):
            continue
        if function.end >= line_number and (found is None or function.start > found.start or function.end < found.end):
            found = function
    return found


CLOSURE_PATTERN = re.compile(r"(implicit )?closure #\d+ in ")


# The mangled suffix of a stored property's initial value ("variable initialization expression of …").
PROPERTY_INITIAL_VALUE_PATTERN = re.compile(r"vpfi$")
# A hint that a run builds a diagnostic rather than generated code. It only orders the report.
ERROR_LINE_PATTERN = re.compile(r"\bthrow\b|SourceDiagnostic\(|Error\(|severity: \.error")
ERROR_FUNCTION_PATTERN = re.compile(r"Error|[Dd]iagnostic|[Rr]emedy|Explanation|Finding|[Ww]arning")

# Files the fuzzer does not exercise by design: other subcommands, caches, the scan's file handling. Their changed
# lines are counted and not listed.
NOT_TARGETED_PATTERN = re.compile(
    r"Sources/SafeDIToolLibrary/(QueryCommand|DumpCommand|ScanCommand|BinaryCod\w*|BinaryFile|FileModificationStamp|"
    r"BuildSettingCompilationConditions|ModulesBeneathSelection)\.swift$"
)

HEADER = """\
A line listed here has no draw. A line not listed was executed, not necessarily judged by an oracle.
Give each run a one-line disposition where the change is handed back or reviewed: `R<n>: draw added`,
`R<n>: rejected-graph draw added`, or `R<n>: no graph can reach, because …`. The `[error path?]` tag only orders
the list."""


def main():
    parser = argparse.ArgumentParser(usage=__doc__)
    parser.add_argument("--corpus", required=True)
    parser.add_argument("--functions", required=True)
    parser.add_argument("--suite")
    parser.add_argument("--suite-failed", action="store_true")
    parser.add_argument("--compared")
    parser.add_argument("--missing-shard", action="append", default=[])
    arguments = parser.parse_args()

    changed = read_changed_lines(sys.stdin)
    corpus = read_line_counts(arguments.corpus)
    suite = read_line_counts(arguments.suite) if arguments.suite else None
    functions = read_functions(arguments.functions, {os.path.realpath(path) for path in changed})
    readable = demangle(function.name for file_functions in functions.values() for function in file_functions)
    for file_functions in functions.values():
        for function in file_functions:
            function.readable = readable.get(function.name, function.name)

    executable_count = 0
    corpus_executed_count = 0
    initial_value_count = 0
    not_targeted_count = 0
    unrecorded_paths = []
    # Runs of unexecuted changed lines, each in one file, in one declared function (closures are part of the function
    # that declares them), and on one side of the unit-suite split, joined across lines that have no counter
    # (comments, braces, declarations) but split by any line that has one.
    runs = []
    for path in sorted(changed):
        real_path = os.path.realpath(path)
        line_counts = corpus.get(real_path)
        if line_counts is None:
            unrecorded_paths.append(path)
            continue
        if NOT_TARGETED_PATTERN.search(path):
            not_targeted_count += sum(1 for line in changed[path] if line in line_counts)
            continue
        file_functions = functions.get(real_path, [])
        suite_counts = suite.get(real_path, {}) if suite is not None else None
        for line_number in sorted(changed[path]):
            count = line_counts.get(line_number)
            if count is None:
                continue
            executable_count += 1
            if count > 0:
                corpus_executed_count += 1
                continue
            innermost = innermost_function(file_functions, line_number)
            if innermost is not None and PROPERTY_INITIAL_VALUE_PATTERN.search(innermost.name):
                initial_value_count += 1
                continue
            function = innermost_function(file_functions, line_number, skipping_closures=True) or innermost
            reach = "unknown" if suite_counts is None else ("tests" if suite_counts.get(line_number, 0) > 0 else "nothing")
            if runs and runs[-1]["path"] == path and runs[-1]["function"] is function and runs[-1]["reach"] == reach:
                gap = range(runs[-1]["lines"][-1] + 1, line_number)
                if all(line_counts.get(line) is None for line in gap):
                    runs[-1]["lines"].append(line_number)
                    continue
            runs.append({"path": path, "function": function, "reach": reach, "lines": [line_number]})

    sources = {}
    for run in runs:
        path = run["path"]
        if path not in sources:
            with open(path, encoding="utf-8") as source:
                sources[path] = source.read().split("\n")
        run["text"] = [sources[path][line - 1] if line <= len(sources[path]) else "" for line in run["lines"]]
        function = run["function"]
        run["function_name"] = shortened(function.readable) if function else "?"
        run["entered"] = function is None or function.count > 0
        run["error_path"] = any(ERROR_LINE_PATTERN.search(line) for line in run["text"]) or bool(ERROR_FUNCTION_PATTERN.search(run["function_name"]))

    unexecuted_count = sum(len(run["lines"]) for run in runs)
    if arguments.compared:
        print(f"Changed generator lines in {arguments.compared} that no fuzzer corpus graph executed.")
    else:
        print("Changed generator lines that no fuzzer corpus graph executed.")
    print(HEADER)
    print()
    if arguments.missing_shard:
        print(f"Shard(s) {', '.join(sorted(arguments.missing_shard))} wrote no coverage profile (a crashed or timed-out "
              "fuzzer writes none), so lines only those shards would have executed are listed too.")
    if suite is None:
        print("No unit-suite profile, so the runs are not split by whether a unit test reaches them.")
    elif arguments.suite_failed:
        print("The unit suite failed in this run, so a line a failing test would have reached may be listed as one "
              "nothing reaches.")
    print(f"{executable_count} changed executable generator line(s); the corpus executed {corpus_executed_count}, "
          f"and no corpus graph executed {unexecuted_count}, in {len(runs)} run(s).")
    if initial_value_count:
        print(f"{initial_value_count} changed line(s) are default values of stored properties that every initializer "
              "passes explicitly, so nothing runs them; they are not listed.")
    if not_targeted_count:
        print(f"{not_targeted_count} changed line(s) in files the fuzzer does not exercise by design were not checked.")
    for path in unrecorded_paths:
        print(f"{path} changed but has no coverage record; it was not checked.")

    titles = {
        "tests": "Unit tests reach these, no corpus graph does",
        "nothing": "Neither the unit tests nor the corpus reach these: a test first",
        "unknown": "No corpus graph reaches these",
    }
    number = 0
    for reach in ("tests", "nothing", "unknown"):
        group = [run for run in runs if run["reach"] == reach]
        if not group:
            continue
        # Runs that look like generated-code paths first, then those that look like error paths, each in file order.
        group.sort(key=lambda run: run["error_path"])
        print()
        print(f"## {titles[reach]} ({len(group)} run(s), {sum(len(run['lines']) for run in group)} line(s))")
        for run in group:
            number += 1
            lines = run["lines"]
            span = f"{lines[0]}" if len(lines) == 1 else f"{lines[0]}-{lines[-1]}"
            tags = ""
            if not run["entered"]:
                tags += "  [the corpus never enters this function]"
            if run["error_path"]:
                tags += "  [error path?]"
            print(f"R{number} {run['path']}:{span} ({len(lines)} line(s)) in {run['function_name']}{tags}")
            shown = list(zip(lines, run["text"]))[:4]
            for line_number, source_line in shown:
                print(f"    {line_number}: {source_line.strip()}")
            if len(lines) > len(shown):
                print(f"    … {len(lines) - len(shown)} more")
    return 0


if __name__ == "__main__":
    sys.exit(main())
