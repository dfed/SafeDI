# Adjudication: claude/verify-with-pins @ 3a035190 (PR #725 stack)

**No blocking findings.** All four reviewer findings are real; I keep finding 1 at should-fix, raise finding 3 to should-fix, and leave 2 and 4 as nits.

## What I verified myself

Both proof runs completed green on head 3a0351908b7c:

| Run | Result | Start to end |
|---|---|---|
| Verify 43774444496 (`pins=true`) | success | 23:22:21 to 00:09:13, 46.9 min |
| Graph Fuzzer 43774447047 (`coverage=true`) | success | 23:22:23 to 00:02:10, 39.8 min |

- **Skipped build, dependants still run.** In the Verify run, "Fuzz / Build for Coverage on Linux" was skipped. The unit suite, all 10 shards, the report and "Fuzz / Check Graph Fuzzer Corpus for Coverage on Linux" (8 s) all succeeded.
- **Undefined `inputs.bundle` on plain dispatch.** In the standalone run, "Build for Coverage on Linux" ran, and the downstream jobs read its bundle. So the value is falsy in both the job `if:` and the workflow-level `env.TEST_BUNDLE`.
- **Caller grant.** There was no startup failure, and the called jobs checked out the repository with `contents: read`.
- **Coverage instrumentation.** verify.yml:90 and graph-fuzzer.yml:175 carry the same arguments, including `--enable-code-coverage`. The diff does not touch verify.yml's build arguments, so a `pins=false` run pays nothing new.
- **Pins from another head.** No explicit commit check exists, and none is needed. Every download omits `run-id`, so it reads only this run's artifacts. The shards run the bundle built in the same run from `github.sha`.
- **Required checks.** I read main's required contexts; none matches "Fuzz / …" or "Check Graph Fuzzer Corpus for Coverage on Linux".

## Findings

### 1. should-fix: the timing quoted for the recommended path was not measured on it

- **Location:** `.claude/rules/fuzzer-corpora.md` line 32, "Coverage of a change".
- **Problem:** the bullet now recommends `verify.yml -f pins=true` but keeps "about 25 to 30 minutes … about 13 when the commit's build is already saved (run 43762600658)". That run is a standalone graph-fuzzer run.
- **Evidence:** the only pins run took 46.9 min, for two reasons.
  - Its build was cold. The log says "Cache not found for input keys: verify-release-v1-…", and Build Tests ran 23:23:07 to 23:48:35. Main's cache under that key prefix was saved at 23:31:47, after the restore at 23:22:53.
  - Its jobs waited for runners. The bundle was uploaded at 23:48:58, but the 7 groups started between 23:49:08 and 23:56:27, and the shards between 23:54:23 and 23:59:32. The standalone proof run was competing for slots at the same time.
- **Fix:** dispatch `verify.yml -f pins=true` once more with main's release cache present and no sibling run, then cite that run's start-to-end time in the bullet. Until then, attribute the existing numbers to `graph-fuzzer.yml -f coverage=true`. Also add one clause: "`pins` adds 13 jobs (the unit suite, 10 shards, the pins check and the report) beside the 7 test groups, so start times depend on free runners."
- **Correction to the reviewer:** the added job count is 13, not 11.

### 2. nit: `pins=true` does nothing, silently, when the run does not split

- **Location:** verify.yml:381, `if: ${{ inputs.pins && needs.verify.outputs.split == 'true' }}`, and the split step at :114-124.
- **Problem:** with a filter or `mode=fast`, the run goes green with no fuzzing and no pins check. With `mode=warm`, "Verify on Linux" is skipped, so "Fuzz" is too. The input description states the precondition, but a green run reads as "pins checked".
- **Fix:** in "Decide Whether to Split the Tests", add `PINS: ${{ inputs.pins }}` to `env`, and in the non-split branch add:
  ```
  if [ "$PINS" = true ]; then echo "::error::pins needs mode=release and an empty filter."; exit 1; fi
  ```
  The `warm` case is covered by the input description; leave it.

### 3. should-fix (raised from nit): the called workflow's uploads cannot be re-run

- **Location:** graph-fuzzer.yml uploads at :219-223 (`graph-fuzzer-test-bundle`), :278-284 (`unit-suite-profile`), :358-364 (`graph-fuzzer-report-<corpus>-<seed>`) and :423-430 (`fuzzer-coverage`). None sets `overwrite: true`.
- **Problem:** the profile, report and coverage uploads run under `if: !cancelled()`, so a failed shard has already uploaded its report. "Re-run failed jobs" then uploads the same name into the same run. I did not exercise a re-run; this rests on upload-artifact's documented name conflict. verify.yml guards against it at :219-220, :359-360 and :370-371.
- **Why raised:** on the now-recommended path, one flaky shard forces a full redispatch of 25 to 47 minutes when a single-job re-run would do. The gap predates this change for standalone dispatch.
- **Fix:** add to all four uploads:
  ```yaml
            # A re-run of the job replaces what an earlier attempt uploaded.
            overwrite: true
  ```
- **Addition to the reviewer:** include the build's bundle upload (:219), which the reviewer's list omitted. "Re-run all jobs" on a standalone run reaches it.

