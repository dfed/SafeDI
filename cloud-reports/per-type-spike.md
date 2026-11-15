# Spike 1: one generated function per type in production trees

- Branch: `claude/project-thread-4xgw6h` (this machine may push only its own `claude/…` branch). Base: `2475984` (main). Head: see the hand-back.
- `swift --version`: Swift version 6.2 (swift-6.2-RELEASE), Target: x86_64-unknown-linux-gnu. One cloud Linux machine, 4 cores, 15 GB.
- Nothing merged, no pull request, nothing posted.

## What the numbers answer, and what they do not

They answer four questions:

- whether one function per type keeps every value and every lifetime the per-path emitter gives;
- how much of today's generated root code is copies;
- whether cycles collapse to one function per type;
- what a worst-case synthetic graph costs to compile and run under each emitter.

They do not answer two questions:

- how a real app's graph is shaped. The repository's tests and examples are small, and section B is synthetic by design.
- what the go/no-go figure is. That decision is not mine.

## What is built

**`Sources/SafeDICore/Generators/PerTypeEmission.swift`** is a pass over the per-path text of a root's `init()` body. It parses the body with SwiftParser and resolves every name lexically. It then rewrites the body so that builder functions that build the same thing become one function. It runs in two stages, repeated until nothing changes.

1. **Acyclic stage.** Builder functions are grouped by text key: the function's text without indentation, with its own name abstracted. Innermost groups go first. Each group with two or more places becomes one function:
   - It is placed at the innermost body that every call passes through, before the first statement that reaches a call.
   - A read becomes a capture where every member resolves it to one declaration visible there. Otherwise it becomes a parameter, in first-read order.
   - `@Sendable` spreads to the shared function from any member.
2. **Cyclic stage**, for functions that call one another around a cycle. Their per-path texts differ by nesting, so no text key matches.
   - Classes start from each function's text with three things abstracted: nested builder functions removed, references to builder functions, and `x: x` versus `x: nil` arguments.
   - Classes are refined by the classes of the functions each one calls, until no class splits. This is bisimulation.
   - Every class with two or more members, and every class those members call, moves to one block of local functions. Swift local functions may call one another, so mutual recursion needs nothing more.
   - A read becomes a parameter where members resolve it to different declarations, or where it is not capturable at the block.
   - `nil` is a declaration of its own, so a call passes `p: nil` or `p: p`.
   - A label that a called function takes as a parameter is read by its caller too, as a fixed point.
   - A builder parameter that is `T` in one member and `T?` in another is `T?`. A member with `T?` compiles the same text, so the shared text compiles.

**The emitter.** `ScopeGenerator.generatePropertyCode` applies the pass to every production root `init()`. `SAFEDI_PER_PATH_EMISSION=1` keeps today's text. The pass leaves alone a seam's initializers, mocks, `.safedi` files and diagnostics.

**A tree in which every key has one place is byte-identical**, by construction: the pass edits nothing without a group.

**Tests and scripts:**

- `Tests/SafeDIToolTestSupport/SafeDIToolTestExecution.swift`: `SAFEDI_SPIKE_DUMP_DIRECTORY` dumps every test's generated files before any assertion.
- `Tests/SafeDIToolFuzzerTests/SpikePerTypeCorpusTests.swift`: the corpus check.
  - It generates each accepted graph per path, applies the pass, and checks that a second pass changes nothing.
  - Where the text changed, it compiles both and compares values and retention through `DifferentialValueOracle`, with retention judging on.
  - In text-only mode it also runs the real emitter and requires it to agree with the pass on every file.
