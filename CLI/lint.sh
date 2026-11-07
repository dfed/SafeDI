#!/bin/zsh
# ./CLI/lint.sh          formats the repository with SwiftFormat (commit the result in its own commit).
# ./CLI/lint.sh --check  reports what formatting would change and exits non-zero; changes nothing.
set -e
pushd "$(git rev-parse --show-toplevel)" >/dev/null
if [[ "${1:-}" == "--check" ]]; then
	swift run --package-path CLI swiftformat --lint .
else
	swift run --package-path CLI swiftformat .
fi
popd >/dev/null
