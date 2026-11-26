#!/usr/bin/env python3
"""Usage: generate-time-check.py [--runs N] [--large-memory-runs N] [--limit RATIO] [--memory-limit RATIO]
                                [--large-memory-limit RATIO] [--size-limit RATIO] [--shapes NAME,…]
                                [--growth NAME,…] [--growth-runs N] [--growth-limit RATIO] [--summary FILE]
                                BASE_TOOL HEAD_TOOL DIRECTORY
       generate-time-check.py --self-test DIRECTORY

Compares how long two builds of `SafeDITool` take to `generate` synthetic dependency graphs, and exits 1 when
HEAD_TOOL takes RATIO (default 2) times as long as BASE_TOOL, or longer, on any of them, or needs MEMORY-LIMIT (default
1.3) times its peak memory, or, on the shapes whose peak is the largest, LARGE-MEMORY-LIMIT (default 1.1) times its
peak with one allocator arena.
"Check Generate Time on Linux"
in ci.yml runs it with main's tool as BASE_TOOL and the change's as HEAD_TOOL, so a change that makes generation several
times slower is seen before it lands, not when an adopter's build slows down.

It also compares the size of each module's `.safedi` file, which every build system that runs `generate` per module
stores, uploads to its cache and reads back for each module above it, and exits 1 when a module's file from HEAD_TOOL
is RATIO (`--size-limit`, default 2) times the size of BASE_TOOL's, or larger, and also more than 4 KB larger, since a
few bytes more of a small file are not what the check is for. Storing seam signatures in the module info once made
E24-fill's `Feature.safedi` 400 times the size it had been, and no check saw it. A module listed with an accepted size
(`ACCEPTED_MODULE_INFO_BYTES`) passes while HEAD_TOOL's file is at most that many bytes, whatever the ratio.

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
  H1200-seam           twelve hundred seams in module `Feature`, seam i instantiating leaf i and `any Api`, which
                       only `DefaultApi` in module `App` fulfills, so each seam has a hole and the root in `App`,
                       which instantiates every seam, fills twelve hundred of them.
  M80x80-calling-mocks eighty protocols in module `Base`; `F` in module `Feat`, `generateMock: .public`, instantiating
                       one value of each, none of which its module fulfills; and in module `App` an implementation
                       of each protocol and eighty types with `generateMock: true` that each instantiate `F`, so
                       each of the eighty mocks calls the public mock of `F` and fills eighty hole types. At thirty
                       of each a run took 0.16 s, too near the 0.1 s a shape must lose before it can fail.

The four shapes below are the ones whose peak memory is the largest, each one module with no seam, as a project that
has not adopted seams writes its graph. They are also held to the tighter memory limit (see "Peak memory"):
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

Peak memory is each `generate` process's maximum resident set size, which the operating system reports for a child
when it exits (`getrusage` through `os.wait4`). That figure starts at the resident size of the process the child was
started from, so the tool is started from a small launcher (`LAUNCHER`, a fresh Python of about 10 MB) that waits for
it and writes what it used, never from this process, whose own size would otherwise be every small run's peak. A
shape's figure is the largest of its modules', and the figure compared
is its median over the timed runs. Its limit is tighter than time's: a shape fails when the
head's median peak is MEMORY-LIMIT times the base's or more, and also more than 8 MB above it, because below that the
peak is the process's own start, not the generator's work.

The four large shapes are also held to LARGE-MEMORY-LIMIT, with the same 8 MB, on another figure: they are where a
build's memory is decided, and each once peaked at 1.5 to 4.5 times what it needs now, so a tenth more on one of
them is a tenth more on the largest module of a project shaped like it. The timed runs' peaks cannot carry a limit
of a tenth. glibc gives each thread that allocates an arena of its own when another thread holds the one it tried,
and how many arenas a run ends with, and what each keeps, differs from run to run of one tool on one graph: 264
runs of one build of C1500-mock-chain on a four-core Linux machine peaked at one of two levels, 225 to 240 MB or 260
to 272 MB, about two in five at the lower. Medians of eleven of those runs were 0.90 to 1.12 times one another, and
of the 552 pairs of the 24 sets of eleven, 26 were a tenth apart: the check failed a change that used no more memory
(1.12 times), and the lowest peak of eleven did little better, a tenth apart in 16 of the 552. Running the tool on
one thread, and with address space layout randomization off, left both levels. With one arena
(`MALLOC_ARENA_MAX=1`), 22 runs of that build peaked between 214.7 and 217.9 MB, and eleven runs of each other large
shape within 1.3% of one another.

So the large shapes take LARGE-MEMORY-RUNS (default 5) more runs of each tool, alternating, with `MALLOC_ARENA_MAX=1`
in the tool's environment, and the figure held to LARGE-MEMORY-LIMIT is the median peak of those. They are runs of
their own because one arena makes the tool's threads wait on one another (E32-inline-mocks took 2.4 s where it takes
1.3 s), so their times are not compared. Their peaks are printed, lowest first, beside the median of the timed
runs, which is held to MEMORY-LIMIT as every shape's is. What this figure cannot see: a change that allocates no
more but leaves more unused in the arenas, as by allocating from more threads at once, is seen only at MEMORY-LIMIT.
The variable is glibc's, so on macOS these runs measure what the timed runs do. Where a large shape peaks under 80 MB,
a tenth of it is under the 8 MB, which then decides the shape: S16 peaked at 67 MB with one arena on that machine and
failed from about 1.12 times, and at 146.7 MB in CI's container, where the tenth decides. Why the two machines differ
on that shape is not known.

Growth: the comparison above holds a change to what main does, so it passes a shape that main already generates in
time that grows by a factor with each layer of the graph, and such a shape cannot be made large enough to matter
without taking minutes. The growth rows hold HEAD_TOOL alone to how its work grows. Each row is one shape built at a
number of layers and at two layers more, generated by HEAD_TOOL; the row fails when the larger graph takes
GROWTH-LIMIT (default 2) times the smaller one's wall time or more, or that many times its peak memory, its
`.safedi` bytes (summed over the modules) or its generated code's bytes, and is also over the measure's floor above
it (0.1 s, 8 MB, 4 KB). The two graphs differ by a third of the smaller one's layers or less, so work that grows with
the graph stays far under 2, and work that grows by a factor of 1.5 or more per layer is over it: no base build is
needed, and a busy machine slows both graphs alike. Time and peak memory are the medians of GROWTH-RUNS (default 3)
alternating runs after one untimed run of each graph. A run still going after 300 s is stopped and fails its row.
`--growth` picks among the rows (default all; `none` runs none, as `--shapes none` runs no comparison):
  P-seam-hole-at-every-screen  module `Feature`: a seam over layers of six screens, each holding `Instantiator`s of
                               three screens of the next layer, instantiating `any Tracker`, which only `LiveTracker`
                               in module `App` fulfills, and receiving `service`. Every screen is a place of the hole.
  L-label-declared-again       one module: layers of four screens, each holding `Instantiator`s of three screens of
                               the next layer and instantiating `model`, of a type of its own, and `viewModel`, which
                               receives it. Validation once kept one answer per path to a screen, since the label is
                               declared again beneath every screen with another type.
  K-mock-at-every-screen       one module: layers of four screens, each holding `Instantiator`s of three screens of
                               the next layer, every screen with `generateMock: true`.
  M-public-mock-layers         module `Feature`: layers of four screens, each holding `Instantiator`s of three screens
                               of the next layer and receiving `service`, the first a public mock
                               (`generateMock: .public`); module `App`: a root whose generated mock calls it.
  MH-public-mock-hole-at-every-screen
                               the same, with every screen also instantiating `any Tracker`, which only `LiveTracker`
                               in `App` fulfills, so every screen is a place of the mock's builder.
  Q-seam-own-module-paths      module `Feature`: layers of four screens, each receiving `service` and holding
                               `Instantiator`s of three screens of the next layer, every screen of the first layer a
                               seam, and no hole; module `App`: the root, which instantiates the first seam.
  B-cycles-through-instantiators
                               module `Feature`: layers of three screens, each holding `Instantiator`s of the three
                               screens of the next layer and of the screen at its own position in the layer before,
                               the last layer's of a first-layer screen instead, so the graph is cycles through
                               `Instantiator`s; module `App`: the root, which builds the tree.
  W-ring-of-screens-that-open-each-other
                               one module: two layers of screens, the row's number the screens per layer, each
                               first-layer screen holding `Instantiator`s of three second-layer screens and each
                               second-layer screen one of the next first-layer screen, so the screens form one ring
                               of cycles through `Instantiator`s that grows with the width, not the depth.
  BM-mocks-of-cycles-through-instantiators
                               the same graph with `generateMock: true` on every screen and on the root.
  F9-public-mock-seam-chain
                               a chain of modules, the row's number its length, each declaring three seams with
                               public mocks that instantiate `any Api`, which only module `App` fulfills, and every
                               seam of the next module both as itself and as an `Instantiator`; module `App`: the
                               mocked root, which builds the first seam.
  H-seam-holes-in-cycles       module `Feature`: layers of two screens, each instantiating `any Tracker`, which only
                               module `App` fulfills, and holding `Instantiator`s of the next layer's screens and of
                               a screen of the layer before, the last layer's of a first-layer screen instead; every
                               first-layer screen is a seam, so the seams' own trees hold cycles.
  O-only-if-available-at-every-screen, R-received-instantiator-at-every-screen, N-rename-at-every-screen
                               one module (`shape_census`): layers of three screens, each holding `Instantiator`s of
                               every screen of the next layer and receiving `service`, with, at every screen, an
                               `@Instantiated(onlyIfAvailable: true)` that nothing fulfills (O), a receive of the
                               `Instantiator` declared two layers up (R), or a rename of `service` (N).
  V-renames-in-alternate-layers, VO-only-if-available-renames-in-alternate-layers
                               one module: layers of four screens, each holding `Instantiator`s of three screens of
                               the next layer and receiving `service`; every screen of an odd layer renames `service`
                               and every screen of an even layer below the first receives the rename (V: a required
                               rename read only if available; VO: an only-if-available rename that is required).
  PR-parents-router            one module: layers of three screens, each holding `Instantiator`s of every screen of
                               the next layer, instantiating a `Router` under its layer's label and receiving the
                               one its parents declare.
A row whose growth is known and not yet removed carries limits of its own (`GROWTH_ROWS`), each what it measured with
room for noise, which the change that removes the growth deletes. Add a row with each change that removes growth of
this kind, for the shape it fixed.

A shape the base tool cannot generate (a new attribute, say) is reported and not compared. A shape the head tool cannot
generate fails the check: the shapes are valid SafeDI, so either the change broke them or they need updating with it.

Exit status: 0 no shape, module or growth row at or over a limit; 1 one is, or the head tool failed on one; 2 usage,
or DIRECTORY exists.

--self-test DIRECTORY runs the comparison and the growth rows with stand-in tools (which sleep, hold memory and write
files that grow with the types a module declares) and checks each verdict above.
"""
import hashlib
import os
import random
import signal
import statistics
import subprocess
import sys
import threading
import time

