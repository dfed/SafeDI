# gen3.py SHAPE(chain) FORM READS D OUT -- spec v3 chain cells. Lead's gen.py extended:
# FORMS inline, cls (open class, every fill/entry overridden by generated caller classes), plv (per-level protocols),
# psm (Sendable per-seam protocol, no extension defaults: every conformer implements every requirement), clo (closure
# carrier: a seam-declared final class per level holding `fill` and `enter` closures the caller's generated code forms,
# each capturing only what it reads; carriers formed on entry).
# READS none | some (fills read id1 from L1) | win (fill of Lk reads m of L(k-1), one reference) | two (m and id of L(k-1)).
import sys, os
shape, form, reads, D, out = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
rebuild = len(sys.argv) > 6 and sys.argv[6] == "rebuild"
os.makedirs(out, exist_ok=True)
F = ["""public final class Instantiator<T> { let b: (Int) -> T; public init(_ b: @escaping (Int) -> T) { self.b = b }; public func instantiate(_ id: Int) -> T { b(id) } }
public final class M: Sendable { public let x = 1; public init() {} }
public protocol H { var v: Int { get } }
"""]
A = ["import Feature\nfinal class HImpl: H, Sendable { let v: Int; init(v: Int) { self.v = v } }\n"]
for k in range(1, D + 1):
    nxt = f", next: Instantiator<L{k+1}>" if k < D else ""
    F.append(f"public final class L{k} {{ public let id: Int; public let m: M; public let h: any H" + (f"; public let next: Instantiator<L{k+1}>" if k < D else "") + f"; public init(id: Int, m: M, h: any H{nxt}) {{ self.id = id; self.m = m; self.h = h" + ("; self.next = next" if k < D else "") + " } }\n")
walk = "var s = 0\n    let l1 = host.instantiate(1); s &+= l1.h.v\n" + "".join(f"    let l{k} = l{k-1}.next.instantiate({k}); s &+= l{k}.h.v\n" for k in range(2, D + 1))
# The fill expression at level k, in terms of: id, m (own level) and carried names.
def fexpr(k, own_id="id", own_m="m", id1="id1", pm="pm", pid="pid"):
    if reads == "none": return "HImpl(v: 0)"
    if reads == "some": return f"HImpl(v: {own_id} &+ {own_m}.x &+ {id1 if k > 1 else own_id})"
    if k == 1: return "HImpl(v: 0)"
    if reads == "win": return f"HImpl(v: {pm}.x)"
    return f"HImpl(v: {pm}.x &+ {pid})"
# carried state class for the caller object forms, per reads: (class name, fields, ctor from level k's id/m)
def state(k):  # what level k+1..D fills need, formed at entry of L(k+1) from level k's values
    if reads == "none": return None
    if reads == "some": return ("Deep", [("id1", "Int")], "Deep(id1: id)") if k == 1 else "same"
    if reads == "win": return ("Win", [("pm", "M")], "Win(pm: m)")
    return ("Win2", [("pm", "M"), ("pid", "Int")], "Win2(pm: m, pid: id)")
if form == "inline":
    body = ""
    for k in range(D, 0, -1):
        fill = fexpr(k, f"id{k}", f"m{k}", "id1", f"m{k-1}", f"id{k-1}")
        nx = f", next: Instantiator<L{k+1}> {{ id{k+1} in\n{body}}}" if k < D else ""
        body = f"let m{k} = M()\nreturn L{k}(id: id{k}, m: m{k}, h: {fill}{nx})\n"
    A.append("func makeHost() -> Instantiator<L1> { Instantiator<L1> { id1 in\n" + body + "} }\n")
elif form in ("cls", "plv", "psm", "cbase", "plvS"):
    if form == "cls":
        F.append("open class Fills {\n    public init() {}\n")
        for k in range(1, D + 1):
            F.append(f"    open func hOfL{k}(id: Int, m: M) -> any H {{ fatalError() }}\n")
            if k < D: F.append(f"    open func enterL{k+1}(id: Int, m: M) -> Fills {{ fatalError() }}\n")
        F.append("}\n")
        P = lambda k: "Fills"; base = "Fills"; ov = "override "; sup = "; super.init()"
        conf = lambda ks: "Fills"
        for k in range(1, D + 1):
            F.append(f"func buildL{k}(_ id: Int, _ f: Fills) -> L{k} {{ let m = M(); let h = f.hOfL{k}(id: id, m: m)" + (f"; let g = f.enterL{k+1}(id: id, m: m); return L{k}(id: id, m: m, h: h, next: Instantiator<L{k+1}> {{ buildL{k+1}($0, g) }}) }}\n" if k < D else f"; return L{k}(id: id, m: m, h: h) }}\n"))
        F.append("public func makeSeamHost(_ f: Fills) -> Instantiator<L1> { Instantiator<L1> { buildL1($0, f) } }\n")
    elif form in ("plv", "plvS"):
        for k in range(1, D + 1):
            ent = f"; func enterL{k+1}(id: Int, m: M) -> any L{k+1}Fills" if k < D else ""
            F.append(f"public protocol L{k}Fills: AnyObject" + (", Sendable" if form == "plvS" else "") + f" {{ func hOfL{k}(id: Int, m: M) -> any H{ent} }}\n")
        for k in range(1, D + 1):
            F.append(f"func buildL{k}(_ id: Int, _ f: any L{k}Fills) -> L{k} {{ let m = M(); let h = f.hOfL{k}(id: id, m: m)" + (f"; let g = f.enterL{k+1}(id: id, m: m); return L{k}(id: id, m: m, h: h, next: Instantiator<L{k+1}> {{ buildL{k+1}($0, g) }}) }}\n" if k < D else f"; return L{k}(id: id, m: m, h: h) }}\n"))
        F.append("public func makeSeamHost(_ f: any L1Fills) -> Instantiator<L1> { Instantiator<L1> { buildL1($0, f) } }\n")
        P = lambda k: f"any L{k}Fills"; ov = ""; sup = ""
        conf = lambda ks: ", ".join(f"L{k}Fills" for k in ks)
    elif form == "cbase":
        F.append("public protocol SeamFills: AnyObject {\n")
        for k in range(1, D + 1):
            F.append(f"    func hOfL{k}(id: Int, m: M) -> any H\n")
            if k < D: F.append(f"    func enterL{k+1}(id: Int, m: M) -> any SeamFills\n")
        F.append("}\n")
        for k in range(1, D + 1):
            F.append(f"func buildL{k}(_ id: Int, _ f: any SeamFills) -> L{k} {{ let m = M(); let h = f.hOfL{k}(id: id, m: m)" + (f"; let g = f.enterL{k+1}(id: id, m: m); return L{k}(id: id, m: m, h: h, next: Instantiator<L{k+1}> {{ buildL{k+1}($0, g) }}) }}\n" if k < D else f"; return L{k}(id: id, m: m, h: h) }}\n"))
        F.append("public func makeSeamHost(_ f: any SeamFills) -> Instantiator<L1> { Instantiator<L1> { buildL1($0, f) } }\n")
        # the caller-side base class: implements every requirement once, each body a trap
        A.append("class Base: SeamFills {\n    init() {}\n" + "".join(f"    func hOfL{k}(id: Int, m: M) -> any H {{ fatalError() }}\n" + (f"    func enterL{k+1}(id: Int, m: M) -> any SeamFills {{ fatalError() }}\n" if k < D else "") for k in range(1, D + 1)) + "}\n")
        P = lambda k: "any SeamFills"; ov = "override "; sup = "; super.init()"
        conf = lambda ks: "Base"
    else:
        F.append("public protocol SFills: AnyObject, Sendable {\n")
        for k in range(1, D + 1):
            F.append(f"    func hOfL{k}(id: Int, m: M) -> any H\n")
            if k < D: F.append(f"    func enterL{k+1}(id: Int, m: M) -> any SFills\n")
        F.append("}\nfinal class Ctx: Sendable { let f: any SFills; init(f: any SFills) { self.f = f } }\n")
        for k in range(1, D + 1):
            F.append(f"func buildL{k}(_ id: Int, _ c: Ctx) -> L{k} {{ let m = M(); let f = c.f; let h = f.hOfL{k}(id: id, m: m)" + (f"; let g = f.enterL{k+1}(id: id, m: m); let c2 = g === f ? c : Ctx(f: g); return L{k}(id: id, m: m, h: h, next: Instantiator<L{k+1}> {{ buildL{k+1}($0, c2) }}) }}\n" if k < D else f"; return L{k}(id: id, m: m, h: h) }}\n"))
        F.append("public func makeSeamHost(_ f: any SFills) -> Instantiator<L1> { let c = Ctx(f: f); return Instantiator<L1> { buildL1($0, c) } }\n")
        P = lambda k: "any SFills"; ov = ""; sup = ""
        conf = lambda ks: "SFills"
    fin = "final " if form != "cls" else "final "
    # Root: level 1 fill, and entries returning self (none) or a new state object.
    def methods(ks, selfexpr):
        s = ""
        for k in ks:
            s += f"    {ov}func hOfL{k}(id: Int, m: M) -> any H {{ {fexpr(k, 'id', 'm', 'self.id1', 'self.pm', 'self.pid')} }}\n"
            if k < D:
                st = state(k)
                ret = "self" if st is None or st == "same" else st[2]
                s += f"    {ov}func enterL{k+1}(id: Int, m: M) -> {P(k+1)} {{ {ret} }}\n"
        return s
    if reads == "none":
        A.append(f"final class Root: {conf(range(1, D + 1))} {{\n" + methods(range(1, D + 1), "self") + "}\n")
    else:
        A.append(f"final class Root: {conf([1])} {{\n" + methods([1], "") + "}\n")
        name, fields, _ = state(1)
        A.append(f"final class {name}: {conf(range(2, D + 1))} {{\n" + "".join(f"    let {n}: {t}\n" for n, t in fields)
                 + f"    init({', '.join(f'{n}: {t}' for n, t in fields)}) {{ " + "; ".join(f"self.{n} = {n}" for n, _ in fields) + f"{sup} }}\n"
                 + methods(range(2, D + 1), "") + "}\n")
    A.append("func makeHost() -> Instantiator<L1> { makeSeamHost(Root()) }\n")
