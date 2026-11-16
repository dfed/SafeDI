# Slice 2: where the waiting went, and what would plug it

Source: the repository's Actions history from 16:07Z on 2026-11-15 to 03:20Z on 2026-11-16 (300 runs, with job-level
queue and run times for five of them). This covers every wait on GitHub. The lead's own idle time between steps is in
`slice-2-timeline.md` beside this file, and "Idle gaps from the lead's timeline" below folds it in.

## What ran

| Kind | Runs | Median | Longest | Uncontended |
|---|---|---|---|---|
| Verify dispatches | 55 | 21 min | 37 min | 20 min |
| Graph fuzzer and pins runs | 19 | 35 min | 64 min | about 30 min |
| Full CI runs | 14 | 56 min | 95 min | about 30 min |

Verify alone summed to 1,122 minutes. 17 of the 55 took 25 minutes or more. Up to 10 heavy runs were in flight at once
(23:47Z).

## Gaps, largest first

### 1. Runners saturate when a landing, a stack's CI and a pins run overlap

Measured: at 00:33Z three full CI runs overlapped with pins runs and took 95, 84 and 68 minutes against about 30
uncontended. "Build and Test on Xcode 26" waited 39 to 44 minutes for a macOS runner and then ran 44 to 50 minutes
(uncontended: 3 minutes queued, 26 running). Linux shards waited 13 to 33 minutes. Queue time summed to 642 to 815
job-minutes per run against 125 uncontended. That is about one hour lost per run, three times over.

Plug:
- A push to main whose tree a pull request's CI already passed (a stack's top commit, landed without change) reruns
  nothing but the jobs that only main runs (cache warmers). The tree hash decides it, so nothing goes unchecked.
- Until that exists, a rule for the lead: land, then wait for main's cache warm job before dispatching the next
  stack's CI or pins run, instead of starting all three at once. Three runs in sequence at 30 minutes each end sooner
  than three overlapping at 68 to 95.

### 2. Thirteen macOS jobs per CI run compete for few macOS runners

Measured: even a single uncontended CI run queues macOS jobs for up to 17 minutes. The 26 minute Xcode 26 test job is
the critical path, and it queues behind short jobs (five xcodebuild platforms, DocC, the integration builds).

Plug: fold the short macOS jobs into two or three jobs so that the Xcode 26 test job always gets a runner first.
Cost: the names of some required checks change, so branch protection needs one edit by Dan. Expected saving: 10 to 15
minutes per uncontended CI run, more under load.

### 3. Verify and pins were dispatched separately, each building cold

Measured: pins run 43780085712 took 63 minutes, 24 of them a cold coverage build, and its shards queued up to 20
minutes. A verify of the same commit had built the same sources minutes before.

