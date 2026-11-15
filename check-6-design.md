# Check 6 design: every graph 2.2.0 accepts is still accepted, with the same values

Phase 1 design note. Phase 2 removes this file and moves its lasting rules into `.claude/rules/fuzzer-value-oracles.md` (or a new rules file under the size limit).

Base: `origin/main` at `247598444e66ab6776891fde798c1cdb7c329c38` when the branch was cut. Branch: `dfed--claude/check-6-release-acceptance`.

The spike's code is not in this tree. It is kept beside the project's shared files as `check-6/spike.patch`, with its three reports. It is a temporary `Check6SpikeTests` test plus the comparator change of question 4, run with `swift test --traits sourceBuild --skip-build --filter Check6SpikeTests` and five environment variables naming 2.2.0's built tool, its `Sources/SafeDI`, its `Modules` directory, its macros and a report path.

Machine for every figure below: the cloud worker, 4 cores (Intel Xeon at 2.10 GHz), 15 GB of memory, Ubuntu 24.04, toolchain `Swift version 6.2 (swift-6.2-RELEASE)`, target `x86_64-unknown-linux-gnu`, from the swift.org tarball `swift-6.2-RELEASE-ubuntu24.04.tar.gz`. Every figure is a cloud-machine figure; confirm on CI.

**First: 2.2.0 accepts more than half of what main accepts, but not by much.** Over seeds 0 to 19, main accepts 13 graphs and 2.2.0 accepts 7 of them (54%). Over seeds 0 to 199, main accepts 100 and 2.2.0 accepts 63 of them (63%); 2.2.0 accepts no graph main rejects. 24 of the 37 graphs main accepts and 2.2.0 rejects are one 2.2.0 defect, below.

## 1. Obtaining 2.2.0

- **Commands** (run, both succeeded with no error on Swift 6.2), in a separate checkout, `TMPDIR` outside both checkouts:
  ```
  git worktree add ../safedi-2.2.0 2.2.0          # 8596f075f
  cd ../safedi-2.2.0
  TMPDIR=~/.cache/swiftpm-tmp-old swift build -c release --traits sourceBuild --product SafeDITool   # 7 min 57 s
  TMPDIR=~/.cache/swiftpm-tmp-old swift build -c release --traits sourceBuild --product SafeDI       # 6 min 58 s
  ```
  Release, because the tool runs once per seed (5000 runs) and `swift-syntax` in debug parses several times slower. The second command builds `SafeDIMacros-tool`, the macros the library loads, and `Modules/SafeDI.swiftmodule`. No test of the tag was built or run.
- **Build time:** 7 min 57 s, then 6 min 58 s (about 15 min). The second build overlapped main's own debug test build for its first minute; neither number is clean. That 2.2.0 builds in CI's `swift:6.2` container is not checked.
- **What the comparing shards need:** three things only. `.build/release/SafeDITool`, `.build/release/SafeDIMacros-tool`, and the tag's `Sources/SafeDI` directory. The comparator compiles 2.2.0's runtime from those sources with 2.2.0's macros, as it compiles main's today. The built `Modules/SafeDI.swiftmodule` is not needed.
- **Delivery:** one build job (`Build SafeDI 2.2.0 on Linux`) restores or fills an `actions/cache` entry keyed `safedi-release-2.2.0-8596f075f-${{ runner.os }}-swift-6.2-<container image digest>`, and uploads the three things as one artifact (about 120 MB) that each comparing shard downloads. An artifact rather than a cache read per shard, so that every shard of one run uses the same bytes. On a cache hit the job takes about a minute.
- **The passed-compile-check cache:** every compile check 6 makes bypasses it. Check 6 compiles through `compileSwift` and the `DifferentialValueOracle`, neither of which reads `SAFEDI_COMPILE_CHECK_PASSED_CACHE` (only `SafeDICompileVerifier.swift` lines 86 and 133 do), so nothing goes into `.github/scripts/compile-check-identity.sh`. Phase 2 adds a comment at the harness's compile saying it must not use that cache.

## 2. Invocation

- **2.2.0's command line for seed 0** (paths shortened to `<dir>`), as 2.2.0's SwiftPM plugin runs it, `scan` then `generate`:
  ```
  SafeDITool scan --input-sources-file <dir>/sources.csv --project-root <dir> --output-directory <dir>/Output --manifest-file <dir>/manifest.json --mock-scoped-files <dir>/Fixture/S0_Ext.swift … <dir>/Fixture/S0_TupleReader.swift
  SafeDITool generate <dir>/sources.csv --swift-manifest <dir>/manifest.json
  ```
  The generated files are every `.swift` file in `<dir>/Output`. A non-zero exit of either command is a tool rejection; its standard error is the diagnostic.
