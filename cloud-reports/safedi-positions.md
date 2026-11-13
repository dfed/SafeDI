# Keeping source positions out of what dependents read: measurement and prototype

Measured 2026-11-13 with SafeDITool built in release from `1d60f27` on Linux (4 cores, Swift 6.2.4). This is a measurement and a prototype, not for merging.

Line-shifting edits in a low module rerun `generate` in every module above it, and most of those reruns change nothing. Keeping positions out of what dependents read is safe and recovers most of that work, but only for local incremental Bazel builds. The absolute saving is small: about 4–5 CPU-seconds per edit on this fixture. I'd do it as a small Bazel-only change, after one fix below; positions are not lost.

## Setup and fixture

- **Swift:** swiftly couldn't install a toolchain (failures listed at the end). I installed Swift 6.2.4 by hand from download.swift.org instead, after checking its gpg signature. The release build of `SafeDITool` (`swift build -c release --product SafeDITool --traits sourceBuild`) took 641 s.
- **Fixture:** `safedi-positions-bench/make_fixture.py ROOT` (seed 7) creates 40 modules in 6 layers (8, 8, 8, 8, 6, 2) with 845 `@Instantiable` types.
  - 20 seams, 2 roots, 82 renames (`@Received(fulfilledByDependencyNamed:ofType:)`).
  - 32 public mocks, which L2 mocks call: each L1 public mock's tree holds a `package` helper of another package than its callers', so their mocks cannot build it inline. Plus 283 internal mocks.
  - 22 of the 40 modules declare a root or a seam.
- **Driver:** `safedi-positions-bench/bazel_sim.py` runs `generate` per module with the same arguments as `bazel/safedi.bzl`, direct and transitive `.safedi` lists included. It reruns an action when the hash of any declared input changes, as Bazel's action cache does.
- **Timing:** `/usr/bin/time -v` on every rerun, averaged over 3 runs.
- **Not checked:** I didn't compile the fixture with swiftc; I only confirmed `generate` accepts it with no errors or warnings.

## Edits in `L1M0` (21 dependents, 3-run averages)

"Wasted" counts dependents that reran with byte-identical `.swift` and `.safedi`.

| Edit | `L1M0.safedi` changes | Reruns today | `.swift` changed | `.safedi` only changed | Wasted today (user / wall) | Prototype reruns (wasted) |
|---|---|---|---|---|---|---|
| blank line above a type | yes | 21 | 5 | 0 | 16 (4.15 s / 3.61 s) | 5 (0) |
| comment above a type | yes | 21 | 5 | 0 | 16 (4.03 / 3.50) | 5 (0) |
| add a method | yes | 21 | 5 | 0 | 16 (4.07 / 3.50) | 5 (0) |
| line in an init body | yes | 21 | 5 | 0 | 16 (4.04 / 3.52) | 5 (0) |
| stored property, not a dependency | yes | 21 | 5 | 0 | 16 (3.80 / 3.32) | 5 (0) |
| `import Foundation` | yes | 21 | 21 | 0 | 0 | 21 (0) |
| rename a local | no | 0 | 0 | 0 | 0 | 0 |
| reorder two types | yes | 21 | 0 | 21 (views) | 0 | 21 (0) |
| add a type at the end of the file | yes | 21 | 0 | 21 (views) | 0 | 21 (0) |
| add a dependency | yes | 21 | 11 | 10 | 0 | 21 (0) |

- **The 5 real changes:** these dependents' generated code names a rename's line in `L1M0`, e.g. `// Declared at L1M0/Sources/File00.swift:53` becomes `:54`.
- **Reorder and add-type:** `L1M0` declares public mocks, so every dependent's view carries its declarations, and those bytes change by design.

The same comparison, blank line or added method, in other low modules (current tool vs prototype):

| Module | Reruns today | Wasted today | Prototype reruns | Prototype wasted |
|---|---|---|---|---|
| `L0M0` (rename used everywhere) | 39 | 1 | 38 | 0 |
| `L0M1` (edited file has no rename) | 26 | 26 (5.44 s user / 4.67 s wall) | 4 | 4 (0.96 s) |
| `L1M3` | 17 | 17 (4.96 s / 4.33 s) | 0 | 0 |

For `L0M1`, `unused_inputs_list` without the split still reran 24 of 26. Modules with a root or seam read everything beneath them, so pruning unread `.safedi` files saves almost nothing on its own.

**Soundness:** across all 14 measured edit/module cases, the prototype never skipped a rerun whose output would have changed. Its generated `.swift` is byte-identical to today's for all 40 modules, and each sidecar is byte-identical to today's `.safedi`.

## Where upstream positions are used downstream

An agent audited the code; the prototype's results agree with it.

- **Generated code, on success:** one channel only. A rename (`.aliased` dependency) in an upstream type that a root, seam, fill or mock builds gets `#sourceLocation(file:line:)` under Bazel, or `// Declared at path:line` otherwise. It comes from `Dependency.declarationLocation`; see `DependencyTreeGenerator.swift:8250, 4926, 7931` and `AliasDeclarationReferences.swift:101`.
- **Warnings, on success:** located at upstream dependencies, and the reader a warning names is picked by upstream position (`DependencyTreeGenerator.swift:284–300, 8289–8362`).
- **Diagnostics, on error only:**
  - located in another module's file, with fix-its at upstream ranges: unfulfillable `@Received`, seam access notes, duplicates, cycles and hidden labels in upstream types, fill findings, `MockOnlySeamError`, `ConfigurationBuiltTwoWays`;
  - which declaration an error names, and the order errors are listed in, both decided by position.
