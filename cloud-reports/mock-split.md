# Splitting `--combined-output` mocks into several files: measurement and prototype

Measured 2026-11-13 on a cloud Linux machine, with Swift 6.2.4. This is post-2.3.0 work. The question: does writing
generated mocks into N files beside the combined output speed up the edit loop and clean Debug builds of the builds
that use `generate --combined-output` (Bazel, Tuist, custom builds)? And is it worth shipping as an opt-in?

## Verdict

**Ship it as an opt-in, with a recommended N of 32. Don't turn it on by default in the Bazel rule yet.**

- **Where it pays.** The gain comes from incremental compiles that leave unchanged generated files alone. On the
  300-type fixture, an edit that adds a private method gets 2.0–2.5× faster, and an edit that adds a dependency
  2.6–3.6× faster. Clean builds get up to 2× faster, but only when the driver runs jobs in parallel (`-j`). This
  covers custom builds and Xcode-like builds (`-incremental -j`, where SafeDITool writes a file only when its bytes
  change), and rules_swift's persistent worker once it hashes files, which rules_swift enables by default from Swift
  6.4 or Xcode 27.
- **Where it doesn't.**
  - rules_swift without the worker (sandboxed or remote): no gain, and 32–64 files cost up to 17% more.
  - rules_swift's worker on Swift 6.2 or 6.3: Bazel rewrites every output, so every mock file recompiles on every
    edit. 8 files gain 20–25% on an added dependency; 32–64 files lose up to 40% on a private-method edit.
  - Clean builds without `-j`, which is rules_swift's default: up to 21% more CPU at 64 files.
- **Why 32.** Edits stop improving at 32 files: 64 is no faster and sometimes slower. A serial clean build pays less
  at 32 than at 64. A parallel clean build gets most of 64's gain at 32 (15.4 s against 12.4 s on 300 types).
- **The adopter's numbers match the `-incremental -j` mode** on shape: 8 files gain nothing on a clean build, and
  32–64 do. They do not describe a default rules_swift build.

## Setup

| | |
|---|---|
| Machine | 4 × Intel Xeon @ 2.10 GHz, 15.7 GiB RAM, Ubuntu 24.04, Linux 6.18 |
| Toolchain | Swift 6.2.4 (swift-6.2.4-RELEASE), the swift.org tarball, signature checked with gpg |
| Setup time | 134 s for the toolchain (download, check, extract) · 9 min 31 s for the release build of SafeDITool · 5 min 55 s for the release build of the SafeDI library and macros · 48 s to rebuild the prototype |
| Timing | `/usr/bin/time -v` on every `generate` and every `swiftc`; user CPU time includes every frontend job the driver waits for |
| Runs | 3 per configuration, configurations alternating within each run (combined, 8, 32, 64, combined, …) |
| Benchmark time | about 51 min for modes 1–3, about 14 min for mode 4 |

