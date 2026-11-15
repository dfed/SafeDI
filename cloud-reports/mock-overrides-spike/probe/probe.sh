#!/bin/bash
# [NONISOLATED=1] probe.sh TOOL BIN OUT [extra swiftc flags...]: generate Lib then App, compile both with -warnings-as-errors.
set -euo pipefail
tool=$1 bin=$2 out=$3; shift 3
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out"
macros=$bin/SafeDIMacros-tool; [[ -f $macros ]] || macros=$bin/SafeDIMacros
for m in Lib App; do
  printf '%s' "$here/$m.swift" > "$out/$m.csv"
  deps=(); [[ $m == App ]] && { printf '%s' "$out/Lib.safedi" > "$out/App.deps"; deps=(--dependent-module-info-file-path "$out/App.deps"); }
  "$tool" generate "$out/$m.csv" --combined-output "$out/$m.gen.swift" --module-info-output "$out/$m.safedi" --module-name $m --package-name p$m "${deps[@]}" --active-compilation-conditions DEBUG
  # NONISOLATED=1: the planned `nonisolated` on every internal SafeDIOverrides and SafeDIMockConfiguration.
  [[ -n ${NONISOLATED:-} ]] && sed -i -E 's/^( *)struct (SafeDIOverrides|SafeDIMockConfiguration) \{/\1nonisolated struct \2 {/' "$out/$m.gen.swift"
  swiftc -emit-object -whole-module-optimization -parse-as-library -Onone -o "$out/$m.o" -module-name $m -package-name p$m \
    -emit-module -emit-module-path "$out/$m.swiftmodule" -I "$bin/Modules" -I "$out" \
    -load-plugin-executable "$macros#SafeDIMacros" -swift-version 6 -DDEBUG -warnings-as-errors "$@" "$here/$m.swift" "$out/$m.gen.swift"
done
echo "probe ok: $*"
# Link and run the probe (plain builds only: the library evolution SafeDI is a static archive).
objects=("$bin"/SafeDI.build/*.o); [[ -e ${objects[0]} ]] || objects=("$bin/libSafeDI.a")
swiftc -o "$out/probe" "$out/Lib.o" "$out/App.o" "${objects[@]}"
"$out/probe" > "$out/observable.txt"
cat "$out/observable.txt"
