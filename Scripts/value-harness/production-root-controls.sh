#!/bin/bash
# production-root-controls.sh OLDER_DIRECTORY CURRENT_TOOL LABEL REPORT_DIRECTORY
#
# Release acceptance over the production-root probes (production-root-probes.py): the older release, whose built
# `SafeDITool`, `SafeDIMacros-tool` and `SafeDIRuntimeSources` are in OLDER_DIRECTORY, against CURRENT_TOOL, and
# against CURRENT_TOOL's output broken three ways, each of which some probes must fail (class F). Every probe fails at
# least one control; a probe that stops failing every control no longer judges what it was written for. Run from a
# checkout whose test bundle is built (`swift build --build-tests --traits sourceBuild`), with `swiftc` on PATH and TMPDIR outside the
# checkout and the system temporary directory.
set -u
OLDER=$1; CURRENT=$2; LABEL=$3; REPORTS=$4
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/../.." && pwd)
mkdir -p "$REPORTS"
export SAFEDI_RELEASE_ACCEPTANCE_RELEASE=older SAFEDI_RELEASE_ACCEPTANCE_TOOL=$OLDER/SafeDITool \
  SAFEDI_RELEASE_ACCEPTANCE_MACROS_TOOL=$OLDER/SafeDIMacros-tool SAFEDI_RELEASE_ACCEPTANCE_RUNTIME_SOURCES=$OLDER/SafeDIRuntimeSources \
  SAFEDI_RELEASE_ACCEPTANCE_CORPUS=base SAFEDI_RELEASE_ACCEPTANCE_SHARD=0/1 \
  SAFEDI_RELEASE_ACCEPTANCE_CURRENT_MACROS_TOOL=$ROOT/.build/debug/SafeDIMacros-tool SAFEDI_RELEASE_ACCEPTANCE_CURRENT_RUNTIME_SOURCES=$ROOT/Sources/SafeDI \
  SAFEDI_RELEASE_ACCEPTANCE_FIXTURES=$(ls -d "$HERE"/production-root-probes/*/ | sed 's|/$||' | paste -sd: -) \
  MUTATE_ALL_FILES=1 MUTATE_REAL_TOOL=$CURRENT
run() { # NAME TOOL
  SAFEDI_RELEASE_ACCEPTANCE_REPORT=$REPORTS/$1.txt SAFEDI_RELEASE_ACCEPTANCE_CURRENT_TOOL=$2 SAFEDI_RELEASE_ACCEPTANCE_CURRENT_NAME=$1 \
    "$ROOT/.build/debug/SafeDIPackageTests.xctest" --testing-library swift-testing --filter 'SafeDIToolReleaseAcceptanceTests/longRun' > "$REPORTS/$1.log" 2>&1
}
cd "$ROOT"
run "$LABEL" "$CURRENT" &
# An instantiator hands out the instance its first call built.
MUTATE_PATTERN='(Sendable)?Instantiator<([^>\n]+)>\((__safeDI_\w+)\)' \
MUTATE_REPLACEMENT='{ let __once = \1LazilyInstantiated<\2>(\3); return \1Instantiator<\2> { __once.instance } }()' \
MUTATE_PATTERN2='(Sendable)?Instantiator<([^>\n]+)> \{\n\s*(__safeDI_\w+\([^)]*\))\n\s*\}' \
MUTATE_REPLACEMENT2='{ let __once = \1LazilyInstantiated<\2> { \3 }; return \1Instantiator<\2> { __once.instance } }()' \
  run "$LABEL-instantiator-shares" "$HERE/mutating-tool.py" &
# A lazy wrapper's instance is built up front.
MUTATE_PATTERN='let (\w+) = (Sendable)?LazilyInstantiated<(.+)>\((\w+)\)\n' \
MUTATE_REPLACEMENT='let __eager_\1 = \4(); let \1 = \2LazilyInstantiated<\3>({ __eager_\1 })\n' \
  run "$LABEL-lazy-eager" "$HERE/mutating-tool.py" &
# An optional binding is nil.
MUTATE_PATTERN='let (\w+): (.+\?) = (?!nil\n).+\n' MUTATE_REPLACEMENT='let \1: \2 = nil\n' \
  run "$LABEL-optional-nil" "$HERE/mutating-tool.py" &
wait
cd "$REPORTS"
for name in "$LABEL" "$LABEL-instantiator-shares" "$LABEL-lazy-eager" "$LABEL-optional-nil"; do
  echo "$name: $(grep -E '^classes' "$name.txt" 2>/dev/null || echo 'no report')"
done
# The seeds no control fails.
uncaught=$(join -j1 <(join -j1 <(grep '^seed' "$LABEL-instantiator-shares.txt" | awk '{print $2, $3}' | sort) <(grep '^seed' "$LABEL-lazy-eager.txt" | awk '{print $2, $3}' | sort)) <(grep '^seed' "$LABEL-optional-nil.txt" | awk '{print $2, $3}' | sort) | awk '$2 != "F" && $3 != "F" && $4 != "F" {print $1}' | sort -n | paste -sd, -)
echo "probes no control fails: ${uncaught:-none}"
