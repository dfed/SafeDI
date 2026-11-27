import random, sys
def gen(seed, reverse=False):
    r = random.Random(seed)
    L = ["import SafeDI"]
    def cls(name, deps, attrs="", conf=", Sendable", order=True):
        if reverse and order: deps = list(reversed(deps))
        params = ", ".join(f"{l}: {t}" for _, l, t in deps)
        body = " ".join(f"self.{l} = {l};" for _, l, t in deps)
        L.append(f"@Instantiable{attrs} public final class {name}: Instantiable{conf} {{")
        L.append(f"    public init({params}) {{ {body} }}")
        for m, l, t in deps: L.append(f"    {m} let {l}: {t}")
        L.append("}")
    nx = r.randint(1, 2)
    labels = [f"x{i}" for i in range(nx)]
    base = []   # per label: ("X", type) or ("P", protocol)
    for i in range(nx):
        L.append(f"public protocol Q{i}: Sendable {{}}")
        cls(f"X{i}", [], conf=f", Q{i}")
        base.append(f"Q{i}" if r.random() < 0.25 else f"X{i}")
    cls("Other", [])
    fam = [("builder" if r.random() < 0.25 else "value") for _ in range(nx)]
    mix = r.random() < 0.12
    def inst(i, form):
        B = base[i]; lab = labels[i]
        m = f'@Instantiated(fulfilledByType: "X{i}")' if B.startswith("Q") else "@Instantiated"
        T = {"val": B, "lazy": f"LazilyInstantiated<{B}>", "slazy": f"SendableLazilyInstantiated<{B}>",
             "builder": f"Instantiator<{B}>", "sbuilder": f"SendableInstantiator<{B}>"}[form]
        return (m, lab, T)
    readers = []
    for k in range(r.randint(1, 3)):
        deps = []
        for i, lab in enumerate(labels):
            B = base[i]
            if mix: pool = ["none", "req", "reqlazy", "reqbuilder", "opt", "opt", "optlazy", "optslazy", "optbuilder", "optsbuilder", "rename", "optrename", "optrename"]
            elif fam[i] == "value": pool = ["none", "req", "opt", "opt", "optlazy", "optslazy", "rename", "rename", "optrename", "optrename", "reqlazy"]
            else: pool = ["none", "reqbuilder", "optbuilder", "optbuilder", "optsbuilder"]
            c = r.choice(pool)
            O = "@Received(onlyIfAvailable: true)"
            if c == "req": deps.append(("@Received", lab, B))
            elif c == "reqlazy": deps.append(("@Received", lab, f"LazilyInstantiated<{B}>"))
            elif c == "reqbuilder": deps.append(("@Received", lab, f"Instantiator<{B}>"))
            elif c == "opt": deps.append((O, lab, B + "?"))
            elif c == "optlazy": deps.append((O, lab, f"LazilyInstantiated<{B}>?"))
            elif c == "optslazy": deps.append((O, lab, f"SendableLazilyInstantiated<{B}>?"))
            elif c == "optbuilder": deps.append((O, lab, f"Instantiator<{B}>?"))
            elif c == "optsbuilder": deps.append((O, lab, f"SendableInstantiator<{B}>?"))
            elif c == "rename": deps.append((f'@Received(fulfilledByDependencyNamed: "{lab}", ofType: {B}.self)', f"r{k}{lab}", B))
            elif c == "optrename": deps.append((f'@Received(fulfilledByDependencyNamed: "{lab}", ofType: {B}.self, onlyIfAvailable: true)', f"r{k}{lab}", B + "?"))
        if deps and r.random() < 0.25:
            # a child beneath the reader that reads the rename or the label again
            m, l, t = r.choice(deps)
            if "onlyIfAvailable" in m: cls(f"S{k}", [("@Received(onlyIfAvailable: true)", l, t)])
            else: cls(f"S{k}", [("@Received", l, t)])
            deps.append(("@Instantiated", f"s{k}", f"S{k}"))
        cls(f"R{k}", deps, attrs="(generateMock: true)" if r.random() < 0.1 else "")
        readers.append(f"R{k}")
    def child(kid):
        w = r.choice(["val", "val", "val", "inst", "lazy", "sinst", "slazy"])
        lab = kid.lower()
        return {"val": ("@Instantiated", lab, kid), "inst": ("@Instantiated", lab + "Builder", f"Instantiator<{kid}>"),
                "sinst": ("@Instantiated", lab + "Builder", f"SendableInstantiator<{kid}>"), "lazy": ("@Instantiated", lab, f"LazilyInstantiated<{kid}>"),
                "slazy": ("@Instantiated", lab, f"SendableLazilyInstantiated<{kid}>")}[w]
    mids = []
    for k in range(r.randint(1, 3)):
        deps = [child(kid) for kid in r.sample(readers, r.randint(1, len(readers))) + (r.sample(mids, 1) if mids and r.random() < 0.5 else [])]
        if r.random() < 0.25:
            i = r.randrange(nx)
            deps.insert(r.randrange(len(deps) + 1), inst(i, r.choice(["val", "lazy", "slazy", "builder"] if mix else (["val", "lazy", "slazy"] if fam[i] == "value" else ["builder", "sbuilder"]))))
        cls(f"M{k}", deps, attrs="(generateMock: true)" if r.random() < 0.1 else "")
        mids.append(f"M{k}")
    parents = []; rootdeps = []
    for k in range(r.randint(2, 4)):
        deps = []; forwarded = r.random() < 0.15
        for i, lab in enumerate(labels):
            c = r.choice(["absent", "val", "val", "lazy", "slazy", "builder", "sbuilder", "other"] if mix else (["absent", "val", "val", "lazy", "lazy", "slazy"] if fam[i] == "value" else ["absent", "builder", "builder", "sbuilder"]))
            if forwarded and r.random() < 0.6: deps.append(("@Forwarded", lab, base[i]))
            elif c == "other": deps.append(("@Instantiated", lab, "Other"))
            elif c != "absent": deps.append(inst(i, c))
        for kid in r.sample(mids, r.randint(1, len(mids))):
            deps.insert(r.randrange(len(deps) + 1), child(kid))
        cls(f"P{k}", deps)
        if any(m == "@Forwarded" for m, _, _ in deps):
            fw = ", ".join(t for m, _, t in deps if m == "@Forwarded")
            rootdeps.append(("@Instantiated", f"p{k}Builder", f"Instantiator<P{k}>"))
        else:
            rootdeps.append(r.choice([("@Instantiated", f"p{k}", f"P{k}"), ("@Instantiated", f"p{k}", f"P{k}"), ("@Instantiated", f"p{k}Builder", f"Instantiator<P{k}>")]))
    for i, lab in enumerate(labels):
        c = r.choice(["absent", "absent", "val", "lazy", "slazy", "builder"] if mix else (["absent", "absent", "val", "lazy", "slazy"] if fam[i] == "value" else ["absent", "absent", "builder"]))
        if c != "absent": rootdeps.insert(r.randrange(len(rootdeps) + 1), inst(i, c))
    cls("Root", rootdeps, "(isRoot: true)")
    return "\n".join(L) + "\n"
if __name__ == "__main__":
    print(gen(int(sys.argv[1]), len(sys.argv) > 2 and sys.argv[2] == "r"), end="")
