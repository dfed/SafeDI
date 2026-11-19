#!/usr/bin/env python3
"""stage2.py [--runs N] [--shapes A,B] FIXTURES WORK LABEL=TOOL[,legacy] ...

Times `SafeDITool generate` on each shape in FIXTURES (from make_fixtures.sh), per module in build order as Bazel
and Tuist run it (`--combined-output --module-info-output`, each module reading the `.safedi` files of its
dependencies). A `legacy` tool (2.2.0) is run without `--module-name`/`--package-name`, which it does not have.
Per shape: one untimed run of each tool, then N rounds (default 7), the tools in a rotated order each round.
A run's wall and CPU (user+sys, from wait4) are summed over modules; its peak memory is the largest module's maxrss.
Prints one log line per run, then per shape each tool's medians and ranges. With exactly two non-legacy tools
labelled A1 and A2 (two builds of one commit), it prints the A/A spread and the band (spread capped at 3%);
with labels BASE and HEAD it prints HEAD/BASE ratios and whether each is inside the band given by --band, and
with --bands FILE the verdict of each shape against that file's bands, exiting 1 when a shape fails."""
import os, statistics, subprocess, sys, time

def run_module(tool, legacy, shape_dir, module, deps, out):
    files = sorted(os.path.join(dp, f) for dp, _, fs in os.walk(f"{shape_dir}/{module}") for f in fs if f.endswith(".swift"))
    csv = f"{out}/{module}.csv"
    open(csv, "w").write(",".join(files))
    args = [tool, "generate", csv, "--combined-output", f"{out}/{module}.generated.swift", "--module-info-output", f"{out}/{module}.safedi",
            "--active-compilation-conditions", "DEBUG"]
    if not legacy:
        args += ["--module-name", module, "--package-name", "Bench"]
    if deps:
        open(f"{out}/{module}.deps.csv", "w").write(",".join(f"{out}/{d}.safedi" for d in deps))
        args += ["--dependent-module-info-file-path", f"{out}/{module}.deps.csv"]
    with open(f"{out}/{module}.log", "wb") as log:
        start = time.monotonic()
        process = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT)
        _, status, usage = os.wait4(process.pid, 0)
        wall = time.monotonic() - start
    if status != 0:
        return None
    # ru_maxrss is in bytes on macOS and in kilobytes on Linux.
    return wall, usage.ru_utime + usage.ru_stime, usage.ru_maxrss / (1024 * 1024 if sys.platform == "darwin" else 1024)

def run_shape(tool, legacy, shape_dir, out):
    os.makedirs(out, exist_ok=True)
    wall = cpu = rss = 0
    for line in open(f"{shape_dir}/modules.txt"):
        parts = line.split()
        if not parts: continue
        module, deps = parts[0], (parts[1].split(",") if len(parts) > 1 else [])
        result = run_module(tool, legacy, shape_dir, module, deps, out)
        if result is None:
            return None
        wall += result[0]; cpu += result[1]; rss = max(rss, result[2])
    return wall, cpu, rss

