#!/bin/zsh
# Runs every Stage 1 fixture of the spike. Needs Swift 6.2 on PATH and `swift build --traits sourceBuild` done at the
# checkout's root. Build output goes to ${SPIKE_OUTPUT:-~/.cache/per-type-seam-spike}.
set -euo pipefail
here=${0:A:h}
for fixture in F1 F2 F4 F6 F5 F3; do
	[[ -x "$here/$fixture/run.sh" ]] || continue
	echo "=== $fixture"
	"$here/$fixture/run.sh"
done
