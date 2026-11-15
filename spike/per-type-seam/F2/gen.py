"""F2, a loop through two types: Home { screenBuilder } -> Screen { cache; stepBuilder } -> Step { api; <label>: Instantiator<Screen> }."""
import os
import sys

sys.path.insert(0, sys.argv[1])
from typegen import swift_type, write_module  # noqa: E402

for label in ["next", "screenBuilder"]:
    feature = [
        swift_type("Cache", []),
        swift_type("Home", [("inst", "screenBuilder", "Instantiator<Screen>")], seam=True),
        swift_type("Screen", [("inst", "cache", "Cache"), ("inst", "stepBuilder", "Instantiator<Step>")]),
        swift_type("Step", [("inst", "api", "any Api"), ("inst", label, "Instantiator<Screen>")]),
    ]
    app = [
        swift_type("Live", [("recv", "cache", "Cache")], fulfills="Api"),
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

// Walks three levels: each screen's step builds a `Live` and opens the next screen through `{label}`.
do {{
\tlet root = Root()
\tlet screen1 = root.home.screenBuilder.instantiate()
\tlet step1 = screen1.stepBuilder.instantiate()
\tlet screen2 = step1.{label}.instantiate()
\tlet step2 = screen2.stepBuilder.instantiate()
\tlet screen3 = step2.{label}.instantiate()
\tlet step3 = screen3.stepBuilder.instantiate()
\tprint("trace of three levels:")
\tRegistry.printTrace()
\twithExtendedLifetime((root, screen1, step1, screen2, step2, screen3, step3)) {{}}
}}
Registry.printAlive("after dropping everything")
// Holds only the second level's step.
do {{
\tlet step2: Step
\tdo {{
\t\tlet root = Root()
\t\tstep2 = root.home.screenBuilder.instantiate().stepBuilder.instantiate().{label}.instantiate().stepBuilder.instantiate()
\t}}
\tRegistry.printTrace()
\tRegistry.printAlive("holding only step 2")
\twithExtendedLifetime(step2) {{}}
}}
Registry.printAlive("after dropping step 2")
""")
