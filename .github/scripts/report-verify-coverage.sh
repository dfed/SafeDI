#!/bin/bash
# usage: report-verify-coverage.sh TEST_BUNDLE GROUP_PROFILES BASE OUTPUT EXPECTED_GROUPS
#
# Lists the lines under Sources/ and Plugins/ changed from BASE to the checkout's HEAD that no test of a Verify run
# executed on Linux (Scripts/changed-line-coverage.py), and appends the list to the job summary, so that a change's
# coverage is known from the Verify run that tests it, long before "Check Line Coverage on Linux" reads a pull
# request's two full test jobs. Run it from the checkout the test bundle was built from. The lines are those HEAD
# changes since its merge base with BASE. GROUP_PROFILES holds one folder per group of "Verify Tests on Linux", as
# the groups upload them (`verify-profile-<group>`, holding `<group>.profdata` when the group's tests wrote a profile
# and `outcome.txt`), and EXPECTED_GROUPS names every group of that job's matrix, space-separated. A group that
# uploaded no profile (one that timed out or crashed, or whose runner was lost) is named in the report, since a line
# only its tests execute is listed; so is a group whose tests failed, whose profile is still counted. A folder no
# expected group names fails the script, so the list keeps in step with the matrix. OUTPUT receives the report and
# what it was made from (coverage.lcov, changed-lines.txt, head.txt, missing-groups.txt, failed-groups.txt).
#
# The report is advisory and exits non-zero only when it cannot make one. It reads Linux alone, so it lists a line
# only macOS executes, which "Check Line Coverage on Linux" counts as executed; and it reads changed lines alone, so
# it does not see an unchanged line whose only test a change removed. That check stays the gate for both.
set -euo pipefail

bundle=$1
group_profiles=$2
base=$3
output=$4
read -r -a expected <<< "$5"
if [ ${#expected[@]} -eq 0 ]; then
  echo "::error::No expected groups were named."
  exit 1
fi
tools=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$output"

profiles=()
missing=()
failed=()
for group in "${expected[@]}"; do
  folder="$group_profiles/verify-profile-$group"
  if [ -f "$folder/$group.profdata" ]; then
    profiles+=("$folder/$group.profdata")
  else
    missing+=("$group")
  fi
  if [ -f "$folder/outcome.txt" ] && [ "$(cat "$folder/outcome.txt")" != success ]; then
    failed+=("$group")
  fi
done
for directory in "$group_profiles"/*/; do
  [ -d "$directory" ] || continue
  group=$(basename "$directory")
  group=${group#verify-profile-}
  if [[ " ${expected[*]} " != *" $group "* ]]; then
    echo "::error::Group $group uploaded a profile but is not among the expected groups (${expected[*]}); keep the list in step with the matrix."
    exit 1
  fi
done
if [ ${#profiles[@]} -eq 0 ]; then
  echo "::error::No group of tests uploaded a coverage profile to $group_profiles."
  exit 1
fi
printf '%s\n' "${missing[@]}" > "$output/missing-groups.txt"
printf '%s\n' "${failed[@]}" > "$output/failed-groups.txt"
git rev-parse HEAD > "$output/head.txt"

# SafeDI's own sources: the dependencies' (under .build) and the tests' are never in the report.
ignored='(\.build|Tests)/'
llvm-profdata merge -sparse "${profiles[@]}" -o "$output/verify.profdata"
llvm-cov export -format=lcov -ignore-filename-regex="$ignored" "$bundle" -instr-profile "$output/verify.profdata" > "$output/coverage.lcov"

merge_base=$(git merge-base "$base" HEAD)
status=0
git diff -U0 --no-color "$merge_base" -- 'Sources/*.swift' 'Plugins/*.swift' \
  | python3 -I "$tools/Scripts/changed-line-coverage.py" "$output/coverage.lcov" > "$output/changed-lines.txt" || status=$?
# changed-line-coverage.py exits 1 when it lists a line; any other failure leaves no report to give.
if [ "$status" -ne 0 ] && [ "$status" -ne 1 ]; then
  cat "$output/changed-lines.txt"
  echo "::error::Scripts/changed-line-coverage.py could not read the coverage or the changes (status $status)."
  exit 1
fi

{
  echo "## Changed lines no Verify test executed on Linux"
  echo
  echo "Lines under \`Sources/\` and \`Plugins/\` that $(cut -c1-9 "$output/head.txt") changes since $(echo "$merge_base" | cut -c1-9), from the profiles of ${#profiles[@]} of ${#expected[@]} groups of tests. Linux alone: a line only macOS executes is listed here and passes \"Check Line Coverage on Linux\"."
  if [ ${#missing[@]} -gt 0 ]; then
    echo
    echo "**No profile from: ${missing[*]}.** A line only those tests execute is listed below."
  fi
  if [ ${#failed[@]} -gt 0 ]; then
    echo
    echo "**Tests failed in: ${failed[*]}.** Their profiles are counted; a test that stopped early executed less than it will once it passes."
  fi
  echo
  echo '```'
  # The whole list is in changed-lines.txt; a summary this long is one of a change no test reaches yet.
  if [ "$(wc -l < "$output/changed-lines.txt")" -gt 300 ]; then
    head -n 299 "$output/changed-lines.txt"
    echo "…"
    tail -n 1 "$output/changed-lines.txt"
  else
    cat "$output/changed-lines.txt"
  fi
  echo '```'
} > "$output/report.md"
cat "$output/report.md"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$output/report.md" >> "$GITHUB_STEP_SUMMARY"
fi
if [ "$status" -eq 1 ]; then
  echo "::warning::$(tail -1 "$output/changed-lines.txt")"
fi
