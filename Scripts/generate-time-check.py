#!/usr/bin/env python3
"""Usage: generate-time-check.py [--runs N] [--limit RATIO] [--memory-limit RATIO] [--large-memory-limit RATIO]
                                [--size-limit RATIO] [--shapes NAME,…] [--summary FILE] BASE_TOOL HEAD_TOOL DIRECTORY
       generate-time-check.py --self-test DIRECTORY

Compares how long two builds of `SafeDITool` take to `generate` synthetic dependency graphs, and exits 1 when
HEAD_TOOL takes RATIO (default 2) times as long as BASE_TOOL, or longer, on any of them, or needs MEMORY-LIMIT (default
1.3) times its peak memory, or LARGE-MEMORY-LIMIT (default 1.1) times on the shapes whose peak is the largest.
"Check Generate Time on Linux"
in ci.yml runs it with main's tool as BASE_TOOL and the change's as HEAD_TOOL, so a change that makes generation several
times slower is seen before it lands, not when an adopter's build slows down.

It also compares the size of each module's `.safedi` file, which every build system that runs `generate` per module
stores, uploads to its cache and reads back for each module above it, and exits 1 when a module's file from HEAD_TOOL
is RATIO (`--size-limit`, default 2) times the size of BASE_TOOL's, or larger, and also more than 4 KB larger, since a
few bytes more of a small file are not what the check is for. Storing seam signatures in the module info once made
E24-fill's `Feature.safedi` 400 times the size it had been, and no check saw it.

DIRECTORY, which must not exist, receives the shapes' sources and each run's output; keep it out of the system
temporary directory. Each shape is generated as Bazel and Tuist generate: `generate --combined-output
--module-info-output` once per module, in dependency order, each module reading the `.safedi` files of the modules
beneath it. A shape's time is the sum over its modules.

The shapes (every name invented; `--shapes` picks among them, default all):
  E16-seam, E24-seam   `Home` builds screens 0–3 through `Instantiator`s; screen i, in layer i / 4, builds its model
                       and the three screens of the next layer other than the one at its own position; the last
                       layer's models take `any Api`, which no type of their module fulfills. `Home` is a seam
                       (`generateDependencyTree: true`) in module `Feature`, and module `App` declares the root and
                       the type that fulfills `any Api`. The number is the count of screens, so E24 is six layers
                       deep and has 3^6 paths.
  E32-inline           the same graph, eight layers deep, with every type in the root's module and no seam.
  D20                  twenty screens with the same edges, each a seam in a module of its own, and a root with a
                       generated mock in module `App`: 22 modules.
  E24-public-mock      E24-seam with a public mock: `Home` is also `generateMock: .public`, every other type of
                       `Feature` but `Service` is `internal`, so `App` cannot build `Home`'s tree, and `App`'s root
                       generates a mock, which calls `Home`'s public mock and fills its hole with `LiveApi`.
  E24-fill             E24-seam with holes at every level: each screen also instantiates `any Store`, which only
                       `LiveStore` in `App` fulfills, so `App` fills two holes with places in every layer.
  E24-sendable-builder E24-seam built through `SendableInstantiator`s, with every type `Sendable`, so the hole's
                       places are inside `@Sendable` functions and `Home` takes, and `App` fills, `@Sendable`
                       builder structs.
  E24-lazy             E24-seam whose root holds `service` as a `LazilyInstantiated`, which the screens receive by
                       value and the models as the wrapper, and whose screens each hold their model as a
                       `LazilyInstantiated`.
  I800-seam            eight hundred seams that reach none of one another in module `Feature`, seam i
                       instantiating model i, both receiving `Service`, and a root in module `App` that instantiates
                       `Service` and every seam. Computing a module's seam signatures once took time that grew with
                       the square of its seams, which made this shape take 2.6 times as long on Linux.

The four shapes below are the ones whose peak memory is the largest, each one module with no seam, as a project that
has not adopted seams writes its graph. They take the tighter memory limit (see "Peak memory"):
  S12-mocks            twelve screens, each holding `Instantiator`s of three other screens drawn at random from a fixed
                       seed, some declaring, receiving or optionally receiving `Context`, and a root that builds
                       screen 0. Every type has `generateMock: true`, so each of the thirteen mocks holds a tree of
                       the whole graph beneath it.
  S16                  the same graph at sixteen screens from another seed, without mocks: the production tree of a
                       graph whose screens reach one another.
  E32-inline-mocks     E32-inline with `generateMock: true` on `Home` and on each of the thirty-two screens.
  C1500-mock-chain     a root with `generateMock: true` whose `Instantiator` builds feature 0, which builds feature
                       1, and so on for 1,500 features, each receiving `Service`: one tree 1,500 levels deep.

How it measures: one untimed run of each tool per shape, then N (default 5) timed runs of each, alternating base and
head so that a busy moment on the machine falls on both. The figure compared is the median wall time. CPU time (user
plus system, of the tool's processes) is printed beside it, since a wall time alone cannot tell a slower tool from a
busier machine. A shape fails only when the head's median is also more than 0.1 s above the base's, because below
that the time is the processes starting, not the generator.

Peak memory is each `generate` process's maximum resident set size, which the operating system reports for the child
when it exits (`getrusage` through `os.wait4`); a shape's figure is the largest of its modules', and the figure compared
is its median over the timed runs. It has far less noise than time, so its limit is tighter: a shape fails when the
head's median peak is MEMORY-LIMIT times the base's or more, and also more than 8 MB above it, because below that the
peak is the process's own start, not the generator's work. The four large shapes fail at LARGE-MEMORY-LIMIT, with the
same 8 MB: they are where a build's memory is decided, and each once peaked at 1.5 to 4.5 times what it needs now, so
a tenth more on one of them is a tenth more on the largest module of a project shaped like it.

A shape the base tool cannot generate (a new attribute, say) is reported and not compared. A shape the head tool cannot
generate fails the check: the shapes are valid SafeDI, so either the change broke them or they need updating with it.

Exit status: 0 no shape or module at or over a limit; 1 one is, or the head tool failed on one; 2 usage, or DIRECTORY
exists.

--self-test DIRECTORY runs the comparison with stand-in tools (one of which sleeps) and checks each verdict above.
"""
import os
import random
import statistics
import subprocess
import sys
import time