def main(argv):
    runs, shapes, band, bands = 7, None, None, None
    while argv and argv[0].startswith("--"):
        flag = argv.pop(0)
        if flag == "--runs": runs = int(argv.pop(0))
        elif flag == "--shapes": shapes = argv.pop(0).split(",")
        elif flag == "--band": band = float(argv.pop(0))
        elif flag == "--bands": bands = __import__("json").load(open(argv.pop(0)))
    fixtures, work = argv[0], argv[1]
    tools = []
    for spec in argv[2:]:
        label, rest = spec.split("=", 1)
        path, *flags = rest.split(",")
        tools.append((label, path, "legacy" in flags))
    shapes = shapes or sorted(os.listdir(fixtures))
    summary = []
    for shape in shapes:
        shape_dir = f"{fixtures}/{shape}"
        results = {label: [] for label, _, _ in tools}
        rejected = set()
        for label, path, legacy in tools:
            if run_shape(path, legacy, shape_dir, f"{work}/{shape}/{label}") is None:
                rejected.add(label)
                print(f"{shape} {label} rejected: {open(max((f for f in os.scandir(f'{work}/{shape}/{label}') if f.name.endswith('.log')), key=lambda e: e.stat().st_mtime).path, errors='replace').read()[:300]!r}", flush=True)
        active = [t for t in tools if t[0] not in rejected]
        for round_ in range(runs):
            order = active[round_ % len(active):] + active[:round_ % len(active)] if active else []
            for label, path, legacy in order:
                r = run_shape(path, legacy, shape_dir, f"{work}/{shape}/{label}")
                results[label].append(r)
                print(f"{shape} round {round_ + 1} {label} wall {r[0]:.3f} cpu {r[1]:.3f} rssMB {r[2]:.0f}", flush=True)
        summary.append((shape, results, rejected))
    print("\n| shape | tool | wall median (range) | CPU median (range) | peak memory median (range) |\n|---|---|---|---|---|")
    for shape, results, rejected in summary:
        for label, _, _ in tools:
            if label in rejected:
                print(f"| {shape} | {label} | rejected | | |"); continue
            cells = []
            for i, unit, fmt in ((0, "s", "%.3f"), (1, "s", "%.3f"), (2, "MB", "%.0f")):
                values = [r[i] for r in results[label]]
                cells.append(f"{fmt % statistics.median(values)} {unit} ({fmt % min(values)}–{fmt % max(values)})")
            print(f"| {shape} | {label} | " + " | ".join(cells) + " |")
    labels = [t[0] for t in tools]
    pair = ("A1", "A2") if "A1" in labels and "A2" in labels else ("BASE", "HEAD") if "BASE" in labels and "HEAD" in labels else None
    if pair:
        a, b = pair
        print(f"\n| shape | {b}/{a} wall | {b}/{a} CPU | {b}/{a} peak memory |" + (" band |" if pair == ("A1", "A2") else "") + "\n|---|---|---|---|" + ("---|" if pair == ("A1", "A2") else ""))
        for shape, results, rejected in summary:
            if a in rejected or b in rejected: continue
            ratios = [statistics.median(r[i] for r in results[b]) / statistics.median(r[i] for r in results[a]) for i in range(3)]
            if pair == ("A1", "A2"):
                spreads = [abs(q - 1) for q in ratios]
                print(f"| {shape} | " + " | ".join(f"{q:.3f}" for q in ratios) + f" | wall {min(spreads[0], .03):.1%}, CPU {min(spreads[1], .03):.1%}, memory {min(spreads[2], .03):.1%} |")
            else:
                verdict = "" if band is None else " (" + ", ".join(("inside" if q <= 1 + band else "OUTSIDE") for q in ratios[1:]) + f" the {band:.1%} band for CPU, memory)"
                print(f"| {shape} | " + " | ".join(f"{q:.3f}" for q in ratios) + f" |{verdict}")

    if bands and pair == ("BASE", "HEAD"):
        print("\n| shape | judged on | HEAD/BASE wall | HEAD/BASE CPU | HEAD/BASE memory | wall band | BASE spread wall/CPU | HEAD spread wall/CPU | verdict |\n|---|---|---|---|---|---|---|---|---|")
        failures = []
        for shape, results, rejected in summary:
            if "BASE" in rejected or "HEAD" in rejected: continue
            pick = min if shape in bands.get("minimums", []) else statistics.median
            q = [pick(r[i] for r in results["HEAD"]) / pick(r[i] for r in results["BASE"]) for i in range(3)]
            spread = lambda label, i: (max(r[i] for r in results[label]) - min(r[i] for r in results[label])) / statistics.median(r[i] for r in results[label])
            wall_band = bands["wall"].get(shape, 0.03)
            problems = []
            if q[1] > 1 + bands["cpu"]: problems.append(f"CPU +{q[1]-1:.1%}")
            if q[2] > 1 + bands["memory"]: problems.append(f"memory +{q[2]-1:.1%}")
            if q[0] > 1 + wall_band: problems.append(f"wall +{q[0]-1:.1%}")
            verdict = "pass" if not problems else "FAIL: " + ", ".join(problems)
            if problems: failures.append(shape)
            print(f"| {shape} | {'minimum' if pick is min else 'median'} | {q[0]:.3f} | {q[1]:.3f} | {q[2]:.3f} | {wall_band:.1%} | {spread('BASE',0):.1%} / {spread('BASE',1):.1%} | {spread('HEAD',0):.1%} / {spread('HEAD',1):.1%} | {verdict} |")
        print("\nGATE " + ("PASSED" if not failures else "FAILED on " + ", ".join(failures)))
        if failures:
            sys.exit(1)

main(sys.argv[1:])