- **Main's side runs in process,** through `GraphFuzzerOracle.toolOutcome(of:)`, exactly as the base corpus runs it (`executeSafeDIToolTest`: `scan`, then `generate --swift-manifest`). Why: the comparing shards already hold main's test bundle; the corpus's pins and known issues are of this path; and a second integration on main's side would add a difference that is not 2.3.0's.
- **Same files, same conditions:** both tools read the fixture `GraphFuzzerGenerator.fixture(forSeed:storingEveryParameter: true)` draws, written under the same file names (`fixture.fileNames`). Neither is given an active compilation condition, so each reads the mock condition `DEBUG` by default, and each output is compiled with `-DDEBUG` and no other condition (`compileSwift`'s default, and the comparator's), against its own release's runtime and macros.

## 3. Acceptance and classes

**2.2.0 accepts a graph** when its tool exits 0 and the fixture plus its output compiles (`swiftc -emit-object -whole-module-optimization -DDEBUG -parse-as-library`) against 2.2.0's runtime and macros. The classes, assigned in the brief's order (A, C, D, E, F, B), worked in the spike as follows.

- **A** has three sub-reasons: the tool exits non-zero (`tool error`); the compile fails with an error located in a fixture file (`macro error`); the compile fails with an error located in a generated file (`compile failure`). A located diagnostic is read only from a line that starts with a path (`/…/<file>:<line>:<column>: warning:`): the compiler's continuation lines repeat the message without a path. The first spike misread those lines and called 11 seeds E; that is fixed and Phase 2 tests it.
- **C** is main's tool rejecting; **D** is main's output not compiling against main's runtime; **E** is a warning located in a file main generated, where 2.2.0's compile had none in a file it generated. **F** is a value difference after both compile; **B** is the rest.
- **Annotations.** "New source diagnostic": a warning main's tool reports, or one main's compile locates in a fixture file, that 2.2.0's compile does not report (the counts are compared per diagnostic text). "Shared generated warning": both compiles locate a warning in a generated file.

**Spike results.** Seeds 0 to 19: 13 A (12 tool error, 1 compile failure), 6 B, 1 F, 0 C, 0 D, 0 E; one new source diagnostic annotation (seed 8), no shared generated warning. Seeds 0 to 199: 137 A (134 tool error, 3 compile failure), 61 B, 2 F, 0 C, 0 D, 0 E; 19 new source diagnostic annotations, no shared generated warning.

**Share accepted:** seeds 0 to 19, 7 of main's 13; seeds 0 to 199, 63 of main's 100. Projected over 5000 seeds, about 1500 of main's 2380 (the corpus's pinned accepted count): an estimate from 200 seeds, not a measurement.

