#!/usr/bin/env python3
"""side-info.py REPOSITORY BASE COMMIT RACER: prints, as JSON, what pr2-compare.sh reports about one side besides its
gates: its commits and the span of their author dates, the size of its diff from BASE under Sources/ and Tests/, the
tests it adds, and how the public declarations of the helper's two files compare with RACER's."""
import json, re, subprocess, sys

HELPER_FILES = ["GenerationJobs.swift", "GenerationPhaseObservation.swift"]


def git(repository, *arguments):
    return subprocess.run(["git", "-C", repository, *arguments], check=True, capture_output=True, text=True).stdout


def diff_size(repository, base, commit, path):
    added = deleted = files = 0
    for line in git(repository, "diff", "--numstat", "-M", f"{base}..{commit}", "--", path).splitlines():
        a, d, _ = line.split("\t", 2)
        files += 1
        if a != "-":
            added += int(a)
            deleted += int(d)
    patch = git(repository, "diff", "-M", f"{base}..{commit}", "--", path)
    added_bytes = sum(len(l.encode()) - 1 for l in patch.splitlines() if l.startswith("+") and not l.startswith("+++"))
    return {"files": files, "added": added, "deleted": deleted, "addedBytes": added_bytes}


def tests_added(repository, base, commit):
    """The test functions the diff adds: an added `func` whose nearest attribute line above is `@Test`, or an added
    XCTest `func test…`."""
    names = []
    for path in git(repository, "diff", "--name-only", f"{base}..{commit}", "--", "Tests").split():
        patch = git(repository, "diff", "-U0", f"{base}..{commit}", "--", path)
        pending_test = False
        for line in patch.splitlines():
            if not line.startswith("+") or line.startswith("+++"):
                pending_test = False if not line.startswith("+") else pending_test
                continue
            body = line[1:].strip()
            if body.startswith("@Test"):
                pending_test = True
            match = re.search(r"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)", body)
            if match and (pending_test or match.group(1).startswith("test")):
                names.append(f"{path.split('/')[-1].removesuffix('.swift')}.{match.group(1)}")
                pending_test = False
    return names


def public_declarations(repository, commit):
    """Every public declaration of the helper's files at COMMIT, from `public` to its body's `{` or line end, with
    whitespace collapsed; a file found under another directory is read there."""
    declarations, missing = [], []
    paths = git(repository, "ls-tree", "-r", "--name-only", commit, "Sources").split()
    for name in HELPER_FILES:
        matches = [p for p in paths if p.endswith("/" + name)]
        if not matches:
            missing.append(name)
            continue
        text = git(repository, "show", f"{commit}:{matches[0]}")
        text = re.sub(r"//[^\n]*", "", text)
        for match in re.finditer(r"(?:@\w+(?:\([^)]*\))?\s+)*public\b", text):
            start, depth, index = match.start(), 0, match.end()
            while index < len(text):
                character = text[index]
                if character in "([<":
                    depth += 1
                elif character in ")]>" and not text[index - 1] == "-":
                    depth -= 1
                elif depth <= 0 and (character == "{" or (character == "\n" and not text[index + 1 :].lstrip().startswith(("->", "where", "throws", "async", "rethrows")))):
                    break
                index += 1
            declarations.append(f"{name}: " + " ".join(text[start:index].split()))
    return sorted(set(declarations)), missing


def main(repository, base, commit, racer):
    log = git(repository, "log", "--reverse", "--format=%aI%x09%s", f"{base}..{commit}").splitlines()
    dates = [l.split("\t", 1)[0] for l in log]
    mine, missing = public_declarations(repository, commit)
    frozen, _ = public_declarations(repository, racer)
    print(json.dumps({
        "commit": commit,
        "commits": [l.split("\t", 1)[1] for l in log],
        "firstAuthorDate": dates[0] if dates else None,
        "lastAuthorDate": dates[-1] if dates else None,
        "sources": diff_size(repository, base, commit, "Sources"),
        "plugins": diff_size(repository, base, commit, "Plugins"),
        "tests": diff_size(repository, base, commit, "Tests"),
        "testsAdded": tests_added(repository, base, commit),
        "api": {
            "missingFiles": missing,
            "missingFromFrozen": [d for d in frozen if d not in mine],
            "notInFrozen": [d for d in mine if d not in frozen],
        },
    }, indent=1))


main(*sys.argv[1:5])
