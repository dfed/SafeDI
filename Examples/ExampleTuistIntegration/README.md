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
  `Project.swift` runs `SafeDITool scan` at `tuist generate` time to
  ask the tool which Swift files it would emit, and registers each one
  via `.generated("$(DERIVED_FILE_DIR)/...")` so Xcode adds it to the
  compile phase without expecting the file to exist yet.
- **Generated code is a build artifact, never in the source tree.**
  The pre-compile script phase writes to `$(DERIVED_FILE_DIR)` during
  every `xcodebuild` run. Nothing is committed, nothing is
  `.gitignore`d — there's just no `Generated/` in the source tree at
  all.
- SafeDITool is fetched as the published artifact bundle. SafeDI's
  own `Package.swift` declares the `.binaryTarget(url:checksum:)` for
  its `prebuilt` trait, so `tuist install` pulls the bundle as a side
  effect of resolving SafeDI — no "build from source" step for
  consumers.

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

# 2. Generate the Xcode project and workspace.
tuist generate
```

`tuist generate` opens the generated workspace in Xcode. Build and run the
`ExampleTuistIntegration` scheme.

Re-run `tuist install` when bumping SafeDI; `tuist generate` after
adding/removing Swift files or `@Instantiable` declarations so the
source glob and `.generated(…)` output list refresh.

Both the SafeDI runtime library and the SafeDITool CLI are consumed
through a single `.package(url:from:)` entry in `Tuist/Package.swift`.
Targets in `Project.swift` depend on `.external(name: "SafeDI")`;
`Scripts/generate-safedi.sh` reads the SafeDITool binary SPM pulled
down as a side effect of SafeDI's `prebuilt` trait chain. One version
pin, one dependency graph.

## How the build wiring works

Each target has a pre-compile Xcode script phase that invokes
`Scripts/generate-safedi.sh <subproject|host>`. The script runs
`SafeDITool scan` followed by `SafeDITool generate` — the same two-step
flow the `SafeDIGenerator` SPM plugin uses. Manifest files land in
`$(DERIVED_FILE_DIR)`, the generated `.swift` files land there too.

`Project.swift` also runs `SafeDITool scan` once at `tuist generate`
time (for the host module only) so it can register each expected
output via `.generated("$(DERIVED_FILE_DIR)/...")`. That call is a
read-only query — it writes only to a scratch dir under `.build/`; the
actual code generation happens at `xcodebuild` time.

### `Subproject` target

1. Runs `SafeDITool generate` with `--module-info-output
   $(BUILT_PRODUCTS_DIR)/SafeDI/Subproject.safedi`.
2. Produces no Swift output today — the subproject has no
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
   shared `SafeDIMockConfiguration.swift` into `$(DERIVED_FILE_DIR)`.
   Specific filenames follow SafeDI's
   [output-naming rules](../../Sources/SafeDICore/Utilities/OutputFileNaming.swift).

## CI

A `spm-tuist-integration` job in `.github/workflows/ci.yml` performs the
equivalent of the first-time setup steps above: it installs Tuist via
`mise` (pinned to `4.183.0`), runs `tuist install` and `tuist generate`,
then builds the generated workspace with `xcodebuild`.
