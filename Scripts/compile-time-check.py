#!/usr/bin/env python3
"""Usage: compile-time-check.py [--runs N] [--limit RATIO] [--line-limit RATIO] [--shapes NAME,…] [--optimizations Onone,O]
                             [--timeout SECONDS] [--compile-every-shape] [--base-build DIRECTORY] [--swiftc PATH]
                             [--summary FILE]
                             BASE_TOOL HEAD_TOOL BUILD DIRECTORY
       compile-time-check.py --lines [--baseline FILE] [--write-baseline] [--summary FILE] TOOL DIRECTORY
       compile-time-check.py --self-test DIRECTORY

Compares what two builds of `SafeDITool` generate for wide dependency graphs by what it costs to compile: the number
of lines generated, and the time `swiftc` takes to compile each module with its generated file. It exits 1 when, for
any module of any shape, the head tool's code is LINE-LIMIT (default 1.25) times the base tool's in lines, or takes
RATIO (default 1.5) times as long to compile. Each module is compared by itself, because a regression in the module
that holds a wide scope disappears in a sum with the module that holds its two hundred screens. `generate-time-check.py` times `generate` alone, which is how generated code that compiled
2.4 times slower was once taken for no regression.

It is run by hand, or by a lane, against main's tool before a change to what seams or builders emit lands; it is not
part of every pull request, because one row is minutes of compiler time.

BUILD is the directory of a debug build of this package made with `--traits sourceBuild` (`swift build --show-bin-path`):
it holds the `SafeDI` module and the macro executable that both tools' code is compiled against. When the base tool's
generated code needs the SafeDI module of its own commit, name that commit's build with `--base-build`. DIRECTORY, which
must not exist, receives the shapes' sources, the generated files and the compiler's logs; keep it out of the system
temporary directory.

The shapes (every name invented; `--shapes` picks among them, default all), at 40 and at 200 screens:
  P1-40, P1-200    seam `Home`, in module `Feat`, instantiates a hundred services and then an `Instantiator` of each
                   screen; each screen is a seam of module `Screens` that instantiates three types no module beneath
                   `App` fulfills. `App` fulfills them and declares the root.
  P2-40, P2-200    the same with every screen a plain type in `Feat`, so its tree is generated inline in `Home`'s.
                   P2-200's code takes many minutes to compile, so only its lines are compared unless
                   `--compile-every-shape` is given.
  N1-40, N1-200    seam `Home`, in module `Feature`, instantiates an `Instantiator` of each screen; each screen
                   instantiates `any Api`, which `App` fulfills, and receives the builders of the three screens after
                   it, so the screens are in a loop.

How it measures: each tool generates each shape once, and the generated files' lines are counted, which has no noise.
Then, for each optimization level (default `-Onone` and `-O`, whole-module), N (default 3) compiles of each tool's
output, alternating base and head. The figure compared is each module's median CPU time (user and system, of the
compiler and its children), because wall time on a loaded machine varies by half between two runs of the same code;
wall time is printed beside it. A module for which neither tool generates a hundred lines is not compared. A compile that takes longer than SECONDS (default 600) is stopped: when both tools' code is
stopped the row is not compared on time, and when only the head's is, the row fails. A module fails on time only
when the head's median is also more than a second above the base's.

A shape the base tool cannot generate is reported and not compared. A shape the head tool cannot generate, or whose
generated code does not compile, fails the check. So does a shape whose base code does not compile, which is what a
missing or wrong `--base-build` looks like, and so does a run that compared nothing: a check that measured nothing has
not passed.

Exit status: 0 no shape at or over a limit; 1 one is, the head failed on one, the base's code did not compile, or
nothing was compared; 2 usage, or DIRECTORY exists.

--lines is the part every pull request runs ("Check Generate Time on Linux"): TOOL generates every shape, nothing is
compiled, and each module's generated lines are compared with the number recorded for it in FILE (default
`compile-time-baseline.txt` beside this script). Lines have no noise, so the limit is tight: it exits 1 when a module's
lines are more than 5% over its baseline, printing every shape's lines beside its baseline with the percentage. It also
exits 1 when they are more than 5% under, so that a gain is recorded and cannot be given back unnoticed, and when the
file and the shapes do not name the same modules. A change that means to move a number runs it with `--write-baseline`,
which rewrites FILE's numbers from TOOL, the tool of the commit under test, keeping the file's comments, and commits
the file: the growth is then a line of the pull request's diff, with its reason in a comment above it.

--self-test DIRECTORY runs the comparison with stand-in tools and a stand-in compiler and checks each verdict above.
"""
import importlib.util
import os
import resource
import signal
import statistics
import subprocess
import sys
import time

