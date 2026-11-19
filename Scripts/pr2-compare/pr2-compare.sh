#!/bin/bash
# Scripts/pr2-compare/pr2-compare.sh PATCH|--commit REF
#
# Compares a `git format-patch` of the 2.3.1 "PR 2" change (GenerationJobs, the bounded and ordered fan-out, and the
# phase timer) with our own implementation of it, by running on each exactly the gates ours passed:
#
#   gate 1  the suite without SafeDIToolFuzzerTests, in a debug build, fails only where the base fails (the base's
#           known failures, found by running the suite at the base), and its compile checks read the base's
#           passed-compile-check file (the generate-benchmark skill's `suite` step);
#   gate 2  Scripts/byte-identical-gate.sh (no line under Tests/ deleted or modified), and the code `generate` writes
#           for the skill's 13 shapes is byte for byte the base's (every `<Module>.generated.swift` and `.safedi`);
#   gate 4  the skill's one-round `generate` check (stage2.py --runs 1 against the base and 2.2.0, judged by
#           bands.json; one round shows the scripts run and nothing regressed grossly, it is not a speed verdict);
#   cover   Scripts/changed-line-coverage.sh (taken from COVERAGE_SCRIPT_REF) against the base, on this machine's
#           Swift, which must be 6.2.
#
# It also reports, for each side: commits, the span of their author dates, the diff size of Sources/ and Tests/,
# the tests added, and whether the public declarations of GenerationJobs.swift and GenerationPhaseObservation.swift
# match the racer's (the frozen helper signature).
#
# PATCH is applied with `git am --3way` on BASE. `--commit REF` instead takes the commits BASE..REF, writes them out
# with `git format-patch` and applies that file the same way (the dry run: `--commit "$RACER"`).
#
# Variables: BASE (default 4f0797a4), RACER (default d9004ab93), WORK (default ~/.cache/SafeDIPR2Compare),
# STEPS (default info,gate1,gate2,gate4,cover), RELEASE (default 2.2.0), COVERAGE_SCRIPT_REF (default origin/main),
# SHAPES (default all 13). Results are cached per commit under WORK/results/<sha>, so the racer and the base run once;
# delete a directory to run it again. Everything it builds is under WORK, outside the checkout and the system
# temporary directory; it never changes the checkout it is run from.
set -u
here=$(cd "$(dirname "$0")" && pwd)
repository=$(git -C "$here" rev-parse --show-toplevel) || exit 2
if [ "$(uname)" = Darwin ]; then caches="$HOME/Library/Caches"; else caches="${XDG_CACHE_HOME:-$HOME/.cache}"; fi
WORK=${WORK:-$caches/SafeDIPR2Compare}
STEPS=${STEPS:-info,gate1,gate2,gate4,cover}
RELEASE=${RELEASE:-2.2.0}
COVERAGE_SCRIPT_REF=${COVERAGE_SCRIPT_REF:-origin/main}
git_() { git -C "$repository" "$@"; }
resolve() { git_ rev-parse --verify --quiet "$1^{commit}" || { echo "pr2-compare: $1 is not a commit here; fetch it first" >&2; exit 2; }; }
BASE=$(resolve "${BASE:-4f0797a4}")
RACER=$(resolve "${RACER:-d9004ab93}")
git_ rev-parse --verify --quiet "$RELEASE^{commit}" > /dev/null || { echo "pr2-compare: fetch tag $RELEASE first (git fetch origin tag $RELEASE)" >&2; exit 2; }
step() { case ",$STEPS," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

[ $# -ge 1 ] || { sed -n '2,30p' "$0"; exit 2; }
mkdir -p "$WORK/results" "$WORK/tools" "$WORK/patches" || exit 2
export TMPDIR="$WORK/swiftpm-tmp"; mkdir -p "$TMPDIR"
export SAFEDI_TEST_TEMPORARY_DIRECTORY="$WORK/test-temporary"

swift_version=$(swift --version 2>&1 | head -1)
case "$swift_version" in *"Swift version 6.2"*) ;; *) echo "pr2-compare: needs Swift 6.2 (CI's compiler), found: $swift_version" >&2; exit 2 ;; esac

# --- The candidate: the patch applied on BASE --------------------------------------------------------------------
if [ "$1" = "--commit" ]; then
	source_commit=$(resolve "$2")
	patch="$WORK/patches/$source_commit.patch"
	git_ format-patch --stdout "$BASE..$source_commit" > "$patch" || exit 2
else
	patch=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
	[ -s "$patch" ] || { echo "pr2-compare: no patch at $1" >&2; exit 2; }
