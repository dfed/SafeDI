import os
VARIANT = os.environ["SHAPE"]   # req: Root declares logger; opt: fill reads Logger? and Root declares none; one: X is not a seam (control, gap 3 as w1-gaps probed it)
DIR = f"RE2/{VARIANT}"
PROTOCOLS = "public protocol Gadget: AnyObject {}\n\n"
x_attributes = "(generateDependencyTree: true)" if VARIANT != "one" else ""
MODULES = [
    ("Feature", [], [
        swift_type("Logger", []),
        swift_type("Service", [("inst", "gadget", "any Gadget"), ("inst", "xBuilder", "Instantiator<X>")], seam=True),
        swift_type("X", [("inst", "logger", "Logger"), ("inst", "serviceBuilder", "Instantiator<Service>")], attributes=x_attributes),
    ]),
    ("App", ["Feature"], [
        swift_type("LiveGadget", [("opt", "logger", "Logger?")] if VARIANT == "opt" else [("recv", "logger", "Logger")], fulfills="Gadget"),
        swift_type("Root", ([] if VARIANT == "opt" else [("inst", "logger", "Logger")]) + [("inst", "service", "Service")], root=True),
    ]),
]
WALK = """\tlet x1 = root.service.xBuilder.instantiate()
\tlet s2 = x1.serviceBuilder.instantiate()
\tlet x2 = s2.xBuilder.instantiate()
\tlet s3 = x2.serviceBuilder.instantiate()
\tlet x2b = s2.xBuilder.instantiate()
\tlet s3b = x2b.serviceBuilder.instantiate()
\tprint("trace:")
\tRegistry.printTrace()
\tRegistry.printAlive("holding everything")
\twithExtendedLifetime((root, x1, s2, x2, x2b, s3b)) {}
\treturn s3"""
