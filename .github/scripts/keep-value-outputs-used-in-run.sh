#!/bin/bash
# usage: keep-value-outputs-used-in-run.sh CACHE_DIRECTORY RUN TEST_OUTCOME
#        keep-value-outputs-used-in-run.sh --self-test DIRECTORY
#
# Deletes from CACHE_DIRECTORY/value-outputs every output of a value comparison
# program that the test processes of run RUN neither read nor wrote, as
# CACHE_DIRECTORY/value-outputs-used-in-run-RUN.txt lists them
# (DifferentialValueOutputMemo.swift), unless one of the newest artifacts of
# the job's identity holds it, as
# CACHE_DIRECTORY/value-outputs-of-artifacts-read.txt lists them
# (.github/actions/restore-shared-compile-checks/restore-from-artifacts.js).
# It deletes the whole directory when it keeps nothing. A job calls it, with
# the outcome of its test step, before it saves CACHE_DIRECTORY as its
# branch's cache.
#
# A job adds to the directory the outputs that other runs of its identity
# uploaded, so without this each run's cache would hold every output any run
# it read had printed, and grow with each. An output a run did not use is one
# its tests do not need. One that the newest artifacts hold stays, since the
# cache also names those artifacts as read and the next run does not download
# them again; the rest leave with the artifact that held them, and a later run
# that needs one compiles and runs its program. A run that ran only some
# tests, such as a Verify run with a filter, keeps only theirs and those.
#
# Only a test step that ran to its end, passing or failing, says which outputs
# its tests use. A cancelled or skipped one (TEST_OUTCOME `cancelled` or
# `skipped`, as `steps.<id>.outcome` spells it) keeps every output, so that a
# push that supersedes a run does not leave the next one to compile what the
# cancelled run had not reached yet.
#
# Prints how many outputs it kept. Runs under bash 3.2, which macOS runners
# ship, and in the test jobs' container. `--self-test DIRECTORY` checks it
# against fixtures it writes under DIRECTORY, which it makes and removes;
# "Check Line Coverage on Linux" runs it.
set -euo pipefail

keep() {
	local directory=$1
	local run=$2
	local outcome=$3
	local outputs="$directory/value-outputs"
	local used="$directory/value-outputs-used-in-run-$run.txt"
	local held="$directory/value-outputs-of-artifacts-read.txt"
	if [ ! -d "$outputs" ]; then
		echo "No value comparison outputs to keep."
		return 0
	fi
	local before
	before=$(find "$outputs" -type f | wc -l | tr -d ' ')
	case "$outcome" in
	success | failure) ;;
	*)
		echo "Value comparison outputs: the tests did not run to their end (outcome ‘${outcome}’), so the cache keeps all $before here."
		return 0
		;;
	esac
	{
		if [ -f "$used" ]; then
			cat "$used"
		fi
		if [ -f "$held" ]; then
			cut -d ' ' -f 2 "$held"
		fi
	} | { grep -Ex '[0-9a-f]{64}' || true; } | LC_ALL=C sort -u > "$directory/value-outputs-to-keep.txt"
	if [ ! -s "$directory/value-outputs-to-keep.txt" ]; then
		rm -rf "$outputs" "$directory/value-outputs-to-keep.txt"
		echo "Value comparison outputs: this run used none of the $before here and the newest artifacts hold none, so the cache keeps none."
		return 0
	fi
	# Every file that is not an output to keep, whatever its name, is deleted.
	find "$outputs" -type f | LC_ALL=C sort > "$directory/value-outputs-here.txt"
	sed "s|^|$outputs/|; s|\$|.txt|" "$directory/value-outputs-to-keep.txt" | LC_ALL=C sort > "$directory/value-outputs-to-keep-paths.txt"
	LC_ALL=C comm -23 "$directory/value-outputs-here.txt" "$directory/value-outputs-to-keep-paths.txt" | tr '\n' '\0' | xargs -0 rm -f
	rm -f "$directory/value-outputs-to-keep.txt" "$directory/value-outputs-here.txt" "$directory/value-outputs-to-keep-paths.txt"
	local after
	after=$(find "$outputs" -type f | wc -l | tr -d ' ')
	echo "Value comparison outputs: kept the $after of the $before here that this run used or the newest artifacts hold."
}

