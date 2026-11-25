"""usage: combine-release-acceptance-reports.py REPORTS-DIRECTORY CORPUS=SHARD-COUNT...

Checks release acceptance across the reports of release-acceptance.yml's
comparing shards, each in a folder of its own under REPORTS-DIRECTORY, and
prints a Markdown summary. Each CORPUS=SHARD-COUNT names a corpus the run
compares (base, seam or public-mock) and how many shards it is split into.
Each shard's long run (SafeDIToolReleaseAcceptanceTests/longRun) writes

    release-acceptance release=<older release> corpus=<corpus> seeds=<first>..<<end>
    seed <seed> <class>[/<rejection>] [annotations=…] roots=<n> mocks=<n> [skips=…]
    known-break <seed> <reason>      (a listed break the seed shows)
    exempted <seed> <reason>         (a listed defect of the older release)
    beyond-comparator <seed> <reason> (a listed graph the comparator cannot describe)
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

A report without `corpus=` is the base corpus's. Every report must be of one
older release and complete; each named corpus must have exactly its shard
count of reports, which together cover its seeds 0..<CORPUS_SEED_COUNTS[corpus]
exactly once, and no report may be of a corpus not named; no shard may report
a failure, a stale seed or a problem; and each corpus's graphs compared by
value (classes B and F, both releases accepting and compiling cleanly) must
reach its COMPARED_GRAPH_FLOORS entry. Exits non-zero otherwise.
"""

import os
import sys

# SafeDIToolGraphFuzzerTests.corpusSeedCount, seamCorpusSeedCount and
# publicMockCorpusSeedCount.
CORPUS_SEED_COUNTS = {"base": 5000, "seam": 2000, "public-mock": 1000}
# The graphs both releases accept and compile cleanly, which the values
# compare, per corpus: about a tenth below what a run compared, so a runner
# that stops comparing a whole shard's worth fails, while the count may move a
# little with a change that rejects or accepts a few graphs.
# Base: run 44696894161 compared 2679 graphs against 2.3.0, every graph of the
# base corpus this tree accepts (corpusAcceptedSeedCount).
# Seam and public mock: run 44868740614 compared 623 seam graphs, beside 6 whose
# probes spent the batch's traversals and are now compared on their own (629,
# seamCorpusAcceptedSeedCount's graphs that 2.3.0 accepts), and 897 public mock
# graphs, publicMockCorpusAcceptedSeedCount.
# Public mock, lowered to 650: one public mock graph in five takes a `@Sendable`
# autoclosure with a default (`drawsSendableAutoclosureDefault`), whose public
# mock 2.3.0 takes as `(() -> T)?` and captures in a `@Sendable` function, so
# its code does not compile ("implicit capture of 'pollInterval' requires that
# '() -> Int' conforms to 'Sendable'") and the graph is class A. Of the 205
# graphs that draw it, 161 that both releases compare with the roll off are
# class A with it on, and no other graph changes class; run 45517807548
# compared 685.
COMPARED_GRAPH_FLOORS = {"base": 2400, "seam": 560, "public-mock": 650}

reports_directory = sys.argv[1]
expected_shard_counts = {}
for argument in sys.argv[2:]:
    corpus, _, count = argument.partition("=")
    if corpus not in CORPUS_SEED_COUNTS or not count.isdigit():
        sys.exit(f"usage: {sys.argv[0]} REPORTS-DIRECTORY CORPUS=SHARD-COUNT..., CORPUS one of {sorted(CORPUS_SEED_COUNTS)}")
    expected_shard_counts[corpus] = int(count)
if not expected_shard_counts:
    sys.exit(f"usage: {sys.argv[0]} REPORTS-DIRECTORY CORPUS=SHARD-COUNT...")
problems = []
releases = set()


class Corpus:
    def __init__(self):
        self.ranges = []
        self.class_counts = {}
        self.rejection_counts = {}
        self.annotation_counts = {}
        self.skip_counts = {}
        self.probe_counts = {}
        self.compared_count = 0
        self.compared_sum = 0
        self.listed = []
        self.wall_seconds = []


corpora = {}
findings = []

report_paths = sorted(
    os.path.join(root, name)
    for root, _, names in os.walk(reports_directory)
    for name in names
    if name == "report.txt"
)


def add_counts(target, fields):
    for field in fields:
        key, _, value = field.partition("=")
        target[key] = target.get(key, 0) + int(value)


