#!/bin/zsh
# Scripts/fuzzer-coverage-report.sh RUN [BASE]   (default BASE: the merge base with origin/main)
# Prints the generator lines changed since BASE that no fuzzer corpus graph executed, from the coverage a run uploaded
# (the `fuzzer-coverage` artifact of ci.yml's "Report Changed Lines No Fuzzer Graph Executed on Linux" or of
# graph-fuzzer.yml's coverage mode), without running anything. RUN is the run's ID or URL. Check out the commit the
# coverage was built from first (the artifact's head.txt, which the run's report names): line numbers are that
# commit's. The download goes under the user's caches directory, never $TMPDIR, and is removed afterwards.
set -euo pipefail
run=${1:?usage: Scripts/fuzzer-coverage-report.sh RUN [BASE]}
run=${run##*/runs/}; run=${run%%/*}
root=$(git rev-parse --show-toplevel); cd "$root"
base=${2:-$(git merge-base origin/main HEAD)}
if [[ $(uname) == Darwin ]]; then caches=$HOME/Library/Caches; else caches=${XDG_CACHE_HOME:-$HOME/.cache}; fi
mkdir -p "$caches/SafeDIFuzzerCoverage"
directory=$(mktemp -d "$caches/SafeDIFuzzerCoverage/run-$run.XXXXXX")
trap 'rm -rf "$directory"' EXIT
gh run download "$run" --name fuzzer-coverage --dir "$directory"
head=$(<"$directory/head.txt")
# The lines head changes since its merge base with BASE, as the run's report lists them.
base=$(git merge-base "$(git rev-parse "$base^{commit}")" "$head")
if [[ $(git rev-parse HEAD) != "$head" ]]; then
	print -u2 "warning: HEAD is not $head, which the coverage was built from; line numbers may not match."
fi
# The exports name the CI checkout's absolute paths; map them onto this checkout.
for name in corpus.lcov corpus-functions.json suite.lcov; do
	if [[ -f "$directory/$name" ]]; then
		sed "s#/__w/SafeDI/SafeDI/#$root/#g" "$directory/$name" >"$directory/local-$name"
	fi
done
arguments=(--corpus "$directory/local-corpus.lcov" --functions "$directory/local-corpus-functions.json" --compared "$base..$head")
if [[ -f "$directory/local-suite.lcov" ]]; then
	arguments+=(--suite "$directory/local-suite.lcov")
fi
for shard in ${(f)"$(<"$directory/missing-shards.txt")"}; do
	arguments+=(--missing-shard "$shard")
done
git diff -U0 --no-color "$base" "$head" -- 'Sources/SafeDICore/*.swift' 'Sources/SafeDIToolLibrary/*.swift' \
	| python3 Scripts/fuzzer-changed-line-coverage.py "${arguments[@]}"
