#!/usr/bin/env python3
"""n1.py ROOT SHAPE N FORM: writes ROOT/<module>/Types.swift and ROOT/modules.txt ("name dep,dep" per line, in build order).
SHAPE e6d (N seams, each with a leaf and a hole `any Api` App fulfills) n1 (N screens that each receive the next three screens' builders, so they form a loop) or n1flat (the same without the loop).
FORM seam (two modules, generateDependencyTree: true), inline2 (two modules, plain @Instantiable), inline1 (one module)."""
import os, sys
root, shape, n, form = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
SEAM = "@Instantiable(generateDependencyTree: true)" if form == "seam" else "@Instantiable"

def declaration(name, properties, attribute="@Instantiable"):
    if not properties:
        return f"{attribute}\npublic final class {name}: Instantiable {{\n    public init() {{}}\n}}\n"
    parameters = [p.split(" let ")[1] for p in properties]
    labels = [p.split(":")[0] for p in parameters]
    assignments = "\n".join(f"        self.{l} = {l}" for l in labels)
    stored = "\n".join(f"    {p}" for p in properties)
    return f"{attribute}\npublic final class {name}: Instantiable {{\n    public init({', '.join(parameters)}) {{\n{assignments}\n    }}\n\n{stored}\n}}\n"

DEFAULT_API = "@Instantiable(fulfillingAdditionalTypes: [Api.self])\npublic final class DefaultApi: Api, Instantiable {\n    public init() {}\n}\n"
if shape == "e6d":
    feature = "public protocol Api {}\n\n"
    for i in range(n):
        feature += declaration(f"Leaf{i}", []) + "\n" + declaration(f"Seam{i}", [f"@Instantiated let leaf: Leaf{i}", "@Instantiated let api: any Api"], SEAM) + "\n"
    app = DEFAULT_API + "\n" + declaration("Root", [f"@Instantiated let seam{i}: Seam{i}" for i in range(n)], "@Instantiable(isRoot: true)")
elif shape in ("n1", "n1flat"):
    feature = "public protocol Api {}\n\n"
    feature += declaration("Home", [f"@Instantiated let screen{s}Builder: Instantiator<Screen{s}>" for s in range(n)], SEAM)
    for s in range(n):
        received = [(s + o) % n for o in (1, 2, 3)] if shape == "n1" else []
        feature += "\n" + declaration(f"Screen{s}", ["@Forwarded let id: Int", "@Instantiated let api: any Api"] + [f"@Received let screen{o}Builder: Instantiator<Screen{o}>" for o in received])
    app = DEFAULT_API + "\n" + declaration("Root", ["@Instantiated let home: Home"], "@Instantiable(isRoot: true)")
modules = [("App", [], "import SafeDI\n\n" + feature + "\n" + app)] if form == "inline1" else [("Feature", [], "import SafeDI\n\n" + feature), ("App", ["Feature"], "import Feature\nimport SafeDI\n\n" + app)]
for name, _, source in modules:
    os.makedirs(f"{root}/{name}", exist_ok=True)
    open(f"{root}/{name}/Types.swift", "w").write(source)
open(f"{root}/modules.txt", "w").write("".join(f"{name} {','.join(deps)}\n" for name, deps, _ in modules))
