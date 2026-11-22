#!/usr/bin/env bash
# usage: report-graph-fuzzer-pins.sh REPORTS
#
# Prints the analysis of a run's graph fuzzer pins where a session that cannot
# download the run's artifacts can still read it: the job's log and its
# summary. REPORTS is the directory the shard reports were downloaded into;
# the working directory is the checkout of the commit the run built.
#
# It runs .github/scripts/analyze-graph-fuzzer-pins.py over them and prints
# its report.md, then its pins.json as the lines
# `.claude/skills/apply-fuzzer-pins/apply-fuzzer-pins.py --print-for-log`
# writes, last, so that the end of the log is the block that script reads
# back. The job summary gets the same two, the report cut to fit a summary's
# size limit when it is longer.
#
# A pull request's run builds the merge of its head into its base, so the
# values are the head's only when that base was an ancestor of the head. The
# merge commit's parents and that ancestry are read from GitHub (GH_TOKEN),
# and anything that cannot be read leaves the validity `unknown`, which
# apply-fuzzer-pins refuses.
#
# It reports and never judges: "Combine Shard Reports" is the check. It
# exits 0 whatever the analysis lists, and with a warning when the analysis
# could not run, so that a fault here never fails the job.
set -uo pipefail

reports=${1:?usage: report-graph-fuzzer-pins.sh REPORTS}
out=${RUNNER_TEMP:?}/graph-fuzzer-pins
scripts=$(dirname "$0")
apply=.claude/skills/apply-fuzzer-pins/apply-fuzzer-pins.py
# A job summary holds 1024 KiB for a step; the pins block is about 100 KiB.
report_bytes_for_summary=800000

export PINS_EVENT=${GITHUB_EVENT_NAME:-}
export PINS_HEAD_SHA=${GITHUB_SHA:-}
export PINS_BASE_REF= PINS_BASE_SHA= PINS_MERGE_SHA= PINS_VALID_FOR_HEAD=
export PINS_RUN_ID=${GITHUB_RUN_ID:-}
export PINS_RUN_URL=${GITHUB_SERVER_URL:-}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}
if [ "$PINS_EVENT" = pull_request ]; then
  PINS_HEAD_SHA=${PULL_REQUEST_HEAD_SHA:-}
  PINS_BASE_REF=${GITHUB_BASE_REF:-}
  PINS_MERGE_SHA=${GITHUB_SHA:-}
  PINS_VALID_FOR_HEAD=unknown
  parents=$(gh api "repos/$GITHUB_REPOSITORY/commits/$PINS_MERGE_SHA" --jq '[.parents[].sha] | join(" ")' 2>/dev/null) || parents=
  read -r first_parent second_parent other_parent <<<"$parents"
  if [ -n "${second_parent:-}" ] && [ -z "${other_parent:-}" ] && [ "$second_parent" = "$PINS_HEAD_SHA" ]; then
    PINS_BASE_SHA=$first_parent
    # `ahead` and `identical` say the base is an ancestor of the head.
    comparison=$(gh api "repos/$GITHUB_REPOSITORY/compare/$PINS_BASE_SHA...$PINS_HEAD_SHA" --jq .status 2>/dev/null) || comparison=
    case "$comparison" in
      ahead | identical) PINS_VALID_FOR_HEAD=true ;;
      behind | diverged) PINS_VALID_FOR_HEAD=false ;;
      *) ;;
    esac
  fi
fi

rm -rf "$out"
python3 -I "$scripts/analyze-graph-fuzzer-pins.py" --in-run "$out" "$reports" > "$out.log" 2>&1
status=$?
if [ ! -f "$out/report.md" ] || [ ! -f "$out/pins.json" ]; then
  cat "$out.log"
  echo "::warning::The fuzzer pins analysis wrote no report (status $status), so this run's pins are not printed."
  exit 0
fi
block=$(python3 -I "$apply" --print-for-log "$out/pins.json") || {
  echo "::warning::The fuzzer pins analysis wrote a pins.json that could not be printed."
  exit 0
}

echo "The analysis of this run's fuzzer pins (status $status) follows, then its pins.json for $apply."
cat "$out/report.md"
echo "$block"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo
    if [ "$(wc -c < "$out/report.md")" -gt "$report_bytes_for_summary" ]; then
      # Whole lines, so that the cut never falls inside a character.
      awk -v limit="$report_bytes_for_summary" '{ used += length($0) + 1; if (used > limit) exit; print }' "$out/report.md"
      printf '\n\n_The report is cut here to fit the summary; the job log has all of it._\n'
    else
      cat "$out/report.md"
    fi
    printf '\n<details><summary>pins.json, as %s reads it from a saved copy of this text or of the job log</summary>\n\n```\n%s\n```\n\n</details>\n' "$apply" "$block"
  } >> "$GITHUB_STEP_SUMMARY"
fi
exit 0
