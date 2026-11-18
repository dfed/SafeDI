#!/usr/bin/env python3
"""Usage: function-compile-time-check.py [--sil-limit SECONDS] [--type-check-limit SECONDS] [--waivers FILE]
                                      [--module NAME] [--demangler COMMAND] [--summary FILE] LOG
       function-compile-time-check.py --self-test DIRECTORY

Fails when the compiler spends too long on any one function of a module (default `SafeDICore`): more than SIL-LIMIT
(default 10) seconds optimizing it, summed over the optimizer's passes, or more than TYPE-CHECK-LIMIT (default 5)
seconds type-checking its body. One 646-line initializer once took 40% of SafeDICore's release compile, three minutes
of every release build, and one getter twelve seconds of every build of any kind, and nothing reported either: a
function's cost in the optimizer grows faster than its length, so the remedy is to split it, and the time to notice is
the pull request that makes it long.

LOG is the output of a release build of the module with the compiler's timers on:

    swift build -c release --traits sourceBuild --target SafeDICore -v \\
        -Xswiftc -Xfrontend -Xswiftc -debug-time-function-bodies \\
        -Xswiftc -Xllvm -Xswiftc -sil-print-pass-time -Xswiftc -Xllvm -Xswiftc -sil-min-pass-time=MILLISECONDS

The optimizer then prints each pass over a function that took MILLISECONDS or more, and the type checker every body's
time. A function's optimizer figure is therefore a lower bound: it leaves out the passes shorter than that. CI passes
20, which prints about 1,400 lines for SafeDICore. Only the module's own functions count. A specialization the optimizer makes of one, and a closure inside one, is a function of
its own here, under its own name ("generic specialization <…> of …", "closure #1 in …").

The type checker's timer names every accessor `_`, so this script reads the property's name from the source line the
timer points at, which needs LOG's paths to exist: run it in the checkout that was built. A function is printed with
its file and line; where two declarations share a name, each is a row.

FILE (default `function-compile-time-waivers.txt` beside this script) lists the functions known to be over a limit,
one a line, as `sil` or `type-check`, a ceiling in seconds, and the start of the function's name as this script prints
it (without the file and line, which move), separated by spaces; a `#` line is a comment and says why the function is
waived and what removes it. A waived function fails only over its ceiling. A waiver fails when it matches two
functions over the limit, since it then shelters one it was not written for, and when it matches nothing that takes
even half the limit, so that the list shrinks when a function is split. Between half the limit and the limit the
function is reported and the waiver kept, because a faster runner would otherwise fail an unrelated change.

The limits are several times what any other function takes, because runners differ in speed by half.

Exit status: 0 no function over its limit; 1 one is, a waiver matches nothing or too much, or LOG lacks either timer's
output for the module (a check that measured nothing has not passed); 2 usage.
"""
import collections
import os
import re
import subprocess
import sys

SIL_PASS = re.compile(r"\s*([0-9.]+) ms: \S+ #\d+(?: @(\S+))?$")
TYPE_CHECK = re.compile(r"([0-9.]+)ms\t(\S+?):(\d+):\d+\t(.*?)(?:@\S*)?$")
PROPERTY = re.compile(r"\b(?:var|let)\s+(`?\w+`?)|\b(subscript)\b")


class Failure(Exception):
    pass


def demangled(names, demangler):
    """Returns {mangled name: readable name}; the mangled name itself when the demangler cannot be run."""
    names = sorted(names)
    try:
        output = subprocess.run(demangler.split(), input="\n".join(names), capture_output=True, text=True, check=True).stdout.splitlines()
    except (OSError, subprocess.CalledProcessError):
        output = []
    if names and len(output) != len(names):
        print(f"`{demangler}` did not run, so the optimizer's functions are printed by their mangled names, which no waiver matches")
        output = names
    return dict(zip(names, output))


def accessor_name(path, line):
    """The name of the property declared at a source line, or None: the type checker's timer calls every accessor `_`."""
    try:
        with open(path, errors="replace") as handle:
            text = handle.read().splitlines()[line - 1]
    except (OSError, IndexError):
        return None
    found = PROPERTY.findall(text)
    return (found[-1][0] or found[-1][1]) if found else None