NOISE_FLOOR_SECONDS = 0.1
MEMORY_NOISE_FLOOR_BYTES = 8 * 1024 * 1024
# `ru_maxrss` is in kilobytes on Linux and in bytes on macOS.
MAXRSS_BYTES = 1 if sys.platform == "darwin" else 1024

# Starts the command after its first argument, waits for it, writes its user seconds, system seconds and maximum
# resident set size to the file its first argument names, and exits as the command did. It runs in a Python of its
# own, so the command's peak memory starts at this small process's, not at the check's.
LAUNCHER = """import os, sys
process = os.posix_spawn(sys.argv[2], sys.argv[2:], os.environ)
_, status, usage = os.wait4(process, 0)
with open(sys.argv[1], "w") as handle:
    handle.write(f"{usage.ru_utime} {usage.ru_stime} {usage.ru_maxrss}")
code = os.waitstatus_to_exitcode(status)
sys.exit(code if code >= 0 else 128 - code)
"""
SIZE_NOISE_FLOOR_BYTES = 4096
# Sizes accepted for one change, by shape and module: a listed module passes while the head's file is at most this many
# bytes, whatever its ratio to the base's. Above it, and for every other module, the ratio limit holds.
#
# M80x80-calling-mocks: the module info now stores each public mock's plan, which lists, for each of its builders, the
# builder's siblings. Each list is written as a difference from an earlier one, so the file grows with the builders,
# but a plan of 80 builders is still several times the size of a base file that stores no plan. Once the change that
# stores the plans is on main, main's own tool is the base and writes files of this size, so the entry is
# unnecessary: remove it then.
ACCEPTED_MODULE_INFO_BYTES = {"M80x80-calling-mocks": {"Feat": 36_000, "App": 48_000}}


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


def shape_h(count):
    feature = "import SafeDI\n\npublic protocol Api {}\n\n"
    for seam in range(count):
        feature += declaration("@Instantiable", f"Leaf{seam}", [])
        feature += declaration("@Instantiable(generateDependencyTree: true)", f"Seam{seam}", [("@Instantiated", "leaf", f"Leaf{seam}"), ("@Instantiated", "api", "any Api")])
    app = declaration("@Instantiable(fulfillingAdditionalTypes: [Api.self])", "DefaultApi", [], conformances="Api, Instantiable")
    app += declaration("@Instantiable(isRoot: true)", "Root", [("@Instantiated", f"seam{seam}", f"Seam{seam}") for seam in range(count)])
    return [("Feature", [], feature), ("App", ["Feature"], "import Feature\nimport SafeDI\n\n" + app)]


def shape_m(hole_types, mocks):
    """`mocks` mocks in `App` that each call the public mock of `F` in `Feat` and fill its `hole_types` hole types."""
    base = "import SafeDI\n\n" + "".join(f"public protocol Api{hole}: Sendable {{ func value() -> Int }}\n" for hole in range(hole_types))
    properties = [(f"api{hole}", f"any Api{hole}") for hole in range(hole_types)]
    lines = ["@Instantiable(generateMock: .public)", "public struct F: Instantiable {", "\tinit(" + ", ".join(f"{label}: {type_}" for label, type_ in properties) + ") {"]
    lines += [f"\t\tself.{label} = {label}" for label, _ in properties]
    lines += ["\t}", ""]
    lines += [f"\t@Instantiated let {label}: {type_}" for label, type_ in properties]
    lines += ["", "\tpublic func total() -> Int { " + " + ".join(f"{label}.value()" for label, _ in properties) + " }", "}", ""]
    feat = "import Base\nimport SafeDI\n\n" + "\n".join(lines)
    lines = []
    for hole in range(hole_types):
        lines += [f"@Instantiable(fulfillingAdditionalTypes: [(any Api{hole}).self])", f"public struct Live{hole}: Api{hole}, Instantiable {{", "\tpublic init() {}", f"\tpublic func value() -> Int {{ {hole + 1} }}", "}", ""]
    for mock in range(mocks):
        lines += ["@Instantiable(generateMock: true)", f"public struct Root{mock}: Instantiable {{", "\tpublic init(f: F) { self.f = f }", "", "\t@Instantiated let f: F", "\tpublic func total() -> Int { f.total() }", "}", ""]
    app = "import Base\nimport Feat\nimport SafeDI\n\n" + "\n".join(lines)
    return [("Base", [], base), ("Feat", ["Base"], feat), ("App", ["Base", "Feat"], app)]


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


def shape_p(layers, width=6):
    """Module `Feature`: a seam over `layers` layers of `width` screens, each holding `Instantiator`s of three screens
    of the next layer, instantiating `any Tracker`, which no type of the module fulfills, and receiving `service`.
    Module `App`: the root and the only `Tracker`. Every screen is a place of the hole, and 3^(layers - 1) paths
    reach the last layer."""
    feature = "import SafeDI\n\npublic protocol Tracker: AnyObject {}\n\n" + declaration("@Instantiable", "Service", [])
    for layer in range(layers):
        for position in range(width):
            children = [f"Screen{layer + 1}x{(position + offset) % width}" for offset in range(3)] if layer + 1 < layers else []
            properties = [("@Instantiated", "tracker", "any Tracker"), ("@Received", "service", "Service")]
            properties += [("@Instantiated", f"screen{child[6:]}Builder", f"Instantiator<{child}>") for child in children]
            attribute = "@Instantiable(generateDependencyTree: true)" if (layer, position) == (0, 0) else "@Instantiable"
            feature += declaration(attribute, f"Screen{layer}x{position}", properties)
    app = declaration("@Instantiable(fulfillingAdditionalTypes: [(any Tracker).self])", "LiveTracker", [("@Received", "service", "Service")], conformances="Instantiable, Tracker")
    app += declaration("@Instantiable(isRoot: true)", "Root", [("@Instantiated", "service", "Service"), ("@Instantiated", "home", "Screen0x0")])
    return [("Feature", [], feature), ("App", ["Feature"], "import Feature\nimport SafeDI\n\n" + app)]


