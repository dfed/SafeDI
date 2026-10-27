"""usage: combine-graph-fuzzer-reports.py SUMMARY REPORT...

Checks the graph fuzzer's whole-corpus pins across the reports of the shards
that ci.yml splits the corpus into. Each shard's long run ends its report with

    shard <starting seed> <count> <accepted count> <accepted seed-set sum>
    corpus <corpusSeedCount> <pinned accepted count> <pinned accepted seed-set sum>

The shards must cover the corpus 0..<corpusSeedCount exactly once, and the
accepted counts and seed-set sums (a wrapping sum of per-seed hashes, so parts
add up) must add up to the pins, and no shard may report a failure, a stale
known issue, or a problem. Writes a Markdown summary to SUMMARY and the
job summary, and exits non-zero when anything is missing or does not match.
"""

import os
import sys

summary_path = sys.argv[1]
# An unmatched shell glob arrives as the pattern itself, so keep only reports that exist.
report_paths = sorted(path for path in sys.argv[2:] if os.path.isfile(path))
problems = []
shards = []
corpora = set()
for path in report_paths:
    shard_lines = []
    completed = False
    with open(path) as report:
        for line in report:
            fields = line.split()
            if not fields:
                continue
            if fields[0] == "shard" and len(fields) == 5:
                shard_lines.append((int(fields[1]), int(fields[2]), int(fields[3]), int(fields[4], 16)))
            elif fields[0] == "corpus" and len(fields) == 4:
                corpora.add((int(fields[1]), int(fields[2]), int(fields[3], 16)))
            elif fields[0] == "completed":
                completed = True
            elif fields[0] in ("failure", "stale", "problem"):
                problems.append(f"{path}: {line.strip()}")
    if len(shard_lines) != 1 or not completed:
        problems.append(f"{path} has no complete shard result; that shard failed or did not finish.")
    shards += shard_lines

if not report_paths:
    problems.append("No shard reports were found. The shards fail, or are skipped when \"Build and Test on Linux\" fails.")
if len(corpora) > 1:
    problems.append(f"The shards disagree about the corpus and its pins: {sorted(corpora)}.")
if len(corpora) == 1 and not problems:
    seed_count, pinned_accepted_count, pinned_accepted_sum = corpora.pop()
    covered = []
    for starting_seed, count, _, _ in sorted(shards):
        covered.append((starting_seed, starting_seed + count))
    expected_start = 0
    for start, end in covered:
        if start != expected_start:
            problems.append(f"The shards do not cover the corpus 0..<{seed_count} exactly once: {covered}.")
            break
        expected_start = end
    else:
        if expected_start != seed_count:
            problems.append(f"The shards cover 0..<{expected_start}, not the corpus 0..<{seed_count}.")
    accepted_count = sum(shard[2] for shard in shards)
    accepted_sum = sum(shard[3] for shard in shards) % (1 << 64)
    if (accepted_count, accepted_sum) != (pinned_accepted_count, pinned_accepted_sum):
        problems.append(
            f"The tool accepted {accepted_count} of seeds 0..<{seed_count} (sum 0x{accepted_sum:X}), but "
            f"{pinned_accepted_count} are pinned (sum 0x{pinned_accepted_sum:X}). A tool change that rejects or "
            "accepts different graphs must update corpusAcceptedSeedCount and corpusAcceptedSeedsSum deliberately."
        )

with open(summary_path, "w") as summary:
    summary.write("### Graph fuzzer corpus\n\n")
    if problems:
        summary.writelines(f"- **Problem:** {problem}\n" for problem in problems)
    else:
        summary.write(f"{len(shards)} shards covered the whole corpus, and the accepted set matches its pins.\n")
step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
if step_summary:
    with open(summary_path) as summary, open(step_summary, "a") as job_summary:
        job_summary.write(summary.read())
sys.exit(1 if problems else 0)
