#!/bin/zsh
# Reruns every W1 derisk fixture from the committed files (no generator reruns: ./CLI/lint.sh formats the committed
# Swift). Each summary goes to <fixture>/results/summary.txt.
set -uo pipefail
here=${0:A:h}; cd $here
run() { local d=$1; shift; mkdir -p $d/results; ../per-type-seam/common/run-fixture.zsh $d "$@" | tee $d/results/summary.txt; }
for s in plain scall sfam; do echo "== G2X/$s"; run G2X/$s a b c d; done
for s in plain scall sfam; do echo "== G2L/$s"; run G2L/$s a b d; done
for s in sdb both; do echo "== SND/$s"; run SND/$s a b d; done
for s in req opt one; do echo "== RE2/$s"; run RE2/$s a b d; done
echo "== STG3/base"; run STG3/base a b d
echo "== PM3"; run PM3 a c2 h
echo "== W1/base"; run W1/base a b
echo "== PM/acc"; run PM/acc a b
echo "== PM/w1"; run PM/w1 a b
echo "== PMRE/base"; run PMRE/base a b
# Gaps 1 and 2 inside a public-mock body (b2: today's split mock, called with the parameter it asks for).
echo "== PMG/order"; run PMG/order a b b2 d
echo "== PMG/loop"; run PMG/loop a b d
