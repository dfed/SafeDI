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

E24-public-mock is judged on the runs with one arena alone, at MEMORY-LIMIT. Its timed runs' peak moves by more than
the limit between runs of one tool on one machine: on one commit its base tool's median peak read 186.5 MB and, half
an hour later, 143.5 MB, and that difference failed a check of a change that had not touched memory, twice. Its timed
peak is still printed, and is not compared.

Growth: the comparison above holds a change to what main does, so it passes a shape that main already generates in
time that grows by a factor with each layer of the graph, and such a shape cannot be made large enough to matter
without taking minutes. The growth rows hold HEAD_TOOL alone to how its work grows. Each row is one shape built at a
number of layers and at two layers more, generated by HEAD_TOOL; the row fails when the larger graph takes
GROWTH-LIMIT (default 2) times the smaller one's wall time or more, or that many times its peak memory, its
`.safedi` bytes (summed over the modules) or its generated code's bytes, and is also over the measure's floor above
it (0.1 s, 8 MB, 4 KB). But for T, TS, TC and TW, whose larger graph is two or three times the smaller one and whose
limits are that multiple's, the two graphs differ by a third of the smaller one's layers or less, so work that grows
with the graph stays far under 2, and work that grows by a factor of 1.5 or more per layer is over it: no base build
is needed, and a busy machine slows both graphs alike. Time and peak memory are the medians of GROWTH-RUNS (default 3)
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
  WL-ring-of-screens-receiving-labels
                               one module: a root that instantiates 400 services, each under a label of its own, and
                               holds an `Instantiator` of the first of a ring of screens, fifty for each of the row's
                               number. Each screen receives two of the services, in turn, and holds an `Instantiator`
                               of the next screen, the last one's of the first, so every screen is a level deeper on
                               one cycle and looks its services up past every screen above it. Its larger graph is
                               twice its smaller one.
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
  PRS-seam-parents-router      the same screens under a seam `Home` of module `Feature`, whose tree its own module
                               lays out; module `App`: the root, which builds `Home`.
  T-leaves-reached-twice-at-depth
                               one module: a chain of screens, a hundred for each of the row's number, each holding
                               an `Instantiator` of the next screen and `Instantiator`s of ten leaves of its own and
                               of the ten of the screen before, so every leaf is reached twice, one screen apart.
                               Its larger graph is three times its smaller one, so its limits are that tripling's.
  TS-leaves-reached-from-two-screens
                               one module: a root that instantiates `First`, `Even`, `Odd` and `Third`. `First` and
                               `Third` each instantiate every leaf, eight hundred for each of the row's number, and
                               `Even` and `Odd` every other one, so each leaf is reached three times and what `Third`
                               finds remembered of its leaves alternates between two screens. Its larger graph is
                               twice its smaller one, so its limits are that doubling's.
  TC-leaves-reached-three-times-down-chain
                               one module: a chain of screens, 250 for each of the row's number, each
                               holding `Instantiator`s of a leaf of its own and of the leaves of the two screens
                               before, and then one of the next screen, so every leaf is reached three times, one
                               screen apart, before the walk goes deeper. Its larger graph is twice its smaller one,
                               so its limits are that doubling's.
  TW-components-on-two-wide-screens
                               one module: a root that instantiates 400 values and holds an `Instantiator` of each of
                               40 screens. Each screen instantiates its own components, 25 for each of the row's
                               number, and those of the screen before it, so every component is on two screens; each
                               component receives one of the root's values and instantiates a model of its own. Its
                               larger graph is twice its smaller one, so its limits are that doubling's.
  BL-back-links-to-feature-entries
                               one module: a root that holds an `Instantiator` of each of six features' entries. Each
                               entry instantiates a state of its feature's own type under one label, which its
                               feature's nine screens in three layers receive, and holds `Instantiator`s of the entry
                               of the feature before it and of the feature three before it. In as many features as
                               the row's number, the last screen holds an `Instantiator` of its feature's entry: a
                               link back.
  BL4-back-links-to-most-feature-entries
                               the same at four and six links, where the time left is tree building's, whose limit
                               the row records.
  BLO-back-links-with-state-only-if-available
                               the same at one and three links, with each screen receiving its feature's state only
                               if available, which validation still walks once for each path through the links: the
                               row records that growth.
  BLS-back-links-with-feature-labels-over-shared-tree
                               one module: a root over sixty features, each an entry and three screens, the last of
                               which holds an `Instantiator` of its entry, a link back, and one of a tree of 1,000
                               types every feature opens. Each entry instantiates 5 values, and at the larger size
                               25, under labels every feature declares with types of its own, which its screens
                               receive.
  LP-lifelike-chain-under-the-plugin
                               `shape_lifelike_chain`: module `Core`, a chain of feature modules, the row's number its
                               length, and module `App`. Each feature is a seam with a public mock that opens thirty
                               screens with generated mocks, in four layers, and the seam of the feature before it.
                               The last feature alone is generated, as the SwiftPM plugin generates it, in a chain of
                               five features and in a chain of ten.

As the SwiftPM plugin generates: every other row is generated per module with `.safedi` files, as the comparison's
shapes are. A Swift package's modules write none: the SafeDIGenerator plugin hands each module's `generate` the sources
of every module beneath it. A row that names a module is generated that way, the named module alone: the check writes
what the plugin writes (`InputSwiftFiles.csv`, which lists the module's file and the file of every module beneath it,
relative to the package, and the target graph beside it), runs the plugin's `scan`, which is not timed, and then times
the plugin's `generate` command, with `DEBUG` as the target's one condition (`createBuildCommands` in
`Plugins/SafeDIGenerator/SafeDIGenerateDependencyTree.swift` builds both commands). The row's `.safedi` bytes are 0,
and its code is every file of the module's output directory. Such a row names both its numbers of layers: one
module's `generate` is short, so two more layers of it differ by less than a busy machine does. This one's larger
chain has twice the features, so work that grows with the chain is at 2, and the row always carries limits: they are
not growth to remove, but what the feature on top may take when every feature beneath it is one more layer.

Any other row whose growth is known and not yet removed carries limits of its own (`GROWTH_ROWS`), each what it
measured with room for noise, which the change that removes the growth deletes. Add a row with each change that
removes growth of this kind, for the shape it fixed.

A shape the base tool cannot generate (a new attribute, say) is reported and not compared. A shape the head tool cannot
generate fails the check: the shapes are valid SafeDI, so either the change broke them or they need updating with it.

Exit status: 0 no shape, module or growth row at or over a limit; 1 one is, or the head tool failed on one; 2 usage,
or DIRECTORY exists.

