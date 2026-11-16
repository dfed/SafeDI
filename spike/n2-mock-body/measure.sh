#!/bin/zsh
# measure.sh FIXTURE MODULE RUNS ITERATIONS VARIANT… — for each variant and optimization level, builds RUNS times and
# records MODULE's compile (wall seconds and peak memory from /usr/bin/time), then runs the executable with BENCH set.
# Prints one JSON line per (variant, optimization) and appends it to FIXTURE/results/measure.jsonl.
set -uo pipefail
fixture=${1:A}; module=$2; runs=$3; iterations=$4; shift 4
here=${0:A:h}
output_root=${SPIKE_OUTPUT:-$HOME/.cache/per-type-seam-spike}
mkdir -p $fixture/results
for variant in "$@"; do
	for optimization in Onone O; do
		walls=(); memories=()
		for run in $(seq $runs); do
			log=$fixture/results/time-$variant-$optimization
			rm -rf $log
			SKIP_GENERATE=1 TIME_LOG=$log $here/common-build.zsh $fixture/$variant $optimization >/dev/null 2>&1 || { echo "$variant $optimization: build failed"; continue 2; }
			wall=$(grep "Elapsed (wall clock)" $log/$module.time | awk '{print $NF}' | awk -F: '{ if (NF==3) print $1*3600+$2*60+$3; else print $1*60+$2 }')
			memory=$(grep "Maximum resident" $log/$module.time | awk '{print $NF}')
			walls+=($wall); memories+=($memory)
		done
		executable=$output_root/${fixture#${here:h}/}/$variant/out-$optimization/main
		bench=$(BENCH=$iterations $executable 2>&1 >/dev/null | awk '/bench/ {print $NF}')
		lines=$(cat $fixture/$variant/stored/$module.swift.txt $fixture/$variant/$module/Generated/*.swift(N) 2>/dev/null | wc -l)
		sorted=(${(n)walls}); median=${sorted[$(( (${#sorted} + 1) / 2 ))]}
		json="{\"fixture\": \"${fixture:t}\", \"variant\": \"$variant\", \"optimization\": \"$optimization\", \"module\": \"$module\", \"generatedLines\": $lines, \"compileWallSeconds\": [${(j:, :)walls}], \"compileMedian\": $median, \"peakKilobytes\": [${(j:, :)memories}], \"nsPerWalk\": ${bench:-null}}"
		echo $json | tee -a $fixture/results/measure.jsonl
	done
done
