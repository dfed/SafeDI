# Example Bazel Integration

A Bazel port of `ExampleTuistIntegration`, demonstrating SafeDI's
cross-module `.safedi` artifact handoff in a Bazel-native way. The
Swift source code (types, mocks, previews) is byte-for-byte identical
to the Tuist example — the differences are entirely in the build
system.

**Supported host:** macOS arm64 only (matches the
[`rules_apple`](https://github.com/bazelbuild/rules_apple) macOS
toolchain). The SafeDI rules themselves are platform-agnostic.

## What it demonstrates

- **Two `swift_library` targets** (`//Subproject:Subproject`,
  `//ExampleBazelIntegration:ExampleBazelIntegration`) that compile
  separately.
- **`safedi_swift_library` macro** — `load("@safedi//bazel:safedi.bzl", "safedi_swift_library")`. It takes a `swift_library`'s attributes and declares two targets from them:
  - `<name>`, the `swift_library`, which compiles `srcs` together with the generated code.
  - `<name>_safedi`, a `safedi_compile` target that runs SafeDITool once over the same `srcs` and writes two outputs:
    - `<name>_safedi.safedi` — module-info artifact for cross-module consumers (carried via the rule's `SafeDIInfo` provider).
    - `<name>_safedi.swift` — combined dependency-tree + mocks + mock configuration source.
  With the manifest `scan` plans, as the SPM plugin uses, SafeDITool writes one generated `.swift` per source file that declares a root, one per source file that declares a `generateMock: true` type, one per `additionalMocksToGenerate` entry, and, when there are mocks, the shared mock configuration. `--combined-output` concatenates them into one statically-declared output instead — no hand-maintained output list regardless of how many `@Instantiable(isRoot:)` / `generateMock: true` types the module declares.
- **One set of compilation conditions.** Both targets receive the same `defines` and `copts`, so SafeDITool scans the `#if` clauses the compiler compiles. SafeDITool also sees `DEBUG` in `dbg`/`fastbuild` builds, `NDEBUG` in `opt` builds, and every `-D` passed with `--@rules_swift//swift:copt`.
- **Cross-module type resolution via `.safedi`.** The host target reaches the subproject via `safedi_deps = ["//Subproject:Subproject_safedi"]` and never re-parses its sources.
- **SafeDI consumed via `bazel_dep`.** MODULE.bazel declares
  `bazel_dep(name = "safedi", ...)`. In this repo the dep is resolved
  via `local_path_override` to the workspace root so the example
  tracks the working copy; downstream consumers would get SafeDI from
  the Bazel Central Registry instead.
- **`SafeDITool` built from this checkout.** `safedi_compile` takes
  SafeDITool from a toolchain. A SafeDI release from the Bazel Central
  Registry runs the release's prebuilt binary for the build machine;
  this example's `local_path_override` takes SafeDI from the checkout,
  whose `bazel/private/prebuilt_safeditool.bzl` names no binaries, so
  it builds `@safedi//Sources/SafeDITool:SafeDITool` from source and
  tests the working copy's tool. CI checks that the generate step ran
  that target.

## Build

```bash
cd Examples/ExampleBazelIntegration
bazelisk build //...
```

First build compiles swift-syntax + SafeDIMacros under the hood
(~few minutes). Subsequent builds are incremental.

## Bumping SafeDI

In a real downstream consumer, you'd edit `bazel_dep(name = "safedi", version = "…")`
in your `MODULE.bazel`. In *this* example, the version is effectively
whatever's checked out under `../..` (via `local_path_override`), so
no bump needed — just `git pull` the outer repo.

## How it maps to the Tuist example

| | Tuist | Bazel |
|---|---|---|
| Codegen entry point | `SafeDI.preCompileScript(module:dependencies:)` Tuist plugin helper | `safedi_swift_library` macro, which declares a `safedi_compile` rule and a `swift_library` |
| Cross-module handoff | `Subproject.safedi` in `$(BUILT_PRODUCTS_DIR)` consumed via script-phase input | `safedi_compile`'s `SafeDIInfo` provider; downstream modules list the producer's `<name>_safedi` label in `safedi_deps` |
| Input enumeration | `FileListGlob` in `Project.swift` | `glob()` in `BUILD.bazel` |
| Output enumeration | `SafeDITool scan` at `tuist generate` time → `.generated(…)` per-file entries | Single concatenated output file per module — no per-file enumeration needed |
| SafeDITool acquisition | `tuist install` pulls via SafeDI's `prebuilt` trait | A toolchain: the release's prebuilt binary, or, for this example's `local_path_override`, built from source by Bazel |
| Generated code location | `$(DERIVED_FILE_DIR)` (Xcode build sandbox) | `bazel-bin/…` (Bazel action sandbox) |

Both end up at the same shape: generated Swift is a build artifact,
never in the source tree; cross-module type info flows through a
`.safedi` artifact.

## Why one combined `.swift` file?

Bazel rule outputs must be known at analysis time (Starlark can't run
subprocesses or read file contents then). SafeDI's output *set*
depends on what's inside each Swift file — how many
`@Instantiable(isRoot:)` / `generateMock: true` declarations it
finds — which analysis can't see. Hand-maintaining the output list
in `BUILD.bazel` would force every author to update their build file
on every annotation change, so `safedi_compile` uses SafeDITool's
`--combined-output` mode to emit a single declared output regardless
of source contents. The concatenated file is still valid Swift
(SafeDI's generated files are all top-level declarations) and
downstream `swift_library.srcs` treats it like any other source.
