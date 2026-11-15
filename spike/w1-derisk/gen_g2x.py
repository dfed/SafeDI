"""G2X: gap 2's loop across a module boundary. Seam `A` (module Feature) has the hole `api`; App's `Store` declares
`aBuilder` (the call) and `sideBuilder`; the fill `LiveApi` receives `sideBuilder`; `Side` receives `aBuilder`.
Shapes: plain (Instantiator), sendable-call (SendableInstantiator at App's call and sibling),
sendable-family (the hole sits under a SendableInstantiator inside the seam)."""
import os, sys
sys.path.insert(0, sys.argv[1])
from typegen import swift_type, write_module

def main_swift(walk):
    return f"""import App
#if canImport(Feature)
import Feature
#endif
import Harness

var deepest: AnyObject? = {{
\tlet root = Root()
{walk}
}}()
Registry.printAlive("holding only the deepest")
withExtendedLifetime(deepest) {{}}
deepest = nil
Registry.printAlive("after dropping everything")

"""

shapes = {}
# plain
shapes["plain"] = dict(
    feature=[swift_type("A", [("inst", "api", "any Api")], seam=True)],
    app=[
        swift_type("LiveApi", [("recv", "sideBuilder", "Instantiator<Side>")], fulfills="Api"),
        swift_type("Side", [("recv", "aBuilder", "Instantiator<A>")]),
        swift_type("Store", [("inst", "aBuilder", "Instantiator<A>"), ("inst", "sideBuilder", "Instantiator<Side>")]),
        swift_type("Root", [("inst", "store", "Store")], root=True),
    ],
    protocol="public protocol Api: AnyObject {}\n\n",
    walk="""\tlet a1 = root.store.aBuilder.instantiate()
\tlet side1 = (a1.api as! LiveApi).sideBuilder.instantiate()
\tlet a2 = side1.aBuilder.instantiate()
\tlet side2 = (a2.api as! LiveApi).sideBuilder.instantiate()
\tlet a3 = side2.aBuilder.instantiate()
\tlet a0 = root.store.sideBuilder.instantiate().aBuilder.instantiate()
\tprint("trace:")
\tRegistry.printTrace()
\tRegistry.printAlive("holding everything")
\twithExtendedLifetime((a1, side1, a2, side2, a0, root)) {}
\treturn a3""",
)
# sendable call: App's call and sibling are SendableInstantiators.
shapes["scall"] = dict(
    feature=[swift_type("A", [("inst", "api", "any Api")], seam=True, sendable=True)],
    app=[
        swift_type("LiveApi", [("recv", "sideBuilder", "SendableInstantiator<Side>")], fulfills="Api", sendable=True),
        swift_type("Side", [("recv", "aBuilder", "SendableInstantiator<A>")], sendable=True),
        swift_type("Store", [("inst", "aBuilder", "SendableInstantiator<A>"), ("inst", "sideBuilder", "SendableInstantiator<Side>")]),
        swift_type("Root", [("inst", "store", "Store")], root=True),
    ],
    protocol="public protocol Api: AnyObject, Sendable {}\n\n",
    walk=None,
)
shapes["scall"]["walk"] = shapes["plain"]["walk"]
# sendable family: the hole is built inside a SendableInstantiator the seam's tree declares.
shapes["sfam"] = dict(
    feature=[
        swift_type("Inner", [("inst", "api", "any Api")], sendable=True),
        swift_type("A", [("inst", "innerBuilder", "SendableInstantiator<Inner>")], seam=True, sendable=True),
    ],
    app=[
        swift_type("LiveApi", [("recv", "sideBuilder", "SendableInstantiator<Side>")], fulfills="Api", sendable=True),
        swift_type("Side", [("recv", "aBuilder", "SendableInstantiator<A>")], sendable=True),
        swift_type("Store", [("inst", "aBuilder", "SendableInstantiator<A>"), ("inst", "sideBuilder", "SendableInstantiator<Side>")]),
        swift_type("Root", [("inst", "store", "Store")], root=True),
    ],
    protocol="public protocol Api: AnyObject, Sendable {}\n\n",
    walk="""\tlet a1 = root.store.aBuilder.instantiate()
\tlet i1 = a1.innerBuilder.instantiate()
\tlet side1 = (i1.api as! LiveApi).sideBuilder.instantiate()
\tlet a2 = side1.aBuilder.instantiate()
\tlet i2 = a2.innerBuilder.instantiate()
\tlet side2 = (i2.api as! LiveApi).sideBuilder.instantiate()
\tlet a3 = side2.aBuilder.instantiate()
\tlet i3 = a3.innerBuilder.instantiate()
\tlet a0 = root.store.sideBuilder.instantiate().aBuilder.instantiate()
\tprint("trace:")
\tRegistry.printTrace()
\tRegistry.printAlive("holding everything")
\twithExtendedLifetime((a1, i1, side1, a2, i2, side2, a3, a0, root)) {}
\treturn i3""",
)
configuration = "#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n\n"
for name, s in shapes.items():
    d = f"G2X/{name}"
    write_module(f"{d}/shared/Feature", ["Harness", "SafeDI"], s["feature"], s["protocol"] + configuration)
    write_module(f"{d}/shared/App", ["Feature", "Harness", "SafeDI"], s["app"])
    inline = [t.replace("(generateDependencyTree: true)", "") for t in s["feature"]]
    write_module(f"{d}/shared/Inline", ["Harness", "SafeDI"], inline + s["app"], s["protocol"])
    os.makedirs(f"{d}/main", exist_ok=True)
    open(f"{d}/main/main.swift", "w").write(main_swift(s["walk"]))
