#!/bin/bash
# Runs the whole matrix serially, configurations alternating within each run.
# Usage: run_all.sh BENCH_DIR SAFEDI_RELEASE_BUILD_DIR PROTOTYPE_SAFEDITOOL
#   BENCH_DIR holds fixture100/ and fixture300/ (from make_fixture.py) and receives results.jsonl.
#   SAFEDI_RELEASE_BUILD_DIR is `.build/release` after `swift build -c release --traits sourceBuild --target SafeDI`.
set -euo pipefail
B=$1; R=$2; TOOL=$3
SCRIPTS=$(cd "$(dirname "$0")" && pwd)
common=(--tool "$TOOL" --safedi-modules "$R/Modules" --macro-plugin "$R/SafeDIMacros-tool" --module-cache "$B/modulecache"
        --work "$B/work" --out "$B/results.jsonl" --runs 3 --configs 0,8,32,64)
cd "$B"
for fixture in fixture100 fixture300; do
  echo "== $fixture rules_swift without the worker: not incremental, no -j"
  python3 -I "$SCRIPTS/bench.py" --fixture $fixture --mode bazel "${common[@]}"
  echo "== $fixture rules_swift worker, Swift 6.2: incremental, no -j, generated files rewritten"
  python3 -I "$SCRIPTS/bench.py" --fixture $fixture --mode incremental-touch "${common[@]}"
  echo "== $fixture custom: incremental, -j 4, write-if-changed"
  python3 -I "$SCRIPTS/bench.py" --fixture $fixture --mode incremental --jobs 4 "${common[@]}"
done
for fixture in fixture100 fixture300; do
  echo "== $fixture rules_swift worker with file hashing: incremental, no -j, write-if-changed"
  python3 -I "$SCRIPTS/bench.py" --fixture $fixture --mode incremental "${common[@]}"
done
echo ALL DONE
