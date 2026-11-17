#!/bin/bash
# Scripts/generator-line-count.sh [COMMIT…]
# Prints the generator's code lines at each commit (default: HEAD): the lines of the Swift files under
# Sources/SafeDICore/Generators that are neither blank nor only a `//` comment. A file's tracked content at the
# commit is counted, never the working tree, so the figure for a commit is the same on every machine.
# The 2.3.1 plan's baseline, 20,938 lines at a6d44aff, is this count; a release check compares a later commit with it.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
directory=Sources/SafeDICore/Generators
if [ $# -eq 0 ]; then set -- HEAD; fi
for commit in "$@"; do
	resolved=$(git rev-parse --verify --quiet "$commit^{commit}") || { echo "generator-line-count: not a commit: $commit" >&2; exit 2; }
	files=0 lines=0
	while IFS= read -r file; do
		count=$(git show "$resolved:$file" | awk '{ line = $0; sub(/^[ \t]+/, "", line); if (line != "" && line !~ /^\/\//) count++ } END { print count + 0 }')
		files=$((files + 1)); lines=$((lines + count))
	done < <(git ls-tree -r --name-only "$resolved" -- "$directory" | grep '\.swift$' || true)
	echo "$commit ${resolved:0:9}: $lines code lines in $files files under $directory"
done