elif form in ("clo", "cloc", "clos", "cloS"):
    kind = "struct" if form == "clos" else "final class"
    sendable = form == "cloS"
    sa = "@Sendable " if sendable else ""
    for k in range(1, D + 1):
        ent = f"    let enter: {sa}(_ id: Int, _ m: M) -> __safeDI_Host_L{k+1}\n" if k < D else ""
        F.append(f"public {kind} __safeDI_Host_L{k}" + (": Sendable" if sendable else "") + f" {{\n    let fill: {sa}(_ id: Int, _ m: M) -> any H\n{ent}"
                 + f"    public init(fill: @escaping {sa}(_ id: Int, _ m: M) -> any H" + (f", enter: @escaping {sa}(_ id: Int, _ m: M) -> __safeDI_Host_L{k+1}" if k < D else "")
                 + ") { self.fill = fill" + ("; self.enter = enter" if k < D else "") + " }\n}\n")
        F.append(f"func buildL{k}(_ id: Int, _ c: __safeDI_Host_L{k}) -> L{k} {{ let m = M(); let h = c.fill(id, m)" + (f"; let n = c.enter(id, m); return L{k}(id: id, m: m, h: h, next: Instantiator<L{k+1}> {{ buildL{k+1}($0, n) }}) }}\n" if k < D else f"; return L{k}(id: id, m: m, h: h) }}\n"))
    F.append("public func makeSeamHost(_ c: __safeDI_Host_L1) -> Instantiator<L1> { Instantiator<L1> { buildL1($0, c) } }\n")
    # caller: static fill functions on the conformer (item 7), carriers formed on entry.
    A.append("enum Fills {\n")
    for k in range(1, D + 1):
        ps = {"none": "", "some": ", id1: Int" if k > 1 else "", "win": ", pm: M" if k > 1 else "", "two": ", pm: M, pid: Int" if k > 1 else ""}[reads]
        A.append(f"    static func hOfL{k}(id: Int, m: M{ps}) -> any H {{ {fexpr(k)} }}\n")
    A.append("}\n")
    params = {"id1": "id1: Int", "pm": "pm: M", "pid": "pid: Int"}
    carried = {"none": [], "some": ["id1"], "win": ["pm"], "two": ["pm", "pid"]}[reads]
    # object mode: one carried-set object unless the set is one class reference
    obj = form != "clo" and carried and carried != ["pm"]
    if obj:
        A.append("final class Carried" + (": Sendable" if sendable else "") + " { " + " ".join(f"let {params[c]};" for c in carried) + f" init({', '.join(params[c] for c in carried)}) {{ " + "; ".join(f"self.{c} = {c}" for c in carried) + " } }\n")
    for k in range(1, D + 1):
        cap = carried if k > 1 else []
        src = {"id1": ("id" if k == 1 else "id1"), "pm": "m", "pid": "id"}
        if obj and cap:
            sig = "_ carried: Carried"; fargs = "".join(f", {c}: carried.{c}" for c in cap)
        else:
            sig = ", ".join(params[c] for c in cap); fargs = "".join(f", {c}: {c}" for c in cap)
        if k < D:
            if obj:
                if reads == "some" and k > 1: nargs = "carried"
                else: nargs = "Carried(" + ", ".join(f"{c}: {src[c]}" for c in carried) + ")"
            else:
                nargs = ", ".join(f"{c}: {src[c]}" for c in carried)
            enter = f", enter: {{ id, m in carrierL{k+1}({nargs}) }}"
        else:
            enter = ""
        A.append(f"func carrierL{k}({sig}) -> __safeDI_Host_L{k} {{ __safeDI_Host_L{k}(fill: {{ id, m in Fills.hOfL{k}(id: id, m: m{fargs}) }}{enter}) }}\n")
    A.append("func makeHost() -> Instantiator<L1> { makeSeamHost(carrierL1()) }\n")
