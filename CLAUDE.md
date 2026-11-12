# SafeDI — Claude Code Guidelines

## Documentation

The core documentation is `Documentation/Manual.md`. Read it before making changes to understand SafeDI's API, macros, configuration options, and mock generation. The manual is the source of truth for user-facing behavior — if you change behavior, update the manual. Each topic has one home section, which the others link to rather than restate. Tests read parts of it by position. Two tests take the Swift code blocks of "Generating a dependency tree per module" up to the section's first line that begins with `#`, its first subheading: one expects exactly seven, takes the first as its fixture, and compares the second with the code generated for that fixture and the third with the call a root in another module generates for it; the other compares the fifth and sixth with the code its own builder fixture generates. A third takes the two Swift code blocks of "Adopting SafeDI in a large codebase" and the first of "Calling a public mock from another module", each section up to its next heading, as the files of modules `Feed`, `App` and a module of another package, and compiles them. The graph fuzzer's known issues cite the first two shapes of the section's list of ways a seam differs from building its tree inline.

## Build & Test

```bash
swift build --traits sourceBuild   # Build all targets
swift test --traits sourceBuild    # Run all tests
./CLI/lint.sh                      # SwiftFormat — must pass before every push
swift test --traits sourceBuild --enable-code-coverage  # Coverage report
```

SwiftPM itself leaves a few `TemporaryDirectory.*` folders in `$TMPDIR` on every `swift test`, so point `TMPDIR` at a folder outside both the system temporary directory and the checkout when you run tests locally (`mkdir -p ~/Library/Caches/SafeDITests/swiftpm && TMPDIR=~/Library/Caches/SafeDITests/swiftpm swift test …`), and empty it afterwards. Inside the checkout, a test on an older branch that still writes fixtures to `TMPDIR` would have them read as part of the project.

The `sourceBuild` trait is required for local development to compile SafeDITool from source. Without it, the plugin uses the prebuilt binary from the artifact bundle.

Always lint before pushing. Always run the full test suite after changes — don't rely on filtered runs alone.

**Run an integration before describing it.** A claim about what SwiftPM, Xcode, Bazel or Tuist passes the tool cites a captured build or a harness case.

### Scripts and hooks

- `./CLI/lint.sh --check` reports what SwiftFormat would change and changes nothing. The committed `PreToolUse` hook (`.claude/hooks/lint-before-push.sh`, wired in `.claude/settings.json`) runs it before `git push`, `gh stack` and `gh pr create`, in the worktree the command runs in, and blocks the command when it fails.
- `Scripts/changed-line-coverage.sh [BASE]` runs the suite with coverage as CI does and prints every added or changed line under `Sources/` and `Plugins/` that no test executed (default base `origin/main`).
- `Scripts/fuzz-corpus.sh [--features …] [--seed N] [--iterations M|corpus] [--release]` runs the graph fuzzer's long run and prints its pin lines.
- `Scripts/multi-module-repro.sh ROOT MODULE…` runs `generate` per module as Bazel and Tuist do and compiles the modules in order.
- `Scripts/check-claude-instruction-files.sh` fails when an instruction file could be truncated or would load at launch by mistake; "Check Markdown links" runs it.

### CI

- Every CI job runs on a Linux runner unless it genuinely needs macOS: Xcode or `xcodebuild`, an Apple platform SDK, the Xcode project plugin, or the macOS release binaries and their notarization. Linux runners scale; macOS runners are the scarce resource that pull requests and publishes queue on.
- A job on a `macos-*` runner states why in a comment in the workflow.
- New Linux jobs use the same container and setup as the existing Linux test job ("Build and Test on Linux" in `ci.yml`), except "Build Release SafeDITool on Linux", which runs `publish.yml`'s Linux build command in `publish.yml`'s container, because publishing 2.3.0-alpha-1 crashed Swift 6.3.3 compiling that release build of code every CI job had passed.
- A required check that a matrix job reports needs a Linux stand-in that reports the same names when a Markdown-only change skips the job. A skipped job satisfies a required check under its own name, but GitHub evaluates a job's `if:` before expanding its matrix, so a skipped matrix job reports only its unexpanded name. The stand-in takes the job's `name:` and matrix through YAML anchors, runs only when `changes` reports a Markdown-only pull request, and needs no container, since it only reports (as "xcodebuild-markdown-only" does for "xcodebuild").
- `Examples/Example Package Integration` has spaces in its name so that CI builds a package under a path with spaces. Markdown links to it spell the spaces `%20`, which GitHub renders but md-dead-link-check cannot decode, so `.github/md-dead-link-check.toml` excludes exactly those links and `.github/scripts/check-excluded-markdown-links.py`, a step of "Check Markdown links", checks that each still names a path that exists.

