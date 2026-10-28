#!/bin/bash
# usage: summarize-graph-fuzzer-report.sh REPORT SUMMARY STARTING_SEED ITERATIONS
#
# Writes a Markdown summary of the graph fuzzer's long-run report to SUMMARY
# and appends it to the job summary. Exits non-zero when a graph failed, a
# known issue went stale, the run reported a problem with itself, the long run
# checked no graphs (it was skipped, renamed, or never built), or the process
# crashed, so the fuzzer cannot go quiet without the job turning red.
set -euo pipefail

report=$1
summary=$2
starting_seed=$3
iterations=$4

reproduce() {
  echo "SAFEDI_GRAPH_FUZZER_STARTING_SEED=$1 SAFEDI_GRAPH_FUZZER_ITERATIONS=1 swift test --traits sourceBuild --filter SafeDIToolGraphFuzzerTests/longRun"
}

touch "$report"
graph_count=$(grep -c '^seed ' "$report" || true)
graph_count=${graph_count:-0}
has_problems=false
if grep -q '^problem ' "$report"; then
  has_problems=true
fi
{
  echo "### Graph fuzzer"
  echo
  echo "Started $graph_count graphs ($iterations requested) from seed $starting_seed on $(git -c safe.directory="$PWD" rev-parse HEAD 2>/dev/null || echo 'an unknown commit')."
  echo
  # Under `pipefail`, a grep that finds nothing must not end the script.
  { grep '^problem ' "$report" || true; } | sed 's/^problem /- **Problem:** /'
  if [ "$graph_count" -eq 0 ] && [ "$has_problems" = false ]; then
    echo "**It ran zero graphs.** If the build succeeded, check that \`longRun_findsNoUnknownFailures_whenEnabledByEnvironment\` still exists and reads \`SAFEDI_GRAPH_FUZZER_ITERATIONS\`."
  elif ! grep -q '^completed ' "$report" && [ "$has_problems" = false ]; then
    # Batches run concurrently, so the crash happened in one of the seeds that started and did not finish.
    suspects=$(comm -23 <({ grep '^seed ' "$report" || true; } | cut -d ' ' -f 2 | sort -u) <({ grep '^finished ' "$report" || true; } | cut -d ' ' -f 2 | sort -u) | sort -n | head -n 40 | tr '\n' ' ')
    first_suspect=${suspects%% *}
    echo "**The test process stopped while SafeDITool ran one of seeds ${suspects% }**, which suggests the tool crashed. Reproduce one with \`$(reproduce "${first_suspect:-0}")\`"
  elif grep -q '^completed ' "$report"; then
    echo "Completed $(grep '^completed ' "$report" | sed 's/^completed //')."
  fi
  echo
  { grep -E '^(failure|stale) ' "$report" || true; } | while read -r kind seed reason; do
    if [ "$kind" = failure ]; then
      echo "- **Seed $seed**: $reason. Reproduce with \`$(reproduce "$seed")\`"
    else
      echo "- **Seed $seed** is a known issue ($reason) that no longer fails. Remove it from \`knownIssues\`. Reproduce with \`$(reproduce "$seed")\`"
    fi
  done
  echo
  echo "The test log holds each failing graph's fixture and compiler output. Every failure becomes a hand-written regression test before its fix; see \"Graph fuzzer\" in CLAUDE.md."
} > "$summary"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$summary" >> "$GITHUB_STEP_SUMMARY"
fi
if [ "$graph_count" -eq 0 ] || ! grep -q '^completed ' "$report" || grep -qE '^(failure|stale|problem) ' "$report"; then
  exit 1
fi
