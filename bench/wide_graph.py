"""python3 wide_graph.py OUT_DIR LAYERS [--cyclic] [--path-values] [--skip-layer] [--seed N]"""
import os, random, sys
out, layers = sys.argv[1], int(sys.argv[2])
cyclic, path_values, skip = "--cyclic" in sys.argv, "--path-values" in sys.argv, "--skip-layer" in sys.argv
seed = int(sys.argv[sys.argv.index("--seed") + 1]) if "--seed" in sys.argv else 1
rng, n = random.Random(seed * 1000 + layers), layers * 4
def kids(i):
    if cyclic: return sorted(rng.sample([j for j in range(n) if j != i], 3))
    if i // 4 >= layers - 1: return []
    result = rng.sample(range((i // 4 + 1) * 4, (i // 4 + 2) * 4), 3)
    if skip and i // 4 < layers - 2: result.append(rng.randrange((i // 4 + 2) * 4, (i // 4 + 3) * 4))
    return sorted(result)
children = {i: kids(i) for i in range(n)}
def ref(label, t):
    if t == "Int": return f"{label}=\\({label})"
    if t.endswith("?"): return f"{label}=\\({label}.map {{ \"#\\($0.oid)\" }} ?? \"nil\")"
    return f"{label}=#\\({label}.oid)"
def cls(attrs, name, props, walk=None):
    params = ", ".join(f"{l}: {t}" for _, l, t in props)
    body = "".join(f"        self.{l} = {l}\n" for _, l, _ in props)
    traced = " ".join(ref(l, t) for _, l, t in props if not t.startswith("Instantiator"))
    fields = "".join(f"    {a} let {l}: {t}\n" for a, l, t in props)
    s = (f"{attrs}\npublic final class {name}: Instantiable {{\n    public init({params}) {{\n{body}"
         f"        trace(\"+{name}#\\(oid) {traced}\")\n    }}\n{fields}"
         f"    let oid = nextObjectID()\n    deinit {{ trace(\"-{name}#\\(oid)\") }}\n")
    if walk is not None:
        calls = "".join(f"        {l}.instantiate(nextForwardedID()).walk(depth - 1)\n" for l in walk)
        s += f"    func walk(_ depth: Int) {{\n        guard depth > 0 else {{ return }}\n{calls}    }}\n"
    return s + "}\n\n"
src = "import SafeDI\n\n" + cls("@Instantiable", "Service", []) + cls("@Instantiable", "Session", [])
for i in range(n):
    props = [("@Forwarded", "id", "Int"), ("@Received", "service", "Service"), ("@Instantiated", "model", f"Model{i}")]
    # Odd layers declare `session`: layer 0 reads nil, and with --skip-layer or --cyclic one type reads nil on one path and a value on another.
    if path_values and (i // 4) % 2 == 1: props.append(("@Instantiated", "session", "Session"))
    props += [("@Instantiated", f"screen{c}Builder", f"Instantiator<Screen{c}>") for c in children[i]]
    src += cls("@Instantiable", f"Screen{i}", props, walk=[f"screen{c}Builder" for c in children[i]])
    model = [("@Received", "id", "Int"), ("@Received", "service", "Service")]
    if path_values: model.append(("@Received(onlyIfAvailable: true)", "session", "Session?"))
    src += cls("@Instantiable", f"Model{i}", model)
src += cls("@Instantiable(isRoot: true)", "Root",
           [("@Instantiated", "service", "Service")] + [("@Instantiated", f"screen{t}Builder", f"Instantiator<Screen{t}>") for t in range(4)],
           walk=[f"screen{t}Builder" for t in range(4)])
src += """nonisolated(unsafe) var traceLines = [String]()
nonisolated(unsafe) var objectCount = 0
nonisolated(unsafe) var forwardedCount = 0
func trace(_ line: @autoclosure () -> String) {
    #if !NO_TRACE
    traceLines.append(line())
    #endif
}
func nextObjectID() -> Int { objectCount += 1; return objectCount }
func nextForwardedID() -> Int { forwardedCount += 1; return forwardedCount }
"""
driver = """let depth = LAYERS
if let index = CommandLine.arguments.firstIndex(of: "--time"), let repeats = Int(CommandLine.arguments[index + 1]) {
    // Build with -Xswiftc -DNO_TRACE so that the figure measures construction, not tracing.
    let clock = ContinuousClock()
    var build = [Duration](), walk = [Duration]()
    for _ in 0..<repeats {
        var root: Root?
        build.append(clock.measure { root = Root() })
        walk.append(clock.measure { root?.walk(depth) })
        root = nil
    }
    print("build median \\(build.sorted()[repeats / 2]) walk median \\(walk.sorted()[repeats / 2]) objects \\(objectCount)")
} else {
    var root: Root? = Root()
    root?.walk(depth)
    root = nil
    trace("end")
    print(traceLines.joined(separator: "\\n"))
}
""".replace("LAYERS", str(layers + 1))
os.makedirs(out, exist_ok=True)
open(os.path.join(out, "Graph.swift"), "w").write(src)
open(os.path.join(out, "main.swift"), "w").write(driver)
open(os.path.join(out, "files.csv"), "w").write(os.path.abspath(os.path.join(out, "Graph.swift")))
