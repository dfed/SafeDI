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
