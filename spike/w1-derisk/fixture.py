"""fixture.py COMMON SPEC.py : SPEC defines MODULES = [(name, imports, [types]), …] (seam modules first, App last),
PROTOCOLS (prepended to the first module and to Inline), WALK (body of a closure returning the object held last),
and DIR. Writes DIR/shared/<Module>, DIR/shared/Inline, DIR/main/main.swift."""
import os, sys
sys.path.insert(0, sys.argv[1])
import typegen
spec = {"swift_type": typegen.swift_type}
exec(open(sys.argv[2]).read(), spec)
d = spec["DIR"]
configuration = "#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n\n"
inline = []
for index, (name, imports, types) in enumerate(spec["MODULES"]):
    extra = (spec["PROTOCOLS"] if index == 0 else "") + (configuration if name != "App" else "")
    typegen.write_module(f"{d}/shared/{name}", imports + ["Harness", "SafeDI"], types, extra)
    inline += [t.replace("(generateDependencyTree: true)", "").replace("generateDependencyTree: true, ", "") for t in types]
typegen.write_module(f"{d}/shared/Inline", ["Harness", "SafeDI"], inline, spec["PROTOCOLS"])
os.makedirs(f"{d}/main", exist_ok=True)
imports = "".join(f"#if canImport({n})\nimport {n}\n#endif\n" for n, _, _ in spec["MODULES"] if n != "App")
open(f"{d}/main/main.swift", "w").write(f"""import App
{imports}import Harness

var held: Any? = {{
\tlet root = Root()
{spec["WALK"]}
}}()
Registry.printAlive("holding only the last value")
held = nil
Registry.printAlive("after dropping everything")
""")