Swiftly installed nothing; see [Commands that failed](#commands-that-failed). The toolchain is the same release
swiftly installs, checked against the same signing key.

### Fixtures (`scripts/make_fixture.py N OUT`)

Each fixture is one module, one type per file, every type `@Instantiable(generateMock: true)`, and one root. The
generator is deterministic for a given N.

| | 100 types | 300 types |
|---|---|---|
| Root (`isRoot: true`) | 1, instantiating every service and 5 top-level features | same |
| Services (instantiated by the root; each receives 0–2 earlier services; every third is reached through a protocol and `fulfillingAdditionalTypes`) | 10 (4 protocol) | 21 (7 protocol) |
| Utilities (no dependencies; instantiated by many features) | 4 | 12 |
| Features (a tree up to depth 6; 0–4 `@Instantiated` children each; 1–3 `@Received` services; ~25% `@Forwarded` with an `Instantiator` in the parent; some receive an ancestor's forwarded value) | 85 (19 forwarding) | 266 (69 forwarding) |
| Generated `--combined-output` | 448 KB: 5% dependency trees, 95% mocks | 1.83 MB: 4% dependency trees, 96% mocks |
| Largest mock | `Root`, 45 KB (11% of the mock code) | `Root`, 154 KB (9%) |
| Median mock | 1 KB | 1 KB |

Both edits touch one type at depth 3 that has children: `Feature015` (100 types) and `Feature007` (300 types).

- **Private method:** adds `private func debugSummary() -> String` to the type's file. SafeDI's output does not
  change.
- **Add a dependency:** adds `@Received private let service001: Service001`, which the root provides, to the same
  type. Its mock changes, and so do the mocks of its ancestors, the root's included.

Each edit reruns `generate`, then the compile; the two are timed separately.

### Compiling like Bazel

rules_swift's defaults for a `fastbuild` `swift_library` come from `swift/toolchains/config/compile_config.bzl` and
`swift/internal/features.bzl` (master on 2026-11-12, commit `d1eb081`):

```
swiftc -module-name Fixture -parse-as-library -emit-object -emit-module -emit-module-path … -output-file-map …
       -Onone -DDEBUG -enable-testing -gline-tables-only -enable-batch-mode
       -I <SafeDI module> -load-plugin-executable <SafeDIMacros>#SafeDIMacros  <sources> <generated files>
```

- **One driver invocation per module, in batch mode.** rules_swift passes `-enable-batch-mode` (feature
  `swift.enable_batch_mode`, on by default). The driver forms `max(-j, ⌈files/25⌉)` batches of contiguous input files
  (swift-driver `Planning.swift`, `defaultSizeLimit = 25`). Generated files come last, as `safedi_swift_library`
  appends its output to `srcs`. So all 9 files of the 8-file split share one batch, 32 files span 2 batches and 64
  span 3.
- **No `-j`.** rules_swift never passes `-j` to a non-WMO compile. Its only thread flag is `-num-threads` for WMO.
  The driver defaults to one job at a time (swift-driver `MultiJobExecutor.swift:294`, `numParallelJobs ?? 1`).
  Measured on the 8-file split of the 100-type fixture: default 5.06 s wall, `-j 1` 4.74 s, `-j 4` 2.84 s. **A default
  rules_swift Debug compile of one module runs its batches one after another.** Bazel gets its parallelism from
  compiling separate modules at once.
- **Incremental through the worker.** The compile action uses `worker_mode = "persistent"` (`swift_toolchain.bzl`,
  `xcode_swift_toolchain.bzl`). Bazel picks the worker strategy by default for local execution, and the worker adds
  `-incremental` whenever the action has an output file map and is not WMO (`tools/worker/work_processor.cc`,
  `is_incremental`). Bazel deletes an action's outputs before running it, so every generated file reaches the worker
  with a new modification time. Swift 6.2's driver has no file hashing (`-enable-incremental-file-hashing` is not in
  `swiftc -help-hidden`), so it recompiles every generated file. rules_swift turns hashing on by default from Swift
  6.4 (`swift_toolchain.bzl:797`) or Xcode 27 (`xcode_swift_toolchain.bzl:870`).
- Not modelled: `-file-prefix-map`, `-Xwrapped-swift` and similar flags that don't change compile work. A warm
  `-module-cache-path` is shared by every run, as Bazel shares its global module cache.

The four modes below cover these cases. `scripts/bench.py` implements them.

| Mode | Stands for | Flags | Generated files |
|---|---|---|---|
| 1 | rules_swift without the worker (sandboxed or remote execution) | not incremental, no `-j`, outputs deleted before each compile | rewritten every run |
| 2 | rules_swift worker on Swift 6.2/6.3 or Xcode < 27 (rules_swift's local default today) | `-incremental`, no `-j` | rewritten every run (new mtime) |
| 3 | rules_swift worker with file hashing (its default from Swift 6.4 or Xcode 27) | `-incremental`, no `-j` | untouched when the bytes are the same (SafeDITool's write-if-changed, standing in for hashing) |
| 4 | Custom build, Tuist or Xcode script phase, Xcode-like driver | `-incremental -j 4` | untouched when the bytes are the same |

## Results

Medians of three runs, compile wall time in seconds, with ± half the spread (max − min). Every run, user CPU time,
and files compiled are in the [appendix](#appendix-every-run). "combined" is today's output.

### 100 types

| Mode | Config | Clean | Private method | Add a dependency |
|---|---|---|---|---|
| 1 no worker | combined | 7.15 ±0.23 | 6.85 ±0.18 | 6.88 ±0.21 |
| | 8 files | 7.14 ±0.23 | 7.01 ±0.19 | 6.86 ±0.25 |
| | 32 files | 7.70 ±0.14 | 7.53 ±0.28 | 7.62 ±0.16 |
| | 64 files | 8.40 ±0.28 | 8.52 ±0.23 | 8.42 ±0.29 |
| 2 worker, 6.2 | combined | 7.36 ±0.15 | 3.41 ±0.12 | 5.37 ±0.44 |
| | 8 files | 7.69 ±0.18 | 3.43 ±0.17 | 4.28 ±0.27 |
| | 32 files | 8.07 ±0.15 | 4.11 ±0.10 | 5.02 ±0.35 |
| | 64 files | 8.81 ±0.08 | 4.76 ±0.12 | 5.41 ±0.34 |
| 3 worker, hashing | combined | 7.41 ±0.59 | 3.32 ±0.21 | 4.98 ±0.28 |
| | 8 files | 7.55 ±0.10 | 2.55 ±0.02 | 3.61 ±0.04 |
| | 32 files | 8.16 ±0.17 | 2.25 ±0.17 | 2.88 ±0.07 |
| | 64 files | 9.18 ±0.39 | 2.49 ±0.05 | 2.99 ±0.09 |
| 4 `-incremental -j 4` | combined | 4.94 ±0.08 | 3.06 ±0.05 | 4.22 ±0.21 |
| | 8 files | 5.12 ±0.12 | 1.70 ±0.35 | 1.78 ±0.26 |
| | 32 files | 3.23 ±0.21 | 1.61 ±0.23 | 1.42 ±0.05 |
| | 64 files | 2.89 ±0.10 | 1.82 ±0.04 | 1.57 ±0.36 |

### 300 types

| Mode | Config | Clean | Private method | Add a dependency |
|---|---|---|---|---|
| 1 no worker | combined | 32.84 ±2.53 | 32.80 ±0.93 | 31.50 ±1.04 |
| | 8 files | 29.70 ±1.39 | 30.73 ±0.88 | 30.94 ±2.02 |
| | 32 files | 32.48 ±2.00 | 32.19 ±0.99 | 32.79 ±1.00 |
| | 64 files | 34.32 ±1.47 | 34.31 ±1.67 | 33.46 ±1.51 |
| 2 worker, 6.2 | combined | 32.04 ±1.38 | 14.82 ±0.69 | 24.08 ±0.89 |
| | 8 files | 31.03 ±1.55 | 13.93 ±1.00 | 18.04 ±0.21 |
| | 32 files | 32.62 ±0.59 | 15.85 ±0.44 | 18.51 ±0.12 |
| | 64 files | 33.91 ±0.65 | 17.57 ±1.21 | 20.39 ±0.69 |
| 3 worker, hashing | combined | 31.32 ±0.70 | 14.65 ±0.88 | 24.33 ±1.62 |
| | 8 files | 31.23 ±1.06 | 9.13 ±0.69 | 13.98 ±0.44 |
| | 32 files | 34.13 ±1.09 | 7.66 ±0.47 | 10.16 ±0.40 |
| | 64 files | 35.62 ±0.69 | 7.36 ±0.23 | 9.34 ±0.10 |
| 4 `-incremental -j 4` | combined | 24.70 ±0.58 | 15.36 ±0.69 | 20.99 ±1.00 |
| | 8 files | 23.73 ±0.62 | 6.92 ±0.31 | 8.25 ±1.04 |
| | 32 files | 15.40 ±0.40 | 6.17 ±0.37 | 5.77 ±0.23 |
| | 64 files | 12.39 ±0.54 | 6.36 ±0.41 | 5.80 ±1.33 |

User CPU time, 300 types, medians in seconds:

| Config | Mode 1 clean | Mode 3 clean | Mode 3 private | Mode 3 add dep. | Mode 4 clean | Mode 4 private | Mode 4 add dep. |
|---|---|---|---|---|---|---|---|
| combined | 29.90 | 28.91 | 12.97 | 22.34 | 29.42 | 14.17 | 22.29 |
| 8 files | 27.73 | 28.96 | 8.23 | 12.89 | 29.31 | 10.89 | 14.85 |
| 32 files | 30.23 | 31.94 | 6.84 | 9.21 | 29.99 | 7.93 | 10.22 |
| 64 files | 31.78 | 33.04 | 6.53 | 8.47 | 30.67 | 8.02 | 9.89 |

### `generate`, reported apart from the compile

Splitting costs `generate` nothing measurable. Its wall time has no trend with N: 0.16–0.27 s on 100 types and
0.62–0.94 s on 300 types, in every mode, step and configuration.

Files rewritten, and files the driver then compiled (generated files in parentheses), on 300 types in mode 3:

| Config | Private method: rewritten · compiled | Add a dependency: rewritten · compiled |
|---|---|---|
| combined | 0/1 · 3 (1) | 1/1 · 3 (1) |
| 8 files | 0/9 · 6 (4) | 4/9 · 6 (4) |
| 32 files | 0/33 · 7 (5) | 5/33 · 7 (5) |
| 64 files | 0/65 · 7 (5) | 5/65 · 7 (5) |

A private method changes no generated byte, yet the driver still recompiles every generated file that mentions the
edited type: adding a member, even a private one, changes the type's fingerprint. Combined, that file is the whole
1.8 MB. Split, it is the 4–5 files that hold the mocks of the type and its ancestors, plus the dependency-tree file.

### Against the adopter's numbers

| | Clean | Private method | Add a dependency |
|---|---|---|---|
| Adopter, 100 types: combined → 8 / 32 / 64 files | 10.1 → 9.3 / 5.1 / 3.6 s | 5.1 → 1.9 / 1.5 / 1.5 s | 8.1 → 2.5 / 1.9 / 1.7 s |
| Here, mode 4, 100 types | 4.94 → 5.12 / 3.23 / 2.89 s | 3.06 → 1.70 / 1.61 / 1.82 s | 4.22 → 1.78 / 1.42 / 1.57 s |
| Here, mode 4, 300 types | 24.7 → 23.7 / 15.4 / 12.4 s | 15.4 → 6.9 / 6.2 / 6.4 s | 21.0 → 8.3 / 5.8 / 5.8 s |
| Here, mode 3 (Bazel worker with hashing), 300 types | 31.3 → 31.2 / 34.1 / 35.6 s | 14.7 → 9.1 / 7.7 / 7.4 s | 24.3 → 14.0 / 10.2 / 9.3 s |

The shape matches mode 4:

- 8 files leave a clean build unchanged, because all of them land in one batch.
- 32–64 files speed a clean build up, because the mock files spread over several batches that run in parallel.
- Edits improve 2–4×, and stop improving after 32 files.

The adopter's ratios are larger: clean 2.8× against 1.7–2.0× here, private method 3.4× against 1.9–2.5×. That fits a
Mac with more cores. With `-j N`, the driver forms at least N batches, so more cores spread the mock files further.
The adopter's numbers describe an incremental, parallel compile, as Xcode or a custom build runs it. They do not
describe a default rules_swift compile (modes 1 and 2), which does not parallelise within a module.

The earlier measurement (40.7B instructions combined against 44.4B at 32 files, a clean build of a real Bazel
project) agrees with mode 1. A clean build at 32 files does 1–10% more work here, depending on fixture and mode
(300 types: user CPU 29.9 → 30.2 s in mode 1, 28.9 → 31.9 s in mode 3), and nothing makes up for it there.

## What drives the gain

`scripts/breakdown.py` reads the frontend's own timers (`-Xfrontend -stats-output-dir`); Swift 6.2's driver ignores
`-driver-time-compilation`. 300 types, `-incremental -j 4`; full output in
[`mock-split/breakdown-j4.md`](mock-split/breakdown-j4.md).

| | Build wall | Generated-code jobs (frontend wall) | emit-module job |
|---|---|---|---|
| combined, clean | 25.1 s | 1 batch of 23 files holding the combined file: 21.6 s | 2.5 s |
| 64 files, clean | 12.3 s | 3 batches, in parallel: 5.7 + 9.1 + 8.0 s | 2.4 s |
| combined, private method | 13.7 s | the combined file alone: 10.5 s | 2.7 s |
| 8 files, private method | 6.3 s | 3 files: 3.5 + 1.8 + 1.2 s | 2.5 s |
| 64 files, private method | 6.2 s | 4 files in 3 jobs: 3.3 + 1.7 + 0.4 s | 2.4 s |

1. **Smaller recompiles drive the edit gain.** An edit recompiles only the mock files that mention the edited type,
   instead of the whole combined file. This holds in modes 3 and 4. In mode 2, every rewritten file recompiles, so it
   mostly does not.
2. **Parallelism drives the clean gain, and only with `-j`.** Batches are contiguous runs of at most 25 input files,
   and the generated files come last. So 8 files stay in one batch, and only 32+ spread over 2–3 batches. Without
   `-j` there is no parallelism within the module, and splitting only adds per-file overhead: modes 1–3 clean get
   0–24% slower.
3. **Less type-checking drives nothing.** Compiled alone at each stage, the 300-type combined file takes:
   `-typecheck` 3.7 s, `-emit-silgen` 6.0 s, `-emit-ir` 12.9 s, `-c` 20.9 s (18.1 s without `-gline-tables-only`). So
   type-checking is about 18% of its cost; SILGen and SIL about 11%; IRGen about 33%; LLVM code generation and object
   emission about 38%. Mock code is expensive to generate code for, not to type-check. Splitting raises total
   type-checking slightly (clean sum 8.5 s → 8.6 s at 64 files) and total clean CPU 4–21% at 64 files. Each edit also pays a fixed
   ~2.4 s for the emit-module job, which type-checks every declaration in the module, the mocks' included, whatever
   the split.

## Where it hurts

- **rules_swift without the worker (mode 1).** Every build recompiles everything one batch at a time. 8 files are
  neutral; 32 and 64 files cost 8% and 17% wall on 100 types, and −1% and +4% on 300 types, where the spread is about
  ±2 s.
- **rules_swift's worker on Swift 6.2/6.3 or Xcode < 27 (mode 2)**, likely the most common Bazel setup today. Bazel
  rewrites every output, so every mock file recompiles on every edit. Private-method edits get slower at 32 and 64
  files: 3.41 → 4.11 / 4.76 s on 100 types, 14.8 → 15.9 / 17.6 s on 300 types. Only 8 files help, and only on an
  added dependency: 20–25%, because the combined file has more to recompile when its content changes.
- **Clean builds without `-j`** pay 6–21% more CPU at 64 files (modes 1–3): per-file headers, `#if` assertions, imports, and one
  object file per mock file.
- **The largest mock sets a floor.** One mock can't be split, and `Root`'s is 9–11% of all mock code. Any change below
  the root changes the root's mock, so its file recompiles on nearly every dependency edit.
- **Placement by path hash is uneven.** At 8 files on 100 types, file sizes range from 41 to 92 KB.
- **Build-system surface.** Bazel's rule must declare N more outputs per module, and Tuist's script N more output
  files. All N must always be written, empty ones included, which the prototype does. Changing N renames outputs.

## The prototype

Branch `dfed--claude/cloud-mock-split`, commit "Prototype: split combined-output mocks into N files". It touches one
file, `Sources/SafeDIToolLibrary/GenerateCommand.swift`: **+84 −9 lines**.

- New option `--combined-output-mock-file-count N` on `generate`, which requires `--combined-output` and N ≥ 1.
- The mocks of each of the module's own source files go to `<combined output without .swift>.mocks.<i>.swift`, where
  `i` is a 64-bit FNV-1a hash of the source path as the CSV spells it (stable across machines and processes; Bazel's
  paths are relative to the execution root), modulo N.
- Each mock file gets its own header, made from its body as a `.mock` file's is, plus the module's `#if` assertions.
- All N files are written every run, header-only when no mock lands in one, and only when their bytes change, as the
  combined file is. In the syntax-error path, each mock file gets a header without code, so none keeps an earlier
  build's mocks.
- The combined file keeps the dependency trees, `additionalMocksToGenerate` mocks and the mock configuration.
- **With the option off, output is byte-for-byte unchanged.** Checked with the baseline binary against the prototype
  on:
  - both fixtures (`.swift` and `.safedi`);
  - the three-module `ExampleBazelIntegration` run per module as the Bazel rule runs it (`Models`, `Subproject`,
    `ExampleBazelIntegration`);
  - `ExampleProjectIntegration` and `Example Package Integration`, each as one module.
- Checked before pushing: SwiftFormat lint passes, and the full test suite result is in
  [Tests](#tests). No new tests were written for the option.
- **Not done:** wiring into `bazel/safedi.bzl` (N declared outputs) or the Tuist plugin; a Manual entry; tests for
  the new option; placing `additionalMocksToGenerate` mocks and the mock configuration by hash too.

## Tests

The full suite (`swift test --traits sourceBuild`) was still running when this commit was pushed; a follow-up commit records its result.

## Commands that failed

| Command | Failure | What I did |
|---|---|---|
| `swiftly install 6.2.4 --use --assume-yes` (twice) | `gpg --import` exited 2: the proxy served the signing keys gzip-compressed and swiftly did not decode them | Downloaded the swift.org tarball and its `.sig`, decompressed and imported the keys, got `Good signature from "Swift 6.x Release Signing Key"`, extracted to `/opt/swift-6.2.4` |
| `gpg --import /tmp/keys.asc` | `no valid OpenPGP data found` (the same gzip file) | `gzip -dc` first |
| `swiftly link` | `couldn't determine the toolchain version to install` (nothing installed) | — |
| `swiftly install … --no-verify` | Denied by the session's permission classifier; never ran | Used the toolchain whose signature I checked myself |
| `curl …/rules_swift/archive/refs/heads/master.tar.gz` | HTTP 403 | `git clone --depth 1` of rules_swift |
| `SafeDITool generate` over all of `ExampleBazelIntegration` and of `ExampleTuistIntegration` as one module | `This module declares #SafeDIConfiguration 2 times` (each is several modules) | Ran `ExampleBazelIntegration` per module; did not rerun the Tuist example per module, so it has no byte-for-byte check |
| `swiftc … -o /dev/null` with several outputs | `cannot specify -o when generating multiple output files` | Compiled into a build directory |
| `swiftc … -driver-time-compilation` | Exit 0 but prints nothing: Swift 6.2's driver ignores it | Used `-Xfrontend -stats-output-dir` |
| First per-job breakdown script | Printed nothing: its `grep` matched no line, so `pipefail` stopped it | Rewrote it as `scripts/breakdown.py` |
| First `breakdown.py` edit rows | Not a failed command, but invalid data: a per-build `-stats-output-dir` changed the driver's arguments, so the "edit" rebuilt everything | Used one stats directory for both builds; reran; only the corrected rows are reported |
| First harness smoke test | Not a failed command, but a wrong count: counting rebuilt objects by modification time found too few, because the frontend leaves an unchanged object file untouched | Counted the files in the driver's `-driver-show-job-lifecycle` "Starting Compiling" lines |
| `sleep 240; tail …` | Blocked by the harness | Waited on background commands instead |
| `./CLI/lint.sh --check` | `cannot execute: required file not found` (zsh is not installed) | Ran its command, `swift run -c release --package-path CLI swiftformat --lint .`: `0/323 files require formatting` |

## Reproducing

Scripts are in [`mock-split/scripts`](mock-split/scripts); every run is in
[`mock-split/results.jsonl`](mock-split/results.jsonl). They expect Swift 6.2.4 at `/opt/swift-6.2.4` (`bench.py`'s
`TOOLCHAIN`).

```bash
swift build --traits sourceBuild -c release --product SafeDITool
```

```bash
swift build --traits sourceBuild -c release --target SafeDI
```

```bash
python3 cloud-reports/mock-split/scripts/make_fixture.py 100 "$BENCH/fixture100"
```

```bash
python3 cloud-reports/mock-split/scripts/make_fixture.py 300 "$BENCH/fixture300"
```

```bash
cloud-reports/mock-split/scripts/run_all.sh "$BENCH" "$PWD/.build/release" "$PWD/.build/release/SafeDITool"
```

```bash
python3 cloud-reports/mock-split/scripts/summarize.py "$BENCH/results.jsonl"
```

```bash
python3 cloud-reports/mock-split/scripts/breakdown.py "$BENCH" fixture300 64 4
```

## Appendix: every run

Generated by `summarize.py` from [`mock-split/results.jsonl`](mock-split/results.jsonl), also kept as
[`mock-split/tables.md`](mock-split/tables.md). Each cell is the **median** (each run, sorted; ± half the spread).
"files compiled" counts the files in the driver's compile jobs, generated files in parentheses.

#### 100 types — rules_swift without the worker (sandboxed or remote): not incremental, no -j

| compile wall s | clean | private-method | add-dependency |
|---|---|---|---|
| combined | **7.15** (6.94 / 7.15 / 7.41; ±0.23) | **6.85** (6.75 / 6.85 / 7.11; ±0.18) | **6.88** (6.83 / 6.88 / 7.25; ±0.21) |
| 8 files | **7.14** (6.91 / 7.14 / 7.38; ±0.23) | **7.01** (6.92 / 7.01 / 7.29; ±0.19) | **6.86** (6.81 / 6.86 / 7.31; ±0.25) |
| 32 files | **7.70** (7.45 / 7.70 / 7.73; ±0.14) | **7.53** (7.33 / 7.53 / 7.89; ±0.28) | **7.62** (7.54 / 7.62 / 7.86; ±0.16) |
| 64 files | **8.40** (8.08 / 8.40 / 8.63; ±0.28) | **8.52** (8.08 / 8.52 / 8.54; ±0.23) | **8.42** (8.09 / 8.42 / 8.67; ±0.29) |

| compile user CPU s | clean | private-method | add-dependency |
|---|---|---|---|
| combined | **6.59** (6.32 / 6.59 / 6.77; ±0.22) | **6.25** (6.19 / 6.25 / 6.44; ±0.12) | **6.24** (6.20 / 6.24 / 6.56; ±0.18) |
| 8 files | **6.53** (6.34 / 6.53 / 6.74; ±0.20) | **6.46** (6.33 / 6.46 / 6.66; ±0.17) | **6.27** (6.23 / 6.27 / 6.66; ±0.21) |
| 32 files | **6.94** (6.75 / 6.94 / 6.99; ±0.12) | **6.82** (6.64 / 6.82 / 7.04; ±0.20) | **6.94** (6.91 / 6.94 / 7.08; ±0.08) |
| 64 files | **7.53** (7.22 / 7.53 / 7.67; ±0.23) | **7.64** (7.24 / 7.64 / 7.72; ±0.24) | **7.53** (7.31 / 7.53 / 7.75; ±0.22) |

| generate wall s · files changed · files compiled (generated) | clean | private-method | add-dependency |
|---|---|---|---|
| combined | 0.19 · 1/1 · 101 (1) | 0.19 · 0/1 · 101 (1) | 0.18 · 1/1 · 101 (1) |
| 8 files | 0.20 · 9/9 · 109 (9) | 0.21 · 0/9 · 109 (9) | 0.18 · 4/9 · 109 (9) |
| 32 files | 0.20 · 33/33 · 133 (33) | 0.20 · 0/33 · 133 (33) | 0.19 · 4/33 · 133 (33) |
| 64 files | 0.22 · 65/65 · 165 (65) | 0.22 · 0/65 · 165 (65) | 0.23 · 5/65 · 165 (65) |

#### 100 types — rules_swift with its persistent worker: -incremental, no -j, every generated file rewritten

| compile wall s | clean | private-method | add-dependency |
|---|---|---|---|
| combined | **7.36** (7.28 / 7.36 / 7.57; ±0.15) | **3.41** (3.26 / 3.41 / 3.50; ±0.12) | **5.37** (4.99 / 5.37 / 5.88; ±0.44) |
| 8 files | **7.69** (7.37 / 7.69 / 7.73; ±0.18) | **3.43** (3.36 / 3.43 / 3.69; ±0.17) | **4.28** (4.20 / 4.28 / 4.74; ±0.27) |
| 32 files | **8.07** (8.04 / 8.07 / 8.33; ±0.15) | **4.11** (3.93 / 4.11 / 4.13; ±0.10) | **5.02** (4.61 / 5.02 / 5.31; ±0.35) |
| 64 files | **8.81** (8.79 / 8.81 / 8.94; ±0.08) | **4.76** (4.73 / 4.76 / 4.98; ±0.12) | **5.41** (5.15 / 5.41 / 5.84; ±0.34) |

| compile user CPU s | clean | private-method | add-dependency |
|---|---|---|---|
| combined | **6.68** (6.62 / 6.68 / 6.94; ±0.16) | **3.04** (2.89 / 3.04 / 3.18; ±0.15) | **4.97** (4.61 / 4.97 / 5.49; ±0.44) |
| 8 files | **7.14** (6.83 / 7.14 / 7.14; ±0.15) | **3.12** (3.06 / 3.12 / 3.33; ±0.14) | **3.94** (3.80 / 3.94 / 4.31; ±0.25) |
| 32 files | **7.41** (7.32 / 7.41 / 7.62; ±0.15) | **3.68** (3.56 / 3.68 / 3.71; ±0.07) | **4.55** (4.18 / 4.55 / 4.80; ±0.31) |
| 64 files | **7.96** (7.88 / 7.96 / 8.11; ±0.11) | **4.21** (4.21 / 4.21 / 4.46; ±0.12) | **4.80** (4.66 / 4.80 / 5.39; ±0.36) |

| generate wall s · files changed · files compiled (generated) | clean | private-method | add-dependency |
|---|---|---|---|
| combined | 0.19 · 1/1 · 101 (1) | 0.21 · 0/1 · 3 (1) | 0.19 · 1/1 · 3 (1) |
| 8 files | 0.22 · 9/9 · 109 (9) | 0.21 · 0/9 · 11 (9) | 0.20 · 4/9 · 11 (9) |
| 32 files | 0.20 · 33/33 · 133 (33) | 0.21 · 0/33 · 35 (33) | 0.19 · 4/33 · 35 (33) |
| 64 files | 0.27 · 65/65 · 165 (65) | 0.22 · 0/65 · 67 (65) | 0.22 · 5/65 · 67 (65) |

#### 100 types — rules_swift worker with file hashing (rules_swift's default from Swift 6.4 / Xcode 27): -incremental, no -j, unchanged generated files untouched

| compile wall s | clean | private-method | add-dependency |
|---|---|---|---|
| combined | **7.41** (7.15 / 7.41 / 8.33; ±0.59) | **3.32** (3.21 / 3.32 / 3.63; ±0.21) | **4.98** (4.95 / 4.98 / 5.51; ±0.28) |
| 8 files | **7.55** (7.42 / 7.55 / 7.62; ±0.10) | **2.55** (2.55 / 2.55 / 2.58; ±0.02) | **3.61** (3.55 / 3.61 / 3.62; ±0.04) |
| 32 files | **8.16** (8.04 / 8.16 / 8.38; ±0.17) | **2.25** (2.11 / 2.25 / 2.44; ±0.17) | **2.88** (2.77 / 2.88 / 2.92; ±0.07) |
| 64 files | **9.18** (8.93 / 9.18 / 9.71; ±0.39) | **2.49** (2.42 / 2.49 / 2.53; ±0.05) | **2.99** (2.90 / 2.99 / 3.09; ±0.09) |

| compile user CPU s | clean | private-method | add-dependency |
|---|---|---|---|
| combined | **6.74** (6.48 / 6.74 / 7.56; ±0.54) | **2.95** (2.79 / 2.95 / 3.24; ±0.23) | **4.61** (4.47 / 4.61 / 5.07; ±0.30) |
| 8 files | **6.90** (6.81 / 6.90 / 6.99; ±0.09) | **2.26** (2.23 / 2.26 / 2.26; ±0.01) | **3.27** (3.21 / 3.27 / 3.30; ±0.04) |
| 32 files | **7.38** (7.26 / 7.38 / 7.63; ±0.19) | **1.94** (1.82 / 1.94 / 2.08; ±0.13) | **2.50** (2.42 / 2.50 / 2.55; ±0.06) |
| 64 files | **8.18** (8.00 / 8.18 / 8.89; ±0.45) | **2.13** (2.10 / 2.13 / 2.22; ±0.06) | **2.61** (2.51 / 2.61 / 2.67; ±0.08) |

| generate wall s · files changed · files compiled (generated) | clean | private-method | add-dependency |
|---|---|---|---|
| combined | 0.24 · 1/1 · 101 (1) | 0.21 · 0/1 · 3 (1) | 0.21 · 1/1 · 3 (1) |
| 8 files | 0.22 · 9/9 · 109 (9) | 0.18 · 0/9 · 6 (4) | 0.19 · 4/9 · 6 (4) |
| 32 files | 0.20 · 33/33 · 133 (33) | 0.18 · 0/33 · 6 (4) | 0.20 · 4/33 · 6 (4) |
| 64 files | 0.24 · 65/65 · 165 (65) | 0.19 · 0/65 · 7 (5) | 0.21 · 5/65 · 7 (5) |

#### 100 types — custom build or Xcode-like: -incremental, -j 4, generated files written only when changed

| compile wall s | clean | private-method | add-dependency |
|---|---|---|---|
| combined | **4.94** (4.92 / 4.94 / 5.08; ±0.08) | **3.06** (3.04 / 3.06 / 3.14; ±0.05) | **4.22** (4.21 / 4.22 / 4.64; ±0.21) |
| 8 files | **5.12** (5.08 / 5.12 / 5.32; ±0.12) | **1.70** (1.25 / 1.70 / 1.96; ±0.35) | **1.78** (1.58 / 1.78 / 2.11; ±0.26) |
| 32 files | **3.23** (3.16 / 3.23 / 3.58; ±0.21) | **1.61** (1.20 / 1.61 / 1.67; ±0.23) | **1.42** (1.40 / 1.42 / 1.50; ±0.05) |
| 64 files | **2.89** (2.83 / 2.89 / 3.03; ±0.10) | **1.82** (1.81 / 1.82 / 1.90; ±0.04) | **1.57** (1.37 / 1.57 / 2.09; ±0.36) |

| compile user CPU s | clean | private-method | add-dependency |
|---|---|---|---|
| combined | **6.49** (6.21 / 6.49 / 6.68; ±0.23) | **2.96** (2.92 / 2.96 / 2.99; ±0.04) | **4.69** (4.68 / 4.69 / 5.03; ±0.18) |
| 8 files | **6.81** (6.61 / 6.81 / 6.98; ±0.19) | **2.73** (2.64 / 2.73 / 3.05; ±0.20) | **3.81** (3.75 / 3.81 / 3.99; ±0.12) |
| 32 files | **7.31** (6.64 / 7.31 / 7.33; ±0.35) | **2.36** (2.27 / 2.36 / 2.54; ±0.14) | **3.09** (2.91 / 3.09 / 3.12; ±0.10) |
| 64 files | **8.03** (7.80 / 8.03 / 8.17; ±0.19) | **2.47** (2.43 / 2.47 / 2.51; ±0.04) | **2.89** (2.78 / 2.89 / 2.92; ±0.07) |

| generate wall s · files changed · files compiled (generated) | clean | private-method | add-dependency |
|---|---|---|---|
| combined | 0.20 · 1/1 · 101 (1) | 0.19 · 0/1 · 3 (1) | 0.16 · 1/1 · 3 (1) |
| 8 files | 0.21 · 9/9 · 109 (9) | 0.18 · 0/9 · 6 (4) | 0.20 · 4/9 · 6 (4) |
| 32 files | 0.23 · 33/33 · 133 (33) | 0.19 · 0/33 · 6 (4) | 0.18 · 4/33 · 6 (4) |
| 64 files | 0.24 · 65/65 · 165 (65) | 0.20 · 0/65 · 7 (5) | 0.21 · 5/65 · 7 (5) |

#### 300 types — rules_swift without the worker (sandboxed or remote): not incremental, no -j

| compile wall s | clean | private-method | add-dependency |
|---|---|---|---|
| combined | **32.84** (29.34 / 32.84 / 34.41; ±2.53) | **32.80** (31.63 / 32.80 / 33.49; ±0.93) | **31.50** (29.71 / 31.50 / 31.80; ±1.04) |
| 8 files | **29.70** (29.30 / 29.70 / 32.08; ±1.39) | **30.73** (29.73 / 30.73 / 31.50; ±0.88) | **30.94** (28.92 / 30.94 / 32.95; ±2.02) |
| 32 files | **32.48** (29.05 / 32.48 / 33.05; ±2.00) | **32.19** (30.27 / 32.19 / 32.24; ±0.99) | **32.79** (31.47 / 32.79 / 33.48; ±1.00) |
| 64 files | **34.32** (31.95 / 34.32 / 34.89; ±1.47) | **34.31** (32.77 / 34.31 / 36.11; ±1.67) | **33.46** (31.73 / 33.46 / 34.74; ±1.51) |

| compile user CPU s | clean | private-method | add-dependency |
|---|---|---|---|
| combined | **29.90** (26.78 / 29.90 / 30.91; ±2.06) | **29.53** (27.94 / 29.53 / 30.78; ±1.42) | **28.68** (27.06 / 28.68 / 28.85; ±0.90) |
| 8 files | **27.73** (27.45 / 27.73 / 30.00; ±1.28) | **28.65** (27.87 / 28.65 / 29.42; ±0.78) | **28.87** (26.92 / 28.87 / 31.09; ±2.08) |
| 32 files | **30.23** (27.01 / 30.23 / 30.60; ±1.79) | **29.98** (28.18 / 29.98 / 30.00; ±0.91) | **30.54** (29.32 / 30.54 / 31.22; ±0.95) |
| 64 files | **31.78** (29.56 / 31.78 / 32.13; ±1.29) | **31.71** (30.32 / 31.71 / 33.71; ±1.70) | **31.04** (29.24 / 31.04 / 32.11; ±1.44) |

| generate wall s · files changed · files compiled (generated) | clean | private-method | add-dependency |
|---|---|---|---|
| combined | 0.68 · 1/1 · 301 (1) | 0.94 · 0/1 · 301 (1) | 0.72 · 1/1 · 301 (1) |
| 8 files | 0.69 · 9/9 · 309 (9) | 0.71 · 0/9 · 309 (9) | 0.73 · 4/9 · 309 (9) |
| 32 files | 0.71 · 33/33 · 333 (33) | 0.72 · 0/33 · 333 (33) | 0.70 · 5/33 · 333 (33) |
| 64 files | 0.72 · 65/65 · 365 (65) | 0.66 · 0/65 · 365 (65) | 0.71 · 5/65 · 365 (65) |

#### 300 types — rules_swift with its persistent worker: -incremental, no -j, every generated file rewritten

| compile wall s | clean | private-method | add-dependency |
|---|---|---|---|
| combined | **32.04** (29.73 / 32.04 / 32.50; ±1.38) | **14.82** (13.62 / 14.82 / 15.00; ±0.69) | **24.08** (23.27 / 24.08 / 25.05; ±0.89) |
| 8 files | **31.03** (29.70 / 31.03 / 32.80; ±1.55) | **13.93** (13.27 / 13.93 / 15.26; ±1.00) | **18.04** (17.88 / 18.04 / 18.31; ±0.21) |
| 32 files | **32.62** (31.48 / 32.62 / 32.66; ±0.59) | **15.85** (15.08 / 15.85 / 15.96; ±0.44) | **18.51** (18.41 / 18.51 / 18.64; ±0.12) |
| 64 files | **33.91** (33.06 / 33.91 / 34.37; ±0.65) | **17.57** (17.00 / 17.57 / 19.41; ±1.21) | **20.39** (19.54 / 20.39 / 20.92; ±0.69) |

| compile user CPU s | clean | private-method | add-dependency |
|---|---|---|---|
| combined | **29.51** (27.50 / 29.51 / 29.66; ±1.08) | **13.44** (12.17 / 13.44 / 13.46; ±0.65) | **22.62** (21.48 / 22.62 / 23.39; ±0.96) |
| 8 files | **28.92** (27.89 / 28.92 / 30.64; ±1.38) | **12.93** (12.33 / 12.93 / 14.24; ±0.96) | **16.98** (16.93 / 16.98 / 17.09; ±0.08) |
| 32 files | **30.38** (29.28 / 30.38 / 30.68; ±0.70) | **14.59** (13.89 / 14.59 / 14.67; ±0.39) | **17.22** (17.16 / 17.22 / 17.35; ±0.10) |
| 64 files | **31.35** (30.78 / 31.35 / 31.93; ±0.57) | **16.20** (15.67 / 16.20 / 17.88; ±1.10) | **18.91** (17.96 / 18.91 / 19.47; ±0.75) |

| generate wall s · files changed · files compiled (generated) | clean | private-method | add-dependency |
|---|---|---|---|
| combined | 0.81 · 1/1 · 301 (1) | 0.67 · 0/1 · 3 (1) | 0.72 · 1/1 · 3 (1) |
| 8 files | 0.69 · 9/9 · 309 (9) | 0.66 · 0/9 · 11 (9) | 0.65 · 4/9 · 11 (9) |
| 32 files | 0.65 · 33/33 · 333 (33) | 0.62 · 0/33 · 35 (33) | 0.71 · 5/33 · 35 (33) |
| 64 files | 0.72 · 65/65 · 365 (65) | 0.78 · 0/65 · 67 (65) | 0.77 · 5/65 · 67 (65) |

#### 300 types — rules_swift worker with file hashing (rules_swift's default from Swift 6.4 / Xcode 27): -incremental, no -j, unchanged generated files untouched

| compile wall s | clean | private-method | add-dependency |
|---|---|---|---|
| combined | **31.32** (30.34 / 31.32 / 31.74; ±0.70) | **14.65** (14.23 / 14.65 / 15.98; ±0.88) | **24.33** (22.80 / 24.33 / 26.03; ±1.62) |
| 8 files | **31.23** (30.13 / 31.23 / 32.25; ±1.06) | **9.13** (8.63 / 9.13 / 10.02; ±0.69) | **13.98** (13.45 / 13.98 / 14.32; ±0.44) |
| 32 files | **34.13** (32.94 / 34.13 / 35.11; ±1.09) | **7.66** (7.32 / 7.66 / 8.27; ±0.47) | **10.16** (9.64 / 10.16 / 10.45; ±0.40) |
| 64 files | **35.62** (34.53 / 35.62 / 35.91; ±0.69) | **7.36** (7.05 / 7.36 / 7.51; ±0.23) | **9.34** (9.31 / 9.34 / 9.52; ±0.10) |

| compile user CPU s | clean | private-method | add-dependency |
|---|---|---|---|
| combined | **28.91** (27.79 / 28.91 / 29.11; ±0.66) | **12.97** (12.76 / 12.97 / 14.32; ±0.78) | **22.34** (21.22 / 22.34 / 24.11; ±1.45) |
| 8 files | **28.96** (28.03 / 28.96 / 29.91; ±0.94) | **8.23** (7.87 / 8.23 / 8.84; ±0.48) | **12.89** (12.46 / 12.89 / 13.32; ±0.43) |
| 32 files | **31.94** (30.73 / 31.94 / 32.80; ±1.03) | **6.84** (6.51 / 6.84 / 7.30; ±0.40) | **9.21** (8.75 / 9.21 / 9.56; ±0.41) |
| 64 files | **33.04** (32.08 / 33.04 / 33.28; ±0.60) | **6.53** (6.29 / 6.53 / 6.65; ±0.18) | **8.47** (8.46 / 8.47 / 8.56; ±0.05) |

| generate wall s · files changed · files compiled (generated) | clean | private-method | add-dependency |
|---|---|---|---|
| combined | 0.69 · 1/1 · 301 (1) | 0.77 · 0/1 · 3 (1) | 0.77 · 1/1 · 3 (1) |
| 8 files | 0.70 · 9/9 · 309 (9) | 0.67 · 0/9 · 6 (4) | 0.69 · 4/9 · 6 (4) |
| 32 files | 0.69 · 33/33 · 333 (33) | 0.69 · 0/33 · 7 (5) | 0.70 · 5/33 · 7 (5) |
| 64 files | 0.74 · 65/65 · 365 (65) | 0.75 · 0/65 · 7 (5) | 0.72 · 5/65 · 7 (5) |

#### 300 types — custom build or Xcode-like: -incremental, -j 4, generated files written only when changed

| compile wall s | clean | private-method | add-dependency |
|---|---|---|---|
| combined | **24.70** (24.15 / 24.70 / 25.31; ±0.58) | **15.36** (14.30 / 15.36 / 15.68; ±0.69) | **20.99** (20.30 / 20.99 / 22.31; ±1.00) |
| 8 files | **23.73** (23.54 / 23.73 / 24.77; ±0.62) | **6.92** (6.85 / 6.92 / 7.47; ±0.31) | **8.25** (6.29 / 8.25 / 8.37; ±1.04) |
| 32 files | **15.40** (15.26 / 15.40 / 16.05; ±0.40) | **6.17** (5.96 / 6.17 / 6.69; ±0.37) | **5.77** (5.54 / 5.77 / 5.99; ±0.23) |
| 64 files | **12.39** (12.02 / 12.39 / 13.11; ±0.54) | **6.36** (5.73 / 6.36 / 6.55; ±0.41) | **5.80** (5.13 / 5.80 / 7.78; ±1.33) |

| compile user CPU s | clean | private-method | add-dependency |
|---|---|---|---|
| combined | **29.42** (28.58 / 29.42 / 29.88; ±0.65) | **14.17** (13.15 / 14.17 / 14.41; ±0.63) | **22.29** (21.39 / 22.29 / 23.50; ±1.05) |
| 8 files | **29.31** (28.95 / 29.31 / 30.89; ±0.97) | **10.89** (10.48 / 10.89 / 12.27; ±0.89) | **14.85** (14.43 / 14.85 / 14.92; ±0.25) |
| 32 files | **29.99** (29.85 / 29.99 / 30.96; ±0.55) | **7.93** (7.64 / 7.93 / 8.43; ±0.40) | **10.22** (10.05 / 10.22 / 10.72; ±0.33) |
| 64 files | **30.67** (29.97 / 30.67 / 32.24; ±1.14) | **8.02** (7.32 / 8.02 / 8.14; ±0.41) | **9.89** (9.10 / 9.89 / 10.34; ±0.62) |

| generate wall s · files changed · files compiled (generated) | clean | private-method | add-dependency |
|---|---|---|---|
| combined | 0.73 · 1/1 · 301 (1) | 0.79 · 0/1 · 3 (1) | 0.69 · 1/1 · 3 (1) |
| 8 files | 0.67 · 9/9 · 309 (9) | 0.81 · 0/9 · 6 (4) | 0.70 · 4/9 · 6 (4) |
| 32 files | 0.70 · 33/33 · 333 (33) | 0.71 · 0/33 · 7 (5) | 0.63 · 5/33 · 7 (5) |
| 64 files | 0.69 · 65/65 · 365 (65) | 0.66 · 0/65 · 7 (5) | 0.74 · 5/65 · 7 (5) |
