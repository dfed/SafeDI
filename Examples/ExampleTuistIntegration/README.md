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
| `Project.swift` | target names, bundle IDs, deployment targets, module directory names, and the `<module-name> [<dependent-module-name>...]` arguments passed to `Scripts/generate-safedi.sh` from each target's pre-compile script |
| `Scripts/generate-safedi.sh` | nothing — the script is module-generic; module name and dependents come in as positional arguments |
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
| macOS with Xcode 26.4 | Matches the rest of SafeDI's CI. |
| [Tuist](https://tuist.dev) 4.x | Install via [mise](https://mise.jdx.dev). Tuist no longer publishes a Homebrew formula. |
| Swift 6.3 toolchain | Ships with Xcode 26.4 |

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
`Scripts/generate-safedi.sh <module-name> [<dependent-module-name>...]`.
The script runs `SafeDITool scan` followed by `SafeDITool generate` —
the same two-step flow the `SafeDIGenerator` SPM plugin uses. Every
invocation writes `$(BUILT_PRODUCTS_DIR)/SafeDI/<module-name>.safedi`
(via `--module-info-output`) so any downstream module can consume it;
modules with no consumers just ignore the artifact. Each
`<dependent-module-name>` resolves to that same shared directory and
is passed through to `--dependent-module-info-file-path`. Generated
`.swift` files land in `$(DERIVED_FILE_DIR)`.

`Project.swift` also runs `SafeDITool scan` once at `tuist generate`
time (for the host module only) so it can register each expected
output via `.generated("$(DERIVED_FILE_DIR)/...")`. That call is a
read-only query — it writes only to a scratch dir under `.build/`; the
actual code generation happens at `xcodebuild` time.

### `Subproject` target

Pre-compile phase runs `generate-safedi.sh Subproject`.

1. Emits `$(BUILT_PRODUCTS_DIR)/SafeDI/Subproject.safedi` — the JSON
   `@Instantiable` surface (`User`, `InMemoryStorage`, `NoteStorage`,
   `StringStorage`, `DefaultUserService`) for the host to consume.
2. Produces no generated Swift today — the subproject has no
   `@Instantiable(isRoot: true)` and no `@Instantiable(generateMock: true)`
   types, so the dependency tree and mock manifests are empty.

### `ExampleTuistIntegration` (host app) target

Pre-compile phase runs `generate-safedi.sh ExampleTuistIntegration Subproject`.

1. Xcode's target dependency graph guarantees `Subproject` builds first, so
   `Subproject.safedi` exists before this script runs.
2. Reads `Subproject.safedi` via `--dependent-module-info-file-path` so
   `SafeDITool generate` can resolve cross-module types. The host never
   re-parses subproject sources.
3. Emits the root's `+SafeDI.swift`, the mocks' `+SafeDIMock.swift`, and the
   shared `SafeDIMockConfiguration.swift` into `$(DERIVED_FILE_DIR)`.
   Specific filenames follow SafeDI's
   [output-naming rules](../../Sources/SafeDICore/Utilities/OutputFileNaming.swift).
4. Also emits its own `ExampleTuistIntegration.safedi` for any future
   downstream consumer. With no current consumer the artifact is
   tracked only so Xcode's incremental dependency analysis sees it.

## CI

A `spm-tuist-integration` job in `.github/workflows/ci.yml` performs the
equivalent of the first-time setup steps above: it installs Tuist via
`mise` (pinned to `4.183.0`), runs `tuist install` and `tuist generate`,
then builds the generated workspace with `xcodebuild`.
