#!/bin/bash
# measure_bc.sh: B5 (cost split) and C (proxy), alternating main's `let`, the enum box and the class box.
here=$(cd "$(dirname "$0")" && pwd)
tools=(~/tools/SafeDITool-main-2475984 ~/tools/SafeDITool-enumbox-228b875 ~/tools/SafeDITool-classbox-c5f79fa)
log() { echo "load: $(cut -d' ' -f1 /proc/loadavg) $*" >&2; }
# B5 (b): a module whose mocks nest no configuration; its generated code must equal main's.
for t in "${tools[@]}"; do log flat $t; python3 "$here/proxy.py" --tool $t --bin ~/bin --flat --repeats 5 --work ~/work/flat-$(basename $t) | tail -1 >> "$here/results/B5-flat.jsonl"; done
# C 1-4: the proxy module (configurations nest) at both levels, with mock() timing and counters.
for opt in Onone O; do for t in "${tools[@]}"; do
  log proxy $opt $t; python3 "$here/proxy.py" --tool $t --bin ~/bin --opt $opt --repeats 5 --calls 2000 --stats ~/work/stats-$(basename $t)-$opt --work ~/work/proxy-$(basename $t) | tail -1 >> "$here/results/C-proxy.jsonl"
done; done
# C: shape D at 16, compile and both time runs, at both levels.
for opt in Onone O; do for w in "" --walk; do for t in "${tools[@]}"; do
  r=0; [[ -z $w ]] && r=5
  log shapeD $opt $w $t; python3 "$here/run_d.py" --tool $t --bin ~/bin --screens 16 --opt $opt $w --repeats $r --modes time:200,layout --work ~/work/c-$(basename $t) | tail -1 >> "$here/results/C-shapeD16.jsonl"
done; done; done
# C: one confirming pair at 16 with the planned `nonisolated` on every configuration struct.
for t in ${tools[0]} ${tools[1]}; do log nonisolated $t; python3 "$here/run_d.py" --tool $t --bin ~/bin --screens 16 --nonisolated --repeats 5 --modes time:200 --work ~/work/cni-$(basename $t) | tail -1 >> "$here/results/C-shapeD16-nonisolated.jsonl"; done