self_test() {
	local scratch=$1
	local cases=0
	local key1 key2 key3 key4
	key1=$(printf '1%.0s' $(seq 64))
	key2=$(printf '2%.0s' $(seq 64))
	key3=$(printf '3%.0s' $(seq 64))
	key4=$(printf '4%.0s' $(seq 64))
	rm -rf "$scratch"
	# Writes a cache directory holding the outputs of keys 1 to 4 and a file
	# that is not an output, in which this run used key 1 and the newest
	# artifacts hold key 2, runs `keep` with OUTCOME, and checks that the
	# outputs left are EXPECTED (names, space-separated, sorted).
	check() {
		local outcome=$1
		local expected=$2
		local used=${3-$key1}
		local held=${4-"7 $key2"}
		cases=$((cases + 1))
		local directory="$scratch/case-$cases"
		mkdir -p "$directory/value-outputs"
		for key in "$key1" "$key2" "$key3" "$key4"; do
			echo "output of $key" > "$directory/value-outputs/$key.txt"
		done
		echo 'not an output' > "$directory/value-outputs/stray"
		if [ -n "$used" ]; then
			# shellcheck disable=SC2086 # The keys are words to split, one a line.
			printf '%s\n' $used > "$directory/value-outputs-used-in-run-5.txt"
		fi
		if [ -n "$held" ]; then
			printf '%s\n' "$held" > "$directory/value-outputs-of-artifacts-read.txt"
		fi
		keep "$directory" 5 "$outcome" > "$directory.log"
		local left=''
		if [ -d "$directory/value-outputs" ]; then
			left=$(find "$directory/value-outputs" -type f -exec basename {} \; | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
		fi
		if [ "$left" != "$expected" ]; then
			echo "keep-value-outputs-used-in-run.sh: case $cases (outcome $outcome) left ‘${left}’, expected ‘${expected}’." >&2
			exit 1
		fi
	}
	# macOS runners run this with bash 3.2, which reads a byte above ASCII just
	# after `$name` as part of the name: a message that quoted the outcome
	# with a curly apostrophe failed there with "unbound variable" and passed
	# on Linux. So no shell script or workflow under `.github` may write such a
	# byte after an unbraced name.
	local unbraced
	unbraced=$(LC_ALL=C grep -rnE --include='*.sh' --include='*.yml' "\\\$[A-Za-z_][A-Za-z_0-9]*[^ -~$(printf '\t')]" "$(dirname "$0")/.." || true)
	if [ -n "$unbraced" ]; then
		echo "keep-value-outputs-used-in-run.sh: a byte above ASCII follows an unbraced variable name, which bash 3.2 reads as part of the name; write \${name}:" >&2
		echo "$unbraced" >&2
		exit 1
	fi
	# Keeps what the run used and what the newest artifacts hold, after tests
	# that passed or failed.
	check success "$key1.txt $key2.txt"
	check failure "$key1.txt $key2.txt"
	# Keeps everything after tests that did not run to their end.
	check cancelled "$key1.txt $key2.txt $key3.txt $key4.txt stray"
	check skipped "$key1.txt $key2.txt $key3.txt $key4.txt stray"
	check '' "$key1.txt $key2.txt $key3.txt $key4.txt stray"
	# Keeps what the newest artifacts hold when the run used none.
	check success "$key2.txt" ''
	# Keeps what the run used when no artifact was read.
	check success "$key1.txt $key3.txt" "$key1 $key3" ''
	# Deletes the directory when it keeps nothing.
	check success '' '' ''
	rm -rf "$scratch"
	echo "keep-value-outputs-used-in-run.sh: $cases cases passed."
}

if [ "${1-}" = "--self-test" ] && [ "$#" -eq 2 ]; then
	self_test "$2"
	exit 0
fi
if [ "$#" -ne 3 ]; then
	echo "usage: $0 CACHE_DIRECTORY RUN TEST_OUTCOME" >&2
	echo "       $0 --self-test DIRECTORY" >&2
	exit 2
fi
keep "$1" "$2" "$3"
