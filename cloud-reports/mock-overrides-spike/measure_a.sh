#!/bin/bash
# measure_a.sh TOOL: section A on one tool. Appends JSON lines to results/A-<tool>.jsonl.
here=$(cd "$(dirname "$0")" && pwd)
tool=$1; name=$(basename "$tool"); res="$here/results/A-$name.jsonl"
run() { echo "load: $(cut -d' ' -f1 /proc/loadavg)" >&2; python3 "$here/run_d.py" --tool "$tool" --bin ~/bin "$@" | tail -1 >> "$res"; }
# A1: lines, generate time, App debug compile (median of 5, 3 above 16 screens), object size, layout.
for n in 8 12 16 20 24; do r=5; (( n > 16 )) && r=3; run --screens $n --repeats $r --modes layout; done
# A2: time at -Onone and -O -DDEBUG, plain and --walk.
for n in 8 12 16; do for opt in Onone O; do run --screens $n --opt $opt --modes time:200; run --screens $n --opt $opt --walk --modes time:200; done; done
# A3: the reference traces.
for n in 8 16; do run --screens $n --trace --modes trace,trace-overrides --work ~/work/ref-$name; done
