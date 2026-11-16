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