elif form == "pcc":
    # One seam-declared final carrier class per seam: an optional fill closure per place and an optional entry closure
    # per builder level (nil keeps the carrier in effect). The caller forms a carrier only where its carried set changes,
    # setting the fields reached through it before the next formation; the seam unwraps each fill (a trap if the caller's
    # generator omitted one: the trap question).
    C = "__safeDI_Host_Fills"
    fl = [(f"hOfL{k}", f"((_ id: Int, _ m: M) -> any H)?") for k in range(1, D + 1)] + [(f"enterL{k}", f"((_ id: Int, _ m: M) -> {C})?") for k in range(2, D + 1)]
    F.append(f"public final class {C} {{\n" + "".join(f"    let {a}: {t}\n" for a, t in fl) + f"    public init({', '.join(f'{a}: {t} = nil' for a, t in fl)}) {{ " + "; ".join(f"self.{a} = {a}" for a, _ in fl) + " }\n}\n")
    for k in range(1, D + 1):
        F.append(f"func buildL{k}(_ id: Int, _ c: {C}) -> L{k} {{ let m = M(); let h = c.hOfL{k}!(id, m)" + (f"; let n = c.enterL{k+1}?(id, m) ?? c; return L{k}(id: id, m: m, h: h, next: Instantiator<L{k+1}> {{ buildL{k+1}($0, n) }}) }}\n" if k < D else f"; return L{k}(id: id, m: m, h: h) }}\n"))
    F.append(f"public func makeSeamHost(_ c: {C}) -> Instantiator<L1> {{ Instantiator<L1> {{ buildL1($0, c) }} }}\n")
    A.append("enum Fills {\n")
    for k in range(1, D + 1):
        ps = {"none": "", "some": ", id1: Int" if k > 1 else "", "win": ", pm: M" if k > 1 else "", "two": ", pm: M, pid: Int" if k > 1 else ""}[reads]
        A.append(f"    static func hOfL{k}(id: Int, m: M{ps}) -> any H {{ {fexpr(k)} }}\n")
    A.append("}\n")
    if reads == "none":
        A.append(f"func makeHost() -> Instantiator<L1> {{ makeSeamHost({C}(" + ", ".join(f"hOfL{k}: {{ id, m in Fills.hOfL{k}(id: id, m: m) }}" for k in range(1, D + 1)) + ")) }\n")
    elif reads == "some":
        A.append("final class Carried { let id1: Int; init(id1: Int) { self.id1 = id1 } }\n")
        A.append(f"func formL2(_ c: Carried) -> {C} {{ {C}(" + ", ".join(f"hOfL{k}: {{ id, m in Fills.hOfL{k}(id: id, m: m, id1: c.id1) }}" for k in range(2, D + 1)) + ") }\n")
        A.append(f"func makeHost() -> Instantiator<L1> {{ makeSeamHost({C}(hOfL1: {{ id, m in Fills.hOfL1(id: id, m: m) }}, enterL2: {{ id, _ in formL2(Carried(id1: id)) }})) }}\n")
    else:
        if reads == "two":
            A.append("final class Carried { let pm: M; let pid: Int; init(pm: M, pid: Int) { self.pm = pm; self.pid = pid } }\n")
        for k in range(2, D + 1):
            if reads == "win":
                sig, fa, nx = "pm: M", "pm: pm", "pm: m"
            else:
                sig, fa, nx = "_ c: Carried", "pm: c.pm, pid: c.pid", "Carried(pm: m, pid: id)"
            ent = f", enterL{k+1}: {{ id, m in formL{k+1}({nx}) }}" if k < D else ""
            A.append(f"func formL{k}({sig}) -> {C} {{ {C}(hOfL{k}: {{ id, m in Fills.hOfL{k}(id: id, m: m, {fa}) }}{ent}) }}\n")
        nx = "pm: m" if reads == "win" else "Carried(pm: m, pid: id)"
        A.append(f"func makeHost() -> Instantiator<L1> {{ makeSeamHost({C}(hOfL1: {{ id, m in Fills.hOfL1(id: id, m: m) }}, enterL2: {{ id, m in formL2({nx}) }})) }}\n")
elif form == "pccdual":
    # The Sendable family's dual entry: the seam threads the plain carrier and a Sendable twin (@Sendable closures);
    # every level enters both. Places read through the plain one; the twin carries what a place under a @Sendable
    # builder would read (here the same set), so each level pays both entries.
    C, S = "__safeDI_Host_Fills", "__safeDI_Host_SendableFills"
    for name, sa, snd in ((C, "", ""), (S, "@Sendable ", ": Sendable")):
        fl = [(f"hOfL{k}", f"({sa}(_ id: Int, _ m: M) -> any H)?") for k in range(1, D + 1)] + [(f"enterL{k}", f"({sa}(_ id: Int) -> {name})?") for k in range(2, D + 1)]
        F.append(f"public final class {name}{snd} {{\n" + "".join(f"    let {a}: {t}\n" for a, t in fl) + f"    public init({', '.join(f'{a}: {t} = nil' for a, t in fl)}) {{ " + "; ".join(f"self.{a} = {a}" for a, _ in fl) + " }\n}\n")
    for k in range(1, D + 1):
        F.append(f"func buildL{k}(_ id: Int, _ c: {C}, _ s: {S}) -> L{k} {{ let m = M(); let h = c.hOfL{k}!(id, m)" + (f"; let n = c.enterL{k+1}?(id) ?? c; let ns = s.enterL{k+1}?(id) ?? s; return L{k}(id: id, m: m, h: h, next: Instantiator<L{k+1}> {{ buildL{k+1}($0, n, ns) }}) }}\n" if k < D else f"; return L{k}(id: id, m: m, h: h) }}\n"))
    F.append(f"public func makeSeamHost(_ c: {C}, _ s: {S}) -> Instantiator<L1> {{ Instantiator<L1> {{ buildL1($0, c, s) }} }}\n")
    A.append("enum Fills {\n" + "".join(f"    static func hOfL{k}(id: Int, m: M" + (", id1: Int" if reads == "some" and k > 1 else "") + f") -> any H {{ {fexpr(k)} }}\n" for k in range(1, D + 1)) + "}\n")
    if reads == "none":
        A.append(f"func makeHost() -> Instantiator<L1> {{ makeSeamHost({C}(" + ", ".join(f"hOfL{k}: {{ id, m in Fills.hOfL{k}(id: id, m: m) }}" for k in range(1, D + 1)) + f"), {S}()) }}\n")
    else:
        A.append("final class Carried: Sendable { let id1: Int; init(id1: Int) { self.id1 = id1 } }\n")
        A.append(f"func formL2(_ c: Carried) -> {C} {{ {C}(" + ", ".join(f"hOfL{k}: {{ id, m in Fills.hOfL{k}(id: id, m: m, id1: c.id1) }}" for k in range(2, D + 1)) + ") }\n")
        A.append(f"func formSL2(_ c: Carried) -> {S} {{ {S}(hOfL{D}: {{ id, m in Fills.hOfL{D}(id: id, m: m, id1: c.id1) }}) }}\n")
        A.append(f"func makeHost() -> Instantiator<L1> {{ makeSeamHost({C}(hOfL1: {{ id, m in Fills.hOfL1(id: id, m: m) }}, enterL2: {{ id in formL2(Carried(id1: id)) }}), {S}(enterL2: {{ id in formSL2(Carried(id1: id)) }})) }}\n")
