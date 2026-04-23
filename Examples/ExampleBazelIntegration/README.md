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
- **SafeDI rules from the SafeDI repo** — `load("@safedi//bazel:safedi.bzl", ...)`:
  - `safedi_module_info(srcs)` emits a module's `.safedi` artifact
    for downstream consumers.
  - `safedi_generate(srcs, module_infos)` reads upstream `.safedi`
    files for cross-module types and emits **one** combined
    `<rule_name>.swift`. SafeDITool's per-root / per-mock file splits
    are concatenated via the tool's `--combined-output` mode into a
    single declared output — `outs` doesn't need a hand-maintained
    list regardless of how many `@Instantiable(isRoot:)` /
    `generateMock: true` types the module declares.
- **Cross-module type resolution via `.safedi`.** The host target
  reads `//Subproject:Subproject_safedi`'s output as `module_infos`
  and never re-parses the subproject's sources.
- **SafeDI consumed via `bazel_dep`.** MODULE.bazel declares
  `bazel_dep(name = "safedi", ...)`. In this repo the dep is resolved
  via `local_path_override` to the workspace root so the example
  tracks the working copy; downstream consumers would get SafeDI from
  the Bazel Central Registry instead.
- **`SafeDITool` built from source by Bazel.** No prebuilt artifact
  fetching — the tool is just another `swift_binary` target
  (`@safedi//Sources/SafeDITool:SafeDITool`). Cached across runs.

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
| Cross-module handoff | `Subproject.safedi` in `$(BUILT_PRODUCTS_DIR)` consumed via script-phase input | `safedi_module_info` output consumed via `safedi_generate.module_infos` |
| Input enumeration | `FileListGlob` in `Project.swift` | `glob()` in `BUILD.bazel` |
| Output enumeration | `SafeDITool scan` at `tuist generate` time → `.generated(…)` per-file entries | Single concatenated output file per `safedi_generate` target — no per-file enumeration needed |
| SafeDITool acquisition | `tuist install` pulls via SafeDI's `prebuilt` trait | Built from source by Bazel; cached across runs |
| Generated code location | `$(DERIVED_FILE_DIR)` (Xcode build sandbox) | `bazel-bin/…` (Bazel action sandbox) |

Both end up at the same shape: generated Swift is a build artifact,
never in the source tree; cross-module type info flows through a
`.safedi` artifact.

## Why one combined `.swift` file?

Bazel rule outputs must be known at analysis time (Starlark can't run
subprocesses or read file contents then). SafeDI's output *set*
depends on what's inside each Swift file — how many
`@Instantiable(isRoot:)` / `generateMock: true` declarations it
finds — which analysis can't see. Listing outputs manually in
`BUILD.bazel` would regress the "no hardcoded filenames" property we
cared about for Tuist, so `safedi_generate` uses SafeDITool's
`--combined-output` mode to emit a single declared output regardless
of source contents. The concatenated file is still valid Swift
(SafeDI's generated files are all top-level declarations) and
downstream `swift_library.srcs` treats it like any other source.
