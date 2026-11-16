"""F2: a loop of builders (Screen <-> Step through Instantiators) with `cache` declared again in every Screen and read
by `Model` inside the loop. F3: a lazy cycle (Preview lazily builds Editor again) with `Toolbar` reading `theme` inside
the cycle. Each in a production (`p`, isRoot) and a mock (`b`, generateMock) form."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "per-type-seam", "common"))
from typegen import swift_type, write_module

here = os.path.dirname(os.path.abspath(__file__))

def f2(production):
    return [
        swift_type("Cache", []),
        swift_type("Model", [("recv", "cache", "Cache")]),
        swift_type("Screen", [("inst", "cache", "Cache"), ("inst", "stepBuilder", "Instantiator<Step>")]),
        swift_type("Step", [("inst", "model", "Model"), ("inst", "screenBuilder", "Instantiator<Screen>")]),
        swift_type("Home", [("inst", "screen", "Screen")], attributes="(isRoot: true)" if production else "(generateMock: true)"),
    ]

def f3(production):
    return [
        swift_type("Theme", []),
        swift_type("Toolbar", [("recv", "theme", "Theme")]),
        swift_type("Editor", [("inst", "previewBuilder", "Instantiator<Preview>"), ("inst", "toolbar", "Toolbar")]),
        swift_type("Preview", [("inst", "theme", "Theme"), ("inst", "editor", "LazilyInstantiated<Editor>")]),
        swift_type("App", [("inst", "theme", "Theme"), ("inst", "editor", "Editor")], attributes="(isRoot: true)" if production else "(generateMock: true)"),
    ]

for fixture, maker in [("F2", f2), ("F3", f3)]:
    for variant, production in [("p", True), ("b", False)]:
        write_module(os.path.join(here, fixture, "shared", f"App-{variant}"), ["Harness", "SafeDI"], maker(production))
        base = os.path.join(here, fixture, variant)
        for module, content in [("Harness", "../../per-type-seam/common"), ("Main", "main"), ("App", f"shared/App-{variant}")]:
            os.makedirs(os.path.join(base, module), exist_ok=True)
            open(os.path.join(base, module, "shared"), "w").write(content + "\n")
        open(os.path.join(base, "modules.txt"), "w").write("Harness plain\nApp tool Harness\nMain plain App Harness\n")
        os.makedirs(os.path.join(base, "App", "Sources"), exist_ok=True)
    os.makedirs(os.path.join(here, fixture, "main"), exist_ok=True)
    open(os.path.join(here, fixture, "main", "main.swift"), "w").write("import App\nimport Harness\n\nrunFixture()\n")
