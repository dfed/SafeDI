# Engine traps

Graphs written to catch a shared builder function handing one place another place's value. Each trap is a directory:

- `Fixture.swift`: the graph.
- `main.swift`: a probe that builds the generated mock (and the production tree where the graph has a root) and prints which token, id, clock, session or override each place was handed.
- `expected.txt`: what the probe prints with one builder function per place, recorded from `claude/record-contract` 4837718, whose mocks are still written per path.

`Scripts/engine-traps/run.sh BUILD_BIN_DIRECTORY [TRAP…]` generates each trap with that build's `SafeDITool`, compiles fixture, generated code and probe, runs the probe and diffs. It prints `ok`, `WRONG-VALUE` with the diff, `COMPILE-ERROR` or `GENERATE-ERROR`, and keeps the generated code in `$ENGINE_TRAPS_OUT/<trap>/Generated.swift` (default `~/engine-traps-out/default`). The build needs `SafeDITool`, the `SafeDI` product and the macros: `swift build --traits sourceBuild --product SafeDITool && swift build --traits sourceBuild --product SafeDI`.

| Trap | What sharing could hand the wrong place |
|---|---|
| `builder-loop-at-two-places` | A loop of builders beneath two parents. Both parents' functions hold the same text, `Instantiator<B>(__safeDI_bBuilder)`, naming two different functions: another token, another override. |
| `cycle-entered-two-ways` | A cycle the root enters at both of its types. A type built again beneath the other entry reads no override today; each lap reads the overrides of the entry it started from. |
| `cycle-beneath-two-parents` | Two cycles beneath two parents with a token and overrides each; one cycle forwards a new id on every lap. |
| `same-type-under-two-labels` | One type built three times, by value under two labels and by an instantiator that forwards nothing, each with a leaf to override and another token to read. |
| `forwarded-beside-root-value` | One reader of `id` beneath two types that forward an `id` and beneath the root, which builds one. |
| `sendable-family-overrides` | One type inside two `@Sendable` builders and in plain code: overrides read into locals before each `@Sendable` function, and a value each construction creates afresh. |
| `seam-deferred-parameter` | A module's own tree that receives a session created on first read: read behind builders at the top, hidden beneath a type that instantiates its own, and by value inside a built type. Counts when the session is created. |
