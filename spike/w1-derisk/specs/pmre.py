DIR = "PMRE/base"
PROTOCOLS = "public protocol Gadget: AnyObject {}\n\n"
MODULES = [
    ("Feature", [], [
        swift_type("Logger", []),
        swift_type("Mark", [("recv", "gadget", "any Gadget")]),
        swift_type("Service", [("inst", "gadget", "any Gadget"), ("inst", "mark", "Mark"), ("inst", "xBuilder", "Instantiator<X>")], seam=True),
        swift_type("X", [("inst", "logger", "Logger"), ("inst", "serviceBuilder", "Instantiator<Service>")], seam=True),
    ]),
    ("App", ["Feature"], [
        swift_type("LiveGadget", [("recv", "logger", "Logger"), ("opt", "mark", "Mark?")], fulfills="Gadget"),
        swift_type("Root", [("inst", "logger", "Logger"), ("inst", "service", "Service")], root=True),
    ]),
]
WALK = """\t_ = root
\tlet top = rootUnderTest()
\tlet x1 = top.service.xBuilder.instantiate()
\tlet s2 = x1.serviceBuilder.instantiate()
\tlet x2 = s2.xBuilder.instantiate()
\tlet s3 = x2.serviceBuilder.instantiate()
\tlet x3 = s3.xBuilder.instantiate()
\tlet s4 = x3.serviceBuilder.instantiate()
\tprint("trace:")
\tRegistry.printTrace()
\tRegistry.printAlive("holding everything")
\twithExtendedLifetime((top, x1, s2, x2, s3, x3)) {}
\treturn s4"""
