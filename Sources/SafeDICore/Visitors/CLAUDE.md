# Visitors

`FileVisitor` walks a file and evaluates `#if` blocks; `InstantiableVisitor` reads one `@Instantiable` declaration (for the macro and for `FileVisitor`); `SafeDIContentDetector` decides which blocks guard SafeDI content; `SafeDIConfigurationVisitor` reads `#SafeDIConfiguration`.
