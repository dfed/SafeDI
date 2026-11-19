#!/bin/bash
# Scripts/byte-identical-gate.sh [BASE [HEAD]]
# The first half of the gate for a change that must leave SafeDI's output byte for byte the same (a rewrite of
# the generator's internals): fails when the change deletes or modifies any line under Tests/. Every expected
# output and every fuzzer pin is a line of a test file, so a changed expectation or pin shows as a deleted line;
# a change that only adds tests, or moves a file unchanged, passes. An edit to test code that is not an
# expectation (a helper, a comment) fails too: the script cannot tell them apart, so a reviewer rules on each. BASE defaults to origin/main, HEAD to HEAD;
# the comparison is from their merge base, so commits main gained since do not count.
#
# It reads commits, never the working tree, and runs no test. The gate's other halves are runs, which it names
# when it passes: the whole suite, the fuzzer's corpus pins, and the report of changed generator lines that no
# fuzzer corpus graph executed (`.claude/rules/fuzzer-corpora.md`, "Coverage of a change").
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
base=${1:-origin/main} head=${2:-HEAD}
for commit in "$base" "$head"; do
	git rev-parse --verify --quiet "$commit^{commit}" >/dev/null || { echo "byte-identical-gate: not a commit: $commit" >&2; exit 2; }
done
fork=$(git merge-base "$base" "$head") || { echo "byte-identical-gate: $base and $head share no history" >&2; exit 2; }
# --numstat prints "added<TAB>deleted<TAB>path"; -M follows a file moved with its content; -z keeps odd paths whole.
failed=0 changed=0
while IFS=$'\t' read -r added deleted path; do
	[ -n "$path" ] || continue
	changed=$((changed + 1))
	if [ "$deleted" = "-" ]; then
		echo "changed (binary): $path"; failed=1
	elif [ "$deleted" != "0" ]; then
		echo "changed: $path ($deleted line(s) deleted or modified, $added added)"; failed=1
	fi
done < <(git diff --numstat -M "$fork" "$head" -- Tests)
if [ "$failed" -ne 0 ]; then
	echo "byte-identical-gate: FAILED. A line under Tests/ changed between $(git rev-parse --short "$fork") and $(git rev-parse --short "$head")."
	echo "See each with: git diff -M $(git rev-parse --short "$fork") $(git rev-parse --short "$head") -- <path>"
	exit 1
fi
echo "byte-identical-gate: passed. $changed file(s) under Tests/ differ between $(git rev-parse --short "$fork") and $(git rev-parse --short "$head"), by added lines only."
echo "Still to run for the gate: the whole suite; the fuzzer corpus pins and the changed-line report of the pre-review skill."
