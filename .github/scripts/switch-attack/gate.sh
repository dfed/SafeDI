#!/bin/bash
# gate.sh ON_TOOL OFF_TOOL FIRST_SEED LAST_SEED WORKERS [OUTPUT_DIRECTORY]
# Runs gen2.py's graphs for seeds FIRST...LAST, both declaration orders, through the two SafeDITool binaries
# (ON: the switch head; OFF: the same head with the node-records layout forced off) and compares generated
# bytes where both succeed, standard error where both fail. Exit status 0 only for a clean run.
set -u
if [ $# -lt 5 ]; then echo "usage: gate.sh ON_TOOL OFF_TOOL FIRST_SEED LAST_SEED WORKERS [OUTPUT_DIRECTORY]" >&2; exit 2; fi
on=$1; off=$2; first=$3; last=$4; workers=$5
here=$(cd "$(dirname "$0")" && pwd); out=${6:-$PWD/gate-$first-$last}
[ -x "$on" ] && [ -x "$off" ] || { echo "a tool path is not executable" >&2; exit 2; }
mkdir -p "$out"
worker() { # worker INDEX
  d=$out/w$1; mkdir -p "$d"; : > "$d/log"
  s=$(( first + $1 ))
  while [ $s -le $last ]; do for o in f r; do
    if [ $o = r ]; then python3 "$here/gen2.py" $s r > "$d/g.swift"; else python3 "$here/gen2.py" $s > "$d/g.swift"; fi
    printf '%s' "$d/g.swift" > "$d/in.csv"; rm -f "$d/off.swift" "$d/on.swift" "$d/f.txt"
    "$off" generate "$d/in.csv" --combined-output "$d/off.swift" --compiler-receives-input-paths-unchanged --module-info-output "$d/o.safedi" --module-name M >/dev/null 2>"$d/off.err"; eo=$?
    "$on" generate "$d/in.csv" --combined-output "$d/on.swift" --compiler-receives-input-paths-unchanged --module-info-output "$d/n.safedi" --module-name M --tree-forcers-output "$d/f.txt" >/dev/null 2>"$d/on.err"; en=$?
    forcers=$(grep -v "^roots that" "$d/f.txt" 2>/dev/null | cut -f2- | sort -u | tr '\n' ';')
    if [ $eo != $en ]; then r=EXITDIFF; elif ! cmp -s "$d/off.err" "$d/on.err"; then r=ERRDIFF; elif [ $eo != 0 ]; then r=ERRSAME
    elif cmp -s "$d/off.swift" "$d/on.swift"; then r=SAME; else r=DIFF; fi
    echo "$s$o $r $eo $en [$forcers]" >> "$d/log"
    case $r in DIFF|EXITDIFF|ERRDIFF) mkdir -p "$out/keep/$s$o"; cp "$d/g.swift" "$d/off.swift" "$d/on.swift" "$d/off.err" "$d/on.err" "$d/f.txt" "$out/keep/$s$o/" 2>/dev/null;; esac
  done; s=$(( s + workers )); done
}
i=0; while [ $i -lt $workers ]; do worker $i & i=$(( i + 1 )); done; wait
cat "$out"/w*/log > "$out/all.log"
count() { grep -c " $1 " "$out/all.log"; }
graphs=$(wc -l < "$out/all.log" | tr -d ' '); expected=$(( (last - first + 1) * 2 ))
same=$(count SAME); errsame=$(count ERRSAME); diff=$(count DIFF); exitdiff=$(count EXITDIFF); errdiff=$(count ERRDIFF)
records=$(grep " SAME " "$out/all.log" | grep -c '\[none;\]')
echo "graphs $graphs of $expected (seeds $first...$last, two orders)"
echo "SAME $same  ERRSAME $errsame  DIFF $diff  EXITDIFF $exitdiff  ERRDIFF $errdiff"
echo "accepted graphs with every root laid out from records: $records of $same"
echo "accepted graphs by the kinds that kept a root off records:"
grep " SAME " "$out/all.log" | sed 's/^[^[]*//' | sort | uniq -c | sort -rn
if [ "$graphs" = "$expected" ] && [ $diff = 0 ] && [ $exitdiff = 0 ] && [ $errdiff = 0 ] && [ $records -gt 0 ]; then echo "CLEAN"; exit 0
else echo "NOT CLEAN: differing graphs are under $out/keep/"; exit 1; fi