NOISE_FLOOR_SECONDS = 1.0
SMALLEST_MEASURED_LINES = 100

_specification = importlib.util.spec_from_file_location("generate_time_check", os.path.join(os.path.dirname(os.path.abspath(__file__)), "generate-time-check.py"))
generate_time_check = importlib.util.module_from_spec(_specification)
_specification.loader.exec_module(generate_time_check)
write = generate_time_check.write
Failure = generate_time_check.Failure


# MARK: Shapes


def declaration(name, properties, attribute="@Instantiable"):
    """One `@Instantiable` class whose initializer takes and stores `properties`, each "<macro> let <label>: <type>"."""
    if not properties:
        return f"{attribute}\npublic final class {name}: Instantiable {{\n    public init() {{}}\n}}\n"
    parameters = [property_.split(" let ")[1] for property_ in properties]
    assignments = "\n".join(f"        self.{label} = {label}" for label in (parameter.split(":")[0] for parameter in parameters))
    stored = "\n".join(f"    {property_}" for property_ in properties)
    return f"{attribute}\npublic final class {name}: Instantiable {{\n    public init({', '.join(parameters)}) {{\n{assignments}\n    }}\n\n{stored}\n}}\n"


SEAM = "@Instantiable(generateDependencyTree: true)"
CONFIGURATION = "#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n\n"


def shape_wide(screens, screens_are_seams, services=100, holes=3):
    """P1 and P2. Returns the shape's modules, in build order: (name, the modules it depends on, its source)."""
    core = "import SafeDI\n\n" + "\n".join(declaration(f"Service{service}", []) for service in range(services)) + "\n"
    core += "\n".join(f"public protocol Hole{hole} {{}}" for hole in range(holes)) + "\n"
    attribute = SEAM if screens_are_seams else "@Instantiable"
    screen_text = "\n".join(declaration(f"Screen{screen}", [f"@Instantiated let hole{hole}: any Hole{hole}" for hole in range(holes)], attribute) for screen in range(screens))
    home = declaration("Home", [f"@Instantiated let service{service}: Service{service}" for service in range(services)]
                       + [f"@Instantiated let screen{screen}Builder: Instantiator<Screen{screen}>" for screen in range(screens)], SEAM)
    app = "\n".join(f"@Instantiable(fulfillingAdditionalTypes: [Hole{hole}.self])\npublic final class Live{hole}: Hole{hole}, Instantiable {{\n    public init() {{}}\n}}\n" for hole in range(holes))
    app += "\n" + declaration("Root", ["@Instantiated let home: Home"], "@Instantiable(isRoot: true)")
    if screens_are_seams:
        return [("Core", [], core),
                ("Screens", ["Core"], "import Core\nimport SafeDI\n\n" + CONFIGURATION + screen_text),
                ("Feat", ["Core", "Screens"], "import Core\nimport SafeDI\nimport Screens\n\n" + CONFIGURATION + home),
                ("App", ["Core", "Screens", "Feat"], "import Core\nimport Feat\nimport SafeDI\nimport Screens\n\n" + app)]
    else:
        return [("Core", [], core),
                ("Feat", ["Core"], "import Core\nimport SafeDI\n\n" + CONFIGURATION + screen_text + "\n" + home),
                ("App", ["Core", "Feat"], "import Core\nimport Feat\nimport SafeDI\n\n" + app)]


