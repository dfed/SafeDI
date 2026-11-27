#!/bin/bash
# local-mock-gate.sh COMMIT [LAST_SEED]
# The mock on/off gate on this machine, for a head of the mock kinds integration: builds SafeDITool at COMMIT
# (off) and at COMMIT with lay-out-mocks.patch applied (on), runs gate.sh's mock-heavy graphs through both for
# seeds 0...LAST_SEED (default 49999, both declaration orders), and then the base and public mock corpora's long
# runs over the patched commit, whose value oracles judge the laid-out mocks. Each step's output, and a summary,
# go to a folder in the user's caches directory, outside the checkout and the system temporary directory, so a
# fixture is never read as part of a project and nothing lands where macOS empties at startup. The two worktrees
# are removed when the script ends; the logs stay. Exit status 0 only when every step is clean.
set -u
if [ $# -lt 1 ]; then echo "usage: local-mock-gate.sh COMMIT [LAST_SEED]" >&2; exit 2; fi
here=$(cd "$(dirname "$0")" && pwd)
repository=$(git -C "$here" rev-parse --show-toplevel)
commit=$(git -C "$repository" rev-parse --verify "$1^{commit}") || { echo "no commit $1 here: fetch it first" >&2; exit 2; }
last=${2:-49999}
if [ "$(uname)" = Darwin ]; then cores=$(sysctl -n hw.ncpu); caches=~/Library/Caches; else cores=$(nproc); caches=${XDG_CACHE_HOME:-~/.cache}; fi
root=$caches/SafeDITests/mock-gate/${commit:0:12}
mkdir -p "$root/swifttmp"
export TMPDIR=$root/swifttmp
off=$root/off on=$root/on
cleanup() {
  git -C "$repository" worktree remove --force "$off" 2>/dev/null
  git -C "$repository" worktree remove --force "$on" 2>/dev/null
  rm -rf "$root/swifttmp" "$root/gate"
}
trap cleanup EXIT
status=0
git -C "$repository" worktree add --detach "$off" "$commit" >/dev/null || exit 1
git -C "$repository" worktree add --detach "$on" "$commit" >/dev/null || exit 1
git -C "$on" apply "$here/lay-out-mocks.patch" || { echo "lay-out-mocks.patch does not apply to $commit" >&2; exit 1; }
for side in off on; do
  (cd "$root/$side" && swift build -c release --product SafeDITool > "$root/build-$side.log" 2>&1) &
done
wait
for side in off on; do
  [ -x "$root/$side/.build/release/SafeDITool" ] || { echo "the $side tool did not build: $root/build-$side.log" >&2; exit 1; }
done
GATE_MODE=mocks "$here/gate.sh" "$on/.build/release/SafeDITool" "$off/.build/release/SafeDITool" 0 "$last" "$cores" "$root/gate" > "$root/gate.txt" 2>&1 || status=1
cat "$root"/gate/w*/log > "$root/gate-all.log" 2>/dev/null
grep -E " (DIFF|EXITDIFF|ERRDIFF) " "$root/gate-all.log" > "$root/gate-differing.log"
for corpus in base generateMockPublic; do
  features=""
  [ $corpus = base ] || features="--features $corpus"
  (cd "$on" && Scripts/fuzz-corpus.sh $features --iterations corpus --release) > "$root/corpus-$corpus.txt" 2>&1 || status=1
done
{
  echo "mock gate of $commit, layout on against off, $(date)"
  echo
  cat "$root/gate.txt"
  for corpus in base generateMockPublic; do
    echo
    echo "$corpus corpus with mocks laid out:"
    grep '↳ Graph fuzzer seed' "$root/corpus-$corpus.txt" | sed 's/^↳ Graph fuzzer seed \([0-9]*\): /\1 /' | awk '{ seed = $1; $1 = ""; seeds[$0] = seeds[$0] " " seed; count[$0]++ } END { for (k in count) printf "%4d%s:%s\n", count[k], k, seeds[k] }' | sort -rn | head -40
    tail -5 "$root/corpus-$corpus.txt"
  done
  echo
  [ $status = 0 ] && echo "CLEAN" || echo "NOT CLEAN"
} > "$root/summary.txt"
cat "$root/summary.txt"
echo "logs: $root"
exit $status
