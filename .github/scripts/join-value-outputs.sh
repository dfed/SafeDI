#!/bin/bash
# usage: join-value-outputs.sh SOURCE_DIRECTORY CACHE_DIRECTORY
#        join-value-outputs.sh --self-test DIRECTORY
#
# Copies into CACHE_DIRECTORY/value-outputs every file under a `value-outputs`
# directory anywhere in SOURCE_DIRECTORY, which holds what each part or group
# of a split test job uploaded. An output is named by its program's key
# (DifferentialValueOutputMemo.swift), so two groups that used one output
# hold the same file under the same name, and it is kept once.
#
# `cp` refuses to copy two sources of one name to one directory in one call
# ("will not overwrite just-created"), which failed the join of every run in
# which two groups used one output.
#
# Two files of one name that differ are a program that printed two outputs
# for one key. Neither is kept, so that no later run trusts either, and a
# warning names the output; the run that needs it runs its program again.
#
# Prints how many outputs it kept. `--self-test DIRECTORY` checks it against
# fixtures it writes under DIRECTORY, which it makes and removes; "Check Line
# Coverage on Linux" runs it.
set -euo pipefail

join() {
	local source=$1
	local destination=$2/value-outputs
	local disagreeing
	disagreeing=$(mktemp)
	mkdir -p "$destination"
	while IFS= read -r file; do
		local name=${file##*/}
		if grep -qxF -- "$name" "$disagreeing"; then
			continue
		elif [ ! -e "$destination/$name" ]; then
			cp "$file" "$destination/$name"
		elif ! cmp -s "$file" "$destination/$name"; then
			rm "$destination/$name"
			echo "$name" >> "$disagreeing"
			echo "::warning::Two groups hold different value comparison outputs named $name; neither is kept."
		fi
	done < <(find "$source" -path '*/value-outputs/*' -type f | LC_ALL=C sort)
	rm -f "$disagreeing"
	echo "Value comparison outputs kept: $(find "$destination" -type f | wc -l | tr -d ' ')."
}

self_test() {
	local directory=$1
	rm -rf "$directory"
	mkdir -p "$directory/source/a/value-outputs" "$directory/source/b/value-outputs" "$directory/source/c/nested/value-outputs"
	echo one > "$directory/source/a/value-outputs/only-a.txt"
	echo same > "$directory/source/a/value-outputs/shared.txt"
	echo same > "$directory/source/b/value-outputs/shared.txt"
	echo same > "$directory/source/c/nested/value-outputs/shared.txt"
	echo first > "$directory/source/a/value-outputs/differs.txt"
	echo second > "$directory/source/b/value-outputs/differs.txt"
	echo first > "$directory/source/c/nested/value-outputs/differs.txt"
	echo other > "$directory/source/a/not-an-output.txt"
	local output
	output=$(join "$directory/source" "$directory/cache")
	local kept
	kept=$(cd "$directory/cache/value-outputs" && find . -type f | LC_ALL=C sort | tr '\n' ' ')
	local failed=0
	if [ "$kept" != "./only-a.txt ./shared.txt " ]; then
		echo "self-test failed: kept $kept"
		failed=1
	fi
	if [ "$(cat "$directory/cache/value-outputs/shared.txt")" != same ]; then
		echo "self-test failed: the shared output's content changed"
		failed=1
	fi
	if [ "$(grep -c '::warning::.*differs.txt' <<< "$output")" != 1 ] || ! grep -q 'kept: 2\.' <<< "$output"; then
		echo "self-test failed: printed $output"
		failed=1
	fi
	# A second join into the same cache, as a job that restored a cache makes.
	join "$directory/source" "$directory/cache" > /dev/null
	if [ -e "$directory/cache/value-outputs/differs.txt" ]; then
		echo "self-test failed: a second join kept an output two groups disagree on"
		failed=1
	fi
	mkdir "$directory/empty"
	if [ "$(join "$directory/empty" "$directory/empty-cache")" != "Value comparison outputs kept: 0." ]; then
		echo "self-test failed: a source with no outputs"
		failed=1
	fi
	rm -rf "$directory"
	if [ "$failed" = 0 ]; then
		echo "self-test passed"
	else
		exit 1
	fi
}

if [ "${1:-}" = --self-test ] && [ $# = 2 ]; then
	self_test "$2"
elif [ $# = 2 ]; then
	join "$1" "$2"
else
	sed -n '2,3p' "$0" >&2
	exit 2
fi
