#!/bin/bash
# Spec v3's isolation probes on Apple's Swift 6.2 (Xcode 26), full compiles (-c). Expected: Q* and S compile except
# QB (rejected: sending the isolated host to Task.detached); A, A2, B rejected (the v2 class form's caller subclasses);
# R0 rejected (seam fills class not spelled nonisolated under default MainActor); R1, R2 compile.
set -u
iso=$(cd "$(dirname "$0")/../isolation" && pwd); work=~/Library/Caches/SafeDITests/rt1-v3-iso; rm -rf "$work"; mkdir -p "$work/tmp" "$work/r" "$work/r0"; export TMPDIR="$work/tmp"; cd "$work"
sc() { xcrun swiftc -swift-version 6 -parse-as-library "$@" 2>&1 | grep -c "error:" ; }
xcrun swiftc -swift-version 6 -parse-as-library -module-name Feature -emit-module -emit-module-path Feature.swiftmodule -c "$iso/Feature.swift" -o Feature.o
xcrun swiftc -swift-version 6 -parse-as-library -module-name QFeature -emit-module -emit-module-path QFeature.swiftmodule -c "$iso/QFeature.swift" -o QFeature.o
echo "A  (expect errors): $(sc -default-isolation MainActor -I . -c $iso/A.swift -o a.o)"
echo "A2 (expect errors): $(sc -default-isolation MainActor -I . -c $iso/A2.swift -o a2.o)"
echo "B  (expect errors): $(sc -I . -c $iso/B.swift -o b.o)"
echo "QA (expect 0): $(sc -default-isolation MainActor -I . -c $iso/QA.swift -o qa.o)"
echo "QB (expect 1, the detached send): $(sc -I . -c $iso/QB.swift -o qb.o)"
echo "QC (expect 0): $(sc -I . -c $iso/QC.swift -o qc.o)"
echo "QD (expect 0): $(sc -I . -c $iso/QD.swift -o qd.o)"
echo "S  (expect 0): $(sc -I . -c $iso/S.swift -o s.o)"
xcrun swiftc -swift-version 6 -parse-as-library -default-isolation MainActor -module-name QFeature -emit-module -emit-module-path r/QFeature.swiftmodule -c "$iso/RFeature.swift" -o r/f.o
xcrun swiftc -swift-version 6 -parse-as-library -default-isolation MainActor -module-name QFeature -emit-module -emit-module-path r0/QFeature.swiftmodule -c "$iso/QFeature.swift" -o r0/f.o
echo "R1 (expect 0): $(sc -default-isolation MainActor -I r -c $iso/QA.swift -o r1.o)"
echo "R2 (expect 0): $(sc -I r -c $iso/QC.swift -o r2.o)"
echo "R0 (expect errors): $(sc -I r0 -c $iso/QC.swift -o r0.o)"
cd /; rm -rf "$work"
