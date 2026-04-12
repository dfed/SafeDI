# SafeDI — Claude Code Guidelines

## Documentation

The core documentation is `Documentation/Manual.md`. Read it before making changes to understand SafeDI's API, macros, configuration options, and mock generation. The manual is the source of truth for user-facing behavior — if you change behavior, update the manual.

## Build & Test

```bash
swift build --traits sourceBuild   # Build all targets
swift test --traits sourceBuild    # Run all tests
./CLI/lint.sh                      # SwiftFormat — must pass before every push
swift test --traits sourceBuild --enable-code-coverage  # Coverage report
```

The `sourceBuild` trait is required for local development to compile SafeDITool from source. Without it, the default `prebuilt` trait downloads a prebuilt binary from the artifact bundle.

Always lint before pushing. Always run the full test suite after changes — don't rely on filtered runs alone.

## Architecture

SafeDI is a compile-time dependency injection framework for Swift. It uses Swift macros (`@Instantiable`, `@Instantiated`, `@Received`, `@Forwarded`) to declare dependency graphs, then generates initializer code and mock methods via a build tool plugin.

### Key modules

| Module | Role |
|--------|------|
| `SafeDICore` | Models (`TypeDescription`, `Property`, `Instantiable`, `Dependency`), visitors (`FileVisitor`, `InstantiableVisitor`), generators (`ScopeGenerator`, `DependencyTreeGenerator`) |
| `SafeDIMacros` | Swift macro implementations (`@Instantiable`, `@Received`, etc.) |
| `SafeDITool` | CLI entry point with `scan` and `generate` subcommands — scans Swift files for `@Instantiable` types, builds dependency tree, generates output |
| Plugins (`SafeDIGenerator`) | SPM build tool plugin that wires the tool into the build |

### Code generation flow

1. **Plugin** writes CSV of swift files → runs `SafeDITool scan` to build manifest → runs `SafeDITool generate` to produce code
2. **`SafeDITool generate`** parses all files via `FileVisitor` → builds `DependencyTreeGenerator` → generates per-root code + mock code
3. **DependencyTreeGenerator** creates `ScopeGenerator` trees → each generates its code via `generatePropertyCode`
4. **Mock generation** (`generateMockCode`) creates `mock()` static methods with `@autoclosure @escaping` parameters, `T? = nil` subtree parameters, and `MockContext` for disambiguation

### Mock generation flow

Mock generation follows this pipeline:

1. **`generateMockCode`** builds the mock scope map via `createMockTypeDescriptionToScopeMapping` (includes ALL types, not just reachable from roots)
2. For each type with `generateMock: true`, **`createMockRootScopeGenerator`** promotes `@Received` dependencies to root-level children and validates for cycles
3. **`ScopeGenerator.generateMockRootCode`** builds the mock method:
   - Calls `collectMockParameterTree` to walk the dependency tree and build `MockParameterNode` trees
   - Collects flat parameters: `@Forwarded` deps, uncovered `@Instantiated` deps, `@Received` deps not in the tree
   - Generates `SafeDIOverrides` struct (if tree children exist) and the `mock()` method signature and body

The production code path (`generatePropertyCode` with `.dependencyTree`) and mock path (`.mock`) share the same `ScopeGenerator` but diverge at `generatePropertyCode`. Mock fields (`mockInitializer`, `mockReturnType`, `customMockName`) are only accessed in mock code paths — never in production paths.

### Mock generation specifics

- **Share logic between production and mock paths where possible.** Validation, scope population, and other shared concerns should live in common helpers rather than being duplicated between `createTypeDescriptionToScopeMapping` and `createMockTypeDescriptionToScopeMapping`. When adding validation to one path, check whether the other path needs it too.
- `MockParameterIdentifier` (propertyLabel + sourceType) is the key type for tracking parameters throughout mock gen
- `resolvedParameters` tracks which deps are already bound — prevents duplicate bindings across scopes
- `parameterLabelMap` maps identifiers to disambiguated parameter names
- `TypeDescription.asIdentifier` produces identifier-safe disambiguation suffixes
- `TypeDescription.simplified` strips wrappers for cleaner suffixes, with fallback on collision
- Closure-typed defaults use `@escaping T = default` (not `@autoclosure`)
- `#SafeDIConfiguration` is always read from the current module only, never dependent modules