NOISE_FLOOR_SECONDS = 0.1
MEMORY_NOISE_FLOOR_BYTES = 8 * 1024 * 1024
# `ru_maxrss` is in kilobytes on Linux and in bytes on macOS.
MAXRSS_BYTES = 1 if sys.platform == "darwin" else 1024
SIZE_NOISE_FLOOR_BYTES = 4096


# MARK: Shapes


def declaration(attribute, name, properties, conformances="Instantiable", access="public ", initializer_access="public "):
    """One `@Instantiable` class whose initializer takes and stores `properties`: (macro, label, type) each."""
    parameters = ", ".join(f"{label}: {type_}" for _, label, type_ in properties)
    lines = [attribute, f"{access}final class {name}: {conformances} {{", f"\t{initializer_access}init({parameters}) {{"]
    lines += [f"\t\tself.{label} = {label}" for _, label, _ in properties]
    lines += ["\t}", ""]
    lines += [f"\t{macro} {initializer_access}let {label}: {type_}" for macro, label, type_ in properties]
    lines += ["}", ""]
    return "\n".join(lines) + "\n"


def builder(screen, wrapper="Instantiator"):
    return ("@Instantiated", f"screen{screen}Builder", f"{wrapper}<Screen{screen}>")


def next_layer(screen, count):
    """The screens `screen` builds: the next layer's, except the one at its own position; none from the last layer."""
    layer = screen // 4
    if layer == count // 4 - 1:
        return []
    else:
        return [(layer + 1) * 4 + position for position in range(4) if position != screen % 4]


