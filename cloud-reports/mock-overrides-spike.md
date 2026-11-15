Branch: `dfed--claude/cloud-mock-overrides-spike` (spike: no pull request, nothing merged)

# Spike: shared mock builders with overrides as a parameter

This report checks hole-free mocks only. No figure here is a gate: the maintainers' rerun of these commits on their private benchmark is. Figures labeled "hand-written" come from a script that rewrites generated code; figures labeled "proxy" come from the section C module, and no storage decision rests on them.

## Variant SHA table

Each variant commit builds with `swift build -c release --traits sourceBuild --product SafeDITool`.

| Variant | Commit | Builds |
|---|---|---|
| main (base) | `2475984` | yes (cold build 16 min on this 4-core machine) |
| B1 enum box | `228b875` | yes |
| B1 class box | `c5f79fa` | yes |
| D2 shared emission on the enum box (one step: analysis, placement and calls together) | `401e334` | yes |

`401e334` sits on top of `c5f79fa` and sets the storage constant back to the enum box, so its storage is `228b875`'s. The report and scripts are in later commits on the branch.

## Setup and versions

- Swift 6.2.4 (`swift-6.2.4-RELEASE`, target `x86_64-unknown-linux-gnu`), from the swift.org Ubuntu 24.04 tarball, its signature checked with gpg against swift.org's keys (swiftly could not install it here: its key import got a compressed response from the proxy, which gpg rejected).
- Ubuntu 24.04, 4 cores, 15 GB, `TMPDIR=~/.cache/safedi-tmp`.
- The macros (`SafeDIMacros-tool`), the `SafeDI` module and its objects come from main's release build and serve every variant. A second `SafeDI` built with `-enable-library-evolution` serves the library evolution runs.
- Load during timing rounds was 0.9–1.16 (target below 1; the machine has nothing else running, the excess is the harness itself). Baseline and variants alternate inside each round.
- Compile figures time the App module's `swift-frontend -c` job (taken from `swiftc -###`), median of 5 (3 above 16 screens), with min–max. `time` figures are the median of 200 `Root.mock()` calls in nanoseconds. Every row below names its script; the scripts print the full command in their JSON (`results/*.jsonl`).

## Recommended design

1. **Storage: the enum box.** Every field whose type is a configuration (nested `SafeDIMockConfiguration`, public module-level configuration, called mock's `SafeDIOverrides`) moves into a `private nonisolated struct __safeDI_Nested`, held through `private nonisolated indirect enum __safeDI_Reference { case to(__safeDI_Nested) }` and read through a get-only computed property of the same name, type and access. A configuration that nests nothing is unchanged byte for byte. The enum box keeps inferred `Sendable`; the class box needs `Sendable` written and can write it only where every nested configuration is `@Sendable`-typed, and its `-O` objects keep class metadata (13,808 → 94,952 bytes for shape D 16; 712,272 → 1,790,056 for the proxy).
2. **Emission: one builder function per key, configuration last.** Key = concrete type, instantiated type, erasure, mock-or-init construction, extension-based, forwarded properties (sorted), and whether it reads a configuration. Shared only when the key has two or more places. The function is `__safeDI_<label>(<forwarded…>, safeDIOverrides: <Type>.SafeDIMockConfiguration) -> T`; each place keeps its `let <label> = Instantiator<T> { __safeDI_<label>($0, safeDIOverrides: <its path>) }`. Outside values are captured when no label they read is declared again below the mock root on any place's path; otherwise the type is not shared.
3. **Never shared:** a subtree with a cycle (any cycle flag, cycle parameters, closed-on declarations), a `@Sendable` builder or a configuration that requires `Sendable`, a loop of builders, scope payloads, fills, calls of public mocks, `onlyIfAvailable` aliases or unavailable receives, `LazilyInstantiated` instances, and every public mock (D2 runs only when `publicMock == nil`). Each exclusion keeps today's nested text, so the change grows by measured need.
4. **What the new builder struct changes:** the configuration is a parameter, not a capture, so one function serves every path. Storage is what makes that cheap: with today's `let` fields each pass copies the whole nested value (Root's overrides are 419,856 bytes at 32 screens), so the shared form alone still compiles exponentially (16.5 s and 106 MB at 32 screens) and overflows a 512 KB thread. With the box, the shared form is linear up to 32 screens (0.67 s, 1.2 MB).