def shape_l(layers, width=4):
    """One module: a root over `layers` layers of `width` screens, each holding `Instantiator`s of three screens of
    the next layer. Every screen instantiates `model`, of a type of its own, and `viewModel`, which receives it: one
    label, declared again beneath every screen with another type."""
    source = "import SafeDI\n\n"
    for layer in range(layers):
        for position in range(width):
            name = f"{layer}x{position}"
            children = [f"{layer + 1}x{(position + offset) % width}" for offset in range(3)] if layer + 1 < layers else []
            properties = [("@Instantiated", "model", f"Model{name}"), ("@Instantiated", "viewModel", f"ViewModel{name}")]
            properties += [("@Instantiated", f"screen{child}Builder", f"Instantiator<Screen{child}>") for child in children]
            source += declaration("@Instantiable", f"Screen{name}", properties)
            source += declaration("@Instantiable", f"Model{name}", [])
            source += declaration("@Instantiable", f"ViewModel{name}", [("@Received", "model", f"Model{name}")])
    source += declaration("@Instantiable(isRoot: true)", "Root", [("@Instantiated", "home", "Screen0x0")])
    return [("App", [], source)]


def shape_k(layers, width=4):
    """One module: `layers` layers of `width` screens, each holding `Instantiator`s of three screens of the next
    layer, every screen with a generated internal mock. 3^(layers - 1) paths reach the last layer from a first-layer
    screen's mock, while the mock's laid-out body has a function per screen type."""
    source = "import SafeDI\n\n"
    for layer in range(layers):
        for position in range(width):
            children = [f"{layer + 1}x{(position + offset) % width}" for offset in range(3)] if layer + 1 < layers else []
            properties = [("@Instantiated", f"screen{child}Builder", f"Instantiator<Screen{child}>") for child in children]
            source += declaration("@Instantiable(generateMock: true)", f"Screen{layer}x{position}", properties)
    return [("Feature", [], source)]


def shape_public_mock_layers(layers, hole, width=4):
    """Module `Feature`: a public mock over `layers` layers of `width` screens, each holding `Instantiator`s of three
    screens of the next layer and receiving `service`; with `hole`, every screen also instantiates `any Tracker`, which
    only `LiveTracker` in module `App` fulfills, so every screen is a place of the mock's builder. Module `App`: the
    root, whose generated mock calls the public mock. 3^(layers - 1) paths reach the last layer."""
    feature = "import SafeDI\n\npublic protocol Tracker: AnyObject {}\n\n" + declaration("@Instantiable", "Service", [])
    for layer in range(layers):
        for position in range(width):
            children = [f"Screen{layer + 1}x{(position + offset) % width}" for offset in range(3)] if layer + 1 < layers else []
            properties = [("@Instantiated", "tracker", "any Tracker")] if hole else []
            properties += [("@Received", "service", "Service")]
            properties += [("@Instantiated", f"screen{child[6:]}Builder", f"Instantiator<{child}>") for child in children]
            attribute = "@Instantiable(generateMock: .public)" if (layer, position) == (0, 0) else "@Instantiable"
            feature += declaration(attribute, f"Screen{layer}x{position}", properties)
    app = ""
    if hole:
        app += declaration("@Instantiable(fulfillingAdditionalTypes: [(any Tracker).self])", "LiveTracker", [("@Received", "service", "Service")], conformances="Instantiable, Tracker")
    app += declaration("@Instantiable(isRoot: true, generateMock: true)", "Root", [("@Instantiated", "service", "Service"), ("@Instantiated", "home", "Screen0x0")])
    return [("Feature", [], feature), ("App", ["Feature"], "import Feature\nimport SafeDI\n\n" + app)]


def shape_public_mock_seam_chain(depth, fan=3):
    """Modules `M{depth-1}` up to `M0`, then `App`, each depending on every module beneath it. Each module declares
    `fan` seams with public mocks, `F{k}_{j}`, each receiving `service`, instantiating `any Api` (which only `LiveApi`
    in `App` fulfills) and, below the last module, every seam of the next module both as itself and as an
    `Instantiator`. `App`'s mocked root builds `F0_0`. Without the public mocks every module generates in time linear
    in the chain; with them each module up the chain multiplies its generate time, memory and `.safedi` by about
    seven (the red team's F9)."""
    modules = []
    names = [f"M{k}" for k in range(depth)]
    for k in reversed(range(depth)):
        dependencies = names[k + 1:]
        source = "import SafeDI\n" + "".join(f"import {dependency}\n" for dependency in dependencies) + "\n"
        if k == depth - 1:
            source += "public protocol Api: AnyObject {}\n\n" + declaration("@Instantiable", "Service", [])
        for j in range(fan):
            properties = [("@Received", "service", "Service"), ("@Instantiated", "api", "any Api")]
            if k + 1 < depth:
                for child in range(fan):
                    properties.append(("@Instantiated", f"f{k + 1}_{child}", f"F{k + 1}_{child}"))
                    properties.append(("@Instantiated", f"f{k + 1}_{child}Builder", f"Instantiator<F{k + 1}_{child}>"))
            source += declaration("@Instantiable(generateDependencyTree: true, generateMock: .public)", f"F{k}_{j}", properties)
        modules.append((names[k], dependencies, source))
    app = "import SafeDI\n" + "".join(f"import {name}\n" for name in names) + "\n"
    app += declaration("@Instantiable(fulfillingAdditionalTypes: [(any Api).self])", "LiveApi", [("@Received", "service", "Service")], conformances="Instantiable, Api")
    app += declaration("@Instantiable(isRoot: true, generateMock: true)", "Root", [("@Instantiated", "service", "Service"), ("@Instantiated", "f", "F0_0")])
    modules.append(("App", names, app))
    return modules


def shape_q(layers, width=4, received=True):
    """Module `Feature`: `layers` layers of `width` screens, each holding `Instantiator`s of three screens of the next
    layer; every screen of the first layer is a seam, and, with `received`, every screen receives `service`. No hole:
    every type the tree instantiates is declared in `Feature`. Module `App`: the root, which instantiates `service` and
    the first seam. 3^(layers - 1) paths reach the last layer from each seam (red-team finding F5)."""
    feature = "import SafeDI\n\n" + declaration("@Instantiable", "Service", [])
    for layer in range(layers):
        for position in range(width):
            children = [f"Screen{layer + 1}x{(position + offset) % width}" for offset in range(3)] if layer + 1 < layers else []
            properties = [("@Received", "service", "Service")] if received else []
            properties += [("@Instantiated", f"screen{child[6:]}Builder", f"Instantiator<{child}>") for child in children]
            attribute = "@Instantiable(generateDependencyTree: true)" if layer == 0 else "@Instantiable"
            feature += declaration(attribute, f"Screen{layer}x{position}", properties)
    root = [("@Instantiated", "service", "Service")] if received else []
    root += [("@Instantiated", "home", "Screen0x0")]
    app = declaration("@Instantiable(isRoot: true)", "Root", root)
    return [("Feature", [], feature), ("App", ["Feature"], "import Feature\nimport SafeDI\n\n" + app)]


def shape_b(layers, mocks, width=3):
    """Module `Feature`: `layers` layers of `width` screens, each holding `Instantiator`s of three screens of the next
    layer and, past the first layer, of the screen at its own position in the layer before; a screen of the last
    layer holds one of a first-layer screen instead, so the graph is cycles through `Instantiator`s. With `mocks`,
    every screen has `generateMock: true`. Module `App`: the root, which builds the tree, with a generated mock when
    `mocks`."""
    feature = "import SafeDI\n\n" + declaration("@Instantiable", "Service", [])
    for layer in range(layers):
        for position in range(width):
            children = [f"{layer + 1}x{(position + offset) % width}" for offset in range(3)] if layer + 1 < layers else []
            if layer > 0:
                children.append(f"0x{(position + 1) % width}" if layer == layers - 1 else f"{layer - 1}x{position}")
            properties = [("@Instantiated", f"screen{child}Builder", f"Instantiator<Screen{child}>") for child in dict.fromkeys(children)]
            feature += declaration("@Instantiable(generateMock: true)" if mocks else "@Instantiable", f"Screen{layer}x{position}", properties)
    root = declaration("@Instantiable(isRoot: true, generateMock: true)" if mocks else "@Instantiable(isRoot: true)", "Root", [("@Instantiated", "service", "Service"), ("@Instantiated", "home", "Screen0x0")])
    return [("Feature", [], feature), ("App", ["Feature"], "import Feature\nimport SafeDI\n\n" + root)]


