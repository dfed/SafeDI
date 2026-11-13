#!/usr/bin/env python3
"""gen.py DIR KIND N USE [MACROS]
Writes N files T<i>.swift, one type each, plus Use.swift.
With LAYOUT=single in the environment, writes all N types to Types.swift instead.
KIND: class | struct
USE: none | construct | metatype | parameter
MACROS: both (default) | peer | member | none
        | methodpeer (no member macro; @NoopPeer on a method and a computed property, plain stored properties)
"""
import os, shutil, sys
d, kind, n, use = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
macros = sys.argv[5] if len(sys.argv) > 5 else "both"
shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
peer = "@NoopPeer " if macros in ("both", "peer") else ""
member = "@NoopMember\n" if macros in ("both", "member") else ""
final = "final " if kind == "class" else ""
for i in range(n):
    if macros == "methodpeer":
        with open(f"{d}/T{i}.swift", "w") as f:
            f.write(f"import NoopMacros\n\npublic {final}{kind} T{i} {{\n"
                    f"    var a: Int = {i}\n    var b: String = \"\"\n"
                    f"    @NoopPeer var c: Int {{ a }}\n    @NoopPeer func d() {{}}\n    public init() {{}}\n}}\n")
        continue
    with open(f"{d}/T{i}.swift", "w") as f:
        f.write(f"import NoopMacros\n\n{member}public {final}{kind} T{i} {{\n"
                f"    {peer}var a: Int = {i}\n    {peer}var b: String = \"\"\n    public init() {{}}\n}}\n")
body = {
    "none": "public func use() {}\n",
    "construct": "public func use() {\n" + "".join(f"    _ = T{i}()\n" for i in range(n)) + "}\n",
    "metatype": "public func use() -> [Any.Type] {\n    [\n" + "".join(f"        T{i}.self,\n" for i in range(n)) + "    ]\n}\n",
    "parameter": "".join(f"public func use{i}(_ value: T{i}) {{}}\n" for i in range(n)),
}[use]
if os.environ.get("LAYOUT") == "single":
    parts = []
    for i in range(n):
        text = open(f"{d}/T{i}.swift").read(); os.remove(f"{d}/T{i}.swift")
        parts.append(text if i == 0 else text.replace("import NoopMacros\n\n", ""))
    open(f"{d}/Types.swift", "w").write("\n".join(parts))
with open(f"{d}/Use.swift", "w") as f:
    f.write(body)
