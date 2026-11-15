"""python3 shape_d.py <SafeDITool> <screens, a multiple of 4> [--walk] [--trace]
Shape D: layered screens, each a public seam in its own module; App's Root mock inlines them all.
--walk: every init calls each of its builders once (id * 4 + k), so one Root.mock() builds the whole tree.
--trace (implies --walk): every type with an id logs "<Type> <id>" to Trace.lines as it is built.
Neither flag changes any generated file: only init bodies and Core's Trace enum differ.
Always writes App's Driver.swift: `layout`, `stack`, `time [calls]`, and with --trace `trace` and `trace-overrides`."""
import os, random, re, subprocess, sys, time
tool, n, trace = sys.argv[1], int(sys.argv[2]), "--trace" in sys.argv
walk = trace or "--walk" in sys.argv
rng, d = random.Random(1000 + n * 10 + 3), os.path.abspath(f"out-D-{n}"); os.makedirs(d, exist_ok=True)
def walk_lines(ps):
    base = "id" if any(l == "id" for _, l, _ in ps) else "0"
    builders = [l for _, l, t in ps if t.startswith("Instantiator<")]
    return [f"_ = {l}.instantiate({base} * 4 + {k + 1})" for k, l in enumerate(builders)] if walk else []
def decl(attr, name, sup, init, ps, acc="public"):
    log = [f'Trace.log("{name}", id)'] if trace and any(l == "id" for _, l, _ in ps) else []
    return (f"{attr} {acc} final class {name}: {sup}Instantiable {{ {init} init({', '.join(f'{l}: {t}' for _, l, t in ps)}) {{ "
            + "; ".join([f"self.{l} = {l}" for _, l, _ in ps] + log + walk_lines(ps) + ["super.init()"] * bool(sup)) + " }\n" + "".join(f"    {a} let {l}: {t}\n" for a, l, t in ps) + "}\n")
