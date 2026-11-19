#!/bin/bash
# usage: keep-value-outputs-used-in-run.sh CACHE_DIRECTORY RUN
#
# Deletes from CACHE_DIRECTORY/value-outputs every output of a value comparison
# program that the test processes of run RUN neither read nor wrote, as
# CACHE_DIRECTORY/value-outputs-used-in-run-RUN.txt lists them
# (DifferentialValueOutputMemo.swift), and deletes the whole directory when the
# run used none. A job calls it before it saves CACHE_DIRECTORY as its branch's
# cache.
#
# A job adds to the directory the outputs that other runs of its identity
# uploaded (.github/actions/restore-shared-compile-checks), so without this
# each run's cache would hold every output any run it read had printed, and
# grow with each. An output a run did not use is one its tests do not need, and
# a later run that needs it again reads it from the run that uploaded it, while
# that run is among the newest of its identity, or compiles and runs its
# program. A run that ran only some tests, such as a Verify run with a filter,
# keeps only theirs.
#
# Prints how many outputs it kept. Runs under bash 3.2, which macOS runners
# ship, and in the test jobs' container.
set -euo pipefail

if [ "$#" -ne 2 ]; then
	echo "usage: $0 CACHE_DIRECTORY RUN" >&2
	exit 2
fi
directory=$1
run=$2
outputs="$directory/value-outputs"
used="$directory/value-outputs-used-in-run-$run.txt"

if [ ! -d "$outputs" ]; then
	echo "No value comparison outputs to keep."
	exit 0
fi
before=$(find "$outputs" -type f | wc -l | tr -d ' ')
if [ ! -s "$used" ]; then
	rm -rf "$outputs"
	echo "Value comparison outputs: this run used none of the $before here, so the cache keeps none."
	exit 0
fi
LC_ALL=C sort -u "$used" > "$directory/value-outputs-to-keep.txt"
# Every file that is not an output this run used, whatever its name, is deleted.
find "$outputs" -type f | LC_ALL=C sort > "$directory/value-outputs-here.txt"
sed "s|^|$outputs/|; s|\$|.txt|" "$directory/value-outputs-to-keep.txt" | LC_ALL=C sort > "$directory/value-outputs-to-keep-paths.txt"
LC_ALL=C comm -23 "$directory/value-outputs-here.txt" "$directory/value-outputs-to-keep-paths.txt" | tr '\n' '\0' | xargs -0 rm -f
rm -f "$directory/value-outputs-to-keep.txt" "$directory/value-outputs-here.txt" "$directory/value-outputs-to-keep-paths.txt"
after=$(find "$outputs" -type f | wc -l | tr -d ' ')
echo "Value comparison outputs: kept the $after this run used of the $before here."
