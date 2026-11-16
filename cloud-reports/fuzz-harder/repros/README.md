# Fill of a place an outer seam passes up reads the root's value for the inner seam's pass-through

Run each with `Scripts/multi-module-repro.sh cloud-reports/fuzz-harder/repros/<dir> Feature App`.

- `c2`: Inner (seam) builds Detail, which receives `logger` and instantiates hole `api: any Api`. Outer (seam)
  instantiates `logger` and calls Inner, passing the hole up. App fills it with LiveApi, which receives `logger`.
  Generated App code reads `logger` from the root's scope: `cannot find 'logger' in scope`.
- `c3`: c2 plus Root instantiating its own `logger`: compiles, LiveApi gets Root's logger; inline gets Outer's
  (`probeResult()` false on the seam build, true inline).
- `d`: two levels of pass-up (Outer -> Middle -> Inner), a required `logger` and an only-if-available `tag`:
  both read from Root. 
- `c4` (control): Detail does not receive `logger`, so it is no pass-through of Inner: the tool reports
  boundByPassingUpSeam correctly.

Inner's `detail_Values` already carries the memo (`values.logger`); the generated fill reads the caller's
declaration, which for a passed-up place is the root's, not the passing-up seam's.

## F3: a hole fill passes `nil` where inline passes the value (seeds 1815, 4668)
- `f3`: Seam (Feature) builds `Reader`, which receives `tag: LazilyInstantiated<Tag>?` only if available, and `service: any Service`. The hole `Impl` (App) receives `tag: Tag?` only if available. Root (App) declares `tag: LazilyInstantiated<Tag>`. Generated fill: `Impl(tag: nil)`.
- `f3i`: the same without `generateDependencyTree`, built inline. Generated: `Impl(tag: tag.instance)`.
- `f3b`: `f3` without `Reader`. Generated: `Impl(tag: tag.instance)`. So the second form of the label inside the seam's tree is what makes the fill pass `nil`. Moving `Impl` into Feature (the visible build) rejects the graph: "receives `tag` in two forms".
Run: `zsh Scripts/repro-release.sh <dir> Feature App` (or `Scripts/multi-module-repro.sh`) on main 58cbc93.

## F4: SwiftPM and module-info (Bazel/Tuist) mocks differ (seeds 4749, 4867) — documented behavior
`f4`: four modules. Base: `ChainLeaf` receives `chainToken: ChainToken?` only if available. Core: `ChainBase` builds `ChainLeaf`. Session: `ChainLink` builds `ChainBase`. Feature: `Screen` (`generateMock: true`) builds `ChainLink`. Each module lists only its direct dependency.
- Module-info flow: `Screen.mock(chainBase: ChainBase, safeDIOverrides:)` with `chainLink: ((ChainBase) -> ChainLink)?`.
- SwiftPM plugin flow: `Screen.mock(safeDIOverrides:)` builds the whole chain, with nested `SafeDIMockConfiguration`s and `chainToken:`.
- Neither seam matters: removing `generateDependencyTree` from `ChainBase` or `ChainLink` gives the same difference. Listing Core and Base in Feature's dependencies makes the two flows agree. Passing `--transitive-module-info-file-path` as the Bazel rule does changes nothing, because Feature declares no root or seam.
- The Manual's "Which modules to list" documents this: "Generated mocks build only the types of the modules a run reads, and take any other type as a `mock()` parameter. Under Bazel, a run reads the modules its module’s trees need, but no others. To have a mock build a type from a module further down, list that module." `bazel/safedi.bzl` says the same. So the fuzzer's integrations oracle lacks an exemption for a mock reaching a module beneath its direct dependencies.
Run with `ExplorationMultiModuleTests` on branch claude/project-thread-a6wosh: `SAFEDI_EXPLORE_MM_DIRECTORY=f4 SAFEDI_EXPLORE_MM_OUTPUT=out`.

## F5: a calling mock's helper returns the erasure but builds the custom-mocked type (public mock seeds 1339, 1649, 2687, 2840)
`f5`: Feature's `T0` has `generateMock: .public, customMockName: "customMock"`. Feature's `AnyT0(_: any T0Protocol)` erases it. Other's `T8` has `generateMock: .public` and declares `@Instantiated(fulfilledByType: "T0", erasedToConcreteExistential: true) let anyT0: AnyT0`. Other's generated `extension T0 { static func __safeDI_mock(…) -> AnyT0 { … T0.customMock(…) } }` doesn't compile: "cannot convert value of type 'T0' to specified type 'AnyT0'". It fails under both integrations. The caller already wraps the result as `AnyT0(T0.__safeDI_mock(…))`.
`f5b`: the same without `customMockName` compiles. The custom mock is the trigger.
Run with `ExplorationMultiModuleTests`: `SAFEDI_EXPLORE_MM_DIRECTORY=f5`.
