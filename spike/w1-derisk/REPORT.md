# W1 derisk spike: the unprobed cases, in the per-type form

Read-only spike. Nothing under `Sources/` changed and no pull request was opened. Everything here is hand-written
generated code, checked against SafeDITool's own inline output.

## Answers

| Case | Answer | Cost against the re-estimate |
|---|---|---|
| Gap 2's loop across a module boundary | **Yes**, in all three shapes: plain, a `@Sendable` call, and the hole in the inner seam's `@Sendable` family | The loop lifts with gap 2, so it is no longer a W4 item. It adds about 1–2 h (draw plus tests), not 3–4 h. The remedy fix for this corner goes away, because the shape stops being an error. |
| `@Sendable` calls | **Yes**: a call inside a `@Sendable` function, a fill reading a plain value, and one seam called from both families | About 1 h for a draw row. No new mechanism is needed. |
| Stage structs three seams deep | **Yes** | Already inside gap 2's 4–5 h. Gap 2 and gap 3 share the "level function takes optional values" plumbing, so building them in sequence saves about 1–2 h. |
| Re-entry through a second seam | **Yes** | About 1 h (draw). This is W1's base error, not gap 3's, and it falls out of W1 plus candidate B. |
| Public mocks with W1 while the mock body is still per-path | **No per-type shape needed.** The per-path body is wrong for gap 3's stale-loop case. It is right once the function that closes the loop takes its level's struct as a cycle parameter, which is the same mechanism today's inline mock already uses for `cache`. | **+4–6 h, down from +8–10 h** (my estimate). That covers struct-as-cycle-parameter in the mock emitter (2–3 h) and the mock draws (1–2 h). Gaps 1 and 2 need nothing extra in a per-path body. |

These revise the re-estimate's 25–35 lane-hours to about **22–30 lane-hours**. The critical path is unchanged at
14–20 h. Every figure is my estimate.

## Setup