def shape_e(count, seam, variant=None):
    """Returns the shape's modules, in build order: (name, the modules it depends on, its source).

    `variant` is None, or one of "public-mock", "fill", "sendable-builder", "lazy" and "mocks", as the module's
    docstring describes them."""
    sendable = variant == "sendable-builder"
    conformances = "Instantiable, Sendable" if sendable else "Instantiable"
    wrapper = "SendableInstantiator" if sendable else "Instantiator"
    # A type of `Feature` that `App` names stays public; under a public mock, the rest of the tree is internal.
    inner = {"access": "", "initializer_access": ""} if variant == "public-mock" else {}
    protocols = "public protocol Api: AnyObject, Sendable {}\n\n" if sendable else "public protocol Api: AnyObject {}\n\n"
    if variant == "fill":
        protocols += "public protocol Store: AnyObject {}\n\n"
    feature = "import SafeDI\n\n" + protocols
    if seam:
        feature += "#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n\n"
    feature += declaration("@Instantiable", "Service", [], conformances=conformances)
    home_attribute = "@Instantiable(generateDependencyTree: true, generateMock: .public)" if variant == "public-mock" else "@Instantiable(generateDependencyTree: true)" if seam else "@Instantiable(generateMock: true)" if variant == "mocks" else "@Instantiable"
    screen_attribute = "@Instantiable(generateMock: true)" if variant == "mocks" else "@Instantiable"
    feature += declaration(home_attribute, "Home", [builder(screen, wrapper) for screen in range(4)], conformances=conformances, initializer_access="" if variant == "public-mock" else "public ")
    service = ("@Received", "service", "Service")
    for screen in range(count):
        children = next_layer(screen, count)
        model = ("@Instantiated", f"model{screen}", f"LazilyInstantiated<Model{screen}>" if variant == "lazy" else f"Model{screen}")
        properties = [("@Forwarded", "id", "Int"), service, model] + [builder(child, wrapper) for child in children]
        if variant == "fill":
            properties.append(("@Instantiated", "store", "any Store"))
        feature += declaration(screen_attribute, f"Screen{screen}", properties, conformances=conformances, **inner)
        model_service = ("@Received", "service", "LazilyInstantiated<Service>") if variant == "lazy" else service
        received = [("@Received", "id", "Int"), model_service]
        feature += declaration("@Instantiable", f"Model{screen}", received + ([] if children else [("@Instantiated", "api", "any Api")]), conformances=conformances, **inner)
    received = [("@Received", "id", "Int"), ("@Received", "service", "Service")]
    app = declaration("@Instantiable(fulfillingAdditionalTypes: [(any Api).self])", "LiveApi", received, conformances=f"{conformances}, Api")
    if variant == "fill":
        app += declaration("@Instantiable(fulfillingAdditionalTypes: [(any Store).self])", "LiveStore", received, conformances="Instantiable, Store")
    root_service = ("@Instantiated", "service", "LazilyInstantiated<Service>" if variant == "lazy" else "Service")
    root_attribute = "@Instantiable(isRoot: true, generateMock: true)" if variant == "public-mock" else "@Instantiable(isRoot: true)"
    app += declaration(root_attribute, "Root", [root_service, ("@Instantiated", "home", "Home")])
    if seam:
        return [("Feature", [], feature), ("App", ["Feature"], "import Feature\nimport SafeDI\n\n" + app)]
    else:
        return [("App", [], feature + app)]


def shape_d(count):
    modules = [("Core", [], "import SafeDI\n\n" + declaration("@Instantiable", "Service", []))]
    for screen in reversed(range(count)):
        children = next_layer(screen, count)
        dependencies = ["Core"] + [f"M{child}" for child in children]
        properties = [("@Forwarded", "id", "Int"), ("@Received", "service", "Service"), ("@Instantiated", f"model{screen}", f"Model{screen}")]
        source = declaration("@Instantiable(generateDependencyTree: true)", f"Screen{screen}", properties + [builder(child) for child in children])
        source += declaration("@Instantiable", f"Model{screen}", [("@Received", "id", "Int"), ("@Received", "service", "Service")])
        modules.append((f"M{screen}", dependencies, source))
    root = declaration("@Instantiable(isRoot: true, generateMock: true)", "Root", [("@Instantiated", "service", "Service")] + [builder(screen) for screen in range(4)])
    modules.append(("App", [name for name, _, _ in modules], root))
    beneath = {}
    for name, dependencies, _ in modules:
        beneath[name] = sorted(set(dependencies).union(*(beneath[dependency] for dependency in dependencies)))
    return [(name, dependencies, (source if name == "Core" else "import SafeDI\n" + "".join(f"import {module}\n" for module in beneath[name]) + "\n" + source)) for name, dependencies, source in modules]


