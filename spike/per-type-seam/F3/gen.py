"""F3, a stale loop value in a public mock: the three modules of SafeDIToolPublicMockCycleRedeclarationTests.
generate_throwsError_whenMockFillsPublicMocksHoleWithTypeReadingValueCycleDeclaresAgain (Core, Feat, App).
`accepted/` is the neighbor main accepts (Live receives nothing), read for the shape of today's public mock."""
import os
import sys

sys.path.insert(0, sys.argv[1])
from typegen import swift_type, write_module  # noqa: E402

for shape, live in [("stale", [("recv", "cache", "Cache")]), ("accepted", [])]:
    core = [swift_type("Cache", [])]
    feat = [
        swift_type("Home", initializer_access="", properties=[("inst", "screen", "Screen")], attributes="(generateMock: .public)"),
        swift_type("Screen", initializer_access="", properties=[("inst", "cache", "Cache"), ("inst", "stepBuilder", "Instantiator<Step>")]),
        swift_type("Step", initializer_access="", properties=[("inst", "api", "any Api"), ("inst", "screenBuilder", "Instantiator<Screen>")]),
    ]
    app = [
        swift_type("Live", live, fulfills="Api"),
        swift_type("Root", [("inst", "home", "Home")], attributes="(generateMock: true)"),
    ]
    protocol = "public protocol Api: AnyObject {}\n\n"
    write_module(f"{shape}/shared/Core", ["Harness", "SafeDI"], core, protocol)
    write_module(f"{shape}/shared/Feat", ["Core", "Harness", "SafeDI"], feat)
    accessor = "#if DEBUG\n/// Main calls Root's internal mock through this.\npublic func rootMock() -> Root {\n    Root.mock()\n}\n#endif\n\n"
    write_module(f"{shape}/shared/App", ["Core", "Feat", "Harness", "SafeDI"], app, accessor)
    write_module(f"{shape}/shared/Inline", ["Harness", "SafeDI"], core + feat + app, protocol + accessor)
    for variant, modules in [("a", "Harness plain\nApp tool Harness\nMain plain App Harness\n"), ("b", "Harness plain\nCore tool Harness\nFeat tool Core Harness\nApp tool Core Feat Harness\nMain plain App Harness\n")]:
        directory = f"{shape}/{variant}"
        for module in ["Harness", "Main", "App"] + (["Core", "Feat"] if variant == "b" else []):
            os.makedirs(f"{directory}/{module}", exist_ok=True)
        open(f"{directory}/modules.txt", "w").write(modules)
        open(f"{directory}/Harness/shared", "w").write("../../common\n")
        open(f"{directory}/Main/shared", "w").write("main\n")
        if variant == "a":
            open(f"{directory}/App/shared", "w").write("shared/Inline\n")
        else:
            for module in ["Core", "Feat", "App"]:
                open(f"{directory}/{module}/shared", "w").write(f"shared/{module}\n")
    os.makedirs(f"{shape}/main", exist_ok=True)
    if not os.path.exists(f"{shape}/main/main.swift"):
        with open(f"{shape}/main/main.swift", "w") as file:
            file.write("""import App
#if canImport(Feat)
import Core
import Feat
#endif
import Harness

// Walks three levels of Root.mock(): each step's Live should receive its own screen's cache.
do {
\tlet root = rootMock()
\tlet step1 = root.home.screen.stepBuilder.instantiate()
\tlet screen2 = step1.screenBuilder.instantiate()
\tlet step2 = screen2.stepBuilder.instantiate()
\tlet screen3 = step2.screenBuilder.instantiate()
\tlet step3 = screen3.stepBuilder.instantiate()
\tprint("trace of three levels:")
\tRegistry.printTrace()
\twithExtendedLifetime((root, step1, screen2, step2, screen3, step3)) {}
}
Registry.printAlive("after dropping everything")
// Holds only screen 2's step: inline frees screen 1's cache.
do {
\tlet step2: Step
\tdo {
\t\tlet root = rootMock()
\t\tstep2 = root.home.screen.stepBuilder.instantiate().screenBuilder.instantiate().stepBuilder.instantiate()
\t}
\tRegistry.printTrace()
\tRegistry.printAlive("holding only screen 2's step")
\twithExtendedLifetime(step2) {}
}
Registry.printAlive("after dropping it")
""")
