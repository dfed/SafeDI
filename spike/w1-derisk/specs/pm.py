import os
VARIANT = os.environ["SHAPE"]   # acc: fill reads nothing (main accepts); w1: fill reads logger (gap 3 shape)
DIR = f"PM/{VARIANT}"
PROTOCOLS = "public protocol Gadget: AnyObject {}\n\n"
MODULES = [
    ("Feature", [], [
        swift_type("Logger", []),
        swift_type("Service", [("inst", "gadget", "any Gadget"), ("inst", "xBuilder", "Instantiator<X>")], attributes="(generateDependencyTree: true, generateMock: .public)"),
        swift_type("X", [("inst", "logger", "Logger"), ("inst", "serviceBuilder", "Instantiator<Service>")]),
    ]),
    ("App", ["Feature"], [
        swift_type("LiveGadget", [] if VARIANT == "acc" else [("recv", "logger", "Logger")], fulfills="Gadget"),
        swift_type("Root", [("inst", "logger", "Logger"), ("inst", "service", "Service")], attributes="(isRoot: true, generateMock: .public)"),
    ]),
]
WALK = """\tlet mocked = Root.mock()
\tlet x1 = mocked.service.xBuilder.instantiate()
\tlet s2 = x1.serviceBuilder.instantiate()
\tlet x2 = s2.xBuilder.instantiate()
\tlet s3 = x2.serviceBuilder.instantiate()
\tprint("trace:")
\tRegistry.printTrace()
\tRegistry.printAlive("holding everything")
\twithExtendedLifetime((root, mocked, x1, s2, x2)) {}
\treturn s3"""
