#!/bin/bash
# Scripts/changed-line-coverage.sh [BASE]   (default upstream/main, or origin/main where no `upstream` remote exists)
# Runs the full suite with coverage as CI does and prints every added or changed line under Sources/ and Plugins/
# that no test executed (the lines changed since the merge base with BASE, so a BASE that has moved on adds none of
# its own), then every Swift file there that the change adds, renames or edits and the report does not
# record (a file of declarations only), which "Check Line Coverage on Linux" fails on unless
# Scripts/unmeasured-files.txt lists it. The plugin compiles SafeDICore and SafeDIToolLibrary files through symlinks;
# a line counts as executed when either copy executed it. Exit 1 when any line is unexecuted or any such file is
# unrecorded. SAFEDI_SKIP_COMPILE_CHECK=1 and SAFEDI_COMPILE_CHECK_PASSED_CACHE are honored; neither changes what
# coverage counts.
# A failing test does not stop the report: the lines are reported from what the tests that ran executed, and the
# script then exits with `swift test`'s status. A test process that crashed wrote no counts, so its lines read as
# unexecuted.
# SwiftPM's native build system, as CI uses: it links every test target into one SafeDIPackageTests.xctest, where
# Swift Build, the default from Swift 6.4, builds one bundle per test target and this script would find none.
# Bash, not zsh, so that it runs unchanged in a Linux container, which has no zsh.
set -euo pipefail
root=$(git rev-parse --show-toplevel); cd "$root"
main=origin/main; git rev-parse --verify --quiet upstream/main >/dev/null && main=upstream/main
base=$(git merge-base "${1:-$main}" HEAD)
test_status=0
swift test --build-system native -c release --enable-code-coverage -Xswiftc -enable-testing -Xswiftc -Xllvm -Xswiftc -instrprof-atomic-counter-update-all --traits sourceBuild || test_status=$?
bin=$(swift build --build-system native -c release --traits sourceBuild --show-bin-path)
# On Linux the .xctest is the executable; on macOS it is a bundle that holds it. Name the path: the bundle's debug
# symbols hold a file of the same name, which llvm-cov cannot load.
if [[ -f "$bin/SafeDIPackageTests.xctest" ]]; then
	executable="$bin/SafeDIPackageTests.xctest"
else
	executable="$bin/SafeDIPackageTests.xctest/Contents/MacOS/SafeDIPackageTests"
fi
if [[ ! -f "$executable" ]]; then
	echo "no test executable at $executable: the build made no SafeDIPackageTests.xctest" >&2
	if (( test_status != 0 )); then exit $test_status; else exit 2; fi
fi
llvm_cov=(llvm-cov); llvm_profdata=(llvm-profdata)
if command -v xcrun >/dev/null 2>&1; then llvm_cov=(xcrun llvm-cov); llvm_profdata=(xcrun llvm-profdata); fi
profile="$bin/codecov/default.profdata"
if (( test_status != 0 )); then
	# SwiftPM empties the directory before a run and merges the raw profiles only when every test passes, so merge
	# what this run wrote.
	echo "swift test exited $test_status; reporting coverage from the tests that ran" >&2
	shopt -s nullglob; raw_profiles=("$bin"/codecov/*.profraw); shopt -u nullglob
	if (( ${#raw_profiles[@]} == 0 )); then
		echo "no raw profile in $bin/codecov: the tests did not run, so there is nothing to report" >&2
		exit $test_status
	fi
	"${llvm_profdata[@]}" merge -sparse "${raw_profiles[@]}" -o "$profile"
fi
mkdir -p .build/coverage
"${llvm_cov[@]}" export -format=lcov "$executable" -instr-profile "$profile" >.build/coverage/full.lcov
report_status=0
git diff --name-only --diff-filter=ACMR "$base" -- 'Sources/*.swift' 'Plugins/*.swift' >.build/coverage/changed-files.txt
git diff -U0 --no-color "$base" -- 'Sources/*.swift' 'Plugins/*.swift' | python3 Scripts/changed-line-coverage.py --files .build/coverage/changed-files.txt .build/coverage/full.lcov || report_status=$?
if (( test_status != 0 )); then exit $test_status; fi
exit $report_status
