---
paths:
  - "Sources/SafeDICore/Generators/**/*"
  - "Sources/SafeDI/**/*"
  - "Tests/**/*Seam*.swift"
  - "Tests/**/*Hole*.swift"
  - "Tests/**/*PublicMock*.swift"
---

<!-- Keep this file under 32,000 characters (Scripts/check-claude-instruction-files.sh): Claude truncates an on-demand file at 40,000. -->

# The contract for seams and public mocks

Every design, change and review of a seam (`generateDependencyTree: true`) or a public mock (`generateMock: .public`) is judged against these seven rules, in this order; rules 1–4 outrank rules 5–7. The baseline is the inline build: the same types generated in one module, with no seam and no public mock call. How seams and public mocks are generated is in `seams.md`, `seam-holes.md` and `public-mocks.md`.

1. **Every valid combination of existing features compiles without warnings, at every position, across a module boundary.** A position is the seam or mocked type itself, a type beneath it, or a type inside a fill. "Reject" covers only what a confused user would write ("Reject nonsense shapes" in `CLAUDE.md`), and a shape an adopter asked for is required.
2. **Values equal the inline build's, or there is an error whose remedy works.**
3. **Nothing is retained that the inline build frees.**
4. **Generated size is linear when every axis grows together**: values, levels and hole types at once.
5. **A level carries only what its own type binds.** A field exists only where a generated read needs it.
6. **One case per property, and a shape that ignores type names, file names, module splits and labels that coincide.**
7. **A public mock differs from its seam only by this list:** a mock takes as parameters the received values its tree cannot build, where production reports an error; its levels follow the mock's tree; it passes one value per name and type to every type that creates it; `mock()` and `SafeDIOverrides` keep build order.

Rules 5 and 6 govern generated code, not public shape: no hand-written code reads a level or names a case, so a breach of either is a defect any release can fix.

**How to use it.** A design states which rule each choice serves and which it costs. A rule gives way only when that yields a simpler API or a shorter path to the release, and the proposal names the rule that gives way and says why. A choice that costs one of rules 1–4 is the maintainer's decision. A field, case or error that no rule asks for is not built. An exception to rule 1 is a rejection: an error at the seam or mock for a shape that builds in one module, naming a remedy that works. The maintainer approves each exception, and lifting one later changes no public shape. What exists only in a prerelease is no public shape to protect: whether a change breaks is measured from the last stable release (`releases-and-packaging.md`).

## No retain cycles

- **No release ships a retain cycle**, prereleases included: not in a seam, a public mock, or anything else SafeDI generates. Rule 3 has no exception, and a known retention blocks the next publish.
- **Fix retention structurally.** Generated code captures only what it reads, so each closure SafeDI generates keeps alive only the values its body uses. Prefer the change that makes a capture unnecessary over a workaround that keeps the capture and breaks it later.

## Builders a person writes

These rules are the decided shape of the public interface of seams and public mocks. Generated code does not follow them everywhere yet; the planned no-scope work brings it in line. Until then, new code follows them, and generated code that differs from them is a shape to remove, not to extend.

- **A hand-written builder takes no scope.** A builder a person writes, whether passed to a seam's readable initializer or to `mock()`, is to take exactly what its place forwards and return the value: `() -> T` (or `@Sendable () -> T`) for a place that forwards nothing. Only generated code is to hand values between a seam's levels, so that no public parameter hands a person a value the seam builds.
- **A forwarding place's builder type is its wrapper's nested `Builder`.** The readable initializer's and `mock()`'s parameter for a place that forwards values is to be the property's own wrapper type, spelled exactly as the property spells it, followed by `.Builder`: `Instantiator<T>.Builder`, `SendableInstantiator<T>.Builder`, `ErasedInstantiator<F, T>.Builder` or `SendableErasedInstantiator<F, T>.Builder`. No wrapper declares `Builder` yet; the planned no-scope work adds all four. Each is to be a typealias nested in its wrapper, and so bound to the property's own wrapper type, with no generic parameters of its own (`(T.ForwardedProperties) -> T`, and its `@Sendable` and erased forms): an alias with generic parameters of its own crashes Swift 6.2 and 6.4 wherever it is used unbound.