def shape_loop(screens):
    """N1."""
    feature = "import SafeDI\n\npublic protocol Api {}\n\n"
    feature += declaration("Home", [f"@Instantiated let screen{screen}Builder: Instantiator<Screen{screen}>" for screen in range(screens)], SEAM)
    for screen in range(screens):
        received = [(screen + offset) % screens for offset in (1, 2, 3)]
        feature += "\n" + declaration(f"Screen{screen}", ["@Forwarded let id: Int", "@Instantiated let api: any Api"]
                                      + [f"@Received let screen{other}Builder: Instantiator<Screen{other}>" for other in received])
    app = "import Feature\nimport SafeDI\n\n@Instantiable(fulfillingAdditionalTypes: [Api.self])\npublic final class DefaultApi: Api, Instantiable {\n    public init() {}\n}\n\n"
    app += declaration("Root", ["@Instantiated let home: Home"], "@Instantiable(isRoot: true)")
    return [("Feature", [], feature), ("App", ["Feature"], app)]


# Each shape, and whether its code is compiled unless `--compile-every-shape` is given.
SHAPES = {
    "P1-40": (lambda: shape_wide(40, screens_are_seams=True), True),
    "P1-200": (lambda: shape_wide(200, screens_are_seams=True), True),
    "P2-40": (lambda: shape_wide(40, screens_are_seams=False), True),
    "P2-200": (lambda: shape_wide(200, screens_are_seams=False), False),
    "N1-40": (lambda: shape_loop(40), True),
    "N1-200": (lambda: shape_loop(200), True),
}


# MARK: Compiling


class Stopped(Exception):
    pass


def build_products(build):
    """Returns (the module search path, the macro executable) of a build directory."""
    macros = next((path for path in (f"{build}/SafeDIMacros-tool", f"{build}/SafeDIMacros-tool.exe", f"{build}/SafeDIMacros") if os.path.isfile(path)), None)
    if macros is None:
        raise Failure(f"no SafeDIMacros executable in {build}")
    modules = f"{build}/Modules" if os.path.exists(f"{build}/Modules/SafeDI.swiftmodule") else build
    return modules, macros


def compile_modules(swiftc, build, modules, sources, generated, output, optimization, timeout):
    """Compiles each module with its generated file; returns each module's (wall seconds, CPU seconds), by name."""
    os.makedirs(output, exist_ok=True)
    search_path, macros = build_products(build)
    times = {}
    for name, _, _ in modules:
        command = [swiftc, "-emit-object", "-whole-module-optimization", "-parse-as-library", f"-{optimization}",
                   "-o", f"{output}/{name}.o", "-module-name", name, "-package-name", "GenerateTimeCheck",
                   "-emit-module", "-emit-module-path", f"{output}/{name}.swiftmodule", "-I", search_path, "-I", output,
                   "-load-plugin-executable", f"{macros}#SafeDIMacros", "-swift-version", "6", "-D", "DEBUG",
                   f"{sources}/{name}/Types.swift", f"{generated}/{name}.generated.swift"]
        with open(f"{output}/{name}.log", "wb") as log:
            before = resource.getrusage(resource.RUSAGE_CHILDREN)
            started = time.monotonic()
            # A session of its own, so that stopping the driver stops the frontends it started.
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True, env=dict(os.environ, TMPDIR=output))
            try:
                process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                raise Stopped(f"compiling module {name} at -{optimization} was stopped after {timeout:g} s")
            wall = time.monotonic() - started
            after = resource.getrusage(resource.RUSAGE_CHILDREN)
        times[name] = (wall, (after.ru_utime - before.ru_utime) + (after.ru_stime - before.ru_stime))
        if process.returncode != 0:
            with open(f"{output}/{name}.log", errors="replace") as log:
                raise Failure(f"module {name} did not compile at -{optimization} (exit {process.returncode}): {log.read().strip()[-1500:]}")
    return times


