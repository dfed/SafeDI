"""Stage 2 emitter: from a tree spec, writes the fixture types, the walker, and the hand-written variants (c) leak fix
(per-path body over the builder struct, candidate B) and (d) per-type (one function per type over the same struct),
with the calling module's level functions, which (c) and (d) share. (a) inline and (b) today come from the tool.

A spec (JSON) is {"seam": name, "types": {name: {"forwarded": [label], "receives": [label], "properties":
[[label, kind, target]]}}, "holes": {hole type: fill type}, "fill_receives": {fill type: [label]}, "pass_through":
[label], "root_declares": [[label, type]]}. kind is "const" (an instantiated value), "inst" (Instantiator<target>) or
"hole" (`any <target>`). A forwarded label is `Int`; a pass-through label is a type of the same name, capitalized,
built by the root.

Usage: python3 -I emit.py SPEC OUTPUT_DIRECTORY"""
import json
import os
import sys


def cap(label):
    return label[0].upper() + label[1:]


class Spec:
    def __init__(self, raw):
        self.seam = raw["seam"]
        self.types = raw["types"]
        self.holes = raw["holes"]
        self.fill_receives = raw.get("fill_receives", {})
        self.pass_through = raw.get("pass_through", [])
        self.root_declares = raw.get("root_declares", [])
        self._leads = {}

    def properties(self, name):
        return self.types[name]["properties"]

    def forwarded(self, name):
        return self.types[name].get("forwarded", [])

    def receives(self, name):
        return self.types[name].get("receives", [])

    def leads(self, name):
        """Whether a build of `name` leads to a place (a hole)."""
        if name not in self._leads:
            self._leads[name] = False
            self._leads[name] = any(kind == "hole" or self.leads(target) for _, kind, target in self.properties(name))
        return self._leads[name]

    def property_leads(self, kind, target):
        return kind == "hole" or self.leads(target)

    def property_type(self, kind, target):
        return {"const": target, "inst": f"Instantiator<{target}>", "hole": f"any {target}"}[kind]

    def values_fields(self, name, index):
        """What `name` binds before its property at `index`: its forwarded values (the seam: its pass-throughs), then its
        earlier properties."""
        fields = []
        if name == self.seam:
            fields += [(label, cap(label), True) for label in self.pass_through]
        fields += [(label, "Int", False) for label in self.forwarded(name)]
        for label, kind, target in self.properties(name)[:index]:
            fields.append((label, self.property_type(kind, target), False))
        return fields

    def hole_types(self):
        return sorted(self.holes)


# MARK: Types


def swift_class(name, properties, attributes="", conformances=""):
    parameters = ", ".join(f"{label}: {type_}" for _, label, type_ in properties)
    received = ", ".join(f'"{label}": {label}' for _, label, _ in properties) or ":"
    lines = [f"@Instantiable{attributes}", f"public final class {name}: Instantiable{conformances} {{", f"    public init({parameters}) {{"]
    lines += [f"        self.{label} = {label}" for _, label, _ in properties]
    lines += ["        #if SPIKE_TRACE", f"        Registry.created(self, [{received}])", "        #endif", "    }", ""]
    lines += [f"    {attribute} public let {label}: {type_}" for attribute, label, type_ in properties]
    lines += ["    #if SPIKE_TRACE", f'    public let tracker = Tracker("{name}")', "    #endif", "}", ""]
    lines += ["#if SPIKE_TRACE", f"extension {name}: Traced {{}}", "#endif", ""]
    return "\n".join(lines) + "\n"


def initializer_properties(spec, name):
    properties = [("@Forwarded", label, "Int") for label in spec.forwarded(name)]
    properties += [("@Received", label, cap(label) if label in spec.pass_through else "Int") for label in spec.receives(name)]
    properties += [("@Instantiated", label, spec.property_type(kind, target)) for label, kind, target in spec.properties(name)]
    return properties


def feature_types(spec, seam=True):
    types = [swift_class(cap(label), []) for label in spec.pass_through]
    for name in spec.types:
        attributes = "(generateDependencyTree: true)" if seam and name == spec.seam else ""
        types.append(swift_class(name, initializer_properties(spec, name), attributes))
    return types


