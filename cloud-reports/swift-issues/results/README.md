# Measurements

All runs were on Ubuntu 24.04.5 LTS (x86_64, 4 cores, 16 GB) with swift.org release toolchains 6.4.2, 6.3.3 and 6.2.4 (signatures verified), and swift-syntax 604.0.0. The harness (`../repros/Harness`) logs one line per expansion from inside the plugin, with the frontend job, plus each request's size and the plugin process's CPU time. `../repros/scripts` generates the client sources and runs the builds.

## Scale matrix

[`matrix-table.md`](matrix-table.md) is the output of `scripts/table.py` over every matrix build. Each type is a `final class` with `@NoopMember` and `@NoopPeer` on two stored properties, one type per file, all constructed in `Use.swift`. Builds:

- `debug-clean`: Debug, the `Client` module rebuilt from scratch.
- `debug-touchT0` and `debug-touchUse`: incremental Debug after touching that file.
- `release-clean`: whole-module Release with `-j 2`.

Expansion counts are identical on every toolchain and build system. Plugin CPU is the sum over plugin processes of the CPU time each had used at its last expansion.

## What triggers the expansion in another file's job

Two files: `Types.swift` declares 100 types, and `Use.swift` uses them. Each type has 1 member macro and 2 peer macros, so a job that expands all of them logs 300. Swift 6.4.2, Debug. The table gives each job's expansions.

| `Use.swift` | Kind | emit-module | `compile[Types.swift]` | `compile[Use.swift]` |
|---|---|---|---|---|
| empty `use()` | class | 300 | 300 | 0 |
| empty `use()` | struct | 300 | 300 | 0 |
| `_ = T()` | class | 300 | 300 | 300 |
| `_ = T()` | struct | 300 | 300 | 300 |
| `[T.self]` as `[Any.Type]` | class | 300 | 300 | 300 |
| `[T.self]` as `[Any.Type]` | struct | 300 | 300 | 300 |
| `func f(_: T) {}` | class | 300 | 300 | 0 |
| `func f(_: T) {}` | struct | 300 | 300 | 300 |
| `func f(_ v: T) { _ = v.description }` (computed) | class | 300 | 300 | 0 |
| `func f(_ v: T) -> Int { v.a }` (stored) | class | 300 | 300 | 300 |

Peer macros moved to a computed property and a method (no member macro, plain stored properties), with `_ = T()`: 200 in each of the three jobs, for both class and struct.

## Build configuration in each request

Mean request size in SwiftPM Debug builds, and the `staticBuildConfiguration` string inside it:

| Toolchain | Request bytes | Configuration bytes |
|---|---|---|
| 6.2.4 | ~900 | 0 |
| 6.3.3 | ~5,400 | 4,080 (4,072 in Release) |
| 6.4.2 | ~5,900 | 4,504 (4,496 in Release) |

The configuration content is the same in each request of a plugin process; only the order of elements in set-valued fields varies. `request-samples/` holds two captured requests per toolchain.

Decode benchmark (`repros/Harness/Sources/DecodeBench`) on a captured 6.4.2 request of 5,843 bytes:

| swift-syntax | Request | Configuration string | Request without the field |
|---|---|---|---|
| Release | 27.8 µs | 72.0 µs | 7.7 µs |
| Debug | 502 µs | 343 µs | 87 µs |

The same benchmark on a 6.3.3 request, Release: 25.7 µs, 63.4 µs and 7.6 µs.

A/B in one plugin binary: 1,000 classes in two files, 9,000 expansions, clean Debug. Per-run values; "removed" means the plugin handed swift-syntax each request without the field.

| Toolchain | Plugin CPU, kept (ms) | Plugin CPU, removed (ms) | Wall, kept (s) | Wall, removed (s) |
|---|---|---|---|---|
| 6.4.2 | 15,700 / 14,912 / 15,243 | 11,487 / 10,786 / 11,173 | 16.6 / 15.5 / 15.5 | 14.8 / 14.0 / 14.2 |
| 6.3.3 | 14,692 / 14,994 / 14,309 | 10,386 / 11,063 / 11,143 | 13.6 / 15.2 / 14.9 | 12.6 / 13.4 / 13.4 |

## Baselines without macros

1,000 types, one per file, `Use.swift` constructing all, Swift 6.4.2 (Swift Build), Debug, wall-clock seconds per run:

| Build | No macro attributes | `@NoopMember` + 2 × `@NoopPeer` per type |
|---|---|---|
| clean | 8.8 / 9.4 / 9.6 | 15.5 / 16.2 / 18.5 |
| incremental, `T0.swift` touched | 6.6 / 6.1 / 7.0 | 13.7 / 13.5 / 12.9 |
