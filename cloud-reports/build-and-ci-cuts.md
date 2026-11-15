# Build and CI time: ranked cuts

Goal (Dan, 2026-11-15): bring build and CI time down with no loss of coverage. Every test, compile check and
fuzzer seed still gates merges somewhere. Estimates count a CI or Verify wait once per stack (CI runs on a
stack's top pull request only) and separate hands-on time from waiting.

Nothing below is built yet except where it says "landing". Figures are step timestamps of real runs unless marked
"estimate" or "unmeasured".

## Where a CI run's time goes today

Five runs read: main 43765011597, 43760851366, 43721724778; pull requests 43755152593, 43671437925.

- End to end: 56 to 70 minutes for a full run (30 for the one run where only the test jobs ran).
- The run ends when the slower of two chains ends:
  - macOS: "Build and Test on Xcode 26", 39 to 57 minutes (build about 11 to 15, tests 27 to 40 with every
    compile check compiling), plus 2 to 12 minutes queued for a runner.
  - Linux: "Build and Test on Linux" 26 to 35 minutes (build 10 to 15, tests 13.5 to 18 cold, 7.5 with checks
    skipped), and only then the fuzzer shards (longest 10.5 to 17.1) and "Repeat Tests on Linux" (four passes one
    after another, 10 to 26 minutes). This chain was the longer one in 43755152593 (56 minutes, macOS done at 51).
- Every run read compiled all 3,310 compile checks on macOS. The shared list of passed checks was first saved at
  21:53Z on 2026-11-15, and no run with tests has started since, so the warm macOS time is unmeasured.
- 12 macOS jobs a run use 110 to 125 runner-minutes. Short ones (DocC 1 minute, Tuist 3, xcodebuild 5) have queued
  up to 61 minutes; in 43671437925 that queue, not a test, set the run's end.

Upcoming work that pays for a cut: slices 3 to 7 (at least three stacks, since 4, 5 and 6 fan out), the 2.3.0
landing stacks, and 2.3.1 (emitter rewrite, then output reshaping). I count 6 stacks at least, each with 2 to 4
CI runs on its top pull request (first push plus review fixes): about 15 to 20 runs.

## Ranked list

Ranked by minutes off the run's end per lane-hour, critical path first.

| # | Cut | Saves per run | Hands-on | Coverage risk | Evidence | Payback |
|---|---|---|---|---|---|---|
| 1 | Keep compile checks warm: all workflow edits go in one stack, and no stack carrying a slice edits `ci.yml` or `verify.yml` | About 20 min on macOS for each cold run avoided (estimate: macOS tests 27 to 40 cold; warm unmeasured, Linux went 13.5 to 7.5) | 0 (a rule) | None | 43760851366 cold, 43765011597 Linux warm | 0 h up front; about 20 min for every run that would otherwise be cold |
| 2 | Start the fuzzer shards and Repeat Tests when the Linux build ends, not when its tests end (upload the bundle after `swift build --build-tests`, as Verify does) | 14 to 18 min off the Linux chain | 1.5 to 2 h | None: same jobs, same seeds | Shards start at +28.7 to +38.4 min today; Linux tests take 13.5 to 18 of that | 2 h up front; about 15 min a run where Linux is the longer chain, which it is once 1 holds; 15 to 20 runs ahead |
| 3 | Run Repeat Tests' four passes as four jobs (one check still reports under today's name) | About 15 min off that chain (one pass took 5.2 min, the step 9.7 to 25.3) | 0.5 h, with 2 | None: same four passes | 43760851366 log; 43755152593 where it ended the run | 0.5 h up front; with 2, the Linux chain drops from about 56 to about 30 to 35 min (estimate) |
| 4 | Fast inner loop while fixing tests: filtered runs, whole suite once at the end (guidance in `.claude/rules/test-design.md`) | About 35 to 40 min a slice (slice 2 ran the 3.5 min suite 12 times; 14 suites with 891 tests ran in 18 s here) | 0.5 h | None: the full suite still runs before hand-back and in CI | Slice 2 retro; local run on 2026-11-15 | 0.5 h up front; about 0.6 h a slice; 5 slices and the 2.3.1 work |
| 5 | Measure the warm macOS job, then decide whether to split its tests | Unmeasured | 0.2 h to read the run | None | Second main run after #723/#724 | Decides whether 6 is worth building |
| 6 | Give the Xcode test job its runner first: fold DocC, Tuist, Multi Project and Project Integration (1 + 3.4 + 3.4 + 6.1 min) into one macOS job | 2 to 12 min of queue on the critical job; frees 3 of 12 macOS slots | 1 to 1.5 h | None if each step keeps failing the job; check names change, so required checks need a look | Queue medians 5.2 (test job), 12.3 (xcodebuild), max 61.5 | 1.5 h up front; about 5 min a run (median), more when two runs overlap |
| 7 | Split Linux CI's tests into groups as Verify does | About 6 to 10 min cold, less warm | 3 to 4 h | Medium: the coverage gate needs every group's report joined | Verify 43766692766: slowest group 5.5 min against 13.5 to 18 in one job | Only after 2 and 3, and only if Linux is still the longer chain |
| 8 | Split the three largest test targets (experiment first) | At most about 1 min of the 2.1 min rebuild after a test-only change; cold build effect unmeasured | 0.5 h experiment, about 1 h to do | None | 43763818802 | Weak: do the experiment only when a build is idle |
| 9 | Container start in Verify and CI | 0.4 to 0.7 min a job, about 1.1 min on a chain | not built | None | 13 container jobs, 6.4 to 6.8 min a run in total | Dropped by Dan (2026-11-15): keeping an image of our own up to date costs more over time than it saves |

Left alone on purpose: "Build and Test on Latest Swift" (29.5 min, compiles every check with a third compiler) and
"Build Release SafeDITool on Linux" (17 min, no cache) are off the critical path, and each exists to catch what a
cache would hide.

Already landing: Verify in seven jobs (9.0 min against 18 to 27, #723) and the fuzzer's ten shards (4.4 to 7.7 min
against up to 17.1, #724).

## What I will build, and in which stack

One stack, "CI cuts", after #723 and #724 land and before slice 3's stack, so the slices never carry a workflow
edit: items 2 and 3 together (one cold run for both), then item 6 in the same stack if its required-check names
allow. Item 4 is documentation and rides at the bottom of slice 3's stack with the test migration. Item 1 is a
rule for the lead's stacking and goes into the retro's estimating guidance.

Expected run after 1 to 3 (estimate, to be measured on the stack's own run): about 30 to 35 minutes end to end
with warm checks, against 56 to 70 today.

## Estimating rule (for retros, slices and W1)

An estimate states hands-on time and waiting separately, counts each CI and Verify wait once per stack, names the
stack the work rides in, and gives a payback line: hours up front, hours saved per slice or stack, and how many
upcoming slices or stacks gain.
