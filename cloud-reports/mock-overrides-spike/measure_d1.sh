#!/bin/bash
# measure_d1.sh: D1, the scripted shared form (hand-written), on main's `let` output and the enum box's, alternating.
here=$(cd "$(dirname "$0")" && pwd)
main=~/tools/SafeDITool-main-2475984; box=~/tools/SafeDITool-enumbox-228b875
res="$here/results/D1.jsonl"
run() { echo "load: $(cut -d' ' -f1 /proc/loadavg) $*" >&2; python3 "$here/run_d.py" --bin ~/bin --rewrite "$here/rewrite_shared.py" "$@" | tail -1 >> "$res"; }
# 1. the curve: lines and debug compile, 8 to 32 screens; stack at 32.
for n in 8 12 16 20 24 28 32; do
  r=5; (( n > 16 )) && r=3; m=layout; (( n == 32 )) && m=layout,stack
  for t in $main $box; do run --tool $t --screens $n --repeats $r --modes $m --work ~/work/d1-$(basename $t); done
done
# 1. time, plain and --walk, at both levels, at 16 and 24.
for n in 16 24; do for opt in Onone O; do for w in "" --walk; do for t in $main $box; do
  run --tool $t --screens $n --opt $opt $w --modes time:200 --work ~/work/d1t-$(basename $t)
done; done; done; done