def line_counts(modules, generated):
    counts = {}
    for name, _, _ in modules:
        with open(f"{generated}/{name}.generated.swift") as handle:
            counts[name] = sum(1 for _ in handle)
    return counts


# MARK: Comparing


def compare(tools, builds, swiftc, directory, shapes, runs, limit, line_limit, optimizations, timeout, compile_every_shape=False):
    """Returns (the table's rows, the failures). `tools` and `builds` are keyed "base" and "head"."""
    rows = []
    failures = []
    for shape in shapes:
        build_shape, compiled = SHAPES[shape]
        modules = build_shape()
        sources = f"{directory}/{shape}/sources"
        for name, _, source in modules:
            write(f"{sources}/{name}/Types.swift", source)
        generated = {label: f"{directory}/{shape}/{label}-generated" for label in ("base", "head")}
        try:
            for label in ("base", "head"):
                generate_time_check.generate(tools[label], modules, sources, generated[label])
        except Failure as failure:
            if label == "base":
                rows.append(f"| {shape} | | | did not generate | | | not compared |")
                print(f"{shape}: the base tool did not generate it, so it is not compared: {failure}", flush=True)
                try:
                    generate_time_check.generate(tools["head"], modules, sources, generated["head"])
                except Failure as head_failure:
                    failures.append(f"{shape}: the head tool did not generate it: {head_failure}")
            else:
                rows.append(f"| {shape} | | | | did not generate | | **failed** |")
                failures.append(f"{shape}: the head tool did not generate it: {failure}")
            continue
        lines = {label: line_counts(modules, generated[label]) for label in ("base", "head")}
        # A module with next to nothing generated says nothing about the generator.
        measured = [name for name, _, _ in modules if max(lines["base"][name], lines["head"][name]) >= SMALLEST_MEASURED_LINES]
        for name in measured:
            line_ratio = lines["head"][name] / max(lines["base"][name], 1)
            lines_over = line_ratio >= line_limit
            if lines_over:
                failures.append(f"{shape}, module {name}: the head tool generated {line_ratio:.2f} times the base tool's lines ({lines['head'][name]} against {lines['base'][name]}); the limit is {line_limit:g}")
            rows.append(f"| {shape} | {name} | lines | {lines['base'][name]} | {lines['head'][name]} | {line_ratio:.2f} | {'**over the limit**' if lines_over else 'within the limit'} |")
            print(f"{shape} {name}: lines base {lines['base'][name]}, head {lines['head'][name]}, ratio {line_ratio:.2f}", flush=True)
        for optimization in optimizations if compiled or compile_every_shape else []:
            samples = {"base": [], "head": []}
            stopped = {}
            failed = None
            for run in range(runs):
                for label in ("base", "head"):
                    if label in stopped:
                        continue
                    try:
                        samples[label].append(compile_modules(swiftc, builds[label], modules, sources, generated[label], f"{directory}/{shape}/{label}-{optimization}-{run}", optimization, timeout))
                    except Stopped as stop:
                        stopped[label] = str(stop)
                    except Failure as failure:
                        failed = (label, failure)
                        break
                if failed:
                    break
            if failed:
                label, failure = failed
                if label == "head":
                    failures.append(f"{shape}: the head tool's code did not compile: {failure}")
                    rows.append(f"| {shape} | | -{optimization} | | did not compile | | **failed** |")
                else:
                    failures.append(f"{shape}: the base tool's code did not compile at -{optimization}, so nothing was compared (does `--base-build` name the base commit's build?): {failure}")
                    rows.append(f"| {shape} | | -{optimization} | did not compile | | | **not compared** |")
                continue
            if stopped:
                figure = lambda label: f"over {timeout:g} s" if label in stopped else "compiled"
                if "head" in stopped and "base" not in stopped:
                    failures.append(f"{shape}: {stopped['head']}, and the base tool's code compiled")
                    rows.append(f"| {shape} | | -{optimization} | {figure('base')} | {figure('head')} | | **over the limit** |")
                else:
                    rows.append(f"| {shape} | | -{optimization} | {figure('base')} | {figure('head')} | | not compared |")
                print(f"{shape} -{optimization}: base {figure('base')}, head {figure('head')}", flush=True)
                continue
            for name in measured:
                median = {label: (statistics.median(times[name][0] for times in values), statistics.median(times[name][1] for times in values)) for label, values in samples.items()}
                figure = lambda label: f"{median[label][0]:.1f} s / {median[label][1]:.1f} s"
                ratio = median["head"][1] / max(median["base"][1], 0.001)
                over = ratio >= limit and median["head"][1] - median["base"][1] > NOISE_FLOOR_SECONDS
                if over:
                    failures.append(f"{shape}, module {name}: the head tool's code took {ratio:.2f} times as long to compile at -{optimization} ({median['head'][1]:.1f} s against {median['base'][1]:.1f} s of CPU, median of {runs}); the limit is {limit:g}")
                rows.append(f"| {shape} | {name} | -{optimization} | {figure('base')} | {figure('head')} | {ratio:.2f} | {'**over the limit**' if over else 'within the limit'} |")
                print(f"{shape} {name} -{optimization}: base {figure('base')}, head {figure('head')} (wall / CPU), ratio {ratio:.2f}", flush=True)
    if not failures and not any(row.endswith(("| within the limit |", "| **over the limit** |")) for row in rows):
        failures.append("nothing was compared, so the check has not passed")
    return rows, failures