## Architecture

SafeDI is a compile-time dependency injection framework for Swift. It uses Swift macros (`@Instantiable`, `@Instantiated`, `@Received`, `@Forwarded`) to declare dependency graphs, then generates initializer code and mock methods via a build tool plugin.

### Key modules

| Module | Role |
|--------|------|
| `SafeDICore` | Models (`TypeDescription`, `Property`, `Instantiable`, `Dependency`), visitors (`FileVisitor`, `InstantiableVisitor`), generators (`ScopeGenerator`, `DependencyTreeGenerator`) |
| `SafeDIMacros` | Swift macro implementations (`@Instantiable`, `@Received`, etc.) |
| `SafeDIToolLibrary` | The CLI's `scan`, `generate`, `query`, and `dump` subcommands — scans Swift files for `@Instantiable` types, builds dependency tree, generates output; `query` reports what one type needs |
| `SafeDITool` | The executable, which only runs `SafeDIToolLibrary`'s root command (`SafeDIToolCommandLine.rootCommand`). The commands live in a library so that the test targets depend on a library: Swift Build orders a target that depends on an executable target after the module it imports only when that target is a test target nothing depends on, which `SafeDIToolTestSupport` is not. The executable keeps the name `SafeDITool`, which names the tool the plugin asks for and the binary releases ship |
| Plugins (`SafeDIGenerator`) | SPM build tool plugin that wires the tool into the build |

### Code generation flow

1. **Plugin** writes CSV of swift files → runs `SafeDITool scan` to build manifest → runs `SafeDITool generate` to produce code. The Bazel rule (`bazel/safedi.bzl`) and the Tuist plugin (`TuistPlugins/SafeDITuist`) run no `scan`: each runs `generate --combined-output --module-info-output` once per module, passing the `.safedi` files of the modules it lists as dependencies.
2. **`SafeDITool generate`** parses all files via `FileVisitor` → builds `DependencyTreeGenerator` → generates per-root code + mock code
3. **DependencyTreeGenerator** creates `ScopeGenerator` trees → each generates its code via `generatePropertyCode`. A seam (`@Instantiable(generateDependencyTree: true)`) is a root of its own module's generation (`generateSeamRootCode`, per access tier an initializer only generated code calls, whose labels start with `__safeDI_`, preceded by a plain one that forwards to it where the module sets `generatePlainDependencyTreeInitializers` and the tier takes an argument, plus a guard enum) and a leaf of every other tree, which calls that initializer; see `.claude/rules/seams.md`.
4. **Mock generation** (`generateMockCode`) creates `mock()` static methods with `@autoclosure @escaping` parameters, `T? = nil` subtree parameters, and `MockContext` for disambiguation

### Mock generation flow

Mock generation follows this pipeline:

