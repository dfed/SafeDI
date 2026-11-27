#!/bin/bash
# Usage: record-and-review.sh --base REF --approved FILE [--rules FILE] [--base-env NAME=VALUE]… [--head-env NAME=VALUE]…
#                             [--filter FILTER]… [--fast] [--apply] [--runner COMMAND] OUT
#
# One command for a change that alters generated code: records the tests' outputs on the old generator (REF, with this
# checkout's Tests/) and on this checkout, both at once, rewrites the expectations with regenerate-expectations.py,
# and sorts every changed output with review-expectation-diffs.py against the approved-differences file. OUT, which
# must not exist, gets base/, head/ (the records and each run's log), regenerate/ and review/ (the two reports).
#
#   --base REF        the old generator. When REF is this checkout's HEAD and only the environment differs (a switch
#                     the change turns on), one build serves both runs.
#   --base-env, --head-env   environment for one run only, such as a layout switch.
#   --filter          passed to `swift test --filter`; repeat it. Default: every test.
#   --fast            records without compile verification (SAFEDI_SKIP_COMPILE_CHECK=1), for a first pass. The tests
#                     that read compileVerificationIsEnabled record nothing then, and regenerate-expectations lists them;
#                     the final run with compile checks on (CI's) is what settles the change.
#   --apply           rewrites the expectations in this checkout; without it both reports are written and no test changes.
#   --rules           regenerate-expectations.py's rules file (renames and rewrites the change predicts). Default: none.
#   --runner          a command put before each `swift test`, for a machine that queues heavy work.
#
# Base records are cached by what decides them (the base's Sources/, Plugins/ and Package files, this checkout's Tests/,
# the base environment and --fast) under $SAFEDI_RECORD_CACHE (default ~/Library/Caches/SafeDITests/records), so
# every lane of a stack that merges the same base records it once. Exit status: review-expectation-diffs.py's (0 when
# every changed output is on the approved list, 1 when a new class needs a person), or 2 when a step failed.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checkout="$(git rev-parse --show-toplevel)"
base_ref=""; approved=""; rules=""; fast=0; apply=0; runner=""; out=""
base_env=(); head_env=(); filters=()
while [ $# -gt 0 ]; do
	case "$1" in
		--base) base_ref="$2"; shift 2 ;;
		--approved) approved="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; shift 2 ;;
		--rules) rules="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; shift 2 ;;
		--base-env) base_env+=("$2"); shift 2 ;;
		--head-env) head_env+=("$2"); shift 2 ;;
		--filter) filters+=(--filter "$2"); shift 2 ;;
		--fast) fast=1; shift ;;
		--apply) apply=1; shift ;;
		--runner) runner="$2"; shift 2 ;;
		-h|--help) sed -n '2,/^set /p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
		-*) echo "error: unknown option $1" >&2; exit 2 ;;
		*) out="$1"; shift ;;
	esac
done
if [ -z "$base_ref" ] || [ -z "$approved" ] || [ -z "$out" ]; then
	echo "error: --base, --approved and OUT are required (see --help)" >&2; exit 2