def shape_seam_holes_in_cycles(layers, width=2):
    """Module `Feature`: `layers` layers of `width` screens, each instantiating `any Tracker`, which no type of the
    module fulfills, receiving `service`, and holding `Instantiator`s of three screens of the next layer (fewer where
    the layer has fewer) and, past the first layer, of the screen at its own position in the layer before; a screen of
    the last layer holds one of a first-layer screen instead. Every first-layer screen is a seam, so the seams reach
    one another and their own trees hold cycles. Module `App`: the root and the only `Tracker`."""
    feature = "import SafeDI\n\npublic protocol Tracker: AnyObject {}\n\n" + declaration("@Instantiable", "Service", [])
    for layer in range(layers):
        for position in range(width):
            children = [f"{layer + 1}x{(position + offset) % width}" for offset in range(3)] if layer + 1 < layers else []
            if layer > 0:
                children.append(f"0x{(position + 1) % width}" if layer == layers - 1 else f"{layer - 1}x{position}")
            properties = [("@Instantiated", "tracker", "any Tracker"), ("@Received", "service", "Service")]
            properties += [("@Instantiated", f"screen{child}Builder", f"Instantiator<Screen{child}>") for child in dict.fromkeys(children)]
            attribute = "@Instantiable(generateDependencyTree: true)" if layer == 0 else "@Instantiable"
            feature += declaration(attribute, f"Screen{layer}x{position}", properties)
    app = declaration("@Instantiable(fulfillingAdditionalTypes: [(any Tracker).self])", "LiveTracker", [("@Received", "service", "Service")], conformances="Instantiable, Tracker")
    app += declaration("@Instantiable(isRoot: true)", "Root", [("@Instantiated", "service", "Service"), ("@Instantiated", "home", "Screen0x0")])
    return [("Feature", [], feature), ("App", ["Feature"], "import Feature\nimport SafeDI\n\n" + app)]


def shape_census(layers, variant, width=3):
    """The growth census's graph: `layers` layers of `width` screens, each holding `Instantiator`s of every screen of
    the next layer and receiving `service`, which the root instantiates, so width^(layers - 1) paths reach the last
    layer. `variant` adds one thing to every screen: "only-if-available", `@Instantiated(onlyIfAvailable: true) let
    tracker: (any Tracker)?`, which nothing fulfills; "received-instantiator", below the second layer, the
    `Instantiator` of the screen at its position two layers up, which that screen's parent declared; "rename",
    `@Received(fulfilledByDependencyNamed: "service", ofType: Service.self) let vendor: ServiceVendor`; "cycle", below
    the first layer, an `Instantiator` of the screen at its position one layer up; "seam", nothing, but the screens are
    in module `Feature` behind the seam `Entry`, which receives `service` and opens the first layer, and App's root
    opens `Entry`."""
    source = "public protocol ServiceVendor {}\npublic protocol Tracker {}\n\n" + declaration("@Instantiable", "Service", [], conformances="ServiceVendor, Instantiable")
    for layer in range(layers):
        for position in range(width):
            properties = [("@Received", "service", "Service")]
            if variant == "only-if-available":
                properties.append(("@Instantiated(onlyIfAvailable: true)", "tracker", "(any Tracker)?"))
            if variant == "received-instantiator" and layer > 1:
                properties.append(("@Received", f"screen{layer - 1}x{position}Builder", f"Instantiator<Screen{layer - 1}x{position}>"))
            if variant == "rename":
                properties.append(('@Received(fulfilledByDependencyNamed: "service", ofType: Service.self)', "vendor", "ServiceVendor"))
            if variant == "cycle" and layer > 0:
                properties.append(("@Instantiated", f"back{layer}", f"Instantiator<Screen{layer - 1}x{position}>"))
            if layer + 1 < layers:
                properties += [("@Instantiated", f"screen{layer + 1}x{child}Builder", f"Instantiator<Screen{layer + 1}x{child}>") for child in range(width)]
            source += declaration("@Instantiable", f"Screen{layer}x{position}", properties)
    first = [("@Instantiated", f"screen0x{child}Builder", f"Instantiator<Screen0x{child}>") for child in range(width)]
    if variant == "seam":
        source += declaration("@Instantiable(generateDependencyTree: true)", "Entry", [("@Received", "service", "Service")] + first)
        app = declaration("@Instantiable(isRoot: true)", "Root", [("@Instantiated", "service", "Service"), ("@Instantiated", "entryBuilder", "Instantiator<Entry>")])
        return [("Feature", [], "import SafeDI\n\n" + source), ("App", ["Feature"], "import Feature\nimport SafeDI\n\n" + app)]
    source += declaration("@Instantiable(isRoot: true)", "Root", [("@Instantiated", "service", "Service")] + first)
    return [("App", [], "import SafeDI\n\n" + source)]


def shape_alternating_renames(layers, only_if_available, width=4):
    """One module: a root over `layers` layers of `width` screens, each holding `Instantiator`s of three screens of the
    next layer and receiving `service`, which the root instantiates. Every screen of an odd layer renames `service` as
    `renamedService`; every screen of an even layer but the first receives `renamedService`. Without
    `only_if_available` the rename is required and the receive only if available; with it, the rename is only if
    available and the receive required. Validation once keyed a subtree by the whole path to the screen whose rename
    it reads."""
    if only_if_available:
        rename = ('@Received(fulfilledByDependencyNamed: "service", ofType: Service.self, onlyIfAvailable: true)', "renamedService", "Service?")
        read = ("@Received", "renamedService", "Service?")
    else:
        rename = ('@Received(fulfilledByDependencyNamed: "service", ofType: Service.self)', "renamedService", "Service")
        read = ("@Received(onlyIfAvailable: true)", "renamedService", "Service?")
    source = "import SafeDI\n\n" + declaration("@Instantiable", "Service", [])
    for layer in range(layers):
        for position in range(width):
            children = [f"{layer + 1}x{(position + offset) % width}" for offset in range(3)] if layer + 1 < layers else []
            properties = [("@Received", "service", "Service")]
            if layer % 2 == 1:
                properties.append(rename)
            elif layer > 0:
                properties.append(read)
            properties += [("@Instantiated", f"screen{child}Builder", f"Instantiator<Screen{child}>") for child in children]
            source += declaration("@Instantiable", f"Screen{layer}x{position}", properties)
    source += declaration("@Instantiable(isRoot: true)", "Root", [("@Instantiated", "service", "Service"), ("@Instantiated", "home", "Screen0x0")])
    return [("App", [], source)]


def shape_parent_router(layers, width=3):
    """One module: a root over `layers` layers of `width` screens, each holding `Instantiator`s of every screen of the
    next layer, instantiating a `Router` under its own layer's label and receiving the one the layer before declares,
    so each screen receives what every one of its parents declares."""
    source = "import SafeDI\n\n" + declaration("@Instantiable", "Router", [])
    for layer in range(layers):
        for position in range(width):
            properties = [("@Instantiated", f"router{layer}", "Router")]
            if layer > 0:
                properties.append(("@Received", f"router{layer - 1}", "Router"))
            if layer + 1 < layers:
                properties += [("@Instantiated", f"screen{layer + 1}x{child}Builder", f"Instantiator<Screen{layer + 1}x{child}>") for child in range(width)]
            source += declaration("@Instantiable", f"Screen{layer}x{position}", properties)
    source += declaration("@Instantiable(isRoot: true)", "Root", [("@Instantiated", f"screen0x{child}Builder", f"Instantiator<Screen0x{child}>") for child in range(width)])
    return [("App", [], source)]


def shape_w(width):
    """One module: a root over two layers of `width` screens, each first-layer screen holding `Instantiator`s of three
    second-layer screens, from its own position on, and each second-layer screen one of the first-layer screen after
    its own position. The screens form one ring of cycles through `Instantiator`s, whose paths without a repeated
    screen grow by a factor per screen added while the generated code holds one function per screen."""
    source = "import SafeDI\n\n"
    for layer in range(2):
        for position in range(width):
            children = [f"1x{(position + offset) % width}" for offset in range(3)] if layer == 0 else [f"0x{(position + 1) % width}"]
            properties = [("@Instantiated", f"screen{child}Builder", f"Instantiator<Screen{child}>") for child in dict.fromkeys(children)]
            source += declaration("@Instantiable", f"Screen{layer}x{position}", properties)
    source += declaration("@Instantiable(isRoot: true)", "Root", [("@Instantiated", "home", "Screen0x0")])
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
    "H1200-seam": lambda: shape_h(1200),
    "M80x80-calling-mocks": lambda: shape_m(80, 80),
    "S12-mocks": lambda: shape_s(12, seed=5, mocks=True),
    "S16": lambda: shape_s(16, seed=1, mocks=False),
    "E32-inline-mocks": lambda: shape_e(32, seam=False, variant="mocks"),
    "C1500-mock-chain": lambda: shape_c(1500),
}

