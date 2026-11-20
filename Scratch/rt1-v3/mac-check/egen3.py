# egen.py LAYERS FORM OUT : the E shape (E24 = 6 layers, E32 = 8), rebuilt from benchmarks/rt1/E24-dc: 4 screens per layer,
# screen i of a layer builds the other three screens of the next layer, each screen instantiates its Model, and the last
# layer's Models hold the hole `api: any Api`, which the app fills with LiveApi(id:service:). Home (the seam) receives
# `service` and instantiates layer 0's builders. Values per walk: E24 2,913, E32 26,241, as in the RT1 profile.
# FORMS: inline (no seam: nested closures per path, in App), dc (RT1's measured layout: per-type functions, one context,
# a flat fill taking what LiveApi reads), b1 (dc plus a level object per screen instantiation holding the values bound
# before its builders and its parent's object; the fill takes the level object), cp (C': one open fills class per seam).
import os, sys
L, form, out = int(sys.argv[1]), sys.argv[2], sys.argv[3]
N = 4 * L
os.makedirs(out + "/bench", exist_ok=True)
def layer(s): return s // 4
def children(s):
    l, i = divmod(s, 4)
    return [] if l == L - 1 else [4 * (l + 1) + j for j in range(4) if j != i]
last = lambda s: layer(s) == L - 1
T = ["public final class Instantiator<T> { let build: (Int) -> T; public init(_ build: @escaping (Int) -> T) { self.build = build }; public func instantiate(_ id: Int) -> T { build(id) } }",
     "public final class Service { public init() {} }", "public protocol Api: AnyObject {}"]
for s in range(N):
    mp = ["id: Int", "service: Service"] + (["api: any Api"] if last(s) else [])
    T.append(f"public final class Model{s} {{ " + " ".join(f"public let {p};" for p in mp) + f" public init({', '.join(mp)}) {{ " + " ".join(f"self.{p.split(':')[0]} = {p.split(':')[0]};" for p in mp) + " } }")
    sp = ["id: Int", "service: Service", f"model{s}: Model{s}"] + [f"screen{c}Builder: Instantiator<Screen{c}>" for c in children(s)]
    T.append(f"public final class Screen{s} {{ " + " ".join(f"public let {p};" for p in sp) + f" public init({', '.join(sp)}) {{ " + " ".join(f"self.{p.split(':')[0]} = {p.split(':')[0]};" for p in sp) + " } }")
hp = [f"screen{s}Builder: Instantiator<Screen{s}>" for s in range(4)]
T.append("public final class Home { " + " ".join(f"public let {p};" for p in hp) + f" public init({', '.join(hp)}) {{ " + " ".join(f"self.{p.split(':')[0]} = {p.split(':')[0]};" for p in hp) + " } }")
feature, app = [], ["import Feature", "", "final class LiveApi: Api { let id: Int; let service: Service; init(id: Int, service: Service) { self.id = id; self.service = service } }", ""]

def screen_args(s, ctx):
    return ", ".join([f"id: id", f"service: {ctx}", f"model{s}: model{s}"] + [f"screen{c}Builder: screen{c}Builder" for c in children(s)])

if form == "inline":
    def emit(s, ind):
        lines = [f"{ind}Instantiator<Screen{s}> {{ id in"]
        api = f", api: LiveApi(id: id, service: service)" if last(s) else ""
        lines.append(f"{ind}    let model{s} = Model{s}(id: id, service: service{api})")
        for c in children(s):
            inner = emit(c, ind + "    ")
            lines.append(f"{ind}    let screen{c}Builder = " + inner[0].lstrip()); lines += inner[1:]
        lines.append(f"{ind}    return Screen{s}({screen_args(s, 'service')})"); lines.append(f"{ind}}}")
        return lines
    app += ["func buildHome(_ service: Service) -> Home {"]
    for s in range(4):
        inner = emit(s, "    "); app.append(f"    let screen{s}Builder = " + inner[0].lstrip()); app += inner[1:]
    app += ["    return Home(" + ", ".join(f"screen{s}Builder: screen{s}Builder" for s in range(4)) + ")", "}"]
