# Example Tuist Integration

This example demonstrates wiring SafeDI into a multi-target project generated
by [Tuist](https://tuist.dev). It is a port of
[`ExampleMultiProjectIntegration`](../ExampleMultiProjectIntegration) with one
architecturally meaningful difference: the host app and the `Subproject`
framework are **compiled separately**, and the cross-module dependency graph
is passed as a `.safedi` module-info artifact rather than by pointing the host
scanner at the subproject's sources.

The source code of both targets (types, mocks, previews) is byte-for-byte the
same as `ExampleMultiProjectIntegration`; only the project structure differs.

## Copying this into your own project

This example is designed to be lifted as a template:

- `Project.swift` and `Scripts/generate-safedi.sh` contain **no
  hardcoded Swift file lists** — `find` (in the script) and
  `FileListGlob` (in the manifest) enumerate sources automatically.
- The set of generated output filenames is **not hardcoded either** —
  `SafeDITool scan` decides them from the `@Instantiable` declarations
  it finds. `Project.swift` enumerates the populated `Generated/`
  directory at `tuist generate` time to compute the script phase's
  `outputPaths`, so new `@Instantiable(isRoot:)` /
  `@Instantiable(generateMock: true)` declarations produce new files
  without any manifest edits.
- **No generated files are committed.** `Project.swift` runs the
  codegen script during `tuist generate`, which populates
  `ExampleTuistIntegration/Generated/` before Tuist evaluates the
  source glob. The same script re-runs as an Xcode build phase on
  every build. `Generated/` is `.gitignore`d.
- SafeDITool is fetched as the published artifact bundle. SafeDI's
  own Package.swift declares the `.binaryTarget(url:checksum:)` for
  its `prebuilt` trait, so `tuist install` pulls the bundle as a side
  effect of resolving SafeDI — nothing extra is declared here, no
  "build from source" step for consumers.

When cloning into a new project the edits you're expected to make are:

| Where | What |
|---|---|
| `Project.swift` | target names, bundle IDs, deployment targets, module directory names |
| `Scripts/generate-safedi.sh` | the two `case` labels (`subproject` / `host`) if your module names differ, or add more branches for additional targets |
| `Tuist/Package.swift` | bump SafeDI version (single source of truth — the artifact bundle follows automatically) |

## Why not use the `SafeDIGenerator` SPM plugin?

SafeDI's build-tool plugin collects every `.swift` file from the target plus
every `.swift` file from its recursive source dependencies, then hands the
whole list to `SafeDITool` in one pass. That works, but it also means every
target re-parses its dependencies' sources on every build and that no target
"publishes" its own SafeDI-visible surface as a consumable artifact.

`SafeDITool` already supports a different workflow: pass `--module-info-output
Module.safedi` when you run `generate` against a leaf module, then pass
`--dependent-module-info-file-path` (a CSV of those `.safedi` paths) when you
run `generate` against a downstream module. This example wires the tool up
that way directly from Xcode build-phase scripts — no SPM plugin involved —
which is easier to do under Tuist than under plain SPM because Tuist emits
real Xcode targets whose script phases can declare arbitrary
input/output paths.

## Prerequisites

| Tool | Notes |
|------|-------|
| macOS with Xcode 26 | Matches the rest of SafeDI's CI. |
| [Tuist](https://tuist.dev) 4.x | Install via [mise](https://mise.jdx.dev). Tuist no longer publishes a Homebrew formula. |
| Swift 6.3 toolchain | Ships with Xcode 26. |

### Installing Tuist

This example pins Tuist to the same concrete version CI installs
(`4.183.0`). The reproducible install path is via
[mise](https://mise.jdx.dev):

```bash
# Install mise if you don't have it.
curl -fsSL https://mise.run | sh

# Install the pinned Tuist version.
mise install tuist@4.183.0
mise use -g tuist@4.183.0

# Verify.
tuist version
```

If you want to track a newer Tuist release locally, bump the pinned
version in `.github/workflows/ci.yml` (`spm-tuist-integration` job) at
the same time so CI and local setup stay aligned.

## First-time setup

From this directory (`Examples/ExampleTuistIntegration`):

```bash
# 1. Resolve SPM dependencies — pulls SafeDI and (via SafeDI's
#    default `prebuilt` trait) the SafeDITool artifact bundle.
tuist install

# 2. Generate the Xcode project and workspace. This also runs the
#    codegen script once to populate Generated/ before Tuist's source
#    glob is evaluated. Re-run any time sources change.
tuist generate
```

`tuist generate` opens the generated workspace in Xcode. Build and run the
`ExampleTuistIntegration` scheme.

Re-run `tuist install` when bumping SafeDI; `tuist generate` otherwise.

Both the SafeDI runtime library and the SafeDITool CLI are consumed
through a single `.package(url:from:)` entry in `Tuist/Package.swift`.
Targets in `Project.swift` depend on `.external(name: "SafeDI")`;
`Scripts/generate-safedi.sh` reads the SafeDITool binary SPM pulled
down as a side effect of SafeDI's `prebuilt` trait chain. One version
pin, one dependency graph.

## How the build wiring works

`Scripts/generate-safedi.sh` is invoked in two places (both use the
same code path — the script takes a `subproject` / `host` / `all`
argument that decides which module(s) to generate for):

- As two pre-compile Xcode script phases (one per target), set up by
  Tuist, so edits during an iteration cycle are picked up on the next
  `xcodebuild` without needing `tuist generate`.
- During `tuist generate` itself — `Project.swift` shells out before
  evaluating its source globs, so `Generated/` (which is `.gitignore`d)
  exists on a fresh checkout by the time Tuist bakes a source list
  into the pbxproj.

Each script run invokes `SafeDITool scan` followed by `SafeDITool
generate` — the same two-step flow the `SafeDIGenerator` SPM plugin
uses — so manifest and cache files land in `$DERIVED_FILE_DIR` (or a
`.build/` scratch dir when running standalone) rather than inside
committed source directories.

### `Subproject` target

1. Runs `SafeDITool generate` with `--module-info-output
   $BUILT_PRODUCTS_DIR/SafeDI/Subproject.safedi`.
2. Produces no Swift output — the subproject has no
   `@Instantiable(isRoot: true)` and no `@Instantiable(generateMock: true)`
   types, so the dependency tree and mock manifests are empty.
3. The `.safedi` artifact encodes the subproject's `@Instantiable` surface
   (including `User`, `InMemoryStorage`, `NoteStorage`, `StringStorage`,
   `DefaultUserService`) as JSON for the host to consume.

### `ExampleTuistIntegration` (host app) target

1. Xcode's target dependency graph guarantees `Subproject` builds first, so
   `Subproject.safedi` exists before this script runs.
2. Runs `SafeDITool generate` with `--dependent-module-info-file-path` pointed
   at a CSV containing `Subproject.safedi`. The host never re-parses
   subproject sources.
3. Emits the root's `+SafeDI.swift`, the mocks' `+SafeDIMock.swift`, and the
   shared `SafeDIMockConfiguration.swift` into `ExampleTuistIntegration/Generated/`.
   The specific filenames follow SafeDI's
   [output-naming rules](../../Sources/SafeDICore/Utilities/OutputFileNaming.swift)
   — no manifest edit required when adding new roots or mocks.

### Script-phase incremental builds

Script `inputPaths` are glob patterns that Tuist expands at
`tuist generate` time into literal file lists. `outputPaths` for the
host target enumerate the concrete generated `.swift` files — Project.swift
reads them off disk after running the codegen, so Xcode's dep-analysis
tracks each output individually. The generated files flow into the
compile phase via the target's source glob.

Adding or removing a Swift source file (whether a normal source or a
new `@Instantiable` type that triggers new generated output) is a
`tuist generate` away from being picked up by the manifest.

## CI

A `spm-tuist-integration` job in `.github/workflows/ci.yml` performs the
equivalent of the first-time setup steps above: it installs Tuist via
`mise` (pinned to `4.183.0`), runs `tuist install` and `tuist generate`,
then builds the generated workspace with `xcodebuild`.
