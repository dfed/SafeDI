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
| [Tuist](https://tuist.dev) 4.x | Install via [mise](https://mise.jdx.dev). Tuist no longer publishes a Homebrew formula, and the old `tuist.dev/install.sh` shortcut now routes through mise. |
| Swift 6.3 toolchain | Ships with Xcode 26; used to build `SafeDITool` from source. |

### Installing Tuist

This example is pinned against Tuist 4.x. The reproducible install path
(matching what CI runs) is via [mise](https://mise.jdx.dev):

```bash
# Install mise if you don't have it.
curl -fsSL https://mise.run | sh

# Install Tuist.
mise install tuist@latest
mise use -g tuist@latest

# Verify.
tuist version
```

Alternatively, if you already manage developer tooling with `asdf`,
`mise` understands asdf plugin configs, so `tuist@latest` resolves the
same.

## First-time setup

From this directory (`Examples/ExampleTuistIntegration`):

```bash
# 1. Build SafeDITool from source. The build-phase script does this
#    automatically on first build, but doing it up front gives a cleaner
#    first Xcode build log.
(cd ../.. && swift build -c release --product SafeDITool)

# 2. Generate the Xcode project and workspace.
tuist generate
```

`tuist generate` opens the generated workspace in Xcode. Build and run the
`ExampleTuistIntegration` scheme.

To regenerate the project after editing `Project.swift`, re-run
`tuist generate`.

SafeDI is consumed as a local SPM package via `Project.packages` rather than
through `Tuist/Package.swift`. Tuist's SPM integration hit wall with SafeDI's
trait-gated internal targets (`SafeDICore`, `SafeDIMacros`, `SafeDITool`,
`SafeDIToolBinary`); going through Xcode's native SPM client sidesteps that.

## How the build wiring works

Two pre-compile script phases, one per target, both invoking
`Scripts/generate-safedi.sh`. The script invokes `SafeDITool scan` followed
by `SafeDITool generate` — the same two-step flow the `SafeDIGenerator` SPM
plugin uses — so manifest and cache files land in `$DERIVED_FILE_DIR` rather
than inside committed source directories.

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
3. Emits four Swift files into `ExampleTuistIntegration/Generated/`:
   - `NotesApp+SafeDI.swift` — dependency tree wiring for the root.
   - `LoggedInView+SafeDIMock.swift` — mock method for previews.
   - `NameEntryView+SafeDIMock.swift` — mock method for previews.
   - `SafeDIMockConfiguration.swift` — shared `SafeDIOverrides` struct.

The `Generated/*.swift` files are committed as empty stubs so Tuist's source
glob resolves them at project-generation time. Each build overwrites them.

### Script-phase incremental builds

The two script phases declare their `inputPaths` and `outputPaths` in
`Project.swift` explicitly (Xcode's script phases don't support globs here).
Adding, removing, or renaming a type means updating those lists in
`Project.swift` and — for a generated output file — committing a new stub
under `Generated/`.

## CI

A `spm-tuist-integration` job in `.github/workflows/ci.yml` performs the
equivalent of the first-time setup steps above: it installs Tuist via
Homebrew, builds `SafeDITool`, runs `tuist generate`, then builds the
generated workspace with `xcodebuild`.
