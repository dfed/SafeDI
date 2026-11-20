#!/bin/bash
# Spec v4's Apple-silicon check (form C: Cx on E and chains, Cf on N1; ccl and inline beside it): Swift 6.2 (Xcode 26), -O -wmo, seam and caller in separate modules, inline in the same run.
# Usage: DEVELOPER_DIR=/Applications/Xcode_26.app/Contents/Developer ./run.sh   (about 10 minutes on an M-series Mac)
# Builds land in ~/Library/Caches/SafeDITests/rt1-v3 (never the system temporary directory), removed at the end.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=~/Library/Caches/SafeDITests/rt1-v3; rm -rf "$work"; mkdir -p "$work/tmp"; export TMPDIR="$work/tmp"
swiftc() { xcrun swiftc "$@"; }
xcrun swiftc --version 2>&1 | head -1
chain() { # FORM READS D [rebuild]
  d=$work/chain-$1-$2-$3${4:+-$4}; python3 "$here/gen3c.py" chain $1 $2 $3 "$d" $4
  (cd "$d" && swiftc -O -wmo -swift-version 6 -parse-as-library -module-name Feature -emit-module -emit-object Feature.swift -o Feature.o && swiftc -O -wmo -swift-version 6 -I . App.swift Feature.o -o app) >/dev/null
}
xb() { # DIR: Types+Feature as module Feature, then App + bench
  d=$1; b=$d/x-O; mkdir -p "$b"
  swiftc -O -wmo -parse-as-library -swift-version 6 -module-name Feature -emit-module -emit-module-path "$b/Feature.swiftmodule" -emit-object -o "$b/Feature.o" "$d/Types.swift" "$d/Feature.swift"
  swiftc -O -wmo -swift-version 6 -module-name Main -I "$b" -emit-object -o "$b/Main.o" "$d/App.swift" "$d/bench/main.swift"
  swiftc -o "$b/bench" "$b/Main.o" "$b/Feature.o"
}
for r in none some win two; do for D in 10 50; do for f in inline ccl2 Cx; do chain $f $r $D; chain $f $r $D rebuild; done; done; done
for g in "E24 6" "E32 8"; do set -- $g; for f in inline ccl Cx; do python3 "$here/gen5.py" e $2 1 plain $f "$work/$1-$f"; xb "$work/$1-$f"; done; done
for n in 40 200; do for f in inline ccl Cf; do python3 "$here/gen5.py" n1 $n 1 plain $f "$work/N1-$n-$f"; xb "$work/N1-$n-$f"; done; done
python3 - "$work" <<'PY'
import subprocess, statistics, sys
w = sys.argv[1]
def line(name, vals):
    b = statistics.median(vals["inline"]); print(name + ": " + "  ".join(f"{f} {statistics.median(v):.1f} ({statistics.median(v)/b:.2f}x)" for f, v in vals.items()), flush=True)
for r in ("none", "some", "win", "two"):
    for D in (10, 50):
        for rb in ("", "-rebuild"):
            vals = {f: [] for f in ("inline", "ccl2", "Cx")}
            for _ in range(3):
                for f in vals: vals[f].append(float(subprocess.run([f"{w}/chain-{f}-{r}-{D}{rb}/app"], capture_output=True, text=True).stdout.split()[0]))
            line(f"CHAIN {r} {D} host-{'rebuilt' if rb else 'once'}", vals)
for g, forms in (("E24", ("inline", "ccl", "Cx")), ("E32", ("inline", "ccl", "Cx")), ("N1-40", ("inline", "ccl", "Cf")), ("N1-200", ("inline", "ccl", "Cf"))):
    vals = {f: [] for f in forms}
    for _ in range(7):
        for f in vals: vals[f].append(float(subprocess.run([f"{w}/{g}-{f}/x-O/bench"], capture_output=True, text=True).stdout.split()[1]))
    line(f"WALK {g} (host rebuilt every walk)", vals)
PY
rm -rf "$work"
