#!/bin/zsh
# ./CLI/lint.sh          formats the repository with SwiftFormat (commit the result in its own commit).
# ./CLI/lint.sh --check  reports what formatting would change and exits non-zero; changes nothing.
# Both run a release build, as CI's "Lint Swift" job does: SwiftFormat stops a file with "rule timed out" when one rule
# is still running after 1 to 2 times (1 second plus 1 millisecond per token) of wall-clock time, which a debug build
# can overrun on large files.
set -e
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