elif form in ("dc", "b1"):
    b1 = form == "b1"
    fill_t = "(__safeDI_Level) -> any Api" if b1 else "(Int, Service) -> any Api"
    feature += ["final class __safeDI_Context {", "    let service: Service", f"    let apiFill: {fill_t}",
                f"    init(service: Service, apiFill: @escaping {fill_t}) {{ self.service = service; self.apiFill = apiFill }}", "}", ""]
    if b1:
        # Generated-only and public: a public tier's fill names it. One base class so a level's parent can be any route's.
        feature += ["open class __safeDI_Level { public let id: Int; let context: __safeDI_Context; public let up: __safeDI_Level?",
                    "    init(id: Int, context: __safeDI_Context, up: __safeDI_Level?) { self.id = id; self.context = context; self.up = up } }", ""]
        for s in range(N):
            feature += [f"public final class __safeDI_Screen{s}_Level: __safeDI_Level {{ public let model{s}: Model{s}",
                        f"    init(id: Int, model{s}: Model{s}, context: __safeDI_Context, up: __safeDI_Level?) {{ self.model{s} = model{s}; super.init(id: id, context: context, up: up) }} }}", ""]
    for s in range(N):
        if b1:
            feature.append(f"func __safeDI_Screen{s}(_ up: __safeDI_Level?, _ context: __safeDI_Context, id: Int) -> Screen{s} {{")
            # The Model's hole is at this level; its fill gets the object of the level it is in, holding what is bound before it.
            # One object per level: where the hole sits (the last layer, no builders) it holds what is bound before the site.
            if last(s): feature.append(f"    let pre = __safeDI_Level(id: id, context: context, up: up)")
            api = ", api: context.apiFill(pre)" if last(s) else ""
            feature.append(f"    let model{s} = Model{s}(id: id, service: context.service{api})")
            if children(s):
                feature.append(f"    let level = __safeDI_Screen{s}_Level(id: id, model{s}: model{s}, context: context, up: up)")
            for c in children(s):
                feature.append(f"    let screen{c}Builder = Instantiator<Screen{c}> {{ __safeDI_Screen{c}(level, level.context, id: $0) }}")
        else:
            feature.append(f"func __safeDI_Screen{s}(_ context: __safeDI_Context, id: Int) -> Screen{s} {{")
            api = ", api: context.apiFill(id, context.service)" if last(s) else ""
            feature.append(f"    let model{s} = Model{s}(id: id, service: context.service{api})")
            for c in children(s):
                feature.append(f"    let screen{c}Builder = Instantiator<Screen{c}> {{ __safeDI_Screen{c}(context, id: $0) }}")
        feature += [f"    return Screen{s}({screen_args(s, 'context.service')})", "}", ""]
    feature += ["extension Home {", f"    public convenience init(__safeDI_service: Service, __safeDI_apiFill: @escaping {fill_t}) {{",
                "        let context = __safeDI_Context(service: __safeDI_service, apiFill: __safeDI_apiFill)"]
    feature += [f"        let screen{s}Builder = Instantiator<Screen{s}> {{ __safeDI_Screen{s}({'nil, ' if b1 else ''}context, id: $0) }}" for s in range(4)]
    feature += ["        self.init(" + ", ".join(f"screen{s}Builder: screen{s}Builder" for s in range(4)) + ")", "    }", "}"]
    fill = "{ level in LiveApi(id: level.id, service: service) }" if b1 else "{ id, service in LiveApi(id: id, service: service) }"
    app += ["func buildHome(_ service: Service) -> Home {", f"    let apiFill: {fill_t.replace('__safeDI_Level', '__safeDI_Level')} = {fill}",
            "    return Home(__safeDI_service: service, __safeDI_apiFill: apiFill)", "}"]
