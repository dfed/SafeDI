#!/bin/zsh
# measure.zsh SHAPE_DIRECTORY… — for each shape directory that emit.py wrote (E8, E16, …):
#  1. values: builds (a)–(d) at -Onone with -D SPIKE_TRACE, walks every path, and compares each trace with (a)'s;
#  2. builds (a)–(d) at -O (whole module, no tracing) with each module's compile timed, the -O -wmo figure;
#  3. runtime: 1 warm-up round, then 7 rounds, interleaved across variants, each `main bench` (a round repeats
#     Root() plus the walk of every path until it lasts at least 100 ms, and prints ns per walk);
#  4. builds (a)–(d) at -Onone (whole module, no tracing) ROUNDS times (default 3, plus a dropped warm-up),
#     interleaved, with each module's compile timed;
#  5. line counts of the seam file, the seam initializer and the App file.
# Results: results/<shape>/. Every compile runs under `timeout 20m /usr/bin/time -v` (build.zsh's TIME_LOG).
set -uo pipefail
here=${0:A:h}
common=${here:h}/common
output_root=${SPIKE_OUTPUT:-$HOME/.cache/per-type-seam-spike}
rounds=${ROUNDS:-3}
variants=(${=VARIANTS:-a b c d})
for shape in "$@"; do
	shape=${shape:A}; name=${shape:t}
	results="$here/results/$name"; mkdir -p "$results"
	binary() { print "$output_root/${shape#${here:h}/}/$1/out-$2/main"; }
	time_log() { print "$output_root/timing/$name/$1-$2-$3"; }
	echo "=== $name: values" | tee "$results/values.txt"
	for variant in $variants; do
		if TIME_LOG=$(time_log $variant trace 0) "$common/build.zsh" "$shape/$variant" Onone -D SPIKE_TRACE >"$results/$variant-trace-build.log" 2>&1; then
			$(binary $variant Onone) >"$output_root/timing/$name-$variant.trace" 2>&1
			if cmp -s "$output_root/timing/$name-a.trace" "$output_root/timing/$name-$variant.trace"; then verdict="trace equals (a)"; else verdict="trace DIFFERS from (a)"; fi
			echo "$variant: $(wc -l <"$output_root/timing/$name-$variant.trace") lines, sha256 $(sha256sum "$output_root/timing/$name-$variant.trace" | cut -c1-16), $verdict" | tee -a "$results/values.txt"
			rm -f "$results/$variant-trace-build.log"
		else
			echo "$variant: did not build (results/$name/$variant-trace-build.log)" | tee -a "$results/values.txt"
		fi
	done
	echo "=== $name: -O builds" >&2
	for variant in $variants; do
		SKIP_GENERATE=1 TIME_LOG=$(time_log $variant O 1) "$common/build.zsh" "$shape/$variant" O >"$results/$variant-O-build.log" 2>&1 && rm -f "$results/$variant-O-build.log"
	done
	echo "=== $name: runtime" | tee "$results/runtime.txt"
	for round in {0..7}; do
		echo "uptime before round $round: $(uptime)" >>"$results/runtime.txt"
		for variant in $variants; do
			[[ -x $(binary $variant O) ]] || continue
			echo "round $round $variant: $($(binary $variant O) bench)" >>"$results/runtime.txt"
		done
	done
	echo "=== $name: -Onone compiles" >&2
	for round in $(seq 0 $rounds); do
		for variant in $variants; do
			SKIP_GENERATE=1 TIME_LOG=$(time_log $variant Onone $round) "$common/build.zsh" "$shape/$variant" Onone >/dev/null 2>&1
		done
	done
	echo "=== $name: lines" | tee "$results/lines.txt"
	for variant in $variants; do
		[[ $variant == a ]] && continue
		if [[ $variant == b ]]; then seam="$shape/b/stored/Feature.swift.txt"; app="$shape/b/stored/App.swift.txt"; else seam="$shape/$variant/Feature/Generated/Feature.swift.txt"; app="$shape/$variant/App/Generated/App.swift.txt"; fi
		initializer=$(awk '/public convenience init\(__safeDI_/{on=1} on{n++} on&&/^    }$/{print n; exit}' "$seam")
		echo "$variant: seam file $(wc -l <"$seam") lines (sha256 $(sha256sum "$seam" | cut -d" " -f1)), seam initializer $initializer lines, App file $(wc -l <"$app") lines (sha256 $(sha256sum "$app" | cut -d" " -f1))" | tee -a "$results/lines.txt"
	done
	python3 -I "$here/summarize.py" "$output_root/timing/$name" "$results" | tee "$results/summary.txt"
done
