"""Writes fixture types for the spike: each a public final class that holds a `Tracker` and logs what it received.

A property is (kind, label, type): kind is `inst`, `recv`, `opt` (received only if available) or `fwd`.
"""


def swift_type(name, properties, seam=False, root=False, fulfills=None, sendable=False, attributes=None, initializer_access="public"):
    if attributes is None:
        if seam:
            attributes = "(generateDependencyTree: true)"
        elif root:
            attributes = "(isRoot: true)"
        elif fulfills:
            attributes = f"(fulfillingAdditionalTypes: [(any {fulfills}).self])"
        else:
            attributes = ""
    conformances = ["Instantiable", "Traced"]
    if fulfills:
        conformances.append(fulfills)
    if sendable:
        conformances.append("Sendable")
    parameters = ", ".join(
        f"{label}: {'@escaping ' if '->' in type_ else ''}{type_}" for _, label, type_ in properties
    )
    attribute_of = {
        "inst": "@Instantiated",
        "recv": "@Received",
        "opt": "@Received(onlyIfAvailable: true)",
        "fwd": "@Forwarded",
    }
    lines = [f"@Instantiable{attributes}", f"public final class {name}: {', '.join(conformances)} {{"]
    lines.append(f"    {initializer_access + ' ' if initializer_access else ''}init({parameters}) {{")
    for _, label, _ in properties:
        lines.append(f"        self.{label} = {label}")
    received = ", ".join(f'"{label}": {label}' for _, label, _ in properties) or ":"
    lines.append(f"        Registry.created(self, [{received}])")
    lines.append("    }")
    lines.append("")
    lines.append(f'    public let tracker = Tracker("{name}")')
    for kind, label, type_ in properties:
        lines.append(f"    {attribute_of[kind]} public let {label}: {type_}")
    lines.append("}")
    return "\n".join(lines) + "\n"


def write_module(directory, imports, types, extra=""):
    import os

    os.makedirs(directory, exist_ok=True)
    with open(os.path.join(directory, "Types.swift.txt"), "w") as file:
        file.write("".join(f"import {module}\n" for module in imports) + "\n" + extra + "\n".join(types))