elif form in ("cp", "ccl"):
    # C': the seam's context holds the fills object its subtree uses; a level whose entry returned a new object gets a
    # new context holding it (an allocation only where the caller allocated). The caller's objects hold no seam context.
    F = "__safeDI_Home_Fills"
    feature += [f"final class __safeDI_Context {{ let service: Service; let fills: {F}; init(service: Service, fills: {F}) {{ self.service = service; self.fills = fills }} }}", "",
                f"open class {F} {{", "    public init() {}"]
    for s in range(N):
        feature.append(f"    open func enterScreen{s}(id: Int) -> {F} {{ " + ("fatalError()" if form == "ccl" else "self") + " }")
        if last(s): feature.append(f"    open func apiOfModel{s}(id: Int) -> any Api {{ fatalError(\"unfilled\") }}  // spike only")
    feature += ["}", ""]
    for s in range(N):
        feature += [f"func __safeDI_Screen{s}(_ context: __safeDI_Context, id: Int) -> Screen{s} {{",
                    f"    let f = context.fills.enterScreen{s}(id: id)"]
        api = f", api: f.apiOfModel{s}(id: id)" if last(s) else ""
        feature.append(f"    let model{s} = Model{s}(id: id, service: context.service{api})")
        if children(s):
            feature.append("    let sub = f === context.fills ? context : __safeDI_Context(service: context.service, fills: f)")
        for c in children(s):
            feature.append(f"    let screen{c}Builder = Instantiator<Screen{c}> {{ __safeDI_Screen{c}(sub, id: $0) }}")
        feature += [f"    return Screen{s}({screen_args(s, 'context.service')})", "}", ""]
    feature += ["extension Home {", f"    public convenience init(__safeDI_service: Service, __safeDI_fills fills: {F}) {{",
                "        let context = __safeDI_Context(service: __safeDI_service, fills: fills)"]
    feature += [f"        let screen{s}Builder = Instantiator<Screen{s}> {{ __safeDI_Screen{s}(context, id: $0) }}" for s in range(4)]
    feature += ["        self.init(" + ", ".join(f"screen{s}Builder: screen{s}Builder" for s in range(4)) + ")", "    }", "}"]
    if form == "cp":
        app += [f"final class AppFills: {F} {{", "    let service: Service", "    init(service: Service) { self.service = service }"]
        app += [f"    override func apiOfModel{s}(id: Int) -> any Api {{ LiveApi(id: id, service: service) }}" for s in range(N) if last(s)]
        app += ["}", "func buildHome(_ service: Service) -> Home { Home(__safeDI_service: service, __safeDI_fills: AppFills(service: service)) }"]
    else:
        lasts = [s for s in range(N) if last(s)]
        app += ["enum StaticFills {"] + [f"    static func apiOfModel{s}(id: Int, service: Service) -> any Api {{ LiveApi(id: id, service: service) }}" for s in lasts] + ["}"]
        app += [f"nonisolated final class AppFills: {F} {{"] + [f"    let api{s}: (Int) -> any Api" for s in lasts]
        app += ["    init(" + ", ".join(f"api{s}: @escaping (Int) -> any Api" for s in lasts) + ") { " + " ".join(f"self.api{s} = api{s};" for s in lasts) + " super.init() }"]
        app += [f"    override func apiOfModel{s}(id: Int) -> any Api {{ api{s}(id) }}" for s in lasts] + [f"    override func enterScreen{s}(id: Int) -> {F} {{ self }}" for s in range(N)] + ["}"]
        app += ["func buildHome(_ service: Service) -> Home { Home(__safeDI_service: service, __safeDI_fills: AppFills(" + ", ".join(f"api{s}: {{ id in StaticFills.apiOfModel{s}(id: id, service: service) }}" for s in lasts) + ")) }"]