# The shapes whose peak memory is held to `--large-memory-limit`.
LARGE_MEMORY_SHAPES = frozenset(["S12-mocks", "S16", "E32-inline-mocks", "C1500-mock-chain"])
# How many runs with one allocator arena those shapes take of each tool ("Peak memory" in the header says why).
LARGE_MEMORY_RUNS = 5
ONE_ARENA = {"MALLOC_ARENA_MAX": "1"}

# The growth rows ("Growth" in the header): name -> (the shape at a number of layers, the smaller number of layers,
# the limits that differ from `--growth-limit`, by measure: "time", "memory", "size" or "code"). A row with limits of
# its own is a shape whose growth is known and not yet removed: each is what the shape measured, with room for noise,
# so that the row holds what has been gained until the change that removes the growth deletes the entry.
#
# Measured on a four-core Linux machine with a release build of the tool, the smaller graph's figure first:
# P 0.376 s and 3.313 s (8.82), 50.7 MB and 213.5 MB (4.21), 341,899 and 3,966,895 bytes of `.safedi` (11.60);
# L 0.335 s and 2.553 s (7.63); K 0.069 s and 0.290 s (4.18), 972,037 and 9,574,045 bytes of code (9.85);
# M 0.122 s and 0.388 s (3.17), 428,063 and 3,552,741 bytes of code (8.30); MH 0.304 s and 2.562 s (8.43), 47.5 MB and
# 170.1 MB (3.58), 267,591 and 3,068,049 bytes of `.safedi` (11.47), 751,871 and 6,212,036 bytes of code (8.26);
# B 0.086 s and 1.576 s (18.37), 34.5 MB and 92.6 MB (2.68); BM 0.079 s and 2.543 s
# (32.30), 33.7 MB and 179.7 MB (5.34), 108,891 and 28,647,642 bytes of code (263.09); O 420,983 and 4,182,623 bytes of
# code (9.94); R 0.052 s and 0.216 s (4.16), 473,396 and 4,666,604 bytes of code (9.86).
# The tool alone, on the smallest graph, peaks at about 33 MB. K (36.6 MB and 67.4 MB, 1.84) and W (52.4 MB and
# 94.9 MB, 1.74 to 1.82 in five runs) stay under the default limit without room to spare.
GROWTH_ROWS = {
    "P-seam-hole-at-every-screen": (lambda layers: shape_p(layers), 6, {"time": 13.0, "memory": 5.5, "size": 12.5}),
    "L-label-declared-again": (lambda layers: shape_l(layers), 9, {"time": 11.0}),
    "K-mock-at-every-screen": (lambda layers: shape_k(layers), 6, {"time": 6.5, "code": 10.5}),
    "M-public-mock-layers": (lambda layers: shape_public_mock_layers(layers, hole=False), 6, {"time": 5.0, "code": 9.0}),
    "MH-public-mock-hole-at-every-screen": (lambda layers: shape_public_mock_layers(layers, hole=True), 6, {"time": 12.5, "memory": 5.5, "size": 12.5, "code": 9.0}),
    "Q-seam-own-module-paths": (lambda layers: shape_q(layers), 9, {}),
    # These two start at few layers because more take minutes today. Once a row's growth is removed, give it more
    # layers with its limits' removal: from two layers to four, work that grows with the graph doubles.
    "B-cycles-through-instantiators": (lambda layers: shape_b(layers, mocks=False), 3, {"time": 27.0, "memory": 3.6}),
    "W-ring-of-screens-that-open-each-other": (lambda width: shape_w(width), 10, {"time": 4.0}),
    "BM-mocks-of-cycles-through-instantiators": (lambda layers: shape_b(layers, mocks=True), 2, {"time": 48.0, "memory": 6.5, "code": 275.0}),
    # Three and five modules, not four and six: at six this row alone takes 21 s and 1.2 GB on main today (30 times
    # four's time). 0.26 s and 3.17 s (12.4), 38 MB and 196 MB (5.1), 122,250 and 4,137,809 bytes of `.safedi` (33.8),
    # 282,609 and 4,967,332 bytes of code (17.6).
    "F9-public-mock-seam-chain": (lambda layers: shape_public_mock_seam_chain(layers), 3, {"time": 16.0, "memory": 6.0, "size": 36.0, "code": 19.0}),
    # H 0.15 s and 2.1 s (13.7 and 14.5 in two runs), 35 MB and 74 MB (2.13), 25,811 and 1,406,899 bytes of `.safedi`
    # (54.5), 31,432 and 126,780 bytes of code (4.03). Starts at three layers: at six, Feature alone takes 9.8 s.
    "H-seam-holes-in-cycles": (lambda layers: shape_seam_holes_in_cycles(layers), 3, {"time": 22.0, "memory": 2.6, "size": 65.0, "code": 5.0}),
    "O-only-if-available-at-every-screen": (lambda layers: shape_census(layers, "only-if-available"), 6, {}),
    "R-received-instantiator-at-every-screen": (lambda layers: shape_census(layers, "received-instantiator"), 6, {"time": 6.0, "code": 10.5}),
    "N-rename-at-every-screen": (lambda layers: shape_census(layers, "rename"), 8, {}),
    # V 1.32 and VO 1.18 times over two more layers, while a subtree's key holds only the entries of a rename's declaring
    # path its walk reads; 2.47 and 3.26 while it holds the whole path.
    "V-renames-in-alternate-layers": (lambda layers: shape_alternating_renames(layers, only_if_available=False), 10, {}),
    "VO-only-if-available-renames-in-alternate-layers": (lambda layers: shape_alternating_renames(layers, only_if_available=True), 10, {}),
    # PR 0.33 s and 3.0 s (9.1), 48 MB and 175 MB (3.65); its code grows with the graph.
    "PR-parents-router": (lambda layers: shape_parent_router(layers), 8, {"time": 12.0, "memory": 4.5}),
}
GROWTH_STEP = 2
GROWTH_RUNS = 3
# A run of a row that is still going after this long is stopped and fails the row: growth by a factor per layer makes
# two layers more take many times as long, and the check must end.
GROWTH_TIME_LIMIT_SECONDS = 300


# MARK: Running a tool


class Failure(Exception):
    pass


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as handle:
        handle.write(text)


def generate(tool, modules, sources, output, variables={}, time_limit=None):
    """Runs `generate` for each module into `output`, with `variables` added to its environment; returns (wall
    seconds, CPU seconds, peak bytes): the times summed over the modules, the peak the largest of the modules'
    processes' maximum resident set sizes. A module's process still running after `time_limit` seconds is killed,
    which fails the run."""
    os.makedirs(output, exist_ok=True)
    environment = dict(os.environ, TMPDIR=output, **variables)
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
            # A session of its own, so that stopping it stops the launcher and the tool together.
            process = subprocess.Popen([sys.executable, "-I", "-S", "-c", LAUNCHER, f"{output}/{name}.usage"] + command,
                                       stdout=log, stderr=subprocess.STDOUT, env=environment, start_new_session=True)
            stopped = threading.Event()

            def stop():
                stopped.set()
                os.killpg(process.pid, signal.SIGKILL)

            timer = threading.Timer(time_limit, stop) if time_limit else None
            if timer:
                timer.start()
            process.wait()
            wall += time.monotonic() - started
            if timer:
                timer.cancel()
            if stopped.is_set():
                raise Failure(f"`generate` of module {name} was still running after {time_limit:g} s and was stopped")
        if process.returncode != 0:
            with open(f"{output}/{name}.log", errors="replace") as log:
                raise Failure(f"`generate` of module {name} exited {process.returncode}: {log.read().strip()[-1500:]}")
        with open(f"{output}/{name}.usage") as handle:
            user, system, maximum_resident_set_size = handle.read().split()
        cpu += float(user) + float(system)
        peak = max(peak, int(maximum_resident_set_size) * MAXRSS_BYTES)
    return wall, cpu, peak


def module_info_sizes(modules, output):
    return [os.path.getsize(f"{output}/{name}.safedi") for name, _, _ in modules]


