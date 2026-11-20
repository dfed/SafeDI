# gen3.py SHAPE(chain) FORM READS D OUT -- spec v3 chain cells. Lead's gen.py extended:
# FORMS inline, cls (open class, every fill/entry overridden by generated caller classes), plv (per-level protocols),
# psm (Sendable per-seam protocol, no extension defaults: every conformer implements every requirement), clo (closure
# carrier: a seam-declared final class per level holding `fill` and `enter` closures the caller's generated code forms,
# each capturing only what it reads; carriers formed on entry).
# READS none | some (fills read id1 from L1) | win (fill of Lk reads m of L(k-1), one reference) | two (m and id of L(k-1)).
import sys, os
shape, form, reads, D, out = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
os.makedirs(out, exist_ok=True)
F = ["""public final class Instantiator<T> { let b: (Int) -> T; public init(_ b: @escaping (Int) -> T) { self.b = b }; public func instantiate(_ id: Int) -> T { b(id) } }
public final class M { public let x = 1; public init() {} }
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
A.append("import Foundation\n@inline(never) func walk(_ host: Instantiator<L1>) -> Int {\n    " + walk + "    return s\n}\n")
A.append("""let host = makeHost()
var best = Double.infinity; var sink = 0
for _ in 0..<41 { let t = DispatchTime.now().uptimeNanoseconds; for _ in 0..<20000 { sink &+= walk(host) }; best = min(best, Double(DispatchTime.now().uptimeNanoseconds - t) / 20000) }
print(String(format: "%.0f ns per walk (sink %d)", best, sink))
""")
open(os.path.join(out, "Feature.swift"), "w").write("".join(F))
open(os.path.join(out, "App.swift"), "w").write("".join(A))