# Screen i (layer i//4) instantiates 3 of the 4 screens in the next layer; the last layer instantiates none.
E = {i: sorted(rng.sample(range((i//4+1)*4, (i//4+2)*4), 3)) if i//4 < n//4-1 else [] for i in range(n)}
plain = lambda c: ("@Instantiated", f"screen{c}Builder", f"Instantiator<Screen{c}>")
core = "@Instantiable public final class Service: Instantiable { public init() {} }\nopen class Screen { public init() {} }\npublic protocol Api {}\n"
if trace: core += "public enum Trace { nonisolated(unsafe) public static var lines: [String] = []; public static func log(_ t: String, _ id: Int) { lines.append(\"\\(t) \\(id)\") } }\n"
M = [("Core", [], core)]
for i in sorted(E, reverse=True):
    ps = [("@Forwarded", "id", "Int"), ("@Received", "service", "Service"), ("@Instantiated", f"model{i}", f"Model{i}")] + [plain(c) for c in E[i]]
    s = decl("@Instantiable(generateDependencyTree: true)", f"Screen{i}", "Screen, ", "public", ps)
    s += decl("@Instantiable", f"Model{i}", "", "public", [("@Received", "id", "Int"), ("@Received", "service", "Service")], "public")
    M.append((f"M{i}", ["Core"] + [f"M{c}" for c in E[i]], s))
M.append(("App", [m for m, _, _ in M], "@Instantiable(fulfillingAdditionalTypes: [Api.self]) final class LiveApi: Api, Instantiable { init() {} }\n"
          + decl("@Instantiable(isRoot: true, generateMock: true)", "Root", "", "", [("@Instantiated", "service", "Service")] + [plain(i) for i in range(4)])))
deps = {m: x for m, x, _ in M}
def below(m): return sorted({y for x in deps[m] for y in [x] + below(x)})
for m, _, src in M:
    p = f"{d}/{m}"
    open(p + ".swift", "w").write("import SafeDI\n" + "".join(f"import {x}\n" for x in below(m)) + src)
    open(p + ".csv", "w").write(p + ".swift"); open(p + ".deps", "w").write(",".join(f"{d}/{x}.safedi" for x in below(m)))
    t = time.time()
    subprocess.run([tool, "generate", p + ".csv", "--combined-output", p + ".gen.swift", "--module-info-output", p + ".safedi", "--module-name", m,
                    "--package-name", "p" + m, "--dependent-module-info-file-path", p + ".deps", "--active-compilation-conditions", "DEBUG"], check=True)
    if m == "App": print(m, open(p + ".gen.swift").read().count("\n"), "lines", f"{time.time()-t:.2f} s generate")
if trace:  # Overrides for `trace-overrides`: a logging safeDIBuilder at fixed places, each building its screen normally.
    paths = [(r,) for r in range(4)]
    for p in paths: paths.extend(p + (c,) for c in E[p[-1]])  # every root-to-screen path, breadth first
    pick = random.Random(7).sample(paths, min(24, len(paths) // 2))
    shared = next(s for s in range(n) if sum(p[-1] == s for p in paths) >= 3)  # a screen three or more paths reach
    pick = [p for p in pick if p[-1] != shared] + [random.Random(8).choice([p for p in paths if p[-1] == shared])]
    lab = lambda s: f"screen{s}Builder"
    def config(p):
        s, args = p[-1], [f"{lab(c)}: {config(p + (c,))}" for c in E[p[-1]] if any(q[:len(p) + 1] == p + (c,) for q in pick)]
        if p in pick:
            bs = [f"b{c}" for c in E[s]]
            args.append("{ " + ", ".join(["id", "service", "model"] + bs) + f' in Trace.log("override {".".join(map(lab, p))}", id); return Screen{s}('
                        + ", ".join(["id: id", "service: service", f"model{s}: model"] + [f"{lab(c)}: b{c}" for c in E[s]]) + ") }")
        return ".init(" + ", ".join(args) + ")"
    root = [f"{lab(r)}: {config((r,))}" for r in range(4) if any(q[0] == r for q in pick)]
    overrides = "extension Driver { static var overrides: Root.SafeDIOverrides { .init(" + ", ".join(root) + ") } }\n"
    print("overrides at", len(pick), "places; screen", shared, "is reached by", sum(p[-1] == shared for p in paths), "paths and overridden on one")
# App's driver, Driver.swift: compile it into App only for runs, never for App's compile timings. It is not part of generate's input.
open(f"{d}/Driver.swift", "w").write("import Foundation\nimport SafeDI\n" + "".join(f"import {x}\n" for x in below("App")) + """#if DEBUG
@main enum Driver {
    nonisolated(unsafe) static var sink: AnyObject?
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        switch arguments.first ?? "time" {
        case "stack":  // one Root.mock() on a thread with a 512 KB stack
            let done = DispatchSemaphore(value: 0)
            let thread = Thread { sink = Root.mock(); print("stack ok"); done.signal() }
            thread.stackSize = 512 * 1024; thread.start(); done.wait()
        case "layout": print("MemoryLayout<Root.SafeDIOverrides>.size", MemoryLayout<Root.SafeDIOverrides>.size)
        case "time":  // median, min and max of N Root.mock() calls (the whole tree under --walk)
            let calls = arguments.count > 1 ? Int(arguments[1]) ?? 100 : 100
            var samples = [UInt64]()
            for _ in 0..<calls { let start = DispatchTime.now().uptimeNanoseconds; sink = Root.mock(); samples.append(DispatchTime.now().uptimeNanoseconds - start) }
            samples.sort(); print("ns median", samples[samples.count / 2], "min", samples[0], "max", samples[samples.count - 1])
""" + ('        case "trace-overrides":  // the same with the overrides below\n            sink = Root.mock(safeDIOverrides: overrides); print(Trace.lines.joined(separator: "\\n"))\n' if trace else "") + ('        case "trace":  // one Root.mock(), then every logged line\n            sink = Root.mock(); print(Trace.lines.joined(separator: "\\n"))\n' if trace else "") + """        default:
            print("usage: layout | stack | time [calls] | trace | trace-overrides (the last two with --trace)")
        }
    }
}
""" + (overrides if trace else "") + "#endif\n")