--self-test DIRECTORY runs the comparison and the growth rows with stand-in tools (which sleep, hold memory and write
files that grow with the types a module declares) and checks each verdict above.
"""
import hashlib
import json
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
# bytes, whatever its ratio to the base's. Above it, and for every other module, the ratio limit holds. An entry is
# for the one change that grows a file on purpose: once that change is on main, main's own tool is the base and
# writes files of that size, so the entry is removed. None is needed now.
ACCEPTED_MODULE_INFO_BYTES = {}


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


# How often, in a hundred screens, a screen of `shape_lifelike_chain` has each trait.
LIFELIKE_TRAITS = {"forwarded": 33, "sendable-worker": 25, "lazy": 30, "default-valued": 30, "optional": 15, "erased": 10, "hand-written": 40}


def lifelike_declaration(attribute, name, properties, conformances="Instantiable", defaults=(), members=""):
    """One `public` class with internal properties: `properties` are (macro, label, type) each, `defaults` (label,
    type, default value) each, parameters of the initializer alone, and `members` is more source for its body."""
    parameters = [f"{label}: {type_}" for _, label, type_ in properties] + [f"{label}: {type_} = {value}" for label, type_, value in defaults]
    body = "\n".join(f"        self.{label} = {label}" for _, label, _ in properties) + "".join(f"\n        _ = {label}" for label, _, _ in defaults)
    stored = "\n".join(f"    {macro} let {label}: {type_}" for macro, label, type_ in properties)
    return f"{attribute}\npublic final class {name}: {conformances} {{\n    public init({', '.join(parameters)}) {{\n{body}\n    }}\n\n{stored}\n{members}}}\n\n"


def shape_lifelike_chain(features, screens=30, layers=4, seed=11):
    """An app as its authors would write one: module `Core`, feature modules `F0` to `F{features-1}`, each depending
    on `Core` and on every feature before it, and `App`. A chain of fewer features is the same modules without the
    last ones, so `F4` is one module in a chain of five and in a chain of ten.

    `Core`: four `Sendable` services, `any AnalyticsClient`, which only a `mockOnly` type fulfills in a mock, a
    `Logger` with a hand-written mock, and a `Formatter`. Feature i: a seam with a public mock, `Entry{i}`, which
    receives four values of `Core`, opens every screen of its first layer and, above `F0`, the entry of the feature
    before it, each through an `Instantiator`; and `screens` screens in `layers` layers, each with a generated mock, a
    view model and a repository, opening two or three screens of the next layer. `seed` decides which screens a
    screen opens and which traits (`LIFELIKE_TRAITS`) it has: it forwards an `id`; its view model holds a
    `SendableInstantiator` of a worker, a `LazilyInstantiated` formatter, a parameter with a default value, or a
    `Session` received only if available; it opens a child through an `ErasedInstantiator`; its repository receives
    the logger and the analytics client. `App`: the type that fulfills `any AnalyticsClient` and a mocked root that
    opens every entry."""
    generator = random.Random(seed)
    drawn = lambda trait: generator.randrange(100) < LIFELIKE_TRAITS[trait]
    core = "import SafeDI\n\n"
    for service in ("Network", "Database", "Session", "ImageCache"):
        core += lifelike_declaration("@Instantiable", service, [], conformances="Instantiable, Sendable")
    core += "public protocol AnalyticsClient: AnyObject, Sendable {}\n\n"
    core += "@Instantiable(fulfillingAdditionalTypes: [(any AnalyticsClient).self], mockOnly: true)\npublic final class FakeAnalytics: AnalyticsClient, Instantiable {\n    public init() {}\n    public static func mock() -> FakeAnalytics { FakeAnalytics() }\n}\n\n"
    core += lifelike_declaration("@Instantiable", "Logger", [("@Received", "network", "Network")], conformances="Instantiable, Sendable",
                                 members="\n    public static func mock(network: Network) -> Logger {\n        Logger(network: network)\n    }\n")
    core += lifelike_declaration("@Instantiable", "Formatter", [])
    core += "public protocol ScreenProtocol: AnyObject {}\n\n"
    modules = [("Core", [], core)]
    names = [f"F{feature}" for feature in range(features)]
    per_layer = max(1, screens // layers)
    layer_of = [min(screen // per_layer, layers - 1) for screen in range(screens)]
    for feature in range(features):
        source = "import SafeDI\nimport Core\n" + "".join(f"import {name}\n" for name in names[:feature]) + "\n#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n\n"
        # A screen of the first layer is opened by the entry, which passes no `id`.
        forwards = [drawn("forwarded") for _ in range(screens)]
        forwards = [forwarded and layer_of[screen] > 0 for screen, forwarded in enumerate(forwards)]
        for screen in range(screens):
            name = f"{feature}_{screen}"
            next_layer_screens = [other for other in range(screens) if layer_of[other] == layer_of[screen] + 1]
            opened = []
            if next_layer_screens:
                count = generator.choice([2, 3])
                opened = sorted(generator.sample(next_layer_screens, min(len(next_layer_screens), count)))
            view_model = [("@Received", "id", "Int")] if forwards[screen] else []
            view_model += [("@Received", "network", "Network"), ("@Instantiated", "repository", f"Repository{name}")]
            if drawn("sendable-worker"):
                view_model.append(("@Instantiated", "workerBuilder", f"SendableInstantiator<Worker{name}>"))
                source += lifelike_declaration("@Instantiable", f"Worker{name}", [("@Received", "database", "Database")], conformances="Instantiable, Sendable")
            if drawn("lazy"):
                view_model.append(("@Instantiated", "formatter", "LazilyInstantiated<Formatter>"))
            if drawn("optional"):
                view_model.append(("@Received(onlyIfAvailable: true)", "session", "Session?"))
            source += lifelike_declaration("@Instantiable", f"ViewModel{name}", view_model, defaults=[("pageSize", "Int", "20")] if drawn("default-valued") else [])
            repository = [("@Received", "database", "Database"), ("@Instantiated", "imageCache", "ImageCache")]
            if drawn("hand-written"):
                repository += [("@Received", "logger", "Logger"), ("@Received", "analytics", "any AnalyticsClient")]
            source += lifelike_declaration("@Instantiable", f"Repository{name}", repository)
            properties = [("@Forwarded", "id", "Int")] if forwards[screen] else []
            properties.append(("@Instantiated", "viewModel", f"ViewModel{name}"))
            for child in opened:
                # One draw per child that decides nothing: the graph is the one the row's limits were measured on, whose
                # generator spent a draw here on a trait no screen of it has.
                generator.randrange(100)
                if not forwards[child] and drawn("erased"):
                    properties.append((f'@Instantiated(fulfilledByType: "Screen{feature}_{child}")', f"screen{child}Builder", "ErasedInstantiator<(), any ScreenProtocol>"))
                else:
                    properties.append(("@Instantiated", f"screen{child}Builder", f"Instantiator<Screen{feature}_{child}>"))
            source += lifelike_declaration("@Instantiable(generateMock: true)", f"Screen{name}", properties, conformances="Instantiable, ScreenProtocol")
        entry = [("@Received", "network", "Network"), ("@Received", "database", "Database"), ("@Received", "logger", "Logger"),
                 ("@Received", "analytics", "any AnalyticsClient"), ("@Instantiated", "session", "Session")]
        entry += [("@Instantiated", f"screen{screen}Builder", f"Instantiator<Screen{feature}_{screen}>") for screen in range(screens) if layer_of[screen] == 0]
        if feature > 0:
            entry.append(("@Instantiated", f"entry{feature - 1}Builder", f"Instantiator<Entry{feature - 1}>"))
        source += lifelike_declaration("@Instantiable(generateDependencyTree: true, generateMock: .public)", f"Entry{feature}", entry)
        modules.append((names[feature], ["Core"] + names[:feature], source))
    app = "import SafeDI\nimport Core\n" + "".join(f"import {name}\n" for name in names) + "\n"
    app += lifelike_declaration("@Instantiable(fulfillingAdditionalTypes: [(any AnalyticsClient).self])", "LiveAnalytics", [], conformances="Instantiable, AnalyticsClient")
    root = [("@Instantiated", "network", "Network"), ("@Instantiated", "database", "Database"), ("@Instantiated", "logger", "Logger"),
            ("@Instantiated", "analytics", "any AnalyticsClient")]
    root += [("@Instantiated", f"entry{feature}Builder", f"Instantiator<Entry{feature}>") for feature in range(features)]
    app += lifelike_declaration("@Instantiable(isRoot: true, generateMock: true)", "Root", root)
    modules.append(("App", ["Core"] + names, app))
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


def shape_all_to_all_tangle(members):
    """Module `Feature`: the seam `Hub` holds an `Instantiator` of each of `members` types, each of which instantiates a
    `Mark` of its own and `any Api`, which no type of the module fulfills, and holds an `Instantiator` of every other
    member: a tangle of cycles no type always encloses, where the member a builder call closes on depends on the set of
    members on the path. Module `App`: the root and the only `Api`."""
    names = [f"M{index}" for index in range(members)]
    feature = "import SafeDI\n\npublic protocol Api: AnyObject {}\n\n"
    for name in names:
        feature += declaration("@Instantiable", f"Mark{name}", [])
        properties = [("@Instantiated", f"mark{name}", f"Mark{name}")]
        properties += [("@Instantiated", f"{other.lower()}Builder", f"Instantiator<{other}>") for other in names if other != name]
        properties.append(("@Instantiated", "api", "any Api"))
        feature += declaration("@Instantiable", name, properties)
    feature += declaration("@Instantiable(generateDependencyTree: true)", "Hub", [("@Instantiated", f"{name.lower()}Builder", f"Instantiator<{name}>") for name in names])
    app = declaration("@Instantiable(fulfillingAdditionalTypes: [(any Api).self])", "LiveApi", [], conformances="Instantiable, Api")
    app += declaration("@Instantiable(isRoot: true)", "Root", [("@Instantiated", "hub", "Hub")])
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


def shape_parent_router(layers, width=3, seam=False):
    """One module: a root over `layers` layers of `width` screens, each holding `Instantiator`s of every screen of the
    next layer, instantiating a `Router` under its own layer's label and receiving the one the layer before declares,
    so each screen receives what every one of its parents declares. With `seam`, module `Feature` holds the screens
    under a seam `Home`, whose own module lays out its tree, and module `App` holds the root, which builds `Home`."""
    source = "import SafeDI\n\n" + declaration("@Instantiable", "Router", [])
    for layer in range(layers):
        for position in range(width):
            properties = [("@Instantiated", f"router{layer}", "Router")]
            if layer > 0:
                properties.append(("@Received", f"router{layer - 1}", "Router"))
            if layer + 1 < layers:
                properties += [("@Instantiated", f"screen{layer + 1}x{child}Builder", f"Instantiator<Screen{layer + 1}x{child}>") for child in range(width)]
            source += declaration("@Instantiable", f"Screen{layer}x{position}", properties)
    if seam:
        source += declaration("@Instantiable(generateDependencyTree: true)", "Home", [("@Instantiated", f"screen0x{child}Builder", f"Instantiator<Screen0x{child}>") for child in range(width)])
        return [("Feature", [], source), ("App", ["Feature"], "import Feature\nimport SafeDI\n\n" + declaration("@Instantiable(isRoot: true)", "Root", [("@Instantiated", "home", "Home")]))]
    source += declaration("@Instantiable(isRoot: true)", "Root", [("@Instantiated", f"screen0x{child}Builder", f"Instantiator<Screen0x{child}>") for child in range(width)])
    return [("App", [], source)]


def shape_leaves_reached_twice(depth, leaves=10, values=60):
    """One module: a root that instantiates `values` values and the first of a chain of `depth` screens, each
    instantiating three values, an `Instantiator` of the next screen, and `Instantiator`s of its own `leaves` leaves and
    of the leaves of the screen before. Each leaf instantiates a model of its own, so every leaf and model is reached
    exactly twice, one screen apart, beneath as many screens as the chain is long there."""
    source = "import SafeDI\n\n" + declaration("@Instantiable", "Value", [])
    for screen in range(depth):
        properties = [("@Instantiated", f"screen{screen}Value{index}", "Value") for index in range(3)]
        if screen + 1 < depth:
            properties.append(("@Instantiated", f"screen{screen + 1}Builder", f"Instantiator<Screen{screen + 1}>"))
        for owner in ([screen, screen - 1] if screen > 0 else [screen]):
            properties += [("@Instantiated", f"leaf{owner}x{leaf}Builder", f"Instantiator<Leaf{owner}x{leaf}>") for leaf in range(leaves)]
        source += declaration("@Instantiable", f"Screen{screen}", properties)
        for leaf in range(leaves):
            source += declaration("@Instantiable", f"Leaf{screen}x{leaf}", [("@Instantiated", "model", f"Model{screen}x{leaf}")])
            source += declaration("@Instantiable", f"Model{screen}x{leaf}", [])
    root = [("@Instantiated", f"rootValue{index}", "Value") for index in range(values)]
    source += declaration("@Instantiable(isRoot: true)", "Root", root + [("@Instantiated", "screen0Builder", "Instantiator<Screen0>")])
    return [("App", [], source)]


def shape_leaves_reached_from_two_screens(width):
    """One module: a root that instantiates `First`, `Even`, `Odd` and `Third`. `First` and `Third` each instantiate
    every one of `width` leaves, `Even` those at even positions and `Odd` the others, and each leaf instantiates a model
    of its own. Every leaf is reached three times: its second reach is beneath `Even` or `Odd`, in turn from one leaf
    to the next, so what `Third` finds remembered of its leaves alternates between two screens."""
    source = "import SafeDI\n\n"
    leaves = [("@Instantiated", f"leaf{leaf}", f"Leaf{leaf}") for leaf in range(width)]
    for leaf in range(width):
        source += declaration("@Instantiable", f"Leaf{leaf}", [("@Instantiated", "model", f"Model{leaf}")])
        source += declaration("@Instantiable", f"Model{leaf}", [])
    source += declaration("@Instantiable", "First", leaves)
    source += declaration("@Instantiable", "Even", leaves[0::2])
    source += declaration("@Instantiable", "Odd", leaves[1::2])
    source += declaration("@Instantiable", "Third", leaves)
    root = [("@Instantiated", label, type_) for label, type_ in [("first", "First"), ("even", "Even"), ("odd", "Odd"), ("third", "Third")]]
    source += declaration("@Instantiable(isRoot: true)", "Root", root)
    return [("App", [], source)]


def shape_leaves_reached_three_times_down_chain(depth):
    """One module: a root over a chain of `depth` screens, each instantiating three values, `Instantiator`s of a leaf of
    its own and of the leaves of the two screens before, and then an `Instantiator` of the next screen. Each leaf
    instantiates a model of its own, so every leaf is reached three times, one screen apart, each time before the walk
    goes a screen deeper, and every model twice."""
    source = "import SafeDI\n\n" + declaration("@Instantiable", "Value", [])
    for screen in range(depth):
        properties = [("@Instantiated", f"screen{screen}Value{index}", "Value") for index in range(3)]
        properties += [("@Instantiated", f"leaf{owner}Builder", f"Instantiator<Leaf{owner}>") for owner in range(screen, max(screen - 3, -1), -1)]
        if screen + 1 < depth:
            properties.append(("@Instantiated", f"screen{screen + 1}Builder", f"Instantiator<Screen{screen + 1}>"))
        source += declaration("@Instantiable", f"Screen{screen}", properties)
        source += declaration("@Instantiable", f"Leaf{screen}", [("@Instantiated", "model", f"Model{screen}")])
        source += declaration("@Instantiable", f"Model{screen}", [])
    source += declaration("@Instantiable(isRoot: true)", "Root", [("@Instantiated", "screen0Builder", "Instantiator<Screen0>")])
    return [("App", [], source)]


def shape_components_on_two_wide_screens(components, screens=40, values=400):
    """One module: a root that instantiates `values` values and holds an `Instantiator` of each of `screens` screens.
    Each screen instantiates `components` components of its own and those of the screen before it, the first screen
    those of the last, so every component is on two screens; each component receives one of the root's values and
    instantiates a model of its own. Nothing is more than three scopes from the root: what the walk hands a component
    grows with the root's labels and with its screen's width, not with depth."""
    source = "import SafeDI\n\n" + declaration("@Instantiable", "Value", [])
    for screen in range(screens):
        properties = []
        for owner in (screen, (screen - 1) % screens):
            properties += [("@Instantiated", f"component{owner}x{index}", f"Component{owner}x{index}") for index in range(components)]
        source += declaration("@Instantiable", f"Screen{screen}", properties)
        for index in range(components):
            received = ("@Received", f"value{(screen * components + index) % values}", "Value")
            source += declaration("@Instantiable", f"Component{screen}x{index}", [received, ("@Instantiated", "model", f"Model{screen}x{index}")])
            source += declaration("@Instantiable", f"Model{screen}x{index}", [])
    root = [("@Instantiated", f"value{index}", "Value") for index in range(values)]
    root += [("@Instantiated", f"screen{screen}Builder", f"Instantiator<Screen{screen}>") for screen in range(screens)]
    source += declaration("@Instantiable(isRoot: true)", "Root", root)
    return [("App", [], source)]


def shape_back_links(links, features=6, layers=2, width=2, state_only_if_available=False):
    """One module: a root that holds an `Instantiator` of each of `features` features' entries. Each entry instantiates
    a state of its feature's own type under one label, `Instantiator`s of its first layer of `width` screens, and one
    of the entry of the feature before it and of the feature three before it. Each screen receives its feature's state
    and holds `Instantiator`s of two screens of the next layer, and in the first `links` features the last screen of
    the last layer holds one of its own feature's entry: a link back, as a tab that opens its flow's start again. A
    feature is reached beneath every set of features that open it, each of which declares the label with another
    type, and a link is inside the tree of every feature that reaches its own, so the paths through the links multiply
    with them, while each type's own tree is the same on every path. With `state_only_if_available`, each screen
    receives the state only if available."""
    source = "import SafeDI\n\n"
    for feature in range(features):
        source += declaration("@Instantiable", f"State{feature}", [])
        entry = [("@Instantiated", "state", f"State{feature}")]
        entry += [("@Instantiated", f"screen0x{position}Builder", f"Instantiator<Screen{feature}x0x{position}>") for position in range(width)]
        entry += [("@Instantiated", f"feature{opened}Builder", f"Instantiator<Entry{opened}>") for opened in (feature - 1, feature - 3) if opened >= 0]
        source += declaration("@Instantiable", f"Entry{feature}", entry)
        for layer in range(layers):
            for position in range(width):
                properties = [("@Received(onlyIfAvailable: true)", "state", f"State{feature}?") if state_only_if_available else ("@Received", "state", f"State{feature}")]
                if layer < layers - 1:
                    properties += [
                        ("@Instantiated", f"screen{layer + 1}x{child}Builder", f"Instantiator<Screen{feature}x{layer + 1}x{child}>")
                        for child in dict.fromkeys(((position + offset) % width for offset in range(2)))
                    ]
                elif position == width - 1 and feature < links:
                    properties.append(("@Instantiated", "entryBackBuilder", f"Instantiator<Entry{feature}>"))
                source += declaration("@Instantiable", f"Screen{feature}x{layer}x{position}", properties)
    source += declaration("@Instantiable(isRoot: true)", "Root", [("@Instantiated", f"feature{feature}Builder", f"Instantiator<Entry{feature}>") for feature in range(features)])
    return [("App", [], source)]


def shape_feature_labels_over_shared_tree(labels, features=60, shared=1000):
    """One module: a root that instantiates six services and holds an `Instantiator` of each of `features` features'
    entries. Each entry instantiates `labels` values, each under a label every feature declares with a type of its own,
    and holds an `Instantiator` of the first of its feature's three screens. Each screen receives its feature's values
    and holds an `Instantiator` of the next screen; the last holds one of its feature's entry, a link back, and one of
    the first of `shared` types, a tree every feature opens, each type of which receives the six services and
    instantiates two more. No feature's value can reach another feature's screens, and the shared tree reads none of
    them, so what validation asks of each label is settled by its own feature's four types."""
    source = "import SafeDI\n\n"
    services = [("service%d" % service, "Service%d" % service) for service in range(6)]
    for _, service in services:
        source += declaration("@Instantiable", service, [])
    for index in range(shared):
        properties = [("@Received", label, type_) for label, type_ in services]
        properties += [("@Instantiated", f"shared{child}", f"Shared{child}") for child in (2 * index + 1, 2 * index + 2) if child < shared]
        source += declaration("@Instantiable", f"Shared{index}", properties)
    for feature in range(features):
        for label in range(labels):
            source += declaration("@Instantiable", f"Value{feature}x{label}", [])
        entry = [("@Instantiated", f"value{label}", f"Value{feature}x{label}") for label in range(labels)]
        source += declaration("@Instantiable", f"Entry{feature}", entry + [("@Instantiated", "screen0Builder", f"Instantiator<Screen{feature}x0>")])
        for screen in range(3):
            properties = [("@Received", f"value{label}", f"Value{feature}x{label}") for label in range(labels)]
            if screen < 2:
                properties.append(("@Instantiated", f"screen{screen + 1}Builder", f"Instantiator<Screen{feature}x{screen + 1}>"))
            else:
                properties += [("@Instantiated", "entryBackBuilder", f"Instantiator<Entry{feature}>"), ("@Instantiated", "sharedBuilder", "Instantiator<Shared0>")]
            source += declaration("@Instantiable", f"Screen{feature}x{screen}", properties)
    root = [("@Instantiated", label, type_) for label, type_ in services]
    root += [("@Instantiated", f"feature{feature}Builder", f"Instantiator<Entry{feature}>") for feature in range(features)]
    source += declaration("@Instantiable(isRoot: true)", "Root", root)
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


