"""usage: combine-graph-fuzzer-reports.py SUMMARY REPORT...

Checks the graph fuzzer's whole-corpus pins across the reports of the shards
that ci.yml splits each corpus into. Each shard's long run ends its report with

    shard <starting seed> <count> <accepted count> <accepted seed-set sum> <corpus>
    corpus <seed count> <pinned accepted count> <pinned accepted seed-set sum> <corpus>
    inspected <graphs the value oracle inspected> <pinned count> <corpus>
    compared <graphs the value comparator compared> <corpus>
    spellings <corpus> <spellings to draw, comma-separated> <spellings drawn in accepted graphs>

where <corpus> names the corpus the shard fuzzed: `base`, or a generator
feature's name. For each corpus the shards must cover 0..<seed count exactly
once, and the accepted counts and seed-set sums (a wrapping sum of per-seed
hashes, so parts add up) must add up to the pins, the graphs the value oracle
inspected must add up to their pin, every spelling the corpus draws must be
drawn in some accepted graph of some shard, and no shard may report a failure,
a stale known issue, or a problem. Writes a Markdown summary to
SUMMARY and the job summary, and exits non-zero when anything is missing or
does not match.
"""

import os
import sys

summary_path = sys.argv[1]
# An unmatched shell glob arrives as the pattern itself, so keep only reports that exist.
report_paths = sorted(path for path in sys.argv[2:] if os.path.isfile(path))
problems = []
shards_by_corpus = {}
pins_by_corpus = {}
inspected_by_corpus = {}
inspected_pins_by_corpus = {}
compared_by_corpus = {}
required_spellings_by_corpus = {}
accepted_spellings_by_corpus = {}
# Every corpus the long run knows, from the `corpora` line each report carries: a corpus whose shards all left no
# report would otherwise go unchecked.
expected_corpora = set()
for path in report_paths:
    shard_lines = []
    completed = False
    with open(path) as report:
        for line in report:
            fields = line.split()
            if not fields:
                continue
            if fields[0] == "shard" and len(fields) == 6:
                shard_lines.append((fields[5], int(fields[1]), int(fields[2]), int(fields[3]), int(fields[4], 16)))
            elif fields[0] == "corpus" and len(fields) == 5:
                pins_by_corpus.setdefault(fields[4], set()).add((int(fields[1]), int(fields[2]), int(fields[3], 16)))
            elif fields[0] == "corpora":
                expected_corpora.update(fields[1:])
            elif fields[0] == "inspected" and len(fields) == 4:
                inspected_by_corpus[fields[3]] = inspected_by_corpus.get(fields[3], 0) + int(fields[1])
                inspected_pins_by_corpus.setdefault(fields[3], set()).add(int(fields[2]))
            elif fields[0] == "compared" and len(fields) == 3:
                compared_by_corpus[fields[2]] = compared_by_corpus.get(fields[2], 0) + int(fields[1])
            elif fields[0] == "spellings" and len(fields) >= 2:
                # An empty list is an absent field, so a corpus that draws no spelling reports two fields.
                required_spellings_by_corpus.setdefault(fields[1], set()).update(filter(None, (fields[2] if len(fields) > 2 else "").split(",")))
                accepted_spellings_by_corpus.setdefault(fields[1], set()).update(filter(None, (fields[3] if len(fields) > 3 else "").split(",")))
            elif fields[0] == "completed":
                completed = True
            elif fields[0] in ("failure", "stale", "problem"):
                problems.append(f"{path}: {line.strip()}")
    if len(shard_lines) != 1 or not completed:
        problems.append(f"{path} has no complete shard result; that shard failed or did not finish.")
    for corpus, starting_seed, count, accepted_count, accepted_sum in shard_lines:
        shards_by_corpus.setdefault(corpus, []).append((starting_seed, count, accepted_count, accepted_sum))

if not report_paths:
    problems.append("No shard reports were found. The shards fail, or are skipped when \"Build and Test on Linux\" fails.")
if report_paths and not pins_by_corpus:
    problems.append("No report names its corpus and the corpus's pins, so nothing can be checked against them.")
for corpus in sorted(expected_corpora - set(pins_by_corpus)):
    problems.append(f"The {corpus} corpus has no report: its shards did not run, or their reports were not uploaded.")
for corpus, pins in sorted(pins_by_corpus.items()):
    if len(pins) > 1:
        problems.append(f"The shards of the {corpus} corpus disagree about its pins: {sorted(pins)}.")
if not problems:
    for corpus, pins in sorted(pins_by_corpus.items()):
        seed_count, pinned_accepted_count, pinned_accepted_sum = next(iter(pins))
        shards = shards_by_corpus.get(corpus, [])
        covered = []
        for starting_seed, count, _, _ in sorted(shards):
            covered.append((starting_seed, starting_seed + count))
        expected_start = 0
        for start, end in covered:
            if start != expected_start:
                problems.append(f"The shards do not cover the {corpus} corpus 0..<{seed_count} exactly once: {covered}.")
                break
            expected_start = end
        else:
            if expected_start != seed_count:
                problems.append(f"The shards cover 0..<{expected_start} of the {corpus} corpus, not 0..<{seed_count}.")
        inspected_pins = inspected_pins_by_corpus.get(corpus, set())
        if len(inspected_pins) > 1:
            problems.append(f"The shards of the {corpus} corpus disagree about how many graphs the value oracle inspects: {sorted(inspected_pins)}.")
        elif inspected_pins and inspected_by_corpus.get(corpus, 0) != next(iter(inspected_pins)):
            problems.append(
                f"The value oracle inspected {inspected_by_corpus.get(corpus, 0)} graphs of the {corpus} corpus, but "
                f"{next(iter(inspected_pins))} are pinned."
            )
        missing_spellings = required_spellings_by_corpus.get(corpus, set()) - accepted_spellings_by_corpus.get(corpus, set())
        if missing_spellings:
            problems.append(f"No accepted graph of the {corpus} corpus draws {', '.join(sorted(missing_spellings))}.")
        accepted_count = sum(shard[2] for shard in shards)
        accepted_sum = sum(shard[3] for shard in shards) % (1 << 64)
        if (accepted_count, accepted_sum) != (pinned_accepted_count, pinned_accepted_sum):
            problems.append(
                f"The tool accepted {accepted_count} of seeds 0..<{seed_count} of the {corpus} corpus (sum 0x{accepted_sum:X}), but "
                f"{pinned_accepted_count} are pinned (sum 0x{pinned_accepted_sum:X}). A tool change that rejects or "
                "accepts different graphs must update that corpus's accepted-seed pins deliberately."
            )

with open(summary_path, "w") as summary:
    summary.write("### Graph fuzzer corpus\n\n")
    if problems:
        summary.writelines(f"- **Problem:** {problem}\n" for problem in problems)
    else:
        for corpus, shards in sorted(shards_by_corpus.items()):
            summary.write(f"{len(shards)} shards covered the whole {corpus} corpus, and the accepted set matches its pins.\n")
            if inspected_by_corpus.get(corpus, 0) > 0:
                summary.write(
                    f"The value oracle inspected {inspected_by_corpus[corpus]} graphs of the {corpus} corpus and compared "
                    f"{compared_by_corpus.get(corpus, 0)} of them.\n"
                )
step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
if step_summary:
    with open(summary_path) as summary, open(step_summary, "a") as job_summary:
        job_summary.write(summary.read())
sys.exit(1 if problems else 0)
