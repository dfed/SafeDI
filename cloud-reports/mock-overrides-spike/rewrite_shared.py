#!/usr/bin/env python3
"""python3 rewrite_shared.py App.gen.swift [--stats]

Rewrites shape D's generated `Root.mock()` (today's form: one nested builder function per path) into the shared form
the spike designs, in place. Hand-written: the figures for its output are labeled "hand-written" in the report.

- The key here is the screen type: in shape D every place of a screen has the same construction (`init`), the same
  by-value receives (`service`, never lazy), and reads a configuration, so places of one type share a key.
- A type with one place (one distinct parent body in the shared form) keeps today's nested text, reading its
  configuration relative to the nearest enclosing shared function's `safeDIOverrides`.
- A type with two or more places gets one function `__safeDI_<label>(id: Int, safeDIOverrides: T.SafeDIMockConfiguration) -> T`,
  placed in the innermost body all its places pass through (the lowest common body of its parents' bodies), before
  the first statement there that reaches it; functions placed before one statement go deepest layer first.
- Outside values: `service` has one declaration (the mock's) at every call, so it is captured; `id` is the forwarded
  value, so it is the function's parameter as today. The configuration is the last parameter; each call passes
  `safeDIOverrides.<path>.<label>` relative to its own function.
Only `Root.mock()`'s body changes; the configuration structs and the production initializer are untouched, so the
script applies to main's `let` output and to the storage variants alike.
"""
import re, sys

path = sys.argv[1]
text = open(path).read()
lines = text.split("\n")

start = next(i for i, l in enumerate(lines) if l.startswith("    static func mock(") and "Root" in "".join(lines[i:i + 4]))
body_start = next(i for i in range(start, len(lines)) if lines[i].endswith(") -> Root {")) + 1
body_end = next(i for i in range(body_start, len(lines)) if lines[i] == "    }")
body = lines[body_start:body_end]

FUNC = re.compile(r"^( *)func __safeDI_(screen(\d+)Builder)\(id: Int\) -> Screen(\d+) \{$")


class Node:
    def __init__(self, label, number):
        self.label, self.number, self.model_line, self.children, self.return_line = label, number, None, [], None


def parse(block, indent):
    """Parses the statements of one body at `indent` into ('line', text) and ('node', Node) items."""
    items, i = [], 0
    while i < len(block):
        line = block[i]
        m = FUNC.match(line)
        if m and len(m.group(1)) == indent:
            node = Node(m.group(2), int(m.group(3)))
            end = next(j for j in range(i + 1, len(block)) if block[j] == " " * indent + "}")
            inner = parse(block[i + 1:end], indent + 4)
            node.model_line = inner[0][1].strip()
            node.return_line = inner[-1][1].strip()
            node.children = [x for _, x in inner[1:-1] if isinstance(x, Node)]
            # Skip the `let <label> = Instantiator<…> { … }` that follows: three lines.
            assert block[end + 1].strip().startswith(f"let {node.label} = Instantiator<Screen{node.number}>"), block[end + 1]
            items.append(("node", node))
            i = end + 4
        else:
            items.append(("line", line))
            i += 1
    return items


items = parse(body, 8)
service_line = items[0][1]
return_line = items[-1][1]
roots = [x for _, x in items if isinstance(x, Node)]

# The type graph and one template per type, with the configuration path written as {C}.
children, templates = {}, {}
PATH = re.compile(r"safeDIOverrides((?:\.\w+Builder)+)\.")


def template(line, own_path):
    return line.replace(f"safeDIOverrides{own_path}.", "{C}.")


def walk(node, own_path):
    children.setdefault(node.number, [c.number for c in node.children])
    assert children[node.number] == [c.number for c in node.children]
    model_template, return_template = template(node.model_line, own_path), template(node.return_line, own_path)
    assert "safeDIOverrides" not in model_template + return_template, (model_template, return_template)
    templates.setdefault(node.number, (node.label, model_template, return_template))
    for c in node.children:
        walk(c, f"{own_path}.{c.label}")


for r in roots:
    walk(r, f".{r.label}")
children["R"] = [r.number for r in roots]

parents = {}
for p, cs in children.items():
    for c in cs:
        parents.setdefault(c, []).append(p)
shared = {t for t, ps in parents.items() if len(ps) >= 2}
layer = lambda t: t // 4


def closure(t, memo={}):
    if t not in memo:
        memo[t] = {t}.union(*[closure(c) for c in children.get(t, [])]) if children.get(t) else {t}
    return memo[t]


# Bodies: "R" and one per type. home(t) is the body t's function is declared in.
home, depth, up = {}, {"R": 0}, {"R": None}
for t in sorted(parents, key=lambda t: (layer(t), t)):
    if t in shared:
        bodies = [p for p in parents[t]]
        def ancestors(b):
            chain = []
            while b is not None:
                chain.append(b); b = up[b]
            return chain
        common = set(ancestors(bodies[0]))
        for b in bodies[1:]:
            common &= set(ancestors(b))
        home[t] = max(common, key=lambda b: depth[b])
    else:
        home[t] = parents[t][0]
    up[t], depth[t] = home[t], depth[home[t]] + 1
homed = {}
for t in sorted(shared):
    homed.setdefault(home[t], []).append(t)


def label(t):
    return templates[t][0]


def body_lines(t, configuration, indent):
    """The statements of the body that builds t: its model, its children, and the shared functions homed in it."""
    _, model_template, return_template = templates[t] if t != "R" else (None, None, None)
    out = [] if t == "R" else [" " * indent + model_template.replace("{C}", configuration)]
    if t == "R":
        out.append(service_line)
    statements = []
    for c in children[t]:
        s = []
        if c in shared:
            s += [f"{' ' * indent}let {label(c)} = Instantiator<Screen{c}> {{",
                  f"{' ' * indent}    __safeDI_{label(c)}(id: $0, safeDIOverrides: {configuration}.{label(c)})",
                  f"{' ' * indent}}}"]
        else:
            s += [f"{' ' * indent}func __safeDI_{label(c)}(id: Int) -> Screen{c} {{"]
            s += body_lines(c, f"{configuration}.{label(c)}", indent + 4)
            s += [f"{' ' * indent}}}",
                  f"{' ' * indent}let {label(c)} = Instantiator<Screen{c}> {{",
                  f"{' ' * indent}    __safeDI_{label(c)}(id: $0)",
                  f"{' ' * indent}}}"]
        statements.append((c, s))
    placed = sorted(homed.get(t, []), key=lambda u: (next(i for i, (c, _) in enumerate(statements) if u in closure(c)), -layer(u), u))
    by_index = {}
    for u in placed:
        by_index.setdefault(next(i for i, (c, _) in enumerate(statements) if u in closure(c)), []).append(u)
    for i, (c, s) in enumerate(statements):
        for u in by_index.get(i, []):
            out.append(f"{' ' * indent}func __safeDI_{label(u)}(id: Int, safeDIOverrides: Screen{u}.SafeDIMockConfiguration) -> Screen{u} {{")
            out += body_lines(u, "safeDIOverrides", indent + 4)
            out.append(f"{' ' * indent}}}")
        out += s
    out.append(return_line if t == "R" else " " * indent + return_template.replace("{C}", configuration))
    return out


new_body = body_lines("R", "safeDIOverrides", 8)
lines[body_start:body_end] = new_body
open(path, "w").write("\n".join(lines))
if "--stats" in sys.argv:
    print(f"shared types {len(shared)} of {len(parents)}; mock body {len(body)} -> {len(new_body)} lines")
