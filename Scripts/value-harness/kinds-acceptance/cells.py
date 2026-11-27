#!/usr/bin/env python3
"""Writes the mock cycle kind's acceptance cells as a Swift test file.

usage: cells.py TOOL OUT.swift

Each cell is a graph (written from a spec, or given as source) whose mock has an override at every place of its
configuration tree. Each override records the configuration path it was read from: the place a lap entered. A
fixture file `Walks.swift` holds seeded walks through the mock's instantiators and lazy wrappers, three and four laps
of the cycle deep, which return what each walk recorded: every step, then each override the step read. The probes
call those walks, so the comparator prints the entered places of each walk and compares them between the mock laid
out from node records and the mock's walk.

TOOL is a built `SafeDITool`, run once per cell to read the configuration tree the overrides fill.
"""
import json, os, re, subprocess, sys, tempfile

WRAPPERS = ("Instantiator", "SendableInstantiator", "LazilyInstantiated", "SendableLazilyInstantiated")


def split_top_level(text, separator=","):
    parts, depth, current = [], 0, ""
    for character in text:
        if character in "<([":
            depth += 1
        elif character in ">)]":
            depth -= 1
        if character == separator and depth == 0:
            parts.append(current.strip()); current = ""
        else:
            current += character
    if current.strip():
        parts.append(current.strip())
    return parts


# MARK: Sources from specs

def spelled(wrapper, built):
    return f"{wrapper}<{built}>" if wrapper else built


def spec_source(spec):
    """A spec's types: {"root": name, "types": {name: [[label, wrapper, built, kind?], ...]}, "sendable": [names],
    "structs": [names], "forwarded": {name: [[label, type]]}}."""
    out = []
    sendable, structs = set(spec.get("sendable", [])), set(spec.get("structs", []))
    for name, dependencies in spec["types"].items():
        attribute = "@Instantiable(generateMock: true)" if name == spec["root"] else "@Instantiable"
        kind = "struct" if name in structs else "final class"
        conformances = "Instantiable" + (", Sendable" if name in sendable or name in structs else "")
        forwarded = spec.get("forwarded", {}).get(name, [])
        parameters = [f"{label}: {spelled(d[1], d[2])}" for d in dependencies for label in [d[0]]] + [f"{label}: {type}" for label, type in forwarded]
        out += [attribute, f"public {kind} {name}: {conformances} {{", "    public init(" + ", ".join(parameters) + ") {"]
        out += [f"        self.{d[0]} = {d[0]}" for d in dependencies] + [f"        self.{label} = {label}" for label, _ in forwarded]
        out += ["    }", ""]
        for d in dependencies:
            attribute = "@Received" if len(d) > 3 and d[3] == "received" else "@Instantiated"
            out.append(f"    {attribute} public let {d[0]}: {spelled(d[1], d[2])}")
        for label, type in forwarded:
            out.append(f"    @Forwarded public let {label}: {type}")
        out += ["}", ""]
    return "\n".join(out)


# MARK: Reading the source

def parse_types(source):
    """Each declared type: its kind, init parameters (label, type), properties (attribute, label, type), the types it
    fulfills, and whether it generates a mock."""
    types = {}
    for match in re.finditer(r"(@Instantiable(?:\(([^\n]*)\))?)\s*public (final class|struct|actor) (\w+)\s*:([^{\n]*)\{\n(.*?)\n\}", source, re.S):
        arguments, kind, name, conformances, body = match.group(2) or "", match.group(3), match.group(4), match.group(5), match.group(6)
        init = re.search(r"public init\((.*?)\)\s*\{", body, re.S)
        parameters = []
        for parameter in split_top_level(init.group(1)) if init else []:
            label_part, type_part = parameter.split(":", 1)
            names = label_part.split()
            default = None
            if "=" in type_part:
                type_part, default = type_part.split("=", 1)
            parameters.append((names[0], names[-1], type_part.strip(), default.strip() if default else None))
        properties = [(attribute, label, type.strip()) for attribute, label, type in re.findall(r"@(Instantiated|Received|Forwarded)(?:\([^\n]*?\))? (?:public )?let (\w+): ([^\n]+)", body)]
        fulfills = re.findall(r"fulfillingAdditionalTypes: \[([^\]]*)\]", arguments)
        types[name] = {
            "kind": kind, "parameters": parameters, "properties": properties,
            "fulfills": [t.strip().removesuffix(".self") for t in fulfills[0].split(",")] if fulfills else [],
            "mock": "generateMock" in arguments,
        }
    for match in re.finditer(r"^(@Instantiable(?:\(([^\n]*)\))?)\s*public (final class|struct|actor) (\w+)\s*:([^{\n]*)\{ *public init\(\) \{\} *\}$", source, re.M):
        name = match.group(4)
        types.setdefault(name, {"kind": match.group(3), "parameters": [], "properties": [], "fulfills": [], "mock": "generateMock" in (match.group(2) or "")})
    return types


