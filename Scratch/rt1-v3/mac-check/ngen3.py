# ngen.py N FORM OUT : the N1 shape (benchmarks/e6/r209-scripts/shapes.py "n1"; layouts after rt1/scripts/make_dc_n1.py).
# Home (the seam) instantiates screen0..N-1 builders; Screen s forwards id, instantiates the hole api: any Api (filled by
# DefaultApi(), which reads nothing) and holds builders of screens s+1..s+3 (mod N). Walker after rt1/N1/N1-40-main.swift.
# FORMS: inline (proxy: the same per-type functions in App with no seam and no context, DefaultApi() in place; lane 6's
# global-bound variant ran 1.05x real inline), dc (RT1's measured layout), b1 (a level object per screen instantiation,
# holding id and the context, which the fill takes), cp (C').
import os, sys
n, form, out = int(sys.argv[1]), sys.argv[2], sys.argv[3]
os.makedirs(out + "/bench", exist_ok=True)
rec = lambda s: [(s + o) % n for o in (1, 2, 3)]
T = ["public final class Instantiator<T> { let build: (Int) -> T; public init(_ build: @escaping (Int) -> T) { self.build = build }; public func instantiate(_ id: Int) -> T { build(id) } }",
     "public protocol Api: AnyObject {}"]
for s in range(n):
    sp = ["id: Int", "api: any Api"] + [f"screen{o}Builder: Instantiator<Screen{o}>" for o in rec(s)]
    T.append(f"public final class Screen{s} {{ " + " ".join(f"public let {p};" for p in sp) + f" public init({', '.join(sp)}) {{ " + " ".join(f"self.{p.split(':')[0]} = {p.split(':')[0]};" for p in sp) + " } }")
hp = [f"screen{s}Builder: Instantiator<Screen{s}>" for s in range(n)]
T.append("public final class Home { " + " ".join(f"public let {p};" for p in hp) + f" public init({', '.join(hp)}) {{ " + " ".join(f"self.{p.split(':')[0]} = {p.split(':')[0]};" for p in hp) + " } }")
feature, app = [], ["import Feature", "", "final class DefaultApi: Api { init() {} }", ""]
ret = lambda s: f"    return Screen{s}(id: id, api: api, " + ", ".join(f"screen{o}Builder: screen{o}Builder" for o in rec(s)) + ")"
if form == "inline":
    for s in range(n):
        app.append(f"func screen{s}(id: Int) -> Screen{s} {{")
        app += [f"    let screen{o}Builder = Instantiator<Screen{o}> {{ screen{o}(id: $0) }}" for o in rec(s)]
        app += ["    let api: any Api = DefaultApi()", ret(s), "}"]
    app.append("func buildHome() -> Home { Home(" + ", ".join(f"screen{s}Builder: Instantiator<Screen{s}> {{ screen{s}(id: $0) }}" for s in range(n)) + ") }")
elif form in ("dc", "b1"):
    b1 = form == "b1"
    fill_t = "(__safeDI_Level) -> any Api" if b1 else "() -> any Api"
    feature += [f"final class __safeDI_Context {{ let apiFill: {fill_t}; init(apiFill: @escaping {fill_t}) {{ self.apiFill = apiFill }} }}", ""]
    if b1:
        feature += ["public final class __safeDI_Level { public let id: Int; let context: __safeDI_Context",
                    "    init(id: Int, context: __safeDI_Context) { self.id = id; self.context = context } }", ""]
    for s in range(n):
        if b1:
            feature += [f"func __safeDI_Screen{s}(_ context: __safeDI_Context, id: Int) -> Screen{s} {{",
                        "    let level = __safeDI_Level(id: id, context: context)"]
            feature += [f"    let screen{o}Builder = Instantiator<Screen{o}> {{ __safeDI_Screen{o}(level.context, id: $0) }}" for o in rec(s)]
            feature += ["    let api: any Api = context.apiFill(level)", ret(s), "}"]
        else:
            feature += [f"func __safeDI_Screen{s}(_ context: __safeDI_Context, id: Int) -> Screen{s} {{"]
            feature += [f"    let screen{o}Builder = Instantiator<Screen{o}> {{ __safeDI_Screen{o}(context, id: $0) }}" for o in rec(s)]
            feature += ["    let api: any Api = context.apiFill()", ret(s), "}"]
    feature += ["extension Home {", f"    public convenience init(__safeDI_apiFill: @escaping {fill_t}) {{", "        let context = __safeDI_Context(apiFill: __safeDI_apiFill)"]
    feature += [f"        let screen{s}Builder = Instantiator<Screen{s}> {{ __safeDI_Screen{s}(context, id: $0) }}" for s in range(n)]
    feature += ["        self.init(" + ", ".join(f"screen{s}Builder: screen{s}Builder" for s in range(n)) + ")", "    }", "}"]
    fill = "{ _ in DefaultApi() }" if b1 else "{ DefaultApi() }"
    app += [f"func buildHome() -> Home {{ let apiFill: {fill_t} = {fill}; return Home(__safeDI_apiFill: apiFill) }}"]
