import os
VARIANT = os.environ["SHAPE"]
DIR = f"G2L/{VARIANT}"
S = VARIANT != "plain"
I = "SendableInstantiator" if S else "Instantiator"
PROTOCOLS = "public protocol Api: AnyObject%s {}\n\n" % (", Sendable" if S else "")
inner = [swift_type("A", [("inst", "api", "any Api")], seam=True, sendable=S)]
if VARIANT == "sfam":
    inner = [swift_type("InnerT", [("inst", "api", "any Api")], sendable=True),
             swift_type("A", [("inst", "tBuilder", "SendableInstantiator<InnerT>")], seam=True, sendable=True)]
MODULES = [
    ("Inner", [], inner),
    ("Feature", ["Inner"], [
        swift_type("Side", [("recv", "aBuilder", f"{I}<A>")], sendable=S),
        swift_type("Store", [("inst", "aBuilder", f"{I}<A>"), ("inst", "sideBuilder", f"{I}<Side>")], seam=True),
    ]),
    ("App", ["Feature", "Inner"], [
        swift_type("LiveApi", [("recv", "sideBuilder", f"{I}<Side>")], fulfills="Api", sendable=S),
        swift_type("Root", [("inst", "store", "Store")], root=True),
    ]),
]
get = "(a{n}.api as! LiveApi)" if VARIANT != "sfam" else "(a{n}.tBuilder.instantiate().api as! LiveApi)"
WALK = f"""\tlet a1 = root.store.aBuilder.instantiate()
\tlet side1 = {get.format(n=1)}.sideBuilder.instantiate()
\tlet a2 = side1.aBuilder.instantiate()
\tlet side2 = {get.format(n=2)}.sideBuilder.instantiate()
\tlet a3 = side2.aBuilder.instantiate()
\tlet a0 = root.store.sideBuilder.instantiate().aBuilder.instantiate()
\t_ = {get.format(n=0)}
\tprint("trace:")
\tRegistry.printTrace()
\tRegistry.printAlive("holding everything")
\twithExtendedLifetime((a1, side1, a2, side2, a0, root)) {{}}
\treturn a3"""
