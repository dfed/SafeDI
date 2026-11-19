#!/bin/bash
# n7 (review of the only-if-available nil fix): Root holds LazilyInstantiated<Session>; Feed's Screen receives it only if
# available as LazilyInstantiated<Session>?; App's Fill builds Screen again and instantiates Child, which receives
# Session by value. Generates and compiles both the two-module build and the same files as one module.
set -uo pipefail
cd "$(dirname "$0")"
mkdir -p out
"$SAFEDI_TOOL" --version || true
status=0
if "$SAFEDI_REPRO" Multi Feed App > out/multi.log 2>&1; then echo "multi: compiled"; else echo "multi: FAILED"; status=1; fi
if "$SAFEDI_REPRO" Inline All > out/inline.log 2>&1; then echo "inline: compiled"; else echo "inline: FAILED"; status=1; fi
cp -R Multi/.safedi-out out/multi-out 2>/dev/null || true
cp -R Inline/.safedi-out out/inline-out 2>/dev/null || true
echo "--- multi.log (errors)"; grep -nE 'error|warning: unreachable' out/multi.log | head -30
echo "--- inline.log (errors)"; grep -nE 'error' out/inline.log | head -30
exit $status