**2.2.0's rejects, by cause,** over seeds 0 to 199. 97 of the 137 are graphs main rejects too: both releases reject them, as the base corpus draws on purpose. The 37 main accepts:
| Cause | Seeds | Count | What it is |
|---|---|---|---|
| An erased instantiator's forwarded-tuple first generic argument | 0, 8, 16, 18, 25, 27, 39, 44, 59, 83, 85, 90, 92, 97, 113, 133, 135, 152, 153, 156, 161, 164, 181, 196 | 24 | A 2.2.0 defect: `firstGenericMatchesForwardedProperties` compares the spelling with `==`, and the fix-it it offers is the same text it rejects. Main compares through `withoutSpellingDifferences` (landed in the squashed 2.3.0 work, `6ca98e0e`, #666). A class A, not a break. |
| A loop of received instantiators | 15, 30, 41, 56, 78, 89, 93, 116, 136, 172 | 10 | A main-only acceptance: "Accept loops through received instantiators" (`6804a3d4`, #649). |
| 2.2.0's own generated code does not compile | 6, 117, 147 | 3 | 2.2.0 generator defects: an optional passed where a non-optional is needed (6, 117), and an `@isolated(any)` closure type spelled without its `(any)`, which Swift rejects (147). |

**2.2.0 spellings main's generator cannot draw:** none among the fuzzer's own features. 2.2.0's fuzzer has 43 `GraphFuzzerFeature` cases and main's has every one of them (compared by name); main adds the rest. Spellings 2.2.0 accepts that neither fuzzer draws are not checked. Main still draws `@Forwarded` on a SafeDI wrapper, which 2.3.0 deprecates: those seeds carry the new source diagnostic annotation and are compared.

**Proposed floor** on the accepted count: 1,300 graphs of the base set, about 85% of the projection. The pin catches drift; the floor catches a harness that stops accepting. Decision for the orchestrator after the first CI run gives the real count.

## 4. Values

- **Per-path runtime: the smallest additive change** (in the spike patch, 46 lines added and 13 changed in `DifferentialValueComparator.swift`): `DifferentialValuePath` takes an optional `runtimeSource: DifferentialValueRuntimeSource?` (`runtimeSourcesDirectory`, `macrosToolPath`), `nil` meaning this checkout's, which every existing caller keeps. `compileAndRun` asks `runtime(for: path.runtimeSource)`: `nil` reads the existing `static let runtime` unchanged, and another source is compiled once per process by an actor that holds one `SharedTestWork` per source. `GraphLayout` adds each path's runtime source, so graphs of different runtimes never batch together, and `merging` keeps the runtime source. The at-exit removal keeps a list of directories instead of one. No existing oracle passes a runtime source, so none of their results can change. Phase 2 must replace the spike's `nonisolated(unsafe) var` list (CLAUDE.md forbids a new one) by keeping the removal inside the actor or by one parent directory under `TestTemporaryDirectory.root`.
- **Describer:** compiles against 2.2.0's runtime unchanged (spike, 70 graphs). The six wrapper types and their stored properties are identical at the tag (`diff` of `Sources/SafeDI/DelayedInstantiation` shows only main's added `Builder` typealiases, which the describer does not name).
- **Probes:** `fixture.differentialValueProbes(generatedFiles:)` taken over each release's output, keeping only probes both lists hold: every root's `Root()`, and each generated `mock()` both releases let be called with no argument. A probe on one list only is a skip, counted by reason (`mockTakesRequiredParameterIn2_2_0`, `mockTakesRequiredParameterInMain`, `mockOnlyGeneratedByOneRelease`). Over seeds 0 to 199 there were 134 root probes, 80 mock probes and no skip. Root probes and mock probes are counted and reported apart (two counts, two set sums, differences listed under two headings), so a deliberate mock change can be ruled on without hiding a root difference. Phase 2 also registers the base value oracle's samples of `ForwardedProperties` (`GraphFuzzerSampleValues`), which the spike did not, so an instantiator with forwarded properties is traversed.
- **Attribution of the two spike differences.** Both seeds, 1 and 107, are one change, release-noted in #649 (`6804a3d4`, "Accept loops through received instantiators"): "an instantiator received with `onlyIfAvailable: true` inside the tree it builds, or from an instantiator beside it that receives it back, is now that instantiator instead of `nil`", and "two types that receive one instantiator this way no longer hold the same wrapper object". Seed 1: `S1_T9` receives `t7Builder: Instantiator<S1_T7>?` only if available, and `S1_Root0` builds `t7Builder`, `t8Builder` and `t9Builder`, which receive one another; 2.2.0 passes `nil`, main passes the instantiator, and each builder function makes its wrappers again. Seed 107 is the same shape with one type receiving its own builder. This is a deliberate behavior change, not a fixed 2.2.0 defect, so it is proposed as a known break of class F, not an exemption (decision 1.5c).
- **Exemptions:** none proposed. The 2.2.0 defects the spike found (forwarded tuple, three uncompilable outputs) are rejects, class A, and need no exemption.

## 5. Cost

- **Seeds 0 to 19:** 18.8 s wall for 20 seeds, 0.94 s per graph; classification 11.7 s, the value batch 7.2 s for 7 graphs.
- **Seeds 0 to 199:** 143.4 s wall, 0.72 s per graph. Sums over the 200 seeds: main's tool 18.4 s, 2.2.0's tool 16.0 s, main's compile check 38.6 s, 2.2.0's compile check 17.7 s; the value batch 44.5 s for 63 graphs (0.71 s per compared graph). The spike ran its seeds one after another (user time 2 min 3 s for 2 min 7 s wall), on one of four cores.
- **Projection for 5000 seeds:** 5000 × 0.72 s = 60 min serial, 15 min per shard of 1250. Phase 2 runs each shard's seeds in a task group with compiles through `runProcess` (one process per core), so a shard of 1250 is projected at about 5 min on four cores. Not measured.
- **Layout:** four shards of 1250 in jobs of their own, not added to today's base shards, which already carry the value oracle. That fits the 0.72 s budget even serial.
- **Step timeout:** `timeout-minutes: 30` on the comparing step: about twice the serial projection of 15 min per shard (0.72 s per graph × 1250, measured over seeds 0 to 199 on the cloud machine). Cloud-machine figure; confirm on CI. The build job: `timeout-minutes: 35`, about twice the 15 min cold build.

