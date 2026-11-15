# W1: the three gaps, closed

All three close. Two are lifted and one corner stays an error. W1 before the rc grows from 4–6 to **7.5–11 plain days (18–26 measured, ×2.4)** on top of the leak fix, with no public API change.

Probes are hand-written Swift 6.4.2, `-swift-version 6 -warnings-as-errors`, plain and `-O`, in `/Users/dfed/Library/Caches/SafeDIScratch/adopter-reply-2026-11-14/w1-w4-lift/probes-gaps` (`zsh run.sh g1|g2|g3 [flags]`). Each compares values and freed/created counts with inline.

## Gap 1: start order — lift

- **Fix:** a call that passes a place up starts as a carrier, last, as a site does. `SeamDeclarationGraph.init` reads only sites and fills today (`SeamDeclarationGraph.swift:53-69`); the order code is `ScopeGenerator.swift:3674-3693`.
- **Probe (`g1.swift`, `g1.out.txt`):** `Store` declares an eager inner seam and an instantiator-held one before `cart`.
  - Today's order does not compile (`-DINDEX`, `g1-index.out.txt`).
  - Carrier-last equals inline when the fill reads `cart`: values, construction order, and freed counts.
  - When the fill reads nothing, values and freed counts are equal, generated and hand-written.
- **One difference:** when the fill reads nothing, `cart` is now built before the eager call; inline builds it after (run 3). Sites already do this.
- **Size:** 1–1.5 days. It reorders existing seam output where a call precedes a sibling.

## Gap 2: one struct per type — lift the plain case, reject the loop

- **Fix:** the shared struct holds what is bound before the first carrier. A call that follows a later sibling takes a stage struct: the previous stage plus what was bound since. Each field is declared once, so size stays linear.
- **Probe (`g2.swift`, `g2.out.txt`):** `badge` receives `aBuilder` and `bBuilder`'s fill reads `badge`. Both fills equal inline, including `nil` for `badge` under `aBuilder`. Everything is freed, generated and hand-written.
- **Stays rejected:** a builder loop between a call and a sibling that call's own fill reads (`Side` receives `aBuilder`; the fill receives `sideBuilder`).
  - The direct form does not compile: "closure captures … before it is declared" (`g2-loop-direct.out.txt`).
  - The deferred-field form leaks where inline frees everything: `Box 0/1` (`g2-loop-boxed.out.txt`).
  - It needs W4's "function takes its builder" form, so it goes to 2.3.1 with W4.
- **Remedy needs a fix:** the existing error offers "instantiate it above the seam" (`SeamBuilderParameters.swift:1684-1686`). That cannot work here, because `Side` receives the seam's own builder. The error must offer only the fulfil-in-the-seam's-module remedy. I did not run that remedy through the generator.
- **Size:** 1.5–2 days, including the remedy.

## Gap 3: re-entry — lift

- **Fix:** the re-entering call is a struct member like any other, and takes what the path binds. Today its values struct is empty (`SafeDIToolSeamBuilderParameterTests.swift:2819-2885`) and the read is an error (`SeamBuilderParameters.swift:1768-1772`). App's function for the seam takes the label and calls itself.
- **Probe (`g3.swift`, `g3.out.txt`):** `Service → X → Service`, three deep, with a second `X`.
  - The fill gets Root's `logger` at depth 0 and each `X`'s below.
  - With an only-if-available read under a root with no logger, it gets `nil` at depth 0 and the `X`'s below.
  - Everything is freed, including the hand-written call.
  - The control that passes the builder on unchanged differs in 2 runs (`g3-unchanged.out.txt`), so the check can tell.
- **Size:** 1–1.5 days. The Manual's "seam built again" error (`Manual.md:1901`) goes. Keeping it rejected instead costs 0.

## Total and API

| | Plain days | Measured |
|---|---|---|
| Original lift (`analysis.md:36`) | 4–6 | 10–14 |
| Three gaps | 3.5–5 | 8–12 |
| **W1 before the rc** | **7.5–11** | **18–26** |

The gap figures are my estimates. Each gap's PR needs its fuzzer draw; that is counted in the gap figures.

**Public API:** none. Everything is inside generated `SafeDIScope_…` types that only generated code names, and hand-written builders still take no scope. Against 2.2.0 nothing breaks, since seams are new. Between betas, W1 only accepts what was an error, plus gap 1's reorder.

## Not verified

- Nothing ran through the generator.
- Swift 6.2 and Linux were not run.
- The probes are one module each; the earlier W1 probe covered module boundaries.
- Not probed: `@Sendable` calls, stage structs three seams deep, and re-entry through a second seam of the module.