1. **`generateMockCode`** builds the mock scope map via `createMockTypeDescriptionToScopeMapping` (includes ALL types, not just reachable from roots)
2. For each type with `generateMock: true`, **`createMockRootScopeGenerator`** promotes `@Received` dependencies to root-level children (except those `mockCanBuild` rejects and those one of the mocked type's own aliases provides), in the order the mock's tree first receives them (`inOrderTheMockTreeFirstReceives`), and validates for cycles
3. **`ScopeGenerator.generateMockRootCode`** builds the mock method:
   - Calls `collectMockParameterTree` to walk the dependency tree and build `MockParameterNode` trees
   - Collects flat parameters: `@Forwarded` deps, uncovered `@Instantiated` deps, `@Received` deps not in the tree
   - Generates `SafeDIOverrides` struct (if tree children exist) and the `mock()` method signature and body

The production code path (`generatePropertyCode` with `.dependencyTree`) and mock path (`.mock`) share the same `ScopeGenerator` but diverge at `generatePropertyCode`. Mock fields (`mockInitializer`, `mockReturnType`, `customMockName`) are only accessed in mock code paths — never in production paths.

### Validation boundaries

Validation is split between the macro and the plugin based on available context:

- **Reject nonsense shapes.** A shape only a confused user would write gets an error, never generator support.
- **The macro prevents; the plugin trusts.** A shape decidable from one declaration gets a macro diagnostic (the rename check under "Plugin validation" stays in the plugin by ruling), and the tool never re-checks what the macro rejects. Where it relies on a macro check to keep from trapping, it reports a plain error instead, as "Never a trap on what the macro rejects" in `.claude/rules/validation-boundaries.md` describes.

The rest of this section (macro validation, plugin warnings, plugin validation, deprecations, and "Never a trap on what the macro rejects") is in `.claude/rules/validation-boundaries.md`.

## Determinism

Everything SafeDI produces must be identical on every run over the same inputs: generated code, diagnostics (their text, their order, and which one is reported first), fix-its, output file names, and the bytes of manifests, `.safedi` files and caches.

- Swift seeds hashing per process, and `Scope` hashes by object identity, so the order of a `Set` or `Dictionary` changes between runs — for scopes, even under a fixed hash seed. A task group's results arrive in completion order. None of these orders may reach output.
- When code chooses among candidates or emits a list, use declaration order, source path order, or a sorted order. Never use first-found or last-write-wins over an unordered collection.
- When a choice is genuinely ambiguous, report an error or apply a stated tie-break. Do not pick silently.
- Sorting only on the failure path is fine, and keeps the success path cheap: visit everything, and keep the candidate that sorts first only when there is something to report.
- A test of choice-making code needs enough candidates that a wrong order fails on nearly every run: twenty or more, or a permutation of six. A fixture with one candidate cannot catch this class of bug.
- `Property.<` sort uses type as tiebreaker (not just label) for stable ordering.
- `typeDescriptionToFulfillingInstantiableMap` is a dictionary — iterating `.values` has non-deterministic order. Any code that reduces, sorts, or builds state from `.values` must produce the same result regardless of iteration order. CI runs tests 5 times specifically to catch non-determinism.
- `Scope` hashes by object identity, so a `Set` of scopes iterates in an order that changes from run to run even under a fixed hash seed. Validation that throws at the first error must visit trees in a sorted order: `validatePropertiesAreFulfillable(typeDescriptionToScopeMap:cyclesOnly:)` visits roots, then the other types whose mocks are generated, each in type order; the mock roots in `generateMockCode` are visited in type order too.
- `Scope` hashes by object identity, so a `Set<Scope>` iterates in an order that changes from run to run even under a fixed hash seed. A loop over one may build state, but anything it reports — the first error, the first match — must be chosen by a deterministic key (as `createTypeDescriptionToScopeMapping` does for `@Forwarded` errors), not by which element the loop reached first.
- **Diagnostics are chosen by source location, never by name order.** Every root (production, `generateMock` type, mock root, mock root's child trees) reports the first error its own walk finds, and `DependencyTreeGeneratorError.reportingAll(of:)` joins them in source order (`SourceDiagnostic.joiningInSourceOrder`), so renaming a type never changes which error appears or where. Two rules keep that true: a memo shared across roots (`ChildrenRequiringEachOtherValidation.validatedScopes`, `walkedAliasFulfillingProperties`) keeps only walks that completed — an entry from a walk that threw must be dropped, or a later root would skip the work and the reported set would depend on root order; and where one of several candidates must be picked (which promoted child a mock root validates first, which received property names a sibling, which reader a warning names), pick by declaration location or declaration order (`inOrderTheMockTreeFirstReceives` orders a mock root's promoted children by where its tree first receives them, for generation and validation alike), not by label or type-name order. The rename-invariance fuzzer oracle (#464) checks this class end to end.

## Code Style

- **Compare for meaning through a projection.** A comparison for meaning (settling, the callers' view, a guard hash) uses an explicit projection, never the synthesized `==` or hash of a type that carries diagnostic payload.
- **No abbreviations.** Use `dependency` not `dep`, `parameter` not `param`, `declaration` not `decl`. Everywhere: variables, functions, tests, comments, commits.
- **No `default` or `case _` in switch statements when all cases are knowable.** Enumerate all cases explicitly for compile-time safety.
- **Use `for ... where` for simple boolean filters** instead of `guard ... else { continue }` inside the loop body.
- **Use `guard` for early exits**, not `if condition { continue/return }`.
- **No early return from bare `if`.** If an `if` branch returns, the non-returning path must be in an explicit `else` clause. Never fall through after `if { return }`.
- **Test names follow `method_expectation_conditionUnderTest`** pattern (e.g., `mock_disambiguatesAllParameters_whenThreeChildrenShareSameLabel`).
- **No traps in shipped code.** A validated tree, and the code generated from it, never crash. Code under `Sources` and `Plugins` uses none of the traps `SourceRuleTests` (below) fails on, except at a site whose waiver states the invariant that keeps it from trapping on any input, including input the macro rejects ("Never a trap on what the macro rejects").
- **`SourceRuleTests` enforces source rules.** It fails on a trap in `Sources` or `Plugins` (a force unwrap, in an expression or a key path, an implicitly unwrapped optional or `init!`, `unsafelyUnwrapped`, `try!`, `as!`, `fatalError`, `precondition`, `preconditionFailure`, `assert`, `assertionFailure`, `Dictionary(uniqueKeysWithValues:)`, `Dictionary(dictionaryLiteral:)`, or a dictionary literal whose keys are not distinct literals), on `try?` under `Sources/SafeDICore/Generators`, on `__safeDI_` in a literal in `Sources` outside `ReservedName.swift`, on a lone backtick literal in `Sources` outside `IdentifierSpellingExtensions.swift`, and on an error type declared under `Sources/SafeDICore` that `ErrorReportingSite.byErrorType` does not list with the code that reports it. A safe site is waived by a comment on its line or on the lines just above it, `// safedi-source-rule: allow <rule> — <the invariant that makes it safe>`; a waiver that names no rule, gives no reason, or waives no site fails the test.
- **No new `@unchecked Sendable`.** The compiler proves the concurrency safety of SafeDI's own code (`Sources` and `Plugins`; a test fixture's types are input); disentangle the state instead. Only a tiny low-level primitive may be unchecked.
- **An actor's `lazy var` initializer reaches nothing isolated through a closure.** In an actor, a `lazy var` whose initializer contains a closure or a local function that calls an isolated method or reads an isolated property fails to compile with Xcode 26's Swift 6.2 ("actor-isolated default value in a actor-isolated context"), although Linux's Swift 6.2 and Swift 6.4 accept it. Keep the value in a stored optional instead, filled on first use by an isolated method that returns it.
- **Build long arrays and strings with sequential appends.** A long expression that joins arrays or strings with `+` and contains ternaries makes Linux's Swift 6.2 time out type-checking it. Declare a `var` and append each part, with an `if` where a ternary chose a part.

## Testing Philosophy

- **TDD**: Write failing tests first, then fix.
- **One behavior per test method.** Each test verifies one behavior, but may use multiple assertions to fully validate it (e.g., checking both the count and content of output). Do not test unrelated behaviors in the same method.
- **No tautological tests.** Tests must exercise real code paths with real input. Never use test helpers that rewrite input before processing — the test content should be exactly what production code would see. Tests should verify input code → output code.
- **Test through the pipeline**, not direct model construction. Mock tests use `executeSafeDIToolTest` which parses real Swift source through the full visitor → generator pipeline.
- **`SafeDITool`'s tests span five test targets.** A release whole-module compile grows faster than its module's line count, so one module of every `SafeDITool` test was the longest step of CI's build; five modules compile in parallel. `SafeDIToolTests` tests the tool itself (scan, generate, configuration, conditional compilation, module info, query, paths, caches, spelling); `SafeDIToolDependencyTreeTests` production code generation (`SafeDIToolCodeGeneration*`, `SafeDIToolDependencyTreeGenerationTests`, and the `LazilyInstantiated`, deferred-cycle, `Sendable` builder and `onlyIfAvailable` rename tests); `SafeDIToolMockTests` mock generation (`SafeDIToolMock*`, `SafeDIToolPublicMock*`, `SafeDIToolFlatMockParameterDefaultTests`, `SafeDIToolNestedTypeMockTests`); `SafeDIToolSeamTests` seams and access (`SafeDIToolSeam*`, `SafeDIToolAccessEnforcementTests`, `SafeDIToolUnreadTypeAccessTests`); `SafeDIToolFuzzerTests` the graph fuzzer's suites and `DifferentialValueComparatorTests`. A new test file goes in the target whose subject it tests. The helpers they share (`executeSafeDIToolTest`, the compile verifier, the graph fuzzer, the comparator) live in `Tests/SafeDIToolTestSupport`, a regular target that declares no tests and that no product lists, because Xcode 26 rejects a test target that depends on another test target (Xcode 27 accepts one). A package that depends on SafeDI never builds it, and Xcode's `SafeDI-Package` scheme builds only products, but a plain `swift build` of this package builds it, in release without `-enable-testing`, so the helpers import `SafeDIToolLibrary` without `@testable`, through the declarations the library makes `public` for them (no product lists the library, so `public` exposes nothing outside SafeDI's own targets; `package` would need a package name, which the `SafeDIGenerator` plugin, compiling `PluginTargetGraph.swift` through a symbolic link, does not have). A helper that needs another declaration of the library makes it `public` too. Every test file reaches it with `@testable import SafeDIToolTestSupport`, and the tool with `@testable import SafeDIToolLibrary`. SwiftPM compiles a regular target for the package's `platforms`, not for the host as it compiles a test target, so a helper that uses newer API than the package's `platforms` is marked `@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)`, as are the helpers that use it. SwiftPM's native build system (CI's) links every test target into one `SafeDIPackageTests.xctest`, so CI, coverage, and the fuzzer shards' `--filter 'SafeDIToolGraphFuzzerTests/longRun'` see one bundle as before; Swift Build builds one bundle per test target, as it did before the split.
- **Full `==` output comparison.** Never use `.contains()` for mock output. Compare the complete expected string.
- **Verify updated test expectations compile.** When updating expected output in generator tests, review the new expected code to confirm it would compile as valid Swift. Check that variable references resolve to the correct scope, types match (no optional where non-optional expected), and all referenced variables have bindings. Do not blindly update expected output to match actual — the actual output may itself be buggy.
- **Code generation tests should only test paths where the macro would not emit an error**, except tests of the plain errors "Never a trap on what the macro rejects" describes. Test inputs must be valid under `@Instantiable` macro validation — every `mockOnly: true` type needs a `mock()` method (or `customMockName` method), mock method names on the same type must not collide (and a `mockOnly` mock paired with a generated mock must use `customMockName`, or generation errors), and production types need `init` or `instantiate()`.
- **Test titles must be observably verified.** When a test title says "prefers X over Y", the assertion must verify X is used — not just that the test doesn't crash. Add a parent type with `generateMock: true` that instantiates the type under test, and assert the full mock output shows X's method name.
- **If code can't be covered by a test with real parsed input, remove the code.** Dead branches and defensive fallbacks for structurally unreachable paths should not exist.
- **"Structurally unreachable" claims need a failing test.** Before removing defensive branches on the grounds that they can't be reached, write a test that tries to reach them with valid input. If the test can't be written, cite the specific rejection (file:line) and the input shape it rejects — a structural argument alone is not evidence. Structural arguments are easy to get wrong: e.g., `erasedToConcreteExistential: true` does NOT imply a constant property type, so "erased + cycle is rejected as constant" was wrong and cost a round trip when the branches had to be restored.
- **Document a deliberate gap; don't pin it.** A deliberate difference between sibling code paths gets a comment at both sites and a rule in the instructions file that owns the topic, not a test that pins the non-behavior.
- **Test fixture file naming controls processing order.** Files parse in parallel, so completion order is random; `ModuleInfo(_:)` therefore orders a module's file scans by path, so its instantiables are in source file path order, keeping each file's top-to-bottom declaration order, and its imports and mock imports are sorted and deduplicated, so the `.safedi` file `generate` writes is the same bytes every run; upstream `.safedi` module info is already in that order, and `loadSafeDIModuleInfo` returns the dependent modules in the path order of their `.safedi` files, whatever order the caller lists them in or the parallel reads finish in, so the combined list `resolveSafeDIFulfilledTypes` sees is deterministic without a second sort. `executeSafeDIToolTest` names fixture files by extracting the type name from `@Instantiable` in the source content, so those names decide the order. When testing ordering-sensitive behavior (e.g., which of the two mockOnly merge branches runs), pick names that sort the way you need, and be aware that an `extension MyService` file falls back to `"File"`. A configuration-only snippet also falls back to `File.swift`, so it exercises `parseModule`'s fallback path; pass `swiftFileContentByFilePath` (e.g. `["SafeDIConfiguration.swift": …]`) to name a fixture explicitly when the file name matters. A single-module test writes a `.safedi` only when it names its module (`moduleMembershipArguments` with `--module-name`), and a multi-module fixture that `omitsModuleName` writes none, so no other module may depend on it.
- **Tests never write to the system temporary directory.** macOS empties `$TMPDIR` at startup before login, and the millions of entries killed test runs left there twice kept a Mac at the Apple logo for hours. Take every temporary path from `TestTemporaryDirectory` (`Tests/SafeDIToolTestSupport/TestTemporaryDirectory.swift`): `root` or `uniquePath(prefix:pathExtension:)`, one directory per test process in the user's caches directory (`$SAFEDI_TEST_TEMPORARY_DIRECTORY` overrides it), outside the checkout because fixtures inside the working directory would be read as part of the project. Give a process a test launches `TestTemporaryDirectory.environment(withTemporaryDirectory:)`, as `runProcess` does.
- **Tests must not depend on where the checkout lives.** The suite runs from checkouts under `/Users`, under `/tmp` (reached as `/private/tmp`), and through other symbolic links. Build an expected path by the rule the contract under "File path spelling" gives its consumer — for example the project root as the test handed it to `scan`, made absolute, joined with the file's path inside it, for `additionalInputFiles` — never from `currentDirectoryPath` or `NSTemporaryDirectory()` compared with a normalized path, and test a symbolic link by creating one, as `SafeDIToolPathSpellingTests` does. Under a plugin invocation that reports the fixture directory resolved, `generate()`'s diagnostics are at `NormalizedFilePath(fixtures.compilerPath(of:)).path`, and what `run()` prints is at `compilerPath(of:)` (see "File path spelling").

