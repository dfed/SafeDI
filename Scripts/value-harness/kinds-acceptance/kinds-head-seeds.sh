#!/bin/bash
# kinds-head-seeds.sh HASH [BUNDLE] — the mock kinds' seed acceptance on one kinds head: merges the mock kind draws
# (claude/project-thread-dotnyu-mock-kind-draws) onto HASH, builds, runs the graph fuzzer's long run over the seeds in
# $SEEDS_FILE with SAFEDI_NODE_RECORDS_LAY_OUT_MOCKS on and off, and prints one line: whether the failures are the same
# line for line, how many there are, and how many mock roots the layout laid out. Reports go to $OUT/HASH/.
set -u
hash=$1; bundle=${2:-}
work=${WORK:-/home/user/wt-kinds-draws}; out=${OUT:-/home/user/kc/heads}
seeds=$(cat "${SEEDS_FILE:-$(dirname "$0")/seeds.txt}")
export PATH=/opt/swift/usr/bin:$PATH TMPDIR=${TMPDIR_FOR_RUNS:-/home/user/tmpdir}
mkdir -p "$out/$hash"
cd "$work" || exit 2
[[ -n $bundle ]] && git fetch -q "$bundle" "+refs/*:refs/remotes/head-$hash/*"
git fetch -q origin claude/project-thread-dotnyu-mock-kind-draws
git checkout -q --detach "$hash" || exit 2
if ! git merge-base --is-ancestor FETCH_HEAD HEAD; then
  git merge -q --no-edit FETCH_HEAD >/dev/null || { echo "$hash: the draws do not merge cleanly"; git merge --abort; exit 1; }
fi
swift build --build-tests --traits sourceBuild > "$out/$hash/build.log" 2>&1 || { echo "$hash: build failed, $out/$hash/build.log"; exit 1; }
for mode in off on; do
  extra=(-u SAFEDI_NODE_RECORDS_LAY_OUT_MOCKS); [[ $mode == on ]] && extra=(SAFEDI_NODE_RECORDS_LAY_OUT_MOCKS=1 SAFEDI_NODE_RECORDS_REPORT="$out/$hash/records-on.tsv")
  rm -f "$out/$hash/records-on.tsv"
  env -u SAFEDI_GRAPH_FUZZER_SHARD -u SAFEDI_GRAPH_FUZZER_STARTING_SEED -u SAFEDI_GRAPH_FUZZER_ITERATIONS "${extra[@]}" \
    SAFEDI_GRAPH_FUZZER_SEEDS="$seeds" SAFEDI_GRAPH_FUZZER_FEATURES= SAFEDI_GRAPH_FUZZER_REPORT="$out/$hash/report-$mode.txt" \
    swift test --skip-build --traits sourceBuild --filter 'SafeDIToolGraphFuzzerTests/longRun' > "$out/$hash/test-$mode.log" 2>&1
done
off=$(grep -c '^failure' "$out/$hash/report-off.txt"); on=$(grep -c '^failure' "$out/$hash/report-on.txt")
finished_off=$(grep -c '^finished' "$out/$hash/report-off.txt"); finished_on=$(grep -c '^finished' "$out/$hash/report-on.txt")
laid=$(awk -F'\t' '$6=="mock" && $3=="laid out"' "$out/$hash/records-on.tsv" | wc -l)
held=$(awk -F'\t' '$6=="mock" && $3!="laid out"' "$out/$hash/records-on.tsv" | wc -l)
if diff -q <(grep '^failure' "$out/$hash/report-off.txt" | sort) <(grep '^failure' "$out/$hash/report-on.txt" | sort) >/dev/null; then same="same failures on and off"; else same="FAILURES DIFFER on and off ($out/$hash)"; fi
echo "$hash: $finished_on of $(tr ',' '\n' <<<"$seeds" | wc -l) seeds finished; $same ($off off, $on on); $laid mock roots laid out, $held held"
