#!/bin/bash
# probes7 (spec v4.1 check) on Apple's Swift 6.2 (Xcode 26). Isolation cells use full compiles (-c).
# Expected: every isolation cell rc=0 with 0 warnings; Retention prints 1/2/1 twice; both FormationKey variants fail.
set -u
p=$(cd "$(dirname "$0")/../probes7" && pwd); work=~/Library/Caches/SafeDITests/rt1-v3-p7; rm -rf "$work"; mkdir -p "$work/tmp"; export TMPDIR="$work/tmp"; cd "$work"
for sm in plain main; do d="$work/s_$sm"; mkdir -p "$d"; f=""; [ $sm = main ] && f="-default-isolation MainActor"
  (cd "$d" && xcrun swiftc -swift-version 6 -parse-as-library -module-name Seam -emit-module -c $f "$p/Seam.swift" -o Seam.o)
  for cm in plain main; do cf=""; [ $cm = main ] && cf="-default-isolation MainActor"
    for r in STRUCT CLASS_ROOT ATTR_ROOT; do rf=""; [ $r != STRUCT ] && rf="-D$r"
      for mi in no yes; do mf=""; [ $mi = yes ] && mf="-DMAIN_IMPL"
        out=$(cd "$d" && xcrun swiftc -swift-version 6 -parse-as-library -I . -c $cf $rf $mf "$p/Caller.swift" -o c.o 2>&1); rc=$?
        echo "seam=$sm caller=$cm root=$r mainimpl=$mi rc=$rc warnings=$(echo "$out" | grep -c 'warning:') errors=$(echo "$out" | grep -c 'error:')"
done; done; done; done
xcrun swiftc -O -swift-version 6 "$p/Retention.swift" -o ret && ./ret
for v in "" "-DSHARED_NONISOLATED"; do xcrun swiftc -typecheck -swift-version 6 $v "$p/key/FormationKey.swift" > /dev/null 2>&1; echo "FormationKey '$v' rc=$? (expect nonzero)"; done
cd /; rm -rf "$work"
