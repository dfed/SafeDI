# An index-out-of-range trap in the fuzzer harness, not in SafeDI

During the combination draws' development, a run of seam combination seeds `0..<90` stopped with `Fatal error: Index out of range`. The trace first saved (`misread-trace.txt`) appeared to put the trap in `DependencyTreeGenerator.shapedBuilders` (`SeamBuilderFamilies.swift:279`). That reading was wrong: the trace was filtered for frames in SafeDI's sources, and the frames it kept belong to another thread, which was generating code when the process stopped.

## Reproduction

The test-support code of that run was rebuilt from the session's edits on top of base `307019f8`. Its fixture hash, `0xBA29E644A87AFAB6`, is the one the original run reported.

- Seeds `0..<90` with compile checks trapped in 3 of 3 runs, each in its own process.
- With `SAFEDI_SKIP_COMPILE_CHECK=1` they did not trap, since the tool run that traps is the inline build, which only the value oracle asks for.
- Alone, with compile checks, seeds 15, 16 and 17 trap. Those are the `actorIsolation` cell at a place inside a fill (`AtBoundary`, `Beneath`, `InsideFill`).

## The crashed thread

`crashed-thread-seed15.txt` holds the crashed thread. The trap is in `GraphFuzzerOracle.splitToolOutcome`, test-support code:

```swift
swiftFileContentByFilePath: Dictionary(uniqueKeysWithValues: modules.indices.filter { modules[$0] == module }.map { (fileNames[$0], fixture.swiftFileContent[$0]) }),
```

The draw wrote `@Instantiable` on the line before `@MainActor`. `GraphFuzzerFixture.fileNames` uses a `compactMap`, which silently dropped the file it could not name. That left `fileNames` one entry shorter than `modules`, so `fileNames[$0]` read past the end.

The draw now writes `@MainActor` first, as the rest of the fuzzer does. With only that line changed back in the rebuilt code, seeds 15, 16 and 17 pass.

## What was ruled out

No SafeDI code under `Sources/` or `Plugins/` trapped, and `SeamBuilderFamilies.swift:279` is not involved. The whole seam combination corpus has since run without a trap: 1,350 seeds, several times.

## The harness fix

`GraphFuzzerFixture.fileNames` now names each file as `executeSafeDIToolTest` writes it: by its `// file: ` line, else the type after its `@Instantiable` attribute (whatever attribute lies between), else its first type. A file that declares no type, which the harness would write as `File.swift`, is reported with an infrastructure error that quotes its first lines, never left out. `filesByName` pairs names with files only when the counts match and no two files share a name, so `splitToolOutcome` cannot index out of range. `GraphFuzzerFileNameTests` covers an `@Instantiable` written above `@MainActor` (named after its type), the same file in a split graph (which trapped before the fix), a file that declares no type, alone and in a split graph, and a split graph given too few names.