### Validation boundaries

Validation is split between the macro and the plugin based on available context:

- **Macro validation** (compile-time, local context only): The macro sees only the single decorated type or extension. Any error that can be determined from local context belongs here — missing `init`/`instantiate()`, invalid parameter combinations (`mockOnly + generateMock`), mock method signature issues, access control. These produce fix-its in the IDE.
- **Plugin validation** (build-time, full context): The plugin (`SafeDITool generate`) sees all modules' types. Errors that require cross-type knowledge belong here — unfulfillable dependencies, dependency cycles, duplicate type declarations, duplicate mock providers.

### Serialization

The `Instantiable` struct conforms to `Codable` and is serialized as JSON in `.safedi` module info files. These files are **regenerated every build** — there is no cross-version deserialization. Do not add backward-compatibility decoding logic (e.g., `decodeIfPresent` with defaults). The synthesized `Codable` conformance is sufficient.

## Code Style

- **No abbreviations.** Use `dependency` not `dep`, `parameter` not `param`, `declaration` not `decl`. Everywhere: variables, functions, tests, comments, commits.
- **No `default` or `case _` in switch statements when all cases are knowable.** Enumerate all cases explicitly for compile-time safety.
- **Use `for ... where` for simple boolean filters** instead of `guard ... else { continue }` inside the loop body.
- **Use `guard` for early exits**, not `if condition { continue/return }`.
- **No early return from bare `if`.** If an `if` branch returns, the non-returning path must be in an explicit `else` clause. Never fall through after `if { return }`.
- **Test names follow `method_expectation_conditionUnderTest`** pattern (e.g., `mock_disambiguatesAllParameters_whenThreeChildrenShareSameLabel`).

## Testing Philosophy

- **TDD**: Write failing tests first, then fix.
- **One behavior per test method.** Each test verifies one behavior, but may use multiple assertions to fully validate it (e.g., checking both the count and content of output). Do not test unrelated behaviors in the same method.
- **No tautological tests.** Tests must exercise real code paths with real input. Never use test helpers that rewrite input before processing — the test content should be exactly what production code would see. Tests should verify input code → output code.
- **Test through the pipeline**, not direct model construction. Mock tests use `executeSafeDIToolTest` which parses real Swift source through the full visitor → generator pipeline.
- **Full `==` output comparison.** Never use `.contains()` for mock output. Compare the complete expected string.
- **Verify updated test expectations compile.** When updating expected output in generator tests, review the new expected code to confirm it would compile as valid Swift. Check that variable references resolve to the correct scope, types match (no optional where non-optional expected), and all referenced variables have bindings. Do not blindly update expected output to match actual — the actual output may itself be buggy.
- **If code can't be covered by a test with real parsed input, remove the code.** Dead branches and defensive fallbacks for structurally unreachable paths should not exist.
- **Test fixture file naming affects processing order.** `executeSafeDIToolTest` names fixture files by extracting the type name from `@Instantiable` in the source content. Files are processed alphabetically, so the order types appear in `resolveSafeDIFulfilledTypes` depends on these names. When testing ordering-sensitive behavior (e.g., duplicate detection), be aware that a `struct MyService` file sorts differently than an `extension MyService` file (which falls back to `"File"`).

## Common Pitfalls

- The input CSV written by plugins includes ALL swift files (target + dependencies). Mock scoping requires passing `mockScopedSwiftFiles` separately — only the target's own files.
- `Property.<` sort uses type as tiebreaker (not just label) for stable ordering.
- Extension-based `@Instantiable` types use `static func instantiate(...)` instead of `init(...)`. Their `@Instantiated` dependencies are constructed by the parent scope.
- When a received dependency is promoted to root scope, the producer branch must capture the root-bound value — not reconstruct the type.
- `resolvedParameters` flows through sibling accumulation AND parent-to-child descent. Both paths must be consistent.
