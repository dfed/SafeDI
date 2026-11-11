# Example Bazel Integration

A Bazel port of `ExampleTuistIntegration`, demonstrating SafeDI's
cross-module `.safedi` artifact handoff in a Bazel-native way. The
Swift source code (types, mocks, previews) is the Tuist example's,
except for the `Models` module, `Subproject`'s seam `WindowTitle`, the
`TitleFormatter` it builds, and what uses it, `NoteStorage`'s
`NoteFormatter`, `EventLogger`, which also checks `NDEBUG` and logs its
own example's name, and a comment in `NameEntryView` on how a mismatch
is reported. The Tuist example, built with SafeDI's latest release,
adopts the seam once a release ships seams.

**Supported host:** macOS arm64 only (matches the
[`rules_apple`](https://github.com/bazelbuild/rules_apple) macOS
toolchain). The SafeDI rules themselves are platform-agnostic.

## What it demonstrates

- **Three `swift_library` targets** (`//Models:Models`,
  `//Subproject:Subproject`,
  `//ExampleBazelIntegration:ExampleBazelIntegration`) that compile
  separately.
- **Each module lists the modules it depends on directly.** `Subproject`
  imports `Models`, so its `safedi_deps` lists `Models_safedi`. The app
  imports only `Subproject`, so its `safedi_deps` lists only
  `Subproject_safedi`. The app's root builds `NoteStorage`, which builds
  `Models`' `NoteFormatter`, and that works because `safedi_swift_library`
  collects the modules beneath the ones a module lists, and SafeDI reads
  every one of them that declares a type a dependency tree of the module
  needs. A mock asks for none: it builds a deeper type only if a tree of
  its module uses that module or the module is listed.
- **A seam reaches across a `package` type.** `Subproject`'s seam
  `WindowTitle` (`generateDependencyTree: true`) receives `Models`'
  `package` type `NoteTheme` only if available, so the initializer
  `Subproject` generates for it is `public` without `theme` and `package`
  with it. SafeDI counts a type it reads no declaration of as `public`, so
  without `Models_safedi` in `Subproject`'s `safedi_deps` the `public`
  initializer would take a `package` type and fail to compile.
  `Subproject`'s `.safedi` also carries what `WindowTitle`'s signature
  needs of `Models`. All three modules set the same `package_name`.
- **`safedi_swift_library` macro** — `load("@safedi//bazel:safedi.bzl", "safedi_swift_library")`. It takes a `swift_library`'s attributes and declares two targets from them:
  - `<name>`, the `swift_library`, which compiles `srcs` together with the generated code.
  - `<name>_safedi`, a `safedi_compile` target that runs SafeDITool once over the same `srcs` and writes two outputs:
    - `<name>_safedi.safedi` — module-info artifact for cross-module consumers (carried via the rule's `SafeDIInfo` provider).
    - `<name>_safedi.swift` — combined dependency-tree + mocks + mock configuration source.
  With the manifest `scan` plans, as the SPM plugin uses, SafeDITool writes one generated `.swift` per source file that declares a root, one per source file that declares a `generateMock: true` type, one per `additionalMocksToGenerate` entry, and, when there are mocks, the shared mock configuration. `--combined-output` concatenates them into one statically-declared output instead — no hand-maintained output list regardless of how many `@Instantiable(isRoot:)` / `generateMock: true` types the module declares.
- **One set of compilation conditions.** Both targets receive the same `defines` and `copts`, so SafeDITool scans the `#if` clauses the compiler compiles. SafeDITool also sees `DEBUG` in `dbg`/`fastbuild` builds, `NDEBUG` in `opt` builds, and every `-D` passed with `--@rules_swift//swift:copt`.
- **Cross-module type resolution via `.safedi`.** The host target reaches the subproject via `safedi_deps = ["//Subproject:Subproject_safedi"]` and `Models` through it, and never re-parses their sources.
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
| Cross-module handoff | `Subproject.safedi` in `$(BUILT_PRODUCTS_DIR)` consumed via script-phase input; a target that declares a root names every target beneath it in `dependencies:`, and one that declares a seam each target whose types its tree builds | `safedi_compile`'s `SafeDIInfo` provider; downstream modules list the producer's `<name>_safedi` label in `safedi_deps`, and the rule collects the modules beneath it |
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
