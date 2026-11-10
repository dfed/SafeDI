#!/bin/bash
# Compiles and runs every case of the seam builder spike with whichever swiftc is on PATH.
#
# Each directory under cases/ is one case. Its case.conf says what the case is and what to expect:
#   WHAT       one line describing the case
#   EXPECT     compile (must compile), run (must compile, link, run and print expected-output.txt), reject (must fail to compile)
#   FEATURE    optional: use shared/<FEATURE>/Feature.swift as module Feature instead of a Feature.swift in the case directory
#   FLAGS      optional: extra swiftc flags for every module of the case
#   APP        optional: use this source as module App instead of the App.swift in the case directory
#   DIAG       reject only: text the diagnostics must contain
#
# Each module is compiled in the Swift 6 language mode with -emit-object, so SIL diagnostics count.
# Every case runs, whatever happens to the others, and the script always exits 0.

set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
COMMON_FLAGS="-swift-version 6 -parse-as-library -wmo -diagnostic-style=llvm"

cd "$ROOT" || exit 0

echo "Compiler: $(swiftc --version 2>&1 | head -1)"
echo "Platform: $(uname -sm)"
echo

# The runtime stand-in, built once for each flavor. A case that sets FLAGS uses the flavor built with them.
build_support() { # directory, flags
	mkdir -p "$1"
	# shellcheck disable=SC2086
	swiftc $COMMON_FLAGS $2 -module-name SafeDI -emit-module -emit-module-path "$1/SafeDI.swiftmodule" -emit-object -o "$1/SafeDI.o" support/SafeDI.swift
}
build_support "$WORK/support-plain" "" || echo "FAILED to build support/SafeDI.swift"
build_support "$WORK/support-evolution" "-enable-library-evolution" || echo "FAILED to build support/SafeDI.swift with library evolution"

total=0
expected_results=0
surprises=0

for directory in cases/*/; do
	name="$(basename "$directory")"
	WHAT=""
	EXPECT=""
	FEATURE=""
	FLAGS=""
	DIAG=""
	APP=""
	# shellcheck disable=SC1090
	. "$directory/case.conf"
	if [ -z "$APP" ]; then
		APP="${directory}App.swift"
	fi
	total=$((total + 1))

	build="$WORK/$name"
	mkdir -p "$build"
	log="$build/log"
	: > "$log"

	if [ -n "$FLAGS" ]; then
		support="$WORK/support-evolution"
	else
		support="$WORK/support-plain"
	fi

	if [ -n "$FEATURE" ]; then
		feature_source="shared/$FEATURE/Feature.swift"
	else
		feature_source="${directory}Feature.swift"
	fi

	failed=0
	# shellcheck disable=SC2086
	swiftc $COMMON_FLAGS $FLAGS -I "$support" -module-name Feature -emit-module -emit-module-path "$build/Feature.swiftmodule" -emit-object -o "$build/Feature.o" "$feature_source" >> "$log" 2>&1 || failed=1
	if [ "$failed" -eq 0 ]; then
		if [ "$EXPECT" = "run" ]; then
			# shellcheck disable=SC2086
			swiftc $COMMON_FLAGS $FLAGS -I "$support" -I "$build" -module-name App -emit-executable -o "$build/app" "$APP" "$build/Feature.o" "$support/SafeDI.o" >> "$log" 2>&1 || failed=1
		else
			# shellcheck disable=SC2086
			swiftc $COMMON_FLAGS $FLAGS -I "$support" -I "$build" -module-name App -emit-object -o "$build/App.o" "$APP" >> "$log" 2>&1 || failed=1
		fi
	fi

	# Show paths relative to the spike, whatever the checkout's location.
	sed -e "s#$ROOT/##g" -e "s#$WORK/##g" "$log" > "$log.relative"
	warnings=$(grep -c ': warning:' "$log.relative")

	echo "=== $name"
	echo "    $WHAT"
	status=""
	output=""
	if [ "$EXPECT" = "reject" ]; then
		if [ "$failed" -eq 0 ]; then
			status="SURPRISE: expected a rejection, but it compiled"
			surprises=$((surprises + 1))
		elif grep -qF -- "$DIAG" "$log.relative"; then
			status="PASS (rejected, as expected)"
			expected_results=$((expected_results + 1))
		else
			status="SURPRISE: rejected, but without the expected text: $DIAG"
			surprises=$((surprises + 1))
		fi
	elif [ "$failed" -ne 0 ]; then
		status="SURPRISE: expected this to compile, but it was rejected"
		surprises=$((surprises + 1))
	elif [ "$EXPECT" = "run" ]; then
		if output="$("$build/app" 2>&1)"; then
			if [ "$output" = "$(cat "${directory}expected-output.txt")" ]; then
				status="PASS (compiled, ran, printed what was expected)"
				expected_results=$((expected_results + 1))
			else
				status="SURPRISE: compiled and ran, but printed something else"
				surprises=$((surprises + 1))
			fi
		else
			status="SURPRISE: compiled, but the program failed"
			surprises=$((surprises + 1))
		fi
	else
		status="PASS (compiled)"
		expected_results=$((expected_results + 1))
	fi
	if [ "$warnings" -ne 0 ] && [ "$EXPECT" != "reject" ]; then
		status="$status, WITH $warnings WARNING(S)"
	fi
	echo "    $status"
	if [ -n "$output" ]; then
		echo "    Printed:"
		echo "$output" | sed -e 's/^/      /'
	fi
	if [ -s "$log.relative" ]; then
		echo "    Diagnostics:"
		sed -e 's/^/      /' "$log.relative"
	fi
	echo
done

echo "$total cases: $expected_results as expected, $surprises surprises."
exit 0
