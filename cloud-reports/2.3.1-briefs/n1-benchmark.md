# Brief N1: the 2.3.1 ship-bar benchmark against 2.2.0

Read `briefs/common-cloud-lane.md` first; this brief overrides it where they differ. Plan: `plans/2.3.1-plan.md` (item N1, section 9 item 1). Base: current `origin/main`. Branch: your own `claude/…` branch. No `Sources/` edits, no PR.

**Goal.** Dan's ruling (2-3-1-SHIP-BAR): code SafeDI 2.3.1 generates must be faster than 2.2.0's in runtime and compile time on a lifelike benchmark; for seams and public mocks (no 2.2.0 counterpart) no worse than 2.3.0. Issue #646 (`generate` about 3x slower than 2.2.0) is fixed in 2.3.1, so `generate` time is measured too. Build the benchmark and record the 2.2.0 baseline and main's figures, so every later 2.3.1 stack can be measured with one command.

**Shapes.** Start from 2.3.0's check 7 benchmark if it exists in the repository or on a pushed branch (ask the coordinator if you cannot find it; do not invent a replacement silently). Add:
- #646's generator script (in the issue body): 12 and 16 screens, seed 1; and the mock variant (12 screens, seed 5, `mock`).
- Spike 2's growth shape E at 8, 16, 24, 32 screens and the low-sharing shape L at 60 and 240 types (`spike/per-type-seam/stage2/spec_e.py`, `spec_l.py`, `emit.py` on `claude/project-thread-ea2rdt`). Seams have no 2.2.0 counterpart: measure them against main only.
- The mock-overrides spike's shape D at 8, 12, 16, 20, 24 screens (`run_d.py` on `dfed--claude/cloud-mock-overrides-spike`).
- A 100-module run that calls `generate` once per module with dependency `.safedi` files, as Bazel does (`Scripts/multi-module-repro.sh` shows the per-module invocation). Pick a module graph shape and state it; ask before choosing samples you cannot justify from the brief.
- The repository's example projects where they build on Linux.

Follow `.claude/rules/generator-design.md`, "Benchmarks are lifelike": a synthetic module takes its shape from measured statistics of a real app (2.3.0's check 7 benchmark records them), with invented names; never copy a private app's source.

**Measures** for each shape and each binary (2.2.0 tag and current main, both `swift build -c release --product SafeDITool`, 2.2.0 built from its tag in a separate worktree; never run 2.2.0's test suite): `generate` wall time and peak memory; generated lines; compile of the generated module at `-Onone` and `-O` (time the frontend job); runtime per value of building the root (or `mock()`) in a loop. Medians of five with min–max. Instructions retired come from `/usr/bin/time -l` on the maintainer's Mac: write the Mac command list into your hand-back; do not try to reach the Mac yourself.

**Done when.** A script (proposed home `Scripts/benchmark-2-3-1.sh`, not merged) that takes two `SafeDITool` paths and prints one table; the baseline table for 2.2.0 and main; two full runs agreeing within 3% on wall-time medians (report any shape that does not); every shape where main is slower than 2.2.0, ranked by ratio; machine, compiler and load recorded. Keep machine load under 1 during timing; run nothing else.

**Hand-back** as in the common brief, plus the Mac command list. Copy the report to `/mnt/project-files/benchmark-2-3-1/report.md` if you can write there.

## Addendum (2026-11-16, from the lead's review of the emitter design)

Add these to the hand-back:
1. **Profile main** on #646's graphs at 12 and 16 screens and on the mock variant, with instructions retired per phase: the `Scope.createScopeGenerator` passes, `ScopeGenerator.init`'s facts, the validation walks, and emission. (Instructions per phase need the Mac or a Linux profiler you can run without root, such as `valgrind --tool=callgrind`; say which.)
2. **Speculative generation:** report instructions and wall time with and without the detached per-generator `generateCode()` starts (`Models/Scope.swift:1304–1322`), on the same graphs. A local, uncommitted patch on your branch is fine for this measurement.
3. **Lifelike production compile** at `-Onone` and `-O`, the 2.3.0 stack head against 2.2.0, and the count of types built in both families (inside and outside a `@Sendable` builder function) on the lifelike benchmark.