Both halves are needed: storage alone fixes object size and runtime but not the exponential text (10,933 lines at 24 screens); emission alone fixes the text but not the copies.

## A. Shape D baseline on main (`measure_a.sh`, `run_d.py`, `-Onone`)

| screens | App lines | generate | compile wall (min–max) | user | App.o bytes | `Root.SafeDIOverrides` size |
|---|---|---|---|---|---|---|
| 8 | 389 | 0.03 s | 0.21 (0.18–0.24) | 0.17 | 256,464 | 528 |
| 12 | 757 | 0.06 s | 0.52 (0.47–0.66) | 0.47 | 969,176 | 1,680 |
| 16 | 1,629 | 0.10 s | 1.66 (1.32–1.80) | 1.50 | 5,239,272 | 5,136 |
| 20 | 4,013 | 0.21 s | 7.34 (7.10–7.38) | 6.57 | 37,439,272 | 15,504 |
| 24 | 10,933 | 0.59 s | 59.40 (55.99–61.04) | 51.23 | 308,206,504 | 46,608 |

Line counts match the brief's exactly (its compile times were measured with another compiler). 32 screens generates 92,813 lines in 4.44 s. `time` (ns, plain / `--walk`): 8 `-Onone` 1,357 / 7,476, `-O` 444 / 3,418; 12 `-Onone` 8,811 / 71,168, `-O` 1,087 / 19,403; 16 `-Onone` 30,249 / 1,317,571, `-O` 4,346 / 153,819. Reference traces: 8 screens 32 / 40 lines (`trace` / `trace-overrides`), 16 screens 320 / 345, in `results/reference-traces/`.

## B. Storage

### B1. Commits

`228b875` (enum box) and `c5f79fa` (class box) change `generateConfigurationStruct`, `generateSafeDIOverridesStruct` (`ScopeGenerator.swift`) and `publicStructBody` (`PublicMockGeneration.swift`) through one helper, `nestedConfigurationStorage(of:indent:sendable:)`, selected by a constant. The nested types always say `nonisolated`, so a `nonisolated` configuration's initializer can build them under `-default-isolation MainActor`.

### B2. Compile matrix (`probe/matrix.sh`, Swift 6 mode, `-warnings-as-errors`)

The probe fixture has a `generateMock: .public` mock whose `SafeDIOverrides` nests public configurations two deep, internal mocks that nest and do not, a module calling the public mock, and a `SendableInstantiator` chain whose configurations are `@Sendable`-typed.

| | probe plain | probe MainActor | probe evolution | shape D 8 plain | shape D 8 MainActor | shape D 8 evolution |
|---|---|---|---|---|---|---|
| main `2475984` | ok | ok | ok | ok | fails in fixture | ok |
| enum box `228b875` | ok | ok | ok | ok | fails in fixture | ok |
| class box `c5f79fa` | ok | ok | ok | ok | fails in fixture | ok |

The MainActor column adds `nonisolated` to every configuration struct by `sed` (the planned change). Without it main's own probe fails: `main actor-isolated default value in a nonisolated context` in `Lib.gen.swift`. Shape D fails under MainActor on every variant in the fixture's own code: `error: stored property 'service' of 'Sendable'-conforming class 'Screen7' has non-Sendable type 'Service'`.

### B3. Observable changes (`probe/probe.sh`, main → enum box; the class box gives the same)

