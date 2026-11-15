#!/bin/zsh
# F6, the @Sendable family: shapes (i) and (ii), each (a) inline, (b) today, (c) leak fix, (d1) one @Sendable function
# per type, (d2) one function per type and family.
set -euo pipefail
here=${0:A:h}
cd "$here" && python3 -I gen.py ../common && python3 -I handgen.py
for shape in i ii; do
	mkdir -p $shape/results
	../common/run-fixture.zsh $shape a b c d1 d2 | tee $shape/results/summary.txt
done
