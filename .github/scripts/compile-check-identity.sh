#!/bin/bash
# usage: compile-check-identity.sh TEST_ARGUMENT…
#
# Prints the SHA-256 of everything a compile check's result depends on that the
# check's own key leaves out (PassedCompileCheckCache.swift): the sources of
# SafeDI's runtime library and macro plugin (which compiles SafeDICore through a
# symbolic link), the package manifest and its resolved dependencies, the sources
# of the compile verifier and its cache, the arguments the test step builds with
# (TEST_ARGUMENT…), the compiler's version and default target, and on macOS the
# SDK. A job keys its cache of passed compile checks on this hash, so a change to
# any of these starts from an empty cache and compiles every check.
#
# Reads files rather than `git ls-tree`: in a container job, git refuses to read
# a checkout another user owns.
set -euo pipefail

cd "$(dirname "$0")/../.."

if command -v sha256sum >/dev/null; then
	sha256() { sha256sum; }
	sha256_of_files() { xargs -0 sha256sum; }
else
	sha256() { shasum -a 256; }
	sha256_of_files() { xargs -0 shasum -a 256; }
fi

if command -v xcrun >/dev/null; then
	swiftc=(xcrun swiftc)
else
	swiftc=(swiftc)
fi

{
	echo "Test arguments: $*"
	find Sources/SafeDI Sources/SafeDICore Sources/SafeDIMacros -type f -name '*.swift' -print0 \
		| LC_ALL=C sort -z \
		| sha256_of_files
	printf '%s\0' \
		Package.swift \
		Package.resolved \
		Tests/SafeDIToolTestSupport/SafeDICompileVerifier.swift \
		Tests/SafeDIToolTestSupport/PassedCompileCheckCache.swift \
		Tests/SafeDIToolTestSupport/TestTemporaryDirectory.swift \
		| sha256_of_files
	"${swiftc[@]}" --version 2>&1
	"${swiftc[@]}" -print-target-info
	if command -v xcrun >/dev/null; then
		echo "SDK $(xcrun --show-sdk-version) ($(xcrun --show-sdk-build-version))"
	fi
} | sha256 | cut -d ' ' -f 1
