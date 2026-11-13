#!/bin/bash
# matrix.sh: the scale matrix. For each toolchain/build system and N: clean Debug, two incremental Debug builds, clean Release.
cd "$(dirname "$0")/.."
for spec in "6.4.2 default" "6.4.2 native" "6.3.3 default" "6.2.4 default"; do
  set -- $spec; TC=$1; BS=$2
  for N in 10 100 1000; do
    python3 scripts/gen.py Harness/Sources/Client class $N construct
    L=$TC-$BS-n$N
    scripts/run.sh $TC debug $BS $L-debug-clean || echo "FAIL $L-debug-clean"
    CLEAN=0 TOUCH=T0.swift scripts/run.sh $TC debug $BS $L-debug-touchT0 || echo "FAIL $L-debug-touchT0"
    CLEAN=0 TOUCH=Use.swift scripts/run.sh $TC debug $BS $L-debug-touchUse || echo "FAIL $L-debug-touchUse"
    [ "$BS" = native ] || scripts/run.sh $TC release $BS $L-release-clean || echo "FAIL $L-release-clean"
    echo "done $L"
  done
done