fi
apply="$WORK/apply"
git_ worktree remove --force "$apply" > /dev/null 2>&1; rm -rf "$apply"
git_ worktree add -q --detach "$apply" "$BASE" || exit 2
# A fixed committer, so one patch always makes the same commit, and its results are found in the cache again.
if ! GIT_COMMITTER_NAME=pr2-compare GIT_COMMITTER_EMAIL=pr2-compare@localhost GIT_COMMITTER_DATE="2000-01-01T00:00:00Z" \
	git -C "$apply" -c commit.gpgsign=false am --3way --keep-cr --committer-date-is-author-date < "$patch" > "$WORK/apply.log" 2>&1; then
	echo "pr2-compare: the patch does not apply on $(git_ rev-parse --short "$BASE"):"; cat "$WORK/apply.log"
	git -C "$apply" am --abort > /dev/null 2>&1; exit 1
fi
CANDIDATE=$(git -C "$apply" rev-parse HEAD)
git_ update-ref "refs/pr2-compare/candidate" "$CANDIDATE"   # keeps the commit for the cache and for worktrees
git_ update-ref "refs/pr2-compare/racer" "$RACER"
git_ worktree remove --force "$apply" > /dev/null 2>&1
echo "candidate $(git_ rev-parse --short "$CANDIDATE") ($(git_ rev-list --count "$BASE..$CANDIDATE") commits on base $(git_ rev-parse --short "$BASE")); racer $(git_ rev-parse --short "$RACER")"

# --- Shared pieces --------------------------------------------------------------------------------------------------
checkout="$WORK/checkout"
[ -d "$checkout" ] || git_ worktree add -q --detach "$checkout" "$BASE" || exit 2
at() { git -C "$checkout" checkout -q --force --detach "$1" && git -C "$checkout" clean -qfdx -e .build > /dev/null; }
skill="$WORK/skill"   # the generate-benchmark skill as BASE has it
rm -rf "$skill"; mkdir -p "$skill"
for file in SKILL.md bands.json make_fixtures.sh make_screens.py n1.py n5.py stage2.py; do
	git_ show "$BASE:.claude/skills/generate-benchmark/$file" > "$skill/$file" || exit 2
done

suite() { # suite LOG: the debug suite without the fuzzer's target, reading or filling the passed-compile-check file
	mkdir -p "$SAFEDI_TEST_TEMPORARY_DIRECTORY"
	(cd "$checkout" && SAFEDI_COMPILE_CHECK_PASSED_CACHE="$WORK/passed-$BASE.txt" swift test --traits sourceBuild \
		--scratch-path "$WORK/build-debug" --skip '^SafeDIToolFuzzerTests\.' > "$1" 2>&1)
	local status=$?
	rm -rf "$SAFEDI_TEST_TEMPORARY_DIRECTORY"
	return $status
}
failures() { # failures LOG: the failing tests a log names, one per line, sorted
	grep -aoE '✘ Test [^ ]+(\(.*\))? (failed|recorded an issue)' "$1" | sed -E 's/^✘ Test //; s/ (failed|recorded an issue)$//' | sort -u
	grep -aoE "Test Case '[^']+' failed" "$1" | sed -E "s/^Test Case '//; s/' failed$//" | sort -u
}
tool() { # tool COMMIT: a release SafeDITool built at COMMIT, cached
	local commit=$1
	if [ ! -x "$WORK/tools/SafeDITool-$commit" ]; then
		at "$commit" || return 1
		(cd "$checkout" && swift build -c release --product SafeDITool --traits sourceBuild --scratch-path "$WORK/build-tool") \
			> "$WORK/tools/build-$commit.log" 2>&1 && cp "$WORK/build-tool/release/SafeDITool" "$WORK/tools/SafeDITool-$commit"
	fi
	[ -x "$WORK/tools/SafeDITool-$commit" ]
}

# --- The base's known failures and compile-check file (gate 1's reference) ----------------------------------------
base_results="$WORK/results/$BASE"; mkdir -p "$base_results"
if step gate1 && [ ! -s "$base_results/known-failures.txt" ]; then
	echo "base: running the suite twice (fills the passed-compile-check file, then reads it); this takes a while"
	rm -f "$WORK/passed-$BASE.txt"
	at "$BASE" && suite "$base_results/suite-fill.log"; suite "$base_results/suite-second.log"
	failures "$base_results/suite-second.log" > "$base_results/known-failures.txt"
	[ -s "$base_results/known-failures.txt" ] || echo "(none)" > "$base_results/known-failures.txt"
	grep -aE "Compile checks:|Value comparison programs:" "$base_results/suite-second.log" | tail -2 > "$base_results/compile-checks.txt"
fi

