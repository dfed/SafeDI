#!/bin/zsh
# mkvariants.sh SHAPE_DIR VARIANT… : writes modules.txt and shared pointers. a = inline (tool), b = today (tool),
# anything else = hand-written Feature and App (VARIANT/<Module>/Generated/*.swift).
set -euo pipefail
d=${1:A}; shift
common=${0:A:h:h}/per-type-seam/common
for v in "$@"; do
  mkdir -p $d/$v/Harness $d/$v/Main $d/$v/App
  print -r -- ${common:A} | python3 -c "import os,sys;print(os.path.relpath(sys.stdin.read().strip(), '$d'))" >$d/$v/Harness/shared
  print main >$d/$v/Main/shared
  if [[ $v == a ]]; then
    print shared/Inline >$d/$v/App/shared
    printf 'Harness plain\nApp tool Harness\nMain plain App Harness\n' >$d/$v/modules.txt
  else
    mkdir -p $d/$v/Feature; print shared/Feature >$d/$v/Feature/shared; print shared/App >$d/$v/App/shared
    mode=hand; [[ $v == b ]] && mode=tool
    printf "Harness plain\nFeature $mode Harness\nApp $mode Feature Harness\nMain plain App Harness\n" >$d/$v/modules.txt
  fi
done