## 6. CI placement and every mode

- **When:** on dispatch and at the release candidate, per the orchestrator's answer, never on a pull request.
- **Where:** new jobs in `.github/workflows/graph-fuzzer.yml`, behind a new boolean input `release_acceptance` (default `false`): `Build SafeDI 2.2.0 on Linux`, `Compare with SafeDI 2.2.0 on Linux (seeds S+1250)` four times, and `Check Release Acceptance on Linux`, which combines. The file is already on main, and a dispatch reads the workflow file of the ref it names, so `gh workflow run graph-fuzzer.yml --ref dfed--claude/check-6-release-acceptance -f release_acceptance=true` runs the new jobs before they are on main. The existing `fuzz` and coverage jobs gain `!inputs.release_acceptance` in their `if:`.
- **Check Graph Fuzzer Corpus on Linux:** check 6 does not join it. That check runs on every pull request and fails when a corpus the long run names has no report; check 6 runs only on dispatch, so it would fail every pull request. Check 6's combine job is its own check.
- **Required matrix checks:** none is added (dispatch only), so no Markdown-only stand-in.
- **Linux only:** every new job runs in `swift:6.2` on `ubuntu-latest`.
- **Fuzzer coverage mode:** unchanged. The coverage jobs mirror `ci.yml`'s shards, which check 6 is not, and `EXPECTED_SHARDS` stays as it is. Check 6 exercises no line under `Sources/` that the base corpus does not, since main's side is the corpus's own path.
- **Unit suite:** a new test in `Tests/SafeDIToolFuzzerTests` runs the harness with main on both sides over a small seed range and must report zero differences; it runs in "Build and Test on Linux", "Build and Test on Xcode 26" and "Build and Test on Latest Swift", and skips its compiles under `SAFEDI_SKIP_COMPILE_CHECK` ("Repeat Tests on Linux", `verify.yml mode=fast`) as every compile-based test does. The release long run (`SafeDIToolReleaseAcceptanceTests/longRun`) does nothing without its environment, like the corpus's long run, and in the comparing job fails, never skips, when the tool, the macros or the sources it is given are missing.

The mode table, as a plan:

| Mode | Runs what | Evidence |
|---|---|---|
| Build and Test on Linux | The main-against-main test (compiles through `compileSwift` and the comparator, never the passed-compile-check cache); classifier tests on hand-written inputs | Phase 2 |
| Repeat Tests on Linux | Same tests; compiles skipped under `SAFEDI_SKIP_COMPILE_CHECK=1` | Phase 2 |
| Build and Test on Xcode 26 | Same tests, on macOS, as part of the existing job | Phase 2 |
| Build and Test on Latest Swift | Same tests | Phase 2 |
| Fuzz Dependency Graphs shards and Check Graph Fuzzer Corpus | Unchanged: they filter `SafeDIToolGraphFuzzerTests/longRun`, which check 6 does not touch | Phase 2 |
| `graph-fuzzer.yml` dispatch, coverage mode | Unchanged; `release_acceptance` runs only the new jobs | Phase 2 |
| `verify.yml`, normal and `mode=fast` | The unit tests above, as in Build and Test on Linux and Repeat Tests respectively | Phase 2 |
| 2.2.0 build job and comparing shards | `release_acceptance=true` dispatch only, Linux | Orchestrator's run |
| Markdown-only stand-in | None needed: no required check added | — |

## 7. Pins and lists

