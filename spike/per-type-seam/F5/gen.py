"""F5, a screen that opens itself: Home { screenBuilder } -> Screen { @Forwarded id; api; <label>: Instantiator<Screen> }."""
import os
import sys

sys.path.insert(0, sys.argv[1])
from typegen import swift_type, write_module  # noqa: E402

for label in ["next", "screenBuilder"]:
    feature = [
        swift_type("Home", [("inst", "screenBuilder", "Instantiator<Screen>")], seam=True),
        swift_type("Screen", [("fwd", "id", "Int"), ("inst", "api", "any Api"), ("inst", label, "Instantiator<Screen>")]),
    ]
    app = [
        swift_type("Live", [("recv", "id", "Int")], fulfills="Api"),
        swift_type("Root", [("inst", "home", "Home")], root=True),
    ]
    protocol = "public protocol Api: AnyObject {}\n\n"
    configuration = "#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n\n"
    write_module(f"{label}/shared/Feature", ["Harness", "SafeDI"], feature, protocol + configuration)
    write_module(f"{label}/shared/App", ["Feature", "Harness", "SafeDI"], app)
    inline = [t.replace("(generateDependencyTree: true)", "") for t in feature]
    write_module(f"{label}/shared/Inline", ["Harness", "SafeDI"], inline + app, protocol)
    os.makedirs(f"{label}/main", exist_ok=True)
    if not os.path.exists(f"{label}/main/main.swift"):
        with open(f"{label}/main/main.swift", "w") as file:
            file.write(f"""import App
#if canImport(Feature)
import Feature
#endif
import Harness

/// Opens `depth` screens, each from the one before, with ids 1 through `depth`, and returns the deepest.
func walk(_ root: Root, depth: Int) -> Screen {{
\tvar screen = root.home.screenBuilder.instantiate(1)
\tfor id in 2...max(depth, 2) where id <= depth {{
\t\tscreen = screen.{label}.instantiate(id)
\t}}
\treturn screen
}}

do {{
\tlet root = Root()
\tlet deepest = walk(root, depth: 8)
\tprint("trace of eight levels:")
\tRegistry.printTrace()
\twithExtendedLifetime((root, deepest)) {{}}
}}
Registry.printAlive("after dropping everything")
for depth in [4, 8] {{
\tdo {{
\t\tlet deepest: Screen
\t\tdo {{
\t\t\tdeepest = walk(Root(), depth: depth)
\t\t}}
\t\tRegistry.printTrace()
\t\tRegistry.printAlive("holding only the screen at depth \\(depth)")
\t\twithExtendedLifetime(deepest) {{}}
\t}}
\tRegistry.printAlive("after dropping it")
}}
""")
    for variant, mode in [("a", None), ("b", "tool")]:
        directory = f"{label}/{variant}"
        os.makedirs(f"{directory}/Harness", exist_ok=True)
        os.makedirs(f"{directory}/Main", exist_ok=True)
        open(f"{directory}/Harness/shared", "w").write("../../common\n")
        open(f"{directory}/Main/shared", "w").write("main\n")
        if mode is None:
            os.makedirs(f"{directory}/App", exist_ok=True)
            open(f"{directory}/modules.txt", "w").write("Harness plain\nApp tool Harness\nMain plain App Harness\n")
            open(f"{directory}/App/shared", "w").write("shared/Inline\n")
        else:
            os.makedirs(f"{directory}/App", exist_ok=True)
            os.makedirs(f"{directory}/Feature", exist_ok=True)
            open(f"{directory}/modules.txt", "w").write("Harness plain\nFeature tool Harness\nApp tool Feature Harness\nMain plain App Harness\n")
            open(f"{directory}/Feature/shared", "w").write("shared/Feature\n")
            open(f"{directory}/App/shared", "w").write("shared/App\n")