| Probe | main `let` | box |
|---|---|---|
| `MemoryLayout<Shell.SafeDIOverrides>.size` | 128 | 8 |
| `MemoryLayout<Screen.SafeDIMockConfiguration>.size` | 128 | 40 |
| `MemoryLayout<Hub.SafeDIOverrides>.size` (`@Sendable`) | 48 | 8 |
| `MemoryLayout<Card.SafeDIMockConfiguration>.size` (`@Sendable`) | 48 | 24 |
| `MemoryLayout<Feature.SafeDIOverrides>.size` (public) | 96 | 24 |
| key path cast to `WritableKeyPath` (internal, public) | false, false | false, false |
| `Mirror` labels of `Screen.SafeDIMockConfiguration` | service, feature, safeDIBuilder | service, safeDIBuilder, __safeDI_nested |
| inferred `Sendable` (`Card.SafeDIMockConfiguration`, `Hub.SafeDIOverrides`) | compiles | compiles |
| a nested read through the generated initializers | 7 | 7 |

Only `MemoryLayout` and `Mirror` change; the fields were never writable (`let`).

### B4. Test churn (`SAFEDI_SKIP_COMPILE_CHECK=1 swift test --traits sourceBuild --filter 'SafeDIToolMockTests|SafeDIToolSeamTests'`, Sources at `228b875`)

2,123 tests ran; 446 test functions change expected output (604 issues), none crash: `SafeDIToolMockTests` 433 functions in 29 suites, `SafeDIToolSeamTests` 13 in 5 suites. Expectations were not updated. Per-suite counts and every function are in `results/B4-enumbox-churn.txt`. The class box changes the same expectations (same members move), with different text.

### B5. Cost split (`measure_bc.sh`, `proxy.py`, `-Onone`; proxy)

(b) No configuration nests another (`proxy.py --flat`: 195 leaf features): every feature's generated mock is byte-identical to main's on both boxes. The files differ only inside `extension Root`, whose `SafeDIOverrides` nests the 195 feature configurations (`diff` hunks at lines 28,836–29,288, all in that extension). Compile: main 15.45 (15.06–15.85) s, 17,652,648 B; enum box 14.91 (14.33–15.51), 17,787,320 B; class box 14.69 (13.70–16.18), 17,553,880 B: the same within spread.

(a) Configurations nest (the C proxy below): enum box +3% wall, +4% object; class box +2% wall, −1% object, all inside the spread.

## C. Proxy module and shape D 16 (`measure_bc.sh`; proxy, not the gate)

Proxy: 30 chained services, 195 features in 15 trees (depth 3, fanout 3), 6 services each, one default-valued parameter, all `generateMock: true`; 35,060 generated lines on main.

| | compile wall `-Onone` | object | `mock()` ns | compile wall `-O` | object `-O` | `mock()` ns `-O` |
|---|---|---|---|---|---|---|
| main | 15.64 (14.51–16.04) | 19,923,512 | 6,478 | 11.63 (10.67–12.22) | 712,272 | 3,305 |
| enum box | 16.10 (15.32–16.85) | 20,694,320 | 4,927 | 12.03 (11.75–12.54) | 712,272 | 2,476 |
| class box | 16.00 (15.34–16.81) | 19,671,888 | 4,877 | 11.07 (10.65–11.60) | 1,790,056 | 2,412 |

Counters (`-stats-output-dir`, `-Onone`, main / enum / class): constraint scopes 115,476 / 119,214 / 115,972; SILGen functions 11,571 / 12,188 / 12,551; decls type-checked 40,761 / 42,854 / 42,612. `NumInstructionsExecuted` is not reported on Linux.

Shape D at 16 screens without shared emission (`-Onone`):

| | compile wall | object | `time` ns | `--walk` ns |
|---|---|---|---|---|
| main | 1.35 (1.25–1.40) | 5,239,272 | 22,463 | 1,629,282 |
| enum box | 0.88 (0.83–0.90) | 1,112,656 | 8,769 | 350,997 |
| class box | 0.72 (0.68–0.82) | 941,336 | 13,193 | 162,882 |

