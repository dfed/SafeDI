#!/bin/zsh
# F4, a nil value under a reopened seam: (a) inline, (b) today, then (c) and (d) with today's caller shape and with the
# root level function taking `cart: Cart?`.
set -euo pipefail
here=${0:A:h}
cd "$here" && mkdir -p results && python3 -I gen.py ../common && python3 -I handgen.py
../common/run-fixture.zsh "$here" a b c-today c-fixed d-today d-fixed | tee results/summary.txt
