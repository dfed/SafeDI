#!/bin/zsh
# Scripts/fuzz-corpus.sh [--features NAME,NAME] [--seed N] [--iterations M|corpus] [--seeds N,N…] [--release]
# Runs SafeDIToolGraphFuzzerTests/longRun as CI does and prints the shard (or seeds) and corpus pin lines and the cost line from its report.
# --features takes `GraphFuzzerGeneratorFeature` raw values (`generateDependencyTree`, `generateMockPublic`, …).
# Default: the base corpus, seeds 0..<100, debug build. `--iterations corpus` runs the whole selected corpus and
# checks its pins; the shard line's accepted count and sum are what corpusAcceptedSeedCount and corpusAcceptedSeedsSum pin.
# --seeds runs exactly the listed seeds in one process, in place of --seed and --iterations.
# Every run draws the whole selected corpus first and prints a problem line with the new value when
# its fixture hash (or the base corpus's partition hash) moved, so `--iterations 1` derives a corpus's hashes in under
# a minute after the build (measured in debug: base 25 s, generateDependencyTree 20 s, generateMockPublic 10 s).
set -euo pipefail
features="" seed=0 iterations=100 seeds="" configuration=debug
while (( $# )); do case "$1" in
	--features) features=$2; shift 2 ;; --seed) seed=$2; shift 2 ;; --iterations) iterations=$2; shift 2 ;; --seeds) seeds=$2; [[ -n $seeds ]] || { echo "--seeds takes a list of seeds" >&2; exit 2 }; shift 2 ;;
	--release) configuration=release; shift ;; *) echo "unknown option $1" >&2; exit 2 ;; esac; done
cd "$(git rev-parse --show-toplevel)"
report=$(mktemp -t safedi-fuzz-report.XXXXXX)
exit_status=0
if [[ -n $seeds ]]; then
	selection=(-u SAFEDI_GRAPH_FUZZER_STARTING_SEED -u SAFEDI_GRAPH_FUZZER_ITERATIONS SAFEDI_GRAPH_FUZZER_SEEDS=$seeds)
else
	selection=(-u SAFEDI_GRAPH_FUZZER_SEEDS SAFEDI_GRAPH_FUZZER_STARTING_SEED=$seed SAFEDI_GRAPH_FUZZER_ITERATIONS=$iterations)
fi
# A shard left in the environment would also select seeds; -u keeps the run to what the options name.
env -u SAFEDI_GRAPH_FUZZER_SHARD $selection SAFEDI_GRAPH_FUZZER_FEATURES=$features SAFEDI_GRAPH_FUZZER_REPORT=$report \
	swift test -c $configuration --traits sourceBuild --filter 'SafeDIToolGraphFuzzerTests/longRun' || exit_status=$?
echo "--- pins (report: $report)"; grep -E '^(shard|seeds|corpus|cpu) |^problem .*(fixture|partition) hash ' "$report" || true
exit $exit_status