def shape_ring_receiving_labels(screens, labels=400):
    """One module: a root that instantiates `labels` services and the first of `screens` screens on one cycle of
    `Instantiator`s. Screen i receives services 2i and 2i + 1, modulo `labels`, and holds an `Instantiator` of the next
    screen, so each screen's reads are looked up past every screen above it."""
    source = "import SafeDI\n\n"
    for service in range(labels):
        source += declaration("@Instantiable", f"Service{service}", [])
    for screen in range(screens):
        received = [("@Received", f"service{index % labels}", f"Service{index % labels}") for index in (2 * screen, 2 * screen + 1)]
        source += declaration("@Instantiable", f"Screen{screen}", received + [builder((screen + 1) % screens)])
    root = [("@Instantiated", f"service{service}", f"Service{service}") for service in range(labels)]
    source += declaration("@Instantiable(isRoot: true)", "Root", root + [builder(0)])
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
# The shapes whose peak memory is judged only on the runs with one allocator arena, at `--memory-limit` ("Peak memory"
# in the header says why).
ONE_ARENA_ONLY_SHAPES = frozenset(["E24-public-mock"])

# The growth rows ("Growth" in the header): name -> (the shape at a number of layers, the smaller number of layers,
# the limits that differ from `--growth-limit`, by measure: "time", "memory", "size" or "code"). A row with limits of
# its own is a shape whose growth is known and not yet removed: each is what the shape measured, with room for noise,
# so that the row holds what has been gained until the change that removes the growth deletes the entry.
# A row generated as the SwiftPM plugin generates ("As the SwiftPM plugin generates" in the header) gives both numbers
# of layers in place of the smaller, and ends with the function that names the one module generated at a number.
#
# Measured on a four-core Linux machine with a release build of the tool, the smaller graph's figure first:
# P 0.376 s and 3.313 s (8.82), 50.7 MB and 213.5 MB (4.21), 341,899 and 3,966,895 bytes of `.safedi` (11.60);
# K 0.069 s and 0.290 s (4.18), 972,037 and 9,574,045 bytes of code (9.85);
# M 0.122 s and 0.388 s (3.17), 428,063 and 3,552,741 bytes of code (8.30); MH 0.304 s and 2.562 s (8.43), 47.5 MB and
# 170.1 MB (3.58), 267,591 and 3,068,049 bytes of `.safedi` (11.47), 751,871 and 6,212,036 bytes of code (8.26);
# B 0.086 s and 1.576 s (18.37), 34.5 MB and 92.6 MB (2.68); BM 0.079 s and 2.543 s
# (32.30), 33.7 MB and 179.7 MB (5.34), 108,891 and 28,647,642 bytes of code (263.09).
# The tool alone, on the smallest graph, peaks at about 33 MB. K (36.6 MB and 67.4 MB, 1.84) and W (52.4 MB and
# 94.9 MB, 1.74 to 1.82 in five runs) stay under the default limit without room to spare.
GROWTH_ROWS = {
    "P-seam-hole-at-every-screen": (lambda layers: shape_p(layers), 6, {"time": 13.0, "memory": 5.5, "size": 12.5}),
    "L-label-declared-again": (lambda layers: shape_l(layers), 9, {}),
    "K-mock-at-every-screen": (lambda layers: shape_k(layers), 6, {"time": 6.5, "code": 10.5}),
    "M-public-mock-layers": (lambda layers: shape_public_mock_layers(layers, hole=False), 6, {"time": 5.0, "code": 9.0}),
    "MH-public-mock-hole-at-every-screen": (lambda layers: shape_public_mock_layers(layers, hole=True), 6, {"time": 12.5, "memory": 5.5, "size": 12.5, "code": 9.0}),
    "Q-seam-own-module-paths": (lambda layers: shape_q(layers), 9, {}),
    # These two start at few layers because more take minutes today. Once a row's growth is removed, give it more
    # layers with its limits' removal: from two layers to four, work that grows with the graph doubles.
    "B-cycles-through-instantiators": (lambda layers: shape_b(layers, mocks=False), 3, {"time": 27.0, "memory": 3.6}),
    "W-ring-of-screens-that-open-each-other": (lambda width: shape_w(width), 10, {"time": 4.0}),
    # WL's graph is twice as large at the larger size, 100 and 200 screens: 0.64 s and 2.77 s (4.36), 65 MB and 130 MB
    # (1.98), 50,201 and 76,701 bytes of code (1.53). Its time grows with the depth of each look-up and with the key of
    # each subtree its validation remembers.
    "WL-ring-of-screens-receiving-labels": (lambda layers: shape_ring_receiving_labels(50 * layers), 2, {"time": 5.5, "memory": 2.4}),
    "BM-mocks-of-cycles-through-instantiators": (lambda layers: shape_b(layers, mocks=True), 2, {"time": 48.0, "memory": 6.5, "code": 275.0}),
    # Three and five modules, not four and six: at six this row alone takes 21 s and 1.2 GB on main today (30 times
    # four's time). 0.26 s and 3.17 s (12.4), 38 MB and 196 MB (5.1), 122,250 and 4,137,809 bytes of `.safedi` (33.8),
    # 282,609 and 4,967,332 bytes of code (17.6).
    "F9-public-mock-seam-chain": (lambda layers: shape_public_mock_seam_chain(layers), 3, {"time": 16.0, "memory": 6.0, "size": 36.0, "code": 19.0}),
    # H 0.15 s and 2.1 s (13.7 and 14.5 in two runs), 35 MB and 74 MB (2.13), 25,811 and 1,406,899 bytes of `.safedi`
    # (54.5), 31,432 and 126,780 bytes of code (4.03). Starts at three layers: at six, Feature alone takes 9.8 s.
    "H-seam-holes-in-cycles": (lambda layers: shape_seam_holes_in_cycles(layers), 3, {"time": 22.0, "memory": 2.6, "size": 65.0, "code": 5.0}),
    # TA 0.150 s and 3.28 s (19.6 and 21.9 in two runs), 42 MB and 166 MB (3.93), 37,156 and 1,466,255 bytes of `.safedi`
    # (39.5), 79,777 and 5,541,268 bytes of code (69.5). The same graph with `Api` fulfilled in `Feature` and no seam stays
    # within the default limits (1.84 times the code from three members to five), so the growth is the seam's places:
    # where a builder call closes depends on the set of members above it.
    # The roadmap's row 4 (seams: one stored graph per seam, a passed-up place a reference) removes these limits.
    "TA-all-to-all-tangle": (lambda members: shape_all_to_all_tangle(members), 4, {"time": 27.0, "memory": 4.7, "size": 47.0, "code": 83.0}),
    "O-only-if-available-at-every-screen": (lambda layers: shape_census(layers, "only-if-available"), 6, {}),
    "R-received-instantiator-at-every-screen": (lambda layers: shape_census(layers, "received-instantiator"), 6, {}),
    "N-rename-at-every-screen": (lambda layers: shape_census(layers, "rename"), 8, {}),
    # V 1.32 and VO 1.18 times over two more layers, while a subtree's key holds only the entries of a rename's declaring
    # path its walk reads; 2.47 and 3.26 while it holds the whole path.
    "V-renames-in-alternate-layers": (lambda layers: shape_alternating_renames(layers, only_if_available=False), 10, {}),
    "VO-only-if-available-renames-in-alternate-layers": (lambda layers: shape_alternating_renames(layers, only_if_available=True), 10, {}),
    "PR-parents-router": (lambda layers: shape_parent_router(layers), 8, {}),
    "PRS-seam-parents-router": (lambda layers: shape_parent_router(layers, seam=True), 8, {}),
    # T's graph is three times as large at the larger size, a chain 100 and 300 screens long, and TS's and TC's twice,
    # so each limit is that multiple with room: T 0.78 s and 3.08 s (3.94), 108 MB and 189 MB (1.74), 321,956 and 997,756
    # bytes of `.safedi` (3.10), 419,959 and 1,288,909 bytes of code (3.07); TS 0.97 s and 2.02 s (2.08), 143 MB and
    # 248 MB (1.73), 510,636 and 1,035,436 bytes of `.safedi` (2.03), 565,355 and 1,150,955 bytes of code (2.04); TC
    # 1.06 s and 2.87 s (2.69), 104 MB and 175 MB (1.68), 317,424 and 653,424 bytes of `.safedi` (2.06), 455,533 and
    # 915,033 bytes of code (2.01). Only T's and TC's times are growth to remove, which the tool had before these rows:
    # they grow faster than the chain. TS's time grew faster than its screens' width, 2.40, until the type key's look-ups
    # read a body's positions by label rather than scanning its statements. What the rows hold: a walk remembered by
    # its whole context, with no key until its scope was reached again, took 146 MB and 662 MB on T (4.53) and 139 MB
    # and 337 MB on TC (2.42), and one whose context was computed again along its path where its scope was next reached
    # took 4.15 s and 15.91 s on TS (3.84).
    "T-leaves-reached-twice-at-depth": (lambda layers: shape_leaves_reached_twice(100 * layers), 1, {"time": 6.0, "memory": 3.8, "size": 3.5, "code": 3.5}),
    "TS-leaves-reached-from-two-screens": (lambda layers: shape_leaves_reached_from_two_screens(800 * layers), 2, {"time": 2.3, "memory": 2.8, "size": 2.3, "code": 2.3}),
    "TC-leaves-reached-three-times-down-chain": (lambda layers: shape_leaves_reached_three_times_down_chain(250 * layers), 2, {"time": 3.6, "memory": 2.1, "size": 2.3, "code": 2.3}),
    # TW's graph is twice as large at the larger size, 50 and 100 components to a screen, and nothing in it is more than
    # three scopes from the root: 1.58 s and 3.09 s (1.96), 167 MB and 243 MB to 292 MB (1.46 to 1.73 in two
    # runs), 687,827 and 1,366,396 bytes of `.safedi` (1.99), 790,823 and 1,558,723 bytes of code (1.97). Its memory is
    # held to 2.3: with one allocator arena the larger graph needs 1.62 times the smaller one's peak, and with the
    # default arenas, which the growth rows run with, a run on CI read up to 2.01. A walk remembered by its whole
    # context only near the root, which T and TC pass, took 209 MB and 537 MB here (2.57), since what a walk hands a
    # scope grows with the labels above it and with its parent's width, not with its depth.
    "TW-components-on-two-wide-screens": (lambda layers: shape_components_on_two_wide_screens(25 * layers), 2, {"time": 2.5, "memory": 2.3, "size": 2.3, "code": 2.3}),
    # BL, BL4 and BLO are one shape, six features that open one another. BL, at one and three links back to a feature's
    # entry: 0.077 s and 0.127 s (1.65), where a tool that walked a screen beneath each set of features above it, and its
    # tree again at each link, took 0.106 s and 0.586 s (5.54). BL4, at four and six: 0.187 s and 0.833 s (4.46), 47.4 MB
    # and 83.5 MB (1.76), where that tool took 1.463 s and 14.544 s (9.94). Validation walks the same scopes whatever the
    # links (105 to 109 from two links to six), so BL4's limits are tree building's, which still builds a first-pass
    # tree with a node for each path through the links. BLO, with the state received only if available: 0.101 s and
    # 0.329 s (3.25). Validation still walks it once for each path: such a receive makes the optional form receivable
    # beneath it, so a screen built again beneath its own feature's last screen has another key than its first build.
    "BL-back-links-to-feature-entries": (lambda layers: shape_back_links(layers, features=6, layers=3, width=3), 1, {}),
    "BL4-back-links-to-most-feature-entries": (lambda layers: shape_back_links(layers, features=6, layers=3, width=3), 4, {"time": 6.0, "memory": 2.4}),
    "BLO-back-links-with-state-only-if-available": (lambda layers: shape_back_links(layers, features=6, layers=3, width=3, state_only_if_available=True), 1, {"time": 8.0}),
    # BLS: sixty features with a link back each, over a shared tree of 1,000 types, at 5 and 25 labels that every
    # feature declares with types of its own. Whether a declaration of such a label can hide a read is asked of each
    # scope once, for every label together: 1.45 s and 2.11 s (1.46), each within a hundredth of a tool that never asks.
    # Asked once for each label and each scope that declares it, over every scope beneath that scope, the shared tree
    # included, it took 2.26 s and 5.94 s (2.63). Its memory is held to 2.3: with the default arenas, which the growth
    # rows run with, a run on CI read 110.9 MB and 222.9 MB (2.01, run 45938379663).
    "BLS-back-links-with-feature-labels-over-shared-tree": (lambda layers: shape_feature_labels_over_shared_tree(10 * layers - 5), 1, {"memory": 2.3}),
    # `F4` of five features and `F9` of ten: twice the features beneath the module on top. Four runs of the row with
    # each of three tools that build the features beneath inline (the 2.4.0 release among them) measured 0.63 to
    # 0.68 s and 1.22 to 1.41 s, 1.79 to 2.17 times, and 3,540,750 and 6,776,238 bytes of code (1.91, and 1.97 with
    # another of the three); peak memory 64 to 69 MB and 89 to 103 MB (1.33 to 1.60). A tool whose mock of each
    # feature's seam instead calls the public mock of the feature before it measured 0.67 to 0.68 s and 1.67 to
    # 1.95 s, 2.47 to 2.92 times, in four runs: the features beneath then cost the module on top more each than they
    # cost built inline. In CI's container a tool that builds them inline measured 0.497 s and 1.013 s (2.04 times),
    # 66.1 MB and 101.1 MB, and 3,542,265 and 6,777,708 bytes of code (1.91), in three runs (run 45938379663). The
    # time limit is that reading plus 15% for noise: this row is the acceptance test of a mock that calls the public
    # mock of the feature beneath, since no feature's plan may be worked out again in the module above it.
    "LP-lifelike-chain-under-the-plugin": (lambda features: shape_lifelike_chain(features), (5, 10), {"time": 2.35, "code": 2.2}, lambda features: f"F{features - 1}"),
}
GROWTH_STEP = 2
GROWTH_RUNS = 3
# The last arguments of the SwiftPM plugin's `generate` command (`buildSettingCompilationConditionArguments` in the
# plugin): references to build settings, which, as the comment there says, SwiftPM's own build system passes as they
# are written here, and the tool then uses the conditions the plugin reported.
UNEXPANDED_BUILD_SETTINGS = ["--build-setting-active-compilation-conditions=[${SWIFT_ACTIVE_COMPILATION_CONDITIONS}]", "--build-setting-other-swift-flags=[${OTHER_SWIFT_FLAGS}]"]
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


