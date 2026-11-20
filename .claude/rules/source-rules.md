---
paths:
  - "Sources/**/*"
  - "Plugins/**/*"
  - "TuistPlugins/**/*"
  - "Tests/SafeDIToolTestSupport/**/*"
---

<!-- Keep this file under 32,000 characters (Scripts/check-claude-instruction-files.sh): Claude truncates an on-demand file at 40,000. -->

# Source rules

`SourceRuleTests` fails on a trap in `Sources` or `Plugins` (a force unwrap, in an expression or a key path, an implicitly unwrapped optional or `init!`, `unsafelyUnwrapped`, `try!`, `as!`, `fatalError`, `precondition`, `preconditionFailure`, `assert`, `assertionFailure`, `Dictionary(uniqueKeysWithValues:)`, `Dictionary(dictionaryLiteral:)`, or a dictionary literal whose keys are not distinct literals), on `try?` under `Sources/SafeDICore/Generators`, on a trap spelled in a literal in `Sources` (`generatedTrap`: one of those five functions’ names or `unsafelyUnwrapped` as a whole word, `try!` or `as!`), on `__safeDI_` in a literal in `Sources` outside `ReservedName.swift`, on a lone backtick literal in `Sources` outside `IdentifierSpellingExtensions.swift`, on a straight apostrophe between letters in a literal in `Sources`, `Plugins` or `TuistPlugins`, on an error type declared under `Sources/SafeDICore` that `ErrorReportingSite.byErrorType` does not list with the code that reports it, on an `async` function or `async` accessor of an actor under `Sources/SafeDICore` that assigns a stored property of that actor (`ActorStateRuleCheck`, matched by what an assignment assigns, with the bindings in scope, never by a property's name; every actor but `ScopeGenerator`, which `actorsNotYetCovered` lists with its reason; no waiver lifts it, since a value computed once is a local handed down, as "One driver builds each layer once" in `generator-design.md` says), and on a `@testable import` in `Tests/SafeDIToolTestSupport` (`testableImport`), a regular target that a plain `swift build` of the package builds in release without `-enable-testing`, which rejects the import: a helper imports `SafeDIToolLibrary` plainly and makes `public` the declarations it needs. The rule finds `@testable` anywhere in an import’s attributes, inside `#if` too, and reports it at the line of the `import` keyword, so a waiver of it goes at the end of that line. A safe site is waived by a comment on its line or on the lines just above it, `// safedi-source-rule: allow <rule> — <the invariant that makes it safe>`; a waiver that names no rule, gives no reason, or waives no site fails the test.
