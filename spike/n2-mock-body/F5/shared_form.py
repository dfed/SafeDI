"""Rewrites every generated `mock()` body of an #646-shaped module (F5) into the shared form: one local function per
key, where the key is (type, the form of `context` it is handed, how each child reads its configuration, the
construction's arguments), every function at the body's top level, and the configuration a parameter.

The override each place reads is taken from today's text, place by place: a function definition reads the path its
`safeDIBuilder` line names, or none. A child's configuration is `param.<label>` when its place reads the parent's path
plus its label, `nil` when it reads none, and otherwise the fixed path it reads (kept in the key). `context` follows
the dynamic rule (#646's fix): each place gets the nearest declaration on the path that built it.

Usage: shared_form.py TODAY.swift OUT.swift STATS.json [--uniform | --loop [--boxed]]

--loop is --uniform, except that a cycle's closing edge hands the re-entered type the configuration its nearest
ancestor of that type read (a `__safeDI_Loop` value every function passes on), so every override applies on every lap.

--uniform replaces today's reads with one rule (every place reads its parent's field for it when the parent's type has
one; the mock root's children read the root's field), so one function serves each (type, context form, construction):
values are unchanged, and the override some places beneath a cycle read changes."""
import json, re, sys

FUNC = re.compile(r"^func (__safeDI_\w+)\((.*)\) -> (\w+) \{$")
CTX_DECL = re.compile(r"^let context = (?:if let safeDIBuilder = safeDIOverrides\.([\w.]+)\.context \{ safeDIBuilder\(\) \} else \{ Context\(\) \}|Context\(\))$")
INST_OPEN = re.compile(r"^let (\w+) = Instantiator<(\w+)> \{$")
INST_REF = re.compile(r"^let (\w+) = Instantiator<(\w+)>\((__safeDI_\w+)\)$")
CALL = re.compile(r"^(__safeDI_\w+)\(id: \$0(?:, context: (\w+))?\)$")
RET_OVERRIDE = re.compile(r"^return if let safeDIBuilder = safeDIOverrides\.([\w.]+)\.safeDIBuilder \{ safeDIBuilder\((.*)\) \} else \{ (\w+)\((.*)\) \}$")
RET_PLAIN = re.compile(r"^return (\w+)\((.*)\)$")


class Place:
    def __init__(self, name, params, type_, parent):
        self.name, self.params, self.type, self.parent = name, params, type_, parent
        self.definitions = {}  # name -> Place, the functions this body declares
        self.children = []  # (label, child type, callee name)
        self.declares_context = False
        self.context_override = None
        self.path = None  # configuration path this place reads, or None
        self.arguments = None  # construction's arguments text
        self.prologue = []

    def resolve(self, name):
        scope = self
        while scope is not None:
            if name in scope.definitions:
                return scope.definitions[name]
            scope = scope.parent
        raise KeyError(name)


def parse_body(lines, index, place):
    """Parses statements until the `}` that closes `place`'s body. Returns the index after it."""
    while True:
        line = lines[index].strip()
        index += 1
        if line == "}":
            return index
        if m := FUNC.match(line):
            child = Place(m.group(1), m.group(2), m.group(3), place)
            place.definitions[child.name] = child
            index = parse_body(lines, index, child)
        elif m := CTX_DECL.match(line):
            place.declares_context = True
            place.context_override = m.group(1)
        elif m := INST_OPEN.match(line):
            call = CALL.match(lines[index].strip())
            assert call and lines[index + 1].strip() == "}", lines[index]
            place.children.append((m.group(1), m.group(2), call.group(1)))
            index += 2
        elif m := INST_REF.match(line):
            place.children.append((m.group(1), m.group(2), m.group(3)))
        elif m := RET_OVERRIDE.match(line):
            place.path, place.arguments = m.group(1), m.group(4)
            assert m.group(3) == place.type
        elif m := RET_PLAIN.match(line):
            place.arguments = m.group(2)
            assert m.group(1) == place.type, line
        else:
            place.prologue.append(line)  # only the mock root has a prologue


