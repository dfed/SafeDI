# Visitors

`FileVisitor` walks a file and evaluates `#if` blocks; `InstantiableVisitor` reads one `@Instantiable` declaration (for the macro and for `FileVisitor`); `SafeDIContentDetector` decides which blocks guard SafeDI content; `SafeDIConfigurationVisitor` reads `#SafeDIConfiguration`. Rules: `.claude/rules/conditional-compilation.md` (any state collected inside an `#if` block) and `.claude/rules/validation-boundaries.md` (what the macro checks).
