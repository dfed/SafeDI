#!/bin/bash
# Scripts/changed-line-coverage.sh [--full] [--compile-checks] [--first REGEX]… [--first-only] [BASE]
# (BASE defaults to upstream/main, or origin/main where no `upstream` remote exists)
# Prints every added or changed line under Sources/ and Plugins/ that no test executed (the lines changed since the
# merge base with BASE, so a BASE that has moved on adds none of its own), then every Swift file there that the
# change adds, renames or edits and the report does not record (a file of declarations only), which "Check Line
# Coverage on Linux" fails on unless Scripts/unmeasured-files.txt lists it. The plugin compiles SafeDICore and
# SafeDIToolLibrary files through symlinks; a line counts as executed when either copy executed it. Exit 1 when any
# line is unexecuted or any such file is unrecorded.
#
# It runs as few tests as answer the question. A line one test executes stays executed whatever else runs, so the
# script first runs only the suites the change itself touches (each `Tests/**/<Suite>Tests.swift` the change adds or
# edits, by the file's name; or, where --first REGEX is given, only the tests those `swift test --filter` patterns name). When those execute every
# changed line, that is the answer and nothing else runs. Otherwise it runs every other test, adds the two runs'
# counts, and reports from both. --full runs the whole suite at once, as before. A change that touches no test file
# and names no --first runs the whole suite.
#
# Generated code is not compiled (SAFEDI_SKIP_COMPILE_CHECK is set unless the caller set it): compiling it is most
# of the suite's time and changes nothing coverage counts. --compile-checks compiles it, which makes the run a full
# test run as well; SAFEDI_COMPILE_CHECK_PASSED_CACHE is then honored. --first-only runs the suites the change touches
# (or the --first patterns) and nothing else, and reports no lines: with --compile-checks it is the test verdict of
# those suites with their generated code compiled, which a run that skips the compile cannot give.
#
# So a green exit says the changed lines are covered, and that the tests that ran passed; it does not say the suite
# passes. A failing test does not stop the report: the lines are reported from what the tests that ran executed, and
# the script then exits with `swift test`'s status. A test process that crashed wrote no counts, so its lines read as
# unexecuted.
# SwiftPM's native build system, as CI uses: it links every test target into one SafeDIPackageTests.xctest, where
# Swift Build, the default from Swift 6.4, builds one bundle per test target and this script would find none.
# Bash, not zsh, so that it runs unchanged in a Linux container, which has no zsh. Bash 3.2 (macOS) runs it: there,
# under `set -u`, expanding an empty array is an "unbound variable" error, so an array that can be empty is expanded
# as ${name[@]+"${name[@]}"}.
set -euo pipefail
full=0; compile_checks=0; first_only=0; first=(); base_argument=
while (( $# > 0 )); do
	case "$1" in
		--full) full=1 ;;
		--compile-checks) compile_checks=1 ;;
		--first-only) first_only=1 ;;
		--first)
			if (( $# < 2 )); then echo "--first needs a pattern" >&2; exit 2; fi
			first+=("$2"); shift ;;
		-*) echo "unknown option $1" >&2; exit 2 ;;
		*) base_argument=$1 ;;
	esac
	shift
done
root=$(git rev-parse --show-toplevel); cd "$root"
main=origin/main; git rev-parse --verify --quiet upstream/main >/dev/null && main=upstream/main
base=$(git merge-base "${base_argument:-$main}" HEAD)
if (( compile_checks )); then
	unset SAFEDI_SKIP_COMPILE_CHECK
else
	export SAFEDI_SKIP_COMPILE_CHECK="${SAFEDI_SKIP_COMPILE_CHECK:-1}"
