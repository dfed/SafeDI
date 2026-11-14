#!/bin/zsh
# Scripts/fuzz-corpus.sh [--features NAME,NAME] [--seed N] [--iterations M|corpus] [--release]
# Runs SafeDIToolGraphFuzzerTests/longRun as CI does and prints the shard and corpus pin lines and the cost line from its report.
# --features takes `GraphFuzzerGeneratorFeature` raw values (`generateDependencyTree`, `generateMockPublic`, …).
# Default: the base corpus, seeds 0..<100, debug build. `--iterations corpus` runs the whole selected corpus and
# checks its pins; the shard line's accepted count and sum are what corpusAcceptedSeedCount and corpusAcceptedSeedsSum pin.
set -euo pipefail
features="" seed=0 iterations=100 configuration=debug
while (( $# )); do case "$1" in
	--features) features=$2; shift 2 ;; --seed) seed=$2; shift 2 ;; --iterations) iterations=$2; shift 2 ;;
	--release) configuration=release; shift ;; *) echo "unknown option $1" >&2; exit 2 ;; esac; done
cd "$(git rev-parse --show-toplevel)"
report=$(mktemp -t safedi-fuzz-report)
exit_status=0
SAFEDI_GRAPH_FUZZER_FEATURES=$features SAFEDI_GRAPH_FUZZER_STARTING_SEED=$seed SAFEDI_GRAPH_FUZZER_ITERATIONS=$iterations SAFEDI_GRAPH_FUZZER_REPORT=$report \
	swift test -c $configuration --traits sourceBuild --filter 'SafeDIToolGraphFuzzerTests/longRun' || exit_status=$?
echo "--- pins (report: $report)"; grep -E '^(shard|corpus|cpu) ' "$report" || true
exit $exit_status
