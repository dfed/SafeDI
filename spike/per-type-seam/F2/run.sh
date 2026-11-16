#!/bin/zsh
# F2, a loop through two types, with L = next (main rejects it) and L = screenBuilder; and `mark/`, the case that tells
# candidate A from candidate B.
set -euo pipefail
here=${0:A:h}
output_root=${SPIKE_OUTPUT:-$HOME/.cache/per-type-seam-spike}
cd "$here" && python3 -I gen.py ../common && python3 -I gen_mark.py ../common --types-only
for label in next screenBuilder; do
	mkdir -p $label/results
	variants=(a b d-A d-B); [[ $label == screenBuilder ]] && variants=(a b c-A c-B d-A d-B)
	../common/run-fixture.zsh $label $variants | tee $label/results/summary.txt
done
# (c) for L = next is the struct and the readable initializer only: compile them with the hand-written callers.
for candidate in A B; do
	../common/build.zsh next/c-$candidate Onone >/dev/null && "$output_root/F2/next/c-$candidate/out-Onone/main" | tee next/results/c-$candidate-Onone.txt
done
mkdir -p mark/results
../common/run-fixture.zsh mark a b d-A d-B | tee mark/results/summary.txt