fi
mkdir -p .build/coverage; rm -f .build/coverage/report.txt .build/coverage/status.txt .build/coverage/full.lcov .build/coverage/*.profdata
git diff --name-only --diff-filter=ACMR "$base" -- 'Sources/*.swift' 'Plugins/*.swift' >.build/coverage/changed-files.txt
# The suites the change touches: a test file is named for the suite it holds.
if (( ${#first[@]} == 0 )); then
	while IFS= read -r test_file; do
		suite=$(basename "$test_file" .swift)
		first+=("\\.${suite}/")
	done < <(git diff --name-only --diff-filter=ACMR "$base" -- 'Tests/*Tests.swift')
fi
if (( first_only && ${#first[@]} == 0 )); then
	echo "the change touches no test file, so there is no suite to run" >&2
	echo "tests=0 report=0" >.build/coverage/status.txt
	exit 0
fi
if (( ${#first[@]} == 0 )); then full=1; fi
swift_test=(swift test --build-system native -c release --enable-code-coverage -Xswiftc -enable-testing -Xswiftc -Xllvm -Xswiftc -instrprof-atomic-counter-update-all --traits sourceBuild)
bin=$(swift build --build-system native -c release --traits sourceBuild --show-bin-path)
llvm_cov=(llvm-cov); llvm_profdata=(llvm-profdata)
if command -v xcrun >/dev/null 2>&1; then llvm_cov=(xcrun llvm-cov); llvm_profdata=(xcrun llvm-profdata); fi
profiles=()
test_status=0

# run_tests NAME [swift test arguments…]: runs the tests and keeps the run's counts in .build/coverage/NAME.profdata,
# because SwiftPM empties its own directory before the next run and merges the raw profiles only when every test
# passes.
run_tests() {
	local name=$1 status=0; shift
	"${swift_test[@]}" "$@" || status=$?
	if (( status != 0 )); then
		test_status=$status
		echo "swift test exited $status; reporting coverage from the tests that ran" >&2
	fi
	shopt -s nullglob; local raw_profiles=("$bin"/codecov/*.profraw); shopt -u nullglob
	if (( ${#raw_profiles[@]} > 0 )); then
		"${llvm_profdata[@]}" merge -sparse "${raw_profiles[@]}" -o ".build/coverage/$name.profdata"
	elif [[ -f "$bin/codecov/default.profdata" ]]; then
		cp "$bin/codecov/default.profdata" ".build/coverage/$name.profdata"
	else
		# A pattern that matches no test starts no test process.
		echo "no profile in $bin/codecov: this run executed no test" >&2
		return
	fi
	profiles+=(".build/coverage/$name.profdata")
}

# report: writes the changed lines no kept run executed to .build/coverage/report.txt; its status is the report's.
report() {
	local executable
	# On Linux the .xctest is the executable; on macOS it is a bundle that holds it. Name the path: the bundle's
	# debug symbols hold a file of the same name, which llvm-cov cannot load.
	if [[ -f "$bin/SafeDIPackageTests.xctest" ]]; then
		executable="$bin/SafeDIPackageTests.xctest"
	else
		executable="$bin/SafeDIPackageTests.xctest/Contents/MacOS/SafeDIPackageTests"
	fi
	if [[ ! -f "$executable" ]]; then
		echo "no test executable at $executable: the build made no SafeDIPackageTests.xctest" >&2
		if (( test_status != 0 )); then exit $test_status; else exit 2; fi
	fi
	if (( ${#profiles[@]} == 0 )); then
		echo "no test ran, so there is nothing to report" >&2
		if (( test_status != 0 )); then exit $test_status; else exit 2; fi
	fi
	"${llvm_profdata[@]}" merge -sparse "${profiles[@]}" -o .build/coverage/merged.profdata || exit 2
	"${llvm_cov[@]}" export -format=lcov "$executable" -instr-profile .build/coverage/merged.profdata >.build/coverage/full.lcov || exit 2
	git diff -U0 --no-color "$base" -- 'Sources/*.swift' 'Plugins/*.swift' | python3 Scripts/changed-line-coverage.py --files .build/coverage/changed-files.txt .build/coverage/full.lcov >.build/coverage/report.txt
}

if (( first_only )); then
	filters=()
	for pattern in ${first[@]+"${first[@]}"}; do filters+=(--filter "$pattern"); done
	echo "running only the ${#first[@]} suite patterns the change touches: ${first[*]-}" >&2
	run_tests first ${filters[@]+"${filters[@]}"}
	echo "tests=$test_status report=0" >.build/coverage/status.txt
	exit $test_status
fi

report_status=0
if (( full )); then
	run_tests all
	report || report_status=$?
else
	filters=(); skips=()
	for pattern in ${first[@]+"${first[@]}"}; do filters+=(--filter "$pattern"); skips+=(--skip "$pattern"); done
	echo "running the ${#first[@]} suite patterns the change touches first: ${first[*]-}" >&2
	run_tests first ${filters[@]+"${filters[@]}"}
	if (( ${#profiles[@]} > 0 )) && report; then
		echo "the suites the change touches execute every changed line; the other tests were not run" >&2
	else
		echo "the suites the change touches leave these; running every other test:" >&2
		if (( ${#profiles[@]} > 0 )); then cat .build/coverage/report.txt >&2; fi
		run_tests rest ${skips[@]+"${skips[@]}"}
		report || report_status=$?
	fi
fi
cat .build/coverage/report.txt
# Which of the two failed, for a caller that reads them apart: `swift test` and the report can both exit 1.
echo "tests=$test_status report=$report_status" >.build/coverage/status.txt
if (( test_status != 0 )); then exit $test_status; fi
exit $report_status
