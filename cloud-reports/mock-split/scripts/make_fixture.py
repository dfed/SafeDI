#!/usr/bin/env python3
"""Generates a module of N @Instantiable types, all with generateMock: true, one root.

Shape (deterministic for a given N and seed):
  - 1 root (`Root`, isRoot: true) that instantiates every service and a few top-level features.
  - Services (~7% of types): instantiated by the root, each receiving 0-2 earlier services.
    A third of them are fulfilled through a protocol (`fulfillingAdditionalTypes`).
  - Utilities (~4%): no dependencies, instantiated by many features (a shared leaf).
  - Features (the rest): a tree up to depth 6. Each instantiates 0-4 children, receives 1-3 services,
    sometimes a utility, and ~25% take a @Forwarded value (their parent holds an Instantiator).
    Some descendants of a forwarding feature @Received its forwarded value.

One type per file, each with a little non-generated code, as an app module has.

Usage: make_fixture.py N OUT_DIR
"""
import os
import random
import sys

n = int(sys.argv[1])
out = sys.argv[2]
rng = random.Random(20261113 + n)

service_count = max(10, round(n * 0.07))
utility_count = max(4, round(n * 0.04))
feature_count = n - 1 - service_count - utility_count

services = [f"Service{i:03d}" for i in range(service_count)]
protocol_services = set(services[::3])  # every third service is used through a protocol
utilities = [f"Utility{i:03d}" for i in range(utility_count)]
features = [f"Feature{i:03d}" for i in range(feature_count)]


def lower_first(name: str) -> str:
    return name[0].lower() + name[1:]


def service_property_type(service: str) -> str:
    return f"any {service}Protocol" if service in protocol_services else service


# --- Feature tree ---
# Assign parents breadth-first so depth stays bounded (root's children, then theirs...).
parent = {}
depth = {}
children = {f: [] for f in features}
root_children = []
frontier = []
index = 0
top_level = min(5, feature_count)
for f in features[:top_level]:
    parent[f] = None
    depth[f] = 1
    root_children.append(f)
    frontier.append(f)
index = top_level
while index < feature_count:
    # Pick a parent among the frontier that has room and is not too deep.
    candidates = [f for f in frontier if len(children[f]) < 4 and depth[f] < 6]
    p = rng.choice(candidates)
    child = features[index]
    parent[child] = p
    depth[child] = depth[p] + 1
    children[p].append(child)
    frontier.append(child)
    index += 1

forwarding = {}  # feature -> (label, type)
for f in features:
    if f not in root_children and rng.random() < 0.25:
        forwarded_type = rng.choice(["String", "Int", "UUID"])
        forwarding[f] = (lower_first(f) + "ID", forwarded_type)


def ancestors(f):
    a = []
    p = parent[f]
    while p is not None:
        a.append(p)
        p = parent[p]
    return a


files = {}

# --- Services ---
for i, s in enumerate(services):
    received = rng.sample(services[:i], k=min(i, rng.choice([0, 1, 1, 2])))
    received.sort()
    lines = ["import Foundation", "import SafeDI", ""]
    if s in protocol_services:
        lines += [
            f"protocol {s}Protocol: AnyObject {{",
            "    func perform(_ request: String) -> String",
            "}",
            "",
            f"@Instantiable(fulfillingAdditionalTypes: [{s}Protocol.self], generateMock: true)",
            f"final class {s}: {s}Protocol, Instantiable {{",
        ]
    else:
        lines += ["@Instantiable(generateMock: true)", f"final class {s}: Instantiable {{"]
    params = ", ".join(f"{lower_first(r)}: {service_property_type(r)}" for r in received)
    lines.append(f"    init({params}) {{")
    for r in received:
        lines.append(f"        self.{lower_first(r)} = {lower_first(r)}")
    lines.append("    }")
    lines.append("")
    lines.append("    func perform(_ request: String) -> String {")
    lines.append(f'        var result = "{s}: " + request')
    for r in received:
        lines.append(f"        result += {lower_first(r)}.perform(request)")
    lines.append("        return result")
    lines.append("    }")
    lines.append("")
    for r in received:
        lines.append(f"    @Received private let {lower_first(r)}: {service_property_type(r)}")
    lines.append("}")
    files[s] = "\n".join(lines) + "\n"

# --- Utilities ---
for u in utilities:
    files[u] = f"""import Foundation
import SafeDI

@Instantiable(generateMock: true)
final class {u}: Instantiable {{
    init() {{}}

    func format(_ value: Int) -> String {{
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\\(value)"
    }}
}}
"""