At `-O`: compile 0.69 / 0.67 / 0.63 s; object 13,808 / 13,808 / 94,952; `time` 4,149 / 2,020 / 4,122; `--walk` 230,508 / 74,354 / 48,765. With the planned `nonisolated` on every configuration (`--nonisolated`), main 1.53 (1.37–1.70) s and 23,206 ns, enum box 0.86 (0.83–1.02) s and 8,406 ns.

## D1. Shared form, hand-written (`rewrite_shared.py`, `measure_d1.sh`, `-Onone`)

The script rewrites `Root.mock()` into the shared form: a screen type with two or more parent bodies gets one function placed in the lowest body all its places pass through. Traces equal main's at 8 and 16 for both storages.

| screens | `let` lines | `let` compile | `let` object | box lines | box compile | box object |
|---|---|---|---|---|---|---|
| 8 | 357 | 0.17 (0.16–0.20) | 240,880 | 361 | 0.18 (0.16–0.21) | 244,120 |
| 12 | 525 | 0.26 (0.22–0.28) | 583,760 | 533 | 0.26 (0.24–0.31) | 398,168 |
| 16 | 693 | 0.40 (0.37–0.44) | 1,508,312 | 705 | 0.30 (0.29–0.36) | 552,696 |
| 20 | 861 | 0.77 (0.77–0.78) | 4,381,904 | 877 | 0.46 (0.40–0.46) | 709,016 |
| 24 | 1,029 | 1.99 (1.78–2.02) | 12,094,624 | 1,049 | 0.59 (0.49–0.59) | 862,000 |
| 28 | 1,197 | 5.35 (5.13–5.44) | 35,774,128 | 1,221 | 0.66 (0.53–0.70) | 1,017,680 |
| 32 | 1,365 | 16.51 (16.14–16.78) | 105,979,752 | 1,393 | 0.67 (0.62–0.70) | 1,171,384 |

At 32 screens `Root.SafeDIOverrides` is 419,856 bytes with `let` and `Root.mock()` on a 512 KB thread crashes (`stack`: exit -11, SIGSEGV); with the box it is 24 bytes and `stack ok`.

`time` ns (plain / `--walk`), `let` → box: 16 `-Onone` 23,239 / 137,634 → 12,440 / 132,866; 16 `-O` 2,945 / 71,926 → 2,083 / 35,926; 24 `-Onone` 828,758 / 3,147,635 → 78,011 / 1,218,066; 24 `-O` 43,715 / 987,868 → 16,772 / 390,815.

## D2. Generator prototype (`401e334`, `measure_d2.sh`)

`SharedMockBuilders` (`ScopeGenerator.swift`) analyzes an internal mock's tree before emission, using the key and exclusions in "Recommended design"; `generateMockBodyBindings` emits each shared function once, at the mock body's top level before the first top-level statement that reaches it, and each place as a call. Public mocks are untouched.

- Output equals D1's hand-written enum-box form byte for byte at 8 screens. At 12, 16, 24 and 32 it has the same lines and differs only in where functions sit (top level, where D1 uses the lowest common body). At 20 and 28 it shares one or two more types than the script (the generator shares a key with two places; the script needs two parent bodies), with the same line count.
- Traces equal main's at 8 and 16 (`trace` and `trace-overrides`).

| screens | lines | compile wall | object |
|---|---|---|---|
| 8 | 361 | 0.18 (0.18–0.24) | 244,120 |
| 12 | 533 | 0.30 (0.24–0.32) | 398,168 |
| 16 | 705 | 0.35 (0.31–0.40) | 552,696 |
| 20 | 877 | 0.39 (0.38–0.46) | 708,048 |
| 24 | 1,049 | 0.45 (0.44–0.49) | 862,000 |
| 28 | 1,221 | 0.55 (0.53–0.74) | 1,016,672 |
| 32 | 1,393 | 0.70 (0.60–0.73) | 1,171,384, `stack ok` |

