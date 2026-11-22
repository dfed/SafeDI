#!/bin/bash
# usage: compile-check-identity.sh TEST_ARGUMENT…
#        compile-check-identity.sh --list-sources
#
# Prints the SHA-256 that names one list of passed compile checks
# (PassedCompileCheckCache.swift). A job keys its cache of passed checks on it,
# so a change to anything it covers starts from an empty list.
#
# A check's own key already covers what its result depends on: everything the
# check compiles, the compiler and SDK the test process finds, the bytes of
# the SafeDI module it loads, and the dependency versions the macro plugin it
# loads was built from (CompileCheckBuild). So no workflow file is hashed
# here, and a workflow edit keeps every passed check unless it changes one of
# those.
#
# What this hash adds is what decides which keys a run writes and shares: the
# sources of the compile verifier and its cache, the actions the test jobs
# restore and upload passed checks with, and this script. Runs on every branch
# read each other's passes of one identity (restore-shared-compile-checks), so
# a branch that changes how passes are written or read reads no other's.
#
# It also covers the sources of SafeDI's runtime library and macro plugin, the
# package manifest and its resolved dependencies, the arguments the test step
# builds with (TEST_ARGUMENT…), the compiler's version and default target, and
# on macOS the SDK. The macro plugin's own sources are covered only here: a
# key cannot hash the built plugin, whose bytes differ between two builds of
# the same sources. For the rest, each key covers them too, and hashing them
# here only keeps one build's list from growing with the keys of every other.
#
# The macro plugin compiles SafeDICore through a symbolic link, leaving out the
# files and directories its target's `exclude` in Package.swift lists: the
# generators and the rest of what only SafeDITool uses. Those are left out here
# too, read from that list. A check compiles the code SafeDITool generated, and
# the check's own key hashes each generated file's contents, so a change to a
# generator compiles again exactly the checks whose generated code it changes,
# and the rest keep their passed results.
#
# `--list-sources` prints the SafeDI sources the hash covers, one path per line
# in the order hashed, and nothing else: `MacroTargetSourceTests` compares them
# with the files the macro target compiles.
#
# Reads files rather than `git ls-tree`: in a container job, git refuses to read
# a checkout another user owns. Uses pipes rather than here-strings, which bash
# writes to a temporary file: a test runs this script, and tests write nothing
# to the system temporary directory.
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

# The SafeDICore files and directories the SafeDIMacros target leaves out, as
# paths from the repository root: the string literals of the `exclude` argument
# that follows `name: "SafeDIMacros"` in Package.swift.
macro_target_exclusions() {
	awk '
		/name: "SafeDIMacros",/ { in_target = 1 }
		in_target && /exclude: \[/ { in_list = 1; next }
		# A comment line names no exclusion, as SwiftPM reads it, and a `]` in one does not end the list.
		in_list && /^[[:space:]]*\/\// { next }
		in_list && /\]/ { exit }
		in_list && match($0, /"[^"]+"/) { print "Sources/SafeDIMacros/" substr($0, RSTART + 1, RLENGTH - 2) }
	' Package.swift | sed 's|^Sources/SafeDIMacros/SafeDICore/|Sources/SafeDICore/|'
}

# The Swift sources of SafeDI's runtime library and macro plugin, in path order.
# An exclusion that names nothing, or a list that leaves out no generator, means
# this script no longer reads Package.swift as it is written, so it fails rather
# than hash other files than the plugin compiles.
hashed_sources() {
	local exclusions exclusion
	exclusions=$(macro_target_exclusions)
	if ! echo "$exclusions" | grep -qx 'Sources/SafeDICore/Generators'; then
		echo "compile-check-identity.sh: found no SafeDICore/Generators in the exclude list of the SafeDIMacros target in Package.swift." >&2
		return 1
	fi
	# No path under Sources has a space, so the list splits into its paths.
	# shellcheck disable=SC2086
	for exclusion in $exclusions; do
		if [ ! -e "$exclusion" ]; then
			echo "compile-check-identity.sh: the SafeDIMacros target in Package.swift excludes $exclusion, which does not exist." >&2
			return 1
		fi
	done
	find Sources/SafeDI Sources/SafeDICore Sources/SafeDIMacros -type f -name '*.swift' \
		| LC_ALL=C sort \
		| awk '
			# The first input is the exclusions, the second the sources.
			NR == FNR {
				excluded[++count] = $0
				next
			}
			{
				for (position = 1; position <= count; position++) {
					if ($0 == excluded[position] || index($0, excluded[position] "/") == 1) {
						next
					}
				}
				print
			}
		' <(echo "$exclusions") -
}

# Assigned first, so that a failure stops the script instead of hashing less.
sources=$(hashed_sources)

# Prints the package manifest as this hash covers it. A release commit rewrites
# two of its lines and nothing else the hash covers: the address and checksum
# of the prebuilt SafeDITool, which the `prebuilt` trait downloads. A build
# with the `sourceBuild` trait compiles the tool from source and never reads
# them, so for such a build they are left out, and the first runs after a
# release keep every passed check: with them hashed, the release of 2.3.1
# compiled all 4,287 checks again on each platform, 41.5 minutes of tests on
# Linux and 68.7 on macOS against about 15 and 24 (run 44919892765). Any other
# build hashes the manifest whole. It fails, rather than hash a manifest it no
# longer reads as written, unless it leaves out exactly those two lines.
hashed_manifest() {
	case " $* " in
	*" --traits sourceBuild "*) ;;
	*)
		cat Package.swift
		return
		;;
	esac
	local prebuilt_tool='^[[:space:]]*(url: "https://github\.com/dfed/SafeDI/releases/download/[^"]*/SafeDITool\.artifactbundle\.zip"|checksum: "[0-9a-f]{64}"),$'
	if [ "$(grep -cE "$prebuilt_tool" Package.swift)" -ne 2 ]; then
		echo "compile-check-identity.sh: expected exactly two lines for the prebuilt SafeDITool's address and checksum in Package.swift." >&2
		return 1
	fi
	grep -vE "$prebuilt_tool" Package.swift
}

# Assigned first, for the same reason.
manifest=$(hashed_manifest "$@")

if [ "${1:-}" = --list-sources ]; then
	echo "$sources"
	exit 0
fi

{
	echo "Test arguments: $*"
	echo "$sources" | tr '\n' '\0' | sha256_of_files
	echo "Package.swift: $(echo "$manifest" | sha256 | cut -d ' ' -f 1)"
	printf '%s\0' \
		Package.resolved \
		Tests/SafeDIToolTestSupport/SafeDICompileVerifier.swift \
		Tests/SafeDIToolTestSupport/PassedCompileCheckCache.swift \
		Tests/SafeDIToolTestSupport/TestTemporaryDirectory.swift \
		.github/actions/restore-shared-compile-checks/action.yml \
		.github/actions/restore-shared-compile-checks/restore-from-artifacts.js \
		.github/actions/upload-passed-compile-checks/action.yml \
		.github/scripts/compile-check-identity.sh \
		| sha256_of_files
	"${swiftc[@]}" --version 2>&1
	"${swiftc[@]}" -print-target-info
	if command -v xcrun >/dev/null; then
		echo "SDK $(xcrun --show-sdk-version) ($(xcrun --show-sdk-build-version))"
	fi
} | sha256 | cut -d ' ' -f 1
