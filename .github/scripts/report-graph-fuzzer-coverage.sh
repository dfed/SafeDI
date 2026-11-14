#!/bin/bash
# usage: report-graph-fuzzer-coverage.sh TEST_BUNDLE SHARD_REPORTS UNIT_SUITE_PROFILE BASE OUTPUT EXPECTED_SHARDS
#
# Lists the generator lines changed from BASE to the checkout's HEAD that no graph of the fuzzer's corpora executed
# (Scripts/fuzzer-changed-line-coverage.py), and appends the list to the job summary. Run it from the checkout the
# test bundle was built from. The lines are those HEAD changes since its merge base with BASE, so a BASE that is not
# an ancestor of HEAD lists none of BASE's own changes. SHARD_REPORTS holds one folder per fuzzer shard, as the shards
# upload them (`graph-fuzzer-report-<shard>`), and EXPECTED_SHARDS names every shard of the workflow's matrix,
# space-separated, as `<corpus>-<starting seed>`. A shard that uploaded no folder (one that timed out, or whose runner
# was lost) or a folder without `coverage.profdata` (one whose fuzzer crashed) is named in the report, since a line
# only it would have executed is listed; a folder no expected shard names fails the script, so the list keeps in step
# with the matrix. UNIT_SUITE_PROFILE, the unit suite's merged profile, may be absent; the lines are then not split by
# whether a unit test reaches them. OUTPUT receives the report and what it was made from (corpus.lcov,
# corpus-functions.json, suite.lcov, head.txt, missing-shards.txt), which Scripts/fuzzer-coverage-report.sh reads to
# report against another base. The report is advisory: this exits non-zero only when it cannot make one.
set -euo pipefail

bundle=$1
shard_reports=$2
unit_suite_profile=$3
base=$4
output=$5
read -r -a expected <<< "$6"
if [ ${#expected[@]} -eq 0 ]; then
  echo "::error::No expected shards were named."
  exit 1
fi
tools=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$output"

profiles=()
missing=()
for shard in "${expected[@]}"; do
  if [ -f "$shard_reports/graph-fuzzer-report-$shard/coverage.profdata" ]; then
    profiles+=("$shard_reports/graph-fuzzer-report-$shard/coverage.profdata")
  else
    missing+=("$shard")
  fi
done
for directory in "$shard_reports"/*/; do
  [ -d "$directory" ] || continue
  shard=$(basename "$directory")
  shard=${shard#graph-fuzzer-report-}
  if [[ " ${expected[*]} " != *" $shard "* ]]; then
    echo "::error::Shard $shard uploaded a report but is not among the expected shards (${expected[*]}); keep the list in step with the matrix."
    exit 1
  fi
done
if [ ${#profiles[@]} -eq 0 ]; then
  echo "::error::No fuzzer shard uploaded a coverage profile to $shard_reports."
  exit 1
fi

# The generator's own files: the dependencies' (under .build) and the tests' are never in the report.
ignored='(\.build|Tests)/'
llvm-profdata merge -sparse "${profiles[@]}" -o "$output/corpus.profdata"
llvm-cov export -format=lcov -ignore-filename-regex="$ignored" "$bundle" -instr-profile "$output/corpus.profdata" > "$output/corpus.lcov"
llvm-cov export -format=text -skip-expansions -ignore-filename-regex="$ignored" "$bundle" -instr-profile "$output/corpus.profdata" > "$output/corpus-functions.json"
arguments=(--corpus "$output/corpus.lcov" --functions "$output/corpus-functions.json")
if [ -f "$unit_suite_profile" ]; then
  llvm-cov export -format=lcov -ignore-filename-regex="$ignored" "$bundle" -instr-profile "$unit_suite_profile" > "$output/suite.lcov"
  arguments+=(--suite "$output/suite.lcov")
fi
# graph-fuzzer.yml's unit-suite job writes its outcome beside the profile; ci.yml's report runs only after the suite
# passed.
outcome_file=$(dirname "$unit_suite_profile")/outcome.txt
if [ -f "$outcome_file" ] && [ "$(cat "$outcome_file")" != success ]; then
  arguments+=(--suite-failed)
fi
: > "$output/missing-shards.txt"
for shard in ${missing[@]+"${missing[@]}"}; do
  arguments+=(--missing-shard "$shard")
  echo "$shard" >> "$output/missing-shards.txt"
done

head=$(git rev-parse HEAD)
base=$(git merge-base "$(git rev-parse "$base^{commit}")" "$head")
echo "$head" > "$output/head.txt"
arguments+=(--compared "$base..$head")
git diff -U0 --no-color "$base" "$head" -- 'Sources/SafeDICore/*.swift' 'Sources/SafeDIToolLibrary/*.swift' \
  | python3 "$tools/Scripts/fuzzer-changed-line-coverage.py" "${arguments[@]}" > "$output/report.txt"
cat "$output/report.txt"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Changed generator lines no fuzzer graph executed"
    echo
    echo '```'
    cat "$output/report.txt"
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi
