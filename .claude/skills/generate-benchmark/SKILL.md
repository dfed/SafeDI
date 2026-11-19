---
name: generate-benchmark
description: Compare the time, CPU and peak memory of `SafeDITool generate` at one commit with another commit's and with release 2.2.0's, on fixed graph shapes, and check that a change meant to leave generated code alone did. Use before stating any speed or memory figure for the generator, and as the gate of a refactoring step.
---

# Measure `generate` against a base commit and 2.2.0

`run-gate.sh`, beside this file, runs three steps for two commits, `BASE` (what the change is measured from) and `HEAD` (the change). Run it from anywhere inside the checkout, in the background, since a whole run takes hours:

```bash
BASE=<commit> HEAD=<commit> bash .claude/skills/generate-benchmark/run-gate.sh
```

It never touches the checkout it is run from. Everything it makes is under `WORK`, by default `SafeDIBenchmarks` in the user's caches directory: a worktree it checks commits out in, a release `SafeDITool` per commit (kept, so a later run builds only new commits), the fixtures, and each run's logs in `gate-<HEAD>`. Both commits must already be in the repository; fetch them first.

| Variable | Meaning |
|---|---|
| `STEPS` | Which steps run, of `tests,suite,generate` (default all). |
| `ROUNDS` | Timed rounds per shape (default 15). |
| `SHAPES` | A comma-separated selection of shapes (default every shape). |
| `REFILL=1` | Fill the passed-compile-check file at `BASE` again. Needed when `BASE` is the same commit but its file is stale. |
| `TESTS_DIFF_REF` | The commit `Scripts/byte-identical-gate.sh` is read from, when `HEAD` does not have it. |
| `RELEASE` | The release tag compared with (default `2.2.0`). |

## The steps

1. **`tests`** runs `Scripts/byte-identical-gate.sh BASE HEAD`, which fails when the change edits an existing line under `Tests/`: a step that must leave generated code alone may add tests and may not change an expectation. A line `./CLI/lint.sh` rewrites passes when its commit holds nothing else.
2. **`suite`** runs the suite without `SafeDIToolFuzzerTests`, in a debug build, three times: twice at `BASE`, the first filling a passed-compile-check file (`.claude/rules/passed-compile-checks.md`), and once at `HEAD` reading it. A fixture's compile check is keyed by its generated code, so at `HEAD` "Compile checks: 0 compiled" means no existing fixture's generated code changed; any that compile belong to tests the change adds, which the log names. A value comparison program that fails to compile or run is never kept and so compiles on every run: compare `HEAD`'s "Value comparison programs" count with `BASE`'s second run, not with 0.
3. **`generate`** builds a release `SafeDITool` at `BASE`, `HEAD` and tag 2.2.0, then `stage2.py` runs `generate` on each shape, per module in build order as the Bazel rule and the Tuist plugin run it. Each round runs the three tools in a rotated order; a run's wall and CPU are summed over the modules and its peak memory is the largest module's. It prints each tool's median and range, then a verdict per shape.

2.2.0 is built from its tag and only ever run through `generate`, never through its tests, which write into the system temporary directory. It is run without `--module-name` and `--package-name`, which it does not have.

## Shapes

`make_fixtures.sh` writes them, once, into `WORK/fixtures`; delete that directory after changing a generator.

- `issue646-12`, `issue646-16`, `issue646-mock-12`: the graph of issue #646, one module, at 12 and 16 screens, and at 12 with `generateMock: true`.
- `N1-40`, `N1-200`: a seam that instantiates a builder of each screen, where each screen receives the next three screens' builders, so the screens form a loop. 2.2.0 rejects this graph as a dependency cycle, so it has no 2.2.0 figure.
- `N5i-8`, `N5i-10`: layers of four screens where every screen is a seam and opens three screens of the next layer. `N5inline-8`, `N5inline-10` are the same graph without seams in one module, which is how a 2.2.0 user writes it: compare 2.2.0 with these. 2.2.0's tool also runs on the `N5i` sources, but its macros reject `generateDependencyTree`, so that row is not a build a 2.2.0 user has.
- `E6d-600`, `E6d-1200`: that many independent seams, each with a hole the root's module fills; `-inline` is the same without seams.

A tool that rejects a shape is printed as "rejected" with the start of its error, and the shape has no verdict.

## Reading the verdict

`bands.json` holds how much `HEAD` may exceed `BASE`: 3% for CPU and for peak memory, and for wall the shape's own spread between two builds of one commit, clamped to 3%–6%. `N1-200` is judged on minimums, the others on medians. The last line is `GATE PASSED` or `GATE FAILED on <shapes>`, and the script exits 1 on a failure.

- Peak memory repeats within about 2% between runs, so a memory failure is real when the two ranges do not overlap.
- Wall and CPU are only as good as the machine is quiet. The verdict table gives each tool's spread (range over median); when spreads are several times the band, run again on an idle machine before believing a wall or CPU failure, or a pass that sits just under the line.
- The bands were measured on a Linux cloud machine. To measure them for another machine, run `stage2.py` with two builds of one commit labelled `A1` and `A2`; it prints each shape's spread.

## Stating a figure

Every speed or memory figure for the generator is stated against 2.2.0 for the same graph, written as a 2.2.0 user would write it (inline, without seams). A change that only removes work a later release added repays a regression; say so, and do not call it a speedup. A shape 2.2.0 rejects has no 2.2.0 figure; say that too.

To check the scripts after changing them, run one round of two small shapes, which takes a quarter of an hour when the three tools must be built and seconds afterwards. One round is a check that the scripts run, not a verdict: two builds of one commit can fail a 3% band on a single run.

`ROUNDS=1 STEPS=generate SHAPES=issue646-12,N5inline-8 BASE=<commit> HEAD=<commit> bash .claude/skills/generate-benchmark/run-gate.sh`.
