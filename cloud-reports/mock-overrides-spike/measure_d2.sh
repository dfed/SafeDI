#!/bin/bash
# measure_d2.sh: D1's measurements on the D2 generator's own output (no rewrite), and the equality of that output with
# the D1 hand-written form of the enum box's output at each size.
here=$(cd "$(dirname "$0")" && pwd)
d2=~/tools/SafeDITool-d2-401e334
run() { echo "load: $(cut -d' ' -f1 /proc/loadavg) $*" >&2; python3 "$here/run_d.py" --bin ~/bin "$@" | tail -1 >> "$here/results/D2.jsonl"; }
for n in 8 16; do run --tool $d2 --screens $n --trace --modes trace,trace-overrides --work ~/work/d2trace; done
for n in 8 12 16 20 24 28 32; do
  r=5; (( n > 16 )) && r=3; m=layout; (( n == 32 )) && m=layout,stack
  run --tool $d2 --screens $n --repeats $r --modes $m --work ~/work/d2
  if cmp -s ~/work/d2/out-D-$n/App.gen.swift ~/work/d1-SafeDITool-enumbox-228b875/out-D-$n/App.gen.swift; then echo "D2 = D1 hand-written at $n"; else echo "D2 differs from D1 hand-written at $n"; fi
done
for n in 16 24; do for opt in Onone O; do for w in "" --walk; do
  run --tool $d2 --screens $n --opt $opt $w --modes time:200 --work ~/work/d2t
done; done; done