def read_times(log, module, demangler):
    """Returns ({function: seconds in the optimizer}, {(function, "File.swift:LINE"): seconds in the type checker}, the
    number of optimizer pass lines read) for the module's functions."""
    marker = f"{len(module)}{module}"
    passes = collections.Counter()
    bodies = {}
    pass_lines = 0
    with open(log, errors="replace") as handle:
        for line in handle:
            match = SIL_PASS.match(line.rstrip("\n"))
            if match:
                pass_lines += 1
                if match.group(2) and marker in match.group(2):
                    passes[match.group(2)] += float(match.group(1)) / 1000
                continue
            match = TYPE_CHECK.match(line.rstrip("\n"))
            if match and f"/Sources/{module}/" in match.group(2) and match.group(4):
                name = match.group(4)
                if name.endswith("._"):
                    name = name[:-1] + (accessor_name(match.group(2), int(match.group(3))) or "_")
                key = (name, f"{os.path.basename(match.group(2))}:{match.group(3)}")
                bodies[key] = max(bodies.get(key, 0.0), float(match.group(1)) / 1000)
    names = demangled(passes, demangler)
    optimizer = collections.Counter()
    for mangled, seconds in passes.items():
        optimizer[names[mangled]] += seconds
    return dict(optimizer), bodies, pass_lines


def read_waivers(path):
    """Returns [(kind, ceiling, the start of a name)]."""
    waivers = []
    if os.path.exists(path):
        with open(path) as handle:
            for line in handle.read().splitlines():
                if not line.strip() or line.lstrip().startswith("#"):
                    continue
                fields = line.split(None, 2)
                try:
                    if len(fields) != 3 or fields[0] not in ("sil", "type-check"):
                        raise ValueError
                    waivers.append((fields[0], float(fields[1]), fields[2].strip()))
                except ValueError:
                    raise Failure(f"{path}: not `sil` or `type-check`, a ceiling in seconds and the start of a name: {line!r}")
    return waivers


def check(log, module, limits, waivers, demangler):
    """Returns (the table's rows, the failures, the notes). `limits` is keyed "sil" and "type-check"."""
    optimizer, bodies, pass_lines = read_times(log, module, demangler)
    if not bodies:
        return [], [f"{log} holds no type-checking time of a function of {module}: was the module compiled, with `-debug-time-function-bodies`?"], []
    if not pass_lines:
        return [], [f"{log} holds no optimizer pass time: were `-sil-print-pass-time` and `-sil-min-pass-time` passed to a release build?"], []
    # Each entry: (the name a waiver matches, the name printed, seconds).
    times = {"sil": [(name, name, seconds) for name, seconds in optimizer.items()],
             "type-check": [(name, f"{name} ({place})", seconds) for (name, place), seconds in bodies.items()]}
    measure = {"sil": "optimizing", "type-check": "type-checking"}
    rows, failures, notes = [], [], []
    for kind in ("sil", "type-check"):
        entries = sorted(times[kind], key=lambda entry: (-entry[2], entry[1]))
        covered = {waiver: [entry for entry in entries if entry[0].startswith(waiver[2])] for waiver in waivers if waiver[0] == kind}
        for name, printed, seconds in entries:
            if seconds <= limits[kind]:
                continue
            matching = [waiver for waiver, covers in covered.items() if (name, printed, seconds) in covers]
            if not matching:
                failures.append(f"{seconds:.1f} s {measure[kind]} `{printed}`; the limit for one function is {limits[kind]:g} s. Split it.")
                rows.append(f"| {measure[kind]} | `{printed}` | {seconds:.1f} s | {limits[kind]:g} s | **over the limit** |")
            else:
                ceiling = min(ceiling for _, ceiling, _ in matching)
                if seconds > ceiling:
                    failures.append(f"{seconds:.1f} s {measure[kind]} `{printed}`, which is waived up to {ceiling:g} s: it grew")
                    rows.append(f"| {measure[kind]} | `{printed}` | {seconds:.1f} s | waived to {ceiling:g} s | **over its waiver** |")
                else:
                    rows.append(f"| {measure[kind]} | `{printed}` | {seconds:.1f} s | waived to {ceiling:g} s | waived |")
        for waiver, covers in covered.items():
            text = f"`{waiver[0]} {waiver[1]:g} {waiver[2]}`"
            over = [entry for entry in covers if entry[2] > limits[kind]]
            if len(over) > 1:
                failures.append(f"the waiver {text} matches {len(over)} functions over the limit ({', '.join(f'`{entry[1]}`' for entry in over)}): a waiver names one function")
            elif not over:
                near = [entry for entry in covers if entry[2] > limits[kind] / 2]
                if near:
                    notes.append(f"the waiver {text} was not needed on this run: `{near[0][1]}` took {near[0][2]:.1f} s, under the limit of {limits[kind]:g} s but over half of it, so the waiver stays")
                else:
                    failures.append(f"the waiver {text} matches no function that takes even half the limit: remove it")
        within = [(seconds, printed) for _, printed, seconds in entries if seconds <= limits[kind]]
        if within:
            seconds, printed = max(within)
            rows.append(f"| {measure[kind]} | `{printed}` (the longest within the limit) | {seconds:.1f} s | {limits[kind]:g} s | within the limit |")
    return rows, failures, notes


