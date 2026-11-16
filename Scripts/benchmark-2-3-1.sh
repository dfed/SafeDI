#!/bin/bash
# Scripts/benchmark-2-3-1.sh [bench.py options] TOOL_A TOOL_B [FIXTURES]
#
# The 2.3.1 ship-bar benchmark: measures `SafeDITool generate` and the code it generates for two builds of the tool
# (TOOL_A, the baseline, and TOOL_B) on every shape in FIXTURES, and prints one table of medians with min–max and
# the ratio B / A, then every measure where B is slower, ranked by ratio.
#
# Each TOOL is the `SafeDITool` in the bin directory of a release build of its whole checkout, which must also hold
# SafeDI and the macros:   swift build -c release --product SafeDITool && swift build -c release --product SafeDI
#
# FIXTURES defaults to the synthetic shapes, written to ~/.cache/safedi-benchmark-2-3-1/fixtures by
# Scripts/benchmark-2-3-1/make_fixtures.py. Any directory in the same layout works (see bench.py's header), so a
# private fixture set runs through the same command.
#
# Options (bench.py): --runs N (default 5), --shapes a,b, --skip-shapes a,b, --measures generate,compile,runtime,
# --labels 2.2.0,main, --json FILE (every sample), --work DIR. Compare two runs' JSON with
#   python3 -I Scripts/benchmark-2-3-1/bench.py --compare RUN1.json RUN2.json
# Needs python3 and a Swift toolchain; on macOS, `generate`'s instructions retired come from /usr/bin/time -l.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
options=()
while (($#)) && [[ $1 == --* ]]; do
	case $1 in
	--runs | --shapes | --skip-shapes | --measures | --labels | --json | --work) options+=("$1" "$2"); shift 2 ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
done
(($# == 2 || $# == 3)) || { sed -n '2,20p' "$0" >&2; exit 2; }
fixtures=${3:-}
if [[ -z $fixtures ]]; then
	fixtures=$HOME/.cache/safedi-benchmark-2-3-1/fixtures
	python3 -I "$here/benchmark-2-3-1/make_fixtures.py" "$fixtures" --repository "$(dirname "$here")" >/dev/null
fi
# SwiftPM and swiftc leave temporary folders behind: keep them out of the system temporary directory.
export TMPDIR=${BENCHMARK_TMPDIR:-$HOME/.cache/safedi-benchmark-2-3-1/tmp}
mkdir -p "$TMPDIR"
# macOS bash 3.2 treats an empty array as unset under set -u.
exec python3 -I "$here/benchmark-2-3-1/bench.py" ${options[@]+"${options[@]}"} "$1" "$2" "$fixtures"