def generated_code(modules, output):
    """Each module's generated code as (its length, a digest of it), with the output directory's path removed. Read
    a line at a time: a child process's peak memory starts at what this process holds when it starts the child, so a
    file held here whole would become the floor of every later measurement."""
    code = []
    for name, _, _ in modules:
        length = 0
        digest = hashlib.sha256()
        with open(f"{output}/{name}.generated.swift") as handle:
            for line in handle:
                line = line.replace(output, "")
                length += len(line)
                digest.update(line.encode())
        code.append((length, digest.hexdigest()))
    return code


# MARK: Comparing


def compare(base_tool, head_tool, directory, shapes, runs, limit, memory_limit, size_limit, large_memory_limit=1.1, large_memory_shapes=LARGE_MEMORY_SHAPES, large_memory_runs=LARGE_MEMORY_RUNS, accepted_sizes=ACCEPTED_MODULE_INFO_BYTES):
    """Returns (the time and memory table's rows, the size table's rows, the failures)."""
    rows = []
    size_rows = []
    failures = []
    for shape in shapes:
        modules = SHAPES[shape]()
        one_arena_runs = large_memory_runs if shape in large_memory_shapes else 0
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
                rows.append(f"| {shape} | | did not generate | | | | | | not compared |")
                print(f"{shape}: the base tool did not generate it, so it is not compared: {failure}", flush=True)
                try:
                    generate(head_tool, modules, sources, f"{directory}/{shape}/head-alone")
                except Failure as head_failure:
                    failures.append(f"{shape}: the head tool did not generate it: {head_failure}")
            else:
                rows.append(f"| {shape} | | | did not generate | | | | | **failed** |")
                failures.append(f"{shape}: the head tool did not generate it: {failure}")
            continue
        for (name, _, _), base_size, head_size in zip(modules, sizes["base"], sizes["head"]):
            size_ratio = head_size / base_size if base_size else float("inf") if head_size else 1.0
            accepted_size = accepted_sizes.get(shape, {}).get(name)
            size_accepted = accepted_size is not None and head_size <= accepted_size
            size_over = not size_accepted and size_ratio >= size_limit and head_size - base_size > SIZE_NOISE_FLOOR_BYTES
            if size_over:
                failures.append(f"{shape}: module {name}'s `.safedi` file is {size_ratio:.2f} times the base tool's ({head_size} bytes against {base_size}); the limit is {size_limit:g}")
            size_rows.append(f"| {shape} | {name} | {base_size} | {head_size} | {size_ratio:.2f} | {'**over the limit**' if size_over else f'within the accepted {accepted_size} bytes' if size_accepted else 'within the limit'} |")
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
        memory_over = memory_ratio >= memory_limit and median["head"][2] - median["base"][2] > MEMORY_NOISE_FLOOR_BYTES
        if memory_over:
            failures.append(f"{shape}: `generate` needed {memory_ratio:.2f} times the base tool's peak memory ({megabytes(median['head'][2])} against {megabytes(median['base'][2])}, median of {runs}); the limit is {memory_limit:g}")
        one_arena = ""
        if one_arena_runs:
            peaks = {"base": [], "head": []}
            for run in range(one_arena_runs):
                for label in ("base", "head"):
                    peaks[label].append(generate(tools[label], modules, sources, f"{directory}/{shape}/{label}-one-arena-{run}", ONE_ARENA)[2])
            base_peak, head_peak = statistics.median(peaks["base"]), statistics.median(peaks["head"])
            one_arena_ratio = head_peak / base_peak
            if one_arena_ratio >= min(memory_limit, large_memory_limit) and head_peak - base_peak > MEMORY_NOISE_FLOOR_BYTES:
                memory_over = True
                failures.append(f"{shape}: `generate` needed {one_arena_ratio:.2f} times the base tool's peak memory with one allocator arena ({megabytes(head_peak)} against {megabytes(base_peak)}, median of {one_arena_runs}); the limit is {min(memory_limit, large_memory_limit):g}")
            one_arena = f"; with one arena {megabytes(base_peak)} and {megabytes(head_peak)}, {one_arena_ratio:.2f}"
            for label in ("base", "head"):
                print(f"{shape}: {label}'s peak memory of each run with one arena, lowest first, in MB: {' '.join(f'{peak / 1024 / 1024:.1f}' for peak in sorted(peaks[label]))}", flush=True)
        figure = lambda label: f"{median[label][0]:.3f} s / {median[label][1]:.3f} s"
        verdict = " and ".join(name for name, failed in (("time", over), ("memory", memory_over)) if failed)
        rows.append(f"| {shape} | {runs}{f', and {one_arena_runs} with one arena' if one_arena_runs else ''} | {figure('base')} | {figure('head')} | {ratio:.2f} | {megabytes(median['base'][2])} | {megabytes(median['head'][2])} | {memory_ratio:.2f}{one_arena} | {'identical' if code['base'] == code['head'] else 'differs'} | {f'**{verdict} over the limit**' if verdict else 'within the limits'} |")
        print(f"{shape}: base {figure('base')}, head {figure('head')} (wall / CPU), ratio {ratio:.2f}; peak memory base {megabytes(median['base'][2])}, head {megabytes(median['head'][2])}, ratio {memory_ratio:.2f}{one_arena}", flush=True)
    return rows, size_rows, failures


def megabytes(size):
    return f"{size / 1024 / 1024:.1f} MB"


# MARK: Growth


def grow(head_tool, directory, growth_rows, runs, limit, time_limit=GROWTH_TIME_LIMIT_SECONDS):
    """Returns (the growth table's rows, the failures): each of `growth_rows` generated by `head_tool` at its layers
    and at `GROWTH_STEP` layers more."""
    rows = []
    failures = []
    for name, (build, layers, row_limits) in growth_rows.items():
        depths = (layers, layers + GROWTH_STEP)
        modules = {depth: build(depth) for depth in depths}
        samples = {depth: [] for depth in depths}
        sizes = {}
        code = {}
        try:
            for depth in depths:
                sources = f"{directory}/growth-{name}/{depth}/sources"
                for module, _, source in modules[depth]:
                    write(f"{sources}/{module}/Types.swift", source)
                generate(head_tool, modules[depth], sources, f"{directory}/growth-{name}/{depth}/warm-up", time_limit=time_limit)
                sizes[depth] = sum(module_info_sizes(modules[depth], f"{directory}/growth-{name}/{depth}/warm-up"))
                code[depth] = sum(length for length, _ in generated_code(modules[depth], f"{directory}/growth-{name}/{depth}/warm-up"))
            for run in range(runs):
                for depth in depths:
                    samples[depth].append(generate(head_tool, modules[depth], f"{directory}/growth-{name}/{depth}/sources", f"{directory}/growth-{name}/{depth}/{run}", time_limit=time_limit))
        except Failure as failure:
            rows.append(f"| {name} | {depths[0]} and {depths[1]} | did not generate | | | | **failed** |")
            failures.append(f"{name}: the head tool did not generate it at {depth} layers: {failure}")
            continue
        median = {depth: tuple(statistics.median(sample[index] for sample in values) for index in range(3)) for depth, values in samples.items()}
        # Each measure: (what the failure calls it, the figure at each depth, how to print one, the least difference that counts).
        measures = [
            ("time", "took {ratio:.2f} times as long as at {fewer} layers", {depth: median[depth][0] for depth in depths}, lambda value: f"{value:.3f} s", NOISE_FLOOR_SECONDS),
            ("memory", "needed {ratio:.2f} times the peak memory it needed at {fewer} layers", {depth: median[depth][2] for depth in depths}, megabytes, MEMORY_NOISE_FLOOR_BYTES),
            ("size", "wrote `.safedi` files {ratio:.2f} times the size of those at {fewer} layers", sizes, lambda value: f"{value} bytes", SIZE_NOISE_FLOOR_BYTES),
            ("code", "generated {ratio:.2f} times the code it generated at {fewer} layers", code, lambda value: f"{value} bytes", SIZE_NOISE_FLOOR_BYTES),
        ]
        cells = []
        over = []
        for measure, phrase, figures, printed, floor in measures:
            smaller, larger = figures[depths[0]], figures[depths[1]]
            ratio = larger / smaller if smaller else float("inf") if larger else 1.0
            measure_limit = row_limits.get(measure, limit)
            if ratio >= measure_limit and larger - smaller > floor:
                over.append(measure)
                failures.append(f"{name}: at {depths[1]} layers `generate` {phrase.format(ratio=ratio, fewer=depths[0])} ({printed(larger)} against {printed(smaller)}); the limit is {measure_limit:g}, and the graph has {depths[1] / depths[0]:.2f} times the layers")
            cells.append(f"{printed(smaller)}, {printed(larger)}, {ratio:.2f}" + (f" (limit {measure_limit:g})" if measure in row_limits else ""))
        rows.append(f"| {name} | {depths[0]} and {depths[1]} | {' | '.join(cells)} | {'**' + ' and '.join(over) + ' over the limit**' if over else 'within the limits'} |")
        print(f"{name}: at {depths[0]} and {depths[1]} layers, " + "; ".join(f"{measure} {cell}" for (measure, _, _, _, _), cell in zip(measures, cells)), flush=True)
    return rows, failures