`time` ns (plain / `--walk`): 16 `-Onone` 8,562 / 141,188; 16 `-O` 3,226 / 36,846; 24 `-Onone` 76,310 / 891,422; 24 `-O` 17,377 / 369,648.

Filtered tests with compile checks on (`swift test --traits sourceBuild --filter 'SafeDIToolMockTests|SafeDIToolSeamTests'`, `SAFEDI_SKIP_COMPILE_CHECK` unset): 2,123 tests, every test's generated code compiled except in the 3 known issues the suite already records (seam fills, `SafeDIToolSeamPlaceInsideFillOfBothRootEnumsTests`). The 446 test functions that fail are exactly B4's, on expected text alone: no fixture's mock failed to compile with shared emission (`results/D2-tests.txt`). The verifier compiles the tool's actual output, before expectations are compared. Shared emission adds no failing test beyond the storage's; which of those 446 it changes again was not counted.

Not done in D2: placement at the lowest common body (top level is simpler and gives the same lines); a deterministic-order review of the analyzer (it walks with an explicit stack and orders keys by first place; names follow the sorted key, which a rename oracle may move); sharing inside `@Sendable` builders, cycles and public mocks; fuzzer draws.

## What broke, with error text

- `swiftly install 6.2.4`: gpg rejected the key file the proxy served compressed; worked around by fetching the keys with `curl --compressed` and checking the tarball's signature by hand.
- Library evolution with the stock `SafeDI` build: the probe needs `SafeDI` built with `-enable-library-evolution` (built separately).
- `-default-isolation MainActor` without `nonisolated` on the configuration structs, main and boxes alike: `main actor-isolated default value in a nonisolated context`.
- Shape D under MainActor, every variant: `stored property 'service' of 'Sendable'-conforming class 'Screen7' has non-Sendable type 'Service'` (fixture code).
- D1 with `let` storage at 32 screens: `Root.mock()` overflows a 512 KB stack (SIGSEGV).
- D2's first build: the new arguments were passed out of declaration order (`incorrect argument labels in call`); fixed before the commit.

## Open questions (decisions not mine)

1. **Ship storage if it costs debug compile time or object size?** Recommend yes. On the proxy the enum box costs +3% compile and +4% object, inside the spread; on shape D 16 it saves 35% compile and 79% object; and shared emission needs it to be linear (D1 table).
2. **Enum or class box?** Recommend the enum box: it keeps inferred `Sendable` with no code, and keeps `-O` objects the size of main's. The class box compiles a little faster on shape D (0.72 vs 0.88 s at 16) but needs written `Sendable` and keeps class metadata at `-O`.
3. **2.3.1 or later, before or after production's per-type work?** Recommend storage and emission together in one release, since emission without storage is still exponential; ordering against production is the maintainers' call.
4. **Accept the observable changes** (`Mirror` labels gain `__safeDI_nested`, `MemoryLayout` shrinks, an object only an override holds is freed when the shared box is)? Recommend yes; the Manual already says a configuration's storage is not API.
5. **Keep today's emitter behind a test option?** Recommend no: the 446 changed expectations are text, and a second emitter doubles the matrix.
6. **Pass or fail figures:** none proposed here; the private benchmark decides.

## Files on the branch

- `cloud-reports/mock-overrides-spike.md` (this report)
- `cloud-reports/mock-overrides-spike/`: `shape_d.py` (the brief's fixture, verbatim), `run_d.py`, `rewrite_shared.py`, `proxy.py`, `summarize.py`, `measure_a.sh`, `measure_d1.sh`, `measure_bc.sh`, `measure_d2.sh`
- `probe/` (`Lib.swift`, `App.swift`, `probe.sh`, `matrix.sh`)
- `results/` (every measurement as JSON lines, `B2-matrix-boxes.txt`, `B4-enumbox-churn.txt`, `reference-traces/`)
- `generated/` (`App.gen.swift` for 8 and 16 screens from main, both boxes, D1 hand-written on `let` and the enum box, and D2)
