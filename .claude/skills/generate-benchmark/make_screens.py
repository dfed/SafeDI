# Usage: python3 make_screens.py OUTPUT_DIR SCREEN_COUNT [SEED] [mock]
# The generator issue #646 reported its graph with, unchanged.
import os, random, sys

out, n = sys.argv[1], int(sys.argv[2])
rng = random.Random(int(sys.argv[3]) if len(sys.argv) > 3 else 1)
mock = len(sys.argv) > 4 and sys.argv[4] == "mock"
os.makedirs(out, exist_ok=True)

def write(name, declarations, attribute="@Instantiable(generateMock: true)" if mock else "@Instantiable"):
    lines = ["import SafeDI", "", attribute, f"public final class {name} {{"]
    lines.append("\tpublic init(" + ", ".join(f"{label}: {type_}" for _, label, type_ in declarations) + ") {")
    lines += [f"\t\tself.{label} = {label}" for _, label, _ in declarations]
    lines += ["\t}", ""] + [f"\t{wrapper} let {label}: {type_}" for wrapper, label, type_ in declarations] + ["}"]
    with open(os.path.join(out, f"{name}.swift"), "w") as file:
        file.write("\n".join(lines) + "\n")

for index in range(n):
    targets = rng.sample([other for other in range(n) if other != index], 3)
    declarations = [("@Forwarded", "id", "String"), ("@Received", "service", "Service")]
    role = rng.choice(["declares", "receives", "receivesIfAvailable", "none"])
    if role == "declares":
        declarations.append(("@Instantiated", "context", "Context"))
    elif role == "receives":
        declarations.append(("@Received", "context", "Context"))
    elif role == "receivesIfAvailable":
        declarations.append(("@Received(onlyIfAvailable: true)", "context", "Context?"))
    declarations += [("@Instantiated", f"screen{target}Builder", f"Instantiator<Screen{target}>") for target in sorted(targets)]
    write(f"Screen{index}", declarations)

write("Root", [("@Instantiated", "service", "Service"), ("@Instantiated", "context", "Context"),
               ("@Instantiated", "screen0Builder", "Instantiator<Screen0>")], "@Instantiable(isRoot: true, generateMock: true)" if mock else "@Instantiable(isRoot: true)")
write("Service", [])
write("Context", [])
