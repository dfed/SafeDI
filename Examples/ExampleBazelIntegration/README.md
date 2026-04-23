# Example Bazel Integration

A Bazel port of [`ExampleTuistIntegration`](../ExampleTuistIntegration),
demonstrating SafeDI's cross-module `.safedi` artifact handoff in a
Bazel-native way. The Swift source code (types, mocks, previews) is
byte-for-byte identical to the Tuist example — the differences are
entirely in the build system.

**Supported host:** macOS arm64 only. Extending to `x86_64` or Linux
is a one-line variant addition in
[`bazel/safeditool_extension.bzl`](bazel/safeditool_extension.bzl);
the rules themselves are platform-agnostic.

## What it demonstrates

- **Two `swift_library` targets** (`//Subproject:Subproject`,
  `//ExampleBazelIntegration:ExampleBazelIntegration`) that compile
  separately.
- **Custom Starlark rules** in [`bazel/safedi.bzl`](bazel/safedi.bzl):
  - `safedi_module_info(srcs)` emits a module's `.safedi` artifact for
    downstream consumers.
  - `safedi_generate(srcs, module_infos)` reads upstream `.safedi`
    files for cross-module types and emits **one** combined
    `<rule_name>.swift` — SafeDI's per-root / per-mock file splits
    happen in a scratch directory and get concatenated into a single
    declared output. That's what makes the rule Bazel-idiomatic:
    `outs` doesn't need a hand-maintained list, because every
    invocation has the same single-file output shape regardless of
    how many `@Instantiable(isRoot:)` / `generateMock: true` types the
    module declares.
- **Cross-module type resolution via `.safedi`.** The host target
  reads `//Subproject:Subproject_safedi`'s output as `module_infos`
  and never re-parses the subproject's sources.
- **`SafeDITool` as a content-addressed artifact.** A
  [module extension](bazel/safeditool_extension.bzl) downloads
  `SafeDITool.artifactbundle.zip` from GitHub Releases with a pinned
  SHA-256. Content-addressed caching via `http_archive`.
- **SafeDI runtime consumed via SPM-in-Bazel.** MODULE.bazel's
  `swift_deps` extension (`rules_swift_package_manager`) resolves
  `Package.swift` and exposes `@swiftpkg_safedi//:SafeDI` as a
  `swift_library` dep.

## Build

```bash
cd Examples/ExampleBazelIntegration
bazelisk build //...
```

First build is ~3 minutes (it compiles swift-syntax + SafeDIMacros
under the hood). Subsequent builds are incremental.

## Bumping SafeDI

- Edit `Package.swift` — the version requirement.
- Run `swift package resolve` to refresh `Package.resolved`.
- Edit `bazel/safeditool_extension.bzl` — the `_SAFEDI_VERSION` and
  `_SAFEDI_CHECKSUM` constants, so the binary artifact bundle matches.

(`rules_swift_package_manager` re-reads `Package.resolved`
automatically on the next Bazel invocation.)

## How it maps to the Tuist example

| | Tuist | Bazel |
|---|---|---|
| Cross-module handoff | `Subproject.safedi` in `$(BUILT_PRODUCTS_DIR)` consumed via script-phase input | `safedi_module_info` output consumed via `safedi_generate.module_infos` |
| Input enumeration | `FileListGlob` in `Project.swift` | `glob()` in `BUILD.bazel` |
| Output enumeration | `SafeDITool scan` at `tuist generate` time → `.generated(…)` per-file entries | Single concatenated output file per `safedi_generate` target — no per-file enumeration needed |
| SafeDITool acquisition | `tuist install` pulls via SafeDI's `prebuilt` trait | `http_archive` via module extension, SHA-pinned |
| Generated code location | `$(DERIVED_FILE_DIR)` (Xcode build sandbox) | `bazel-bin/…` (Bazel action sandbox) |

Both end up at the same shape: generated Swift is a build artifact,
never in the source tree; cross-module type info flows through a
`.safedi` artifact; tool provenance is content-addressed.

## Why one combined `.swift` file?

Bazel rule outputs must be known at analysis time (Starlark can't run
subprocesses or read file contents then). SafeDI's output *set*
depends on what's inside each Swift file — how many
`@Instantiable(isRoot:)` / `generateMock: true` declarations it
finds — which analysis can't see. Listing outputs manually in
`BUILD.bazel` would regress the "no hardcoded filenames" property we
cared about for Tuist, so the rule instead writes every per-root /
per-mock file SafeDITool emits into a scratch directory and stitches
them into a single declared output. The concatenated file is still
valid Swift (SafeDI's generated files are all top-level declarations)
and downstream `swift_library.srcs` treats it like any other source.

## Why `rules_swift_package_manager`?

Consuming an SPM-native package like SafeDI in Bazel otherwise
requires hand-writing Bazel targets for SafeDI + SwiftSyntax, plus
wiring `swift_compiler_plugin` for the macro. The
`rules_swift_package_manager` extension does that translation from
`Package.swift` + `Package.resolved` automatically.
