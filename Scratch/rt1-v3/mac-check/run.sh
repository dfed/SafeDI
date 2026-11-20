#!/bin/bash
# Spec v3's Apple-silicon check: Swift 6.2 (Xcode 26), -O -wmo, seam and caller in separate modules, inline in the same run.
# Usage: DEVELOPER_DIR=/Applications/Xcode_26.app/Contents/Developer ./run.sh   (about 10 minutes on an M-series Mac)
# Builds land in ~/Library/Caches/SafeDITests/rt1-v3 (never the system temporary directory), removed at the end.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=~/Library/Caches/SafeDITests/rt1-v3; rm -rf "$work"; mkdir -p "$work/tmp"; export TMPDIR="$work/tmp"
swiftc() { xcrun swiftc "$@"; }
xcrun swiftc --version 2>&1 | head -1
chain() { # FORM READS D
  d=$work/chain-$1-$2-$3; python3 "$here/gen3.py" chain $1 $2 $3 "$d"
  (cd "$d" && swiftc -O -wmo -swift-version 6 -parse-as-library -module-name Feature -emit-module -emit-object Feature.swift -o Feature.o && swiftc -O -wmo -swift-version 6 -I . App.swift Feature.o -o app) >/dev/null
}
xb() { # DIR: Types+Feature as module Feature, then App + bench
  d=$1; b=$d/x-O; mkdir -p "$b"
  swiftc -O -wmo -parse-as-library -swift-version 6 -module-name Feature -emit-module -emit-module-path "$b/Feature.swiftmodule" -emit-object -o "$b/Feature.o" "$d/Types.swift" "$d/Feature.swift"
  swiftc -O -wmo -swift-version 6 -module-name Main -I "$b" -emit-object -o "$b/Main.o" "$d/App.swift" "$d/bench/main.swift"
  swiftc -o "$b/bench" "$b/Main.o" "$b/Feature.o"
}
for r in none some win two; do for D in 10 50; do for f in inline cls ccl ccl2; do chain $f $r $D; done; done; done
for L in 6 8; do for f in inline cp ccl; do python3 "$here/egen3.py" $L $f "$work/E$((L*4))-$f"; xb "$work/E$((L*4))-$f"; done; done
for n in 40 200; do for f in inline cp ccl; do python3 "$here/ngen3.py" $n $f "$work/N1-$n-$f"; xb "$work/N1-$n-$f"; done; done
python3 - "$work" <<'PY'
import subprocess, statistics, sys
w = sys.argv[1]
def line(name, vals):
    b = statistics.median(vals["inline"]); print(name + ": " + "  ".join(f"{f} {statistics.median(v):.1f} ({statistics.median(v)/b:.2f}x)" for f, v in vals.items()), flush=True)
for r in ("none", "some", "win", "two"):
    for D in (10, 50):
        vals = {f: [] for f in ("inline", "cls", "ccl", "ccl2")}
        for _ in range(3):
            for f in vals: vals[f].append(float(subprocess.run([f"{w}/chain-{f}-{r}-{D}/app"], capture_output=True, text=True).stdout.split()[0]))
        line(f"CHAIN {r} {D}", vals)
for g in ("E24", "E32", "N1-40", "N1-200"):
    vals = {f: [] for f in ("inline", "cp", "ccl")}
    for _ in range(5):
        for f in vals: vals[f].append(float(subprocess.run([f"{w}/{g}-{f}/x-O/bench"], capture_output=True, text=True).stdout.split()[1]))
    line(f"WALK {g}", vals)
PY
rm -rf "$work"