def plugin_command(tool, name, direct, beneath, sources, output, environment):
    """The `generate` command the SwiftPM plugin runs for module `name` ("As the SwiftPM plugin generates" in the
    header), after writing what the plugin writes and running its `scan`, which is not timed."""
    file = lambda module: f"{module}/Types.swift"
    target = lambda module: {"moduleName": module, "packageID": "generatetimecheck", "sourceFilePaths": [file(module)], "dependencyModuleNames": sorted(direct[module])}
    inputs = f"{output}/{name}/InputSwiftFiles.csv"
    manifest = f"{output}/{name}/SafeDIManifest.json"
    write(inputs, ",".join(file(module) for module in [name] + beneath[name]))
    write(inputs + ".targets.json", json.dumps({"target": target(name), "dependencyTargets": [target(module) for module in beneath[name]]}))
    # The build system makes the directory of the outputs a command declares.
    os.makedirs(f"{output}/{name}/SafeDIOutput", exist_ok=True)
    with open(f"{output}/{name}.scan.log", "wb") as log:
        scan = subprocess.run([tool, "scan", "--input-sources-file", inputs, "--project-root", sources, "--output-directory", f"{output}/{name}/SafeDIOutput",
                               "--manifest-file", manifest, "--mock-scoped-files", f"{sources}/{file(name)}", "--active-compilation-conditions", "DEBUG"],
                              stdout=log, stderr=subprocess.STDOUT, env=environment, cwd=sources)
    if scan.returncode != 0:
        with open(f"{output}/{name}.scan.log", errors="replace") as log:
            raise Failure(f"`scan` of module {name} exited {scan.returncode}: {log.read().strip()[-1500:]}")
    return [tool, inputs, "--swift-manifest", manifest, "--active-compilation-conditions", "DEBUG"] + UNEXPANDED_BUILD_SETTINGS