- `bench/wide_graph.py` (the brief's), `bench/measure.py` (CSV and package modes) and `bench/compare_dumps.py`.

## Worked example

The output matches the brief's 27-line form:

- grandchildA and grandchildB are hoisted and `@Sendable`;
- grandchildB takes `recreated:`;
- the body goes from 33 lines to 24.

## Section A: the repository's tests

Commands:

- Base dumps: `swift test --traits sourceBuild --filter 'SafeDIToolDependencyTreeTests|SafeDIToolTests'` with `SAFEDI_PER_PATH_EMISSION=1` and `SAFEDI_SPIKE_DUMP_DIRECTORY=dump-base`. The script is `runA.sh`, not committed.
- Spike dumps: the whole suite through the test bundle with `SAFEDI_SPIKE_DUMP_DIRECTORY=dump-spike` and `SAFEDI_SPIKE_STATS_FILE=stats.jsonl`.
- Comparison: `python3 bench/compare_dumps.py dump-base dump-spike --json A.json`.

Over the root trees both runs share:

| Measure | Base (per path) | Spike (per type) |
|---|---|---|
| Root trees | 738 | 738 |
| Root-tree lines | 13,853 | 13,640 |
| Share of root-tree lines that are copies | | **1.54%** |
| Trees that build a type in two or more functions | 34 | 14 |
| Tests whose files changed | | 26 (2 more differ only in a temporary fixture path) |

The ten largest reductions, in lines:

| Base | Spike | Test |
|---|---|---|
| 83 | 31 | `ReceivedBuilderCycleRetentionTests`, `generatedCode_freesWhatItsOwnerReleases_whenEachLoopMemberFunctionTakesTheOtherAsCycleParameter` |
| 83 | 31 | `ReceivedBuilderCycleTests`, `generate_declaresReceivedFunctionForEachMember_whenEachMemberFunctionTakesTheOtherAsCycleParameter` |
| 33 | 21 | `CodeGenerationErrorTests`, `generate_rebindsSiblingInstantiator_whenSiblingInstantiatorIsReceivedInsideLazyCycleOfEarlierSibling` |
| 34 | 25 | `CodeGenerationTests` (line 2489) |
| 29 | 21 | `ReceivedBuilderCycleTests` (line 1359) |
| 16 | 9 | `CodeGenerationTests` (line 5814) |
| 28 | 22 | `LazyCycleNearestDeclarationTests` (line 3248) |
| 25 | 19 | `LazyCycleNearestDeclarationTests` (line 2448) |
| 42 | 36 | `LazyCycleNearestDeclarationTests` (line 3091) |
| 29 | 23 | `LazyCycleNearestDeclarationTests` (line 3615) |

**`Examples/`, CSV mode.** Each project's files go to `SafeDITool generate … --combined-output` under each emitter: Bazel with `--active-compilation-conditions DEBUG`, and the multi-module examples without their subprojects' configuration files.

- All 5 examples are byte-identical, so 0% of their lines are copies.
- None builds a type twice.

These examples and tests are the nearest proxy for a realistic graph, and both are small. They build few types twice, so they say little about a large app. The realistic benchmark decides that.

**Spike stats over every production tree the whole suite generated**: 5,080 trees, the fuzzer suites' included.

- Lines: 120,658 → 113,508.
- Types built by two or more functions: 2,551 → 1,747.
- Shared: 614 groups (1,499 places) in the acyclic stage, and 134 cyclic components (375 groups, 812 places).
- Kept per path: 19 types (39 places) where one place reads `nil` and another a value, outside a cycle.
- Not shared, per tree:

| Trees | Reason |
|---|---|
| 272 | the subtree holds a seam call |
| 73 | a statement the pass does not model (`switch`, `if`, `guard`, a closure with parameters) |
| 27 | a group that is not shared |
| 25 | members call different enclosing functions |
| 15 | members read different labels |
| 7 | skipped: the per-path text does not parse at that depth |
| 5 | skipped: deeper than 48 levels |

## Section B: synthetic wide graph (worst case, synthetic — no headline figure from it)

Graphs come from `python3 bench/wide_graph.py OUT LAYERS [--cyclic] [--path-values] [--skip-layer]`. Each configuration was measured with:

`python3 bench/measure.py csv B/<config>/files.csv --driver B/<config>/main.swift --variant base=<main's release SafeDITool> --variant spike=<this branch's release SafeDITool> --safedi <this checkout> --trace --compile-runs 5 --workdir mb/shared --json mb/<config>.json`

How the measurements were taken:

- Swift 6 mode, warnings as errors.
- Base and spike runs alternate.
- Runtime is the release build with `-Xswiftc -DNO_TRACE`, `--time 11`, 11 runs.
- `-Onone` times the batch frontend invocation whose primary file is `Generated.swift`; `-O` times the whole module. Each command was rerun alone from `swift build -v`, without `-supplementary-output-file-map`.
- The load average stayed between 1.0 and 1.4 during the runs. The measuring process itself accounts for one core, and nothing else was running.
- No single compile exceeded 5 minutes, so every configuration has 5 compile runs.

Configuration names: `dag` is a DAG, `pv` is `--path-values`, `pvs` is `--path-values --skip-layer`, `cyc` is `--cyclic`, `cycpv` is `--cyclic --path-values`. The number is the layer count.

Each figure is the median, with (min–max, n) for compile times and (min–max) over 11 runs for runtime.

| Config | Variant | Lines | Bytes | -Onone CPU s | -Onone wall s | -O CPU s | -O wall s | Construction µs | Walk µs | generate wall s |
|---|---|---|---|---|---|---|---|---|---|---|
| dag3 | base | 377 | 20,134 | 0.54 (0.51–0.58, n=5) | 0.55 | 1.25 (1.19–1.35, n=5) | 1.24 | 0.2 (0.1–0.2) | 6.7 (4.7–7.8) | 0.03 |
| dag3 | spike | 145 | 6,964 | 0.45 (0.43–0.47, n=5) | 0.47 | 1.11 (1.02–1.21, n=5) | 1.12 | 0.2 (0.1–0.2) | 6.9 (4.7–7.5) | 0.06 |
| dag4 | base | 1,133 | 66,061 | 0.78 (0.76–0.84, n=5) | 0.79 | 1.68 (1.63–1.78, n=5) | 1.70 | 0.2 (0.1–0.5) | 18.0 (16.7–35.0) | 0.05 |
| dag4 | spike | 197 | 9,577 | 0.58 (0.57–0.65, n=5) | 0.60 | 1.26 (1.13–1.30, n=5) | 1.25 | 0.2 (0.2–0.3) | 20.9 (15.1–27.5) | 0.12 |
| dag5 | base | 3,401 | 212,833 | 1.57 (1.52–1.64, n=5) | 1.62 | 3.06 (2.83–3.21, n=5) | 3.08 | 0.3 (0.2–0.5) | 89.4 (61.8–96.2) | 0.09 |
| dag5 | spike | 249 | 12,237 | 0.84 (0.76–0.88, n=5) | 0.87 | 1.36 (1.23–1.40, n=5) | 1.37 | 0.3 (0.1–0.5) | 73.6 (44.0–79.8) | 0.34 |
| dag6 | base | 10,205 | 680,347 | 3.71 (3.56–3.79, n=5) | 3.75 | 7.75 (7.07–8.12, n=5) | 7.80 | 0.6 (0.4–1.2) | 226.0 (188.1–347.8) | 0.25 |
| dag6 | spike | 301 | 14,944 | 0.94 (0.93–1.16, n=5) | 0.99 | 1.73 (1.66–2.16, n=5) | 1.74 | 0.3 (0.2–0.5) | 150.5 (134.3–241.3) | 1.43 |
| dag7 | base | 30,617 | 2,164,609 | 9.21 (8.88–9.74, n=5) | 9.29 | 18.57 (18.37–19.04, n=5) | 18.60 | 1.5 (0.7–2.3) | 958.3 (640.2–1097.4) | 0.53 |
| dag7 | spike | 353 | 17,557 | 1.03 (0.96–1.25, n=5) | 1.05 | 1.61 (1.58–1.71, n=5) | 1.64 | 0.6 (0.4–1.5) | 658.3 (445.6–722.9) | 5.73 |
| pv3 | base | 389 | 21,750 | 0.67 (0.62–0.73, n=5) | 0.69 | 1.50 (1.36–1.66, n=5) | 1.50 | 0.1 (0.1–0.3) | 7.2 (6.7–12.2) | 0.04 |
| pv3 | spike | 149 | 7,672 | 0.59 (0.55–0.67, n=5) | 0.61 | 1.45 (1.14–1.74, n=5) | 1.45 | 0.1 (0.1–0.3) | 7.3 (6.7–10.8) | 0.08 |
| pv4 | base | 1,253 | 76,749 | 1.10 (1.04–1.13, n=5) | 1.13 | 2.03 (1.91–2.47, n=5) | 2.06 | 0.3 (0.1–0.7) | 27.6 (23.0–54.1) | 0.06 |
| pv4 | spike | 205 | 10,569 | 0.80 (0.74–0.83, n=5) | 0.84 | 1.40 (1.35–1.86, n=5) | 1.44 | 0.3 (0.1–0.7) | 33.5 (22.9–42.7) | 0.21 |
| pv5 | base | 3,521 | 229,353 | 1.89 (1.77–1.91, n=5) | 1.92 | 3.62 (3.51–3.83, n=5) | 3.64 | 0.3 (0.3–0.4) | 94.9 (86.1–131.9) | 0.13 |
| pv5 | spike | 257 | 13,589 | 1.01 (0.94–1.08, n=5) | 1.06 | 1.55 (1.41–1.59, n=5) | 1.57 | 0.2 (0.1–0.3) | 69.9 (61.5–102.2) | 0.42 |
| pv6 | base | 11,297 | 786,291 | 4.53 (4.35–4.80, n=5) | 4.63 | 9.31 (8.81–10.09, n=5) | 9.41 | 0.6 (0.5–1.0) | 303.1 (247.7–408.9) | 0.33 |
| pv6 | spike | 313 | 16,588 | 1.25 (1.19–1.33, n=5) | 1.30 | 1.84 (1.73–1.96, n=5) | 1.87 | 0.3 (0.2–0.6) | 217.2 (188.6–335.8) | 1.50 |
| pvs3 | base | 417 | 23,291 | 0.70 (0.67–0.79, n=5) | 0.71 | 1.49 (1.38–1.91, n=5) | 1.50 | 0.2 (0.1–0.3) | 10.9 (7.1–12.6) | 0.04 |
| pvs3 | spike | 173 | 8,960 | 0.67 (0.64–0.69, n=5) | 0.68 | 1.33 (1.25–1.61, n=5) | 1.38 | 0.2 (0.1–0.4) | 11.0 (7.0–12.2) | 0.07 |
| pvs4 | base | 1,473 | 89,675 | 1.22 (1.10–1.28, n=5) | 1.28 | 2.27 (2.06–2.35, n=5) | 2.33 | 0.2 (0.1–0.4) | 28.7 (25.4–50.3) | 0.07 |
| pvs4 | spike | 255 | 13,282 | 0.85 (0.76–0.88, n=5) | 0.89 | 1.55 (1.48–1.60, n=5) | 1.57 | 0.2 (0.1–0.3) | 26.4 (24.0–43.1) | 0.22 |
| pvs5 | base | 4,525 | 291,812 | 2.44 (2.35–2.62, n=5) | 2.52 | 4.96 (4.63–5.84, n=5) | 4.98 | 0.5 (0.4–0.7) | 182.6 (117.6–191.7) | 0.13 |
| pvs5 | spike | 333 | 17,751 | 1.09 (1.04–1.16, n=5) | 1.14 | 1.77 (1.58–2.48, n=5) | 1.78 | 0.4 (0.2–0.5) | 142.2 (91.8–180.5) | 0.57 |
| pvs6 | base | 16,045 | 1,100,777 | 5.96 (5.32–6.91, n=5) | 6.05 | 13.50 (12.15–15.55, n=5) | 13.53 | 1.0 (0.7–2.3) | 596.9 (417.9–701.7) | 0.42 |
| pvs6 | spike | 477 | 25,846 | 1.33 (1.17–1.47, n=5) | 1.37 | 2.49 (2.02–2.55, n=5) | 2.51 | 0.7 (0.4–1.8) | 481.2 (272.6–530.5) | 2.51 |
| cyc2 | base | 8,735 | 602,551 | 3.14 (2.81–3.68, n=5) | 3.17 | 6.23 (5.65–6.34, n=5) | 6.25 | 0.2 (0.1–0.2) | 8.9 (8.6–13.0) | 0.27 |
| cyc2 | spike | 129 | 6,107 | 0.48 (0.42–0.53, n=5) | 0.49 | 1.15 (0.95–1.30, n=5) | 1.18 | 0.1 (0.1–0.3) | 8.6 (7.8–15.0) | 1.09 |
| cyc3 | base | 69,224 | 5,537,555 | 26.26 (24.06–26.66, n=5) | 26.46 | 43.71 (41.14–47.01, n=5) | 43.74 | 0.3 (0.2–0.6) | 31.4 (27.7–57.4) | 1.57 |
| cyc3 | spike | 181 | 8,734 | 0.64 (0.56–0.65, n=5) | 0.65 | 1.29 (1.13–1.57, n=5) | 1.30 | 0.2 (0.1–0.3) | 27.5 (23.6–43.9) | 11.40 |
| cycpv2 | base | 9,130 | 660,161 | 3.87 (3.76–4.52, n=5) | 3.93 | 7.81 (7.73–9.37, n=5) | 7.84 | 0.2 (0.1–0.3) | 13.2 (12.1–21.9) | 0.49 |
| cycpv2 | spike | 133 | 6,797 | 0.57 (0.54–0.59, n=5) | 0.59 | 1.13 (1.09–1.31, n=5) | 1.15 | 0.2 (0.1–0.3) | 12.1 (11.7–20.0) | 1.72 |
| cycpv3 | base | 71,023 | 5,975,066 | 31.12 (29.93–34.99, n=5) | 31.35 | 54.59 (53.62–57.07, n=5) | 54.78 | 0.3 (0.3–0.4) | 55.4 (49.7–68.2) | 5.28 |
| cycpv3 | spike | 185 | 9,878 | 0.69 (0.66–0.81, n=5) | 0.72 | 1.40 (1.31–1.43, n=5) | 1.39 | 0.2 (0.1–0.2) | 37.8 (34.6–42.9) | 18.53 |

**Not measured:** `cyc4` and `cycpv4`. The base emitter generates 323,569 and 336,780 lines for them. The spike's post-pass ran out of memory at 11 GB on that text: it renders a key from every nested function's whole text. An emitter that never builds the per-path text has no such step.

**What it shows (worst case, synthetic):**

- **Runtime is the same or better.** Construction is the same; the root builds only instantiators. The walk overlaps base within spread on small graphs and is lower at the median on larger ones: `dag7` 958 → 658 µs, `pv6` 303 → 217 µs, `pvs6` 597 → 481 µs, `cycpv3` 55 → 38 µs. Nothing is slower beyond the spread.
- **Compile time falls with the text.**
  - At `-Onone`: `dag7` 9.21 → 1.03 s, `cyc3` 26.3 → 0.64 s, `cycpv3` 31.1 → 0.69 s.
  - At `-O`: `cyc3` 43.7 → 1.29 s, `cycpv3` 54.6 → 1.40 s.
  - The `-stats-output-dir` counters show it is type checking: `Sema.NumDeclsTypechecked` for the generated file is 47,920 → 121 in `cyc3`, 21,865 → 241 in `dag7`, and 13,493 → 341 in `pvs6`.
- **Size grows linearly in layers for the spike** (`dag3`–`dag7`: 145, 197, 249, 301, 353 lines). The base triples per layer.
- **`generate` wall is information only.** It is slower here, up to 18.5 s for `cycpv3`, because the spike first generates per path and then parses and rewrites the text. A production emitter does not, so these figures do not predict its cost.
- **Where it falls back:**
  - In `pvs` graphs a type reads `nil` on one path and a value on another, and it keeps one function per outcome in the acyclic stage. This is why `pvs6` is 477 lines against `pv6`'s 313.
  - The synthetic graphs hit no other fallback.

**Traces (C1):** identical for all 17 configurations; trace lengths run from 213 to 17,493 lines.

## Section C: values and lifetimes

**C1. Traced synthetic drivers.** Both variants are built in debug (`measure.py … --trace`) and their creation traces compared byte for byte. Every configuration in section B has identical traces: the same creations in the same order, the same releases, and nothing alive at `end`. There are no free-order differences.

**C2. Fuzzer base corpus, seeds 0..<5000**, with the final pass. The command, in four shards:

`SAFEDI_PER_PATH_EMISSION=1 SAFEDI_SPIKE_CORPUS=0-1250 SAFEDI_SPIKE_CORPUS_REPORT=… SafeDIPackageTests.xctest --testing-library swift-testing --filter SpikePerTypeCorpusTests`

| Measure | Count |
|---|---|
| Rejected by the tool (both emitters) | 2,620 |
| Accepted, text unchanged | 1,170 |
| Accepted, text changed | 1,210 |
| Changed graphs compiled and compared (values and retention) | 1,210 (none skipped) |
| Value differences | **0** |
| Retention differences | **0** (retention judged in 1,209 graphs; 1 had no probe to judge) |
| Graphs a second pass changes | **0** |
| Generated lines in the changed graphs | 229,815 → 198,947 (−13.4%) |

The first run of the final cyclic stage found 5 graphs whose shared text did not compile (seeds 2529, 4179, 4462, 4549 and 4684). A shared function called another that takes a label as a parameter, and the caller did not pass that label through. Seed 4684 also left an unused binding. The fix makes a caller read every label its calls pass. All 5 now compile and compare equal, and the rerun above includes it.

**Fuzzer long run** (`SafeDIToolGraphFuzzerTests/longRun`, 4 shards) on the spike emitter: all pass. Their known issues are the pinned shapes the run already lists, with no unexpected failure. The base-corpus value oracle is one of its checks. It ran on the build before the cyclic stage.

**C3. Seam corpus** (`generateDependencyTree`, seeds 0..<1000) and **public-mock corpus** (`generateMockPublic`, seeds 0..<1000), text only. Each run also runs the real emitter and requires it to agree with the pass on every file.

| Corpus | Accepted | Changed graphs | Files changed | Changed files that are not a root's | Emitter disagrees |
|---|---|---|---|---|---|
| Seam | 289 | 44 | 82 | 0 | 0 |
| Public mock | 856 | 0 | 0 | 0 | 0 |

Seam bodies and every mock are byte-identical, and only root callers change.

**C4. The key oracle:**

- Idempotence holds on every graph of all three corpora: places that share a key generate one function, and a second pass finds nothing more to share.
- Every call resolves to its key's function. The pass refuses a group where any call would resolve to another declaration ("a site would resolve to another declaration"), or where a passed label resolves elsewhere at a call. The compile and value checks above confirm it on every changed graph.
- Places split only by `nil` are counted: 39 places of 19 types across the suite, all outside cycles.

## Failure classes and not-shared cases

Full suite on the spike emitter (`SafeDIPackageTests.xctest --testing-library swift-testing`): 5,246 tests in 173 suites ran, and 40 tests recorded an issue that is not a known issue.

- **(a) Text changed where a type has two or more places (intended): 35 tests.** Every changed root file the dumps cover built a type in two or more functions in the base. The only exceptions are two whose sole difference is a temporary fixture path.
  - The tests are in CodeGeneration ×7, LazyCycleNearestDeclaration ×9, SeamUncreatedAlias ×5, SeamLabelKeepingAlias ×3, KeywordLabel ×2, ReceivedBuilderCycle ×2, SeamLazyCycle ×2, CodeGenerationError, DeferredHopCycle, SeamHiddenReceive, SeamPlainInitializer and AccessEnforcement.
  - The seam tests' changes are in the root callers' trees, never in a seam's own body.
  - The compile verifier compiled every one without a warning.
- **(a′) A lazy value at a closing call created at first read: 0**, because the fix is not implemented (see Deviations).
- **(b) Changed where every key has one place: 0.** The pass edits nothing without a group of two or more.
- **(c) A diagnostic or `.safedi` change: 0.**
- **(d) Generated code that does not compile: 0 in the suite.** 5 in the corpus before the final fix, 0 after (C2).
- **(e) A parameter type that does not compile or resolves to another declaration: 0.**
- **(f) A moved fuzzer pin or known-failure list: 0.** The fuzzer suites, the long run included, pass unchanged.
- **Spike-only, not a generator class: 4 `SourceRuleTests`.** The spike file breaks four of the repository's source rules: `try?` under Generators, a `__safeDI_` literal outside `ReservedName.swift`, a straight apostrophe in a literal, and an error type that `ErrorReportingSite.byErrorType` does not list. A production version would follow the rules.
- **Environment, not the spike: 1.** `generate_declaresOneEnumPerTypeAndCallerCompiles_whenPublicMocksTwentyFourScreensReachEachOtherInLayers` was killed by the compiler with signal 9. This is the known cloud out-of-memory failure of that test in a full run; it involves only mocks, which the pass does not touch.

## Deviations from the brief

- **The key is the text, plus a cyclic stage.** Places of one type are shared when their text matches once outside reads are abstracted. The cyclic stage then joins functions that differ only in which functions they call and whether a label is `nil`. A pure text key would miss every cycle. The brief's oracle holds on the output: every graph is idempotent, so a second pass shares nothing more.
- **Path values (`nil` against a value) are split in the acyclic stage and joined in the cyclic one.**
  - In a DAG, a type that reads `nil` on one path and a value on another keeps two functions. The stats count these as `typesSplitOnlyByNil` and `placesSplitOnlyByNil`.
  - In a cycle, the label becomes a parameter that the call passes as `nil` or as a value.
  - Joining them in a DAG is the same mechanism and is left for productionizing.
- **(a′), the lazy value at a cycle's closing call created at first read, is not done.** A closing call still passes `x.instance`, as today. That fix needs a function per provided form, which is the production design's job. The spike shares only what exists.
- **A `@Sendable` shared function takes every read as a parameter.** Fills, `_ =` guards, control flow and closures with signatures are not shared.
- **The pass is a post-pass over text, not an emitter.** That is the spike's shortcut. Two costs follow:
  - Trees deeper than the parser's nesting limit (7 tests' trees) stay per path.
  - On the largest cyclic graph (`--cyclic` at 4 layers, 323,569 lines per path) the pass ran out of memory at 11 GB.
  - An emitter that writes one function per type never builds the per-path text, so neither limit applies to the design.

