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

## How it's wired

All SafeDI-specific scaffolding lives in the
[`SafeDITuist` Tuist plugin](../../TuistPlugins/SafeDITuist) shipped from this
repo. `Tuist.swift` declares the plugin; `Project.swift` calls two helpers:

- `SafeDI.preCompileScript(module:dependents:generatedOutputs:)` — returns a
  `TargetScript.pre` that runs `SafeDITool scan` + `generate` against one
  module at build time. Every call writes
  `$(BUILT_PRODUCTS_DIR)/SafeDI/<module>.safedi` for downstream consumers;
  `dependents:` lists upstream modules whose `.safedi` to feed in via
  `--dependent-module-info-file-path`.
- `SafeDI.generatedSources(for:)` — runs `SafeDITool scan` at `tuist generate`
  time and returns `[SourceFileGlob]` of `.generated(...)` entries pointing
  at `$(DERIVED_FILE_DIR)`. Add to the target's `sources` so Xcode wires the
  build-time outputs into the compile phase before they exist.

That's the entire integration surface. The plugin internally locates the
`SafeDIToolBinary` artifact bundle (resolved by `tuist install` via
`Tuist/Package.swift`), runs the scan + generate flow, and emits the
appropriate inputs/outputs for Xcode's incremental dependency analysis.

## Copying this into your own project

1. Add the plugin to your `Tuist.swift`:

   ```swift
   let tuist = Tuist(
       project: .tuist(
           plugins: [
               .git(
                   url: "https://github.com/dfed/SafeDI",
                   tag: "<version>",
                   directory: "TuistPlugins/SafeDITuist",
               ),
           ],
       ),
   )
   ```

2. In `Tuist/Package.swift`, depend on SafeDI so its runtime library and
   `SafeDIToolBinary` artifact bundle are resolved:

   ```swift
   .package(url: "https://github.com/dfed/SafeDI.git", from: "<version>"),
   ```

3. In `Project.swift`, `import SafeDITuist` and call the helpers from each
   target's `scripts:` and `sources:`. See this example's `Project.swift`
   for the full shape.

4. Each target depending on SafeDI's runtime library adds
   `.external(name: "SafeDI")` to its `dependencies`.

Adding/removing `.swift` files: just `tuist generate`. Bumping SafeDI: edit
the version in `Tuist/Package.swift`. Both the runtime library and the
`SafeDITool` binary the plugin invokes follow from that single pin.

## Why not use the `SafeDIGenerator` SPM plugin?

SafeDI's build-tool plugin collects every `.swift` file from the target plus
every `.swift` file from its recursive source dependencies, then hands the
whole list to `SafeDITool` in one pass. That works, but it also means every
target re-parses its dependencies' sources on every build and that no target
"publishes" its own SafeDI-visible surface as a consumable artifact.

`SafeDITool` already supports a different workflow: pass `--module-info-output
Module.safedi` when you run `generate` against a leaf module, then pass
`--dependent-module-info-file-path` (a CSV of those `.safedi` paths) when you
run `generate` against a downstream module. The `SafeDITuist` plugin wires
`SafeDITool` up that way directly from Xcode build-phase scripts — no SPM
plugin involved — which is easier to do under Tuist than under plain SPM
because Tuist emits real Xcode targets whose script phases can declare
arbitrary input/output paths.

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
# 1. Resolve SPM dependencies and Tuist plugins. SPM pulls SafeDI and
#    (via its `prebuilt` trait) the SafeDITool artifact bundle. Tuist
#    fetches the `SafeDITuist` plugin manifest.
tuist install

# 2. Generate the Xcode project and workspace. The SafeDITuist plugin
#    runs `SafeDITool scan` for the host module to register each
#    expected output as a `.generated(...)` source.
tuist generate
```

`tuist generate` opens the generated workspace in Xcode. Build and run the
`ExampleTuistIntegration` scheme.

Re-run `tuist install` when bumping SafeDI; `tuist generate` after
adding/removing Swift files or `@Instantiable` declarations so the
source glob and `.generated(…)` output list refresh.

## How the build wiring works (under the hood)

The plugin's `preCompileScript` helper emits a `TargetScript.pre` whose
inline shell:

1. Locates `SafeDITool` under
   `$(SRCROOT)/Tuist/.build/artifacts/safedi/SafeDIToolBinary/...`
   (resolved by `tuist install`).
2. Globs the module's `.swift` sources into a CSV.
3. For each `dependents:` entry, builds a CSV of
   `$(BUILT_PRODUCTS_DIR)/SafeDI/<name>.safedi` paths and feeds them to
   `--dependent-module-info-file-path`.
4. Runs `SafeDITool scan` then `SafeDITool generate
   --module-info-output $(BUILT_PRODUCTS_DIR)/SafeDI/<module>.safedi`,
   writing generated Swift into `$(DERIVED_FILE_DIR)`.

Manifest-time, `SafeDI.generatedSources(for:)` runs the same `scan` to
discover output filenames so `Project.swift` can register each as a
`.generated("$(DERIVED_FILE_DIR)/...")` source. That call writes only
to a scratch dir under `.build/`; the real code generation happens at
`xcodebuild` time.

### `Subproject` target

`SafeDI.preCompileScript(module: "Subproject")` — emits
`$(BUILT_PRODUCTS_DIR)/SafeDI/Subproject.safedi` (the JSON `@Instantiable`
surface for `User`, `InMemoryStorage`, `NoteStorage`, `StringStorage`,
`DefaultUserService`). Produces no generated Swift today — the subproject
has no `@Instantiable(isRoot: true)` and no
`@Instantiable(generateMock: true)` types.

### `ExampleTuistIntegration` (host app) target

`SafeDI.preCompileScript(module: "ExampleTuistIntegration", dependents: ["Subproject"], generatedOutputs: ...)` — Xcode's target
dependency graph guarantees `Subproject` builds first, so
`Subproject.safedi` exists. The host reads it via
`--dependent-module-info-file-path` (never re-parsing subproject sources)
and emits its root's `+SafeDI.swift`, the mocks' `+SafeDIMock.swift`, and
the shared `SafeDIMockConfiguration.swift` into `$(DERIVED_FILE_DIR)`.
Filenames follow SafeDI's
[output-naming rules](../../Sources/SafeDICore/Utilities/OutputFileNaming.swift).
The host also emits its own `ExampleTuistIntegration.safedi` for any
future downstream consumer.

## CI

A `spm-tuist-integration` job in `.github/workflows/ci.yml` performs the
equivalent of the first-time setup steps above: it installs Tuist via
`mise` (pinned to `4.183.0`), runs `tuist install` and `tuist generate`,
then builds the generated workspace with `xcodebuild`.
