# Shape D fixtures (seams, one per module)

Written by `Scripts/benchmark-2-3-1/make_fixtures.py` (function `shape_d`), the mock-overrides spike's `shape_d.py`
with `--walk`: screen `i` (layer `i / 4`) instantiates 3 of the 4 screens of the next layer; every screen is a public
seam (`generateDependencyTree: true`) in its own module `M<i>`, with a `Model<i>`; module `App` holds `Root`
(`isRoot: true, generateMock: true`), which instantiates screens 0–3, and `LiveApi`.

Layout (bench.py's): `<shape>/modules.txt` lists modules in build order with their direct dependencies; each module's
sources are in `<shape>/<Module>/`; `bench/` holds the runtime driver's file. Regenerate every shape with
`python3 -I Scripts/benchmark-2-3-1/make_fixtures.py OUTPUT`, or measure with
`Scripts/benchmark-2-3-1.sh --shapes D24 TOOL_A TOOL_B FIXTURES`.

`../D24-generated-main/` is main's (a6d44aff) `generate` output for D24, one `<Module>.gen.swift` per module, as
`generate --combined-output` wrote it with `--module-name`, `--package-name Benchmark`, the direct dependencies'
`.safedi` files and the transitive ones. `App.gen.swift` (10,933 lines) is the file whose `-Onone` compile exceeds an
11 GB address-space cap (Swift 6.2, Linux) at `swiftc -emit-object -wmo -parse-as-library -Onone -swift-version 6 -DDEBUG`.