for path in report_paths:
    with open(path, encoding="utf-8") as report:
        lines = report.read().splitlines()
    completed = False
    corpus = None
    for line in lines:
        kind, _, rest = line.partition(" ")
        fields = rest.split()
        if kind == "release-acceptance":
            values = dict(field.split("=", 1) for field in fields)
            releases.add(values["release"])
            corpus = corpora.setdefault(values.get("corpus", "base"), Corpus())
            corpus_name = values.get("corpus", "base")
            first, _, end = values["seeds"].partition("..<")
            corpus.ranges.append((int(first), int(end), path))
        elif corpus is None:
            continue
        elif kind == "classes":
            add_counts(corpus.class_counts, fields)
        elif kind == "rejections":
            add_counts(corpus.rejection_counts, fields)
        elif kind == "annotations":
            add_counts(corpus.annotation_counts, fields)
        elif kind == "skips":
            add_counts(corpus.skip_counts, fields)
        elif kind == "probes":
            add_counts(corpus.probe_counts, fields)
        elif kind == "compared":
            values = dict(field.split("=", 1) for field in fields)
            corpus.compared_count += int(values["count"])
            corpus.compared_sum = (corpus.compared_sum + int(values["sum"])) % (1 << 64)
        elif kind in ("known-break", "exempted", "beyond-comparator"):
            corpus.listed.append(line)
        elif kind in ("failure", "stale", "problem"):
            findings.append(f"{corpus_name}: {line}")
        elif kind == "cpu":
            corpus.wall_seconds.append(int(dict(field.split("=", 1) for field in fields)["wall"]))
        elif kind == "completed":
            completed = True
    if corpus is None:
        problems.append(f"{path} names no release and corpus")
    if not completed:
        problems.append(f"{path} does not complete: its shard crashed, timed out or was skipped")

if len(releases) > 1:
    problems.append(f"the shards compared different releases: {sorted(releases)}")
for name in sorted(set(corpora) - set(expected_shard_counts)):
    problems.append(f"a report is of the {name} corpus, which the run does not name")
for name, expected_shard_count in expected_shard_counts.items():
    corpus = corpora.get(name, Corpus())
    if len(corpus.ranges) != expected_shard_count:
        problems.append(f"expected {expected_shard_count} shard reports of the {name} corpus, found {len(corpus.ranges)}")
    next_seed = 0
    for first, end, path in sorted(corpus.ranges):
        if first != next_seed:
            problems.append(f"the shards do not cover the {name} corpus once: {path} starts at {first}, expected {next_seed}")
        next_seed = max(next_seed, end)
    if corpus.ranges and next_seed != CORPUS_SEED_COUNTS[name]:
        problems.append(f"the {name} corpus's shards end at seed {next_seed}, not {CORPUS_SEED_COUNTS[name]}")
    if corpus.compared_count < COMPARED_GRAPH_FLOORS[name]:
        problems.append(f"{corpus.compared_count} graphs of the {name} corpus compared by value, below the floor of {COMPARED_GRAPH_FLOORS[name]}")
problems += findings

release = ", ".join(sorted(releases)) or "unknown"
print(f"## Release acceptance against SafeDI {release}")
print()
descriptions = {
    "A": "older release rejects",
    "B": "values agree",
    "C": "this tree rejects",
    "D": "this tree's code does not compile",
    "E": "new generated warning",
    "F": "values differ",
    "X": "values not compared",
}
names = list(expected_shard_counts)
print("| Class | " + " | ".join(names) + " |")
print("|---|" + "---|" * len(names))
for key, description in descriptions.items():
    print(f"| {key}: {description} | " + " | ".join(str(corpora.get(name, Corpus()).class_counts.get(key, 0)) for name in names) + " |")
print()
for name in names:
    corpus = corpora.get(name, Corpus())
    print(f"### The {name} corpus")
    print()
    print("Older release's rejections: " + ", ".join(f"{key} {value}" for key, value in sorted(corpus.rejection_counts.items())))
    print()
    print("Annotations: " + ", ".join(f"{key} {value}" for key, value in sorted(corpus.annotation_counts.items())))
    print()
    print(f"Compared by value: {corpus.compared_count} graphs (floor {COMPARED_GRAPH_FLOORS[name]}, seed-set sum {corpus.compared_sum}), "
          + ", ".join(f"{value} {key} probes" for key, value in sorted(corpus.probe_counts.items()))
          + "; probes skipped: " + ", ".join(f"{key} {value}" for key, value in sorted(corpus.skip_counts.items())))
    print()
    if corpus.wall_seconds:
        print(f"Shard wall seconds: {', '.join(str(seconds) for seconds in corpus.wall_seconds)}")
        print()
    if corpus.listed:
        print("Listed seeds:")
        print()
        for line in corpus.listed:
            print(f"- `{line}`")
        print()
if problems:
    print("**Problems:**")
    print()
    for problem in problems:
        print(f"- `{problem}`")
    sys.exit(1)
print("No unlisted break.")
