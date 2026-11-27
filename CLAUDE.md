# SafeDI — Claude Code Guidelines

## Documentation

The core documentation is `Documentation/Manual.md`. Read it before making changes to understand SafeDI's API, macros, configuration options, and mock generation. The manual is the source of truth for user-facing behavior — if you change behavior, update the manual. Each topic has one home section, which the others link to rather than restate. Tests read parts of it by position, so read `.claude/rules/documentation.md` before moving a section or a code block of it.

## Build & Test

```bash
swift build --traits sourceBuild   # Build all targets
swift test --traits sourceBuild    # Run all tests
./CLI/lint.sh                      # SwiftFormat — must pass before every push
swift test --traits sourceBuild --enable-code-coverage  # Coverage report
```

SwiftPM itself leaves a few `TemporaryDirectory.*` folders in `$TMPDIR` on every `swift` command (`build`, `test`, `run`), so point `TMPDIR` at a folder outside both the system temporary directory and the checkout when you run one locally (`mkdir -p ~/Library/Caches/SafeDITests/swiftpm && TMPDIR=~/Library/Caches/SafeDITests/swiftpm swift test …`), and empty it afterwards; `./CLI/lint.sh` already does this for its own run, in a folder under the gitignored `CLI/.build` that it removes when it exits. Inside the checkout, a test on an older branch that still writes fixtures to `TMPDIR` would have them read as part of the project.

The `sourceBuild` trait is required for local development to compile SafeDITool from source. Without it, the plugin uses the prebuilt binary from the artifact bundle.

Always lint before pushing. Always run the full test suite after changes — don't rely on filtered runs alone.

Formatting changes from `./CLI/lint.sh` go in a commit of their own, after the change. Coverage stays at 100%: every added or changed line under `Sources/` and `Plugins/` runs in a test or is removed. 2.x builds with Swift 6.2; a newer local compiler accepts code that fails there, so CI settles whether a change compiles. After resolving a conflict by hand, build the tests and check that no conflict marker is left before pushing; after a rebase, run the tests main changed; after merging documentation, check that the merge restored no text the base deleted. Never run an older release's test suite, which writes into the system temporary directory; compare with a release through its built `SafeDITool generate`.

**Run an integration before describing it.** A claim about what SwiftPM, Xcode, Bazel or Tuist passes the tool cites a captured build or a harness case.

### Scripts and hooks