def generate(tool, modules, sources, output, variables={}, time_limit=None, under_plugin=None):
    """Runs `generate` for each module into `output`, with `variables` added to its environment; returns (wall
    seconds, CPU seconds, peak bytes): the times summed over the modules, the peak the largest of the modules'
    processes' maximum resident set sizes. A module's process still running after `time_limit` seconds is killed,
    which fails the run. With `under_plugin`, a module's name, runs `generate` for that module alone, as the SwiftPM
    plugin runs it."""
    os.makedirs(output, exist_ok=True)
    environment = dict(os.environ, TMPDIR=output, **variables)
    direct = {name: dependencies for name, dependencies, _ in modules}
    beneath = {}
    wall = 0.0
    cpu = 0.0
    peak = 0
    for name, dependencies, _ in modules:
        beneath[name] = sorted(set(dependencies).union(*(beneath[dependency] for dependency in dependencies)))
        if under_plugin is None:
            write(f"{output}/{name}.csv", f"{sources}/{name}/Types.swift\n")
            command = [tool, "generate", f"{output}/{name}.csv", "--combined-output", f"{output}/{name}.generated.swift",
                       "--module-info-output", f"{output}/{name}.safedi", "--active-compilation-conditions", "DEBUG",
                       "--module-name", name, "--package-name", "GenerateTimeCheck"]
            if dependencies:
                write(f"{output}/{name}.dependencies.csv", "".join(f"{output}/{dependency}.safedi\n" for dependency in dependencies))
                write(f"{output}/{name}.transitive.csv", "".join(f"{output}/{module}.safedi\n" for module in beneath[name]))
                command += ["--dependent-module-info-file-path", f"{output}/{name}.dependencies.csv",
                            "--transitive-module-info-file-path", f"{output}/{name}.transitive.csv"]
        elif name == under_plugin:
            command = plugin_command(tool, name, direct, beneath, sources, output, environment)
        else:
            continue
        with open(f"{output}/{name}.log", "wb") as log:
            started = time.monotonic()
            # A session of its own, so that stopping it stops the launcher and the tool together. The plugin's command
            # starts in the sources' directory, which the paths in the plugin's files are relative to.
            process = subprocess.Popen([sys.executable, "-I", "-S", "-c", LAUNCHER, f"{output}/{name}.usage"] + command,
                                       stdout=log, stderr=subprocess.STDOUT, env=environment, start_new_session=True, cwd=sources if under_plugin else None)
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


