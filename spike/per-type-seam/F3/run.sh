#!/bin/zsh
# F3, a stale loop value in a public mock: (a) inline, (b) today (main rejects it), (c) the struct and readable mock
# only, (d) a per-type `__safeDI_mock`; and `accepted/`, the neighbor main accepts, whose today's mock is the reference
# for the public mock's shape.
set -euo pipefail
here=${0:A:h}
cd "$here" && python3 -I gen.py ../common
mkdir -p stale/results accepted/results
../common/run-fixture.zsh stale a b c d | tee stale/results/summary.txt
../common/run-fixture.zsh accepted a b | tee accepted/results/summary.txt
