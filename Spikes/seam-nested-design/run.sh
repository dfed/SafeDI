#!/bin/bash
# Compiles every probe under probes/ with the swiftc on PATH, against the real SafeDI runtime, which it builds first
# from Sources/SafeDI into build/rt.
# A probe holds, in build order, any of Lower.swift, Feature.swift, Mid.swift (each a library module of that name),
# then App.swift (an executable when EXPECT=run). conf: WHAT, EXPECT (run|compile|reject), DIAG, FLAGS, REQUIRED.
#
# A probe that fails only because this platform lacks an API it uses is reported as PLATFORM GAP, never as a pass.
# Every probe runs, whatever happens to the others. The script exits 0 unless a probe whose conf sets REQUIRED=yes did
# not do what it EXPECTs, a platform gap included.
set -u
ROOT="$(cd "$(dirname "$0")" && pwd)"
REPOSITORY="$(cd "$ROOT/../.." && pwd)"
RT="$ROOT/build/rt"
COMMON="-swift-version 6 -parse-as-library -wmo -diagnostic-style=llvm -package-name Pkg"
# An error that means the platform lacks something, rather than that the probe's shape is wrong.
PLATFORM_ERRORS="no such module|is only available|is unavailable|cannot find '(NS|CF|CG|UI|os_|objc_|autoreleasepool|DispatchQueue)"
cd "$ROOT" || exit 0
echo "Compiler: $(swiftc --version 2>&1 | head -1)"
echo "Platform: $(uname -sm)"
echo

rm -rf "$RT"; mkdir -p "$RT"
find "$REPOSITORY/Sources/SafeDI" -name '*.swift' | LC_ALL=C sort > "$RT/sources"
# shellcheck disable=SC2046
if swiftc $COMMON -module-name SafeDI -emit-module -emit-module-path "$RT/SafeDI.swiftmodule" -emit-object -o "$RT/SafeDI.o" $(cat "$RT/sources") > "$RT/log" 2>&1; then
	echo "Runtime: built from $(wc -l < "$RT/sources" | tr -d ' ') files of Sources/SafeDI, warnings: $(grep -c ': warning:' "$RT/log")"
else
	echo "RUNTIME DID NOT BUILD, so every probe below that imports SafeDI is meaningless:"
	sed -e "s#$REPOSITORY/##g" -e 's/^/  /' "$RT/log"
fi
echo

only="${1:-}"
total=0; expected_results=0; surprises=0; platform_gaps=0; required_failures=0
for directory in probes/*/; do
	name="$(basename "$directory")"
	if [ -n "$only" ] && [ "$name" != "$only" ]; then continue; fi
	WHAT=""; EXPECT=""; DIAG=""; FLAGS=""; REQUIRED=""
	. "$directory/conf"
	total=$((total + 1))
	expected_results_before=$expected_results
	build="$ROOT/build/$name"; rm -rf "$build"; mkdir -p "$build"
	log="$build/log"; : > "$log"
	failed=0; objects=""
	for module in Lower Feature Mid; do
		if [ -f "$directory/$module.swift" ] && [ "$failed" -eq 0 ]; then
			swiftc $COMMON $FLAGS -I "$RT" -I "$build" -module-name $module -emit-module -emit-module-path "$build/$module.swiftmodule" -emit-object -o "$build/$module.o" "$directory/$module.swift" >> "$log" 2>&1 || failed=1
			objects="$objects $build/$module.o"
		fi
	done
	if [ "$failed" -eq 0 ] && [ -f "$directory/App.swift" ]; then
		if [ "$EXPECT" = "run" ]; then
			swiftc $COMMON $FLAGS -I "$RT" -I "$build" -module-name App -emit-executable -o "$build/app" "$directory/App.swift" $objects "$RT/SafeDI.o" >> "$log" 2>&1 || failed=1
		else
			swiftc $COMMON $FLAGS -I "$RT" -I "$build" -module-name App -emit-object -o "$build/App.o" "$directory/App.swift" >> "$log" 2>&1 || failed=1
		fi
	fi
	sed -e "s#$ROOT/##g" "$log" > "$log.rel"
	warnings=$(grep -c ': warning:' "$log.rel")
	# The expected text is looked for in the errors' messages only: a probe's directory name can contain it.
	grep 'error:' "$log.rel" > "$log.errors"
	sed -E -e 's/^(.*: )?error: //' "$log.errors" > "$log.messages"
	echo "=== $name: $WHAT"
	if grep -lE '^[[:space:]]*#(else)?if .*(os\(|canImport\(|targetEnvironment\()' "$directory"*.swift > "$log.guarded" 2>/dev/null; then
		echo "    PLATFORM-GUARDED CODE, which this platform may skip, in: $(tr '\n' ' ' < "$log.guarded")"
	fi
	if grep -qE -- "$PLATFORM_ERRORS" "$log.messages"; then
		echo "    PLATFORM GAP: uses something $(uname -s) does not have, so this probe says nothing about its shape here"
		platform_gaps=$((platform_gaps + 1))
		sed -e 's/^/      /' "$log.rel"
	elif [ "$EXPECT" = "reject" ]; then
		if [ "$failed" -eq 0 ]; then echo "    SURPRISE: compiled"; surprises=$((surprises + 1))
		elif grep -qF -- "$DIAG" "$log.messages"; then
			echo "    PASS (rejected):"; sed -e 's/^/      /' "$log.errors"
			expected_results=$((expected_results + 1))
		else echo "    SURPRISE: rejected without: $DIAG"; surprises=$((surprises + 1)); sed -e 's/^/      /' "$log.rel"; fi
	elif [ "$failed" -ne 0 ]; then echo "    SURPRISE: rejected"; surprises=$((surprises + 1)); sed -e 's/^/      /' "$log.rel"
	elif [ "$EXPECT" = "run" ]; then
		status=0
		output="$("$build/app" 2>&1)" || status=$?
		if [ "$status" -eq 0 ]; then
			echo "    PASS (ran), warnings: $warnings"
			expected_results=$((expected_results + 1))
		else
			echo "    SURPRISE: compiled, but the program exited with status $status"
			surprises=$((surprises + 1))
		fi
		echo "$output" | sed -e 's/^/      /'
		if [ "$warnings" -ne 0 ]; then grep -A3 ': warning:' "$log.rel" | sed -e 's/^/      /'; fi
	else
		echo "    PASS (compiled), warnings: $warnings"
		expected_results=$((expected_results + 1))
		if [ "$warnings" -ne 0 ]; then grep -A3 ': warning:' "$log.rel" | sed -e 's/^/      /'; fi
	fi
	if [ "$REQUIRED" = "yes" ] && [ "$expected_results" -eq "$expected_results_before" ]; then
		echo "    REQUIRED PROBE FAILED: the job fails"
		required_failures=$((required_failures + 1))
	fi
done
echo
echo "$total probes: $expected_results as expected, $surprises surprises, $platform_gaps platform gaps."
if [ "$required_failures" -ne 0 ]; then
	echo "$required_failures required probes failed."
	exit 1
fi
exit 0
