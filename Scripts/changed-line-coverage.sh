#!/bin/zsh
# Scripts/changed-line-coverage.sh [BASE]   (default origin/main)
# Runs the full suite with coverage as CI does and prints every added or changed line under Sources/ and Plugins/
# that no test executed. The plugin compiles SafeDICore and SafeDIToolLibrary files through symlinks; a line counts as
# executed when either copy executed it. Exit 1 when any line is unexecuted. SAFEDI_SKIP_COMPILE_CHECK=1 and
# SAFEDI_COMPILE_CHECK_PASSED_CACHE are honored; neither changes what coverage counts.
set -euo pipefail
base=${1:-origin/main}
root=$(git rev-parse --show-toplevel); cd "$root"
swift test -c release --enable-code-coverage -Xswiftc -enable-testing -Xswiftc -Xllvm -Xswiftc -instrprof-atomic-counter-update-all --traits sourceBuild
bin=$(swift build -c release --traits sourceBuild --show-bin-path)
# On Linux the .xctest is the executable; on macOS it is a bundle that holds it.
if [[ -f "$bin/SafeDIPackageTests.xctest" ]]; then
	executable="$bin/SafeDIPackageTests.xctest"
else
	executable=$(find "$bin/SafeDIPackageTests.xctest" -type f -name SafeDIPackageTests | head -1)
fi
profile=$(find "$bin/codecov" -name default.profdata | head -1)
llvm_cov=(llvm-cov); command -v xcrun >/dev/null 2>&1 && llvm_cov=(xcrun llvm-cov)
mkdir -p .build/coverage
"${llvm_cov[@]}" export -format=lcov "$executable" -instr-profile "$profile" >.build/coverage/full.lcov
git diff -U0 --no-color "$base" -- 'Sources/*.swift' 'Plugins/*.swift' | python3 Scripts/changed-line-coverage.py .build/coverage/full.lcov
