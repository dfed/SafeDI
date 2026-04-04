# SafeDI — Claude Code Guidelines

## Documentation

The core documentation is `Documentation/Manual.md`. Read it before making changes to understand SafeDI's API, macros, configuration options, and mock generation. The manual is the source of truth for user-facing behavior — if you change behavior, update the manual.

## Build & Test

```bash
swift build              # Build all targets
swift test               # Run all tests
./lint.sh                # SwiftFormat — must pass before every push
swift test --enable-code-coverage  # Coverage report
```

Always lint before pushing. Always run the full test suite after changes — don't rely on filtered runs alone.

## Architecture

SafeDI is a compile-time dependency injection framework for Swift. It uses Swift macros (`@Instantiable`, `@Instantiated`, `@Received`, `@Forwarded`) to declare dependency graphs, then generates initializer code and mock methods via a build tool plugin.

### Key modules

| Module | Role |
|--------|------|
| `SafeDICore` | Models (`TypeDescription`, `Property`, `Instantiable`, `Dependency`), visitors (`FileVisitor`, `InstantiableVisitor`), generators (`ScopeGenerator`, `DependencyTreeGenerator`) |
| `SafeDIMacros` | Swift macro implementations (`@Instantiable`, `@Received`, etc.) |
| `SafeDITool` | CLI entry point — parses Swift files, builds dependency tree, generates output |
| `SafeDIRootScannerCore` | Pre-scan for roots and `@Instantiable` types (used by plugins, no SwiftSyntax) |
| Plugins (`SafeDIGenerator`, `SafeDIPrebuiltGenerator`) | SPM build tool plugins that wire the tool into the build |

### Code generation flow

1. **Plugin** writes CSV of swift files → runs `RootScanner` to build manifest → invokes `SafeDITool`
2. **SafeDITool** parses all files via `FileVisitor` → builds `DependencyTreeGenerator` → generates per-root code + mock code
3. **DependencyTreeGenerator** creates `ScopeGenerator` trees → each generates its code via `generatePropertyCode`
4. **Mock generation** (`generateMockCode`) creates `mock()` static methods with `@autoclosure @escaping` parameters, `T? = nil` subtree parameters, and `MockContext` for disambiguation

### Mock generation specifics

- `MockParameterIdentifier` (propertyLabel + sourceType) is the key type for tracking parameters throughout mock gen
- `resolvedParameters` tracks which deps are already bound — prevents duplicate bindings across scopes
- `parameterLabelMap` maps identifiers to disambiguated parameter names
- `TypeDescription.asIdentifier` produces identifier-safe disambiguation suffixes
- `TypeDescription.simplified` strips wrappers for cleaner suffixes, with fallback on collision
- Closure-typed defaults use `@escaping T = default` (not `@autoclosure`)
- `@SafeDIConfiguration` is always read from the current module only, never dependent modules

## Code Style

- **No abbreviations.** Use `dependency` not `dep`, `parameter` not `param`, `declaration` not `decl`. Everywhere: variables, functions, tests, comments, commits.
- **No `default` in switch statements.** Enumerate all cases explicitly for compile-time safety.
- **Use `for ... where` for simple boolean filters** instead of `guard ... else { continue }` inside the loop body.
- **Use `guard` for early exits**, not `if condition { continue/return }`.
- **No early return from bare `if`.** If an `if` branch returns, the non-returning path must be in an explicit `else` clause. Never fall through after `if { return }`.
- **Test names follow `method_expectation_conditionUnderTest`** pattern (e.g., `mock_disambiguatesAllParameters_whenThreeChildrenShareSameLabel`).

## Testing Philosophy

- **TDD**: Write failing tests first, then fix.
- **One assertion per test method.** Each test verifies one behavior.
- **Test through the pipeline**, not direct model construction. Mock tests use `executeSafeDIToolTest` which parses real Swift source through the full visitor → generator pipeline.
- **Full `==` output comparison.** Never use `.contains()` for mock output. Compare the complete expected string.
- **If code can't be covered by a test with real parsed input, remove the code.** Dead branches and defensive fallbacks for structurally unreachable paths should not exist.

## Common Pitfalls

- The input CSV written by plugins includes ALL swift files (target + dependencies). Mock scoping requires passing `mockScopedSwiftFiles` separately — only the target's own files.
- `Property.<` sort uses type as tiebreaker (not just label) for stable ordering.
- Extension-based `@Instantiable` types use `static func instantiate(...)` instead of `init(...)`. Their `@Instantiated` dependencies are constructed by the parent scope.
- When a received dependency is promoted to root scope, the producer branch must capture the root-bound value — not reconstruct the type.
- `resolvedParameters` flows through sibling accumulation AND parent-to-child descent. Both paths must be consistent.