# MARK: Lines against a baseline

LINES_TOLERANCE = 0.05


def read_baseline(path):
    """Returns ({(shape, module): lines}, {(shape, module): the comment lines above it}, the comment lines after the last entry)."""
    counts, comments, pending = {}, {}, []
    with open(path) as handle:
        for line in handle.read().splitlines():
            fields = line.split()
            if not fields or fields[0].startswith("#"):
                pending.append(line)
            elif len(fields) == 3 and fields[2].isdigit() and (fields[0], fields[1]) not in counts:
                counts[(fields[0], fields[1])] = int(fields[2])
                comments[(fields[0], fields[1])] = pending
                pending = []
            else:
                raise Failure(f"{path}: not `SHAPE MODULE LINES`, or a module named twice: {line!r}")
    return counts, comments, pending


def generated_lines(tool, directory):
    """Returns {(shape, module): lines} for every module of every shape for which TOOL generates a hundred lines."""
    counts = {}
    for shape, (build_shape, _) in SHAPES.items():
        modules = build_shape()
        sources = f"{directory}/{shape}/sources"
        for name, _, source in modules:
            write(f"{sources}/{name}/Types.swift", source)
        generate_time_check.generate(tool, modules, sources, f"{directory}/{shape}/generated")
        for name, lines in line_counts(modules, f"{directory}/{shape}/generated").items():
            if lines >= SMALLEST_MEASURED_LINES:
                counts[(shape, name)] = lines
    return counts