def module_info_sizes(modules, output, under_plugin=None):
    """Each module's `.safedi` bytes; none `under_plugin`, where no module writes one."""
    return [os.path.getsize(f"{output}/{name}.safedi") for name, _, _ in modules if under_plugin is None]


def generated_code(modules, output, under_plugin=None):
    """Each module's generated code as (its length, a digest of it), with the output directory's path removed: the
    one file it writes, or, of the module generated `under_plugin`, the files of its output directory in name order.
    Read a line at a time: a child process's peak memory starts at what this process holds when it starts the child,
    so a file held here whole would become the floor of every later measurement."""
    code = []
    for name, _, _ in modules:
        if under_plugin is None:
            files = [f"{output}/{name}.generated.swift"]
        elif name == under_plugin:
            files = [f"{output}/{name}/SafeDIOutput/{file}" for file in sorted(os.listdir(f"{output}/{name}/SafeDIOutput")) if file.endswith(".swift")]
        else:
            continue
        length = 0
        digest = hashlib.sha256()
        for file in files:
            with open(file) as handle:
                for line in handle:
                    line = line.replace(output, "")
                    length += len(line)
                    digest.update(line.encode())
        code.append((length, digest.hexdigest()))
    return code


# MARK: Comparing


def compare(base_tool, head_tool, directory, shapes, runs, limit, memory_limit, size_limit, large_memory_limit=1.1, large_memory_shapes=LARGE_MEMORY_SHAPES, large_memory_runs=LARGE_MEMORY_RUNS, accepted_sizes=ACCEPTED_MODULE_INFO_BYTES, one_arena_only_shapes=ONE_ARENA_ONLY_SHAPES):
    """Returns (the time and memory table's rows, the size table's rows, the failures)."""
    rows = []
    size_rows = []
    failures = []
    for shape in shapes:
        modules = SHAPES[shape]()
        one_arena_only = shape in one_arena_only_shapes
        one_arena_runs = large_memory_runs if shape in large_memory_shapes or one_arena_only else 0
        one_arena_limit = min(memory_limit, large_memory_limit) if shape in large_memory_shapes else memory_limit
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
        memory_over = not one_arena_only and memory_ratio >= memory_limit and median["head"][2] - median["base"][2] > MEMORY_NOISE_FLOOR_BYTES
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
            if one_arena_ratio >= one_arena_limit and head_peak - base_peak > MEMORY_NOISE_FLOOR_BYTES:
                memory_over = True
                failures.append(f"{shape}: `generate` needed {one_arena_ratio:.2f} times the base tool's peak memory with one allocator arena ({megabytes(head_peak)} against {megabytes(base_peak)}, median of {one_arena_runs}); the limit is {one_arena_limit:g}")
            one_arena = f"; with one arena {megabytes(base_peak)} and {megabytes(head_peak)}, {one_arena_ratio:.2f}{', the figure compared' if one_arena_only else ''}"
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


