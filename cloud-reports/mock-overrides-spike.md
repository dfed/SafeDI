Branch: `dfed--claude/cloud-mock-overrides-spike` (checkpoint report; the spike is paused for usage, see "Where it stopped")

# Spike: shared mock builders with overrides as a parameter — checkpoint

This report checks hole-free mocks only. No figure here is a gate: the maintainers' rerun of these commits on their private benchmark is.

## Variant SHA table

| Variant | Commit | Builds `swift build -c release --traits sourceBuild --product SafeDITool` |
|---|---|---|
| main (base) | `2475984` | yes (cold build 16 min on this 4-core machine) |
| B1 enum box | `228b875` | yes |
| B1 class box | `c5f79fa` | yes |
| D2 emission steps | not started | — |

## Setup and versions

- Swift 6.2.4 (`swift-6.2.4-RELEASE`, Target `x86_64-unknown-linux-gnu`), from the swift.org Ubuntu 24.04 tarball, signature checked with gpg against swift.org's keys. swiftly could not install it here: its key import got a compressed response from the proxy and gpg rejected it.
- Ubuntu 24.04, 4 cores, 15 GB, `TMPDIR=~/.cache/safedi-tmp`.
- The macros (`SafeDIMacros-tool`), the `SafeDI` module and its objects are copied once from main's release build and used for every variant. A second `SafeDI` built with `-enable-library-evolution` (static archive, from `Sources/SafeDI`) serves the library evolution probe.

## What is done

### Storage (B1), enum box, commit `228b875`

`generateSafeDIOverridesStruct`, `generateConfigurationStruct` (`ScopeGenerator.swift`) and `publicStructBody` (`PublicMockGeneration.swift`) store every field whose type is a configuration (a nested `SafeDIMockConfiguration`, a public module-level configuration, or a called public mock's `SafeDIOverrides`) in

```swift
private nonisolated struct __safeDI_Nested { let leaf: …; let pane: … }
private nonisolated indirect enum __safeDI_Reference { case to(__safeDI_Nested) }
private let __safeDI_nested: __safeDI_Reference
```

read through `var leaf: … { switch __safeDI_nested { case let .to(nested): nested.leaf } }` at the field's own access. A configuration that nests none is unchanged byte for byte (the helper returns nothing for no members). The nested types always say `nonisolated`, so a `nonisolated` struct's initializer can build them in a module whose declarations default to the main actor.

### Compile matrix (B2), main against enum box, Swift 6 mode, `-warnings-as-errors`

Script: `cloud-reports/mock-overrides-spike/probe/matrix.sh`. The probe fixture (`probe/Lib.swift`, `probe/App.swift`) has a `generateMock: .public` mock whose `SafeDIOverrides` nests public configurations, one of which nests another; an internal mock whose configurations nest; an internal mock that nests none; a module that calls the public mock (its configuration holds `Feature.SafeDIOverrides`); and a `SendableInstantiator` chain whose configurations are `@Sendable`-typed.

| | probe, plain | probe, `-default-isolation MainActor` (+ `nonisolated` on every struct by sed) | probe, library evolution | shape D 8, plain | shape D 8, MainActor | shape D 8, library evolution |
|---|---|---|---|---|---|---|
| main `2475984` | ok | ok | ok | ok | fails, in the fixture | ok |
| enum box `228b875` | ok | ok | ok | ok | fails, the same error | ok |

Shape D fails under `-default-isolation MainActor` on main too, in the fixture's own code, not generated code: `error: stored property 'service' of 'Sendable'-conforming class 'Screen7' has non-Sendable type 'Service'`. Without the struct-level `nonisolated`, main's probe fails under that default (`main actor-isolated default value in a nonisolated context` in `Lib.gen.swift`), so the planned `nonisolated` on every configuration is needed for that mode whatever the storage.

### Observable changes (B3), probe run, main → enum box

| Probe | main `let` | enum box |
|---|---|---|
| `MemoryLayout<Shell.SafeDIOverrides>.size` | 128 | 8 |
| `MemoryLayout<Screen.SafeDIMockConfiguration>.size` | 128 | 40 |
| `MemoryLayout<Hub.SafeDIOverrides>.size` (`@Sendable`) | 48 | 8 |
| `MemoryLayout<Card.SafeDIMockConfiguration>.size` (`@Sendable`) | 48 | 24 |
| `MemoryLayout<Feature.SafeDIOverrides>.size` (public) | 96 | 24 |
| key path cast to `WritableKeyPath` (internal, public) | false, false | false, false |
| `Mirror` labels of `Screen.SafeDIMockConfiguration` | service, feature, safeDIBuilder | service, safeDIBuilder, __safeDI_nested |
| `Sendable` inference (`requireSendable(Card.SafeDIMockConfiguration.self)`, `Hub.SafeDIOverrides`) | compiles | compiles |
| a nested read through the generated initializers | 7 | 7 |

So with the enum box only `MemoryLayout` and `Mirror` change; the key path was never writable (`let`), and inferred `Sendable` survives.

### Shape D harness on main (A, smoke only)

`run_d.py` reproduces the brief's numbers: 8 screens gives 389 lines, all driver modes work (`layout` 528 bytes, `stack ok`, `trace` 32 lines, `trace-overrides` 40 lines at 8 screens), at `-Onone`.

### Scripts written, not yet measured

- `rewrite_shared.py`: the D1 scripted shared form of `Root.mock()`. At 8 screens it shares 4 of 8 screen types and takes the mock body from 114 to 82 lines; its output is not compiled or traced yet.
- `proxy.py`: the section C proxy module (30 chained services, 195 features in 15 trees of depth 3, fanout 3, 6 services each, one default-valued parameter, all `generateMock: true`). Not run yet.

## Where it stopped

Paused at the tech lead's request (usage) while the class box variant was compiling. Not done: the class box commit and its matrix and probe run; B4 test churn; B5 cost split; all of A's timings (8–24 screens, `time` at both levels, the reference traces); C; D1's measurements and trace equality; D2.

## Open questions (decisions not mine)

None answered yet; the brief's list stands: whether storage ships if it costs debug compile time or object size; enum or class box; 2.3.1 or later, before or after production; accepting the observable changes above (`Mirror`, `MemoryLayout`, objects only an override holds freed earlier); keeping today's emitter behind a test option; any pass or fail figure. Evidence so far favors neither box: the enum box keeps inferred `Sendable` with no code; a class box needs its `Sendable` written, which SafeDI can only do where every nested configuration is `@Sendable`-typed.

## Files on the branch

- `cloud-reports/mock-overrides-spike.md` (this report)
- `cloud-reports/mock-overrides-spike/shape_d.py` (the brief's fixture, verbatim), `run_d.py`, `rewrite_shared.py`, `proxy.py`
- `cloud-reports/mock-overrides-spike/probe/` (`Lib.swift`, `App.swift`, `probe.sh`, `matrix.sh`)