def check_lines(tool, directory, baseline, write_baseline, summary):
    counts = generated_lines(tool, directory)
    if write_baseline:
        _, comments, trailing = read_baseline(baseline) if os.path.exists(baseline) else ({}, {}, [])
        text = []
        if not comments:
            # A file of comments alone is a heading.
            text, trailing = trailing, []
        for key, lines in counts.items():
            text += comments.get(key, []) + [f"{key[0]} {key[1]} {lines}"]
        with open(baseline, "w") as handle:
            handle.write("\n".join(text + trailing) + "\n")
        print(f"wrote {len(counts)} modules' lines to {baseline}")
        return 0
    recorded, _, _ = read_baseline(baseline)
    rows, failures = [], []
    for key in list(recorded) + [key for key in counts if key not in recorded]:
        shape, name = key
        if key not in counts:
            failures.append(f"{shape}, module {name}: the baseline records {recorded[key]} lines, and the tool generates under {SMALLEST_MEASURED_LINES} or the shape has no such module")
            rows.append(f"| {shape} | {name} | {recorded[key]} | | | **not generated** |")
        elif key not in recorded:
            failures.append(f"{shape}, module {name}: the tool generates {counts[key]} lines, and the baseline records none")
            rows.append(f"| {shape} | {name} | | {counts[key]} | | **not in the baseline** |")
        else:
            change = counts[key] / recorded[key] - 1
            verdict = "within 5%"
            if change > LINES_TOLERANCE:
                verdict = "**over the baseline**"
                failures.append(f"{shape}, module {name}: {counts[key]} lines generated against a baseline of {recorded[key]} ({change:+.1%})")
            elif change < -LINES_TOLERANCE:
                verdict = "**under the baseline: record the gain**"
                failures.append(f"{shape}, module {name}: {counts[key]} lines generated against a baseline of {recorded[key]} ({change:+.1%}); record the gain")
            rows.append(f"| {shape} | {name} | {recorded[key]} | {counts[key]} | {change:+.1%} | {verdict} |")
    lines = ["Lines of generated code for each wide shape, against the baseline (a module fails more than 5% from it).", "",
             "| Shape | Module | Baseline | Generated | Change | Verdict |", "|---|---|---|---|---|---|"] + rows + [""] + [f"- {failure}" for failure in failures]
    if failures:
        lines += ["", f"If the change is meant, rewrite the baseline with this commit's tool (`compile-time-check.py --lines --write-baseline TOOL DIRECTORY`), say why in a comment above the number, and commit {os.path.basename(baseline)}."]
    text = "\n".join(lines) + "\n"
    print(text)
    if summary:
        with open(summary, "a") as handle:
            handle.write(text)
    return 1 if failures else 0


def report(rows, failures, runs, limit, line_limit, summary):
    lines = [f"Compile cost of generated code, head against base: lines generated (a shape fails at {line_limit:g} times the base's), and `swiftc`'s time over each module with its generated file, median of {runs} alternating runs (a shape fails at {limit:g} times the base's CPU time).", "",
             "| Shape | Module | Measure | Base (wall / CPU) | Head (wall / CPU) | Head / base | Verdict |", "|---|---|---|---|---|---|---|"] + rows
    lines += [""] + [f"- {failure}" for failure in failures]
    text = "\n".join(lines) + "\n"
    print(text)
    if summary:
        with open(summary, "a") as handle:
            handle.write(text)


# MARK: Self-test


STAND_IN_TOOL = """#!/usr/bin/env python3
import sys
arguments = sys.argv[1:]
option = lambda name: arguments[arguments.index(name) + 1]
if {refuses!r} and option("--module-name") == "App":
    sys.exit("stand-in: refused")
lines = {{"Feat": {feat!r}, "Core": 5}}.get(option("--module-name"), {lines!r})
open(option("--combined-output"), "w").write("// generated\\n" * lines)
open(option("--module-info-output"), "w").write("")
"""

# Computes for a ten-thousandth of a second for each line of the generated file, and fails on a file of exactly 130
# lines. It computes and does not sleep, because the check compares CPU time.
STAND_IN_COMPILER = """#!/usr/bin/env python3
import sys, time
lines = sum(1 for _ in open(sys.argv[-1]))
if lines == 130:
    sys.exit("stand-in: does not compile")
while time.process_time() < lines / 10000:
    pass
"""


