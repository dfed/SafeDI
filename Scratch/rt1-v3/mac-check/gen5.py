# gen5.py SHAPE SIZE HOLES MODE FORM OUT -- the decisive C experiment's tree cells (2026-11-20, D4-TRAJECTORY-STOP-CCL).
# SHAPE n1 (SIZE screens) or e (SIZE layers: 6 = E24, 8 = E32). HOLES per hole site: 1, or 3 (multi-member carriers).
# n1 with HOLES 1 is the canonical N1 (the fill reads nothing). n1 with HOLES 3: each screen has 3 holes whose fills read
# the screen's id and `service`, a value only the caller has. e: the last layer's Models hold HOLES holes whose fills read
# id and `service` (which the caller passes the seam, and the seam also uses).
# MODE plain (Instantiator everywhere) or S (SendableInstantiator everywhere: every place is under @Sendable).
# FORMS:
#   inline  no seam (2.2.0's form): n1 per-type functions; e nested closures.
#   ccl     spec v3.1 (plain only): seam `open class` with trapping bases; caller `nonisolated final class` zone that
#           stores the carried values and non-capturing closures; entries keep `self` (the carried set never changes).
#   C       the trajectory candidate: per place type a seam-declared `final class` carrier of required closures the caller
#           forms. Fill members take the level's values; entry members form the child type's carrier. Each closure
#           captures at most one reference: the caller's context for its carried set (nothing when the set is empty).
#           The seam's builder captures one word: the carrier itself where the seam passes nothing else down, else the
#           seam's per-level context, which holds the carrier as a `let`. Child carriers are formed per entry, inside
#           the builder. MODE S makes the carriers, contexts and closures the Sendable family's.
import os, sys
shape, size, H, mode, form, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5], sys.argv[6]
once = len(sys.argv) > 7 and sys.argv[7] == "once"   # build the host once, outside the timed walks
os.makedirs(out + "/bench", exist_ok=True)
assert form in ("inline", "ccl", "C", "Cf", "Cx") and (form != "ccl" or mode == "plain")
E = shape == "e"
if E:
    L = size; N = 4 * L
    def kids(s):
        l, i = divmod(s, 4)
        return [] if l == L - 1 else [4 * (l + 1) + j for j in range(4) if j != i]
    roots = list(range(4)); holes = {s for s in range(N) if s // 4 == L - 1}
else:
    N = size
    kids = lambda s: [(s + o) % N for o in (1, 2, 3)]
    roots = list(range(N)); holes = set(range(N))
reads_service = E or H > 1          # the fill reads `service` (carried from the caller's root)
seam_service = E                    # the seam itself receives and uses `service`
S = mode == "S"
BT = (lambda o: f"SendableInstantiator<Screen{o}>") if S else (lambda o: f"Instantiator<Screen{o}>")
SA = "@Sendable " if S else ""
SN = ": Sendable" if S else ""
HS = [f"api{j}" for j in range(H)]
PT = lambda j: f"Api{j}"

T = ["public final class Instantiator<T> { let build: (Int) -> T; public init(_ build: @escaping (Int) -> T) { self.build = build }; public func instantiate(_ id: Int) -> T { build(id) } }",
     "public final class SendableInstantiator<T>: Sendable { let build: @Sendable (Int) -> T; public init(_ build: @escaping @Sendable (Int) -> T) { self.build = build }; public func instantiate(_ id: Int) -> T { build(id) } }",
     "public final class Service: Sendable { public init() {} }"] + [f"public protocol {PT(j)}: AnyObject {{}}" for j in range(H)]
def cls(name, ps):
    return f"public final class {name} {{ " + " ".join(f"public let {p};" for p in ps) + f" public init({', '.join(ps)}) {{ " + " ".join(f"self.{p.split(':')[0]} = {p.split(':')[0]};" for p in ps) + " } }"
holeps = [f"{h}: any {PT(j)}" for j, h in enumerate(HS)]
for s in range(N):
    bs = [f"screen{o}Builder: {BT(o)}" for o in kids(s)]
    if E:
        T.append(cls(f"Model{s}", ["id: Int", "service: Service"] + (holeps if s in holes else [])))
        T.append(cls(f"Screen{s}", ["id: Int", "service: Service", f"model{s}: Model{s}"] + bs))
    else:
        T.append(cls(f"Screen{s}", ["id: Int"] + holeps + bs))
T.append(cls("Home", [f"screen{s}Builder: {BT(s)}" for s in roots]))

feature, app = [], ["import Feature", ""]
for j in range(H):
    if reads_service:
        app.append(f"final class Live{j}: {PT(j)} {{ let id: Int; let service: Service; init(id: Int, service: Service) {{ self.id = id; self.service = service }} }}")
    else:
        app.append(f"final class Live{j}: {PT(j)} {{ init() {{}} }}")
fargs = "id: Int, service: Service" if reads_service else "id: Int"
fbody = (lambda j: f"Live{j}(id: id, service: service)") if reads_service else (lambda j: f"Live{j}()")
app += ["enum Fills {"] + [f"    static func {h}Of{s}({fargs}) -> any {PT(j)} {{ {fbody(j)} }}" for s in sorted(holes) for j, h in enumerate(HS)] + ["}"]
fcall = (lambda s, h: f"Fills.{h}Of{s}(id: id, service: service)") if reads_service else (lambda s, h: f"Fills.{h}Of{s}(id: id)")

def ret(s):
    args = ["id: id"] + (["service: service", f"model{s}: model{s}"] if E else [f"{h}: {h}" for h in HS]) + [f"screen{o}Builder: screen{o}Builder" for o in kids(s)]
    return f"    return Screen{s}({', '.join(args)})"
def values(s, hexpr):
    if E:
        return [f"    let model{s} = Model{s}(id: id, service: service" + "".join(f", {h}: {hexpr(h)}" for h in HS if s in holes) + ")"]
    return [f"    let {h}: any {PT(j)} = {hexpr(h)}" for j, h in enumerate(HS)]

if form == "inline":
    if E:
        def emit(s, ind):
            lines = [f"{ind}{BT(s)} {{ id in"] + [ind + l for l in values(s, lambda h: fcall(s, h))]
            for c in kids(s):
                inner = emit(c, ind + "    ")
                lines.append(f"{ind}    let screen{c}Builder = " + inner[0].lstrip()); lines += inner[1:]
            return lines + [ind + ret(s), f"{ind}}}"]
        app.append("func buildHome(_ service: Service) -> Home {")
        for s in roots:
            inner = emit(s, "    "); app.append(f"    let screen{s}Builder = " + inner[0].lstrip()); app += inner[1:]
        app += ["    return Home(" + ", ".join(f"screen{s}Builder: screen{s}Builder" for s in roots) + ")", "}"]
    else:
        sv = ", service: Service" if reads_service else ""; sa = ", service: service" if reads_service else ""
        for s in range(N):
            app.append(f"func screen{s}(id: Int{sv}) -> Screen{s} {{")
            app += values(s, lambda h: fcall(s, h))
            app += [f"    let screen{o}Builder = {BT(o)} {{ screen{o}(id: $0{sa}) }}" for o in kids(s)]
            app += [ret(s), "}"]
        app.append(f"func buildHome({'_ service: Service' if reads_service else ''}) -> Home {{ Home(" + ", ".join(f"screen{s}Builder: {BT(s)} {{ screen{s}(id: $0{sa}) }}" for s in roots) + ") }")

elif form == "ccl":
    F = "__safeDI_Home_Fills"
    feature += [f"open class {F} {{", "    public init() {}"]
    for s in range(N):
        feature.append(f"    open func enterScreen{s}(id: Int) -> {F} {{ fatalError(\"SafeDI: unentered\") }}")
        if s in holes:
            feature += [f"    open func {h}Of{s}(id: Int) -> any {PT(j)} {{ fatalError(\"SafeDI: unfilled\") }}" for j, h in enumerate(HS)]
    feature.append("}")
    if E:
        feature.append(f"final class __safeDI_Context {{ let service: Service; let fills: {F}; init(service: Service, fills: {F}) {{ self.service = service; self.fills = fills }} }}")
    for s in range(N):
        if E:
            feature += [f"func __safeDI_Screen{s}(_ context: __safeDI_Context, id: Int) -> Screen{s} {{", f"    let f = context.fills.enterScreen{s}(id: id)", "    let service = context.service"]
        else:
            feature += [f"func __safeDI_Screen{s}(_ fills: {F}, id: Int) -> Screen{s} {{", f"    let f = fills.enterScreen{s}(id: id)"]
        feature += values(s, lambda h: f"f.{h}Of{s}(id: id)")
        if E and kids(s):
            feature.append("    let sub = f === context.fills ? context : __safeDI_Context(service: service, fills: f)")
        feature += [f"    let screen{o}Builder = {BT(o)} {{ __safeDI_Screen{o}({'sub' if E else 'f'}, id: $0) }}" for o in kids(s)]
        feature += [ret(s), "}"]
    feature += ["extension Home {", f"    public convenience init({'__safeDI_service service: Service, ' if E else ''}__safeDI_fills fills: {F}) {{"]
    if E: feature.append("        let context = __safeDI_Context(service: service, fills: fills)")
    feature += [f"        let screen{s}Builder = {BT(s)} {{ __safeDI_Screen{s}({'context' if E else 'fills'}, id: $0) }}" for s in roots]
    feature += ["        self.init(" + ", ".join(f"screen{s}Builder: screen{s}Builder" for s in roots) + ")", "    }", "}"]
    CT = lambda j: f"(Int, Service) -> any {PT(j)}" if reads_service else f"(Int) -> any {PT(j)}"
    flds = ([("service", "Service")] if reads_service else []) + [(f"{h}{s}", CT(j)) for s in sorted(holes) for j, h in enumerate(HS)]
    app.append(f"nonisolated final class AppFills: {F} {{")
    app += [f"    let {a}: {t}" for a, t in flds]
    app.append("    init(" + ", ".join(f"{a}: " + ("@escaping " if "->" in t else "") + t for a, t in flds) + ") { " + " ".join(f"self.{a} = {a};" for a, _ in flds) + " super.init() }")
    app += [f"    override func {h}Of{s}(id: Int) -> any {PT(j)} {{ {h}{s}(id" + (", service" if reads_service else "") + ") }" for s in sorted(holes) for j, h in enumerate(HS)]
    app += [f"    override func enterScreen{s}(id: Int) -> {F} {{ self }}" for s in range(N)]
    app.append("}")
    clos = ", ".join(f"{h}{s}: {{ id" + (", service" if reads_service else "") + f" in {fcall(s, h)} }}" for s in sorted(holes) for j, h in enumerate(HS))
    args = ("service: service, " if reads_service else "") + clos
    if E:
        app.append(f"func buildHome(_ service: Service) -> Home {{ Home(__safeDI_service: service, __safeDI_fills: AppFills({args})) }}")
    else:
        app.append(f"func buildHome({'_ service: Service' if reads_service else ''}) -> Home {{ Home(__safeDI_fills: AppFills({args})) }}")

elif form == "C":
    fam = "Sendable" if S else ""
    C = lambda s: f"__safeDI_Home_Screen{s}{fam}Carrier"
    CH = f"__safeDI_Home_Home{fam}Carrier"
    def carrier(name, members):
        return [f"public final class {name}{SN} {{"] + [f"    public let {a}: {SA}{t}" for a, t in members] + \
               ["    public init(" + ", ".join(f"{a}: @escaping {SA}{t}" for a, t in members) + ") { " + " ".join(f"self.{a} = {a};" for a, _ in members) + " }", "}"]
    feature += carrier(CH, [(f"enterScreen{s}", f"() -> {C(s)}") for s in roots])
    for s in range(N):
        feature += carrier(C(s), [(f"{h}Of{s}", f"(_ id: Int) -> any {PT(j)}") for j, h in enumerate(HS) if s in holes] + [(f"enterScreen{o}", f"() -> {C(o)}") for o in kids(s)])
    # The seam's per-level context, where the seam passes `service` down beside the carrier.
    if seam_service:
        for s in range(N):
            if kids(s):
                feature.append(f"final class __safeDI_Screen{s}Level{SN} {{ let service: Service; let carrier: {C(s)}; init(service: Service, carrier: {C(s)}) {{ self.service = service; self.carrier = carrier }} }}")
        feature.append(f"final class __safeDI_HomeLevel{SN} {{ let service: Service; let carrier: {CH}; init(service: Service, carrier: {CH}) {{ self.service = service; self.carrier = carrier }} }}")
    for s in range(N):
        feature.append(f"func __safeDI_Screen{s}({'_ service: Service, ' if seam_service else ''}_ carrier: {C(s)}, id: Int) -> Screen{s} {{")
        feature += values(s, lambda h: f"carrier.{h}Of{s}(id)")
        if seam_service and kids(s):
            feature.append(f"    let level = __safeDI_Screen{s}Level(service: service, carrier: carrier)")
            feature += [f"    let screen{o}Builder = {BT(o)} {{ __safeDI_Screen{o}(level.service, level.carrier.enterScreen{o}(), id: $0) }}" for o in kids(s)]
        else:
            feature += [f"    let screen{o}Builder = {BT(o)} {{ __safeDI_Screen{o}(carrier.enterScreen{o}(), id: $0) }}" for o in kids(s)]
        feature += [ret(s), "}"]
    feature += ["extension Home {", f"    public convenience init({'__safeDI_service service: Service, ' if seam_service else ''}__safeDI_carrier carrier: {CH}) {{"]
    if seam_service:
        feature.append("        let level = __safeDI_HomeLevel(service: service, carrier: carrier)")
        feature += [f"        let screen{s}Builder = {BT(s)} {{ __safeDI_Screen{s}(level.service, level.carrier.enterScreen{s}(), id: $0) }}" for s in roots]
    else:
        feature += [f"        let screen{s}Builder = {BT(s)} {{ __safeDI_Screen{s}(carrier.enterScreen{s}(), id: $0) }}" for s in roots]
    feature += ["        self.init(" + ", ".join(f"screen{s}Builder: screen{s}Builder" for s in roots) + ")", "    }", "}"]
    # Caller: one context per carried set ({service} or empty); each closure captures the context or nothing.
    if reads_service:
        app.append(f"final class Context{SN} {{ let service: Service; init(service: Service) {{ self.service = service }} }}")
        cp, ca, cv = "_ context: Context", "context", "context.service"
    else:
        cp, ca, cv = "", "", None
    for s in range(N):
        mem = []
        if s in holes:
            mem += [f"{h}Of{s}: {{ id in Fills.{h}Of{s}(id: id" + (f", service: {cv}" if reads_service else "") + ") }" for h in HS]
        mem += [f"enterScreen{o}: {{ form{o}({ca}) }}" for o in kids(s)]
        app.append(f"func form{s}({cp}) -> {C(s)} {{ {C(s)}({', '.join(mem)}) }}")
    rootc = f"{CH}(" + ", ".join(f"enterScreen{s}: {{ form{s}({ca}) }}" for s in roots) + ")"
    if reads_service:
        pre = "let context = Context(service: service); "
    else:
        pre = ""
    if E:
        app.append(f"func buildHome(_ service: Service) -> Home {{ {pre}return Home(__safeDI_service: service, __safeDI_carrier: {rootc}) }}")
    else:
        app.append(f"func buildHome({'_ service: Service' if reads_service else ''}) -> Home {{ {pre}return Home(__safeDI_carrier: {rootc}) }}")

elif form == "Cf":
    # C formed once per carried set: the carried set never changes in these trees, so the caller forms every carrier once
    # when it forms the host (child first) and a parent carrier holds its children's carriers as `let`s. A cycle's types
    # share one carrier (n1: one loop carrier), so an entry inside the cycle is the carrier it was called on. The seam
    # forms its per-level contexts (where it passes `service` down) once too, at Home's init, child first.
    fam = "Sendable" if S else ""
    def carrier(name, members):  # (name, type, is_closure)
        return [f"public final class {name}{SN} {{"] + [f"    public let {a}: {(SA if c else '')}{t}" for a, t, c in members] + \
               ["    public init(" + ", ".join(f"{a}: " + (f"@escaping {SA}" if c else "") + t for a, t, c in members) + ") { " + " ".join(f"self.{a} = {a};" for a, _, _ in members) + " }", "}"]
    if not E:
        LC = f"__safeDI_Home_Loop{fam}Carrier"; CH = f"__safeDI_Home_Home{fam}Carrier"
        feature += carrier(LC, [(f"{h}Of{s}", f"(_ id: Int) -> any {PT(j)}", True) for s in range(N) for j, h in enumerate(HS)])
        feature += carrier(CH, [("loop", LC, False)])
        for s in range(N):
            feature.append(f"func __safeDI_Screen{s}(_ carrier: {LC}, id: Int) -> Screen{s} {{")
            feature += values(s, lambda h: f"carrier.{h}Of{s}(id)")
            feature += [f"    let screen{o}Builder = {BT(o)} {{ __safeDI_Screen{o}(carrier, id: $0) }}" for o in kids(s)]
            feature += [ret(s), "}"]
        feature += ["extension Home {", f"    public convenience init(__safeDI_carrier carrier: {CH}) {{", "        let loop = carrier.loop"]
        feature += [f"        let screen{s}Builder = {BT(s)} {{ __safeDI_Screen{s}(loop, id: $0) }}" for s in roots]
        feature += ["        self.init(" + ", ".join(f"screen{s}Builder: screen{s}Builder" for s in roots) + ")", "    }", "}"]
        if reads_service:
            app.append(f"final class Context{SN} {{ let service: Service; init(service: Service) {{ self.service = service }} }}")
        mem = ", ".join(f"{h}Of{s}: {{ id in Fills.{h}Of{s}(id: id" + (", service: context.service" if reads_service else "") + ") }" for s in range(N) for h in HS)
        pre = "let context = Context(service: service); " if reads_service else ""
        app.append(f"func buildHome({'_ service: Service' if reads_service else ''}) -> Home {{ {pre}return Home(__safeDI_carrier: {CH}(loop: {LC}({mem}))) }}")
    else:
        C = lambda s: f"__safeDI_Home_Screen{s}{fam}Carrier"; CH = f"__safeDI_Home_Home{fam}Carrier"
        feature += carrier(CH, [(f"screen{s}", C(s), False) for s in roots])
        for s in range(N):
            feature += carrier(C(s), [(f"{h}Of{s}", f"(_ id: Int) -> any {PT(j)}", True) for j, h in enumerate(HS) if s in holes] + [(f"screen{o}", C(o), False) for o in kids(s)])
        Lv = lambda s: f"__safeDI_Screen{s}Level"
        for s in range(N):
            fl = [("service", "Service"), ("carrier", C(s))] + [(f"screen{o}", Lv(o)) for o in kids(s)]
            feature.append(f"final class {Lv(s)}{SN} {{ " + " ".join(f"let {a}: {t};" for a, t in fl) + f" init({', '.join(f'{a}: {t}' for a, t in fl)}) {{ " + " ".join(f"self.{a} = {a};" for a, _ in fl) + " } }")
        for s in range(N):
            feature.append(f"func __safeDI_Screen{s}(_ level: {Lv(s)}, id: Int) -> Screen{s} {{")
            feature += ["    let service = level.service"] + values(s, lambda h: f"level.carrier.{h}Of{s}(id)")
            for o in kids(s):
                feature += [f"    let l{o} = level.screen{o}", f"    let screen{o}Builder = {BT(o)} {{ __safeDI_Screen{o}(l{o}, id: $0) }}"]
            feature += [ret(s), "}"]
        parent = {}
        for s in range(N):
            for o in kids(s): parent.setdefault(o, s)
        feature += ["extension Home {", f"    public convenience init(__safeDI_service service: Service, __safeDI_carrier carrier: {CH}) {{"]
        for s in range(N):
            feature.append(f"        let c{s} = " + (f"carrier.screen{s}" if s in roots else f"c{parent[s]}.screen{s}"))
        for s in reversed(range(N)):
            feature.append(f"        let l{s} = {Lv(s)}(service: service, carrier: c{s}" + "".join(f", screen{o}: l{o}" for o in kids(s)) + ")")
        feature += [f"        let screen{s}Builder = {BT(s)} {{ __safeDI_Screen{s}(l{s}, id: $0) }}" for s in roots]
        feature += ["        self.init(" + ", ".join(f"screen{s}Builder: screen{s}Builder" for s in roots) + ")", "    }", "}"]
        app.append(f"final class Context{SN} {{ let service: Service; init(service: Service) {{ self.service = service }} }}")
        app.append("func buildHome(_ service: Service) -> Home {")
        app.append("    let context = Context(service: service)")
        for s in reversed(range(N)):
            mem = [f"{h}Of{s}: {{ id in Fills.{h}Of{s}(id: id, service: context.service) }}" for h in HS if s in holes] + [f"screen{o}: c{o}" for o in kids(s)]
            app.append(f"    let c{s} = {C(s)}({', '.join(mem)})")
        app += [f"    return Home(__safeDI_service: service, __safeDI_carrier: {CH}(" + ", ".join(f"screen{s}: c{s}" for s in roots) + "))", "}"]

elif form == "Cx":
    # The spec v4 form for e. The seam cannot know which of a level's values the caller's fills read, so every level
    # that binds values visible beneath has an entry per child place, taking those values (id, model), called when the
    # parent forms the child's builder. The caller formed every carrier once (its carried set never changes here), so
    # each entry closure returns the child's pre-formed carrier, captured (one word). The seam's builders need `service`
    # and the child carrier: one seam per-level context per level instance holds both.
    assert E
    fam = "Sendable" if S else ""
    C = lambda s: f"__safeDI_Home_Screen{s}{fam}Carrier"; CH = f"__safeDI_Home_Home{fam}Carrier"
    def carrier(name, members):
        return [f"public final class {name}{SN} {{"] + [f"    public let {a}: {SA}{t}" for a, t in members] + \
               ["    public init(" + ", ".join(f"{a}: @escaping {SA}{t}" for a, t in members) + ") { " + " ".join(f"self.{a} = {a};" for a, _ in members) + " }", "}"]
    feature += carrier(CH, [(f"enterScreen{s}", f"() -> {C(s)}") for s in roots])
    for s in range(N):
        feature += carrier(C(s), [(f"{h}Of{s}", f"(_ id: Int) -> any {PT(j)}") for j, h in enumerate(HS) if s in holes] + [(f"enterScreen{o}", f"(_ id: Int, _ model: Model{s}) -> {C(o)}") for o in kids(s)])
    Lv = lambda s: f"__safeDI_Screen{s}Level"
    for s in range(N):
        if kids(s):
            fl = [("service", "Service")] + [(f"c{o}", C(o)) for o in kids(s)]
            feature.append(f"final class {Lv(s)}{SN} {{ " + " ".join(f"let {a}: {t};" for a, t in fl) + f" init({', '.join(f'{a}: {t}' for a, t in fl)}) {{ " + " ".join(f"self.{a} = {a};" for a, _ in fl) + " } }")
    feature.append(f"final class __safeDI_HomeLevel{SN} {{ let service: Service; " + " ".join(f"let c{s}: {C(s)};" for s in roots) + f" init(service: Service, {', '.join(f'c{s}: {C(s)}' for s in roots)}) {{ self.service = service; " + " ".join(f"self.c{s} = c{s};" for s in roots) + " } }")
    for s in range(N):
        feature.append(f"func __safeDI_Screen{s}(_ service: Service, _ carrier: {C(s)}, id: Int) -> Screen{s} {{")
        feature += values(s, lambda h: f"carrier.{h}Of{s}(id)")
        if kids(s):
            feature.append(f"    let level = {Lv(s)}(service: service, " + ", ".join(f"c{o}: carrier.enterScreen{o}(id, model{s})" for o in kids(s)) + ")")
            feature += [f"    let screen{o}Builder = {BT(o)} {{ __safeDI_Screen{o}(level.service, level.c{o}, id: $0) }}" for o in kids(s)]
        feature += [ret(s), "}"]
    feature += ["extension Home {", f"    public convenience init(__safeDI_service service: Service, __safeDI_carrier carrier: {CH}) {{",
                "        let level = __safeDI_HomeLevel(service: service, " + ", ".join(f"c{s}: carrier.enterScreen{s}()" for s in roots) + ")"]
    feature += [f"        let screen{s}Builder = {BT(s)} {{ __safeDI_Screen{s}(level.service, level.c{s}, id: $0) }}" for s in roots]
    feature += ["        self.init(" + ", ".join(f"screen{s}Builder: screen{s}Builder" for s in roots) + ")", "    }", "}"]
    app.append(f"final class Context{SN} {{ let service: Service; init(service: Service) {{ self.service = service }} }}")
    app.append("func buildHome(_ service: Service) -> Home {")
    app.append("    let context = Context(service: service)")
    for s in reversed(range(N)):
        mem = [f"{h}Of{s}: {{ id in Fills.{h}Of{s}(id: id, service: context.service) }}" for h in HS if s in holes] + [f"enterScreen{o}: {{ _, _ in c{o} }}" for o in kids(s)]
        app.append(f"    let c{s} = {C(s)}({', '.join(mem)})")
    app += [f"    return Home(__safeDI_service: service, __safeDI_carrier: {CH}(" + ", ".join(f"enterScreen{s}: {{ c{s} }}" for s in roots) + "))", "}"]

open(f"{out}/Types.swift", "w").write("\n".join(T) + "\n")
open(f"{out}/Feature.swift", "w").write("\n".join(feature) + "\n")
open(f"{out}/App.swift", "w").write("\n".join(app) + "\n")

# Walkers (as ngen3.py and egen3.py walk; buildHome runs on every walk, so the seam is re-instantiated each time).
touch = lambda v: " ".join(f"withExtendedLifetime({v}.{h}) {{}};" for h in HS)
w = ["import Foundation", "import Feature", "nonisolated(unsafe) var nextID = 0", "nonisolated(unsafe) var built = 0", "@inline(__always) func newID() -> Int { nextID &+= 1; return nextID }"]
if E:
    for s in reversed(range(N)):
        w += [f"@inline(never) func walk{s}(_ v: Screen{s}) {{", "    built &+= 2"] + ([f"    {touch(f'v.model{s}')}"] if s in holes else []) + [f"    walk{c}(v.screen{c}Builder.instantiate(newID()))" for c in kids(s)] + ["}"]
    w += (["nonisolated(unsafe) let theService = Service(); nonisolated(unsafe) let theHome = buildHome(theService)", "func walkAll() { let service = theService; let home = theHome"] if once else ["func walkAll() { let service = Service(); let home = buildHome(service)"])
    w += [ *[f"    walk{s}(home.screen{s}Builder.instantiate(newID()))" for s in roots], "    withExtendedLifetime(service) {} }",
          "walkAll(); let perWalk = built + 1; built = 0", "var samples = [Double]()", f"let reps = {max(1, 2000 // (4 * 3 ** (L - 1)))}"]
else:
    hb = "let service = Service(); let home = buildHome(service)" if reads_service else "let home = buildHome()"
    if once:
        w.append("nonisolated(unsafe) let theHome: Home = { " + hb.replace("let home = ", "return ") + " }()"); hb = "let home = theHome"
    for s in range(N):
        w.append(f"@inline(never) func walkReceived(_ v: Screen{s}) {{")
        w += [f"    let s{o} = v.screen{o}Builder.instantiate(newID()); built &+= 1; {touch(f's{o}')}" for o in kids(s)]
        w.append("}")
    w.append(f"@inline(never) func walkAll() {{ {hb}")
    w += [f"    do {{ let v = home.screen{s}Builder.instantiate(newID()); built &+= 1; {touch('v')} walkReceived(v) }}" for s in roots]
    w += ["}", "walkAll(); let perWalk = built; built = 0", "var samples = [Double]()", f"let reps = {max(1, 40000 // (4 * N))}"]
w += ["for _ in 0..<31 { let start = DispatchTime.now().uptimeNanoseconds; for _ in 0..<reps { walkAll() }; samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / Double(reps) / 1000) }",
      'samples.sort(); print(String(format: "median %.2f us per walk, %d values per walk", samples[15], perWalk))']
open(f"{out}/bench/main.swift", "w").write("\n".join(w) + "\n")
