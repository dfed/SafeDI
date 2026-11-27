---
paths:
  - "Tests/**/GraphFuzzer.swift"
  - "Tests/**/SafeDIToolGraphFuzzerNestedCycleTests.swift"
---

# Graph fuzzer: the nested-cycle hole draw

Continues `fuzzer-gating-checks.md`, whose gating draws it is one of.

The nested-cycle hole draw (`addingNestedCycleHoleShapes`, `nestedCycleHoleRandom`, three split graphs in ten whose wrappers are not all `Sendable`, after `addingOptionalPlaceShapes`) puts a place on a type a second lazy cycle builds again. Its features begin `nestedCycleHole`, a gating family, each accepted count floored. `NestHoleHome`, a seam, instantiates `nestHoleTag` and the builder of `NestHoleOuter`, which builds `NestHoleInner` and holds a place of `NestHoleApi`, on itself or on `NestHoleScreen`; `NestHoleInner` builds `NestHoleOuter` again and `NestHoleRedeclarer`, which declares `nestHoleTag` again, before or after it builds `NestHoleInner` again, one draw in three through `NestHoleThird` (`…ThirdCycle`); `NestHoleLive` fills the place from the roots' module, reading the tag. Two draws in five where the seam's module names its package, `NestHoleHub`, a seam of `FuzzSession`, holds the place and `NestHoleHome` passes its builder up (`…PlacePassedUp`), `NestHoleHubRoot` instantiating the tag in `NestHoleHome`'s place. Where `NestHoleOuter` (`…LabelReceivedByTypeBuiltAgain`) or `NestHoleHub` (`…LabelReceivedBySeamPassingPlaceUp`) receives the tag, the graph is accepted and the value comparator judges each level's fill; where no type of the cycles does, half the draws of a graph without another draw's hole, the read is rejected by design (`nestedCycleHoleLabelNoFunctionTakes`, drawn count pinned; `declarationBoundOnCycleReentry`, whose remedy the remedy oracle applies). `SafeDIToolGraphFuzzerNestedCycleTests` names the seeds that fail without each fix: 1501, with a nested cycle's own nested cycles left out of `declarationsBetween`, and 222, with `holesPassedUp` adding no declaration for the scopes a called seam's place is closed on. An all-`Sendable` graph is not drawn: its place is handed no values, so `SafeDIToolSeamHoleOnCycleTests` covers it.