elif form in ("ccl", "ccldual", "ccl2"):
    # The class form whose caller-side subclasses hold closures: the seam's open class (base bodies trap); the caller's
    # generated subclasses are spelled `nonisolated final class`, one per carried set, and each override in its zone calls a
    # closure the caller's generated code formed (so it inherits the caller's isolation). An entry that keeps the object
    # is a plain `{ self }` override.
    F.append("open class Fills {\n    public init() {}\n")
    for k in range(1, D + 1):
        F.append(f"    open func hOfL{k}(id: Int, m: M) -> any H {{ fatalError() }}\n")
        if k < D: F.append(f"    open func enterL{k+1}(id: Int, m: M) -> Fills {{ fatalError() }}\n")
    F.append("}\n")
    for k in range(1, D + 1):
        if form == "ccldual":
            F.append(f"func buildL{k}(_ id: Int, _ f: Fills, _ s: Twin) -> L{k} {{ let m = M(); let h = f.hOfL{k}(id: id, m: m)" + (f"; let g = f.enterL{k+1}(id: id, m: m); let gs = s.enterL{k+1}?(id) ?? s; return L{k}(id: id, m: m, h: h, next: Instantiator<L{k+1}> {{ buildL{k+1}($0, g, gs) }}) }}\n" if k < D else f"; return L{k}(id: id, m: m, h: h) }}\n"))
        else:
            F.append(f"func buildL{k}(_ id: Int, _ f: Fills) -> L{k} {{ let m = M(); let h = f.hOfL{k}(id: id, m: m)" + (f"; let g = f.enterL{k+1}(id: id, m: m); return L{k}(id: id, m: m, h: h, next: Instantiator<L{k+1}> {{ buildL{k+1}($0, g) }}) }}\n" if k < D else f"; return L{k}(id: id, m: m, h: h) }}\n"))
    if form == "ccldual":
        tf = [(f"enterL{k}", "(@Sendable (_ id: Int) -> Twin)?") for k in range(2, D + 1)] + [("hSendable", "(@Sendable (_ id: Int) -> Int)?")]
        F.append("public final class Twin: Sendable {\n" + "".join(f"    let {x}: {t}\n" for x, t in tf) + f"    public init({', '.join(f'{x}: {t} = nil' for x, t in tf)}) {{ " + "; ".join(f"self.{x} = {x}" for x, _ in tf) + " }\n}\n")
        F.append("public func makeSeamHost(_ f: Fills, _ s: Twin) -> Instantiator<L1> { Instantiator<L1> { buildL1($0, f, s) } }\n")
    else:
        F.append("public func makeSeamHost(_ f: Fills) -> Instantiator<L1> { Instantiator<L1> { buildL1($0, f) } }\n")
    A.append("enum StaticFills {\n")
    for k in range(1, D + 1):
        ps = {"none": "", "some": ", id1: Int" if k > 1 else "", "win": ", pm: M" if k > 1 else "", "two": ", pm: M, pid: Int" if k > 1 else ""}[reads]
        A.append(f"    static func hOfL{k}(id: Int, m: M{ps}) -> any H {{ {fexpr(k)} }}\n")
    A.append("}\n")
    HT, ET = "(Int, M) -> any H", "(Int, M) -> Fills"
    if form == "ccl2" and reads != "none":
        # The zone object stores the carried values; each closure is non-capturing and takes them as arguments.
        cv = {"some": [("id1", "Int")], "win": [("pm", "M")], "two": [("pm", "M"), ("pid", "Int")]}[reads]
        CT = "(Int, M, " + ", ".join(t for _, t in cv) + ") -> any H"
        def zone2(name, fills, closure_entries, self_entries, carried):
            flds = (list(cv) if carried else []) + [(f"h{k}", CT if carried else HT) for k in fills] + [(f"e{k}", ET) for k in closure_entries]
            s = f"nonisolated final class {name}: Fills {{\n" + "".join(f"    let {a}: {t}\n" for a, t in flds)
            s += f"    init({', '.join(f'{a}: ' + ('@escaping ' if '->' in t else '') + t for a, t in flds)}) {{ " + "; ".join(f"self.{a} = {a}" for a, _ in flds) + "; super.init() }\n"
            extra = "".join(f", {a}" for a, _ in cv) if carried else ""
            s += "".join(f"    override func hOfL{k}(id: Int, m: M) -> any H {{ h{k}(id, m{extra}) }}\n" for k in fills)
            s += "".join(f"    override func enterL{k}(id: Int, m: M) -> Fills {{ e{k}(id, m) }}\n" for k in closure_entries)
            s += "".join(f"    override func enterL{k}(id: Int, m: M) -> Fills {{ self }}\n" for k in self_entries)
            return s + "}\n"
        A.append(zone2("Root", [1], [2], [], False))
        names = ", ".join(a for a, _ in cv)
        if reads == "some":
            A.append(zone2("Deep", range(2, D + 1), [], range(3, D + 1), True))
            A.append("func formDeep(id1: Int) -> Fills { Deep(id1: id1, " + ", ".join(f"h{k}: {{ id, m, id1 in StaticFills.hOfL{k}(id: id, m: m, id1: id1) }}" for k in range(2, D + 1)) + ") }\n")
            A.append("func makeHost() -> Instantiator<L1> { makeSeamHost(Root(h1: { id, m in StaticFills.hOfL1(id: id, m: m) }, e2: { id, _ in formDeep(id1: id) })) }\n")
        else:
            nx = "pm: m" if reads == "win" else "pm: m, pid: id"
            for k in range(2, D + 1):
                A.append(zone2(f"W{k}", [k], [k + 1] if k < D else [], [], True))
                ent = f", e{k+1}: {{ id, m in form{k+1}({nx}) }}" if k < D else ""
                A.append(f"func form{k}({', '.join(f'{a}: {t}' for a, t in cv)}) -> Fills {{ W{k}({', '.join(f'{a}: {a}' for a, _ in cv)}, h{k}: {{ id, m, {names} in StaticFills.hOfL{k}(id: id, m: m, {', '.join(f'{a}: {a}' for a, _ in cv)}) }}{ent}) }}\n")
            A.append(f"func makeHost() -> Instantiator<L1> {{ makeSeamHost(Root(h1: {{ id, m in StaticFills.hOfL1(id: id, m: m) }}, e2: {{ id, m in form2({nx}) }})) }}\n")
    elif True:
        def zone(name, fills, closure_entries, self_entries):
            flds = [(f"h{k}", HT) for k in fills] + [(f"e{k}", ET) for k in closure_entries]
            s = f"nonisolated final class {name}: Fills {{\n" + "".join(f"    let {a}: {t}\n" for a, t in flds)
            s += f"    init({', '.join(f'{a}: @escaping {t}' for a, t in flds)}) {{ " + "; ".join(f"self.{a} = {a}" for a, _ in flds) + "; super.init() }\n"
            s += "".join(f"    override func hOfL{k}(id: Int, m: M) -> any H {{ h{k}(id, m) }}\n" for k in fills)
            s += "".join(f"    override func enterL{k}(id: Int, m: M) -> Fills {{ e{k}(id, m) }}\n" for k in closure_entries)
            s += "".join(f"    override func enterL{k}(id: Int, m: M) -> Fills {{ self }}\n" for k in self_entries)
            return s + "}\n"
        if reads == "none":
            A.append(zone("Root", range(1, D + 1), [], range(2, D + 1)))
            A.append("func makeHost() -> Instantiator<L1> { makeSeamHost(Root(" + ", ".join(f"h{k}: {{ id, m in StaticFills.hOfL{k}(id: id, m: m) }}" for k in range(1, D + 1)) + ")" + (", Twin()" if form == "ccldual" else "") + ") }\n")
        elif reads == "some":
            A.append("final class Carried { let id1: Int; init(id1: Int) { self.id1 = id1 } }\n")
            A.append(zone("Root", [1], [2], []))
            A.append(zone("Deep", range(2, D + 1), [], range(3, D + 1)))
            A.append("func formDeep(_ c: Carried) -> Fills { Deep(" + ", ".join(f"h{k}: {{ id, m in StaticFills.hOfL{k}(id: id, m: m, id1: c.id1) }}" for k in range(2, D + 1)) + ") }\n")
            tw = ", Twin(enterL2: { id1 in Twin(hSendable: { id in id &+ id1 }) })" if form == "ccldual" else ""
            A.append("func makeHost() -> Instantiator<L1> { makeSeamHost(Root(h1: { id, m in StaticFills.hOfL1(id: id, m: m) }, e2: { id, _ in formDeep(Carried(id1: id)) })" + tw + ") }\n")
        else:
            if reads == "two": A.append("final class Carried { let pm: M; let pid: Int; init(pm: M, pid: Int) { self.pm = pm; self.pid = pid } }\n")
            A.append(zone("Root", [1], [2], []))
            for k in range(2, D + 1):
                A.append(zone(f"W{k}", [k], [k + 1] if k < D else [], []))
                if reads == "win": sig, fa, nx = "pm: M", "pm: pm", "pm: m"
                else: sig, fa, nx = "_ c: Carried", "pm: c.pm, pid: c.pid", "Carried(pm: m, pid: id)"
                ent = f", e{k+1}: {{ id, m in form{k+1}({nx}) }}" if k < D else ""
                A.append(f"func form{k}({sig}) -> Fills {{ W{k}(h{k}: {{ id, m in StaticFills.hOfL{k}(id: id, m: m, {fa}) }}{ent}) }}\n")
            nx = "pm: m" if reads == "win" else "Carried(pm: m, pid: id)"
            A.append(f"func makeHost() -> Instantiator<L1> {{ makeSeamHost(Root(h1: {{ id, m in StaticFills.hOfL1(id: id, m: m) }}, e2: {{ id, m in form2({nx}) }})) }}\n")