def report(rows, size_rows, failures, runs, limit, memory_limit, size_limit, summary, large_memory_limit=1.1, large_memory_runs=LARGE_MEMORY_RUNS, growth_rows=[], growth_runs=GROWTH_RUNS, growth_limit=2.0):
    lines = [f"`generate` time and peak memory, head against base: median of {runs} alternating runs; a shape fails at {limit:g} times the base's wall time or {memory_limit:g} times its peak memory, and {', '.join(sorted(LARGE_MEMORY_SHAPES))} also at {min(memory_limit, large_memory_limit):g} times the base's median peak of {large_memory_runs} more runs with one allocator arena.", "",
             "| Shape | Runs | Base wall / CPU | Head wall / CPU | Head / base (wall) | Base peak | Head peak | Head / base (peak) | Generated code | Verdict |",
             "|---|---|---|---|---|---|---|---|---|---|"] + rows
    lines += ["", f"`.safedi` size, head against base: a module fails at {size_limit:g} times the base's bytes.", "",
              "| Shape | Module | Base bytes | Head bytes | Head / base | Verdict |", "|---|---|---|---|---|---|"] + size_rows
    if growth_rows:
        lines += ["", f"Growth, the head tool alone: each row at its layers and at {GROWTH_STEP} more; median of {growth_runs} alternating runs for time and peak memory. A measure fails at {growth_limit:g} times the smaller graph's, or at the limit beside it.", "",
                  "| Row | Layers | Wall: fewer layers, more, ratio | Peak memory | `.safedi` bytes | Generated code | Verdict |", "|---|---|---|---|---|---|---|"] + growth_rows
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
import os, sys, time
arguments = sys.argv[1:]
option = lambda name: arguments[arguments.index(name) + 1]
if {refuses!r} and option("--module-name") == "App":
    sys.exit("stand-in: refused")
# Touched page by page, so that the memory is resident.
# What a measure listed in `grows` is multiplied by: the number of types the module declares, to the listed power.
types = sum(open(path).read().count("final class ") for path in open(arguments[1]).read().split())
factor = lambda measure: types ** {grows!r}.get(measure, 0)
held = bytearray({allocates!r} * factor("memory") + (0 if os.environ.get("MALLOC_ARENA_MAX") == "1" else {allocates_without_one_arena!r}))
for index in range(0, len(held), 4096):
    held[index] = 1
