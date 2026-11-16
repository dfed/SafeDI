# Slice 2: where the waiting went, and what would plug it

Source: the repository's Actions history from 16:07Z on 2026-11-15 to 03:20Z on 2026-11-16 (300 runs, with job-level
queue and run times for five of them). This covers every wait on GitHub. It does not cover the lead's own idle time
between steps (review rounds, hand-offs, reruns it chose): that needs the lead's timeline, which has been asked for and
is to be added below as `slice-2-timeline.md` arrives.

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

Plug, to measure before promising: save the build directory per branch after a verify, so the second and later
dispatches on a branch compile only what changed since the last one. Most of the 55 dispatches were repeats on a
handful of branches. Risk: the 10 GB cache limit evicting main's caches, so the per-branch cache needs a short life
or a size check.

### 5. `mode=fast` with an empty filter is slower than release

Measured: verify 43793266801, fast mode, whole suite in one job: 37 minutes, against 20 for release, which splits the
suite across seven jobs.

Plug: make `verify.yml` split the tests in fast mode too, or refuse an empty filter with `mode=fast` and say why.
Small workflow change.

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

## Order of work proposed

1. Lead's rule for landings (no code, today).
2. Fast-mode split in `verify.yml` (small).
3. Skip main's duplicate CI by tree hash.
4. Per-branch verify build cache, after a measurement.
5. Fold the short macOS jobs (needs Dan's branch protection edit).