## Recommended design

**Build it into the emitter, not as a pass over text.** The emitter should write one builder function per (concrete type, provided form) in each body, keyed by the outcome of each received form. Three things follow:

- **The key** is the type built, the form provided, and for each label the body reads: which declaration it resolves to, `nil`, or "passed". Labels, renames, `@Sendable` and whether a declaration exists stay out of it, as the brief says. The spike shows this is the right equivalence: once reads are abstracted, text equality plus the classes of the functions called (bisimulation) gives one function per type in every synthetic cycle and every corpus graph it could model.
- **Placement**: one block of local functions at the lowest body every call passes through, before the first statement that reaches a call. Mutual recursion needs nothing more, because Swift local functions in one block can call one another.
- **Reads**: capture where every place resolves the read to one declaration that is visible and declared before the block. Otherwise the read is a parameter, and `nil` is just an argument. A call passes on every label its callee takes (a fixed point). A builder parameter takes the optional type where any place reads it optionally.

**What to keep from today's emitter:**

- the per-path walk, to decide availability, ordering and `nil`;
- the cycle-closing analysis, which already names the declaration closed on, so the classes come from the scope graph instead of from text;
- the generated-name allocator, for the shared names.

**What changes for adopters:** only the text of production root bodies. Signatures, diagnostics, `.safedi` files, seams and mocks stay as they are, and values and lifetimes are unchanged on every graph this spike compared.