def rewrite_mock(body_lines, return_line, indent, stats):
    root = Place("<root>", "", None, None)
    index = parse_body(body_lines + ["}"], 0, root)
    assert index == len(body_lines) + 1
    # Top-level `context` binding's type, if any.
    root_context = None
    for line in root.prologue:
        if line.startswith("let context: Context? ="):
            root_context = "Context?"
        elif line.startswith("let context ="):
            root_context = "Context"
    # Nodes are (definition, the context form it is handed). Each node's local signature is its type, context form,
    # whether it declares `context`, how each child reads its configuration, and its construction's arguments.
    # Classes are refined by the classes of the nodes each one calls until no class splits (bisimulation), so two
    # places share a function only when everything they build, to any depth, reads the same.
    nodes, edges, local = [], {}, {}
    index_of = {}

    def expression_for(place, label, callee):
        if UNIFORM:
            # The uniform rule: every place reads its parent's field for it when the parent's type has one.
            if label in CONFIGURATION_FIELDS.get(place.type, ()):
                return "param"
            # The loop rule: a cycle's closing edge hands the re-entered type the configuration its nearest ancestor of
            # that type read, so every override applies on every lap of the cycle.
            return "loop:" + callee.type if LOOP else "nil"
        if callee.path is None:
            return "nil"
        if place.path is not None and callee.path == f"{place.path}.{label}":
            return "param"
        return "fixed:" + callee.path

    def discover(place, context_type):
        node = (id(place), context_type)
        if node in index_of:
            return index_of[node]
        number = len(nodes)
        index_of[node] = number
        nodes.append((place, context_type))
        own_context = "Context" if place.declares_context else context_type
        calls = []
        for label, child_type, callee_name in place.children:
            callee = place.resolve(callee_name)
            calls.append((label, child_type, expression_for(place, label, callee), discover(callee, own_context)))
        edges[number] = calls
        local[number] = (place.type, None if place.declares_context else context_type, place.declares_context,
                         tuple((l, t, e) for l, t, e, _ in calls), place.arguments)
        return number

    root_targets = []
    for label, child_type, callee_name in root.children:
        callee = root.resolve(callee_name)
        expression = "nil" if callee.path is None else "fixed:" + callee.path
        if UNIFORM:
            expression = "fixed:" + label
        root_targets.append((label, child_type, expression, discover(callee, root_context)))

    classes = {}
    signature_numbers = {}
    for number in range(len(nodes)):
        classes[number] = signature_numbers.setdefault(local[number], len(signature_numbers))
    while True:
        refined, numbers = {}, {}
        for number in range(len(nodes)):
            signature = (classes[number], tuple(classes[c] for _, _, _, c in edges[number]))
            refined[number] = numbers.setdefault(signature, len(numbers))
        if len(numbers) == len(set(classes.values())):
            break
        classes = refined
    # One function per class, numbered in first-reach order.
    order, function_of_class = [], {}
    for number in range(len(nodes)):
        if classes[number] not in function_of_class:
            function_of_class[classes[number]] = len(order)
            order.append(number)
    functions = []
    for number in order:
        place, context_type = nodes[number]
        functions.append((place, context_type, [(l, t, e, function_of_class[classes[c]]) for l, t, e, c in edges[number]]))
    root_calls = [(l, t, e, function_of_class[classes[c]]) for l, t, e, c in root_targets]
    places = nodes

    def expression_text(expression, label):
        if expression == "param":
            return f"__safeDI_overrides?.{label}"
        if expression == "nil":
            return "nil"
        if expression.startswith("loop:"):
            return "__safeDI_loop.t_" + expression[len("loop:"):]
        return "safeDIOverrides." + expression[len("fixed:"):]

    def instantiator(label, child_type, expression, number, context_available, pad):
        callee_place, callee_context, _ = functions[number]
        context_argument = ", context: context" if (callee_context is not None and not callee_place.declares_context) else ""
        loop_argument = (", __safeDI_loop: __safeDI_loop" if context_available else ", __safeDI_loop: __safeDI_Loop()") if LOOP else ""
        return [f"{pad}let {label} = Instantiator<{child_type}> {{",
                f"{pad}    __safeDI_shared{number}(id: $0{context_argument}, safeDIOverrides: {expression_text(expression, label)}{loop_argument})",
                f"{pad}}}"]

    pad = " " * indent
    out = [pad + line for line in root.prologue]
    loop_types = sorted({e[len("loop:"):] for _, _, calls in functions for _, _, e, _ in calls if e.startswith("loop:")})
    if LOOP:
        out.append(f"{pad}struct __safeDI_Loop {{")
        if BOXED:
            # Each loop configuration is held in a box, so copying or capturing the loop value retains a few
            # references instead of copying every configuration it holds.
            out.append(f"{pad}    final class Box<Value> {{ let value: Value; init(_ value: Value) {{ self.value = value }} }}")
            for t in loop_types:
                out.append(f"{pad}    var b_{t}: Box<{t}.SafeDIMockConfiguration?>? = nil")
                out.append(f"{pad}    var t_{t}: {t}.SafeDIMockConfiguration? {{ b_{t}?.value }}")
            for t in loop_types:
                out.append(f"{pad}    func entering{t}(_ configuration: {t}.SafeDIMockConfiguration?) -> __safeDI_Loop {{ var loop = self; loop.b_{t} = Box(configuration); return loop }}")
        else:
            for t in loop_types:
                out.append(f"{pad}    var t_{t}: {t}.SafeDIMockConfiguration? = nil")
            for t in loop_types:
                out.append(f"{pad}    func entering{t}(_ configuration: {t}.SafeDIMockConfiguration?) -> __safeDI_Loop {{ var loop = self; loop.t_{t} = configuration; return loop }}")
        out.append(f"{pad}}}")
    for number, (place, context_type, calls) in enumerate(functions):
        parameters = "id: Int"
        if not place.declares_context and context_type is not None:
            parameters += f", context: {context_type}"
        parameters += f", safeDIOverrides __safeDI_overrides: {place.type}.SafeDIMockConfiguration?"
        if LOOP:
            parameters += ", __safeDI_loop: __safeDI_Loop"
        out.append(f"{pad}func __safeDI_shared{number}({parameters}) -> {place.type} {{")
        if LOOP and place.type in loop_types:
            out.append(f"{pad}    let __safeDI_loop = __safeDI_loop.entering{place.type}(__safeDI_overrides)")
        if place.declares_context:
            out.append(f"{pad}    let context = if let safeDIBuilder = __safeDI_overrides?.context {{ safeDIBuilder() }} else {{ Context() }}")
        for label, child_type, expression, callee_number in calls:
            out += instantiator(label, child_type, expression, callee_number, True, pad + "    ")
        argument_values = ", ".join(part.split(": ", 1)[1] for part in place.arguments.split(", "))
        out.append(f"{pad}    return if let safeDIBuilder = __safeDI_overrides?.safeDIBuilder {{ safeDIBuilder({argument_values}) }} else {{ {place.type}({place.arguments}) }}")
        out.append(f"{pad}}}")
    for label, child_type, expression, number in root_calls:
        out += instantiator(label, child_type, expression, number, False, pad)
    out.append(pad + return_line)
    stats.append({"places": len(places), "functions": len(functions),
                  "types": len({p.type for p, _, _ in functions}),
                  "fixed_paths": sum(1 for _, _, calls in functions for c in calls if c[2].startswith("fixed"))})
    return out