def shape_i(count):
    feature = "import SafeDI\n\n#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n\n"
    feature += declaration("@Instantiable", "Service", [])
    received = ("@Received", "service", "Service")
    for seam in range(count):
        feature += declaration("@Instantiable(generateDependencyTree: true)", f"Seam{seam}", [received, ("@Instantiated", f"model{seam}", f"Model{seam}")])
        feature += declaration("@Instantiable", f"Model{seam}", [received])
    app = declaration("@Instantiable(isRoot: true)", "Root", [("@Instantiated", "service", "Service")] + [("@Instantiated", f"seam{seam}", f"Seam{seam}") for seam in range(count)])
    return [("Feature", [], feature), ("App", ["Feature"], "import Feature\nimport SafeDI\n\n" + app)]


def shape_s(count, seed, mocks):
    """One module: `count` screens that hold builders of three other screens each, chosen by `seed`."""
    generator = random.Random(seed)
    attribute = "@Instantiable(generateMock: true)" if mocks else "@Instantiable"
    source = "import SafeDI\n\n"
    for screen in range(count):
        targets = generator.sample([other for other in range(count) if other != screen], 3)
        properties = [("@Forwarded", "id", "String"), ("@Received", "service", "Service")]
        role = generator.choice(["declares", "receives", "receivesIfAvailable", "none"])
        if role == "declares":
            properties.append(("@Instantiated", "context", "Context"))
        elif role == "receives":
            properties.append(("@Received", "context", "Context"))
        elif role == "receivesIfAvailable":
            properties.append(("@Received(onlyIfAvailable: true)", "context", "Context?"))
        source += declaration(attribute, f"Screen{screen}", properties + [builder(target) for target in sorted(targets)])
    root = [("@Instantiated", "service", "Service"), ("@Instantiated", "context", "Context"), builder(0)]
    source += declaration("@Instantiable(isRoot: true, generateMock: true)" if mocks else "@Instantiable(isRoot: true)", "Root", root)
    source += declaration(attribute, "Service", []) + declaration(attribute, "Context", [])
    return [("App", [], source)]


def shape_c(depth):
    """One module: a mocked root above a chain of `depth` features, each building the next through an `Instantiator`."""
    service = ("@Received", "service", "Service")
    source = "import SafeDI\n\n" + declaration("@Instantiable", "Service", [])
    source += declaration("@Instantiable(generateMock: true)", "Root", [("@Instantiated", "service", "Service"), ("@Instantiated", "feature0", "Instantiator<Feature0>")])
    for feature in range(depth):
        following = [("@Instantiated", f"feature{feature + 1}", f"Instantiator<Feature{feature + 1}>")] if feature + 1 < depth else []
        source += declaration("@Instantiable", f"Feature{feature}", [service] + following)
    return [("App", [], source)]


SHAPES = {
    "E16-seam": lambda: shape_e(16, seam=True),
    "E24-seam": lambda: shape_e(24, seam=True),
    "E32-inline": lambda: shape_e(32, seam=False),
    "D20": lambda: shape_d(20),
    "E24-public-mock": lambda: shape_e(24, seam=True, variant="public-mock"),
    "E24-fill": lambda: shape_e(24, seam=True, variant="fill"),
    "E24-sendable-builder": lambda: shape_e(24, seam=True, variant="sendable-builder"),
    "E24-lazy": lambda: shape_e(24, seam=True, variant="lazy"),
    "I800-seam": lambda: shape_i(800),
    "S12-mocks": lambda: shape_s(12, seed=5, mocks=True),
    "S16": lambda: shape_s(16, seed=1, mocks=False),
    "E32-inline-mocks": lambda: shape_e(32, seam=False, variant="mocks"),
    "C1500-mock-chain": lambda: shape_c(1500),
}