**The (a′) fix** comes with this design: one function per provided form means a closing call can hand the lazy wrapper rather than its `instance`.

## Open questions (not mine to decide)

- The go/no-go figure. Section B is a worst case; the real benchmark decides.
- Whether a lazy value at a cycle's closing call should be created at first read: the (a′) fix, which the brief already records as decided.
- Extending the design to seam bodies and to mocks. Both are untouched here.
- Final naming of the shared functions. The spike uses the label's builder name, made unique with `_`.
- Whether to join `nil`-split places in DAGs too.

## Size of productionizing

About **2–3 weeks** for one engineer, plus review. The pieces:

1. **Emitter (5–7 days).** Compute the classes from the generator tree: type, form, the resolution of each read, and the callee classes refined to a fixed point. Emit one block per lowest common body, and thread the passed labels.
   - It replaces `ScopeGenerator`'s per-path nesting for production roots. The per-path walk stays, to decide availability and order.
   - The spike's 1,300 lines of text analysis become a tree analysis with no parser and no lexical resolver.
2. **Expectations (2–3 days).** Regenerate the 35 tests of class (a) with the repository's expectation tool and review each by hand. Add a full-output pin per rule: one type shared, a cycle, a cycle with path values, a passed label, and an optional parameter.
3. **Fuzzer (2–3 days).**
   - An oracle that every production tree builds each (type, form, read outcome) in one function. This is the key oracle, run on the tree rather than on text.
   - Make the corpus differential against today's emitter part of the base corpus for one release.
