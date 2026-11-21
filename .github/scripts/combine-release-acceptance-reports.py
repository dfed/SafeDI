"""usage: combine-release-acceptance-reports.py REPORTS-DIRECTORY SHARD-COUNT

Checks release acceptance across the reports of graph-fuzzer.yml's comparing
shards, each in a folder of its own under REPORTS-DIRECTORY, and prints a
Markdown summary. Each shard's long run
(SafeDIToolReleaseAcceptanceTests/longRun) writes

    release-acceptance release=<older release> seeds=<first>..<<end>
    seed <seed> <class>[/<rejection>] [annotations=…] roots=<n> mocks=<n> [skips=…]
    known-break <seed> <reason>      (a listed break the seed shows)
    exempted <seed> <reason>         (a listed defect of the older release)
    failure <seed> <class> <detail>  (an unlisted break, or values not compared)
    stale <seed> <class> <reason>    (a listed seed that no longer shows its class)
    problem <text>                   (anything wrong with the run itself)
    classes A=<n> B=<n> C=<n> D=<n> E=<n> F=<n> X=<n>
    rejections tool=<n> macro=<n> compile=<n>
    annotations new-source-diagnostic=<n> shared-generated-warning=<n>
    probes roots=<n> mocks=<n>
    skips only-current=<n> only-older-release=<n>
    compared count=<n> sum=<seed-set sum>
    cpu wall=<seconds>
    completed <seeds judged>

The shards must be SHARD-COUNT reports of one older release that each
complete and together cover the base corpus's seeds 0..<CORPUS_SEED_COUNT
exactly once; no shard may report a failure, a stale seed or a problem; and the
graphs compared by value (classes B and F, both releases accepting and
compiling cleanly) must reach COMPARED_GRAPH_FLOOR. Exits non-zero otherwise.
"""

import os
import sys

# SafeDIToolGraphFuzzerTests.corpusSeedCount.
CORPUS_SEED_COUNT = 5000
# The graphs both releases accept and compile cleanly, which the values compare.
# Set from run 44696894161, which compared 2679 graphs against 2.3.0, every
# graph of the base corpus this tree accepts (corpusAcceptedSeedCount): about a
# tenth below it, so a runner that stops comparing a whole shard's worth fails,
# while the count may move a little with a change that rejects or accepts a few
# graphs.
COMPARED_GRAPH_FLOOR = 2400

reports_directory = sys.argv[1]
expected_shard_count = int(sys.argv[2])
problems = []
releases = set()
ranges = []
class_counts = {}
rejection_counts = {}
annotation_counts = {}
skip_counts = {}
probe_counts = {}
compared_count = 0
compared_sum = 0
listed = []
findings = []
wall_seconds = []

report_paths = sorted(
    os.path.join(root, name)
    for root, _, names in os.walk(reports_directory)
    for name in names
    if name == "report.txt"
)
if len(report_paths) != expected_shard_count:
    problems.append(f"expected {expected_shard_count} shard reports, found {len(report_paths)}")


def add_counts(target, fields):
    for field in fields:
        key, _, value = field.partition("=")
        target[key] = target.get(key, 0) + int(value)


for path in report_paths:
    with open(path, encoding="utf-8") as report:
        lines = report.read().splitlines()
    completed = False
    for line in lines:
        kind, _, rest = line.partition(" ")
        fields = rest.split()
        if kind == "release-acceptance":
            values = dict(field.split("=", 1) for field in fields)
            releases.add(values["release"])
            first, _, end = values["seeds"].partition("..<")
            ranges.append((int(first), int(end), path))
        elif kind == "classes":
            add_counts(class_counts, fields)
        elif kind == "rejections":
            add_counts(rejection_counts, fields)
        elif kind == "annotations":
            add_counts(annotation_counts, fields)
        elif kind == "skips":
            add_counts(skip_counts, fields)
        elif kind == "probes":
            add_counts(probe_counts, fields)
        elif kind == "compared":
            values = dict(field.split("=", 1) for field in fields)
            compared_count += int(values["count"])
            compared_sum = (compared_sum + int(values["sum"])) % (1 << 64)
        elif kind in ("known-break", "exempted"):
            listed.append(line)
        elif kind in ("failure", "stale", "problem"):
            findings.append(line)
        elif kind == "cpu":
            wall_seconds.append(int(dict(field.split("=", 1) for field in fields)["wall"]))
        elif kind == "completed":
            completed = True
    if not completed:
        problems.append(f"{path} does not complete: its shard crashed, timed out or was skipped")

if len(releases) > 1:
    problems.append(f"the shards compared different releases: {sorted(releases)}")
covered = sorted(ranges)
next_seed = 0
for first, end, path in covered:
    if first != next_seed:
        problems.append(f"the shards do not cover the corpus once: {path} starts at {first}, expected {next_seed}")
    next_seed = max(next_seed, end)
if ranges and next_seed != CORPUS_SEED_COUNT:
    problems.append(f"the shards end at seed {next_seed}, not {CORPUS_SEED_COUNT}")
if compared_count < COMPARED_GRAPH_FLOOR:
    problems.append(f"{compared_count} graphs compared by value, below the floor of {COMPARED_GRAPH_FLOOR}")
problems += findings

release = ", ".join(sorted(releases)) or "unknown"
print(f"## Release acceptance against SafeDI {release}")
print()
print("| Class | Graphs |")
print("|---|---|")
descriptions = {
    "A": "older release rejects",
    "B": "values agree",
    "C": "this tree rejects",
    "D": "this tree's code does not compile",
    "E": "new generated warning",
    "F": "values differ",
    "X": "values not compared",
}
for key, description in descriptions.items():
    print(f"| {key}: {description} | {class_counts.get(key, 0)} |")
print()
print("Older release's rejections: " + ", ".join(f"{key} {value}" for key, value in sorted(rejection_counts.items())))
print()
print("Annotations: " + ", ".join(f"{key} {value}" for key, value in sorted(annotation_counts.items())))
print()
print(f"Compared by value: {compared_count} graphs (floor {COMPARED_GRAPH_FLOOR}, seed-set sum {compared_sum}), "
      + ", ".join(f"{value} {key} probes" for key, value in sorted(probe_counts.items()))
      + "; probes skipped: " + ", ".join(f"{key} {value}" for key, value in sorted(skip_counts.items())))
print()
if wall_seconds:
    print(f"Shard wall seconds: {', '.join(str(seconds) for seconds in wall_seconds)}")
    print()
if listed:
    print("Listed seeds:")
    print()
    for line in listed:
        print(f"- `{line}`")
    print()
if problems:
    print("**Problems:**")
    print()
    for problem in problems:
        print(f"- `{problem}`")
    sys.exit(1)
print("No unlisted break.")