# The shapes whose peak memory is held to `--large-memory-limit`.
LARGE_MEMORY_SHAPES = frozenset(["S12-mocks", "S16", "E32-inline-mocks", "C1500-mock-chain"])


# MARK: Running a tool


class Failure(Exception):
    pass


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as handle:
        handle.write(text)


def generate(tool, modules, sources, output):
    """Runs `generate` for each module into `output`; returns (wall seconds, CPU seconds, peak bytes): the times summed
    over the modules, the peak the largest of the modules' processes' maximum resident set sizes."""
    os.makedirs(output, exist_ok=True)
    environment = dict(os.environ, TMPDIR=output)
    beneath = {}
    wall = 0.0
    cpu = 0.0
    peak = 0
    for name, dependencies, _ in modules:
        beneath[name] = sorted(set(dependencies).union(*(beneath[dependency] for dependency in dependencies)))
        write(f"{output}/{name}.csv", f"{sources}/{name}/Types.swift\n")
        command = [tool, "generate", f"{output}/{name}.csv", "--combined-output", f"{output}/{name}.generated.swift",
                   "--module-info-output", f"{output}/{name}.safedi", "--active-compilation-conditions", "DEBUG",
                   "--module-name", name, "--package-name", "GenerateTimeCheck"]
        if dependencies:
            write(f"{output}/{name}.dependencies.csv", "".join(f"{output}/{dependency}.safedi\n" for dependency in dependencies))
            write(f"{output}/{name}.transitive.csv", "".join(f"{output}/{module}.safedi\n" for module in beneath[name]))
            command += ["--dependent-module-info-file-path", f"{output}/{name}.dependencies.csv",
                        "--transitive-module-info-file-path", f"{output}/{name}.transitive.csv"]
        with open(f"{output}/{name}.log", "wb") as log:
            started = time.monotonic()
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, env=environment)
            _, status, usage = os.wait4(process.pid, 0)
            wall += time.monotonic() - started
            process.returncode = os.waitstatus_to_exitcode(status)
        cpu += usage.ru_utime + usage.ru_stime
        peak = max(peak, usage.ru_maxrss * MAXRSS_BYTES)
        if process.returncode != 0:
            with open(f"{output}/{name}.log", errors="replace") as log:
                raise Failure(f"`generate` of module {name} exited {process.returncode}: {log.read().strip()[-1500:]}")
    return wall, cpu, peak


def module_info_sizes(modules, output):
    return [os.path.getsize(f"{output}/{name}.safedi") for name, _, _ in modules]


def generated_code(modules, output):
    code = []
    for name, _, _ in modules:
        with open(f"{output}/{name}.generated.swift") as handle:
            code.append(handle.read().replace(output, ""))
    return code


# MARK: Comparing