4. **(a′) (2 days).** Hand the wrapper at a cycle's closing call, and drop the "Eager instances at a lazy cycle's calls" gap.
5. **Seams and mocks: not estimated.** Extending to them is a decision that is not mine.

## Leftovers

Each leftover belongs to the production pull request unless it says otherwise:

- **Sharing through a seam call, fills, control flow and closures with parameters.** In the spike these trees fall back to per path (345 trees in the suite). The emitter version reads them from the tree, so the fallback goes away.
- **`nil` against a value outside a cycle** stays split (19 types in the suite). The production key already treats it as a passed label, so this disappears with the emitter.
- **(a′)**: in the production pull request, as the brief records it as decided.
- **The spike's own source-rule hits**: none in production code, since the production emitter is new code.
- **The parser's depth limit and the memory used on the largest cyclic graph**: properties of a post-pass, gone with the emitter.
- **The test-only pass and `SAFEDI_PER_PATH_EMISSION`.** Keep both for one release as the differential's known-right path, then remove them in the release after (2.4.0 or later), once the base corpus has run against the new emitter.

## Draft PR description

**Generate one builder function per type in production dependency trees**

SafeDI wrote a builder function for every place a type is built. A type built under several parents, or around a cycle, appeared once per path, so a root's `init()` grew with the number of paths, not the number of types. A cyclic graph of 12 screens generated 69,224 lines.

