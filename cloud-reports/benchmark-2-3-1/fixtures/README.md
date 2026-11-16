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

# Shape E fixtures (spike 2's growth shape)

`E<n>-inline` and `E<n>-seam` come from `make_fixtures.py`'s `spike2()`, which runs spike 2's `spec_e.py` and `emit.py`
(vendored unchanged in `Scripts/benchmark-2-3-1/spike2/`): `Home` instantiates screens 0–3; screen `i` (layer `i / 4`)
instantiates the 3 screens of the next layer other than `4·(layer+1) + i mod 4`, a `Model<i>`, and the last layer's
models hold the hole `any Api`, filled by `LiveApi` in `App`. Depth is n / 4, so paths grow 3^depth. `-inline` builds
everything in module `App`; `-seam` makes `Home` a seam in module `Feature` (with
`generatePlainDependencyTreeInitializers: true`), and `App` fills the hole. `Harness` is a stand-in module, and `bench/`
holds the walker for the runtime measure.