def concrete_type(types, spelled_type):
    bare = spelled_type.removeprefix("any ").strip()
    if bare in types:
        return bare
    for name, declaration in types.items():
        if bare in declaration["fulfills"]:
            return name
    return None


# MARK: Reading the generated configuration tree

def configurations(generated):
    """Each configuration's init parameters, by owner ("<root>" for the root's `SafeDIOverrides`)."""
    found = {}
    pattern = r"extension (\w+) \{\n(?:    ///[^\n]*\n)?    (?:nonisolated )?struct (SafeDIOverrides|SafeDIMockConfiguration)[^\n]*\{\n        init\(\n(.*?)\n        \) \{"
    for owner, kind, parameters in re.findall(pattern, generated, re.S):
        fields = []
        for line in parameters.split("\n"):
            line = line.strip().rstrip(",")
            match = re.match(r"(_ )?(\w+): (.*?)(?: = (.*))?$", line)
            if match:
                fields.append((match.group(2), match.group(3), match.group(4), bool(match.group(1))))
        found[(owner, kind)] = fields
    return found


def closure_parameter_count(closure_type):
    inner = re.match(r"\(+(?:@Sendable )?\((.*?)\) -> ", closure_type)
    return len(split_top_level(inner.group(1))) if inner and inner.group(1).strip() else 0


def construction(types, built, recorder_path, closure_type):
    """A closure that records `recorder_path` and builds `built` with the closure's arguments, in its initializer's order."""
    count = closure_parameter_count(closure_type)
    parameters = types[built]["parameters"]
    names = [f"a{index}" for index in range(count)]
    arguments = []
    for (label, _, _, _), name in zip(parameters, names):
        arguments.append(name if label == "_" else f"{label}: {name}")
    head = ", ".join(names) + " in " if names else ""
    return "{ " + head + f"recorder.record(\"{recorder_path}\"); return {built}(" + ", ".join(arguments) + ") }"


def overrides_expression(types, found, owner, kind, path, built):
    arguments = []
    for label, type, default, unlabeled in found.get((owner, kind), []):
        place = ".".join(path + [label]) if label != "safeDIBuilder" else ".".join(path)
        nested = re.match(r"(\w+)\.SafeDIMockConfiguration$", type)
        if nested:
            arguments.append(f"{label}: " + overrides_expression(types, found, nested.group(1), "SafeDIMockConfiguration", path + [label], nested.group(1)))
        elif label == "safeDIBuilder":
            arguments.append(construction(types, built, place, type))
        elif type.startswith("((") and type.endswith(")?"):
            leaf = concrete_type(types, re.search(r"-> (.*)\)\?$", type).group(1))
            if leaf is not None and types[leaf]["kind"] != "actor":
                arguments.append(f"{label}: " + construction(types, leaf, place, type))
        elif re.search(r"\bString\b", type) and default is not None and default.startswith('"'):
            arguments.append(f"{label}: \"{place}\"")
    return ".init(" + ", ".join(arguments) + ")"


# MARK: Walks

def step_expression(type):
    for wrapper in ("SendableInstantiator", "Instantiator", "SendableErasedInstantiator", "ErasedInstantiator"):
        if type.startswith(wrapper + "<"):
            return ".instantiate()", type[len(wrapper) + 1:-1].split(",")[-1].strip()
    for wrapper in ("SendableLazilyInstantiated", "LazilyInstantiated"):
        if type.startswith(wrapper + "<"):
            return ".instance", type[len(wrapper) + 1:-1]
    return "", type