elif form in ("clo", "clop"):
    # Closure carriers. clo: the caller forms a carrier at each entry. clop: the caller forms one carrier per type once,
    # where the carried set ({service}) is bound, and each entry returns the one already formed (acyclic shapes only).
    def carrier(name, fields):
        return [f"public final class {name} {{ " + " ".join(f"let {fn}: {ft};" for fn, ft in fields) + f" public init({', '.join(f'{fn}: @escaping {ft}' for fn, ft in fields)}) {{ " + " ".join(f"self.{fn} = {fn};" for fn, _ in fields) + " } }"]
    feature += carrier("__safeDI_Home_Home", [(f"enterScreen{s}", f"(_ id: Int) -> __safeDI_Home_Screen{s}") for s in range(4)])
    for s in range(N):
        fl = [(f"enterScreen{c}", f"(_ id: Int) -> __safeDI_Home_Screen{c}") for c in children(s)] + ([(f"apiOfModel{s}", "(_ id: Int) -> any Api")] if last(s) else [])
        feature += carrier(f"__safeDI_Home_Screen{s}", fl)
    feature += ["final class __safeDI_Context { let service: Service; init(service: Service) { self.service = service } }"]
    for s in range(N):
        feature += [f"func __safeDI_Screen{s}(_ context: __safeDI_Context, _ f: __safeDI_Home_Screen{s}, id: Int) -> Screen{s} {{"]
        api = f", api: f.apiOfModel{s}(id)" if last(s) else ""
        feature.append(f"    let model{s} = Model{s}(id: id, service: context.service{api})")
        for c in children(s):
            feature.append(f"    let screen{c}Builder = Instantiator<Screen{c}> {{ id in __safeDI_Screen{c}(context, f.enterScreen{c}(id), id: id) }}")
        feature += [f"    return Screen{s}({screen_args(s, 'context.service')})", "}"]
    feature += ["extension Home {", "    public convenience init(__safeDI_service: Service, __safeDI_fills f: __safeDI_Home_Home) {",
                "        let context = __safeDI_Context(service: __safeDI_service)"]
    feature += [f"        let screen{s}Builder = Instantiator<Screen{s}> {{ id in __safeDI_Screen{s}(context, f.enterScreen{s}(id), id: id) }}" for s in range(4)]
    feature += ["        self.init(" + ", ".join(f"screen{s}Builder: screen{s}Builder" for s in range(4)) + ")", "    }", "}"]
    app += ["enum Fills {"] + [f"    static func apiOfModel{s}(id: Int, service: Service) -> any Api {{ LiveApi(id: id, service: service) }}" for s in range(N) if last(s)] + ["}"]
    def fields(s, ref):
        fl = [f"enterScreen{c}: {{ _ in {ref(c)} }}" for c in children(s)]
        if last(s): fl.append(f"apiOfModel{s}: {{ id in Fills.apiOfModel{s}(id: id, service: service) }}")
        return ", ".join(fl)
    if form == "clo":
        for s in range(N):
            app += [f"func carrierScreen{s}(service: Service) -> __safeDI_Home_Screen{s} {{ __safeDI_Home_Screen{s}({fields(s, lambda c: f'carrierScreen{c}(service: service)')}) }}"]
        app += ["func buildHome(_ service: Service) -> Home { Home(__safeDI_service: service, __safeDI_fills: __safeDI_Home_Home(" + ", ".join(f"enterScreen{s}: {{ _ in carrierScreen{s}(service: service) }}" for s in range(4)) + ")) }"]
    else:
        app += ["func buildHome(_ service: Service) -> Home {"]
        for s in reversed(range(N)):
            app += [f"    let c{s} = __safeDI_Home_Screen{s}({fields(s, lambda c: f'c{c}')})"]
        app += ["    return Home(__safeDI_service: service, __safeDI_fills: __safeDI_Home_Home(" + ", ".join(f"enterScreen{s}: {{ _ in c{s} }}" for s in range(4)) + ")) }"]
