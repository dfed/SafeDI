"""Writes F5's driver: walks every mock to a depth (instantiating every builder), once with no overrides and once with
every override field set to a closure that notes its path. Field lists come from today's generated file.
Usage: driver_gen.py TODAY.swift N DEPTH OUT"""
import re, sys
today, n, depth, out = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
text = open(today).read()
types = {}  # type -> [(label, typeText)] of its SafeDIMockConfiguration
overrides = {}  # mocked type -> fields of its SafeDIOverrides
for m in re.finditer(r"extension (\w+) \{\n(?:    ///[^\n]*\n)?    struct (SafeDIMockConfiguration|SafeDIOverrides) \{\n        init\(\n(.*?)\n        \) \{", text, re.S):
    fields = []
    for line in m.group(3).split("\n"):
        f = re.match(r"\s*(_ )?(\w+): (.*) = (\.init\(\)|nil),?$", line.strip())
        fields.append((f.group(2), f.group(3), bool(f.group(1))))
    (types if m.group(2) == "SafeDIMockConfiguration" else overrides)[m.group(1)] = fields

screens = {}
for m in re.finditer(r"@Instantiable\(generateMock: true\)\npublic final class (Screen\d+)[^{]*\{\n    public init\((.*?)\) \{", text):
    pass
src = open(today.replace("stored/App.swift.txt", "../shared/App/Types.swift.txt")).read() if False else None

def closure(path, label, type_text, owner):
    # (() -> Context)? or ((Int, Service, ...) -> ScreenK)?
    inner = re.match(r"\(\((.*)\) -> (\w+)\)\?$", type_text)
    parameters, result = inner.group(1), inner.group(2)
    count = 0 if parameters == "" else parameters.count(",") + 1
    names = [f"p{i}" for i in range(count)]
    if result == "Context":
        body = "Context()"
    elif result == "Service":
        body = "Service()"
    else:
        labels = initializer_labels[result]
        body = f"{result}(" + ", ".join(f"{l}: {v}" for l, v in zip(labels, names)) + ")"
    head = (", ".join(names) + " in ") if names else ""
    return f'{{ {head}Registry.note("override {path}"); return {body} }}'

initializer_labels = {}
types_src = open(sys.argv[5]).read()
for m in re.finditer(r"public final class (\w+): [^{]*\{\n    public init\((.*?)\) \{", types_src):
    initializer_labels[m.group(1)] = [p.split(":")[0] for p in m.group(2).split(", ")] if m.group(2) else []

lines = ["import Harness", "import SafeDI", ""]
def config_function(type_):
    lines.append(f"func configuration{type_}(_ path: String) -> {type_}.SafeDIMockConfiguration {{")
    arguments = []
    for label, type_text, unlabeled in types[type_]:
        if type_text.endswith(".SafeDIMockConfiguration"):
            child = type_text.split(".")[0]
            value = f'configuration{child}(path + ".{label}")'
        else:
            value = closure("\\(path)." + label, label, type_text, type_)
        arguments.append(value if unlabeled else f"{label}: {value}")
    lines.append("    .init(" + ", ".join(arguments) + ")")
    lines.append("}")
for t in sorted(types):
    config_function(t)

def walk_function(k):
    labels = initializer_labels[f"Screen{k}"]
    builders = [l for l in labels if l.endswith("Builder")]
    lines.append(f"func walk(_ s: Screen{k}, _ depth: Int, _ keep: inout [AnyObject]) {{")
    lines.append("    keep.append(s)")
    lines.append("    guard depth > 0 else { return }")
    for b in builders:
        target = int(re.match(r"screen(\d+)Builder", b).group(1))
        lines.append(f"    walk(s.{b}.instantiate({target}), depth - 1, &keep)")
    lines.append("}")
for k in range(n):
    walk_function(k)

def mock_overrides(type_):
    arguments = []
    for label, type_text, unlabeled in overrides[type_]:
        if type_text.endswith(".SafeDIMockConfiguration"):
            value = f'configuration{type_text.split(".")[0]}("{label}")'
        elif type_text == "Context?":
            value = "Context()"
        else:
            value = closure(label, label, type_text, type_)
        arguments.append(f"{label}: {value}")
    return ".init(" + ", ".join(arguments) + ")"

lines.append("public func runFixture() {")
lines.append("    runFixture(overrides: [false, true])")
lines.append("}")
lines.append("")
lines.append("/// The timing run's walk: every mock with no overrides.")
lines.append("public func runPlain() {")
lines.append("    runFixture(overrides: [false])")
lines.append("}")
lines.append("")
lines.append("func runFixture(overrides: [Bool]) {")
lines.append("    for overridden in overrides {")
lines.append("        do {")
lines.append("            var keep = [AnyObject]()")
lines.append(f"            let root = overridden ? Root.mock(safeDIOverrides: {mock_overrides('Root')}) : Root.mock()")
lines.append(f"            walk(root.screen0Builder.instantiate(0), {depth}, &keep)")
lines.append('            print("Root.mock, overridden \\(overridden):")')
lines.append("            Registry.printTrace()")
lines.append("            withExtendedLifetime((root, keep)) {}")
lines.append("        }")
lines.append('        Registry.printAlive("after dropping everything")')
for k in range(n):
    if f"Screen{k}" not in overrides:
        continue
    lines.append("        do {")
    lines.append("            var keep = [AnyObject]()")
    lines.append(f"            let screen = overridden ? Screen{k}.mock(id: {k}, safeDIOverrides: {mock_overrides(f'Screen{k}')}) : Screen{k}.mock(id: {k})")
    lines.append(f"            walk(screen, {depth}, &keep)")
    lines.append(f'            print("Screen{k}.mock, overridden \\(overridden):")')
    lines.append("            Registry.printTrace()")
    lines.append("            withExtendedLifetime(keep) {}")
    lines.append("        }")
    lines.append('        Registry.printAlive("after dropping everything")')
lines.append("    }")
lines.append("}")
open(out, "w").write("\n".join(lines) + "\n")
