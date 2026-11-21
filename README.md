# Fixtures for #947's width sweep (scratch, no PR)

Two shapes, each one module named `App`:
- `fixtures/issue646-mock-12`: issue #646's graph at 12 screens with `generateMock: true`.
- `fixtures/N5im-8`: N5 inline with mocks, 8 layers.

Generate runs once per module, as the Bazel rule and the Tuist plugin run it. For each module, the command is:

```
SafeDITool generate OUT/App.csv \
  --combined-output OUT/App.generated.swift \
  --module-info-output OUT/App.safedi \
  --active-compilation-conditions DEBUG \
  --module-name App --package-name Bench
```

Here `App.csv` lists the module's `.swift` files, comma-separated and sorted, with absolute paths or paths relative to where you run it. For 2.2.0, drop `--module-name` and `--package-name`, which it doesn't have.

`measure.py` does all of that and prints wall time, CPU and max RSS. On macOS, `ru_maxrss` is in bytes, and the script handles that:

```
python3 measure.py PATH/TO/SafeDITool fixtures/issue646-mock-12 /tmp/out-mock12
python3 measure.py PATH/TO/SafeDITool fixtures/N5im-8 /tmp/out-n5im8
python3 measure.py PATH/TO/SafeDITool-2.2.0,legacy fixtures/N5im-8 /tmp/out-220   # 2.2.0: ",legacy" drops the two flags
```

The width is `BoundedConcurrency.mockRootWidth` in `Sources/SafeDICore/Generators/BoundedConcurrency.swift` (4 on #947's head). Linux medians on 4 vCPUs, 7 rotated rounds:

| roots at once | mock-12 wall | mock-12 max RSS |
|---|---|---|
| 1 | 8.37 s | 275 MB |
| 2 | 6.58 s | 304 MB |
| 4 | 5.60 s | 326 MB |
| 2.2.0 | 4.78–5.23 s | 335 MB |
| main (020a364e) | 5.37 s | 526 MB |