time.sleep({sleep!r} * factor("time"))
open(option("--combined-output"), "w").write("// generated\\n" * factor("code"))
open(option("--module-info-output"), "w").write("x" * ({module_info_size!r} * factor("size")))
"""


def self_test(directory):
    failures = []

    def tool(name, sleep, refuses=False, allocates=0, module_info_size=10000, allocates_without_one_arena=0, grows={}):
        path = f"{directory}/tools/{name}"
        write(path, STAND_IN.format(sleep=sleep, refuses=refuses, allocates=allocates, module_info_size=module_info_size, allocates_without_one_arena=allocates_without_one_arena, grows=grows))
        os.chmod(path, 0o755)
        return path

    def expect(name, base, head, expected_failures, expected_row, expected_size_row=None, memory_limit=1.3, large_memory_shapes=frozenset(), large_memory_runs=3, accepted_sizes={}):
        rows, size_rows, found = compare(base, head, f"{directory}/{name}", ["E16-seam"], 3, 2.0, memory_limit, 2.0, large_memory_shapes=large_memory_shapes, large_memory_runs=large_memory_runs, accepted_sizes=accepted_sizes)
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
    # is held to with one arena. The same stand-ins pass as an ordinary shape and fail as a large one.
    held = tool("holds-memory", 0.0, allocates=64 * 1024 * 1024)
    holds_more = tool("holds-a-fifth-more", 0.0, allocates=80 * 1024 * 1024)
    expect("a-fifth-more-memory", held, holds_more, 0, "within the limits")
    expect("a-fifth-more-memory-of-a-large-shape", held, holds_more, 1, "**memory over the limit**", large_memory_shapes=frozenset(["E16-seam"]))
    expect("same-memory-of-a-large-shape", held, held, 0, "within the limits", large_memory_shapes=frozenset(["E16-seam"]))
    # The tighter limit reads the runs with one arena only: a fifth more in the timed runs alone, as when the arenas
    # hold more, is within 1.3 there and the same with one arena, and a fifth more with one arena alone fails.
    expect("a-fifth-more-without-one-arena-of-a-large-shape", held, tool("holds-a-fifth-more-in-arenas", 0.0, allocates=64 * 1024 * 1024, allocates_without_one_arena=16 * 1024 * 1024), 0, "within the limits", large_memory_shapes=frozenset(["E16-seam"]))
    expect("a-fifth-more-with-one-arena-of-a-large-shape", tool("holds-a-fifth-more-in-arenas-too", 0.0, allocates=64 * 1024 * 1024, allocates_without_one_arena=16 * 1024 * 1024), holds_more, 1, "**memory over the limit**", large_memory_shapes=frozenset(["E16-seam"]))
    # A large shape's row gives both counts of runs and both figures; an ordinary shape's has neither.
    expect("runs-of-a-large-shape", held, held, 0, "| E16-seam | 3, and 5 with one arena |", large_memory_shapes=frozenset(["E16-seam"]), large_memory_runs=5)
    expect("figures-of-a-large-shape", held, held, 0, "; with one arena ", large_memory_shapes=frozenset(["E16-seam"]))
    expect("runs-of-an-ordinary-shape", held, held, 0, "| E16-seam | 3 |", large_memory_runs=5)
    expect("slower-and-more-memory", fast, tool("slower-and-more-memory", 0.2, allocates=64 * 1024 * 1024), 2, "**time and memory over the limit**")
    expect("head-refuses", fast, tool("head-refuses", 0.0, refuses=True), 1, "**failed**")
    expect("base-refuses", tool("base-refuses", 0.0, refuses=True), fast, 0, "not compared")
    expect("both-refuse", tool("refuses", 0.0, refuses=True), tool("refuses-too", 0.0, refuses=True), 1, "not compared")
    # Each of the shape's two modules writes a file twice the base's and 10 KB larger: both over the limit.
    expect("larger-module-info", fast, tool("larger-module-info", 0.0, module_info_size=20000), 2, "within the limit", "**over the limit**")
    expect("smaller-module-info", fast, tool("smaller-module-info", 0.0, module_info_size=100), 0, "within the limit", "within the limit")
    # Twice the size but only 3 KB larger is under the floor.
    expect("module-info-under-the-floor", tool("small-module-info", 0.0, module_info_size=3000), tool("small-module-info-doubled", 0.0, module_info_size=6000), 0, "within the limit", "within the limit")
    # Both modules write a file three times the base's. `Feature` is listed with an accepted size: at most that size
    # it passes whatever the ratio, and over it the ratio limit fails it. `App` is not listed, and fails either way.
    tripled = tool("tripled-module-info", 0.0, module_info_size=30000)
    expect("module-info-within-its-accepted-size", fast, tripled, 1, "within the limits", "within the accepted 30000 bytes", accepted_sizes={"E16-seam": {"Feature": 30000}})
    expect("module-info-over-its-accepted-size", fast, tripled, 2, "within the limits", "**over the limit**", accepted_sizes={"E16-seam": {"Feature": 29999}})

    def expect_growth(name, head, expected_failures, expected_row, row_limits={}, time_limit=GROWTH_TIME_LIMIT_SECONDS):
        rows, found = grow(head, f"{directory}/{name}", {"P": (shape_p, 4, row_limits)}, 3, 2.0, time_limit=time_limit)
        if len(found) != expected_failures or expected_row not in rows[0]:
            failures.append(f"{name}: expected {expected_failures} failure(s) and a growth row with {expected_row!r}, got {found} and {rows}")

    # The row's `Feature` declares 25 types at 4 layers and 37 at 6, 1.48 times as many, and its `App` two at both.
    # What grows with the types is within the limit of 2, and what grows with their cube, 3.24 times, is over it.
    expect_growth("growth-none", fast, 0, "within the limits")
    expect_growth("growth-of-time-with-the-types", tool("linear-time", 0.005, grows={"time": 1}), 0, "within the limits")
    expect_growth("growth-of-time-with-their-cube", tool("cubic-time", 0.00001, grows={"time": 3}), 1, "**time over the limit**")
    expect_growth("growth-of-memory-with-the-types", tool("linear-memory", 0.0, allocates=1024 * 1024, grows={"memory": 1}), 0, "within the limits")
    expect_growth("growth-of-memory-with-their-cube", tool("cubic-memory", 0.0, allocates=2048, grows={"memory": 3}), 1, "**memory over the limit**")
    expect_growth("growth-of-size-with-the-types", tool("linear-size", 0.0, module_info_size=1000, grows={"size": 1}), 0, "within the limits")
    expect_growth("growth-of-size-with-their-cube", tool("cubic-size", 0.0, module_info_size=1, grows={"size": 3}), 1, "**size over the limit**")
    # Under the floor: files of 629 and 1,373 bytes are 2.18 times apart and 744 bytes apart, and the floor is 4 KB.
    expect_growth("growth-of-size-under-the-floor", tool("squared-size-under-the-floor", 0.0, module_info_size=1, grows={"size": 2}), 0, "629 bytes, 1373 bytes, 2.18")
    expect_growth("growth-of-code-with-the-types", tool("linear-code", 0.0, grows={"code": 1}), 0, "within the limits")
    expect_growth("growth-of-code-with-their-cube", tool("cubic-code", 0.0, grows={"code": 3}), 1, "**code over the limit**")
    expect_growth("growth-of-two-measures", tool("cubic-size-and-code", 0.0, module_info_size=1, grows={"size": 3, "code": 3}), 2, "**size and code over the limit**")
    # A row's own limit replaces the general one for its measure alone: 3.24 times passes under 4 and fails under 3,
    # and the other measure is still held to 2.
    expect_growth("growth-within-the-rows-limit", tool("cubic-size-known", 0.0, module_info_size=1, grows={"size": 3}), 0, "(limit 4)", row_limits={"size": 4.0})
    expect_growth("growth-over-the-rows-limit", tool("cubic-size-worse", 0.0, module_info_size=1, grows={"size": 3}), 1, "**size over the limit**", row_limits={"size": 3.0})
    expect_growth("growth-of-another-measure-than-the-rows-limit", tool("cubic-code-beside-a-size-limit", 0.0, grows={"code": 3}), 1, "**code over the limit**", row_limits={"size": 4.0})
    expect_growth("growth-refused", tool("growth-refuses", 0.0, refuses=True), 1, "**failed**")
    expect_growth("growth-never-ends", tool("never-ends", 30.0), 1, "**failed**", time_limit=1)
    for row, (build, layers, row_limits) in GROWTH_ROWS.items():
        if not set(row_limits) <= {"time", "memory", "size", "code"}:
            failures.append(f"growth row {row} limits {sorted(row_limits)}, which are not all measures")
        for module, dependencies, _ in build(layers):
            if not all(dependency in [earlier for earlier, _, _ in build(layers)] for dependency in dependencies):
                failures.append(f"growth row {row}: module {module} depends on a module the shape does not have")
        if sum(len(source) for _, _, source in build(layers + GROWTH_STEP)) <= sum(len(source) for _, _, source in build(layers)):
            failures.append(f"growth row {row}: the shape is no larger at {layers + GROWTH_STEP} layers than at {layers}")
    for shape, accepted in ACCEPTED_MODULE_INFO_BYTES.items():
        if shape not in SHAPES or not set(accepted) <= {name for name, _, _ in SHAPES[shape]()}:
            failures.append(f"the accepted sizes name {shape} {sorted(accepted)}, which are not a shape and its modules")
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
    # A measurement after a large generated file was read: the file must not have become this process's footprint,
    # which a child's peak memory starts at.
    footprint = f"{directory}/footprint"
    large = shape_e(4, seam=False)
    for name, _, _ in large:
        os.makedirs(f"{footprint}/output", exist_ok=True)
        with open(f"{footprint}/output/{name}.generated.swift", "w") as handle:
            for _ in range(4000):
                handle.write("// a line of generated code\n" * 1000)
    lengths = [length for length, _ in generated_code(large, f"{footprint}/output")]
    for name, _, source in large:
        write(f"{footprint}/sources/{name}/Types.swift", source)
    _, _, peak = generate(tool("footprint", sleep=0), large, f"{footprint}/sources", f"{footprint}/output")
    if lengths != [len("// a line of generated code\n") * 4_000_000] * len(large) or peak > 64 * 1024 * 1024:
        failures.append(f"reading {lengths} characters of generated code left a later run's peak at {megabytes(peak)}")
    # A child of a known size, measured while this process is several times larger: the peak is the child's own, a
    # stand-in that allocates 20 MB on top of its interpreter, not this process's size when it started the child.
    ballast = bytearray(b"x") * (256 * 1024 * 1024)
    _, _, peak = generate(tool("known-size", sleep=0, allocates=20 * 1024 * 1024), large, f"{footprint}/sources", f"{directory}/known-size")
    del ballast
    if not 20 * 1024 * 1024 <= peak <= 48 * 1024 * 1024:
        failures.append(f"a child that allocates 20 MB, started from a process holding 256 MB, measured {megabytes(peak)}")
    for failure in failures:
        print(f"self-test failed: {failure}")
    print("self-test " + ("failed" if failures else "passed"))
    return 1 if failures else 0


def main(arguments):
    runs = 5
    limit = 2.0
    memory_limit = 1.3
    large_memory_limit = 1.1
    large_memory_runs = LARGE_MEMORY_RUNS
    size_limit = 2.0
    shapes = list(SHAPES)
    growth = list(GROWTH_ROWS)
    growth_runs = GROWTH_RUNS
    growth_limit = 2.0
    summary = None
    positional = []
    self_testing = False
    while arguments:
        argument = arguments.pop(0)
        if argument == "--self-test":
            self_testing = True
        elif argument in ("--runs", "--large-memory-runs", "--limit", "--memory-limit", "--large-memory-limit", "--size-limit", "--shapes", "--growth", "--growth-runs", "--growth-limit", "--summary") and arguments:
            value = arguments.pop(0)
            if argument == "--runs":
                runs = int(value)
            elif argument == "--large-memory-runs":
                large_memory_runs = int(value)
            elif argument == "--limit":
                limit = float(value)
            elif argument == "--memory-limit":
                memory_limit = float(value)
            elif argument == "--large-memory-limit":
                large_memory_limit = float(value)
            elif argument == "--size-limit":
                size_limit = float(value)
            elif argument == "--shapes":
                shapes = [shape for shape in value.split(",") if shape != "none"]
            elif argument == "--growth":
                growth = [row for row in value.split(",") if row != "none"]
            elif argument == "--growth-runs":
                growth_runs = int(value)
            elif argument == "--growth-limit":
                growth_limit = float(value)
            else:
                summary = value
        else:
            positional.append(argument)
    unknown = [shape for shape in shapes if shape not in SHAPES]
    unknown_growth = [row for row in growth if row not in GROWTH_ROWS]
    if len(positional) != (1 if self_testing else 3) or unknown or unknown_growth or runs < 1 or growth_runs < 1:
        print(__doc__.split("\n\n")[0] + (f"\nunknown shape(s): {', '.join(unknown)}; the shapes are {', '.join(SHAPES)}" if unknown else "") + (f"\nunknown growth row(s): {', '.join(unknown_growth)}; the rows are {', '.join(GROWTH_ROWS)}" if unknown_growth else ""), file=sys.stderr)
        return 2
    directory = os.path.abspath(positional[-1])
    if os.path.exists(directory):
        print(f"{directory} exists; the check writes a new directory", file=sys.stderr)
        return 2
    if self_testing:
        return self_test(directory)
    else:
        rows, size_rows, failures = compare(os.path.abspath(positional[0]), os.path.abspath(positional[1]), directory, shapes, runs, limit, memory_limit, size_limit, large_memory_limit, large_memory_runs=large_memory_runs)
        growth_rows, growth_failures = grow(os.path.abspath(positional[1]), directory, {row: GROWTH_ROWS[row] for row in growth}, growth_runs, growth_limit)
        failures += growth_failures
        report(rows, size_rows, failures, runs, limit, memory_limit, size_limit, summary, large_memory_limit, large_memory_runs, growth_rows, growth_runs, growth_limit)
        return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