- Branch base: `claude/project-thread-ea2rdt` (spike 2's harness, main at 247598444). The fixtures are in `spike/w1-derisk/`, and `run-all.sh` reruns them all.
- Compiler: Swift 6.2.4 on Linux x86_64, `-swift-version 6 -warnings-as-errors`, at `-Onone` and `-O`. Every hand-written variant (`d`, `h`) was also built with library evolution and a verified interface.
- Variants:
  - `a`: inline, from SafeDITool. This is the reference.
  - `b`: today's tool. Every W1 shape is an error, and the error text is in `results/b-Onone.error.txt`.
  - `d`: the hand-written W1 form. It uses the leak fix's builder struct, a per-type body, and caller level functions using the dispatcher fixed point.
  - `c2` and `h`: public-mock bodies.
- "= inline" means the trace equals `a` byte for byte at both optimization levels. The trace covers values, construction order, what is alive while the last value is held, and what is alive after everything is dropped.

## 1. Gap 2's loop across modules (`G2L/`)

**Shape.** There are three modules. `Inner` has seam `A { api: any Api }`. `Feature` has seam `Store { aBuilder: Instantiator<A>, sideBuilder: Instantiator<Side> }` and `Side { @Received aBuilder }`. `App` has the fill `LiveApi { @Received sideBuilder }`. Today this is W1's "Store passes the builder … on from its own caller" error.

**Result.** `d` equals inline in `plain`, `scall` (both builders are `SendableInstantiator`) and `sfam` (`A { tBuilder: SendableInstantiator<InnerT> }`, so the hole is only in `A`'s `@Sendable` family).

**Form.** The `_Values` carries an instantiator that the caller builds at the call from the sibling's local function, exactly as inline builds its own. The two functions are mutually recursive local functions, and nothing is boxed or deferred:

```swift
// Feature: Store's seam body
func __safeDI_aBuilder() -> A {
	let sideBuilder = Instantiator<Side>(__safeDI_sideBuilder)
	return A(__safeDI_apiBuilder: __safeDI_apiBuilder.aBuilder(.init(sideBuilder: sideBuilder)))
}
let aBuilder = Instantiator<A>(__safeDI_aBuilder)
func __safeDI_sideBuilder() -> Side {
	let aBuilder = Instantiator<A>(__safeDI_aBuilder)
	return Side(aBuilder: aBuilder)
}
// App: the level function
return .init(aBuilder: { values in .init(api: { _ in __safeDI_liveApi(sideBuilder: values.sideBuilder) }) })
```

**The `@Sendable` forms.**
- In `scall`, Store's builder is `SafeDISendableScope_Api.__safeDI_Builder<Built>: Sendable`. Its member is `@Sendable (aBuilder_Values) -> A.SafeDIScope_Api.__safeDI_Builder<Built>`, which returns the plain struct, as F6's return-type rule says. `aBuilder_Values` is `Sendable`.
- In `sfam`, the member returns `A.SafeDISendableScope_Api.__safeDI_Builder<Built>`.

**Why the earlier probe kept the loop as an error.** The "deferred field" form leaked, and the "direct" form captured a value before it was declared. Neither problem appears when the value carried is an instantiator rebuilt from the sibling's function at the call.

**Control (`G2X/`).** The same loop with `Store` in the caller's module is accepted on main today, equals inline, and also equals inline in the per-path struct form (`c`). So the cross-module case is the only new one.

**Error text today.** The first remedy is "Declare `@Received let sideBuilder` on `A`", which cannot work for the loop. In `sfam` the text differs: "Instantiate `sideBuilder` outside `Store` …". This is the remedy defect `w1-gaps.md` names. It stops mattering once the loop is accepted.

## 2. `@Sendable` calls (`SND/`, plus `G2L/scall` and `G2L/sfam`)

- **`sdb`.** `Store { db: Db, aBuilder: SendableInstantiator<A> }`, and the fill reads `db`. `d` equals inline. `db` goes into a `Sendable` `aBuilder_Values`.
- **`both`.** `Store { db, a: A, aBuilder: SendableInstantiator<A> }` calls one seam from a plain place and a `@Sendable` place. Store takes one builder per family (`apiBuilder`, `apiSendableBuilder`), and both members return `A`'s plain struct. App has one `@Sendable` fill function, `__safeDI_liveApi(db:)`, that both families' level functions call. `d` equals inline.
- **A non-`Sendable` value.** A non-`Sendable` value read in a `@Sendable` call does not compile inline either ("capture of 'db' with non-Sendable type"). So it is the user's error, not a W1 case.

## 3. Stage structs three seams deep (`STG3/`)

**Shape.** There are four modules: `App → S1 (One) → S2 (Two) → S3 (Three, hole api)`. Each `Sk { mk: Mk, a: S(k+1), badgek: Badgek(@Received a), b: S(k+1) }`. The fill reads `m1`, `m2` (required) and `badge1?`, `badge2?` (only if available). Inline gives the four paths `(nil, nil)`, `(nil, badge2)`, `(badge1, nil)` and `(badge1, badge2)`.

**Result.** `d` equals inline. Each level declares stage 0 once and chains stage 1 onto it, so size stays linear:

```swift
nonisolated public struct a_Values { public let m2: M2 }                                   // stage 0
nonisolated public struct b_Values { public let previous: a_Values; public let badge2: Badge2 } // stage 1
let __safeDI_stage0 = SafeDIScope_Api.a_Values(m2: m2)
let a = S3(__safeDI_apiBuilder: __safeDI_apiBuilder.a(__safeDI_stage0))
let badge2 = Badge2(a: a)
let b = S3(__safeDI_apiBuilder: __safeDI_apiBuilder.b(.init(previous: __safeDI_stage0, badge2: badge2)))
```

App has one level function per seam type, and each takes what the levels above bound. This is the fixed point: the `a` member passes `nil`, and `b` passes `values.badge1`.

```swift
func __safeDI_apiBuilder_S2(m1: M1, badge1: Badge1?) -> S2.SafeDIScope_Api.__safeDI_Builder<any Api> {
	.init(
		a: { values in __safeDI_apiBuilder_S3(m1: m1, badge1: badge1, m2: values.m2, badge2: nil) },
		b: { values in __safeDI_apiBuilder_S3(m1: m1, badge1: badge1, m2: values.previous.m2, badge2: values.badge2) },
	)
}
```

**A finding for gap 1's rule.** My first draft used siblings that read nothing back, such as `S1 { e: S2, m1a, … }`. There, inline builds every sibling the fill reads before the call. That makes stages unnecessary and shows gap 1's start-order rule in action. Stage structs arise only where a sibling needs the call (`badge` receives `a`), so it cannot be reordered.

## 4. Re-entry through a second seam (`RE2/`)

**Shape.** `Feature` has seam `Service { gadget: any Gadget, xBuilder: Instantiator<X> }` and seam `X { logger: Logger, serviceBuilder: Instantiator<Service> }`. The fill reads `logger`.
- **`req`.** Root declares `logger`, so depth 0 gets Root's logger.
- **`opt`.** The fill reads `Logger?` and Root declares none, so depth 0 gets `nil`.
- **`one`.** `X` is not a seam. This is gap 3 as `w1-gaps.md` probed it.

**Errors today.** With `X` a seam, today's error is W1's base error ("`X` … passes the builder … on from its own caller"), not gap 3's "builds `Service` again".

**Result.** All three `d` variants equal inline. Each seam's struct has a member at the property that calls the other seam, returning that seam's struct. The two seams' enums refer to each other, and App's level functions are mutually recursive:

```swift
// Feature
public let xBuilder: (xBuilder_Values) -> X.SafeDIScope_Gadget.__safeDI_Builder<Built>             // in Service's struct
public let serviceBuilder: (serviceBuilder_Values) -> Service.SafeDIScope_Gadget.__safeDI_Builder<Built> // in X's; values { logger }
// X's body
func __safeDI_serviceBuilder() -> Service {
	Service(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder.serviceBuilder(.init(logger: logger)))
}
// App
func __safeDI_gadgetBuilder_Service(logger: Logger) -> Service.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
	.init(gadget: { _ in LiveGadget(logger: logger) }, xBuilder: { _ in __safeDI_gadgetBuilder_Service_X() })
}
func __safeDI_gadgetBuilder_Service_X() -> X.SafeDIScope_Gadget.__safeDI_Builder<any Gadget> {
	.init(serviceBuilder: { values in __safeDI_gadgetBuilder_Service(logger: values.logger) })
}
let service = Service(__safeDI_gadgetBuilder: __safeDI_gadgetBuilder_Service(logger: logger)) // `nil` in `opt`
```

## 5. Public mocks: per-type shape, or per-path body? (`PM3/`)

**Shape.** This is F3 (the stale loop value), the public-mock case of gap 3. `Home` has `generateMock: .public`, `Screen { cache, stepBuilder }` and `Step { api (hole), screenBuilder }`. The fill reads `cache`. App's mock calls Home's public mock. The struct, the readable `mock()` and every caller are F3's, unchanged.

**`c2`: the per-path body as today's mock closes a loop.** The reopened `Screen` re-enters the first level's `Step` function. **Wrong:** `Live#2(cache: Cache#1)` where inline gives `Cache#2`, plus two more lines.

**`h`: the per-path body with one change.** The function that closes the loop takes its level's struct, and the reopened `Screen` is still written out in place. **= inline**, frees included:

```swift
func __safeDI_stepBuilder(_ __safeDI_apiBuilder_step: SafeDIMockScope_Api.Step_Scope.__safeDI_Builder<any Api>) -> Step {
	func __safeDI_screenBuilder() -> Screen {
		let __safeDI_apiBuilder_screen = __safeDI_apiBuilder_step.screenBuilder(.init())
		let cache = Cache()
		let __safeDI_apiBuilder_step = __safeDI_apiBuilder_screen.stepBuilder(.init(cache: cache))
		let stepBuilder = Instantiator<Step> { __safeDI_stepBuilder(__safeDI_apiBuilder_step) }
		return Screen.__safeDI_init(cache: cache, stepBuilder: stepBuilder, safeDIBuilder: nil)
	}
	…
}
```

**This is today's cycle-parameter mechanism.** Inline's own mock closes this loop with `func __safeDI_stepBuilder(cache: Cache)` (`per-type-seam/F3/stale/a/stored/App.swift.txt`). `h` passes the level struct where inline passes `cache`.

**Overrides are untouched.** `h` reads exactly what today's per-path text reads:
- The first `Screen` reads `safeDIOverrides.screen`.
- A reopened `Screen` reads `nil`.
- Every `Step` reads `safeDIOverrides.screen.stepBuilder`.

So F3's objection, that one function shared by the first `Screen` and a reopened one would need the configuration as a parameter, does not arise.

**Gaps 1 and 2 in a mock.** A per-path body builds the values each path hands its call. Spike 2's leak-fix (c) bodies, and this spike's `Feature` bodies, are already per-path and handle start order, stages and the loop. I did not write a public mock for gaps 1 and 2 specifically.

**Answer.** Public mocks need W1's struct, which they already share with the seam, plus one emitter change: the level struct becomes a cycle parameter of the functions that close loops. They do not need a per-type body.

**Neighbour checked (`PMRE/`).** A re-entry through a second seam with a value bound after the hole (`Mark` receives `gadget`; the fill reads `mark?`) cannot go stale. Inline passes `nil` at every level, because a type's own later declaration hides the earlier level's. Today it reports a new error ("builds only after it calls the builder"), which is gap 1's carrier case and correctly stays an error.

## Not probed

- Swift 6.2 under Xcode 26, and macOS.
- Gap 1's order rule and gap 2's stages inside a public mock body. Both are argued above from per-path construction, not run.
- Overrides that change a value a fill reads inside a loop, in `h`.
- Main as of today: the base is 247598444, as in spike 2.
- The fuzzer seam corpus (spike 2's Stage 3).
