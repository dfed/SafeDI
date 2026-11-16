#!/bin/zsh
# F1, calibration. Writes the shared sources, then builds and runs (a) inline, (b) today, (c) leak fix, (d) per-type.
set -euo pipefail
here=${0:A:h}
cd "$here" && mkdir -p results && python3 -I gen.py ../common
../common/run-fixture.zsh "$here" a b c d | tee results/summary.txt