- **Pinned, per graph set** (one Swift constant per old release and set, as `corpusValueOracleCounts` is): the graphs 2.2.0 accepts, as a count and a set sum over seeds; the compared root probe pairs and mock probe pairs, each a count and a set sum over `<seed>:<probe>`; the skips by reason; the count per class (A by sub-reason, B, C, D, E, F) and the count of each annotation. All "pins: derive on CI".
- **Combine:** a sibling script, `.github/scripts/combine-release-acceptance-reports.py`, not an extension of `combine-graph-fuzzer-reports.py`: the existing script's rule that every corpus the long run names has a report would fail check 6's dispatch-only reports, and its record format is the corpus's. The sibling checks shard coverage (each seed exactly once), adds the shards' counts and set sums, and compares them with the pins in the shards' reports.
- **Lists:** two constants beside the pins. Known breaks: `(seed, class, reason)`. Exemptions: `(seed, reason, fix)`, the fix a pull request or commit that made 2.2.0's value wrong and main's right. No global off switch. A listed seed that no longer shows its class is stale and fails the run, as a stale known issue does.
- **The leak fix:** check 6's pins should not move. Base graphs draw no seam (`features` empty) and no public mock, and the leak fix changes what a seam's builder is handed. Read in the code: the scope enums and builders come only from `generateSeamRootCode` and the public mock path, which no base graph reaches. Not proven: each leak-fix slice touches `ScopeGenerator.swift`, which every base graph passes through, so the orchestrator's re-derivation after each slice stays the check.

## 8. Proof that it fails

- **Hand mutation** (run, then reverted): in `Initializer.createInitializerArgumentList` (`Sources/SafeDICore/Models/Initializer.swift`), pass `nil` for every `.received(onlyIfAvailable: true)` dependency. Over seeds 0 to 199 the check then reports 17 F (seeds 24, 36, 47, 50, 77, 84, 88, 101, 110, 121, 123, 139, 140, 141, 154, 157, 162) and 3 E (1, 107, 114), against 2 F before. Seed 24 is the one to pin: `S24_Root0() > anyT1 > value > t1` is `nil` on main and an instance on 2.2.0. Seed 1 shows E working: the mutation leaves `t7Builder` unused, `warning: initialization of immutable value 't7Builder' was never used` in `S1_Root0+SafeDI.swift`, which 2.2.0's output does not have.
- **A real break on main:** none beyond the #649 behavior change above (seeds 1 and 107), which is release-noted and proposed as a known break.

## 9. Spike table, seeds 0 to 19

Time is the seed's tool runs and compile checks; seeds that reached the value batch add its share, 1.03 s each (7.2 s for 7 graphs).

| Seed | Class | Annotations | Time (s) | Note |
|---|---|---|---|---|
| 0 | A, tool error | | 0.76 | forwarded-tuple defect of 2.2.0 |
| 1 | F | | 0.88 + 1.03 | #649 behavior change, known-break candidate |
| 2 | B | | 0.70 + 1.03 | |
| 3 | B | | 0.97 + 1.03 | |
| 4 | A, tool error | | 0.18 | both reject |
| 5 | A, tool error | | 0.16 | both reject |
| 6 | A, compile failure | | 0.69 | 2.2.0 generated an optional where a non-optional is needed |
| 7 | A, tool error | | 0.16 | both reject |
| 8 | A, tool error | new source diagnostic | 0.51 | forwarded-tuple defect; deprecation of `@Forwarded` on a `SendableLazilyInstantiated` |
| 9 | B | | 1.09 + 1.03 | |
| 10 | A, tool error | | 0.17 | both reject |
| 11 | A, tool error | | 0.18 | both reject |
| 12 | B | | 0.78 + 1.03 | |
| 13 | B | | 0.65 + 1.03 | |
| 14 | A, tool error | | 0.16 | both reject |
| 15 | A, tool error | | 0.48 | loop of received instantiators, main-only (#649) |
| 16 | A, tool error | | 0.79 | forwarded-tuple defect |
| 17 | A, tool error | | 0.22 | both reject |
| 18 | A, tool error | | 0.57 | forwarded-tuple defect |
| 19 | B | | 0.63 + 1.03 | |

## Decisions for the orchestrator

1. **Shard layout:** four shards of 1250 in jobs of their own fits (0.72 s per graph serial). Confirm, or ask for the comparison to ride in today's base shards instead.
2. **Accepted-count floor:** propose 1,300 (projection about 1,500 of main's 2,380). Settle after the first CI run.
3. **Known breaks:** seeds 1 and 107, class F, reason "#649: an instantiator received only if available inside the loop of instantiators it belongs to is that instantiator, not `nil`, and each receiver holds its own wrapper (release-noted behavior change)". The full list over 5000 seeds comes from the first CI run. Or rule them exemptions, if the orchestrator reads 2.2.0's `nil` as a defect.
4. **When CI runs it:** on dispatch and at the release candidate (already answered); recorded here for completeness.
5. **The forwarded-tuple defect hides about a quarter (24 of 100) of main's accepted graphs from check 6.** Accept, or add a second graph set drawn without the forwarded-tuple draw, so those graphs' other shapes are compared. The brief allows only main's generator; this would be main's generator with one draw off.