## Where the rest lives

The deep rules load on their own when you Read, Write or Edit a matching file (they are `.claude/rules/*.md` with `paths:`). Grep and Glob load nothing, so before changing an area from a file outside it, read its file. The sections this file used to hold are named in the first column.

If your session started outside the worktree you are editing, scoped rules and nested CLAUDE.md files do not load, so Read the files listed here for your area before editing.

| Before touching | Read |
|---|---|
| "Conditional compilation": `#if` handling, scan's cache, plugin build settings | `.claude/rules/conditional-compilation.md` |
| module membership, "Access between modules", generated imports | `.claude/rules/module-membership-and-access.md` |
| "Types a module cannot name": two modules' declarations of one name, the duplicate-name error | `.claude/rules/types-a-module-cannot-name.md` |
| "Type requirements query": `SafeDITool query needs` | `.claude/rules/query-needs.md` |
| "Serialization": `.safedi` files, the scan cache, `BinaryCoding` | `.claude/rules/serialization.md` |
| "File path spelling": any path comparison, `#sourceLocation`, `// Declared at` | `.claude/rules/file-paths.md` |
| "Validation boundaries": a diagnostic, a macro check, a plugin check | `.claude/rules/validation-boundaries.md` |
| reserved names, nested-type qualification, identifier spelling, `any` | `.claude/rules/reserved-names-and-spelling.md` |
| "Cycle mechanisms": cycle closing, builder function names, sibling order, deep walks | `.claude/rules/cycle-generation.md` |
| "Cycle mechanisms": a cycle or received-property walk | `.claude/rules/cycle-validation.md` |
| "Mock generation specifics": `mock()` bodies, hand-written mocks, overrides | `.claude/rules/mock-generation.md` |
| promotion to the mock root, parameter naming | `.claude/rules/mock-root-promotion.md` |
| `LazilyInstantiated` anywhere | `.claude/rules/lazily-instantiated.md` |
| `generateMock: .public`, generated attributes | `.claude/rules/public-mocks.md` |
| `generateDependencyTree: true` (seams) | `.claude/rules/seams.md`, `seam-access-proof.md`, `seam-generation.md`, `seam-holes.md` |
| "Graph fuzzer" | `.claude/rules/fuzzer-overview.md`, then `fuzzer-seam-draws.md`, `fuzzer-seam-oracles.md`, `fuzzer-corpora.md`, `fuzzer-value-oracles.md` |
| Bazel rules | `bazel/CLAUDE.md` |

Each file stays under 32,000 characters (Claude truncates an on-demand file at 40,000); `Scripts/check-claude-instruction-files.sh` fails CI otherwise. Add a rule to the file that owns its topic, never here, unless every change needs it.