def row_parts(row):
    """A growth row's (shape, the two numbers of layers it is built at, limits, the function that names the module
    generated as the SwiftPM plugin generates it at a number of layers, or None for a row generated per module)."""
    build, layers, row_limits, *under_plugin = row
    return build, layers if isinstance(layers, tuple) else (layers, layers + GROWTH_STEP), row_limits, under_plugin[0] if under_plugin else None


def grow(head_tool, directory, growth_rows, runs, limit, time_limit=GROWTH_TIME_LIMIT_SECONDS):
    """Returns (the growth table's rows, the failures): each of `growth_rows` generated by `head_tool` at its two
    numbers of layers."""
    rows = []
    failures = []
    for name, row in growth_rows.items():
        build, depths, row_limits, timed_module = row_parts(row)
        under_plugin = {depth: timed_module(depth) if timed_module else None for depth in depths}
        modules = {depth: build(depth) for depth in depths}
        samples = {depth: [] for depth in depths}
        sizes = {}
        code = {}
        try:
            for depth in depths:
                sources = f"{directory}/growth-{name}/{depth}/sources"
                for module, _, source in modules[depth]:
                    write(f"{sources}/{module}/Types.swift", source)
                generate(head_tool, modules[depth], sources, f"{directory}/growth-{name}/{depth}/warm-up", time_limit=time_limit, under_plugin=under_plugin[depth])
                sizes[depth] = sum(module_info_sizes(modules[depth], f"{directory}/growth-{name}/{depth}/warm-up", under_plugin[depth]))
                code[depth] = sum(length for length, _ in generated_code(modules[depth], f"{directory}/growth-{name}/{depth}/warm-up", under_plugin[depth]))
            for run in range(runs):
                for depth in depths:
                    samples[depth].append(generate(head_tool, modules[depth], f"{directory}/growth-{name}/{depth}/sources", f"{directory}/growth-{name}/{depth}/{run}", time_limit=time_limit, under_plugin=under_plugin[depth]))
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
    lines = [f"`generate` time and peak memory, head against base: median of {runs} alternating runs; a shape fails at {limit:g} times the base's wall time or {memory_limit:g} times its peak memory, and {', '.join(sorted(LARGE_MEMORY_SHAPES))} also at {min(memory_limit, large_memory_limit):g} times the base's median peak of {large_memory_runs} more runs with one allocator arena. {', '.join(sorted(ONE_ARENA_ONLY_SHAPES))} is compared at {memory_limit:g} on its runs with one arena alone.", "",
             "| Shape | Runs | Base wall / CPU | Head wall / CPU | Head / base (wall) | Base peak | Head peak | Head / base (peak) | Generated code | Verdict |",
             "|---|---|---|---|---|---|---|---|---|---|"] + rows
    lines += ["", f"`.safedi` size, head against base: a module fails at {size_limit:g} times the base's bytes.", "",
              "| Shape | Module | Base bytes | Head bytes | Head / base | Verdict |", "|---|---|---|---|---|---|"] + size_rows
    if growth_rows:
        lines += ["", f"Growth, the head tool alone: each row at its layers and at {GROWTH_STEP} more, or at the two numbers it names; median of {growth_runs} alternating runs for time and peak memory. A measure fails at {growth_limit:g} times the smaller graph's, or at the limit beside it.", "",
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
# The SwiftPM plugin's commands: a `scan`, whose manifest here holds only the output directory, then a `generate`
# that names no subcommand and reads the manifest.
scans = arguments[0] == "scan"
under_plugin = "--swift-manifest" in arguments
if {refuses!r} and (scans or not under_plugin and option("--module-name") == "App"):
    sys.exit("stand-in: refused")
if scans:
    open(option("--manifest-file"), "w").write(option("--output-directory"))
    sys.exit(0)
# What a measure listed in `grows` is multiplied by: the number of types the module's input declares, to the listed
# power. The plugin's input lists the files of the modules beneath too, separated by commas.
types = sum(open(path).read().count("final class ") for path in open(arguments[0 if under_plugin else 1]).read().replace(",", " ").split())
factor = lambda measure: types ** {grows!r}.get(measure, 0)
# Touched page by page, so that the memory is resident.
held = bytearray({allocates!r} * factor("memory") + (0 if os.environ.get("MALLOC_ARENA_MAX") == "1" else {allocates_without_one_arena!r}))
for index in range(0, len(held), 4096):
    held[index] = 1
time.sleep({sleep!r} * factor("time"))
if under_plugin:
    for file in ("One+SafeDI.swift", "Two+SafeDI.swift"):
        open(open(option("--swift-manifest")).read() + "/" + file, "w").write("// generated\\n" * factor("code"))
else:
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

    def expect(name, base, head, expected_failures, expected_row, expected_size_row=None, memory_limit=1.3, large_memory_shapes=frozenset(), large_memory_runs=3, accepted_sizes={}, one_arena_only_shapes=frozenset()):
        rows, size_rows, found = compare(base, head, f"{directory}/{name}", ["E16-seam"], 3, 2.0, memory_limit, 2.0, large_memory_shapes=large_memory_shapes, large_memory_runs=large_memory_runs, accepted_sizes=accepted_sizes, one_arena_only_shapes=one_arena_only_shapes)
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
    # A shape judged with one arena alone: more in the timed runs alone passes, however much, and more with one arena
    # fails at the ordinary limit, not the tighter one.
    expect("twice-the-memory-without-one-arena-of-a-one-arena-shape", held, tool("holds-twice-in-arenas", 0.0, allocates=64 * 1024 * 1024, allocates_without_one_arena=64 * 1024 * 1024), 0, "within the limits", one_arena_only_shapes=frozenset(["E16-seam"]))
    expect("a-fifth-more-with-one-arena-of-a-one-arena-shape", held, holds_more, 0, ", the figure compared", one_arena_only_shapes=frozenset(["E16-seam"]))
    expect("half-more-with-one-arena-of-a-one-arena-shape", held, tool("holds-half-more", 0.0, allocates=96 * 1024 * 1024), 1, "**memory over the limit**", one_arena_only_shapes=frozenset(["E16-seam"]))
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

    def expect_growth_under_plugin(name, head, expected_failures, expected_row, time_limit=GROWTH_TIME_LIMIT_SECONDS):
        rows, found = grow(head, f"{directory}/{name}", {"P": (shape_p, (4, 7), {}, lambda layers: "App")}, 3, 2.0, time_limit=time_limit)
        if len(found) != expected_failures or expected_row not in rows[0]:
            failures.append(f"{name}: expected {expected_failures} failure(s) and a growth row with {expected_row!r}, got {found} and {rows}")

    # As the SwiftPM plugin generates, `App` alone is generated, from its own two types and `Feature`'s, 27 at 4
    # layers and 45 at 7, 1.67 times as many: their cube is 4.63 times. A module writes no `.safedi` file, and its
    # code is every file of its output directory.
    expect_growth_under_plugin("growth-under-the-plugin-none", fast, 0, "| P | 4 and 7 |")
    expect_growth_under_plugin("growth-under-the-plugin-of-time-with-the-types", tool("linear-time-under-the-plugin", 0.005, grows={"time": 1}), 0, "within the limits")
    expect_growth_under_plugin("growth-under-the-plugin-of-time-with-their-cube", tool("cubic-time-under-the-plugin", 0.00001, grows={"time": 3}), 1, "**time over the limit**")
    expect_growth_under_plugin("growth-under-the-plugin-of-size", tool("cubic-size-under-the-plugin", 0.0, module_info_size=1, grows={"size": 3}), 0, "| 0 bytes, 0 bytes, 1.00 |")
    expect_growth_under_plugin("growth-under-the-plugin-of-code-with-the-types", tool("linear-code-under-the-plugin", 0.0, grows={"code": 1}), 0, "| 702 bytes, 1170 bytes, 1.67 |")
    expect_growth_under_plugin("growth-under-the-plugin-of-code-with-their-cube", tool("cubic-code-under-the-plugin", 0.0, grows={"code": 3}), 1, "**code over the limit**")
    expect_growth_under_plugin("growth-under-the-plugin-scan-refused", tool("scan-refuses", 0.0, refuses=True), 1, "**failed**")
    expect_growth_under_plugin("growth-under-the-plugin-never-ends", tool("never-ends-under-the-plugin", 30.0), 1, "**failed**", time_limit=1)
    for row, parts in GROWTH_ROWS.items():
        build, (fewer, more), row_limits, timed_module = row_parts(parts)
        if not set(row_limits) <= {"time", "memory", "size", "code"}:
            failures.append(f"growth row {row} limits {sorted(row_limits)}, which are not all measures")
        for module, dependencies, _ in build(fewer):
            if not all(dependency in [earlier for earlier, _, _ in build(fewer)] for dependency in dependencies):
                failures.append(f"growth row {row}: module {module} depends on a module the shape does not have")
        if sum(len(source) for _, _, source in build(more)) <= sum(len(source) for _, _, source in build(fewer)):
            failures.append(f"growth row {row}: the shape is no larger at {more} layers than at {fewer}")
        for layers in (fewer, more):
            if timed_module and timed_module(layers) not in [module for module, _, _ in build(layers)]:
                failures.append(f"growth row {row}: at {layers} layers the shape has no module {timed_module(layers)} to generate as the SwiftPM plugin does")
    # The lifelike chain's row times `F4` of five features and `F9` of ten as one chain's modules at two heights.
    if shape_lifelike_chain(10)[:6] != shape_lifelike_chain(5)[:6]:
        failures.append("the lifelike chain of ten features does not start with the modules of the chain of five")
    for shape, accepted in ACCEPTED_MODULE_INFO_BYTES.items():
        if shape not in SHAPES or not set(accepted) <= {name for name, _, _ in SHAPES[shape]()}:
            failures.append(f"the accepted sizes name {shape} {sorted(accepted)}, which are not a shape and its modules")
    if not LARGE_MEMORY_SHAPES <= set(SHAPES):
        failures.append(f"the large shapes name {sorted(LARGE_MEMORY_SHAPES - set(SHAPES))}, which are not shapes")
    if not ONE_ARENA_ONLY_SHAPES <= set(SHAPES):
        failures.append(f"the shapes judged with one arena alone name {sorted(ONE_ARENA_ONLY_SHAPES - set(SHAPES))}, which are not shapes")
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