elif form in ("C", "Ce"):
    # The trajectory candidate C: per level type a seam-declared final class carrier of required closures the caller
    # forms. hOfLk takes the level's own values; enterL(k+1) takes the values of level k that the subtree beneath reads
    # and forms the child carrier. Each closure captures at most one reference, the caller's context for its carried set.
    # C: the entry runs inside the builder; the builder captures one word: the carrier where the entry takes nothing,
    #    else the seam's per-level context holding the carrier as a let and the entry's arguments.
    # Ce: the entry runs when the parent forms the builder; the builder captures the child carrier.
    cv = {"none": [], "some": [("id1", "Int")], "win": [("pm", "M")], "two": [("pm", "M"), ("pid", "Int")]}[reads]
    def eargs(k):  # values of level k passed to enterL(k+1)
        if reads == "none": return []
        if reads == "some": return [("id", "Int")] if k == 1 else []
        if reads == "win": return [("m", "M")]
        return [("m", "M"), ("id", "Int")]
    Cn = lambda k: f"__safeDI_Host_L{k}Carrier"
    for k in range(1, D + 1):
        mem = [(f"hOfL{k}", "(_ id: Int, _ m: M) -> any H")]
        if k < D: mem.append((f"enterL{k+1}", "(" + ", ".join(f"_ {a}: {t}" for a, t in eargs(k)) + f") -> {Cn(k+1)}"))
        F.append(f"public final class {Cn(k)} {{ " + " ".join(f"public let {a}: {t};" for a, t in mem) + f" public init({', '.join(f'{a}: @escaping {t}' for a, t in mem)}) {{ " + " ".join(f"self.{a} = {a};" for a, _ in mem) + " } }\n")
    for k in range(1, D + 1):
        body = f"func buildL{k}(_ id: Int, _ c: {Cn(k)}) -> L{k} {{ let m = M(); let h = c.hOfL{k}(id, m)"
        if k == D:
            body += f"; return L{k}(id: id, m: m, h: h) }}\n"
        else:
            ea = eargs(k); call = ", ".join(a for a, _ in ea)
            if form == "Ce":
                body += f"; let n = c.enterL{k+1}({call}); return L{k}(id: id, m: m, h: h, next: Instantiator<L{k+1}> {{ buildL{k+1}($0, n) }}) }}\n"
            elif not ea:
                body += f"; return L{k}(id: id, m: m, h: h, next: Instantiator<L{k+1}> {{ buildL{k+1}($0, c.enterL{k+1}()) }}) }}\n"
            else:
                F.append(f"final class __safeDI_L{k}Level {{ let carrier: {Cn(k)}; " + " ".join(f"let {a}: {t};" for a, t in ea) + f" init(carrier: {Cn(k)}, {', '.join(f'{a}: {t}' for a, t in ea)}) {{ self.carrier = carrier; " + " ".join(f"self.{a} = {a};" for a, _ in ea) + " } }\n")
                body += f"; let level = __safeDI_L{k}Level(carrier: c, {', '.join(f'{a}: {a}' for a, _ in ea)}); return L{k}(id: id, m: m, h: h, next: Instantiator<L{k+1}> {{ buildL{k+1}($0, level.carrier.enterL{k+1}({', '.join(f'level.{a}' for a, _ in ea)})) }}) }}\n"
        F.append(body)
    F.append(f"public func makeSeamHost(_ c: {Cn(1)}) -> Instantiator<L1> {{ Instantiator<L1> {{ buildL1($0, c) }} }}\n")
    A.append("enum StaticFills {\n")
    for k in range(1, D + 1):
        ps = "".join(f", {a}: {t}" for a, t in cv) if k > 1 else ""
        A.append(f"    static func hOfL{k}(id: Int, m: M{ps}) -> any H {{ {fexpr(k)} }}\n")
    A.append("}\n")
    if cv:
        A.append("final class Ctx { " + " ".join(f"let {a}: {t};" for a, t in cv) + f" init({', '.join(f'{a}: {t}' for a, t in cv)}) {{ " + " ".join(f"self.{a} = {a};" for a, _ in cv) + " } }\n")
    # form functions: level 1 has no context; level k >= 2 takes the context of its carried set
    newctx = {"some": "Ctx(id1: id)", "win": "Ctx(pm: m)", "two": "Ctx(pm: m, pid: id)"}
    for k in range(1, D + 1):
        has = bool(cv) and k > 1
        fill = f"hOfL{k}: {{ id, m in StaticFills.hOfL{k}(id: id, m: m" + ("".join(f", {a}: ctx.{a}" for a, _ in cv) if has else "") + ") }"
        mem = [fill]
        if k < D:
            ea = eargs(k); ps = ", ".join(a for a, _ in ea)
            if not cv:
                mem.append(f"enterL{k+1}: {{ formL{k+1}() }}")
            elif reads == "some" and k > 1:
                mem.append(f"enterL{k+1}: {{ formL{k+1}(ctx) }}")
            else:
                mem.append(f"enterL{k+1}: {{ {ps} in formL{k+1}({newctx[reads]}) }}")
        A.append(f"func formL{k}({'_ ctx: Ctx' if has else ''}) -> {Cn(k)} {{ {Cn(k)}({', '.join(mem)}) }}\n")
    A.append("func makeHost() -> Instantiator<L1> { makeSeamHost(formL1()) }\n")