# --- Features ---
for f in features:
    instantiated = []  # (label, type)
    for c in children[f]:
        if c in forwarding:
            instantiated.append((lower_first(c) + "Builder", f"Instantiator<{c}>"))
        else:
            instantiated.append((lower_first(c), c))
    if rng.random() < 0.4:
        u = rng.choice(utilities)
        instantiated.append((lower_first(u), u))
    received = [(lower_first(s), service_property_type(s)) for s in sorted(rng.sample(services, k=rng.choice([1, 2, 2, 3])))]
    forwarded_ancestors = [a for a in ancestors(f) if a in forwarding]
    if forwarded_ancestors and rng.random() < 0.5:
        label, forwarded_type = forwarding[rng.choice(forwarded_ancestors)]
        received.append((label, forwarded_type))
    forwarded = [forwarding[f]] if f in forwarding else []

    all_properties = forwarded + received + instantiated
    lines = ["import Foundation", "import SafeDI", "", "@Instantiable(generateMock: true)", f"final class {f}: Instantiable {{"]
    params = ", ".join(f"{label}: {t}" for label, t in all_properties)
    lines.append(f"    init({params}) {{")
    for label, _ in all_properties:
        lines.append(f"        self.{label} = {label}")
    lines.append("    }")
    lines.append("")
    lines.append("    func render() -> [String] {")
    lines.append(f'        var lines = ["{f}"]')
    for label, t in received:
        if "Service" in t:
            lines.append(f'        lines.append({label}.perform("render"))')
        else:
            lines.append(f'        lines.append("\\({label})")')
    for label, t in instantiated:
        if t.startswith("Utility"):
            lines.append(f"        lines.append({label}.format(lines.count))")
        elif not t.startswith("Instantiator"):
            lines.append(f"        lines += {label}.render()")
    lines.append("        return lines")
    lines.append("    }")
    lines.append("")
    for label, t in forwarded:
        lines.append(f"    @Forwarded private let {label}: {t}")
    for label, t in received:
        lines.append(f"    @Received private let {label}: {t}")
    for label, t in instantiated:
        lines.append(f"    @Instantiated private let {label}: {t}")
    lines.append("}")
    files[f] = "\n".join(lines) + "\n"

# --- Root ---
root_properties = [(lower_first(s), service_property_type(s)) for s in services]
root_properties += [(lower_first(c), c) for c in root_children]
lines = ["import Foundation", "import SafeDI", "", "@Instantiable(isRoot: true, generateMock: true)", "final class Root: Instantiable {"]
lines.append("    init(" + ", ".join(f"{label}: {t}" for label, t in root_properties) + ") {")
for label, _ in root_properties:
    lines.append(f"        self.{label} = {label}")
lines.append("    }")
lines.append("")
lines.append("    func render() -> [String] {")
lines.append("        var lines = [String]()")
for c in root_children:
    lines.append(f"        lines += {lower_first(c)}.render()")
lines.append("        return lines")
lines.append("    }")
lines.append("")
for label, t in root_properties:
    lines.append(f"    @Instantiated private let {label}: {t}")
lines.append("}")
files["Root"] = "\n".join(lines) + "\n"

os.makedirs(os.path.join(out, "Sources"), exist_ok=True)
for name, content in files.items():
    with open(os.path.join(out, "Sources", name + ".swift"), "w") as handle:
        handle.write(content)

# The type both edits touch: a feature at depth 3 with a parent, children and no forwarded value,
# chosen deterministically.
edit_target = next(f for f in features if depth[f] == 3 and children[f] and f not in forwarding)
# A service the edit target does not receive yet, which the root instantiates.
existing = {label for label, _ in [(lower_first(s), None) for s in services] if f"@Received private let {label}:" in files[edit_target]}
new_service = next(s for s in services if lower_first(s) not in existing and s not in protocol_services)
with open(os.path.join(out, "edit-target.txt"), "w") as handle:
    handle.write(f"{edit_target}\n{new_service}\n")

max_depth = max(depth.values())
print(f"types={len(files)} services={service_count} protocolServices={len(protocol_services)} utilities={utility_count} "
      f"features={feature_count} forwarding={len(forwarding)} maxDepth={max_depth} editTarget={edit_target} newService={new_service} "
      f"editTargetAncestors={len(ancestors(edit_target))}")