### 4. nit: the new job's limit has no measurement beside it

- **Location:** graph-fuzzer.yml:442, `coverage-corpus` `timeout-minutes: 5`.
- **Problem:** CLAUDE.md asks for the measurement beside a limit. The job took 8 s in run 43774444496 and 14 s in 43774447047. ci.yml's "Check Graph Fuzzer Corpus on Linux" has no limit, and verify.yml's "Check Every Verify Test Ran Once" has the same bare job-level 5, so this matches local precedent.
- **Fix:** add a comment above the limit: `# 8 and 14 seconds (runs 43774444496, 43774447047); the limit only bounds a stuck download.`

## Reviewer's "not findings"

I confirmed the ones the proof runs or the diff show:
- The skipped `fuzz` matrix job reports only its unexpanded name.
- Artifact names do not collide between caller and callee.
- "Check Every Verify Test Ran Once" and "Save Passed Compile Checks of Verify" both succeeded beside the fuzz jobs.

I did not re-check the claims about `compile-check-identity.sh` hashing verify.yml or about `share-compile-checks.yml`; neither affects a finding.

Nothing was edited; I used only git fetch/show/diff, `gh run view` and `gh api`.

---

# Adjudication: claude/verify-with-pins @ 3a035190 (PR #725)

**Verdict: no blocking findings; three should-fix (one upgraded from nit), six nits.** Both proof runs finished green at head 3a035190 and confirm the mechanics the lane asked reviewers to attack.

## What I confirmed in the proof runs

**Verify run 43774444496 (pins=true): success, 23:22:21 to 00:09:13, 46.9 min.**
- "Fuzz / Build for Coverage on Linux" was skipped, and all 10 shards, the unit suite, the report and the corpus check still ran and passed. So `!cancelled() && inputs.coverage && (… || inputs.bundle)` works.
- The corpus job's log shows `TEST_BUNDLE: verify-test-bundle` and "Total of 10 artifact(s) downloaded".
- "Restore Release Build Directory" took 1 s (a miss), and "Build Tests" ran 23:23:07 to 23:48:35, 25.5 min.
- The 7 groups, "Check Every Verify Test Ran Once" and the compile-check save all succeeded.

**Graph Fuzzer run 43774447047 (coverage=true): success.**
- The build ran, so an undefined `inputs.bundle` is falsy on a plain dispatch. Its "Build" step ran 23:23:07 to 23:46:11, 23.1 min.
- The corpus check and the report both succeeded.

## Answers to the lane's questions

- **Is Verify's bundle built with coverage?** Yes. verify.yml line 90 and graph-fuzzer.yml line 175 are the same argument string, with `--enable-code-coverage` and the atomic-counter flag. The two "Package Test Bundle" steps tar the same four paths.
- **Does pins=false now slow the 7 groups?** No. The diff adds only the two inputs and the `fuzz` job to verify.yml; the build and its arguments are untouched, and the release build was already instrumented.
- **Can pins come from another head?** No, by construction. `download-artifact` without a `run-id` reads only the current run. `bundle` is a fixed literal from the caller and does not exist on dispatch. Checkouts use `github.sha`, which is the caller's in a called workflow.
- **Permissions and required checks:** `contents: read` was enough. ci.yml is unchanged. graph-fuzzer.yml has no `concurrency:` block that a call could collide on.

## Findings

