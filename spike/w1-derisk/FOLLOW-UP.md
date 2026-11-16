# W1 derisk follow-up: main, public-mock bodies, macOS

Read-only spike, the follow-up to `REPORT.md`. Nothing under `Sources/` changed and no pull request was opened. The
branch merges main at a6d44af into the first spike's branch (19757f7). Linux runs use Swift 6.2.4 on x86_64,
`-swift-version 6 -warnings-as-errors`, at `-Onone` and `-O`, and every hand-written `d` variant is also built with
library evolution and a verified interface.

## 1. Every case on current main

**Yes.** With SafeDITool built from a6d44af, `run-all.sh` printed the same summary line for every fixture as on
247598444, and rewrote no stored generated file (`*/stored/*.swift.txt`), no trace and no error text: `git status`
showed no change under the old fixtures. So main's generator output for these shapes did not move between the two
bases, and every hand-written form still equals inline. No change to the estimate.

## 2. Gaps 1 and 2 inside a public-mock body (`PMG/`)

**Yes.** Two new fixtures, each with a public mock in `Feat`, the fill in `App`, and `Root(generateMock: true)` in `App`
calling the public mock. `d` is the hand-written per-path body with W1's struct; it equals inline at both
optimization levels, frees included, and passes library evolution.

### `PMG/order`: gap 1's start order and gap 2's stage struct

`Home(generateMock: .public) { a: Sub, meter: Meter, badge: Badge(@Received a), b: Sub }`, `Sub { api: any Api }`,
and the fill `Live { @Received meter, @Received(onlyIfAvailable: true) badge: Badge? }`. Inline builds `meter` first
(gap 1), gives `a`'s fill `badge: nil` and `b`'s fill `badge` (gap 2: `badge` needs `a`, so it cannot move). Main also
calls `Root.mock(safeDIOverrides: .init(home: .init(meter: …)))`, and both fills read the overriding meter.

```swift
// Feat: the body hands each call the stage its own path bound.
let meter = if let safeDIBuilder = safeDIOverrides.meter { safeDIBuilder() } else { Meter() }
let __safeDI_stage0 = SafeDIMockScope_Api.a_Values(meter: meter)
func __safeDI_a() -> Sub {
	let __safeDI_apiBuilder_a = __safeDI_apiBuilder.a(__safeDI_stage0)
	let api: any Api = __safeDI_apiBuilder_a.api(.init())
	return if let safeDIBuilder = safeDIOverrides.a { safeDIBuilder(api) } else { Sub(api: api) }
}
let a: Sub = __safeDI_a()
let badge = if let safeDIBuilder = safeDIOverrides.badge { safeDIBuilder(a) } else { Badge(a: a) }
func __safeDI_b() -> Sub {
	let __safeDI_apiBuilder_b = __safeDI_apiBuilder.b(.init(previous: __safeDI_stage0, badge: badge))
	…
}
// App: one level function per scope type, `nil` where a path bound nothing.
func __safeDI_apiBuilder_Home() -> Home.SafeDIMockScope_Api.__safeDI_Builder<any Api> {
	.init(
		a: { values in __safeDI_apiBuilder_Home_Sub_Scope(meter: values.meter, badge: nil) },
		b: { values in __safeDI_apiBuilder_Home_Sub_Scope(meter: values.previous.meter, badge: values.badge) },
	)
}
```

`SafeDIOverrides` and the readable `mock(apiBuilder:safeDIOverrides:)` are today's, unchanged, and hand-written callers
of the readable mock compile against `d`.

### `PMG/loop`: gap 2's loop

`Store(generateMock: .public) { aBuilder: Instantiator<A>, sideBuilder: Instantiator<Side> }`, `A { api: any Api }`,
`Side { @Received aBuilder }`, and the fill `LiveApi { @Received sideBuilder }`: `G2L/plain` as a public mock. The body
is G2L's seam body with today's override reads; the level function hands the instantiator to the fill.

```swift
func __safeDI_aBuilder() -> A {
	let sideBuilder = Instantiator<Side>(__safeDI_sideBuilder)
	let __safeDI_apiBuilder_aBuilder = __safeDI_apiBuilder.aBuilder(.init(sideBuilder: sideBuilder))
	let api: any Api = __safeDI_apiBuilder_aBuilder.api(.init())
	return if let safeDIBuilder = safeDIOverrides.aBuilder { safeDIBuilder(api) } else { A(api: api) }
}
let aBuilder = Instantiator<A>(__safeDI_aBuilder)
func __safeDI_sideBuilder() -> Side {
	let aBuilder = Instantiator<A>(__safeDI_aBuilder)
	return if let safeDIBuilder = safeDIOverrides.sideBuilder { safeDIBuilder(aBuilder) } else { Side(aBuilder: aBuilder) }
}
```

### What main does today with these shapes

Main accepts both and generates code, but `Root`'s mock is not inline's: it takes a required
`apiBuilder: (Home.SafeDIMockScope_Api) -> any Api` parameter (`b` fails to compile only because the fixture calls
`Root.mock()` as inline allows).
- In `loop`, `aBuilder_Values` is empty, so `Root.mock` hands every `aBuilder` call to that parameter.
- In `order`, `Root.mock` builds `b`'s fill itself but hands `a`'s (where `badge` is unbound) to the parameter
  (`badge: Badge??`, `passUp`). Variant `b2` calls it with a closure that builds `Live(meter: Meter(), badge: nil)`;
  the trace then differs from inline, since that closure cannot reach Home's meter.

So the mock side of W1 removes a required parameter from the calling mock in these shapes. That is a source break
for a test that calls such a mock with the parameter, and wants a 2.3.1 release note. The mock-side equivalent in
production is W1's base error, which W1 lifts.

### Estimate

No change to the +4–6 h for public mocks: gaps 1 and 2 need nothing beyond the struct the seam already has and the
per-path body, as the first report argued. Add about 1 h for the dropped-parameter release note and a test that pins
the new `mock()` signature. W1 stays at about 22–30 lane-hours.

## 3. macOS and Xcode

See the section added after the Mac probe runs.
