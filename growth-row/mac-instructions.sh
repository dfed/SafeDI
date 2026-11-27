#!/bin/zsh
# mac-instructions.sh CLONE COMMIT LABEL
# Builds SafeDITool at COMMIT (release, sourceBuild) in a worktree of CLONE, generates the fill-built shape E fixture
# (make-fixture.py, beside this script) at 3, 4 and 5 layers, and prints the instructions retired by the App module's
# `generate`, five runs per size, as /usr/bin/time -l reports them.
set -euo pipefail
clone=${1:A}; commit=$2; label=$3; here=${0:A:h}
base=~/Library/Caches/SafeDITests/growth-row; mkdir -p $base/swiftpm
worktree=$base/$label; fixture=$base/fixture; out=$base/out-$label
[[ -d $worktree ]] || git -C $clone worktree add --detach $worktree $commit
(cd $worktree && TMPDIR=$base/swiftpm swift build -c release --traits sourceBuild --product SafeDITool >&2)
tool=$(cd $worktree && TMPDIR=$base/swiftpm swift build -c release --traits sourceBuild --show-bin-path)/SafeDITool
[[ -d $fixture ]] || python3 -I $here/make-fixture.py $fixture
for n in 12 16 20; do
  mkdir -p $out/s$n
  for m in Inner App; do
    pkg=Shop; [[ $m == App ]] && pkg=Other
    print -rn -- ${(j:,:)$(print -l $fixture/s$n/$m/Sources/*.swift)} > $out/s$n/$m.csv
    args=($out/s$n/$m.csv --combined-output $out/s$n/$m.swift --compiler-receives-input-paths-unchanged --module-info-output $out/s$n/$m.safedi --module-name $m --package-name $pkg --active-compilation-conditions DEBUG)
    if [[ $m == App ]]; then print -rn -- $out/s$n/Inner.safedi > $out/s$n/App-dependencies.csv; args+=(--dependent-module-info-file-path $out/s$n/App-dependencies.csv); fi
    if [[ $m == Inner ]]; then $tool generate $args; continue; fi
    for run in 1 2 3 4 5; do
      /usr/bin/time -l $tool generate $args 2>&1 >/dev/null | awk -v label=$label -v n=$n '/instructions retired/ {print label, "layers", n/4, $1}'
    done
  done
done
TMPDIR=$base/swiftpm true; rm -rf $base/swiftpm/*
