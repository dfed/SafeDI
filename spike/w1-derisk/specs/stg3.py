DIR = "STG3/base"
PROTOCOLS = "public protocol Api: AnyObject {}\n\n"
def level(k, inner):
    return [swift_type(f"M{k}", []), swift_type(f"Badge{k}", [("recv", "a", inner)]),
            swift_type(f"S{k}", [("inst", f"m{k}", f"M{k}"), ("inst", "a", inner), ("inst", f"badge{k}", f"Badge{k}"), ("inst", "b", inner)], seam=True)]
MODULES = [
    ("Three", [], [swift_type("S3", [("inst", "api", "any Api")], seam=True)]),
    ("Two", ["Three"], level(2, "S3")),
    ("One", ["Three", "Two"], level(1, "S2")),
    ("App", ["One", "Three", "Two"], [
        swift_type("LiveApi", [("recv", "m1", "M1"), ("opt", "badge1", "Badge1?"), ("recv", "m2", "M2"), ("opt", "badge2", "Badge2?")], fulfills="Api"),
        swift_type("Root", [("inst", "s1", "S1")], root=True),
    ]),
]
WALK = """\tvar all: [AnyObject] = []
\tfor s2 in [root.s1.a, root.s1.b] {
\t\tall.append(s2)
\t\tfor s3 in [s2.a, s2.b] { all.append(s3) }
\t}
\tprint("trace:")
\tRegistry.printTrace()
\tRegistry.printAlive("holding everything")
\twithExtendedLifetime((root, all)) {}
\treturn all[2]"""
