---
paths:
  - "Sources/SafeDICore/Generators/DependencyTreeGenerator+SeamDriver.swift"
  - "Tests/**/*SkippedConfirmingPass*.swift"
---

# Seams: skipping the confirming signature pass

Only the seam driver applies this rule, so it loads for the driver and its tests, not for every generator file; `seams.md` holds the fixed point it shortens.

- **Skipping the confirming pass.** A component of one seam that does not reach itself (`SeamComponents.seamsReachingThemselves`, from the walk that builds the components, since Tarjan returns a self-loop as a component of one) settles after its first pass, without the pass that would confirm it, when that pass threw nothing, added no parameter (same count and order, each by label, type spelling, `deferral` and `internalName`; a `nil` root is computed again from `initialSeamRoot` anyway), and its tree holds no generator with `seamCall`, `publicMockCall`, `fillKey` or `passedUpHoles` (`confirmingPassFindsNothingNew`): the second pass would read the same parameters, and of the holes, builders and call routes it adds (`SeamHoles`) only code generation, the memo's sharing, and reads behind calls, fills and passed-up holes read anything, so it finds the same root, byte for byte, not just the same `settledContent`. Such a seam's signature comes from a tree built with the construction memo on (`construction-memo.md`). The skip runs the settled pass's bookkeeping; emission still builds the seam's tree from its signature, since the first pass's tree has no hole sites. The test executors run the skipped pass anyway and compare encoded signatures (`SeamSignatureObservation.confirmsSkippedPasses`, `SkippedConfirmingPassChecks`).