UNIFORM = False
LOOP = False
BOXED = False
CONFIGURATION_FIELDS = {}


def main():
    global UNIFORM, LOOP, BOXED
    BOXED = "--boxed" in sys.argv[4:]
    today, out_path, stats_path = sys.argv[1:4]
    LOOP = "--loop" in sys.argv[4:]
    UNIFORM = "--uniform" in sys.argv[4:] or LOOP
    text = open(today).read()
    for m in re.finditer(r"extension (\w+) \{\n(?:    ///[^\n]*\n)?    struct SafeDIMockConfiguration \{\n        init\(\n(.*?)\n        \) \{", text, re.S):
        CONFIGURATION_FIELDS[m.group(1)] = {l.strip().split(":")[0] for l in m.group(2).split("\n") if not l.strip().startswith("_ ")}
    lines = text.split("\n")
    result, stats, index = [], [], 0
    while index < len(lines):
        line = lines[index]
        result.append(line)
        index += 1
        if re.match(r"^    \) -> \w+ \{$", line) and any("static func mock(" in l for l in lines[max(0, index - 8):index]):
            start, depth = index, 1
            while depth:
                stripped = lines[index].strip()
                depth += stripped.count("{") - stripped.count("}")
                index += 1
            body = lines[start:index - 1]
            if any(l.strip().startswith("func ") for l in body):
                result += rewrite_mock(body[:-1], body[-1].strip(), 8, stats)
            else:
                result += body
            result.append(lines[index - 1])
    open(out_path, "w").write("\n".join(result))
    json.dump(stats, open(stats_path, "w"), indent=1)


if __name__ == "__main__":
    main()