def app_types(spec):
    types = []
    for hole, fill in spec.holes.items():
        receives = [("@Received", label, cap(label) if label in spec.pass_through else "Int") for label in spec.fill_receives.get(fill, [])]
        types.append(swift_class(fill, receives, f"(fulfillingAdditionalTypes: [(any {hole}).self])", f", {hole}"))
    root = [("@Instantiated", label, type_) for label, type_ in spec.root_declares] + [("@Instantiated", spec.seam[0].lower() + spec.seam[1:], spec.seam)]
    types.append(swift_class("Root", root, "(isRoot: true)"))
    return types


def protocols(spec):
    return "".join(f"public protocol {hole}: AnyObject {{}}\n\n" for hole in spec.hole_types())


# MARK: Walker


def main_swift(spec):
    lines = ["import App", "#if canImport(Feature)", "import Feature", "#endif", "import Harness", "", "nonisolated(unsafe) var nextIdentifier = 0", "nonisolated(unsafe) var built = 0", ""]
    lines.append("func identifier() -> Int {\n\tnextIdentifier += 1\n\treturn nextIdentifier\n}\n")
    for name in spec.types:
        lines.append(f"func walk(_ value: {name}) {{")
        lines.append("\tbuilt += 1")
        for label, kind, target in spec.properties(name):
            if kind == "const":
                lines.append(f"\twalk(value.{label})")
            elif kind == "inst":
                arguments = ", ".join("identifier()" for _ in spec.forwarded(target))
                lines.append(f"\twalk(value.{label}.instantiate({arguments}))")
            else:
                lines.append(f"\twithExtendedLifetime(value.{label}) {{}}")
        lines.append("}\n")
    seam_property = spec.seam[0].lower() + spec.seam[1:]
    lines.append(f"func walkEveryPath(_ root: Root) {{\n\twalk(root.{seam_property})\n}}\n")
    lines.append("""let arguments = CommandLine.arguments
if arguments.count > 1, arguments[1] == "bench" {
\t// One round: builds a Root and walks every path, again until the walks last at least 100 ms; prints nanoseconds per
\t// walk, a walk being a Root plus every path, so that a variant's cost per tree build is in the figure.
\tvar walks = 0
\tlet clock = ContinuousClock()
\twalkEveryPath(Root())
\tlet start = clock.now
\tvar elapsed = Duration.zero
\twhile elapsed < .milliseconds(100) {
\t\twalkEveryPath(Root())
\t\twalks += 1
\t\telapsed = clock.now - start
\t}
\tlet (seconds, attoseconds) = elapsed.components
\tlet nanoseconds = Double(seconds) * 1e9 + Double(attoseconds) / 1e9
\tprint("\\(nanoseconds / Double(walks)) ns per walk, \\(walks) walks, \\(built / (walks + 1)) values per walk")
} else {
\tdo {
\t\tlet root = Root()
\t\twalkEveryPath(root)
\t\tprint("trace of every path:")
\t\tRegistry.printTrace()
\t\twithExtendedLifetime(root) {}
\t}
\tRegistry.printAlive("after dropping everything")
}
""")
    return "\n".join(lines)


# MARK: The struct


def struct_builder(members, indent, built_holes):
    pad = " " * indent
    lines = [f"{pad}nonisolated public struct __safeDI_Builder<Built> {{"]
    lines += [f"{pad}    public let {name}: ({values}) -> {returned}" for name, values, returned in members]
    lines.append("")
    lines.append(f"{pad}    public init(" + ", ".join(f"{name}: @escaping ({values}) -> {returned}" for name, values, returned in members) + ") {")
    lines += [f"{pad}        self.{name} = {name}" for name, _, _ in members]
    lines.append(f"{pad}    }}")
    lines.append("")
    lines.append(f"{pad}    public init(__safeDI_noScope builder: @escaping () -> Built) {{")
    lines += [f"{pad}        {name} = {{ _ in {'builder()' if returned == 'Built' else '.init(__safeDI_noScope: builder)'} }}" for name, _, returned in members]
    lines.append(f"{pad}    }}")
    lines.append(f"{pad}}}")
    return "\n".join(lines)