- `./CLI/lint.sh --check` reports what SwiftFormat would change and changes nothing. The committed `PreToolUse` hook (`.claude/hooks/lint-before-push.sh`, wired in `.claude/settings.json`) runs it before `git push`, `gh stack` and `gh pr create`, in the worktree the command runs in, and blocks the command when it fails.
- `.claude/hooks/pre-push` is the same check as a git hook, for a session that started outside the checkout, where Claude Code loads no hook: `git config core.hooksPath .claude/hooks` in a clone (never `--global`, which replaces every other repository’s hooks) makes git refuse a push while `./CLI/lint.sh --check` fails or cannot run. `--self-test` runs inside `pre-review.py --self-test`.
- `Scripts/changed-line-coverage.sh [--full] [--first REGEX]… [BASE]` runs the suites the change touches with coverage (every other test only for lines those leave, `--full` for the whole suite at once; generated code is not compiled unless `--compile-checks`), and prints every added or changed line under `Sources/` and `Plugins/` that no test executed (default base `upstream/main` where that remote exists, else `origin/main`).
- `Scripts/fuzz-corpus.sh [--features …] [--seed N] [--iterations M|corpus] [--seeds N,N…] [--release]` runs the graph fuzzer's long run and prints its pin lines.
- `Scripts/fuzzer-coverage-report.sh RUN [BASE]` lists the changed generator lines no fuzzer corpus graph executed, from a run's `fuzzer-coverage` artifact, against another base; `graph-fuzzer.yml`'s `coverage` input makes the report for a commit before review ("Coverage of a change" in `.claude/rules/fuzzer-corpora.md`).
- `Scripts/multi-module-repro.sh [--conditions DEBUG,X] ROOT MODULE…` runs `generate` per module as Bazel and Tuist do and compiles the modules in order.
- `Scripts/unexecuted-lines.py` is "Check Line Coverage on Linux": it needs both test jobs' reports, so it cannot check a local run. `.claude/rules/ci.md` says how to read a CI run's result locally.
- Tools only agents run are skills under `.claude/skills/`: `verify-touched` runs the suites a branch touches, before any full Verify. Before a review, run `pre-review` on the final head and put its block in the hand-back: lint, the touched suites, every fuzzer corpus with its pins on CI when the change owes them, and the lists a reviewer would otherwise ask for (32 of the 49 findings of one day's review rounds were ones an existing command shows).
- `Scripts/generate-time-check.py BASE_TOOL HEAD_TOOL DIRECTORY` is "Check Generate Time on Linux": it times two builds of `SafeDITool` generating synthetic seam, inline and public mock graphs in alternating runs, and fails when the second takes twice as long on one.
- `Scripts/check-claude-instruction-files.sh` fails when an instruction file could be truncated or would load at launch by mistake, when a rules file is missing from the table under "Where the rest lives", when an instruction file names a Swift symbol no other tracked file contains (`Scripts/check-instruction-symbols.py`), or when reading one tracked file would load more rules than a budget allows (`Scripts/check-instruction-load.py`, whose `--report FILE…` prints what a file loads); "Check Markdown links" runs it.

### CI

The rules for CI itself are in `.claude/rules/ci.md`, which loads when you read a workflow or a file under `.github/`: which runner a job uses, macOS steps, managing runs, timeouts, containers, `verify.yml`, the coverage gate, stand-ins for required checks. Read it before proposing a CI change from another file. `gh workflow run verify.yml --ref <branch> -f filter=<swift test filter>` runs the Linux test job's build for one branch.

## Architecture

SafeDI is a compile-time dependency injection framework for Swift. It uses Swift macros (`@Instantiable`, `@Instantiated`, `@Received`, `@Forwarded`) to declare dependency graphs, then generates initializer code and mock methods via a build tool plugin.

### Key modules

| Module | Role |
|--------|------|
| `SafeDICore` | Models (`TypeDescription`, `Property`, `Instantiable`, `Dependency`), visitors (`FileVisitor`, `InstantiableVisitor`), generators (`ScopeGenerator`, `DependencyTreeGenerator`) |
| `SafeDIMacros` | Swift macro implementations (`@Instantiable`, `@Received`, etc.), compiled with the SafeDICore files they use; see `Sources/SafeDIMacros/CLAUDE.md` |
| `SafeDIToolLibrary` | The CLI's `scan`, `generate`, `query`, and `dump` subcommands — scans Swift files for `@Instantiable` types, builds dependency tree, generates output; `query` reports what one type needs |
| `SafeDITool` | The executable, which only runs `SafeDIToolLibrary`'s root command (`SafeDIToolCommandLine.rootCommand`). The commands live in a library so that the test targets depend on a library: Swift Build orders a target that depends on an executable target after the module it imports only when that target is a test target nothing depends on, which `SafeDIToolTestSupport` is not. The executable keeps the name `SafeDITool`, which names the tool the plugin asks for and the binary releases ship |
| Plugins (`SafeDIGenerator`) | SPM build tool plugin that wires the tool into the build |

### Code generation flow

1. **Plugin** writes CSV of swift files → runs `SafeDITool scan` to build manifest → runs `SafeDITool generate` to produce code. The Bazel rule (`bazel/safedi.bzl`) and the Tuist plugin (`TuistPlugins/SafeDITuist`) run no `scan`: each runs `generate --combined-output --module-info-output` once per module, passing the `.safedi` files of the modules it lists as dependencies.
2. **`SafeDITool generate`** parses all files via `FileVisitor` → builds `DependencyTreeGenerator` → generates per-root code + mock code
3. **DependencyTreeGenerator** creates `ScopeGenerator` trees → each generates its code via `generatePropertyCode`. A seam (`@Instantiable(generateDependencyTree: true)`) is a root of its own module's generation (`generateSeamRootCode`, per access tier an initializer only generated code calls, whose labels start with `__safeDI_`, preceded by a plain one that forwards to it where the module sets `generatePlainDependencyTreeInitializers` and the tier takes an argument, plus a guard enum) and a leaf of every other tree, which calls that initializer; see `.claude/rules/seams.md`.
4. **Mock generation** (`generateMockCode`) creates `mock()` static methods: a flat parameter for each value the mock cannot build, and `safeDIOverrides: SafeDIOverrides = .init()`, whose fields are override closures or nested `SafeDIMockConfiguration` values; `ScopeGenerator.MockContext` carries what a mock root needs (the mock condition, flat parameter defaults, cycle edges, the module's public mock context). The steps of mock generation are under "Mock generation flow" in `.claude/rules/generator-design.md`.


### Validation boundaries

Validation is split between the macro and the plugin based on available context:

- **Reject nonsense shapes.** A shape only a confused user would write gets an error, never generator support. "Reject" covers nothing else: every valid combination of existing features, at every position and across a module boundary, is in scope, and a shape an adopter asked for is required. A discouraged shape (one label declared again along one root-to-leaf branch; siblings may share a label) is rejected only where SafeDI would generate code that does not compile or that misleads.
- **The macro prevents; the plugin trusts.** A shape decidable from one declaration gets a macro diagnostic (the rename check under "Plugin validation" stays in the plugin by ruling), and the tool never re-checks what the macro rejects. Where it relies on a macro check to keep from trapping, it reports a plain error instead, as "Never a trap on what the macro rejects" in `.claude/rules/validation-boundaries.md` describes. A project upgrades SafeDI in every module at once, so no check or compatibility code serves a module an older SafeDI compiled.

The rest of this section (macro validation, plugin warnings, plugin validation, deprecations, and "Never a trap on what the macro rejects") is in `.claude/rules/validation-boundaries.md`.

## Determinism

Everything SafeDI produces must be identical on every run over the same inputs: generated code, diagnostics (their text, their order, and which one is reported first), fix-its, output file names, and the bytes of manifests, `.safedi` files and caches.

- Swift seeds hashing per process, and `Scope` hashes by object identity, so the order of a `Set` or `Dictionary` changes between runs — for scopes, even under a fixed hash seed. A task group's results arrive in completion order. None of these orders may reach output.
- When code chooses among candidates or emits a list, use declaration order, source path order, or a sorted order. Never use first-found or last-write-wins over an unordered collection.
- When a choice is genuinely ambiguous, report an error or apply a stated tie-break. Do not pick silently.
- Sorting only on the failure path is fine, and keeps the success path cheap: visit everything, and keep the candidate that sorts first only when there is something to report.
- A test of choice-making code needs enough candidates that a wrong order fails on nearly every run: twenty or more, or a permutation of six. A fixture with one candidate cannot catch this class of bug.
- The generator's own hazards (the fulfilling-instantiable map, a loop over a `Set<Scope>`, choosing a diagnostic by source location) are under "Determinism in the generator" in `.claude/rules/generator-design.md`.
- **What may follow names.** Generated code and signatures, which graphs are accepted, and which diagnostic is reported never depend on names or order. The order of suggestions inside one message, and a label sort of equivalent parameters (flat `mock()` parameters, overrides, a seam's pass-throughs), may. Fix an order-dependent choice in the change that notices it.

## Code Style

- **Compare for meaning through a projection.** A comparison for meaning (settling, the callers' view, a guard hash) uses an explicit projection, never the synthesized `==` or hash of a type that carries diagnostic payload.
- **No abbreviations.** Use `dependency` not `dep`, `parameter` not `param`, `declaration` not `decl`. Everywhere: variables, functions, tests, comments, commits.
- **No `default` or `case _` in switch statements when all cases are knowable.** Enumerate all cases explicitly for compile-time safety.
- **Use `for ... where` for simple boolean filters** instead of `guard ... else { continue }` inside the loop body.
- **Use `guard` for early exits**, not `if condition { continue/return }`.
- **No early return from bare `if`.** If an `if` branch returns, the non-returning path must be in an explicit `else` clause. Never fall through after `if { return }`.
- **Test names follow `method_expectation_conditionUnderTest`** pattern (e.g., `mock_disambiguatesAllParameters_whenThreeChildrenShareSameLabel`).
- **No traps in shipped code.** A validated tree, and the code generated from it, never crash. Code under `Sources` and `Plugins` uses none of the traps `SourceRuleTests` fails on (`.claude/rules/source-rules.md`), except at a site whose waiver states the invariant that keeps it from trapping on any input, including input the macro rejects ("Never a trap on what the macro rejects").
- **`SourceRuleTests` enforces source rules**, listed with the waiver syntax in `.claude/rules/source-rules.md`.
- **Spell an apostrophe ’ in the text SafeDI emits.** Diagnostics, fix-its, help and generated comments use ’ (U+2019), never '; a quotation mark and quoted compiler output keep theirs. `Scripts/sweep-apostrophes.py` rewrites a literal's apostrophes and the tests that compare them.
- **No `@unchecked Sendable` or `nonisolated(unsafe)`.** The compiler proves the concurrency safety of SafeDI's own code (`Sources` and `Plugins`; a test fixture's types are input); disentangle the state instead. `SourceRuleTests` fails on either unless Dan approved the site. Nor a lock around a shared reference type (`.claude/rules/generator-design.md`).
- **Name the compiler at each workaround.** A workaround for an older Swift or one platform's compiler, and a test that exists for it, names the Swift version and the diagnostic it avoids in a comment. The workarounds SafeDI's own sources need are in `.claude/rules/source-rules.md`.

## Testing Philosophy

- **TDD**: Write failing tests first, then fix.
- **The fuzzer draws what the generator newly does.** A change that makes the generator accept or emit a new shape adds a fuzzer draw for it in the same PR, whose graphs the tool accepts; a fixed generator defect adds a roll that fails with the fix reverted; a new oracle names the seed a hand mutation makes fail; no flag turns an oracle off. Late defects came from shapes the fuzzer did not draw yet. A small fix in a drawn shape needs only its roll; docs and diagnostic wording need nothing. Before changing the generator, read "Drawing a change" in `.claude/rules/fuzzer-corpora.md`.
- **One behavior per test method.** Each test verifies one behavior, but may use multiple assertions to fully validate it (e.g., checking both the count and content of output). Do not test unrelated behaviors in the same method.
- **No tautological tests.** Tests must exercise real code paths with real input. Never use test helpers that rewrite input before processing — the test content should be exactly what production code would see. Tests should verify input code → output code.
- **Test through the pipeline**, not direct model construction. Mock tests use `executeSafeDIToolTest` which parses real Swift source through the full visitor → generator pipeline.
- **Design a change's tests before its code**, as `.claude/rules/test-design.md` says: the shape matrix, which cells are handwritten, which go to the fuzzer.
- **Before adding a test file or a fixture, read `.claude/rules/test-infrastructure.md`** (it loads with any file under `Tests/`): which of the five `SafeDITool` test targets a test goes in, how fixture file names decide processing order, and how a test builds a path. Tests never write to the system temporary directory, and never depend on where the checkout lives.
- **Full `==` output comparison.** Never use `.contains()` for mock output. Compare the complete expected string.
- **Verify updated test expectations compile.** When updating expected output in generator tests, review the new expected code to confirm it would compile as valid Swift. Check that variable references resolve to the correct scope, types match (no optional where non-optional expected), and all referenced variables have bindings. Do not blindly update expected output to match actual — the actual output may itself be buggy.
- **Code generation tests should only test paths where the macro would not emit an error**, except tests of the plain errors "Never a trap on what the macro rejects" describes. Test inputs must be valid under `@Instantiable` macro validation — every `mockOnly: true` type needs a `mock()` method (or `customMockName` method), mock method names on the same type must not collide (and a `mockOnly` mock paired with a generated mock must use `customMockName`, or generation errors), and production types need `init` or `instantiate()`.
- **Invented names only.** A fixture, comment, test name or document never carries the type, module or app names of a real project that uses SafeDI, nor its counts: invent a neutral name and say "a real adopter's shape". History already published stays as it is; fix only what is on the default branch.
- **Test titles must be observably verified.** When a test title says "prefers X over Y", the assertion must verify X is used — not just that the test doesn't crash. Add a parent type with `generateMock: true` that instantiates the type under test, and assert the full mock output shows X's method name.
- **If code can't be covered by a test with real parsed input, remove the code.** Dead branches and defensive fallbacks for structurally unreachable paths should not exist.
- **"Structurally unreachable" claims need a failing test.** Before removing defensive branches on the grounds that they can't be reached, write a test that tries to reach them with valid input. If the test can't be written, cite the specific rejection (file:line) and the input shape it rejects — a structural argument alone is not evidence. Structural arguments are easy to get wrong: e.g., `erasedToConcreteExistential: true` does NOT imply a constant property type, so "erased + cycle is rejected as constant" was wrong and cost a round trip when the branches had to be restored.
- **Same behavior on sibling paths.** Inside and outside a cycle, seam and inline, mock and production behave the same unless a stated reason says otherwise; that reason makes it a deliberate gap.
- **Document a deliberate gap; don't pin it.** A deliberate difference between sibling code paths gets a comment at both sites and a rule in the instructions file that owns the topic, not a test that pins the non-behavior.

## Pull requests

- The title and description become the squash commit: write them for a newcomer reading `git log` a year later. Say what changes in SafeDI's user-facing terms and why, the tests in a sentence, and the leftovers; no local paths, scratch files, decision identifiers, review rounds or history. Update the description with every push. A fix found in passing gets its own pull request.
- Each "Found and not fixed" item states its plan: a named pull request, a named later release and why, or left and why. A leftover earns a pull request only if it generates code that does not compile, or a wrong value, in a shape a real adopter writes.
- Work planned as several pull requests starts only after the whole plan is reviewed for soundness (rework, design coherence, scope, dependencies, risk), never on a plan assembled piece by piece.

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
| a workflow, a CI job, runners, timeouts, `verify.yml`, the coverage gate | `.claude/rules/ci.md` |
| CI's cache of passed compile checks, its identity, the sharing workflow | `.claude/rules/passed-compile-checks.md` |
| "File path spelling": any path comparison, `#sourceLocation`, `// Declared at` | `.claude/rules/file-paths.md` |
| "Validation boundaries": a diagnostic, a macro check, a plugin check | `.claude/rules/validation-boundaries.md` |
| reserved names, nested-type qualification, identifier spelling, `any` | `.claude/rules/reserved-names-and-spelling.md` |
| "Cycle mechanisms": cycle closing, builder function names, sibling order, deep walks | `.claude/rules/cycle-generation.md` |
| "Cycle mechanisms": a cycle or received-property walk | `.claude/rules/cycle-validation.md` |
| "Mock generation specifics": `mock()` bodies, hand-written mocks, overrides | `.claude/rules/mock-generation.md` |
| `mockRootParameters` or `seamMockBuilders` in `ScopeGenerator.swift`, which does not load it | `.claude/rules/mock-generation.md` |
| promotion to the mock root, parameter naming | `.claude/rules/mock-root-promotion.md` |
| `LazilyInstantiated` anywhere | `.claude/rules/lazily-instantiated.md` |
| `generateMock: .public`, generated attributes; a public mock's or a seam's own mock's builders that take nothing | `.claude/rules/public-mocks.md`, `public-mock-builders.md`, `calling-mock-hole-builders.md` |
| `generateDependencyTree: true` (seams) | `.claude/rules/seams.md`, `seam-access-proof.md`, `seam-generation.md`, `seam-builder-structs.md`, `seam-carriers.md`, `seam-holes.md`, `seam-hole-fills.md`, `seam-signature-passes.md` |
| a seam's or public mock's design: the contract, retention, hand-written builders | `.claude/rules/seam-and-mock-contract.md` |
| a generator's design: type spelling, cost, captures, parallel work, runtime safety | `.claude/rules/generator-design.md` |
| a tree's plan by declaration (`Generators/CycleTree`) | `.claude/rules/cycle-tree-per-type.md` |
| the construction memo; a decision made while code is emitted | `.claude/rules/construction-memo.md`, `construction-memo-calls.md`, `emission-decisions.md` |
| a source rule, `SourceRuleTests`, a waiver | `.claude/rules/source-rules.md` |
| a change's tests, before writing them | `.claude/rules/test-design.md` |
| a new test file, a fixture's file name, a temporary or expected path in a test | `.claude/rules/test-infrastructure.md` |
| `Documentation/`, `README.md` | `.claude/rules/documentation.md` |
| a breaking-change judgment, release notes, `publish.yml`, packaging | `.claude/rules/releases-and-packaging.md` |
| "Graph fuzzer" | `.claude/rules/fuzzer-overview.md`, then `fuzzer-known-issues.md`, `fuzzer-seam-draws.md`, `fuzzer-seam-oracles.md`, `fuzzer-builder-surface.md`, `fuzzer-gating-checks.md`, `fuzzer-corpora.md`, `fuzzer-seam-dependencies.md`, `fuzzer-value-oracles.md`, `fuzzer-remedy-oracle.md`, `fuzzer-calling-mocks.md`, `fuzzer-calling-mock-draw.md`, `fuzzer-calling-mock-limits.md`, `fuzzer-query-oracle.md`, `fuzzer-public-mock-corpus.md`, `fuzzer-release-acceptance.md`, `fuzzer-base-comparison.md`, `fuzzer-nested-cycle-hole.md` |
| Bazel rules | `bazel/CLAUDE.md` |
| the macro target's sources (what it compiles of SafeDICore) | `Sources/SafeDIMacros/CLAUDE.md` |
| the Tuist plugin | `TuistPlugins/CLAUDE.md` |

Each rules file stays under 32,000 characters (Claude truncates an on-demand file at 40,000), each directory `CLAUDE.md` under 1,500 characters, and this file under 5,500 words; `Scripts/check-claude-instruction-files.sh` fails CI otherwise. Add a rule to the file that owns its topic, never here, unless every change needs it.
