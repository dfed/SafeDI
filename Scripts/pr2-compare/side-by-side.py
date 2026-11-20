#!/usr/bin/env python3
"""side-by-side.py RESULTS BASE RACER CANDIDATE: prints pr2-compare.sh's table, our racer beside the patch."""
import json, os, re, sys

results, base, racer, candidate = sys.argv[1:5]


def read(commit, name):
    path = os.path.join(results, commit, name)
    return open(path, errors="replace").read().strip() if os.path.exists(path) else None


def info(commit):
    text = read(commit, "info.json")
    return json.loads(text) if text else {}


def first_line(text, fallback="not run"):
    return text.splitlines()[0] if text else fallback


def gate4(commit):
    log = read(commit, "stage2.log")
    if not log:
        return "not run"
    verdicts = [l for l in log.splitlines() if l.startswith("GATE ")]
    rejected = sorted({l.split()[0] for l in log.splitlines() if " HEAD rejected" in l or " BASE rejected" in l})
    text = verdicts[-1] if verdicts else "no verdict (" + log.splitlines()[-1] + ")"
    return text + (f"; rejected: {', '.join(rejected)}" if rejected else "")


def worst_ratio(commit):
    """The largest HEAD/BASE wall ratio of stage2.py's verdict table, with its shape."""
    log = read(commit, "stage2.log")
    if not log:
        return "not run"
    ratios = []
    for line in log.splitlines():
        cells = [c.strip() for c in line.split("|")]
        if len(cells) > 10 and cells[2] in ("median", "minimum"):
            ratios.append((float(cells[3]), cells[1]))
    return f"{max(ratios)[0]:.3f} ({max(ratios)[1]})" if ratios else "no verdict table"


def coverage(commit):
    text = read(commit, "coverage.txt")
    if not text:
        return "not run"
    summary = [l for l in text.splitlines() if "changed line(s) no test executed" in l]
    return summary[-1] if summary else first_line(text)


def span(side):
    if not side.get("firstAuthorDate"):
        return "–"
    return f"{side['firstAuthorDate']} → {side['lastAuthorDate']}"


def size(side, key):
    part = side.get(key)
    return f"+{part['added']} −{part['deleted']} in {part['files']} files ({part['addedBytes']} bytes added)" if part else "–"


def api(side):
    part = side.get("api")
    if not part:
        return "not run"
    if part["missingFiles"]:
        return "files absent: " + ", ".join(part["missingFiles"])
    if not part["missingFromFrozen"] and not part["notInFrozen"]:
        return "matches the frozen signature"
    return f"{len(part['missingFromFrozen'])} frozen declaration(s) missing, {len(part['notInFrozen'])} extra"


ours, theirs = info(racer), info(candidate)
rows = [
    ("commit", racer[:9], candidate[:9]),
    ("commits", str(len(ours.get("commits", []))), str(len(theirs.get("commits", [])))),
    ("author dates (time)", span(ours), span(theirs)),
    ("Sources/ diff", size(ours, "sources"), size(theirs, "sources")),
    ("Plugins/ diff", size(ours, "plugins"), size(theirs, "plugins")),
    ("Tests/ diff", size(ours, "tests"), size(theirs, "tests")),
    ("tests added", str(len(ours.get("testsAdded", []))), str(len(theirs.get("testsAdded", [])))),
    ("gate 1: suite failures only the base's", first_line(read(racer, "gate1.txt")), first_line(read(candidate, "gate1.txt"))),
    ("gate 1: compile checks", (read(racer, "compile-checks.txt") or "–").replace("\n", "; "), (read(candidate, "compile-checks.txt") or "–").replace("\n", "; ")),
    ("gate 2: test lines (byte-identical gate)", first_line(read(racer, "byte-identical.txt")), first_line(read(candidate, "byte-identical.txt"))),
    ("gate 2: 13 shapes' generated code", (read(racer, "identity.txt") or "not run").splitlines()[-1], (read(candidate, "identity.txt") or "not run").splitlines()[-1]),
    # One round's bands are noise: the dry run, whose patch is the racer itself, failed 3 of 13 shapes on each side, on
    # different shapes each run, on a 4-core container. Read it as "the scripts run, nothing regressed grossly".
    ("gate 4: one round of generate (not a speed verdict)", gate4(racer), gate4(candidate)),
    ("gate 4: HEAD/BASE wall, worst shape", worst_ratio(racer), worst_ratio(candidate)),
    ("Swift 6.2 Linux coverage of changed lines", coverage(racer), coverage(candidate)),
    ("API: frozen helper signature", api(ours), api(theirs)),
]


def cell(text):
    return re.sub(r"\|", "\\|", text)


print(f"# PR 2 compare: ours {racer[:9]} beside the patch {candidate[:9]}, on base {base[:9]}\n")
print(f"Base's known failures (gate 1's reference):\n```\n{read(base, 'known-failures.txt') or 'not run'}\n```\n")
print("| | ours (racer) | patch |\n|---|---|---|")
for name, left, right in rows:
    print(f"| {name} | {cell(left)} | {cell(right)} |")
for label, side in (("ours", ours), ("patch", theirs)):
    part = side.get("api") or {}
    if part.get("missingFromFrozen") or part.get("notInFrozen"):
        print(f"\nAPI differences, {label}:")
        for declaration in part.get("missingFromFrozen", []):
            print(f"- missing: `{declaration}`")
        for declaration in part.get("notInFrozen", []):
            print(f"- extra: `{declaration}`")
for label, commit in (("ours", racer), ("patch", candidate)):
    text = read(commit, "gate1.txt")
    if text and text.startswith("FAIL"):
        print(f"\nGate 1, {label}:\n```\n{text}\n```")
    text = read(commit, "identity.txt")
    if text and "DIFFERENT" in text:
        print(f"\nGate 2 shapes, {label}:\n```\n{text}\n```")
    text = read(commit, "coverage.txt")
    if text and re.search(r"^[1-9]\d* changed line", text, re.M):
        print(f"\nUnexecuted changed lines, {label}:\n```\n{text}\n```")
print("\nTests added, patch:\n" + "\n".join(f"- {name}" for name in theirs.get("testsAdded", [])) if theirs.get("testsAdded") else "\nTests added, patch: none")
