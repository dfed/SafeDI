#!/usr/bin/env python3
"""Usage: function-compile-time-check.py [--sil-limit SECONDS] [--type-check-limit SECONDS] [--waivers FILE]
                                      [--module NAME] [--demangler COMMAND] [--summary FILE] LOG
       function-compile-time-check.py --self-test

Fails when the compiler spends too long on any one function of a module (default `SafeDICore`): more than SIL-LIMIT
(default 10) seconds optimizing it, summed over the optimizer's passes, or more than TYPE-CHECK-LIMIT (default 5)
seconds type-checking its body. One 646-line initializer once took 40% of SafeDICore's release compile, three minutes
of every release build, and one getter twelve seconds of every build of any kind, and nothing reported either: a
function's cost in the optimizer grows faster than its length, so the remedy is to split it, and the time to notice is
the pull request that makes it long.

LOG is the output of a release build of the module with the compiler's timers on:

    swift build -c release --traits sourceBuild --target SafeDICore -v \\
        -Xswiftc -Xfrontend -Xswiftc -debug-time-function-bodies \\
        -Xswiftc -Xllvm -Xswiftc -sil-print-pass-time -Xswiftc -Xllvm -Xswiftc -sil-min-pass-time=200

The optimizer then prints each pass over a function that took 200 ms or more, and the type checker every body's time.
Only the module's own functions count, with the specializations the optimizer makes of them.

FILE (default `function-compile-time-waivers.txt` beside this script) lists the functions known to be over a limit,
one a line, as `sil` or `type-check`, a ceiling in seconds, and the start of the function's name as this script prints
it, separated by spaces; a `#` line is a comment and says why the function is waived and what removes it. A waived
function fails only over its ceiling. A waiver that no function over the limit matches also fails, so that the list
shrinks when a function is split and cannot shelter the next one.

The limits are several times what any other function takes, because runners differ in speed by half.

Exit status: 0 no function over its limit; 1 one is, a waiver matches nothing, or LOG holds no timing of the module
(a check that measured nothing has not passed); 2 usage.
"""
import collections
import os
import re
import subprocess
import sys

SIL_PASS = re.compile(r"\s*([0-9.]+) ms: \S+ #\d+ @(\S+)")
TYPE_CHECK = re.compile(r"([0-9.]+)ms\t(\S+?):\d+:\d+\t(.*?)(?:@\S*)?$")


class Failure(Exception):
    pass


def demangled(names, demangler):
    """Returns {mangled name: readable name}; the mangled name itself when the demangler cannot be run."""
    names = sorted(names)
    try:
        output = subprocess.run(demangler.split(), input="\n".join(names), capture_output=True, text=True, check=True).stdout.splitlines()
    except (OSError, subprocess.CalledProcessError):
        output = []
    return dict(zip(names, output if len(output) == len(names) else names))


def read_times(log, module, demangler):
    """Returns ({function: seconds in the optimizer}, {function: seconds in the type checker}) for the module's functions."""
    marker = f"{len(module)}{module}"
    passes = collections.Counter()
    bodies = {}
    with open(log, errors="replace") as handle:
        for line in handle:
            match = SIL_PASS.match(line)
            if match:
                if marker in match.group(2):
                    passes[match.group(2)] += float(match.group(1)) / 1000
                continue
            match = TYPE_CHECK.match(line.rstrip("\n"))
            if match and f"/Sources/{module}/" in match.group(2) and match.group(3):
                name = f"{match.group(3)} ({os.path.basename(match.group(2))})"
                bodies[name] = max(bodies.get(name, 0.0), float(match.group(1)) / 1000)
    names = demangled(passes, demangler)
    optimizer = collections.Counter()
    for mangled, seconds in passes.items():
        optimizer[names[mangled]] += seconds
    return dict(optimizer), bodies


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
    """Returns (the table's rows, the failures). `limits` is keyed "sil" and "type-check"."""
    times = dict(zip(("sil", "type-check"), read_times(log, module, demangler)))
    if not times["type-check"]:
        return [], [f"{log} holds no type-checking time of a function of {module}: was the module compiled, with the timers on?"]
    measure = {"sil": "optimizing", "type-check": "type-checking"}
    rows, failures = [], []
    used = set()
    for kind in ("sil", "type-check"):
        for name, seconds in sorted(times[kind].items(), key=lambda item: (-item[1], item[0])):
            if seconds <= limits[kind]:
                continue
            matching = [waiver for waiver in waivers if waiver[0] == kind and name.startswith(waiver[2])]
            used.update(matching)
            if not matching:
                failures.append(f"{seconds:.1f} s {measure[kind]} `{name}`; the limit for one function is {limits[kind]:g} s. Split it.")
                rows.append(f"| {measure[kind]} | `{name}` | {seconds:.1f} s | {limits[kind]:g} s | **over the limit** |")
            elif seconds > min(ceiling for _, ceiling, _ in matching):
                ceiling = min(ceiling for _, ceiling, _ in matching)
                failures.append(f"{seconds:.1f} s {measure[kind]} `{name}`, which is waived up to {ceiling:g} s: it grew")
                rows.append(f"| {measure[kind]} | `{name}` | {seconds:.1f} s | waived to {ceiling:g} s | **over its waiver** |")
            else:
                rows.append(f"| {measure[kind]} | `{name}` | {seconds:.1f} s | waived to {min(ceiling for _, ceiling, _ in matching):g} s | waived |")
    for waiver in waivers:
        if waiver not in used:
            failures.append(f"the waiver `{waiver[0]} {waiver[1]:g} {waiver[2]}` matches no function over the limit: remove it")
    for kind in ("sil", "type-check"):
        within = [(seconds, name) for name, seconds in times[kind].items() if seconds <= limits[kind]]
        if within:
            seconds, name = max(within)
            rows.append(f"| {measure[kind]} | `{name}` (the longest within the limit) | {seconds:.1f} s | {limits[kind]:g} s | within the limit |")
    return rows, failures


