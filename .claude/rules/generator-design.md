---
paths:
  - "Sources/SafeDICore/Generators/**/*"
  - "Sources/SafeDICore/Models/**/*"
  - "Sources/SafeDICore/Visitors/**/*"
  - "Sources/SafeDIToolLibrary/**/*"
  - "Sources/SafeDI/**/*"
---

<!-- Keep this file under 32,000 characters (Scripts/check-claude-instruction-files.sh): Claude truncates an on-demand file at 40,000. -->

# Generator design

- **No feature that can crash an accepted tree.** If static analysis cannot rule out that an accepted tree plus ordinary user code crashes, hangs or recurses at runtime because of a feature, the feature is disqualified; removing a trap does not satisfy this. Misuse inside a user's own initializer (reading the `LazilyInstantiated` being created) is the user's: it behaves like the Swift feature it mirrors, never a trap.
- **Build type spellings through `TypeDescription`.** Generated code computes type names and call targets with `TypeDescription` (`asSource`, `asInstantiatedType`), never by joining strings such as a type name, `"."` and a method name, which loses generics, nesting and module qualification.
- **No hand-kept list of system frameworks.** Where logic or wording must tell system modules from the user's, use a signal SafeDI has (the modules it read, or was given module info for), or drop the feature. A curated list is always incomplete and goes stale with every SDK.
- **Runtime speed of generated code over compile time.** Generated trees run in adopters' apps; compile time costs only developers, and release compile time matters least. Never make a tree slower in order to compile faster (`@inline(never)` on seam initializers, heap-allocated payloads) without a runtime measurement beside the compile numbers, and rank compile-cost work by debug builds. A small constant cost per tree build, such as one allocation per seam, is fine: trees are not built in tight loops.
- **A cost every build pays needs the case's frequency.** More `generate` time is paid by every user on every build; a rare compile error with a documented fix is paid once by the few who hit it. Measure how often the case occurs in a real app before trading API, capability or build time for it, and keep it documented when it is rare, fails at compile time (never with a wrong value) and has an easy fix. Where SafeDI cannot see something (isolation, another module's sources), a documented opt-in or spelling comes before generator work. Erasure (`fulfilledByType:`, `erasedToConcreteExistential:`, `ErasedInstantiator`) is first-class: a real app's tree that does not use it yet is no evidence a shape is rare.
- **Benchmarks are lifelike.** A synthetic module takes its shape from a real app's measured statistics: module count and sizes, the share of files with `#if` and mock text, where `#SafeDIConfiguration` lives, received-chain depth and fan-out. Never copy a private app's source into the repository, a fixture or the fuzzer's seeds; reproduce its shape with invented names.
- **Generated code captures only what it reads.** A generated closure, `@Sendable` or not, never captures a value nothing in it reads; that failure is SafeDI's (`seam-and-mock-contract.md`, "No retain cycles"). A non-`Sendable` value the user's own declarations capture is the user's, left to the compiler.
- **Parallel generator work reads only `Sendable` values.** No `@unchecked Sendable`, `nonisolated(unsafe)`, or lock-wrapped sharing of a mutable reference type in the generator: build immutable value snapshots (structs of what each task needs, keyed by index) once, serially, and keep `Scope` and the other classes actor-isolated or task-local. If that needs a type that does too much split in two, split it. A small, self-contained concurrency primitive with an auditable contract is the only place `@unchecked` may appear.
