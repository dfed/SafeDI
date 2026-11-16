#!/bin/zsh
# run-fixture.zsh FIXTURE VARIANT… — builds each variant at -Onone and -O with -warnings-as-errors, runs it, stores its
# trace in FIXTURE/results/<variant>-<optimization>.txt (or the compiler's verdict in <variant>-<optimization>.error.txt),
# compares every trace with the first variant's -Onone trace byte for byte, and builds each variant named `d*` once more
# with library evolution and a verified module interface.
set -uo pipefail
fixture=${1:A}; shift
common=${0:A:h}
spike=${common:h}
output_root=${SPIKE_OUTPUT:-$HOME/.cache/per-type-seam-spike}
mkdir -p "$fixture/results"
for variant in "$@"; do rm -f "$fixture/results/$variant"-*(N); done
reference=""
for variant in "$@"; do
	for optimization in Onone O; do
		result="$fixture/results/$variant-$optimization"
		if "$common/build.zsh" "$fixture/$variant" $optimization >"$result.build.log" 2>&1; then
			"$output_root/${fixture#$spike/}/$variant/out-$optimization/main" >"$result.txt" 2>&1 || echo "exit $?" >>"$result.txt"
			[[ -z "$reference" ]] && reference="$result.txt"
			if cmp -s "$reference" "$result.txt"; then echo "$variant -$optimization: trace equals ${reference:t}"; else echo "$variant -$optimization: trace DIFFERS from ${reference:t}"; fi
			rm -f "$result.build.log"
		else
			grep -E "error:" "$result.build.log" | sed -e "s|$output_root/${fixture#$spike/}/||g" -e "s|$fixture/||g" | sort -u >"$result.error.txt"
			echo "$variant -$optimization: does not compile ($(wc -l <"$result.error.txt" | tr -d " ") distinct errors)"
			rm -f "$result.build.log"
		fi
	done
	if [[ $variant == d* ]]; then
		if "$common/build.zsh" "$fixture/$variant" Onone -enable-library-evolution -emit-module-interface -verify-emitted-module-interface >"$fixture/results/$variant-evolution.log" 2>&1; then
			echo "$variant library evolution: compiles, interface verifies"; rm -f "$fixture/results/$variant-evolution.log"
		else
			echo "$variant library evolution: FAILS (results/$variant-evolution.log)"
		fi
	fi
done
