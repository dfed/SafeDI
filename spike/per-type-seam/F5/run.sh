#!/bin/zsh
# F5, a screen that opens itself, with L = next and L = screenBuilder; frees at depth 4 and 8.
set -euo pipefail
here=${0:A:h}
cd "$here" && python3 -I gen.py ../common
mkdir -p next/results screenBuilder/results
../common/run-fixture.zsh next a b c d | tee next/results/summary.txt
../common/run-fixture.zsh screenBuilder a b c-A c-B d-A d-B | tee screenBuilder/results/summary.txt