def compare(base_tool, head_tool, directory, shapes, runs, limit, memory_limit, size_limit, large_memory_limit=1.1, large_memory_shapes=LARGE_MEMORY_SHAPES):
    """Returns (the time and memory table's rows, the size table's rows, the failures)."""
    rows = []
    size_rows = []
    failures = []
    for shape in shapes:
        modules = SHAPES[shape]()
        shape_memory_limit = min(memory_limit, large_memory_limit) if shape in large_memory_shapes else memory_limit
        sources = f"{directory}/{shape}/sources"
        for name, _, source in modules:
            write(f"{sources}/{name}/Types.swift", source)
        tools = {"base": base_tool, "head": head_tool}
        samples = {"base": [], "head": []}
        code = {}
        sizes = {}
        try:
            for label in ("base", "head"):
                generate(tools[label], modules, sources, f"{directory}/{shape}/{label}-warm-up")
                code[label] = generated_code(modules, f"{directory}/{shape}/{label}-warm-up")
                sizes[label] = module_info_sizes(modules, f"{directory}/{shape}/{label}-warm-up")
        except Failure as failure:
            if label == "base":
                rows.append(f"| {shape} | did not generate | | | | | | not compared |")
                print(f"{shape}: the base tool did not generate it, so it is not compared: {failure}", flush=True)
                try:
                    generate(head_tool, modules, sources, f"{directory}/{shape}/head-alone")
                except Failure as head_failure:
                    failures.append(f"{shape}: the head tool did not generate it: {head_failure}")
            else:
                rows.append(f"| {shape} | | did not generate | | | | | **failed** |")
                failures.append(f"{shape}: the head tool did not generate it: {failure}")
            continue
        for (name, _, _), base_size, head_size in zip(modules, sizes["base"], sizes["head"]):
            size_ratio = head_size / base_size if base_size else float("inf") if head_size else 1.0
            size_over = size_ratio >= size_limit and head_size - base_size > SIZE_NOISE_FLOOR_BYTES
            if size_over:
                failures.append(f"{shape}: module {name}'s `.safedi` file is {size_ratio:.2f} times the base tool's ({head_size} bytes against {base_size}); the limit is {size_limit:g}")
            size_rows.append(f"| {shape} | {name} | {base_size} | {head_size} | {size_ratio:.2f} | {'**over the limit**' if size_over else 'within the limit'} |")
            print(f"{shape}: module {name}'s `.safedi` file, base {base_size} bytes, head {head_size} bytes, ratio {size_ratio:.2f}", flush=True)
        for run in range(runs):
            for label in ("base", "head"):
                samples[label].append(generate(tools[label], modules, sources, f"{directory}/{shape}/{label}-{run}"))
        median = {label: tuple(statistics.median(sample[index] for sample in values) for index in range(3)) for label, values in samples.items()}
        ratio = median["head"][0] / median["base"][0]
        over = ratio >= limit and median["head"][0] - median["base"][0] > NOISE_FLOOR_SECONDS
        if over:
            failures.append(f"{shape}: `generate` took {ratio:.2f} times as long as the base tool ({median['head'][0]:.3f} s against {median['base'][0]:.3f} s, median wall of {runs}); the limit is {limit:g}")
        memory_ratio = median["head"][2] / median["base"][2]
        memory_over = memory_ratio >= shape_memory_limit and median["head"][2] - median["base"][2] > MEMORY_NOISE_FLOOR_BYTES
        if memory_over:
            failures.append(f"{shape}: `generate` needed {memory_ratio:.2f} times the base tool's peak memory ({megabytes(median['head'][2])} against {megabytes(median['base'][2])}, median of {runs}); the limit is {shape_memory_limit:g}")
        figure = lambda label: f"{median[label][0]:.3f} s / {median[label][1]:.3f} s"
        verdict = " and ".join(name for name, failed in (("time", over), ("memory", memory_over)) if failed)
        rows.append(f"| {shape} | {figure('base')} | {figure('head')} | {ratio:.2f} | {megabytes(median['base'][2])} | {megabytes(median['head'][2])} | {memory_ratio:.2f} | {'identical' if code['base'] == code['head'] else 'differs'} | {f'**{verdict} over the limit**' if verdict else 'within the limits'} |")
        print(f"{shape}: base {figure('base')}, head {figure('head')} (wall / CPU), ratio {ratio:.2f}; peak memory base {megabytes(median['base'][2])}, head {megabytes(median['head'][2])}, ratio {memory_ratio:.2f}", flush=True)
    return rows, size_rows, failures


def megabytes(size):
    return f"{size / 1024 / 1024:.1f} MB"


def report(rows, size_rows, failures, runs, limit, memory_limit, size_limit, summary, large_memory_limit=1.1):
    lines = [f"`generate` time and peak memory, head against base: median of {runs} alternating runs; a shape fails at {limit:g} times the base's wall time or {memory_limit:g} times its peak memory ({min(memory_limit, large_memory_limit):g} times for {', '.join(sorted(LARGE_MEMORY_SHAPES))}).", "",
             "| Shape | Base wall / CPU | Head wall / CPU | Head / base (wall) | Base peak | Head peak | Head / base (peak) | Generated code | Verdict |",
             "|---|---|---|---|---|---|---|---|---|"] + rows
    lines += ["", f"`.safedi` size, head against base: a module fails at {size_limit:g} times the base's bytes.", "",
              "| Shape | Module | Base bytes | Head bytes | Head / base | Verdict |", "|---|---|---|---|---|---|"] + size_rows
    lines += [""] + [f"- {failure}" for failure in failures]
    text = "\n".join(lines) + "\n"
    print(text)
    if summary:
        with open(summary, "a") as handle:
            handle.write(text)
    for failure in failures:
        if os.environ.get("GITHUB_ACTIONS") == "true":
            print(f"::error::{failure.splitlines()[0]}")


