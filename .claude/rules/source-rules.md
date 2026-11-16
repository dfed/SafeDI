---
paths:
  - "Sources/**/*"
  - "Plugins/**/*"
  - "TuistPlugins/**/*"
---

<!-- Keep this file under 32,000 characters (Scripts/check-claude-instruction-files.sh): Claude truncates an on-demand file at 40,000. -->

# Source rules

`SourceRuleTests` fails on a trap in `Sources` or `Plugins` (a force unwrap, in an expression or a key path, an implicitly unwrapped optional or `init!`, `unsafelyUnwrapped`, `try!`, `as!`, `fatalError`, `precondition`, `preconditionFailure`, `assert`, `assertionFailure`, `Dictionary(uniqueKeysWithValues:)`, `Dictionary(dictionaryLiteral:)`, or a dictionary literal whose keys are not distinct literals), on `try?` under `Sources/SafeDICore/Generators`, on a trap spelled in a literal in `Sources` (`generatedTrap`: one of those five functions’ names or `unsafelyUnwrapped` as a whole word, `try!` or `as!`), on `__safeDI_` in a literal in `Sources` outside `ReservedName.swift`, on a lone backtick literal in `Sources` outside `IdentifierSpellingExtensions.swift`, on a straight apostrophe between letters in a literal in `Sources`, `Plugins` or `TuistPlugins`, and on an error type declared under `Sources/SafeDICore` that `ErrorReportingSite.byErrorType` does not list with the code that reports it. A safe site is waived by a comment on its line or on the lines just above it, `// safedi-source-rule: allow <rule> — <the invariant that makes it safe>`; a waiver that names no rule, gives no reason, or waives no site fails the test.