def struct_values(spec, name, label, fields, indent):
    pad = " " * indent
    if not fields:
        return f"{pad}nonisolated public struct {label}_Values {{}}"
    lines = [f"{pad}nonisolated public struct {label}_Values {{"]
    for field, type_, memo in fields:
        if memo:
            lines.append(f"{pad}    public var {field}: {type_} {{ __safeDI_{field}.instance }}")
        else:
            lines.append(f"{pad}    public let {field}: {type_}")
    for field, type_, memo in fields:
        if memo:
            lines.append(f"{pad}    let __safeDI_{field}: LazilyInstantiated<{type_}>")
    if any(memo for _, _, memo in fields):
        lines.append("")
        lines.append(f"{pad}    init(" + ", ".join(f"{field}: {f'LazilyInstantiated<{type_}>' if memo else type_}" for field, type_, memo in fields) + ") {")
        for field, _, memo in fields:
            lines.append(f"{pad}        {'__safeDI_' + field if memo else 'self.' + field} = {field}")
        lines.append(f"{pad}    }}")
    lines.append(f"{pad}}}")
    return "\n".join(lines)


def scope_types(spec, hole):
    """The types with a level struct for `hole`: every type that leads to a place of `hole`, in first-reach order."""
    order = []
    leads = {}

    def leads_to(name):
        if name not in leads:
            leads[name] = False
            leads[name] = any((kind == "hole" and target == hole) or (kind != "hole" and leads_to(target)) for _, kind, target in spec.properties(name))
        return leads[name]

    queue = [spec.seam]
    while queue:
        name = queue.pop(0)
        if name in order or not leads_to(name):
            continue
        order.append(name)
        queue += [target for _, kind, target in spec.properties(name) if kind != "hole"]
    return order, leads_to


def stem(hole):
    return hole


def members_of(spec, name, hole, leads_to, root_name):
    members = []
    for index, (label, kind, target) in enumerate(spec.properties(name)):
        if kind == "hole" and target == hole:
            members.append((index, label, "Built", None))
        elif kind != "hole" and leads_to(target):
            members.append((index, label, f"{target}_Scope.__safeDI_Builder<Built>" if name != root_name or True else "", target))
    return members


def struct_code(spec, hole):
    order, leads_to = scope_types(spec, hole)
    root = f"SafeDIScope_{stem(hole)}"
    lines = [f"    nonisolated public enum {root} {{"]
    body = []
    for name in order:
        members = members_of(spec, name, hole, leads_to, spec.seam)
        indent = 8 if name == spec.seam else 12
        parts = []
        for index, label, returned, _ in members:
            parts.append(struct_values(spec, name, label, spec.values_fields(name, index), indent))
        parts.append(struct_builder([(label, f"{label}_Values", returned) for _, label, returned, _ in members], indent, None))
        if name == spec.seam:
            body.insert(0, "\n\n".join(parts))
        else:
            body.append(f"        nonisolated public enum {name}_Scope {{\n" + "\n\n".join(parts) + "\n        }")
    lines.append("\n\n".join(body))
    lines.append("    }")
    return "\n".join(lines)


# MARK: Bodies


def initializer_arguments(spec, name, scope):
    """The arguments `name`'s initializer takes, read from `scope` (label -> expression)."""
    arguments = [f"{label}: {scope[label]}" for label in spec.forwarded(name)]
    arguments += [f"{label}: {scope[label]}" for label in spec.receives(name)]
    arguments += [f"{label}: {label}" for label, _, _ in spec.properties(name)]
    return ", ".join(arguments)


def builder_parameter(hole):
    return f"__safeDI_{hole[0].lower() + hole[1:]}Builder"


def values_arguments(spec, name, index, scope):
    fields = spec.values_fields(name, index)
    return ", ".join(f"{field}: {scope.get(field + '#memo', field) if memo else field}" for field, _, memo in fields)


