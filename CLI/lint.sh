#!/bin/zsh
# ./CLI/lint.sh          formats the repository with SwiftFormat (commit the result in its own commit).
# ./CLI/lint.sh --check  reports what formatting would change and exits non-zero; changes nothing.
# Both run a release build, as CI's "Lint Swift" job does: SwiftFormat stops a file with "rule timed out" when one rule
# is still running after 1 to 2 times (1 second plus 1 millisecond per token) of wall-clock time, which a debug build
# can overrun on large files.
set -e
# Without swift nothing below can run. Say so loudly and fail, so that a run whose output is piped (`./CLI/lint.sh | tail`
# reports tail's status unless the shell sets pipefail) cannot be read as a pass.
if ! command -v swift >/dev/null 2>&1; then
	print -u2 "error: ./CLI/lint.sh did NOT run: swift is not on PATH."
	print -u2 "error: Nothing was formatted or checked. Add a Swift toolchain to PATH and run it again."
	exit 127
fi
pushd "$(git rev-parse --show-toplevel)" >/dev/null
# SwiftPM leaves TemporaryDirectory.* folders in $TMPDIR on every run, and macOS empties the system temp folder at boot.
mkdir -p CLI/.build
export TMPDIR="$(mktemp -d "$PWD/CLI/.build/lint-tmp.XXXXXX")/"
trap 'rm -rf "$TMPDIR"' EXIT
if [[ "${1:-}" == "--check" ]]; then
	swift run -c release --package-path CLI swiftformat --lint .
else
	swift run -c release --package-path CLI swiftformat .
fi
popd >/dev/null