elif form == "pcc":
    C = "__safeDI_Home_Fills"
    fl = []
    for s in range(N):
        fl.append((f"enterScreen{s}", f"((_ id: Int) -> {C})?"))
        if last(s): fl.append((f"apiOfModel{s}", "(_ id: Int) -> any Api"))
    feature += [f"public final class {C} {{ " + " ".join(f"let {a}: {t};" for a, t in fl) + f" public init({', '.join(f'{a}: ' + ('' if t.endswith('?') else '@escaping ') + t for a, t in fl)}) {{ " + " ".join(f"self.{a} = {a};" for a, _ in fl) + " } }"]
    feature += [f"final class __safeDI_Context {{ let service: Service; let fills: {C}; init(service: Service, fills: {C}) {{ self.service = service; self.fills = fills }} }}"]
    for s in range(N):
        feature += [f"func __safeDI_Screen{s}(_ context: __safeDI_Context, id: Int) -> Screen{s} {{", f"    let e = context.fills.enterScreen{s}?(id)"]
        api = f", api: (e ?? context.fills).apiOfModel{s}(id)" if last(s) else ""
        feature.append(f"    let model{s} = Model{s}(id: id, service: context.service{api})")
        if children(s): feature.append("    let sub = e.map { __safeDI_Context(service: context.service, fills: $0) } ?? context")
        for c in children(s):
            feature.append(f"    let screen{c}Builder = Instantiator<Screen{c}> {{ __safeDI_Screen{c}(sub, id: $0) }}")
        feature += [f"    return Screen{s}({screen_args(s, 'context.service')})", "}"]
    feature += ["extension Home {", f"    public convenience init(__safeDI_service: Service, __safeDI_fills fills: {C}) {{",
                "        let context = __safeDI_Context(service: __safeDI_service, fills: fills)"]
    feature += [f"        let screen{s}Builder = Instantiator<Screen{s}> {{ __safeDI_Screen{s}(context, id: $0) }}" for s in range(4)]
    feature += ["        self.init(" + ", ".join(f"screen{s}Builder: screen{s}Builder" for s in range(4)) + ")", "    }", "}"]
    app += ["enum Fills {"] + [f"    static func apiOfModel{s}(id: Int, service: Service) -> any Api {{ LiveApi(id: id, service: service) }}" for s in range(N) if last(s)] + ["}"]
    args = []
    for s in range(N):
        args.append(f"enterScreen{s}: nil")
        if last(s): args.append(f"apiOfModel{s}: {{ id in Fills.apiOfModel{s}(id: id, service: service) }}")
    app += [f"func buildHome(_ service: Service) -> Home {{ Home(__safeDI_service: service, __safeDI_fills: {C}(" + ", ".join(args) + ")) }"]
else:
    sys.exit("form?")
open(f"{out}/Types.swift", "w").write("\n".join(T) + "\n")
open(f"{out}/Feature.swift", "w").write("\n".join(feature) + "\n")
open(f"{out}/App.swift", "w").write("\n".join(app) + "\n")
# Walker: every path, touching each last-layer model's api.
w = ["import Foundation", "import Feature", "nonisolated(unsafe) var nextID = 0", "@inline(__always) func newID() -> Int { nextID &+= 1; return nextID }", "nonisolated(unsafe) var built = 0"]
for s in reversed(range(N)):
    body = [f"@inline(never) func walk{s}(_ v: Screen{s}) {{", "    built &+= 2"]
    if last(s): body.append(f"    withExtendedLifetime(v.model{s}.api) {{}}")
    body += [f"    walk{c}(v.screen{c}Builder.instantiate(newID()))" for c in children(s)]
    w += body + ["}"]
w += ["func walkAll() { let service = Service(); let home = buildHome(service)", *[f"    walk{s}(home.screen{s}Builder.instantiate(newID()))" for s in range(4)], "    withExtendedLifetime(service) {} }",
      "walkAll(); let perWalk = built + 1; built = 0",
      "var samples = [Double]()", f"let reps = {max(1, 2000 // (4 * 3 ** (L - 1)))}",
      "for _ in 0..<31 { let start = DispatchTime.now().uptimeNanoseconds; for _ in 0..<reps { walkAll() }; samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / Double(reps) / 1000) }",
      'samples.sort(); print(String(format: "median %.1f us per walk, %d values per walk", samples[15], perWalk))']
open(f"{out}/bench/main.swift", "w").write("\n".join(w) + "\n")
