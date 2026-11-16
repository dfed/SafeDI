#!/bin/zsh
# Stage 2, shape E (synthetic growth shape): emits 8, 16, 24 and 32 screens and measures each.
# Sizes above 16 screens are not committed (they are regenerated here); results/E*/lines.txt holds their line counts
# and sha256.
set -euo pipefail
here=${0:A:h}
cd "$here"
for n in 8 16 24 32; do
	python3 -I spec_e.py $n >spec-E$n.json
	rm -rf E$n && python3 -I emit.py spec-E$n.json E$n
done
./measure.zsh E8 E16 E24 E32