elif form == "Cf":
    # C formed once per carried set (the lead's 6.4.2 variant): a level whose child carries nothing new holds the child's
    # carrier as a `let`, formed once by the caller when the carried set's zone is formed (child first); only where a
    # level carries a new value is there an entry, which forms the new zone (its context and its carriers). The seam's
    # builder captures one word: the child carrier, or the seam's per-level context (carrier + the entry's arguments).
    cv = {"none": [], "some": [("id1", "Int")], "win": [("pm", "M")], "two": [("pm", "M"), ("pid", "Int")]}[reads]
    def eargs(k):
        if reads == "none": return None
        if reads == "some": return [("id", "Int")] if k == 1 else None
        if reads == "win": return [("m", "M")]
        return [("m", "M"), ("id", "Int")]
    Cn = lambda k: f"__safeDI_Host_L{k}Carrier"
    for k in range(1, D + 1):
        mem = [(f"hOfL{k}", "(_ id: Int, _ m: M) -> any H", True)]
        if k < D:
            ea = eargs(k)
            mem.append((f"l{k+1}", Cn(k + 1), False) if ea is None else (f"enterL{k+1}", "(" + ", ".join(f"_ {a}: {t}" for a, t in ea) + f") -> {Cn(k+1)}", True))
        F.append(f"public final class {Cn(k)} {{ " + " ".join(f"public let {a}: {t};" for a, t, _ in mem) + f" public init({', '.join(f'{a}: ' + ('@escaping ' if c else '') + t for a, t, c in mem)}) {{ " + " ".join(f"self.{a} = {a};" for a, _, _ in mem) + " } }\n")
    for k in range(1, D + 1):
        body = f"func buildL{k}(_ id: Int, _ c: {Cn(k)}) -> L{k} {{ let m = M(); let h = c.hOfL{k}(id, m)"
        if k == D:
            body += f"; return L{k}(id: id, m: m, h: h) }}\n"
        else:
            ea = eargs(k)
            if ea is None:
                body += f"; let n = c.l{k+1}; return L{k}(id: id, m: m, h: h, next: Instantiator<L{k+1}> {{ buildL{k+1}($0, n) }}) }}\n"
            else:
                F.append(f"final class __safeDI_L{k}Level {{ let carrier: {Cn(k)}; " + " ".join(f"let {a}: {t};" for a, t in ea) + f" init(carrier: {Cn(k)}, {', '.join(f'{a}: {t}' for a, t in ea)}) {{ self.carrier = carrier; " + " ".join(f"self.{a} = {a};" for a, _ in ea) + " } }\n")
                body += f"; let level = __safeDI_L{k}Level(carrier: c, {', '.join(f'{a}: {a}' for a, _ in ea)}); return L{k}(id: id, m: m, h: h, next: Instantiator<L{k+1}> {{ buildL{k+1}($0, level.carrier.enterL{k+1}({', '.join(f'level.{a}' for a, _ in ea)})) }}) }}\n"
        F.append(body)
    F.append(f"public func makeSeamHost(_ c: {Cn(1)}) -> Instantiator<L1> {{ Instantiator<L1> {{ buildL1($0, c) }} }}\n")
    A.append("enum StaticFills {\n")
    for k in range(1, D + 1):
        ps = "".join(f", {a}: {t}" for a, t in cv) if k > 1 else ""
        A.append(f"    static func hOfL{k}(id: Int, m: M{ps}) -> any H {{ {fexpr(k)} }}\n")
    A.append("}\n")
    if cv:
        A.append("final class Ctx { " + " ".join(f"let {a}: {t};" for a, t in cv) + f" init({', '.join(f'{a}: {t}' for a, t in cv)}) {{ " + " ".join(f"self.{a} = {a};" for a, _ in cv) + " } }\n")
    newctx = {"some": "Ctx(id1: id)", "win": "Ctx(pm: m)", "two": "Ctx(pm: m, pid: id)"}
    # zones: maximal runs of levels joined by lets; zone j forms its carriers child first and returns level j's
    starts = [1] + [k + 1 for k in range(1, D) if eargs(k) is not None]
    for j in starts:
        end = j
        while end < D and eargs(end) is None: end += 1
        has = bool(cv) and j > 1
        lines = []
        for k in range(end, j - 1, -1):
            mem = [f"hOfL{k}: {{ id, m in StaticFills.hOfL{k}(id: id, m: m" + ("".join(f", {a}: ctx.{a}" for a, _ in cv) if has else "") + ") }"]
            if k < D:
                ea = eargs(k)
                if ea is None: mem.append(f"l{k+1}: c{k+1}")
                else: mem.append(f"enterL{k+1}: {{ {', '.join(a for a, _ in ea)} in zoneL{k+1}({newctx[reads]}) }}")
            lines.append(f"let c{k} = {Cn(k)}({', '.join(mem)})")
        A.append(f"func zoneL{j}({'_ ctx: Ctx' if has else ''}) -> {Cn(j)} {{ " + "; ".join(lines) + f"; return c{j} }}\n")
    A.append("func makeHost() -> Instantiator<L1> { makeSeamHost(zoneL1()) }\n")
