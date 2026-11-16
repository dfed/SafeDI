"""make_wide.py OUT DEPTH WIDTH FANOUT [mock] [modules=M]: a layered single- or multi-module production tree.
Layer 0 has one root. Each type in layer l instantiates FANOUT types of layer l+1 (Instantiator for every third),
receives `logger`, `session` (instantiated by the root), and every other type receives its parent layer's
`ctx<l-1>` that its parent instantiates. With mock, every type has generateMock: true. With modules=M, layer types are
spread across M modules by layer (module k holds layers whose index mod M... simple: by layer bucket)."""
import os, random, sys
out, depth, width, fanout = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
mock = "mock" in sys.argv[5:]
modules = next((int(a.split("=")[1]) for a in sys.argv[5:] if a.startswith("modules=")), 1)
rng = random.Random(3)
attr_mock = "generateMock: true" if mock else ""
os.makedirs(out, exist_ok=True)
layers = [["Root"]] + [[f"T{l}_{i}" for i in range(width)] for l in range(1, depth + 1)]
module_of_layer = lambda l: "App" if l == 0 else f"M{(depth - l) * modules // depth}"
files = {}
def emit(module, name, attrs, decls):
    lines = ["import SafeDI", "", f"@Instantiable({attrs})" if attrs else "@Instantiable", f"public final class {name} {{"]
    lines.append("\tpublic init(" + ", ".join(f"{lab}: {t}" for _, lab, t in decls) + ") {")
    lines += [f"\t\tself.{lab} = {lab}" for _, lab, _ in decls] + ["\t}", ""]
    lines += [f"\t{w} let {lab}: {t}" for w, lab, t in decls] + ["}", ""]
    files.setdefault(module, []).append("\n".join(lines))
for l, names in enumerate(layers):
    for i, name in enumerate(names):
        decls = []
        if l == 0:
            decls += [("@Instantiated", "logger", "Logger"), ("@Instantiated", "session", "Session")]
        else:
            decls += [("@Received", "logger", "Logger")]
            if i % 2 == 0: decls.append(("@Received", "session", "Session"))
            if l > 1 and i % 3 == 0: decls.append(("@Received", f"ctx{l-1}", f"Ctx{l-1}"))
        if l < depth:
            if l >= 1: decls.append(("@Instantiated", f"ctx{l}", f"Ctx{l}"))
            for t in sorted(rng.sample(range(width), fanout)):
                child = layers[l + 1][t]
                if t % 3 == 0: decls.append(("@Instantiated", f"{child[0].lower()}{child[1:]}Builder", f"Instantiator<{child}>"))
                else: decls.append(("@Instantiated", f"{child[0].lower()}{child[1:]}", child))
        attrs = ", ".join(a for a in (("isRoot: true" if l == 0 else ""), attr_mock) if a)
        emit(module_of_layer(l), name, attrs, decls)
    if 1 <= l < depth:
        emit(module_of_layer(l), f"Ctx{l}", attr_mock, [("@Received", "logger", "Logger")])
emit(module_of_layer(depth), "Logger", attr_mock, [])
emit(module_of_layer(depth), "Session", attr_mock, [("@Received", "logger", "Logger")])
order = sorted({module_of_layer(l) for l in range(1, depth + 1)}, key=lambda m: -int(m[1:])) + ["App"]
with open(f"{out}/modules.txt", "w") as h:
    for k, m in enumerate(order):
        os.makedirs(f"{out}/{m}", exist_ok=True)
        open(f"{out}/{m}/Types.swift", "w").write("\n".join(files[m]))
        h.write(f"{m} generate {' '.join(order[:k])}\n")