elif form in ("cp", "ccl"):
    F = "__safeDI_Home_Fills"
    feature += [f"open class {F} {{", "    public init() {}"]
    for s in range(n):
        feature.append(f"    open func enterScreen{s}(id: Int) -> {F} {{ " + ("fatalError()" if form == "ccl" else "self") + " }")
        feature.append(f"    open func apiOfScreen{s}(id: Int) -> any Api {{ fatalError(\"unfilled\") }}  // spike only")
    feature += ["}", ""]
    for s in range(n):
        feature += [f"func __safeDI_Screen{s}(_ fills: {F}, id: Int) -> Screen{s} {{", f"    let f = fills.enterScreen{s}(id: id)"]
        feature += [f"    let screen{o}Builder = Instantiator<Screen{o}> {{ __safeDI_Screen{o}(f, id: $0) }}" for o in rec(s)]
        feature += [f"    let api: any Api = f.apiOfScreen{s}(id: id)", ret(s), "}"]
    feature += ["extension Home {", f"    public convenience init(__safeDI_fills fills: {F}) {{"]
    feature += [f"        let screen{s}Builder = Instantiator<Screen{s}> {{ __safeDI_Screen{s}(fills, id: $0) }}" for s in range(n)]
    feature += ["        self.init(" + ", ".join(f"screen{s}Builder: screen{s}Builder" for s in range(n)) + ")", "    }", "}"]
    if form == "cp":
        app += [f"final class AppFills: {F} {{"] + [f"    override func apiOfScreen{s}(id: Int) -> any Api {{ DefaultApi() }}" for s in range(n)] + ["}"]
        app += ["func buildHome() -> Home { Home(__safeDI_fills: AppFills()) }"]
    else:
        app += ["enum StaticFills {"] + [f"    static func apiOfScreen{s}(id: Int) -> any Api {{ DefaultApi() }}" for s in range(n)] + ["}"]
        app += [f"nonisolated final class AppFills: {F} {{"] + [f"    let api{s}: (Int) -> any Api" for s in range(n)]
        app += ["    init(" + ", ".join(f"api{s}: @escaping (Int) -> any Api" for s in range(n)) + ") { " + " ".join(f"self.api{s} = api{s};" for s in range(n)) + " super.init() }"]
        app += [f"    override func apiOfScreen{s}(id: Int) -> any Api {{ api{s}(id) }}" for s in range(n)] + [f"    override func enterScreen{s}(id: Int) -> {F} {{ self }}" for s in range(n)] + ["}"]
        app += ["func buildHome() -> Home { Home(__safeDI_fills: AppFills(" + ", ".join(f"api{s}: {{ id in StaticFills.apiOfScreen{s}(id: id) }}" for s in range(n)) + ")) }"]
