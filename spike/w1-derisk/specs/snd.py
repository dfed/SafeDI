import os
VARIANT = os.environ["SHAPE"]   # sdb: Db is Sendable; ndb: Db is not
DIR = f"SND/{VARIANT}"
PROTOCOLS = "public protocol Api: AnyObject, Sendable {}\n\n"
MODULES = [
    ("Inner", [], [swift_type("A", [("inst", "api", "any Api")], seam=True, sendable=True)]),
    ("Feature", ["Inner"], [
        swift_type("Db", [], sendable=(VARIANT == "sdb")),
        swift_type("Store", [("inst", "db", "Db"), ("inst", "aBuilder", "SendableInstantiator<A>")], seam=True),
    ]),
    ("App", ["Feature", "Inner"], [
        swift_type("LiveApi", [("recv", "db", "Db")], fulfills="Api", sendable=(VARIANT == "sdb")),
        swift_type("Root", [("inst", "store", "Store")], root=True),
    ]),
]
WALK = """\tlet a1 = root.store.aBuilder.instantiate()
\tlet a2 = root.store.aBuilder.instantiate()
\tprint("trace:")
\tRegistry.printTrace()
\tRegistry.printAlive("holding everything")
\twithExtendedLifetime((root, a1)) {}
\treturn a2"""