def per_path_body(spec):
    """(c): today's per-path body over the struct: one nested function per property per path, a member call where
    today binds a payload."""
    out = []

    def build(name, scope, builders, indent):
        """Emits statements that bind each property of `name` and returns nothing; scope: label -> expression;
        builders: hole -> the variable holding `name`'s level struct, or None where `name` leads to no place of it."""
        pad = " " * indent
        for index, (label, kind, target) in enumerate(spec.properties(name)):
            child_builders = {}
            for hole in spec.hole_types():
                parent = builders.get(hole)
                if parent is None:
                    continue
                if (kind == "hole" and target == hole) or (kind != "hole" and leads[hole](target)):
                    if kind == "hole":
                        child_builders[hole] = parent
                    else:
                        variable = f"{parent}_{label}"
                        out.append(f"{pad}let {variable} = {parent}.{label}(.init({values_arguments(spec, name, index, scope)}))")
                        child_builders[hole] = variable
            if kind == "hole":
                out.append(f"{pad}let {label}: any {target} = {child_builders[target]}.{label}(.init({values_arguments(spec, name, index, scope)}))")
            elif not spec.properties(target) and kind == "const":
                out.append(f"{pad}let {label} = {target}({initializer_arguments(spec, target, scope)})")
            elif not spec.properties(target) and not spec.forwarded(target):
                out.append(f"{pad}let {label} = Instantiator<{target}> {{ {target}({initializer_arguments(spec, target, scope)}) }}")
            else:
                child_scope = dict(scope)
                for forwarded in spec.forwarded(target):
                    child_scope[forwarded] = forwarded
                parameters = ", ".join(f"{forwarded}: Int" for forwarded in spec.forwarded(target))
                out.append(f"{pad}func __safeDI_{label}({parameters}) -> {target} {{")
                build(target, child_scope, child_builders, indent + 4)
                out.append(f"{pad}    return {target}({initializer_arguments(spec, target, child_scope)})")
                out.append(f"{pad}}}")
                if kind == "const":
                    out.append(f"{pad}let {label}: {target} = __safeDI_{label}()")
                elif spec.forwarded(target):
                    out.append(f"{pad}let {label} = Instantiator<{target}> {{")
                    out.append(f"{pad}    __safeDI_{label}({', '.join(f'{f}: $0' for f in spec.forwarded(target))})")
                    out.append(f"{pad}}}")
                else:
                    out.append(f"{pad}let {label} = Instantiator<{target}>(__safeDI_{label})")
            scope[label] = label

    leads = {hole: scope_types(spec, hole)[1] for hole in spec.hole_types()}
    scope = {}
    for label in spec.pass_through:
        out.append(f"        let {label} = LazilyInstantiated<{cap(label)}>(__safeDI_{label})")
        scope[label] = f"{label}.instance"
        scope[label + "#memo"] = label
    build(spec.seam, scope, {hole: builder_parameter(hole) for hole in spec.hole_types()}, 8)
    out.append(f"        self.init({initializer_arguments(spec, spec.seam, scope)})")
    return "\n".join(out)


def per_type_body(spec):
    """(d): one function per type, declared callees first; each takes its level struct per hole type it leads to, its
    forwarded values and what it receives that is not a pass-through (a pass-through is the same declaration at every
    call, so it is captured)."""
    leads = {hole: scope_types(spec, hole)[1] for hole in spec.hole_types()}
    order = []
    seen = set()

    def visit(name):
        if name in seen:
            return
        seen.add(name)
        for _, kind, target in spec.properties(name):
            if kind != "hole":
                visit(target)
        order.append(name)

    visit(spec.seam)
    out = []
    scope_base = {}
    for label in spec.pass_through:
        out.append(f"        let {label} = LazilyInstantiated<{cap(label)}>(__safeDI_{label})")
        scope_base[label] = f"{label}.instance"
        scope_base[label + "#memo"] = label

    def lead_holes(name):
        return [hole for hole in spec.hole_types() if leads[hole](name)]

    def function_parameters(name):
        parameters = [f"_ {builder_parameter(hole)}: SafeDIScope_{stem(hole)}.{name}_Scope.__safeDI_Builder<any {hole}>" for hole in lead_holes(name)]
        parameters += [f"{label}: Int" for label in spec.forwarded(name)]
        parameters += [f"{label}: Int" for label in spec.receives(name) if label not in spec.pass_through]
        return ", ".join(parameters)

    def body(name, scope, indent, builders):
        pad = " " * indent
        lines = []
        for index, (label, kind, target) in enumerate(spec.properties(name)):
            if kind == "hole":
                lines.append(f"{pad}let {label}: any {target} = {builders[target]}.{label}(.init({values_arguments(spec, name, index, scope)}))")
                scope[label] = label
                continue
            arguments = []
            for hole in lead_holes(target):
                variable = f"{builders[hole]}_{label}"
                lines.append(f"{pad}let {variable} = {builders[hole]}.{label}(.init({values_arguments(spec, name, index, scope)}))")
                arguments.append(variable)
            received = [f"{r}: {scope[r]}" for r in spec.receives(target) if r not in spec.pass_through]
            if not spec.properties(target) and kind == "const":
                lines.append(f"{pad}let {label} = {target}({initializer_arguments(spec, target, scope)})")
            elif not spec.properties(target) and not spec.forwarded(target):
                lines.append(f"{pad}let {label} = Instantiator<{target}> {{ {target}({initializer_arguments(spec, target, scope)}) }}")
            elif kind == "const":
                call_arguments = ", ".join(arguments + received)
                lines.append(f"{pad}let {label}: {target} = __safeDI_{target}({call_arguments})")
            else:
                forwarded = [f"{f}: $0" for f in spec.forwarded(target)]
                call_arguments = ", ".join(arguments + forwarded + received)
                lines.append(f"{pad}let {label} = Instantiator<{target}> {{ __safeDI_{target}({call_arguments}) }}")
            scope[label] = label
        return lines

    for name in order:
        if name == spec.seam or not spec.properties(name):
            continue
        scope = dict(scope_base)
        for label in spec.forwarded(name) + [r for r in spec.receives(name) if r not in spec.pass_through]:
            scope[label] = label
        out.append(f"        func __safeDI_{name}({function_parameters(name)}) -> {name} {{")
        out += body(name, scope, 12, {hole: builder_parameter(hole) for hole in lead_holes(name)})
        out.append(f"            return {name}({initializer_arguments(spec, name, scope)})")
        out.append("        }")
    scope = dict(scope_base)
    out += body(spec.seam, scope, 8, {hole: builder_parameter(hole) for hole in spec.hole_types()})
    out.append(f"        self.init({initializer_arguments(spec, spec.seam, scope)})")
    return "\n".join(out)