elif form in ("cbase", "plv", "clo", "clos"):
    # spec v3 forms. The parent's object enters the child inside the builder: Instantiator { id in screen(f.enterScreenO(id), id) }.
    if form == "cbase":
        feature += ["public protocol __safeDI_Home_Fills: AnyObject {"]
        for s in range(n):
            feature += [f"    func enterScreen{s}(id: Int) -> any __safeDI_Home_Fills", f"    func apiOfScreen{s}(id: Int) -> any Api"]
        feature += ["}"]
        PT = lambda s: "any __safeDI_Home_Fills"; RT = "any __safeDI_Home_Fills"
    elif form == "plv":
        feature += ["public protocol __safeDI_Home_HomeFills: AnyObject { " + " ".join(f"func enterScreen{s}(id: Int) -> any __safeDI_Home_Screen{s}Fills;" for s in range(n)) + " }"]
        for s in range(n):
            feature += [f"public protocol __safeDI_Home_Screen{s}Fills: AnyObject {{ func apiOfScreen{s}(id: Int) -> any Api; " + " ".join(f"func enterScreen{o}(id: Int) -> any __safeDI_Home_Screen{o}Fills;" for o in rec(s)) + " }"]
        PT = lambda s: f"any __safeDI_Home_Screen{s}Fills"; RT = "any __safeDI_Home_HomeFills"
    else:
        kind = "struct" if form == "clos" else "final class"
        def carrier(name, fields):
            return [f"public {kind} {name} {{ " + " ".join(f"let {fn}: {ft};" for fn, ft in fields) + f" public init({', '.join(f'{fn}: @escaping {ft}' for fn, ft in fields)}) {{ " + " ".join(f"self.{fn} = {fn};" for fn, _ in fields) + " } }"]
        feature += carrier("__safeDI_Home_Home", [(f"enterScreen{s}", f"(_ id: Int) -> __safeDI_Home_Screen{s}") for s in range(n)])
        for s in range(n):
            feature += carrier(f"__safeDI_Home_Screen{s}", [(f"apiOfScreen{s}", "(_ id: Int) -> any Api")] + [(f"enterScreen{o}", f"(_ id: Int) -> __safeDI_Home_Screen{o}") for o in rec(s)])
        PT = lambda s: f"__safeDI_Home_Screen{s}"; RT = "__safeDI_Home_Home"
    call = (lambda o: f"f.enterScreen{o}(id)") if form in ("clo", "clos") else (lambda o: f"f.enterScreen{o}(id: id)")
    api = (lambda s: f"f.apiOfScreen{s}(id)") if form in ("clo", "clos") else (lambda s: f"f.apiOfScreen{s}(id: id)")
    for s in range(n):
        feature += [f"func __safeDI_Screen{s}(_ f: {PT(s)}, id: Int) -> Screen{s} {{"]
        feature += [f"    let screen{o}Builder = Instantiator<Screen{o}> {{ id in __safeDI_Screen{o}({call(o)}, id: id) }}" for o in rec(s)]
        feature += [f"    let api: any Api = {api(s)}", ret(s), "}"]
    feature += ["extension Home {", f"    public convenience init(__safeDI_fills f: {RT}) {{"]
    feature += [f"        let screen{s}Builder = Instantiator<Screen{s}> {{ id in __safeDI_Screen{s}({call(s)}, id: id) }}" for s in range(n)]
    feature += ["        self.init(" + ", ".join(f"screen{s}Builder: screen{s}Builder" for s in range(n)) + ")", "    }", "}"]
    app += ["enum Fills {"] + [f"    static func apiOfScreen{s}(id: Int) -> any Api {{ DefaultApi() }}" for s in range(n)] + ["}"]
    if form == "cbase":
        app += ["class Base: __safeDI_Home_Fills {", "    init() {}"]
        for s in range(n):
            app += [f"    func enterScreen{s}(id: Int) -> any __safeDI_Home_Fills {{ fatalError() }}", f"    func apiOfScreen{s}(id: Int) -> any Api {{ fatalError() }}"]
        app += ["}", "final class AppFills: Base {"]
        for s in range(n):
            app += [f"    override func enterScreen{s}(id: Int) -> any __safeDI_Home_Fills {{ self }}", f"    override func apiOfScreen{s}(id: Int) -> any Api {{ Fills.apiOfScreen{s}(id: id) }}"]
        app += ["}", "func buildHome() -> Home { Home(__safeDI_fills: AppFills()) }"]
    elif form == "plv":
        app += ["final class AppFills: __safeDI_Home_HomeFills, " + ", ".join(f"__safeDI_Home_Screen{s}Fills" for s in range(n)) + " {"]
        for s in range(n):
            app += [f"    func enterScreen{s}(id: Int) -> any __safeDI_Home_Screen{s}Fills {{ self }}", f"    func apiOfScreen{s}(id: Int) -> any Api {{ Fills.apiOfScreen{s}(id: id) }}"]
        app += ["}", "func buildHome() -> Home { Home(__safeDI_fills: AppFills()) }"]
    else:
        for s in range(n):
            app += [f"func carrierScreen{s}() -> __safeDI_Home_Screen{s} {{ __safeDI_Home_Screen{s}(apiOfScreen{s}: {{ id in Fills.apiOfScreen{s}(id: id) }}, " + ", ".join(f"enterScreen{o}: {{ _ in carrierScreen{o}() }}" for o in rec(s)) + ") }"]
        app += ["func buildHome() -> Home { Home(__safeDI_fills: __safeDI_Home_Home(" + ", ".join(f"enterScreen{s}: {{ _ in carrierScreen{s}() }}" for s in range(n)) + ")) }"]