elif form == "Cx":
    # The spec v4 form for chains: every level binds id and m, visible beneath, so every level has an entry taking them,
    # called when the parent forms the builder; the builder captures the child carrier it returned (one word). The caller
    # forms a zone (context and carriers, child first) where its fills read a new value, and otherwise returns the child's
    # pre-formed carrier, captured.
    cv = {"none": [], "some": [("id1", "Int")], "win": [("pm", "M")], "two": [("pm", "M"), ("pid", "Int")]}[reads]
    newzone = lambda k: {"none": False, "some": k == 1, "win": True, "two": True}[reads]   # does enterL(k+1) form a new zone
    Cn = lambda k: f"__safeDI_Host_L{k}Carrier"
    for k in range(1, D + 1):
        mem = [(f"hOfL{k}", "(_ id: Int, _ m: M) -> any H")]
        if k < D: mem.append((f"enterL{k+1}", f"(_ id: Int, _ m: M) -> {Cn(k+1)}"))
        F.append(f"public final class {Cn(k)} {{ " + " ".join(f"public let {a}: {t};" for a, t in mem) + f" public init({', '.join(f'{a}: @escaping {t}' for a, t in mem)}) {{ " + " ".join(f"self.{a} = {a};" for a, _ in mem) + " } }\n")
    for k in range(1, D + 1):
        body = f"func buildL{k}(_ id: Int, _ c: {Cn(k)}) -> L{k} {{ let m = M(); let h = c.hOfL{k}(id, m)"
        body += (f"; let n = c.enterL{k+1}(id, m); return L{k}(id: id, m: m, h: h, next: Instantiator<L{k+1}> {{ buildL{k+1}($0, n) }}) }}\n" if k < D else f"; return L{k}(id: id, m: m, h: h) }}\n")
        F.append(body)
    F.append(f"public func makeSeamHost(_ c: {Cn(1)}) -> Instantiator<L1> {{ Instantiator<L1> {{ buildL1($0, c) }} }}\n")
    A.append("enum StaticFills {\n")
    for k in range(1, D + 1):
        ps = "".join(f", {a}: {t}" for a, t in cv) if k > 1 else ""
        A.append(f"    static func hOfL{k}(id: Int, m: M{ps}) -> any H {{ {fexpr(k)} }}\n")
    A.append("}\n")
    if cv:
        A.append("final class Ctx { " + " ".join(f"let {a}: {t};" for a, t in cv) + f" init({', '.join(f'{a}: {t}' for a, t in cv)}) {{ " + " ".join(f"self.{a} = {a};" for a, _ in cv) + " } }\n")
    newctx = {"some": "Ctx(id1: id)", "win": "Ctx(pm: m)", "two": "Ctx(pm: m, pid: id)"}
    starts = [1] + [k + 1 for k in range(1, D) if newzone(k)]
    for j in starts:
        end = j
        while end < D and not newzone(end): end += 1
        has = bool(cv) and j > 1
        lines = []
        for k in range(end, j - 1, -1):
            mem = [f"hOfL{k}: {{ id, m in StaticFills.hOfL{k}(id: id, m: m" + ("".join(f", {a}: ctx.{a}" for a, _ in cv) if has else "") + ") }"]
            if k < D:
                mem.append(f"enterL{k+1}: {{ id, m in zoneL{k+1}({newctx[reads]}) }}" if newzone(k) else f"enterL{k+1}: {{ _, _ in c{k+1} }}")
            lines.append(f"let c{k} = {Cn(k)}({', '.join(mem)})")
        A.append(f"func zoneL{j}({'_ ctx: Ctx' if has else ''}) -> {Cn(j)} {{ " + "; ".join(lines) + f"; return c{j} }}\n")
    A.append("func makeHost() -> Instantiator<L1> { makeSeamHost(zoneL1()) }\n")
elif form == "ccl3":
    # Shared closure table: the root's generated code forms one table of non-capturing closures (every fill and every
    # forming entry); each zone stores the table and its carried values, so forming a zone allocates only the zone.
    F.append("nonisolated open class Fills {\n    public init() {}\n")
    for k in range(1, D + 1):
        F.append(f"    open func hOfL{k}(id: Int, m: M) -> any H {{ fatalError(\"SafeDI: unfilled hOfL{k}\") }}\n")
        if k < D: F.append(f"    open func enterL{k+1}(id: Int, m: M) -> Fills {{ fatalError(\"SafeDI: unentered enterL{k+1}\") }}\n")
    F.append("}\n")
    for k in range(1, D + 1):
        F.append(f"func buildL{k}(_ id: Int, _ f: Fills) -> L{k} {{ let m = M(); let h = f.hOfL{k}(id: id, m: m)" + (f"; let g = f.enterL{k+1}(id: id, m: m); return L{k}(id: id, m: m, h: h, next: Instantiator<L{k+1}> {{ buildL{k+1}($0, g) }}) }}\n" if k < D else f"; return L{k}(id: id, m: m, h: h) }}\n"))
    F.append("public func makeSeamHost(_ f: Fills) -> Instantiator<L1> { Instantiator<L1> { buildL1($0, f) } }\n")
    cv = {"none": [], "some": [("id1", "Int")], "win": [("pm", "M")], "two": [("pm", "M"), ("pid", "Int")]}[reads]
    A.append("enum StaticFills {\n")
    for k in range(1, D + 1):
        ps = "".join(f", {a}: {t}" for a, t in cv) if k > 1 else ""
        A.append(f"    static func hOfL{k}(id: Int, m: M{ps}) -> any H {{ {fexpr(k)} }}\n")
    A.append("}\n")
    CT = "(Int, M" + "".join(f", {t}" for _, t in cv) + ") -> any H"
    tf = [("h1", "(Int, M) -> any H")] + [(f"h{k}", CT) for k in range(2, D + 1)]
    A.append("nonisolated final class Table { " + " ".join(f"let {a}: {t};" for a, t in tf) + f" init({', '.join(f'{a}: @escaping {t}' for a, t in tf)}) {{ " + " ".join(f"self.{a} = {a};" for a, _ in tf) + " } }\n")
    args = "".join(f", {a}" for a, _ in cv)
    if reads == "none":
        A.append("nonisolated final class Root: Fills { let t: Table; init(t: Table) { self.t = t }\n" + "".join(f"    override func hOfL{k}(id: Int, m: M) -> any H {{ t.h{k}(id, m) }}\n" + (f"    override func enterL{k+1}(id: Int, m: M) -> Fills {{ self }}\n" if k < D else "") for k in range(1, D + 1)) + "}\n")
    else:
        nx = {"some": "id1: id", "win": "pm: m", "two": "pm: m, pid: id"}[reads]
        A.append(f"nonisolated final class Root: Fills {{ let t: Table; init(t: Table) {{ self.t = t }}\n    override func hOfL1(id: Int, m: M) -> any H {{ t.h1(id, m) }}\n    override func enterL2(id: Int, m: M) -> Fills {{ Z2(t: t, {nx}) }} }}\n")
        fl = "".join(f"let {a}: {t}; " for a, t in cv); il = ", ".join(f"{a}: {t}" for a, t in cv); asg = " ".join(f"self.{a} = {a};" for a, _ in cv)
        if reads == "some":
            A.append(f"nonisolated final class Z2: Fills {{ let t: Table; {fl}init(t: Table, {il}) {{ self.t = t; {asg} }}\n" + "".join(f"    override func hOfL{k}(id: Int, m: M) -> any H {{ t.h{k}(id, m{args}) }}\n" + (f"    override func enterL{k+1}(id: Int, m: M) -> Fills {{ self }}\n" if k < D else "") for k in range(2, D + 1)) + "}\n")
        else:
            for k in range(2, D + 1):
                ent = f"    override func enterL{k+1}(id: Int, m: M) -> Fills {{ Z{k+1}(t: t, {nx}) }}\n" if k < D else ""
                A.append(f"nonisolated final class Z{k}: Fills {{ let t: Table; {fl}init(t: Table, {il}) {{ self.t = t; {asg} }}\n    override func hOfL{k}(id: Int, m: M) -> any H {{ t.h{k}(id, m{args}) }}\n{ent}}}\n")
    targs = ["h1: { id, m in StaticFills.hOfL1(id: id, m: m) }"] + [f"h{k}: {{ id, m" + "".join(f", {a}" for a, _ in cv) + f" in StaticFills.hOfL{k}(id: id, m: m" + "".join(f", {a}: {a}" for a, _ in cv) + ") }" for k in range(2, D + 1)]
    A.append("func makeHost() -> Instantiator<L1> { makeSeamHost(Root(t: Table(" + ", ".join(targs) + "))) }\n")