- **Seams:** positions appear only in error notes; signatures, guards and call shapes hold none.
- **Public mocks:** error locations only.
- **`query needs`:** paths only, except the locations of errors it throws.
- **Never:** the order of generated code, guard hashes, or the downstream `.safedi`. Its view is already stripped of positions.

## The prototype

- **Where:** the first three commits of this branch.
- **Size:** +119 / −9 lines in `GenerateCommand.swift` and `ModuleInfoFile.swift`, including the SwiftFormat commit, plus +19 / −2 in `bazel/safedi.bzl`.
- **What it does:** behind `--split-module-info-positions`, it writes `X.safedi` without positions and `X.safedipositions` as today's full file. When a sidecar exists it reads the sidecar, so every use above still gets exact positions. `--unused-inputs-list-output` then marks as unused:
  - every file beneath that the run never opened;
  - every sidecar whose module's files the generated code doesn't name with a line, provided the run printed no warnings.

  A failed run writes no list.
- **Cost:** a full 40-module pass takes 6.9 s user / 6.3 s wall against 6.2 / 5.6 today, about 11% more. The main `.safedi` shrinks only 4.5% (1,094,527 to 1,045,063 bytes), because views dominate.
- **Bazel rule:** the `bazel/safedi.bzl` change is untested; bcr.bazel.build was blocked, so rules_swift couldn't load.

## What `unused_inputs_list` buys under Bazel

I checked this with a small rule on Bazel 7.6.1 (`safedi-positions-bench/unused-inputs-probe`, run with `--noenable_bzlmod --enable_workspace`, an empty `WORKSPACE`, and its `BUILD.bazel.example` renamed to `BUILD.bazel`, which keeps it out of this repository's own Bazel build); Bazel 9 is untested.

- **Local builds:** the local action cache honours the list. Changing an input listed as unused reran nothing.
- **Disk cache:** it keys on every declared input. After `bazel clean`, changing the unused input missed the disk cache and the action reran. A remote cache presumably behaves the same; I couldn't test one.

So the saving applies to local incremental builds only.

## Verdict

**Worth doing, Bazel-only, with no loss of diagnostics.**

- **Size of the win:** each wasted rerun costs about 0.25 s here, and identical outputs already stop recompiles from spreading further. Bigger modules would gain more.
- **Risk:** stale incremental output, not worse diagnostics. If a later change lets an upstream position reach success-path output through a new channel, Bazel would skip a rerun it needs.
- **Before shipping:**
  - have the generator record which upstream positions it emitted, instead of searching the generated text for paths (the search would miss a path the string literal escapes);
  - add a test that fails when output depends on positions the run marked unused, so a new channel is caught;
  - consider one sidecar per source file, which would remove `L0M1`'s 4 wasted reruns.

**Rejected alternative:** leaving the sidecars out of the action's inputs entirely would help remote caches too. But it would drop the line numbers in upstream renames' `#sourceLocation`, and every upstream error location and fix-it listed above.

## Commands that failed

- `apt-get install -y time`: failed until I ran `apt-get update`.
- `swiftly install 6.2 --use` and `swiftly install 6.2.3`: `gpg --import` exited 2. The proxy serves swift.org's signing keys gzip-compressed.
- `swiftly link`: "couldn't determine the toolchain version".
- Downloading from releases.bazel.build: the proxy returned 403.
- Bazel 9.1.0: couldn't fetch modules from bcr.bazel.build (403).
- Bazel 7 probe, first try: `run_shell` doesn't accept `unused_inputs_list`; switched to `ctx.actions.run`.
- `sleep 60; …` was blocked by the harness.
- First experiment run: my timing-file path was relative to the wrong directory.
- The `L1M3` batch was killed (exit 137) when the session's worker restarted; it reran cleanly afterwards. `L0M1`'s prototype run with an added method was lost in the same restart.
- Not run: the test suite on the prototype. SwiftFormat flagged the prototype at push time, and its formatting is the third commit.

## Rerunning

From `cloud-reports/safedi-positions-bench`, with a release `SafeDITool` built from `1d60f27` and one built from this branch:

```bash
python3 -I make_fixture.py fixture
```

```bash
python3 -I experiment.py fixture work-main /path/to/SafeDITool-main L1M0 --repeats 3 > results-main.jsonl
```

```bash
python3 -I experiment.py fixture work-split /path/to/SafeDITool-split L1M0 --split --repeats 3 > results-split.jsonl
```

```bash
python3 -I summarize.py results-main.jsonl results-split.jsonl
```

`--edits blank-line,add-method` limits the edits, and `--keep` keeps each edit's outputs for diffing. `full_build.py FIXTURE WORK TOOL [--split]` times a full pass. The `results-*.jsonl` files here are the runs this report cites.
