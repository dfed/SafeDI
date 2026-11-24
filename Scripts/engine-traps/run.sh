#!/bin/bash
# Runs every trap graph under this directory against one build of SafeDI and prints what each probe observed.
#
#   Scripts/engine-traps/run.sh BUILD_BIN_DIRECTORY [TRAP…]
#
# A trap is a directory holding `Fixture.swift` (the graph), `main.swift` (top-level code that builds the mock and
# prints what each place was handed) and `expected.txt` (what the probe prints when every place is handed its own
# value, recorded from the per-path emitter). The script generates the module with BUILD_BIN_DIRECTORY's SafeDITool,
# compiles fixture, generated code and probe into one executable, runs it, and compares. It keeps each trap's generated
# code in OUT/<trap>/Generated.swift, so a failing trap's wrong output is at hand.
set -uo pipefail
bin=$(cd "$1" && pwd); shift
here=$(cd "$(dirname "$0")" && pwd)
out=${ENGINE_TRAPS_OUT:-$HOME/engine-traps-out/default}
modules="$bin/Modules"; [[ -e "$modules/SafeDI.swiftmodule" ]] || modules="$bin"
macros=""
for candidate in "$bin/SafeDIMacros-tool" "$bin/SafeDIMacros"; do [[ -f "$candidate" ]] && { macros=$candidate; break; }; done
[[ -n "$macros" ]] || { echo "no SafeDIMacros executable in $bin" >&2; exit 2; }
traps=("$@"); (( ${#traps[@]} )) || traps=($(cd "$here" && ls -d */ | tr -d /))
status=0
for trap in "${traps[@]}"; do
	directory="$here/$trap"; work="$out/$trap"; rm -rf "$work"; mkdir -p "$work"
	printf '%s' "$directory/Fixture.swift" >"$work/inputs.csv"
	if ! "$bin/SafeDITool" generate "$work/inputs.csv" --combined-output "$work/Generated.swift" \
		--compiler-receives-input-paths-unchanged --module-name Trap --active-compilation-conditions DEBUG >"$work/generate.log" 2>&1; then
		echo "GENERATE-ERROR $trap (see $work/generate.log)"; status=1; continue
	fi
	if ! swiftc -o "$work/probe" -module-name Trap -I "$modules" -load-plugin-executable "$macros#SafeDIMacros" \
		-swift-version 6 -D DEBUG -Onone "$directory/Fixture.swift" "$work/Generated.swift" "$directory/main.swift" \
		"$bin"/SafeDI.build/*.o >"$work/compile.log" 2>&1; then
		echo "COMPILE-ERROR $trap (see $work/compile.log)"; status=1; continue
	fi
	"$work/probe" >"$work/actual.txt" 2>&1
	if [[ ! -f "$directory/expected.txt" ]]; then
		echo "RECORDED $trap"; cp "$work/actual.txt" "$directory/expected.txt"
	elif diff -u "$directory/expected.txt" "$work/actual.txt" >"$work/diff.txt"; then
		echo "ok $trap ($(wc -l <"$work/Generated.swift") generated lines)"
	else
		echo "WRONG-VALUE $trap"; cat "$work/diff.txt"; status=1
	fi
done
exit $status