def self_test(directory):
    failures = []

    def executable(name, text):
        path = f"{directory}/tools/{name}"
        write(path, text)
        os.chmod(path, 0o755)
        return path

    def tool(name, feat, lines=100, refuses=False):
        """A tool that generates `feat` lines for module `Feat`, 5 for `Core` and `lines` for every other module."""
        return executable(name, STAND_IN_TOOL.format(feat=feat, lines=lines, refuses=refuses))

    swiftc = executable("swiftc", STAND_IN_COMPILER)
    build = f"{directory}/build"
    write(f"{build}/SafeDIMacros-tool", "")
    write(f"{build}/Modules/SafeDI.swiftmodule", "")

    def expect(name, base, head, expected_failures, expected_rows, floor=0.05, timeout=30):
        """`expected_rows`: for each row of the table in order, text it holds. P1-40's modules are Core, Screens, Feat, App."""
        global NOISE_FLOOR_SECONDS
        saved = NOISE_FLOOR_SECONDS
        NOISE_FLOOR_SECONDS = floor
        try:
            rows, found = compare({"base": base, "head": head}, {"base": build, "head": build}, swiftc, f"{directory}/{name}", ["P1-40"], 3, 1.5, 1.25, ["Onone"], timeout)
        finally:
            NOISE_FLOOR_SECONDS = saved
        if len(found) != expected_failures or len(rows) != len(expected_rows) or any(expected not in row for expected, row in zip(expected_rows, rows)):
            failures.append(f"{name}: expected {expected_failures} failure(s) and rows with {expected_rows!r}, got {found} and {rows}")

    within = "within the limit"
    over = "**over the limit**"
    # Core, at 5 lines, is never a row: three modules' lines, then three modules' times.
    same = tool("same", 100)
    expect("same", same, same, 0, ["| Screens | lines", "| Feat | lines", "| App | lines", "| Screens | -Onone", "| Feat | -Onone", "| App | -Onone"])
    expect("slightly-longer", same, tool("slightly-longer", 120), 0, [within] * 6)
    # Feat alone grows fourfold, among 5,000 lines of Screens and of App that would hide it in a sum.
    wide = tool("wide", 400, lines=5000)
    wider = tool("wider", 1600, lines=5000)
    expect("one-module-longer", wide, wider, 2, [within, "| Feat | lines | 400 | 1600 | 4.00 | " + over, within, within, "| Feat | -Onone", within])
    expect("one-module-longer-rows", wide, wider, 2, [within, over, within, within, over, within])
    # The same times under a floor of ten seconds fail on lines alone.
    expect("under-the-floor", wide, tool("wider-again", 1600, lines=5000), 1, [within, over, within, within, within, within], floor=10.0)
    expect("shorter", wider, wide, 0, [within] * 6)
    expect("head-does-not-compile", same, tool("does-not-compile", 130), 2, [within, over, within, "**failed**"])
    expect("base-does-not-compile", tool("base-does-not-compile", 130), same, 1, [within, within, within, "**not compared**"])
    expect("head-refuses", same, tool("head-refuses", 100, refuses=True), 1, ["**failed**"])
    # The one shape of this run was not compared, so the run compared nothing.
    expect("base-refuses", tool("base-refuses", 100, refuses=True), same, 1, ["not compared"])
    # 20,000 lines compute for two seconds, over a limit of one.
    slow = tool("slow", 20000)
    expect("head-stopped", same, slow, 2, [within, over, within, over], timeout=1)
    expect("both-stopped", slow, tool("slow-too", 20000), 0, [within, within, within, "not compared"], timeout=1)
    # Lines against a baseline: written by one tool, read back, then compared with tools 4% and 6% away each way.
    baseline = f"{directory}/baseline.txt"
    write(baseline, "# kept: heading\n")
    check_lines(tool("heading", 100), f"{directory}/lines-heading", baseline, True, None)
    with open(baseline) as handle:
        if not handle.read().startswith("# kept: heading\nP1-40 Screens 100\n"):
            failures.append("lines: a baseline of comments alone did not keep them as its heading")
    write(baseline, "# kept: heading\n# kept: above Feat\nP1-40 Feat 1\n# kept: last\n")
    recorded = tool("recorded", 1000, lines=200)
    if check_lines(recorded, f"{directory}/lines-write", baseline, True, None) != 0:
        failures.append("lines: writing the baseline failed")
    with open(baseline) as handle:
        written = handle.read()
    if "# kept: heading\n# kept: above Feat\nP1-40 Feat 1000\n" not in written or not written.endswith("# kept: last\n") or "P2-200 Feat 1000" not in written or " Core " in written:
        failures.append(f"lines: the baseline written is {written!r}")
    for name, feat, expected in (("same", 1000, 0), ("a-little-over", 1040, 0), ("over", 1060, 1), ("a-little-under", 960, 0), ("under", 940, 1)):
        if check_lines(tool(f"lines-{name}", feat, lines=200), f"{directory}/lines-{name}", baseline, False, None) != expected:
            failures.append(f"lines: {name} did not exit {expected}")
    # A module the baseline lacks, and one the tool no longer generates a hundred lines for.
    write(baseline, "\n".join(line for line in written.splitlines() if line != "N1-40 App 200") + "\nN1-40 Gone 300\n")
    if check_lines(recorded, f"{directory}/lines-names", baseline, False, None) != 1:
        failures.append("lines: a baseline naming other modules than the shapes did not fail")
    for name, (shape, _) in SHAPES.items():
        modules = shape()
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
    options = {"--runs": "3", "--limit": "1.5", "--line-limit": "1.25", "--shapes": ",".join(SHAPES), "--optimizations": "Onone,O",
               "--timeout": "600", "--base-build": None, "--swiftc": "swiftc", "--summary": None,
               "--baseline": os.path.join(os.path.dirname(os.path.abspath(__file__)), "compile-time-baseline.txt")}
    positional = []
    self_testing = False
    compile_every_shape = False
    lines_only = False
    write_baseline = False
    while arguments:
        argument = arguments.pop(0)
        if argument == "--self-test":
            self_testing = True
        elif argument == "--lines":
            lines_only = True
        elif argument == "--write-baseline":
            write_baseline = True
        elif argument == "--compile-every-shape":
            compile_every_shape = True
        elif argument in options and arguments:
            options[argument] = arguments.pop(0)
        else:
            positional.append(argument)
    shapes = options["--shapes"].split(",")
    unknown = [shape for shape in shapes if shape not in SHAPES]
    runs = int(options["--runs"])
    if len(positional) != (1 if self_testing else 2 if lines_only else 4) or (write_baseline and not lines_only) or unknown or runs < 1:
        print(__doc__.split("\n\n")[0] + (f"\nunknown shape(s): {', '.join(unknown)}; the shapes are {', '.join(SHAPES)}" if unknown else ""), file=sys.stderr)
        return 2
    directory = os.path.abspath(positional[-1])
    if os.path.exists(directory):
        print(f"{directory} exists; the check writes a new directory", file=sys.stderr)
        return 2
    if self_testing:
        return self_test(directory)
    elif lines_only:
        try:
            return check_lines(os.path.abspath(positional[0]), directory, options["--baseline"], write_baseline, options["--summary"])
        except Failure as failure:
            print(failure, file=sys.stderr)
            return 2
    else:
        build = os.path.abspath(positional[2])
        builds = {"base": os.path.abspath(options["--base-build"]) if options["--base-build"] else build, "head": build}
        tools = {"base": os.path.abspath(positional[0]), "head": os.path.abspath(positional[1])}
        limit = float(options["--limit"])
        line_limit = float(options["--line-limit"])
        try:
            rows, failures = compare(tools, builds, options["--swiftc"], directory, shapes, runs, limit, line_limit, options["--optimizations"].split(","), float(options["--timeout"]), compile_every_shape)
        except Failure as failure:
            print(failure, file=sys.stderr)
            return 2
        report(rows, failures, runs, limit, line_limit, options["--summary"])
        return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