def walks_source(types, root, root_call, overrides):
    out = [
        "/// What a mock’s overrides recorded, in order: each step of a walk, then each override the step read.",
        "public final class Recorder: @unchecked Sendable {",
        "    public init() {}",
        "    public private(set) var log = [String]()",
        "    public func record(_ entry: String) { log.append(entry) }",
        "}",
        "",
        "struct WalkGenerator {",
        "    var state: UInt64",
        "    mutating func next(_ bound: Int) -> Int {",
        "        state = state &* 6364136223846793005 &+ 1442695040888963407",
        "        return Int((state >> 33) % UInt64(bound))",
        "    }",
        "}",
        "",
    ]
    walkable = {name for name, declaration in types.items() if declaration["kind"] != "actor"}
    for name in sorted(walkable):
        steps = []
        for attribute, label, type in types[name]["properties"]:
            if attribute == "Forwarded" or type.endswith("?"):
                continue
            read, built = step_expression(type)
            concrete = concrete_type(types, built)
            if concrete is None or concrete not in walkable:
                continue
            value = f"value.{label}{read}"
            if concrete != built.removeprefix("any ").strip():
                value = f"({value} as! {concrete})"
            steps.append((label, value, concrete))
        out.append(f"func walk(_ value: {name}, _ depth: Int, _ generator: inout WalkGenerator, _ recorder: Recorder) {{")
        if steps:
            out += ["    guard depth > 0 else { return }", f"    switch generator.next({len(steps)}) {{"]
            for index, (label, value, concrete) in enumerate(steps):
                case = "default" if index == len(steps) - 1 else f"case {index}"
                out.append(f"    {case}: recorder.record(\"-> {label}\"); walk({value}, depth - 1, &generator, recorder)")
            out.append("    }")
        else:
            out.append("    _ = (value, depth, generator, recorder)")
        out += ["}", ""]
    out += [
        "#if DEBUG",
        f"func overridesAtEveryPlace(_ recorder: Recorder) -> {root}.SafeDIOverrides {{",
        f"    {overrides}",
        "}",
        "",
        "/// The entered places of each walk of `seeds`, `depth` steps deep, each from a new mock.",
        "func walks(seeds: Range<Int>, depth: Int) -> [String] {",
        "    let recorder = Recorder()",
        "    for seed in seeds {",
        "        recorder.record(\"walk \\(seed)\")",
        "        var generator = WalkGenerator(state: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 1)",
        f"        walk({root_call}, depth, &generator, recorder)",
        "    }",
        "    return recorder.log",
        "}",
        "",
        "/// How many overrides the walks of `seeds` read, and a digest of every entry they recorded, in order.",
        "func walkDigest(seeds: Range<Int>, depth: Int) -> [UInt64] {",
        "    var digest: UInt64 = 0xCBF2_9CE4_8422_2325",
        "    var reads: UInt64 = 0",
        "    for entry in walks(seeds: seeds, depth: depth) {",
        "        if !entry.hasPrefix(\"-> \"), !entry.hasPrefix(\"walk \") { reads += 1 }",
        "        for byte in entry.utf8 { digest = (digest ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }",
        "        digest = (digest ^ 10) &* 0x0000_0100_0000_01B3",
        "    }",
        "    return [reads, digest]",
        "}",
        "#endif",
    ]
    return "\n".join(out) + "\n"


def generate(tool, files):
    with tempfile.TemporaryDirectory(dir="/home/user/tmpdir") as directory:
        paths = []
        for name, source in files.items():
            path = f"{directory}/{name}"
            open(path, "w").write(source)
            paths.append(path)
        open(f"{directory}/sources.csv", "w").write("\n".join(paths) + "\n")
        result = subprocess.run([tool, "generate", f"{directory}/sources.csv", "--combined-output", f"{directory}/out.swift",
                                 "--active-compilation-conditions", "DEBUG", "--module-name", "App"],
                                capture_output=True, text=True, env=dict(os.environ, TMPDIR=directory))
        if result.returncode != 0:
            raise SystemExit(f"generate failed: {result.stderr[:2000]}")
        return open(f"{directory}/out.swift").read()


def cell(tool, name, files, root, root_arguments="", cycle_length=1, walk_seeds=8, digest_seeds=400, extra_probes=()):
    source = "\n".join(files.values())
    types = parse_types(source)
    generated = generate(tool, files)
    found = configurations(generated)
    overrides = overrides_expression(types, found, root, "SafeDIOverrides", [], root)
    root_call = f"{root}.mock({root_arguments}{', ' if root_arguments else ''}safeDIOverrides: overridesAtEveryPlace(recorder))"
    walks = walks_source(types, root, root_call, overrides)
    probes = []
    for laps in (3, 4):
        depth = laps * cycle_length
        for seed in range(walk_seeds):
            probes.append(f"walks(seeds: {seed} ..< {seed + 1}, depth: {depth})")
        probes.append(f"walkDigest(seeds: 0 ..< {digest_seeds}, depth: {depth})")
    probes += list(extra_probes)
    return {"name": name, "files": dict(files, **{"Walks.swift": walks}), "probes": probes}


def swift_string(text, indent):
    lines = text.rstrip("\n").split("\n")
    return '#"""\n' + "\n".join((indent + line) if line else "" for line in lines) + "\n" + indent + '"""#'


def test_file(cells, header):
    out = [header]
    for c in cells:
        out += ["", "\t@Test", "\t@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)"]
        if c.get("knownIssue"):
            out.append(f"\tmutating func {c['name']}() async throws {{")
            out.append(f"\t\t// {c['comment']}")
            out.append(f"\t\tawait withKnownIssue(\"{c['knownIssue']}\") {{")
            indent = "\t\t\t"
        else:
            out.append(f"\tmutating func {c['name']}() async throws {{")
            if c.get("comment"):
                out.append(f"\t\t// {c['comment']}")
            indent = "\t\t"
        out.append(f"{indent}try await MockKindsAcceptance.expectLaidOutValuesEqualWalks(fixtureFiles: [")
        for file_name, source in sorted(c["files"].items()):
            out.append(f"{indent}\t\"{file_name}\": " + swift_string(source, indent + "\t") + ",")
        out.append(f"{indent}], probes: [")
        for probe in c["probes"]:
            out.append(f"{indent}\tDifferentialValueProbe(\"{probe}\"),")
        out.append(f"{indent}], filesToDelete: &filesToDelete)")
        if c.get("knownIssue"):
            out.append("\t\t}")
        out.append("\t}")
    out += ["", "\t// MARK: Private", "", "\tprivate var filesToDelete: [URL]", "}", ""]
    return "\n".join(out)