def report(rows, failures, module, summary):
    lines = [f"The compiler's time on single functions of {module}, release build.", "",
             "| Measure | Function | Time | Limit | Verdict |", "|---|---|---|---|---|"] + rows + [""] + [f"- {failure}" for failure in failures]
    text = "\n".join(lines) + "\n"
    print(text)
    if summary:
        with open(summary, "a") as handle:
            handle.write(text)


# MARK: Self-test


def self_test():
    import tempfile
    failures = []
    body = lambda seconds, name, module="SafeDICore": f"{seconds * 1000:.2f}ms\t/checkout/Sources/{module}/File.swift:10:5\tinstance method {module}.(file).Type.{name}@/checkout/Sources/{module}/File.swift:10:5\n"
    sil = lambda seconds, name, module="10SafeDICore": f"  {seconds * 1000:.3f} ms: sil-combine #12 @$s{module}{len(name)}{name}\n"
    quiet = body(0.3, "quiet()") + sil(0.4, "quiet") + "  900.000 ms: loadable-address #8501\n" + "unrelated output\n"
    # Another module's functions never count.
    quiet += body(60, "other()", module="SwiftSyntax") + sil(60, "other", module="11SwiftSyntax")
    with tempfile.TemporaryDirectory() as directory:
        def expect(name, log, waivers, expected_failures, expected_rows):
            path = f"{directory}/{name}.log"
            with open(path, "w") as handle:
                handle.write(log)
            waiver_path = f"{directory}/{name}.waivers"
            with open(waiver_path, "w") as handle:
                handle.write(waivers)
            rows, found = check(path, "SafeDICore", {"sil": 10.0, "type-check": 5.0}, read_waivers(waiver_path), "no-such-demangler")
            if len(found) != expected_failures or len(rows) != len(expected_rows) or any(expected not in row for expected, row in zip(expected_rows, rows)):
                failures.append(f"{name}: expected {expected_failures} failure(s) and rows with {expected_rows!r}, got {found} and {rows}")

        within = "within the limit"
        expect("quiet", quiet, "", 0, ["0.4 s | 10 s | " + within, "0.3 s | 5 s | " + within])
        # Six passes of two seconds over one function are twelve seconds of it.
        expect("slow-to-optimize", quiet + sil(2, "long") * 6, "", 1, ["12.0 s | 10 s | **over the limit**", within, within])
        expect("slow-to-type-check", quiet + body(6, "long()"), "", 1, ["6.0 s | 5 s | **over the limit**", within, within])
        waivers = "# why\nsil 20 $s10SafeDICore4long\ntype-check 8 instance method SafeDICore.(file).Type.long()\n"
        both = quiet + sil(2, "long") * 6 + body(6, "long()")
        expect("waived", both, waivers, 0, ["| waived |", "| waived |", within, within])
        expect("over-its-waiver", quiet + sil(3, "long") * 7 + body(9, "long()"), waivers, 2, ["**over its waiver**", "**over its waiver**", within, within])
        # The function was split: both waivers must go.
        expect("waiver-unused", quiet, waivers, 2, [within, within])
        # A waiver of one kind does not cover the other.
        expect("waiver-of-the-other-kind", quiet + body(6, "long()"), "sil 20 instance method SafeDICore.(file).Type.long()\n", 2, ["**over the limit**", within, within])
        expect("nothing-measured", "Build complete!\n", "", 1, [])
        expect("module-not-compiled", body(1, "other()", module="SwiftSyntax"), "", 1, [])
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
    if len(positional) != (0 if self_testing else 1):
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        return 2
    if self_testing:
        return self_test()
    else:
        try:
            limits = {"sil": float(options["--sil-limit"]), "type-check": float(options["--type-check-limit"])}
            rows, failures = check(positional[0], options["--module"], limits, read_waivers(options["--waivers"]), options["--demangler"])
        except (Failure, OSError, ValueError) as failure:
            print(failure, file=sys.stderr)
            return 2
        report(rows, failures, options["--module"], options["--summary"])
        return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
