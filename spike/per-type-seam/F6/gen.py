"""F6, the @Sendable family. (i) `T { api }` built at a plain place and inside a `SendableInstantiator<T>`;
(ii) `Screen { api; again: SendableInstantiator<Screen> }` in a plain wrapper, a `@Sendable` function closing a cycle on it."""
import os
import sys

sys.path.insert(0, sys.argv[1])
from typegen import swift_type, write_module  # noqa: E402

shapes = {
    "i": (
        [
            swift_type("T", [("inst", "api", "any Api")], sendable=True),
            swift_type("Hub", [("inst", "t", "T"), ("inst", "tBuilder", "SendableInstantiator<T>")], seam=True),
        ],
        "hub",
        "Hub",
        """\tlet t2 = root.hub.tBuilder.instantiate()
\tlet t3 = root.hub.tBuilder.instantiate()
\tprint("trace:")
\tRegistry.printTrace()
\twithExtendedLifetime((root, t2, t3)) {}""",
    ),
    "ii": (
        [
            swift_type("Screen", [("inst", "api", "any Api"), ("inst", "again", "SendableInstantiator<Screen>")], sendable=True),
            swift_type("Home", [("inst", "screenBuilder", "Instantiator<Screen>")], seam=True),
        ],
        "home",
        "Home",
        """\tlet screen1 = root.home.screenBuilder.instantiate()
\tlet screen2 = screen1.again.instantiate()
\tlet screen3 = screen2.again.instantiate()
\tprint("trace:")
\tRegistry.printTrace()
\twithExtendedLifetime((root, screen1, screen2, screen3)) {}""",
    ),
}
for shape, (feature, property_label, seam, walk) in shapes.items():
    app = [
        swift_type("LiveApi", [], fulfills="Api", sendable=True),
        swift_type("Root", [("inst", property_label, seam)], root=True),
    ]
    protocol = "public protocol Api: AnyObject, Sendable {}\n\n"
    configuration = "#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n\n"
    write_module(f"{shape}/shared/Feature", ["Harness", "SafeDI"], feature, protocol + configuration)
    write_module(f"{shape}/shared/App", ["Feature", "Harness", "SafeDI"], app)
    inline = [t.replace("(generateDependencyTree: true)", "") for t in feature]
    write_module(f"{shape}/shared/Inline", ["Harness", "SafeDI"], inline + app, protocol)
    os.makedirs(f"{shape}/main", exist_ok=True)
    with open(f"{shape}/main/main.swift", "w") as file:
        file.write(f"""import App
#if canImport(Feature)
import Feature
#endif
import Harness

do {{
\tlet root = Root()
{walk}
}}
Registry.printAlive("after dropping everything")
""")