# MARK: Self-test


STAND_IN = """#!/usr/bin/env python3
import sys, time
arguments = sys.argv[1:]
option = lambda name: arguments[arguments.index(name) + 1]
if {refuses!r} and option("--module-name") == "App":
    sys.exit("stand-in: refused")
# Touched page by page, so that the memory is resident.
held = bytearray({allocates!r})
for index in range(0, len(held), 4096):
    held[index] = 1
time.sleep({sleep!r})
open(option("--combined-output"), "w").write("// generated\\n")
open(option("--module-info-output"), "w").write("x" * {module_info_size!r})
"""


def self_test(directory):
    failures = []

    def tool(name, sleep, refuses=False, allocates=0, module_info_size=10000):
        path = f"{directory}/tools/{name}"
        write(path, STAND_IN.format(sleep=sleep, refuses=refuses, allocates=allocates, module_info_size=module_info_size))
        os.chmod(path, 0o755)
        return path

    def expect(name, base, head, expected_failures, expected_row, expected_size_row=None, memory_limit=1.3, large_memory_shapes=frozenset()):
        rows, size_rows, found = compare(base, head, f"{directory}/{name}", ["E16-seam"], 3, 2.0, memory_limit, 2.0, large_memory_shapes=large_memory_shapes)
        if len(found) != expected_failures or expected_row not in rows[0] or (expected_size_row and expected_size_row not in size_rows[0]):
            failures.append(f"{name}: expected {expected_failures} failure(s), a row with {expected_row!r} and a size row with {expected_size_row!r}, got {found}, {rows} and {size_rows}")

    fast = tool("fast", 0.0)
    expect("same", fast, fast, 0, "within the limits")
    # Each of the shape's two modules sleeps, so the head is 0.4 s behind: over twice the base and over the floor.
    expect("slower", fast, tool("slower", 0.2), 1, "**time over the limit**")
    # Twice a time below the floor is the processes starting, not a slower generator.
    expect("under-the-floor", fast, tool("slightly-slower", 0.03), 0, "within the limits")
    expect("faster", tool("slow", 0.2), fast, 0, "within the limits")
    # A stand-in's own peak is about 15 MB: another 64 MB is several times that, and far over the floor.
    expect("more-memory", fast, tool("more-memory", 0.0, allocates=64 * 1024 * 1024), 1, "**memory over the limit**")
    # Against a limit of 1.1: 24 MB more (a peak about 20 MB higher, measured) is over the floor of 8 MB, and 6 MB more
    # (about 3 MB higher) is not.
    expect("memory-over-the-floor", fast, tool("more-than-the-floor", 0.0, allocates=24 * 1024 * 1024), 1, "**memory over the limit**", memory_limit=1.1)
    expect("memory-under-the-floor", fast, tool("less-than-the-floor", 0.0, allocates=6 * 1024 * 1024), 0, "within the limits", memory_limit=1.1)
    expect("less-memory", tool("much-memory", 0.0, allocates=64 * 1024 * 1024), fast, 0, "within the limits")
    # 16 MB more than a base that holds 64 MB is about 1.2 times its peak: within 1.3, and over the 1.1 a large shape
    # is held to. The same stand-ins pass as an ordinary shape and fail as a large one.
    held = tool("holds-memory", 0.0, allocates=64 * 1024 * 1024)
    holds_more = tool("holds-a-fifth-more", 0.0, allocates=80 * 1024 * 1024)
    expect("a-fifth-more-memory", held, holds_more, 0, "within the limits")
    expect("a-fifth-more-memory-of-a-large-shape", held, holds_more, 1, "**memory over the limit**", large_memory_shapes=frozenset(["E16-seam"]))
    expect("same-memory-of-a-large-shape", held, held, 0, "within the limits", large_memory_shapes=frozenset(["E16-seam"]))
    expect("slower-and-more-memory", fast, tool("slower-and-more-memory", 0.2, allocates=64 * 1024 * 1024), 2, "**time and memory over the limit**")
    expect("head-refuses", fast, tool("head-refuses", 0.0, refuses=True), 1, "**failed**")
    expect("base-refuses", tool("base-refuses", 0.0, refuses=True), fast, 0, "not compared")
    expect("both-refuse", tool("refuses", 0.0, refuses=True), tool("refuses-too", 0.0, refuses=True), 1, "not compared")
    # Each of the shape's two modules writes a file twice the base's and 10 KB larger: both over the limit.
    expect("larger-module-info", fast, tool("larger-module-info", 0.0, module_info_size=20000), 2, "within the limit", "**over the limit**")
    expect("smaller-module-info", fast, tool("smaller-module-info", 0.0, module_info_size=100), 0, "within the limit", "within the limit")
    # Twice the size but only 3 KB larger is under the floor.
    expect("module-info-under-the-floor", tool("small-module-info", 0.0, module_info_size=3000), tool("small-module-info-doubled", 0.0, module_info_size=6000), 0, "within the limit", "within the limit")
    if not LARGE_MEMORY_SHAPES <= set(SHAPES):
        failures.append(f"the large shapes name {sorted(LARGE_MEMORY_SHAPES - set(SHAPES))}, which are not shapes")
    if SHAPES["S12-mocks"]() != SHAPES["S12-mocks"]():
        failures.append("S12-mocks: two builds of the shape differ, so its seed does not decide it")
    for name, build in SHAPES.items():
        modules = build()
        seen = set()
        for module, dependencies, _ in modules:
            if not set(dependencies) <= seen:
                failures.append(f"{name}: module {module} is listed before a module it depends on")
            seen.add(module)
    for failure in failures:
        print(f"self-test failed: {failure}")
    print("self-test " + ("failed" if failures else "passed"))
    return 1 if failures else 0


