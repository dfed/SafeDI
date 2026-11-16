"""F5: #646's graph (python3 make_screens.py OUT N SEED mock), with every type a traced class. Same random choices as
the issue's script: screens open three others through Instantiators and declare, receive, receive-if-available, or
do not mention `context`. Usage: F5_gen.py N SEED"""
import os, random, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "per-type-seam", "common"))
from typegen import swift_type, write_module

n, seed = int(sys.argv[1]), int(sys.argv[2])
rng = random.Random(seed)
here = os.path.dirname(os.path.abspath(__file__))
kinds = {"@Forwarded": "fwd", "@Received": "recv", "@Instantiated": "inst", "@Received(onlyIfAvailable: true)": "opt"}
types, roles = [], {}
for index in range(n):
    targets = rng.sample([other for other in range(n) if other != index], 3)
    declarations = [("@Forwarded", "id", "Int"), ("@Received", "service", "Service")]
    role = rng.choice(["declares", "receives", "receivesIfAvailable", "none"])
    roles[index] = (role, sorted(targets))
    if role == "declares":
        declarations.append(("@Instantiated", "context", "Context"))
    elif role == "receives":
        declarations.append(("@Received", "context", "Context"))
    elif role == "receivesIfAvailable":
        declarations.append(("@Received(onlyIfAvailable: true)", "context", "Context?"))
    declarations += [("@Instantiated", f"screen{t}Builder", f"Instantiator<Screen{t}>") for t in sorted(targets)]
    types.append(swift_type(f"Screen{index}", [(kinds[w], l, t) for w, l, t in declarations], attributes="(generateMock: true)"))
types.append(swift_type("Root", [("inst", "service", "Service"), ("inst", "context", "Context"), ("inst", "screen0Builder", "Instantiator<Screen0>")], attributes="(isRoot: true, generateMock: true)"))
types.append(swift_type("Service", [], attributes="(generateMock: true)"))
types.append(swift_type("Context", [], attributes="(generateMock: true)"))
out = os.path.join(here, "F5", f"s{n}-{seed}")
write_module(os.path.join(out, "shared", "App"), ["Harness", "SafeDI"], types)
for index in range(n):
    print(index, *roles[index])