def feature_code(spec, body):
    holes = spec.hole_types()
    readable = ", ".join([f"{label}: {cap(label)}" for label in spec.pass_through] + [f"{h[0].lower() + h[1:]}Builder: @escaping () -> any {h}" for h in holes])
    forwarding = ", ".join([f"__safeDI_{label}: {label}" for label in spec.pass_through] + [f"{builder_parameter(h)}: .init(__safeDI_noScope: {h[0].lower() + h[1:]}Builder)" for h in holes])
    generated = ", ".join([f"__safeDI_{label}: @autoclosure @escaping () -> {cap(label)}" for label in spec.pass_through] + [f"{builder_parameter(h)}: SafeDIScope_{stem(h)}.__safeDI_Builder<any {h}>" for h in holes])
    parts = ["import Harness", "import SafeDI", "", f"extension {spec.seam} {{"]
    parts += [struct_code(spec, hole) + "\n" for hole in holes]
    parts.append(f"    /// For code you write.\n    public convenience init({readable}) {{\n        self.init({forwarding})\n    }}\n")
    parts.append(f"    /// Only code SafeDI generates calls this initializer, and its shape can change in any release of SafeDI.\n    public convenience init({generated}) {{")
    parts.append(body)
    parts.append("    }\n}\n")
    return "\n".join(parts)