def main(arguments):
    runs = 5
    limit = 2.0
    memory_limit = 1.3
    large_memory_limit = 1.1
    size_limit = 2.0
    shapes = list(SHAPES)
    summary = None
    positional = []
    self_testing = False
    while arguments:
        argument = arguments.pop(0)
        if argument == "--self-test":
            self_testing = True
        elif argument in ("--runs", "--limit", "--memory-limit", "--large-memory-limit", "--size-limit", "--shapes", "--summary") and arguments:
            value = arguments.pop(0)
            if argument == "--runs":
                runs = int(value)
            elif argument == "--limit":
                limit = float(value)
            elif argument == "--memory-limit":
                memory_limit = float(value)
            elif argument == "--large-memory-limit":
                large_memory_limit = float(value)
            elif argument == "--size-limit":
                size_limit = float(value)
            elif argument == "--shapes":
                shapes = value.split(",")
            else:
                summary = value
        else:
            positional.append(argument)
    unknown = [shape for shape in shapes if shape not in SHAPES]
    if len(positional) != (1 if self_testing else 3) or unknown or runs < 1:
        print(__doc__.split("\n\n")[0] + (f"\nunknown shape(s): {', '.join(unknown)}; the shapes are {', '.join(SHAPES)}" if unknown else ""), file=sys.stderr)
        return 2
    directory = os.path.abspath(positional[-1])
    if os.path.exists(directory):
        print(f"{directory} exists; the check writes a new directory", file=sys.stderr)
        return 2
    if self_testing:
        return self_test(directory)
    else:
        rows, size_rows, failures = compare(os.path.abspath(positional[0]), os.path.abspath(positional[1]), directory, shapes, runs, limit, memory_limit, size_limit, large_memory_limit)
        report(rows, size_rows, failures, runs, limit, memory_limit, size_limit, summary, large_memory_limit)
        return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
