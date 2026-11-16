"""F1: an internal mock with a promoted root (`service`), a flat parameter (`user`), overrides three deep, and `Leaf`
built at three places (under `a`, `b`, and `cBuilder`), reading `badge` only where `B` declares it."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "per-type-seam", "common"))
from typegen import swift_type, write_module

here = os.path.dirname(os.path.abspath(__file__))

def types(production):
    t = []
    t.append(swift_type("Service", []))
    t.append(swift_type("Badge", []))
    t.append(swift_type("Detail", [("recv", "service", "Service")]))
    t.append(swift_type("Leaf", [("recv", "service", "Service"), ("recv", "user", "User"), ("inst", "detail", "Detail"), ("opt", "badge", "Badge?")]))
    t.append(swift_type("A", [("inst", "leaf", "Leaf")]))
    t.append(swift_type("B", [("inst", "badge", "Badge"), ("inst", "leaf", "Leaf")]))
    t.append(swift_type("C", [("inst", "leaf", "Leaf")]))
    t.append(swift_type("Root", [("recv", "service", "Service"), ("fwd", "user", "User"), ("inst", "a", "A"), ("inst", "b", "B"), ("inst", "cBuilder", "Instantiator<C>")], attributes="(generateMock: true)"))
    if production:
        t.append(swift_type("Top", [("inst", "service", "Service"), ("inst", "rootBuilder", "Instantiator<Root>")], root=True))
    return t

user = '''public final class User: Traced {
    public init() { Registry.created(self, [:]) }
    public let tracker = Tracker("User")
}

'''
for variant, production in [("p", True), ("b", False)]:
    write_module(os.path.join(here, "F1", "shared", f"App-{variant}"), ["Harness", "SafeDI"], types(production), user)
