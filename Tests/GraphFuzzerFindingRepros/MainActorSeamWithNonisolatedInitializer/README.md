# A `@MainActor` seam whose initializer is `nonisolated`

Found by the seam combination corpus's `combinationActorIsolationInnerSeamAtBoundary` cell, and drawn by `combinationActorIsolationSeamTreeAtBoundary` too, whose seeds `seamCombinationKnownIssues` lists. Minimized to the three types of `Fixture.swift`, in one module.

`Generated.swift.txt` is what `SafeDITool generate --include <directory of Fixture.swift> --combined-output …` writes for it on base 307019f8. Both seam initializers are declared in an extension of `Inner`, which is `@MainActor`, so both inherit the main actor, though the initializer they forward to is `nonisolated`:

- the generated-only `init(__safeDI_token:)`, which `Root`'s generated `init()` calls from outside the main actor, so the generated code does not compile:

  ```
  Generated.swift:32:20: error: call to main actor-isolated initializer 'init(__safeDI_token:)' in a synchronous nonisolated context
  ```

- the readable `init(token:)` (`generatePlainDependencyTreeInitializers: true`), which a hand-written nonisolated caller (`HandWrittenCaller.swift`) cannot call either:

  ```
  HandWrittenCaller.swift:2:5: error: call to main actor-isolated initializer 'init(token:)' in a synchronous nonisolated context
  ```

The inline build calls `Inner(token:leaf:)`, which is `nonisolated`, and compiles. Swift 6.2.4 (`swift:6.2`), `-swift-version 6`. Without the configuration line only `init(__safeDI_token:)` is generated, and `Root`'s generated call of it fails with the same error. The likely fix: each generated seam initializer spells the isolation of the initializer it forwards to (`nonisolated`, or a global actor), as a public mock's construction functions mirror `Initializer.spelledIsolation`.