elif form == "tw":
    # The Sendable twin alone (every place under a @Sendable builder): one final Sendable class per seam, optional fill
    # closures (a guard-let trap where unreachable), non-optional entries with an explicit keep, init with no defaults.
    C = "__safeDI_Host_SendableFills"
    F.append("public enum __safeDI_Entry<T: Sendable>: Sendable { case keep; case enter(@Sendable (_ id: Int, _ m: M) -> T) }\n")
    fl = [(f"hOfL{k}", "(@Sendable (_ id: Int, _ m: M) -> any H)?") for k in range(1, D + 1)] + [(f"enterL{k}", f"__safeDI_Entry<{C}>") for k in range(2, D + 1)]
    F.append(f"public final class {C}: Sendable {{\n" + "".join(f"    let {a}: {t}\n" for a, t in fl) + f"    public init({', '.join(f'{a}: {t}' for a, t in fl)}) {{ " + "; ".join(f"self.{a} = {a}" for a, _ in fl) + " }\n}\n")
    for k in range(1, D + 1):
        body = f"func buildL{k}(_ id: Int, _ c: {C}) -> L{k} {{ let m = M(); guard let fill = c.hOfL{k} else {{ fatalError(\"SafeDI: unfilled hOfL{k}\") }}; let h = fill(id, m)"
        if k < D:
            body += f"; let n: {C}; switch c.enterL{k+1} {{ case .keep: n = c; case let .enter(e): n = e(id, m) }}; return L{k}(id: id, m: m, h: h, next: Instantiator<L{k+1}> {{ buildL{k+1}($0, n) }}) }}\n"
        else:
            body += f"; return L{k}(id: id, m: m, h: h) }}\n"
        F.append(body)
    F.append(f"public func makeSeamHost(_ c: {C}) -> Instantiator<L1> {{ Instantiator<L1> {{ buildL1($0, c) }} }}\n")
    cv = {"none": [], "some": [("id1", "Int")], "win": [("pm", "M")], "two": [("pm", "M"), ("pid", "Int")]}[reads]
    A.append("enum StaticFills {\n")
    for k in range(1, D + 1):
        ps = "".join(f", {a}: {t}" for a, t in cv) if k > 1 else ""
        A.append(f"    nonisolated static func hOfL{k}(id: Int, m: M{ps}) -> any H {{ {fexpr(k)} }}\n")
    A.append("}\n")
    def form_call(fills, enters):  # fills: {k: closure}, enters: {k: closure}; everything else nil / .keep
        parts = [f"hOfL{k}: {fills.get(k, 'nil')}" for k in range(1, D + 1)] + [f"enterL{k}: {('.enter(' + enters[k] + ')') if k in enters else '.keep'}" for k in range(2, D + 1)]
        return f"{C}(" + ", ".join(parts) + ")"
    if reads == "none":
        A.append("func makeHost() -> Instantiator<L1> { makeSeamHost(" + form_call({k: f"{{ id, m in StaticFills.hOfL{k}(id: id, m: m) }}" for k in range(1, D + 1)}, {}) + ") }\n")
    elif reads == "some":
        A.append("func formL2(id1: Int) -> " + C + " { " + form_call({k: f"{{ id, m in StaticFills.hOfL{k}(id: id, m: m, id1: id1) }}" for k in range(2, D + 1)}, {}) + " }\n")
        A.append("func makeHost() -> Instantiator<L1> { makeSeamHost(" + form_call({1: "{ id, m in StaticFills.hOfL1(id: id, m: m) }"}, {2: "{ id, _ in formL2(id1: id) }"}) + ") }\n")
    else:
        sig = ", ".join(f"{a}: {t}" for a, t in cv); pa = ", ".join(f"{a}: {a}" for a, _ in cv)
        nx = "pm: m" if reads == "win" else "pm: m, pid: id"
        for k in range(2, D + 1):
            ent = {k + 1: f"{{ id, m in formL{k+1}({nx}) }}"} if k < D else {}
            A.append(f"func formL{k}({sig}) -> {C} {{ " + form_call({k: f"{{ id, m in StaticFills.hOfL{k}(id: id, m: m, {pa}) }}"}, ent) + " }\n")
        A.append("func makeHost() -> Instantiator<L1> { makeSeamHost(" + form_call({1: "{ id, m in StaticFills.hOfL1(id: id, m: m) }"}, {2: f"{{ id, m in formL2({nx}) }}"}) + ") }\n")
A.append("import Foundation\n@inline(never) func walk(_ host: Instantiator<L1>) -> Int {\n    " + walk + "    return s\n}\n")
A.append("""let host = makeHost()
var best = Double.infinity; var sink = 0
for _ in 0..<41 { let t = DispatchTime.now().uptimeNanoseconds; for _ in 0..<20000 { sink &+= walk(""" + ("makeHost()" if rebuild else "host") + """) }; best = min(best, Double(DispatchTime.now().uptimeNanoseconds - t) / 20000) }
print(String(format: "%.0f ns per walk (sink %d)", best, sink))
""")
open(os.path.join(out, "Feature.swift"), "w").write("".join(F))
open(os.path.join(out, "App.swift"), "w").write("".join(A))