fi
if [ -e "$out" ]; then echo "error: $out exists" >&2; exit 2; fi
mkdir -p "$out"; out="$(cd "$out" && pwd)"
system_temporary="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
case "$(cd "$out" && pwd -P)/" in
	"$checkout"/*|"$system_temporary"/*|/tmp/*|/private/tmp/*|/private/var/folders/*)
		echo "error: OUT must be outside the checkout and the system temporary directory, which the recording refuses" >&2; exit 2 ;;
esac
base_commit="$(git -C "$checkout" rev-parse --verify "$base_ref^{commit}")"

# SwiftPM's temporary folders go to a folder of this run's own, outside the checkout and the system temporary directory.
export TMPDIR="$out/tmp"; mkdir -p "$TMPDIR"
trap 'rm -rf "$out/tmp"' EXIT

# What decides the base records.
tests_digest="$(cd "$checkout" && find Tests -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-64)"
source_trees="$(git -C "$checkout" rev-parse "$base_commit:Sources" "$base_commit:Plugins" "$base_commit:Package.swift")"
key="$(printf '%s\n' "$source_trees" "$tests_digest" "fast=$fast" "${base_env[@]+"${base_env[@]}"}" "${filters[@]+"${filters[@]}"}" | sha256sum | cut -c1-32)"
cache="${SAFEDI_RECORD_CACHE:-$HOME/Library/Caches/SafeDITests/records}/$key"

same_commit=0
if [ "$base_commit" = "$(git -C "$checkout" rev-parse HEAD)" ] && git -C "$checkout" diff --quiet HEAD -- Sources Plugins Package.swift; then
	same_commit=1
fi

record() { # record NAME CHECKOUT BUNDLE ENV…
	local name="$1" directory="$2" bundle="$3"; shift 3
	mkdir -p "$out/$name/records"
	local environment=(SAFEDI_TEST_RECORD_DIRECTORY="$out/$name/records" "$@")
	if [ "$fast" = 1 ]; then environment+=(SAFEDI_SKIP_COMPILE_CHECK=1); fi
	# SwiftPM lets one `swift test` at a time use a build directory, so on Linux the test bundle runs directly, which
	# lets both runs of one commit go at once. Elsewhere `swift test` runs it, and the second run waits for the first.
	if [ "$(uname)" = Linux ] && [ -x "$bundle" ]; then
		(cd "$directory" && env "${environment[@]}" $runner "$bundle" ${filters[@]+"${filters[@]}"} --testing-library swift-testing \
			>"$out/$name/test.log" 2>&1) || true
	else
		(cd "$directory" && env "${environment[@]}" $runner swift test --traits sourceBuild --skip-build \
			${filters[@]+"${filters[@]}"} >"$out/$name/test.log" 2>&1) || true
	fi
	python3 -I "$checkout/.claude/skills/regenerate-expectations/regenerate-expectations.py" \
		--write-manifest "$out/$name/records" --checkout "$checkout" >/dev/null
}

start=$(date +%s)
base_checkout="$checkout"
if [ "$same_commit" = 0 ]; then
	base_checkout="$out/base-checkout"
	git -C "$checkout" worktree add --detach "$base_checkout" "$base_commit" >/dev/null 2>&1
	trap 'rm -rf "$out/tmp"; git -C "$checkout" worktree remove --force "$base_checkout" >/dev/null 2>&1 || true' EXIT
	rm -rf "$base_checkout/Tests"; cp -R "$checkout/Tests" "$base_checkout/Tests"
fi

builds=()
(cd "$checkout" && $runner swift build --build-tests --traits sourceBuild >"$out/head-build.log" 2>&1) & builds+=($!)
if [ "$same_commit" = 0 ] && [ ! -d "$cache" ]; then
	(cd "$base_checkout" && $runner swift build --build-tests --traits sourceBuild >"$out/base-build.log" 2>&1) & builds+=($!)
fi
for pid in "${builds[@]}"; do wait "$pid" || { echo "error: a build failed; see $out/*-build.log" >&2; exit 2; }; done
echo "built in $(( $(date +%s) - start ))s"
bundle_of() { echo "$(cd "$1" && swift build --traits sourceBuild --show-bin-path)/SafeDIPackageTests.xctest"; }
head_bundle="$(bundle_of "$checkout")"

runs=()
if [ -d "$cache" ]; then
	mkdir -p "$out/base"; cp -R "$cache" "$out/base/records"; cp "$cache.log" "$out/base/test.log" 2>/dev/null || true
	python3 -I "$checkout/.claude/skills/regenerate-expectations/regenerate-expectations.py" \
		--write-manifest "$out/base/records" --checkout "$checkout" >/dev/null
	echo "base records from the cache ($cache)"
else
	record base "$base_checkout" "$(bundle_of "$base_checkout")" ${base_env[@]+"${base_env[@]}"} & runs+=($!)
fi
record head "$checkout" "$head_bundle" ${head_env[@]+"${head_env[@]}"} & runs+=($!)
for pid in "${runs[@]}"; do wait "$pid"; done
echo "recorded in $(( $(date +%s) - start ))s"
if [ ! -d "$cache" ]; then
	mkdir -p "$(dirname "$cache")"; cp -R "$out/base/records" "$cache.partial" && mv "$cache.partial" "$cache"
	cp "$out/base/test.log" "$cache.log"
fi

# The tests that failed on the head, which are the ones whose expectations a person reviews.
grep -oE '^✘ Test [A-Za-z0-9_]+\(' "$out/head/test.log" | sed -E 's/^✘ Test //; s/\($//' | sort -u >"$out/head/failed-tests.txt" || true

if [ -z "$rules" ]; then rules="$out/no-rules.json"; echo '{"rename": [], "rewrite": [], "normalize": []}' >"$rules"; fi
regenerate=(--base-records "$out/base/records" --head-records "$out/head/records" --rules "$rules" --report "$out/regenerate" --checkout "$checkout")
if [ "$apply" = 0 ]; then regenerate+=(--dry-run); fi
if [ "$fast" = 1 ]; then regenerate+=(--allow-compile-skipped-records); fi
(cd "$checkout" && python3 -I .claude/skills/regenerate-expectations/regenerate-expectations.py "${regenerate[@]}" >"$out/regenerate.log" 2>&1) \
	|| [ $? = 1 ] || { echo "error: regenerate-expectations failed; see $out/regenerate.log" >&2; exit 2; }
status=0
python3 -I "$here/review-expectation-diffs.py" --base-records "$out/base/records" --head-records "$out/head/records" \
	--approved "$approved" --report "$out/review" --failed-tests "$out/head/failed-tests.txt" || status=$?
echo "done in $(( $(date +%s) - start ))s: read $out/review/report.txt, then $out/regenerate/report.txt"
exit "$status"
