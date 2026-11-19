#!/bin/bash
# run-gate.sh: compares one commit's `SafeDITool generate` with another's and with release 2.2.0's.
#   BASE=<commit> HEAD=<commit> [ROUNDS=15] [STEPS=tests,suite,generate] [SHAPES=A,B] [REFILL=1] bash run-gate.sh
# tests     Scripts/byte-identical-gate.sh BASE HEAD, taken from TESTS_DIFF_REF (default HEAD); skipped when that
#           commit has no such script.
# suite     the suite without the fuzzer's target, in a debug build, with a passed-compile-check file filled at BASE
#           and read at HEAD. Compile checks at HEAD must read "0 compiled" apart from new tests' fixtures. A value
#           comparison program that fails is never kept, so compare HEAD's count with BASE's second run, not with 0.
# generate  stage2.py: BASE, HEAD and 2.2.0 on each shape, ROUNDS interleaved rounds, judged by bands.json.
# Everything is kept under WORK (default: SafeDIBenchmarks in the user's caches directory), outside the checkout and
# the system temporary directory: a worktree (W), release tools by commit (T), fixtures (FX), this run's logs (L).
# 2.2.0 is built from its tag and only ever run through `generate`.
set -u
BASE=${BASE:?set BASE to the commit to measure from} HEAD=${HEAD:?set HEAD to the commit to judge}
ROUNDS=${ROUNDS:-15} STEPS=${STEPS:-tests,suite,generate} RELEASE=${RELEASE:-2.2.0}
S=$(cd "$(dirname "$0")" && pwd)
repository=$(git -C "$S" rev-parse --show-toplevel) || exit 2
if [ "$(uname)" = Darwin ]; then caches="$HOME/Library/Caches"; else caches="${XDG_CACHE_HOME:-$HOME/.cache}"; fi
WORK=${WORK:-$caches/SafeDIBenchmarks}
BASE=$(git -C "$repository" rev-parse --verify --quiet "$BASE^{commit}") || { echo "BASE is not a commit of $repository; fetch it first"; exit 2; }
HEAD=$(git -C "$repository" rev-parse --verify --quiet "$HEAD^{commit}") || { echo "HEAD is not a commit of $repository; fetch it first"; exit 2; }
W=${W:-$WORK/checkout} T=${T:-$WORK/tools} FX=${FX:-$WORK/fixtures} L=${L:-$WORK/gate-$HEAD}
mkdir -p "$WORK" "$T" "$L" || exit 2
export TMPDIR="$WORK/swiftpm-tmp"; mkdir -p "$TMPDIR"
[ -d "$W" ] || git -C "$repository" worktree add -q --detach "$W" "$HEAD" || exit 2
cd "$W" || exit 2
step() { case ",$STEPS," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

if step tests; then
	reference=${TESTS_DIFF_REF:-$HEAD}
	if git show "$reference:Scripts/byte-identical-gate.sh" > "$L/byte-identical-gate.sh" 2> /dev/null; then
		bash "$L/byte-identical-gate.sh" "$BASE" "$HEAD" | tee "$L/tests-diff.txt"
	else
		echo "tests: skipped, $reference has no Scripts/byte-identical-gate.sh (name a commit that has it in TESTS_DIFF_REF)"
	fi
fi

if step suite; then
	export SAFEDI_COMPILE_CHECK_PASSED_CACHE="$WORK/passed-$BASE/passed.txt"
	export SAFEDI_TEST_TEMPORARY_DIRECTORY="$WORK/test-temporary"
	mkdir -p "$(dirname "$SAFEDI_COMPILE_CHECK_PASSED_CACHE")" "$SAFEDI_TEST_TEMPORARY_DIRECTORY"
	suite() {
		swift test --traits sourceBuild --scratch-path "$WORK/build-debug" --skip '^SafeDIToolFuzzerTests\.' > "$L/suite-$1.log" 2>&1
		echo "suite $1 exit $?"
		grep -E "Compile checks:|Value comparison programs:|Test run with" "$L/suite-$1.log" | tail -3
	}
	if [ ! -s "$SAFEDI_COMPILE_CHECK_PASSED_CACHE" ] || [ "${REFILL:-0}" = 1 ]; then
		git checkout -q --detach "$BASE" && suite base-fill && suite base-second
	fi
	git checkout -q --detach "$HEAD" && suite head
	rm -rf "$SAFEDI_TEST_TEMPORARY_DIRECTORY"
	unset SAFEDI_COMPILE_CHECK_PASSED_CACHE SAFEDI_TEST_TEMPORARY_DIRECTORY
fi

if step generate; then
	[ -d "$FX" ] || bash "$S/make_fixtures.sh" "$FX" || exit 2
	for commit in "$BASE" "$HEAD" "$RELEASE"; do
		[ -x "$T/SafeDITool-$commit" ] && continue
		git checkout -q --detach "$commit" || { echo "tool $commit: no such commit or tag; fetch it first"; exit 2; }
		swift build -c release --product SafeDITool --traits sourceBuild --scratch-path "$WORK/build-tool" > "$L/tool-$commit.log" 2>&1 \
			&& cp "$WORK/build-tool/release/SafeDITool" "$T/SafeDITool-$commit"
		echo "tool $commit exit $?"
		[ -x "$T/SafeDITool-$commit" ] || exit 1
	done
	rm -rf "$L/work"
	python3 -I "$S/stage2.py" --runs "$ROUNDS" --bands "$S/bands.json" ${SHAPES:+--shapes "$SHAPES"} "$FX" "$L/work" \
		"BASE=$T/SafeDITool-$BASE" "HEAD=$T/SafeDITool-$HEAD" "V220=$T/SafeDITool-$RELEASE,legacy" > "$L/stage2.log" 2>&1
	status=$?
	rm -rf "$L/work"
	sed -n '/^| shape | tool /,$p' "$L/stage2.log"
	echo "logs: $L"
	exit $status
fi
