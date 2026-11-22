# SafeDIToolTests

Tests of the tool itself; generation, mock, seam and fuzzer tests are in their own targets, and the shared helpers (`executeSafeDIToolTest`, the compile verifier, the graph fuzzer) in `Tests/SafeDIToolTestSupport`. `.claude/rules/test-infrastructure.md` says which target a test goes in and how fixtures are named; the root `CLAUDE.md` holds the rest of the testing rules.