if form == "pcc":
    C = "__safeDI_Home_Fills"
    fl = []
    for s in range(n): fl += [(f"enterScreen{s}", f"((_ id: Int) -> {C})?"), (f"apiOfScreen{s}", "(_ id: Int) -> any Api")]
    feature += [f"public final class {C} {{ " + " ".join(f"let {a}: {t};" for a, t in fl) + f" public init({', '.join(f'{a}: ' + ('' if t.endswith('?') else '@escaping ') + t for a, t in fl)}) {{ " + " ".join(f"self.{a} = {a};" for a, _ in fl) + " } }"]
    for s in range(n):
        feature += [f"func __safeDI_Screen{s}(_ parent: {C}, id: Int) -> Screen{s} {{", f"    let f = parent.enterScreen{s}?(id) ?? parent"]
        feature += [f"    let screen{o}Builder = Instantiator<Screen{o}> {{ __safeDI_Screen{o}(f, id: $0) }}" for o in rec(s)]
        feature += [f"    let api: any Api = f.apiOfScreen{s}(id)", ret(s), "}"]
    feature += ["extension Home {", f"    public convenience init(__safeDI_fills f: {C}) {{"]
    feature += [f"        let screen{s}Builder = Instantiator<Screen{s}> {{ __safeDI_Screen{s}(f, id: $0) }}" for s in range(n)]
    feature += ["        self.init(" + ", ".join(f"screen{s}Builder: screen{s}Builder" for s in range(n)) + ")", "    }", "}"]
    app += ["enum Fills {"] + [f"    static func apiOfScreen{s}(id: Int) -> any Api {{ DefaultApi() }}" for s in range(n)] + ["}"]
    app += [f"func buildHome() -> Home {{ Home(__safeDI_fills: {C}(" + ", ".join(f"enterScreen{s}: nil, apiOfScreen{s}: {{ id in Fills.apiOfScreen{s}(id: id) }}" for s in range(n)) + ")) }"]
open(f"{out}/Types.swift", "w").write("\n".join(T) + "\n")
open(f"{out}/Feature.swift", "w").write("\n".join(feature) + "\n")
open(f"{out}/App.swift", "w").write("\n".join(app) + "\n")
w = ["import Foundation", "import Feature", "nonisolated(unsafe) var nextID = 0", "nonisolated(unsafe) var built = 0", "@inline(__always) func newID() -> Int { nextID &+= 1; return nextID }"]
for s in range(n):
    w.append(f"@inline(never) func walkReceived(_ v: Screen{s}) {{")
    w += [f"    let s{o} = v.screen{o}Builder.instantiate(newID()); built &+= 1; withExtendedLifetime(s{o}.api) {{}}" for o in rec(s)]
    w.append("}")
w.append("@inline(never) func walkAll() { let home = buildHome()")
w += [f"    do {{ let v = home.screen{s}Builder.instantiate(newID()); built &+= 1; withExtendedLifetime(v.api) {{}}; walkReceived(v) }}" for s in range(n)]
w += ["}", "walkAll(); let perWalk = built; built = 0", "var samples = [Double]()", f"let reps = {max(1, 40000 // (4 * n))}",
      "for _ in 0..<31 { let start = DispatchTime.now().uptimeNanoseconds; for _ in 0..<reps { walkAll() }; samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / Double(reps) / 1000) }",
      'samples.sort(); print(String(format: "median %.2f us per walk, %d values per walk", samples[15], perWalk))']
open(f"{out}/bench/main.swift", "w").write("\n".join(w) + "\n")
