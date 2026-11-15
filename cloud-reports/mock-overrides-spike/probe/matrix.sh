#!/bin/bash
# matrix.sh TOOL...: the storage compile matrix, each with -warnings-as-errors in Swift 6 mode:
# the probe fixture and shape D at 8 screens, plain, under -default-isolation MainActor (with the planned nonisolated
# on every configuration struct; the nested types carry their own), and with library evolution.
here=$(cd "$(dirname "$0")" && pwd)
for tool in "$@"; do
  name=$(basename "$tool")
  for mode in plain mainactor evolution; do
    case $mode in
      plain) flags=(); bin=~/bin; ni= ;;
      mainactor) flags=(-default-isolation MainActor); bin=~/bin; ni=1 ;;
      evolution) flags=(-enable-library-evolution); bin=~/bin-le; ni= ;;
    esac
    if NONISOLATED=$ni "$here/probe.sh" "$tool" "$bin" ~/work/matrix-$name-$mode "${flags[@]}" > ~/work/matrix-$name-$mode.log 2>&1; then r=ok; else r="FAIL $(grep -m1 error: ~/work/matrix-$name-$mode.log)"; fi
    echo "$name probe $mode: $r"
    d=(); [[ -n $ni ]] && d=(--nonisolated)
    if python3 "$here/../run_d.py" --tool "$tool" --bin "$bin" --screens 8 --work ~/work/matrixD-$name-$mode "${d[@]}" --module-flags "-warnings-as-errors ${flags[*]}" > ~/work/matrixD-$name-$mode.log 2>&1; then r=ok; else r="FAIL $(grep -o -m1 'error: [^\\]*' ~/work/matrixD-$name-$mode.log | head -1)"; fi
    echo "$name shapeD-8 $mode: $r"
  done
done