# --- One side's gates ---------------------------------------------------------------------------------------------
run_side() { # run_side COMMIT: writes WORK/results/COMMIT/*
	local commit=$1 out="$WORK/results/$1"
	mkdir -p "$out"
	if step info && [ ! -s "$out/info.json" ]; then
		python3 -I "$here/side-info.py" "$repository" "$BASE" "$commit" "$RACER" > "$out/info.json"
	fi
	if step gate1 && [ ! -s "$out/gate1.txt" ]; then
		at "$commit" && suite "$out/suite.log"
		echo "exit $?" > "$out/suite-status.txt"
		failures "$out/suite.log" > "$out/failures.txt"
		grep -aE "Compile checks:|Value comparison programs:|Test run with" "$out/suite.log" | tail -3 > "$out/compile-checks.txt"
		local unknown; unknown=$(comm -23 "$out/failures.txt" <(grep -v '^(none)$' "$base_results/known-failures.txt"))
		if [ -z "$unknown" ] && grep -aq "Test run with" "$out/suite.log"; then
			echo "PASS: $(wc -l < "$out/failures.txt" | tr -d ' ') failing, all among the base's $(grep -cv '^(none)$' "$base_results/known-failures.txt")" > "$out/gate1.txt"
		elif grep -aq "Test run with" "$out/suite.log"; then
			{ echo "FAIL: failures the base does not have:"; echo "$unknown"; } > "$out/gate1.txt"
		else
			echo "FAIL: the suite did not finish (see $out/suite.log)" > "$out/gate1.txt"
		fi
	fi
	if step gate2 && [ ! -s "$out/byte-identical.txt" ]; then
		git_ show "$COVERAGE_SCRIPT_REF:Scripts/byte-identical-gate.sh" > "$WORK/byte-identical-gate.sh" 2> /dev/null \
			|| git_ show "$BASE:Scripts/byte-identical-gate.sh" > "$WORK/byte-identical-gate.sh"
		(cd "$repository" && bash "$WORK/byte-identical-gate.sh" "$BASE" "$commit") > "$out/byte-identical.txt" 2>&1
		echo "exit $?" >> "$out/byte-identical.txt"
	fi
	if { step gate2 || step gate4; } && [ ! -s "$out/stage2.log" ]; then
		[ -d "$WORK/fixtures" ] || bash "$skill/make_fixtures.sh" "$WORK/fixtures" > /dev/null || return 1
		for built in "$BASE" "$commit" "$RELEASE"; do tool "$built" || { echo "tool $built failed to build" > "$out/stage2.log"; return 1; }; done
		rm -rf "$out/work"
		python3 -I "$skill/stage2.py" --runs 1 --bands "$skill/bands.json" ${SHAPES:+--shapes "$SHAPES"} "$WORK/fixtures" "$out/work" \
			"BASE=$WORK/tools/SafeDITool-$BASE" "HEAD=$WORK/tools/SafeDITool-$commit" "V220=$WORK/tools/SafeDITool-$RELEASE,legacy" \
			> "$out/stage2.log" 2>&1
		echo "exit $?" >> "$out/stage2.log"
		python3 -I "$here/output-identity.py" "$out/work" > "$out/identity.txt"
		rm -rf "$out/work"
	fi
	if step cover && [ ! -s "$out/coverage.txt" ]; then
		at "$commit" || return 1
		for file in changed-line-coverage.sh changed-line-coverage.py; do
			git_ show "$COVERAGE_SCRIPT_REF:Scripts/$file" > "$checkout/Scripts/$file" || return 1
		done
		mkdir -p "$SAFEDI_TEST_TEMPORARY_DIRECTORY"
		(cd "$checkout" && zsh Scripts/changed-line-coverage.sh "$BASE") > "$out/coverage.log" 2>&1
		echo "exit $?" >> "$out/coverage.log"
		rm -rf "$SAFEDI_TEST_TEMPORARY_DIRECTORY"
		git -C "$checkout" checkout -q -- Scripts
		grep -aE "^(Sources|Plugins)/.*:[0-9]+: |changed line\(s\) no test executed" "$out/coverage.log" > "$out/coverage.txt" \
			|| echo "no report (see $out/coverage.log)" > "$out/coverage.txt"
	fi
}

start=$(date +%s)
run_side "$RACER"
run_side "$CANDIDATE"
python3 -I "$here/side-by-side.py" "$WORK/results" "$BASE" "$RACER" "$CANDIDATE" | tee "$WORK/results/side-by-side-$CANDIDATE.md"
echo "harness time $(( ($(date +%s) - start) / 60 )) min; report: $WORK/results/side-by-side-$CANDIDATE.md"
