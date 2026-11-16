"""Stage 2, shape E (synthetic growth shape): writes the fixture types for N screens.

N screens in N/4 layers of four. Screen<i> { @Forwarded id: Int; @Received service: Service; @Instantiated model<i>: Model<i>;
screen<c>Builder: Instantiator<Screen<c>> for each c = (layer+1)*4+k, k != i mod 4, outside the last layer }.
Model<i> { @Received id; @Received service; last layer: @Instantiated api: any Api }. The seam Home has screen0Builder
through screen3Builder. App: LiveApi { @Received id; @Received service }, Root { service; home }.

Usage: python3 -I shape_e.py N OUTPUT_DIRECTORY
Types log what they receive only under `-D SPIKE_TRACE`, so the benchmark build pays no tracing cost."""
import os
import sys


def children(i, layers):
    layer = i // 4
    if layer == layers - 1:
        return []
    return [(layer + 1) * 4 + k for k in range(4) if k != i % 4]


def swift_class(name, properties, attributes="", conformances=""):
    """properties: (attribute, label, type)."""
    parameters = ", ".join(f"{label}: {type_}" for _, label, type_ in properties)
    received = ", ".join(f'"{label}": {label}' for _, label, _ in properties) or ":"
    lines = [f"@Instantiable{attributes}", f"public final class {name}: Instantiable{conformances} {{", f"    public init({parameters}) {{"]
    lines += [f"        self.{label} = {label}" for _, label, _ in properties]
    lines += ["        #if SPIKE_TRACE", f"        Registry.created(self, [{received}])", "        #endif", "    }", ""]
    lines += [f"    {attribute} public let {label}: {type_}" for attribute, label, type_ in properties]
    lines += ["    #if SPIKE_TRACE", f'    public let tracker = Tracker("{name}")', "    #endif", "}", ""]
    lines += ["#if SPIKE_TRACE", f"extension {name}: Traced {{}}", "#endif", ""]
    return "\n".join(lines) + "\n"


def feature_types(n):
    layers = n // 4
    types = [swift_class("Service", [])]
    types.append(swift_class("Home", [("@Instantiated", f"screen{k}Builder", f"Instantiator<Screen{k}>") for k in range(4)], "(generateDependencyTree: true)"))
    for i in range(n):
        properties = [("@Forwarded", "id", "Int"), ("@Received", "service", "Service"), ("@Instantiated", f"model{i}", f"Model{i}")]
        properties += [("@Instantiated", f"screen{c}Builder", f"Instantiator<Screen{c}>") for c in children(i, layers)]
        types.append(swift_class(f"Screen{i}", properties))
        model = [("@Received", "id", "Int"), ("@Received", "service", "Service")]
        if i // 4 == layers - 1:
            model.append(("@Instantiated", "api", "any Api"))
        types.append(swift_class(f"Model{i}", model))
    return types


def app_types():
    return [
        swift_class("LiveApi", [("@Received", "id", "Int"), ("@Received", "service", "Service")], "(fulfillingAdditionalTypes: [(any Api).self])", ", Api"),
        swift_class("Root", [("@Instantiated", "service", "Service"), ("@Instantiated", "home", "Home")], "(isRoot: true)"),
    ]


def main_swift(n):
    """Walks every path: builds every screen every builder can build, with ids numbered in walk order."""
    layers = n // 4
    lines = ["import App", "#if canImport(Feature)", "import Feature", "#endif", "import Harness", "", "nonisolated(unsafe) var nextIdentifier = 0", "nonisolated(unsafe) var built = 0", ""]
    lines.append("func identifier() -> Int {\n\tnextIdentifier += 1\n\treturn nextIdentifier\n}\n")
    for i in range(n):
        lines.append(f"func walk(_ screen: Screen{i}) {{")
        lines.append(f"\tbuilt += 1")
        if i // 4 == layers - 1:
            lines.append(f"\twithExtendedLifetime(screen.model{i}.api) {{}}")
        for c in children(i, layers):
            lines.append(f"\twalk(screen.screen{c}Builder.instantiate(identifier()))")
        lines.append("}\n")
    lines.append("func walkEveryPath(_ root: Root) {")
    for k in range(4):
        lines.append(f"\twalk(root.home.screen{k}Builder.instantiate(identifier()))")
    lines.append("}\n")
    lines.append("""let arguments = CommandLine.arguments
if arguments.count > 1, arguments[1] == "bench" {
\t// One round: repeats the walk until it lasts at least 100 ms; prints nanoseconds per walk.
\tlet root = Root()
\twalkEveryPath(root)
\tvar walks = 0
\tlet clock = ContinuousClock()
\tlet start = clock.now
\tvar elapsed = Duration.zero
\twhile elapsed < .milliseconds(100) {
\t\twalkEveryPath(root)
\t\twalks += 1
\t\telapsed = clock.now - start
\t}
\tlet (seconds, attoseconds) = elapsed.components
\tlet nanoseconds = Double(seconds) * 1e9 + Double(attoseconds) / 1e9
\tprint("\\(nanoseconds / Double(walks)) ns per walk, \\(walks) walks, \\(built / (walks + 1)) screens per walk")
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


if __name__ == "__main__":
    n = int(sys.argv[1])
    output = sys.argv[2]
    header = "import Harness\nimport SafeDI\n\n"
    protocol = "public protocol Api: AnyObject {}\n\n"
    configuration = "#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n\n"
    for directory, text in [
        ("Feature", header + protocol + configuration + "".join(feature_types(n))),
        ("App", "import Feature\n" + header + "".join(app_types())),
        ("Inline", header + protocol + "".join(t.replace("(generateDependencyTree: true)", "") for t in feature_types(n)) + "".join(app_types())),
    ]:
        os.makedirs(f"{output}/{directory}", exist_ok=True)
        open(f"{output}/{directory}/Types.swift.txt", "w").write(text)
    os.makedirs(f"{output}/main", exist_ok=True)
    open(f"{output}/main/main.swift.txt", "w").write(main_swift(n))