Plug: already landed (#732, `verify -f pins=true`, and #733, the apply-pins skill). The remaining work is habit: every
brief and the lead's operations notes name the single dispatch, and nobody dispatches `graph-fuzzer.yml` by hand for
pins again.

### 4. Half of every Verify is the build

Measured: verify 43795430677 (green, 20.5 minutes): 10.2 minutes building, 6 minutes of tests across seven groups, the
rest set-up and queueing. With 55 dispatches, the build is about 9 hours of the day's waiting.

Correction after reading `verify.yml`: a per-branch build already exists. `-f mode=warm` saves the branch a release
build that its later `release` runs start from (10 seconds of building from the same commit, about 2 minutes after a
change to one test file, 23 to 26 minutes from nothing). A plain `release` run saves no build, so a branch that was
never warmed starts every run from main's build, and for a branch that changes SafeDICore that is nearly a cold build
each time.

Plug: a `release` run of the whole suite saves its own build for its branch, so nobody has to remember `warm`. To
measure first: the minutes the save adds, and the cache space against the 10 GB limit (an old branch build must not
evict main's). Until then, a rule for lanes: dispatch `mode=warm` once on a branch that changes `Sources/` before its
first verify.

### 5. `mode=fast` with an empty filter is slower than release

Measured: verify 43793266801, fast mode, whole suite in one job: 37 minutes, against 20 for release, which splits the
suite across seven jobs.

Plug: a `fast` run with an empty filter fails at once and names `release` (#736).

### 6. The coverage gate reports last

Measured: the 84 minute CI run on slice 2's labels branch failed only in "Check Line Coverage on Linux", its final
job.

Plug: `Scripts/changed-line-coverage.sh` before the push already answers this locally in about 12 minutes; make it a
step of the pre-review checklist for any change under `Sources/`. A Linux-only early warning job in CI is possible but
adds a job to an already saturated pool, so the local step comes first.

### 7. Hand edits of expectations

Not a CI wait, but slice 2's largest hands-on cost: about 100 expectations edited by hand because tests assembled
their expected files. Plugged: 451 comparisons are now whole literals the regenerator rewrites (branch
`claude/write-out-expectations-s2`, verify green).

## Idle gaps from the lead's timeline

Slice 2 took 473 minutes from the implementer's start to final code. The timeline's three biggest gaps are 293 of
them, and about 21 minutes of the middle one was work.

### A. 19:40 to 21:22 (102 min): three full Verify runs to learn what a local run shows

Three Verify runs of 29 to 38 minutes each failed on the same remaining seam expectations, which a compiled local run
of the seam suites reports in about 3.5 minutes; and the lane waited 41 minutes for a regenerator that was on hold.

Plug, tooling: a skill, `verify-touched`, one command that works out the suites a branch touches (the suites of the
test files it changed, and for a change under `Sources/` the test targets of that area), runs them locally with
compile checks on, and prints only the failures. A full Verify is dispatched only after it passes. The regenerator
half is plugged already: the written-out expectations let it rewrite what slice 2 edited by hand.

### B. 22:54 to 00:29 (95 min): hand-back to a rebased green head, 21 min of it work

Rulings 10, probes 11, a 28 minute wait for a base SHA, 25 minutes of rebase and triage of stale lists by hand, a
24.8 minute Verify.

Plug, tooling: a skill, `restack-lane`, one command for the rebase a lane repeats: fetch the new base, rebase, stop
on a conflict with the files listed, check for conflict markers, build the tests, rerun the regenerator on the
expectations the base's changes moved, run the suites the base changed and the lane touched (`verify-touched`), lint,
and print the SHA to push. The 25 minutes become a few of attention. The wait for the base SHA is the lead's: a lane
can restack onto the base's "ready for review" head at once and again onto its final head, since a second restack is
then cheap.

### C. 00:29 to 02:05 (96 min): pins, apply, verify and a denied push, in sequence

Pins 56.8 minutes (two pins runs overlapped, about 20 minutes of it queueing), applying the lists 15 minutes, the
Verify 21.6 minutes, and the worker's snapshot push refused twice.

Plug:
- `verify -f pins=true` on the content head runs the tests and the pins from one build, so pins and Verify stop being
  two steps. One such run at a time across all lanes.
- The apply-pins skill (#733) turns the 15 minutes of list edits into one command. The commit it makes changes only
  lists, pins and hashes, so a filtered Verify of the pins suites covers it instead of a second whole run.
- Review starts when the code is green locally, beside the Verify, not after pins and lists (the lead has taken this).
- The refused push is a harness matter: a worker pushes its snapshot to a new branch name instead of force-pushing,
  which the classifier allows. It belongs in the harness friction log.

### D. Later slices idle behind slice 2's head (slice 5 at least 158 min)

Slices 3, 5 and 6 had finished their work on a speculative base and waited for 8f0574412 plus the review fixes.

Plug: with `restack-lane`, a waiting slice restacks onto each published head of the slice below it (ready for review,
then final, then review-fixed) and runs `verify-touched`, so its own review can start on real code while the base
settles. Each restack repeats little work, since the regenerator and the pins tooling redo what a rebase invalidates.

## Order of work proposed

1. Lead's rules (no code, taken 03:25Z): no overlapping stack CI, pins run and landing; `verify -f pins=true`; review
   beside the Verify; a local compiled run before any full Verify.
2. `fast` needs a filter (#736).
3. `verify-touched` skill, then `restack-lane` skill on top of it: these two address 197 of the timeline's minutes.
4. Skip main's duplicate CI by tree hash.
5. A `release` Verify saving its own branch build, after a measurement.
6. Fold the short macOS jobs (needs Dan's branch protection edit, with the exact before-and-after check names).