### 1. should-fix (confirmed): cold-build measurements are stale and the 35-minute Build limits are about 1.4x
- **Location:** verify.yml lines 176-182 (`timeout-minutes: 35`), 373-377 (the new comment's "10 to 17 minutes") and 488-497; graph-fuzzer.yml lines 200-205.
- **Evidence:** three cold builds, all checked from step times:
  - 23.9 min: main's "Warm the Release Verify Build Cache", run 43772841709 at 677b42f, 23:06:45 to 23:30:37.
  - 25.5 min: Verify run 43774444496.
  - 23.1 min: Graph Fuzzer run 43774447047.
- **Caveat:** all three ran within the same half hour, two of them at once. They are still the only current measurements.
- **Fix:** 
  - Set both Build steps to `timeout-minutes: 50`.
  - Replace "10 to 17 minutes" in all four comments with "23 to 26 minutes (runs 43772841709, 43774444496, 43774447047)".
  - Raise the warm job's limit from 45 to 60. I did not read past line 500, so check whether its Build step has its own limit to raise too.
  - The job limits of 75 (verify) and 60 (coverage-build) still hold a 50-minute step.

### 2. should-fix (confirmed): fuzzer-corpora.md's timing is from the other workflow and is stale
- **Location:** `.claude/rules/fuzzer-corpora.md`, "Coverage of a change".
- **Evidence:** the sentence now tells readers to run `verify.yml -f pins=true` but keeps "about 25 to 30 minutes … about 13 when the commit's build is already saved (run 43762600658)", which is a graph-fuzzer.yml run. The pins run took 46.9 min cold. Its shards were queued at 23:49:03 and the last started at 23:59:32.
- **Fix:**
  - Write "about 47 minutes from a cold build (run 43774444496, of which the build was 25.5 and about 10 were shards waiting for runners)".
  - Add a warm figure once a warm pins run exists, and until then do not quote 13.
  - Merge the back-to-back parentheticals into one: "(`graph-fuzzer.yml -f coverage=true` fuzzes alone; `base` defaults to …)".

### 3. should-fix (upgraded from nit, numbers corrected): the shard's fuzz step limit is 1.6x the slowest measured
- **Location:** graph-fuzzer.yml lines 331-337 ("4.4 to 7.7 minutes", `timeout-minutes: 16`), job limit 25 at line 295.
- **Evidence:** the reviewer's 9.4 min is not the slowest. In run 43774447047:
  - base 2500+1250 took 10.1 min (23:49:18 to 23:59:23).
  - base 3750+1250 took 9.65 min.
  - generateMockPublic 0+500 took 9.6 min.
  - In run 43774444496, generateDependencyTree 250+250 took 9.4 min.
- **Why upgraded:** a shard that times out makes the new pins check fail for a reason unrelated to pins, which is the result this PR exists to give.
- **Fix:** comment "4.4 to 10.1 minutes (runs 43762600658, 43774447047)", step `timeout-minutes: 20`, job `timeout-minutes: 30`.
- **Not in this PR's diff:** ci.yml's shard comment near line 1279 cites the same 4.4 to 7.7.

### 4. nit (confirmed): `pins=true` is silently ignored with a filter or `mode=fast`
- **Location:** verify.yml line 381 and the "Decide Whether to Split the Tests" step at lines 114-124.
- **Fix:** pass `PINS: ${{ inputs.pins }}` into that step. In its `else` branch, when `"$PINS" = true`, run `echo "::error::pins needs mode=release and an empty filter."; exit 1`.

### 5. nit (confirmed): `coverage-corpus` has `timeout-minutes: 5` with no measurement
- **Evidence:** "Combine Shard Reports" took under 1 s in both runs; the jobs took 8 s and 14 s. The limit is at job level, and ci.yml's counterpart has none.
- **Fix:** drop the limit to match ci.yml, or add a comment "the job took 8 and 14 seconds (runs 43774444496, 43774447047)".

### 6. nit (confirmed): instruction files do not cover the new entry point
- `.claude/rules/fuzzer-corpora.md` front matter lists graph-fuzzer.yml but not verify.yml. Add `- ".github/workflows/verify.yml"`.
- CLAUDE.md's `verify.yml` bullet should gain "`-f pins=true` also runs graph-fuzzer.yml's coverage jobs and pins check from the same build". Its Scripts bullet should name `verify.yml -f pins=true` beside the `coverage` input.
- verify.yml's header (lines 31-41) should get one sentence on the pins jobs.

### 7. nit (plausible, untested): graph-fuzzer.yml's uploads lack `overwrite: true`
- **Location:** uploads of `unit-suite-profile`, `graph-fuzzer-report-<corpus>-<seed>` and `fuzzer-coverage`.
- **Evidence:** every verify.yml upload sets `overwrite: true` with "A re-run of the job replaces what an earlier attempt uploaded." No re-run was made in either proof run. These uploads predate the PR, which only extends them into Verify runs.
- **Fix:** add `overwrite: true` to the three uploads.

### 8. nit (optional): the unit suite runs twice on the pins path
- **Evidence:** "Fuzz / Run the Unit Suite for Coverage on Linux" spent 5.4 min in "Run Unit Suite" (23:54:22 to 23:59:44) on the same bundle the 7 groups test.
- **Fix:** no change now. It is off the critical path, because the report waits on the shards, which finished at 00:08:20.

### 9. nit (new, observation): runner queueing delays the 7 test groups under pins=true
- **Evidence:** in run 43774444496 the build ended at 23:49:02. The groups started between 23:49:08 and 23:56:27, and the last finished at 00:01:23, 12.4 min after the build. The header quotes 9.0 min for a whole non-pins run (43766692766).
- **Caveat:** the standalone Graph Fuzzer proof run was competing for runners at the same time, so the delay is not attributable to pins alone.
- **Fix:** none required. When rewriting the timing for finding 2, say that a pins run's tests can finish later than a plain run's. If a lone pins run still shows the delay, lower `max-parallel` on the shards.

### 10. nit (new, cosmetic): a skipped job shows an unexpanded name in every pins run
- **Evidence:** run 43774444496 lists "Fuzz / Fuzz Dependency Graphs on Linux (shard ${{ strategy.job-index }} of ${{ strategy.job-total }})" as skipped. The standalone coverage run shows the same, so this is existing behaviour that pins runs now also show.
- **Fix:** none needed.

## Dropped
None of the reviewer's findings is wrong. The only correction is to finding 3: the slowest shard is 10.1 min, not 9.4.

## Not evidenced by the proof runs
- The corpus check's failure path, when a pin has moved, did not run: both runs matched their pins. `combine-graph-fuzzer-reports.py` is the same script and invocation as ci.yml's and exits 1 on any problem.
- I could not read the corpus job's summary. The script writes the count-beside-pin text to the job summary and prints nothing to the log on success.