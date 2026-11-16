#!/bin/zsh
# mkv.sh DIR "Mod1 Mod2 … App" VARIANT… : a = inline, b = all tool, other = all hand (VARIANT/<Module>/Generated).
set -euo pipefail
d=${1:A}; mods=(${=2}); shift 2
common=${0:A:h:h}/per-type-seam/common
rel=$(python3 -c "import os;print(os.path.relpath('$common', '$d'))")
for v in "$@"; do
  mkdir -p $d/$v/Harness $d/$v/Main; print $rel >$d/$v/Harness/shared; print main >$d/$v/Main/shared
  if [[ $v == a ]]; then
    mkdir -p $d/$v/App; print shared/Inline >$d/$v/App/shared
    printf 'Harness plain\nApp tool Harness\nMain plain App Harness\n' >$d/$v/modules.txt; continue
  fi
  mode=hand; [[ $v == b ]] && mode=tool
  print "Harness plain" >$d/$v/modules.txt; previous=()
  for m in $mods; do
    mkdir -p $d/$v/$m/Generated; print shared/$m >$d/$v/$m/shared
    print "$m $mode ${previous[*]} Harness" >>$d/$v/modules.txt; previous+=($m)
  done
  print "Main plain ${(j: :)mods} Harness" >>$d/$v/modules.txt
done