def report(rows, failures, notes, module, summary):
    lines = [f"The compiler's time on single functions of {module}, release build.", "",
             "| Measure | Function | Time | Limit | Verdict |", "|---|---|---|---|---|"] + rows + [""] + [f"- {failure}" for failure in failures] + [f"- Note: {note}" for note in notes]
    text = "\n".join(lines) + "\n"
    print(text)
    if summary:
        with open(summary, "a") as handle:
            handle.write(text)


# MARK: Self-test


def self_test(directory):
    failures = []
    os.makedirs(f"{directory}/Sources/SafeDICore")
    with open(f"{directory}/Sources/SafeDICore/File.swift", "w") as handle:
        handle.write("enum Errors {\n\tvar first: Int { 1 }\n\tvar second: Int { 2 }\n\tfunc long() {}\n}\n")
    body = lambda seconds, name, line=4, module="SafeDICore", kind="instance method": f"{seconds * 1000:.2f}ms\t{directory}/Sources/{module}/File.swift:{line}:5\t{kind} {module}.(file).Errors.{name}@{directory}/Sources/{module}/File.swift:{line}:5\n"
    getter = lambda seconds, line: body(seconds, "_", line=line, kind="getter")
    sil = lambda seconds, name, module="10SafeDICore": f"  {seconds * 1000:.3f} ms: sil-combine #12 @$s{module}{len(name)}{name}\n"
    module_pass = "  900.000 ms: loadable-address #8501\n"
    quiet = body(0.3, "quiet()") + sil(0.4, "quiet") + module_pass + "unrelated output\n"
    # Another module's functions never count.
    quiet += body(60, "other()", module="SwiftSyntax") + sil(60, "other", module="11SwiftSyntax")

    def expect(name, log, waivers, expected_failures, expected_rows, expected_notes=0):
        path = f"{directory}/{name}.log"
        with open(path, "w") as handle:
            handle.write(log)
        waiver_path = f"{directory}/{name}.waivers"
        with open(waiver_path, "w") as handle:
            handle.write(waivers)
        # No demangler: the stand-in names are not mangled names.
        rows, found, notes = check(path, "SafeDICore", {"sil": 10.0, "type-check": 5.0}, read_waivers(waiver_path), "no-such-demangler")
        if len(found) != expected_failures or len(notes) != expected_notes or len(rows) != len(expected_rows) or any(expected not in row for expected, row in zip(expected_rows, rows)):
            failures.append(f"{name}: expected {expected_failures} failure(s), {expected_notes} note(s) and rows with {expected_rows!r}, got {found}, {notes} and {rows}")

    within = "within the limit"
    expect("quiet", quiet, "", 0, ["0.4 s | 10 s | " + within, "0.3 s | 5 s | " + within])
    # Six passes of two seconds over one function are twelve seconds of it.
    expect("slow-to-optimize", quiet + sil(2, "long") * 6, "", 1, ["12.0 s | 10 s | **over the limit**", within, within])
    expect("slow-to-type-check", quiet + body(6, "long()"), "", 1, [within, "`instance method SafeDICore.(file).Errors.long() (File.swift:4)` | 6.0 s | 5 s | **over the limit**", within])
    waivers = "# why\nsil 20 $s10SafeDICore4long\ntype-check 8 instance method SafeDICore.(file).Errors.long()\n"
    both = quiet + sil(2, "long") * 6 + body(6, "long()")
    expect("waived", both, waivers, 0, ["| waived |", within, "| waived |", within])
    expect("over-its-waiver", quiet + sil(3, "long") * 7 + body(9, "long()"), waivers, 2, ["**over its waiver**", within, "**over its waiver**", within])
    # The functions were split: both waivers must go.
    expect("waiver-unused", quiet, waivers, 2, [within, within])
    # A faster runner: over half the limit, so the waivers stay and nothing fails.
    expect("waiver-not-needed-on-this-run", quiet + sil(2, "long") * 3 + body(3, "long()"), waivers, 0, ["6.0 s | 10 s | " + within, "3.0 s | 5 s | " + within], expected_notes=2)
    # A waiver of one kind does not cover the other.
    expect("waiver-of-the-other-kind", quiet + body(6, "long()"), "sil 20 instance method SafeDICore.(file).Errors.long()\n", 2, [within, "**over the limit**", within])
    # Two getters of one type, which the timer names alike: each is a row under its property's name, and a waiver of one
    # does not cover the other.
    getters = quiet + getter(6, 2) + getter(7, 3)
    expect("two-getters", getters, "", 2, [within, "Errors.second (File.swift:3)` | 7.0 s", "Errors.first (File.swift:2)` | 6.0 s", within])
    expect("one-getter-waived", getters, "type-check 8 getter SafeDICore.(file).Errors.first\n", 1, [within, "Errors.second (File.swift:3)` | 7.0 s | 5 s | **over the limit**", "Errors.first (File.swift:2)` | 6.0 s | waived to 8 s | waived", within])
    # A waiver whose text starts two functions over the limit shelters one it was not written for.
    expect("waiver-matches-two", getters, "type-check 8 getter SafeDICore.(file).Errors.\n", 1, [within, "| waived |", "| waived |", within])
    expect("nothing-measured", "Build complete!\n", "", 1, [])
    expect("module-not-compiled", body(1, "other()", module="SwiftSyntax") + module_pass, "", 1, [])
    # The optimizer's timer was lost: the type checker's lines alone do not pass.
    expect("no-optimizer-times", body(0.3, "quiet()"), "", 1, [])
    try:
        expect("waivers-malformed", quiet, "sil ten name\n", 0, [])
        failures.append("waivers-malformed: a ceiling that is not a number was accepted")
    except Failure:
        pass
    for failure in failures:
        print(f"self-test failed: {failure}")
    print("self-test " + ("failed" if failures else "passed"))
    return 1 if failures else 0


def main(arguments):
    options = {"--sil-limit": "10", "--type-check-limit": "5", "--module": "SafeDICore", "--demangler": "swift demangle", "--summary": None,
               "--waivers": os.path.join(os.path.dirname(os.path.abspath(__file__)), "function-compile-time-waivers.txt")}
    positional = []
    self_testing = False
    while arguments:
        argument = arguments.pop(0)
        if argument == "--self-test":
            self_testing = True
        elif argument in options and arguments:
            options[argument] = arguments.pop(0)
        else:
            positional.append(argument)
    if len(positional) != 1:
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        return 2
    if self_testing:
        if os.path.exists(positional[0]):
            print(f"{positional[0]} exists; the self-test writes a new directory", file=sys.stderr)
            return 2
        return self_test(os.path.abspath(positional[0]))
    else:
        try:
            limits = {"sil": float(options["--sil-limit"]), "type-check": float(options["--type-check-limit"])}
            rows, failures, notes = check(positional[0], options["--module"], limits, read_waivers(options["--waivers"]), options["--demangler"])
        except (Failure, OSError, ValueError) as failure:
            print(failure, file=sys.stderr)
            return 2
        report(rows, failures, notes, options["--module"], options["--summary"])
        return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