Production trees now build each type, for each form it provides and each way its reads resolve, in one local function. The function sits at the innermost body every call passes through. A read every place resolves to the same declaration is captured, and any other read becomes a parameter that each call passes, `nil` included. Functions that call one another around a cycle become one block of mutually recursive local functions. That same cyclic graph now generates 181 lines.

The values and lifetimes are unchanged. Every accepted graph of the fuzzer's base corpus whose output changed was compiled under both emitters, and its values and retention compared, with no difference. Seam bodies, mocks, signatures, diagnostics and `.safedi` files are unchanged. Only production root bodies change.

Tests: the expectations of trees that build a type more than once are updated. New pins cover a shared type, a cycle, a cycle with path values and a passed label. A fuzzer oracle checks that each tree builds each type in one function.

Leftovers:

- The emitter of earlier releases stays behind a test option for one release, as the differential's reference, and is removed after.
- Seams and mocks keep per-path builders; extending them is a separate decision.

## Time and friction

About 4 hours of work in two stretches, on 2026-11-15 between 15:15 and 19:55 UTC. The stretches were split by the usage pause (about 40 minutes).

Checkpoints reached: 1 (the worked example and section A), 2 (section C) and 3 (section B). Each was pushed.

Friction:

- Cloud machines lack Swift, so 6.2 was installed first.
- Parallel `swift test` runs wait on SwiftPM's build lock. Running the test bundle directly (`SafeDIPackageTests.xctest --testing-library swift-testing --filter …`) avoids it. A second scratch path (`--scratch-path`) let tests rebuild while the long fuzzer run used the first build.
- `measure.py` rebuilt the SafeDI library for every graph, about 8 minutes each. It now keeps the driver package's `.build` across graphs.
- One `SafeDITool` run was killed by the kernel at 11 GB on the 4-layer cyclic graph (see section B).
- In a full-suite run in a cloud container, the 24-screen public-mock test runs out of memory, as known.
