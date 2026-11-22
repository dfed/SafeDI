# Compile time of generated code (scratch, not for merging)

```bash
# fixtures
bash .claude/skills/generate-benchmark/make_fixtures.sh ~/ct-fixtures
# SafeDI runtime and macros, release (any checkout; the runtime is the same on main and #930)
swift build -c release --product SafeDI --scratch-path ~/ct-build   # macOS: ~/ct-build/arm64-apple-macosx/release
# each tool: a release SafeDITool of main and of #930's head
python3 Scratch/compile-time/compile_time.py MAIN_TOOL ~/ct-build/release ~/ct-fixtures issue646-16 ~/ct-out/main/issue646-16 3
python3 Scratch/compile-time/compile_time.py PR930_TOOL ~/ct-build/release ~/ct-fixtures issue646-16 ~/ct-out/930/issue646-16 3
```

The swiftc command per module (from the script):
`swiftc -O -wmo -parse-as-library -module-name M -I BUILD/Modules -I OUT -load-plugin-executable BUILD/SafeDIMacros-tool#SafeDIMacros -emit-module -emit-module-path OUT/M.swiftmodule -c -o OUT/M.o <fixture sources> OUT/M.generated.swift`

Linux results (Swift 6.2, 4 cores; main 020a364e vs #930 07fee3de, whose output 4b509468 matches), App module:

| shape | lines main → #930 | swiftc median main → #930 |
|---|---|---|
| issue646-16 | 114,024 → 203 | 103.7 s → 0.36 s |
| issue646-12 | 5,311 → 165 | 3.33 s → 0.32 s |
| N5inline-8 | 126,849 → 425 | 89.5 s → 1.05 s (1 run) |
| N5inline-10 | 1,141,617 → 529 | 1,159 s → 1.1 s (1 run) |
| E6d-600-inline | 3,615 (identical) | 9.6 s vs 10.1 s |
| E6d-1200-inline | 7,215 (identical) | 41.2 s vs 42.0 s |