def app_code(spec):
    """The calling module's level functions: one per level struct, by type, shared by (c) and (d)."""
    seam_property = spec.seam[0].lower() + spec.seam[1:]
    lines = ["import Feature", "import Harness", "import SafeDI", "", "extension Root {", "    public convenience init() {"]
    for label, type_ in spec.root_declares:
        lines.append(f"        let {label} = {type_}()")
    lines.append(f"        func __safeDI_{seam_property}() -> {spec.seam} {{")
    for hole, fill in spec.holes.items():
        order, leads_to = scope_types(spec, hole)
        builder = hole[0].lower() + hole[1:] + "Builder"
        receives = spec.fill_receives.get(fill, [])
        carried = [r for r in receives if r not in spec.pass_through]
        needs = {}

        def need(name):
            """What `name`'s level function takes: the labels its fills read that no level from it down binds."""
            if name not in needs:
                needs[name] = set()
                result = set()
                for index, label, returned, target in members_of(spec, name, hole, leads_to, spec.seam):
                    fields = {field for field, _, _ in spec.values_fields(name, index)}
                    below = set(carried) if returned == "Built" else need(target)
                    result |= below - fields
                needs[name] = result
            return needs[name]

        for name in order:
            members = members_of(spec, name, hole, leads_to, spec.seam)
            parameters = ", ".join(f"{r}: Int" for r in carried if r in need(name)) if name != spec.seam else ""
            struct = f"{spec.seam}.SafeDIScope_{stem(hole)}" + ("" if name == spec.seam else f".{name}_Scope")
            function = f"__safeDI_{builder}_{spec.seam}" + ("" if name == spec.seam else f"_{name}_Scope")
            lines.append(f"            func {function}({parameters}) -> {struct}.__safeDI_Builder<any {hole}> {{")
            entries = []
            for index, label, returned, target in members:
                fields = [field for field, _, _ in spec.values_fields(name, index)]
                wanted = [r for r in carried if r in (set(carried) if returned == "Built" else need(target))]
                arguments = ", ".join(f"{r}: {'values.' + r if r in fields else r}" for r in wanted)
                reads = any(r in fields for r in wanted)
                callee = f"__safeDI_{fill[0].lower() + fill[1:]}" if returned == "Built" else f"__safeDI_{builder}_{spec.seam}_{target}_Scope"
                entries.append(f"{label}: {{ {'values' if reads else '_'} in {callee}({arguments}) }}")
            lines.append("                .init(\n                    " + ",\n                    ".join(entries) + "\n                )")
            lines.append("            }")
        fill_parameters = ", ".join(f"{r}: Int" for r in receives if r not in spec.pass_through)
        fill_arguments = ", ".join(f"{r}: {r}" for r in receives)
        lines.insert(lines.index(f"        func __safeDI_{seam_property}() -> {spec.seam} {{") + 1, f"            func __safeDI_{fill[0].lower() + fill[1:]}({fill_parameters}) -> any {hole} {{\n                {fill}({fill_arguments})\n            }}")
    arguments = ", ".join([f"__safeDI_{label}: {label}" for label in spec.pass_through] + [f"{builder_parameter(h)}: __safeDI_{h[0].lower() + h[1:]}Builder_{spec.seam}()" for h in spec.hole_types()])
    lines.append(f"            return {spec.seam}({arguments})")
    lines.append("        }")
    lines.append(f"        let {seam_property}: {spec.seam} = __safeDI_{seam_property}()")
    lines.append(f"        self.init({', '.join([f'{label}: {label}' for label, _ in spec.root_declares] + [f'{seam_property}: {seam_property}'])})")
    lines.append("    }")
    lines.append("}")
    return "\n".join(lines) + "\n"


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as file:
        file.write(text)


def layout(output, variant, mode):
    write(f"{output}/{variant}/Harness/shared", "../../common\n")
    write(f"{output}/{variant}/Main/shared", "main\n")
    if variant == "a":
        write(f"{output}/{variant}/modules.txt", "Harness plain\nApp tool Harness\nMain plain App Harness\n")
        write(f"{output}/{variant}/App/shared", "Inline\n")
    else:
        write(f"{output}/{variant}/modules.txt", f"Harness plain\nFeature {mode} Harness\nApp {mode} Feature Harness\nMain plain App Harness\n")
        write(f"{output}/{variant}/Feature/shared", "Feature\n")
        write(f"{output}/{variant}/App/shared", "App\n")


if __name__ == "__main__":
    spec = Spec(json.load(open(sys.argv[1])))
    output = sys.argv[2]
    header = "import Harness\nimport SafeDI\n\n"
    configuration = "#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n\n"
    write(f"{output}/Feature/Types.swift.txt", header + protocols(spec) + configuration + "".join(feature_types(spec)))
    write(f"{output}/App/Types.swift.txt", "import Feature\n" + header + "".join(app_types(spec)))
    write(f"{output}/Inline/Types.swift.txt", header + protocols(spec) + "".join(feature_types(spec, seam=False)) + "".join(app_types(spec)))
    write(f"{output}/main/main.swift.txt", main_swift(spec))
    for variant, mode in [("a", "tool"), ("b", "tool"), ("c", "hand"), ("d", "hand")]:
        layout(output, variant, mode)
    write(f"{output}/c/Feature/Generated/Feature.swift.txt", feature_code(spec, per_path_body(spec)))
    write(f"{output}/d/Feature/Generated/Feature.swift.txt", feature_code(spec, per_type_body(spec)))
    write(f"{output}/c/App/Generated/App.swift.txt", app_code(spec))
    write(f"{output}/d/App/Generated/App.swift.txt", app_code(spec))
