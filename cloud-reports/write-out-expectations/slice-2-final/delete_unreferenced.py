#!/usr/bin/env python3
"""Deletes private members of the given test files that nothing references, to a fixed point.

    delete_unreferenced.py [--dry-run] FILE...

A member is a `func`, `let` or `var` declared with `private` (or a non-private `static func`, searched across Tests/).
A function counts as referenced when a call spells its name with its first argument label (or, for an unlabeled first
parameter, its name followed by a parenthesis and no label of another overload), or names it without calling it.
Members with the `@Test` attribute, `init`s and overrides are never candidates.
"""
import pathlib, re, subprocess, sys

DECL = re.compile(r"^(\t+)((?:@\w+(?:\([^)]*\))?\s+)*)((?:private|fileprivate)\s+)?((?:static|nonisolated)\s+)*(func|let|var)\s+(`?\w+`?)(.*)$")

def members(lines):
    for i, line in enumerate(lines):
        m = DECL.match(line)
        if not m: continue
        indent, attrs, access, _, kind, name, rest = m.groups()
        if "@Test" in attrs or (i and "@Test" in lines[i-1]) : continue
        is_static = "static" in line.split(kind)[0]
        if not access and not (kind == "func" and is_static): continue
        if len(indent) != 1: continue
        # end line
        j = i
        opener = line.rstrip()
        if kind == "func" or opener.endswith(("{", "(", "[", '"""')):
            if kind != "func" and opener.endswith('"""'):
                close = ('"""',)
            else:
                close = ("}", ")", "]")
            j = i + 1
            while j < len(lines) and not (lines[j].startswith(indent) and lines[j][len(indent):len(indent)+3].startswith(close) and not lines[j].startswith(indent + "\t")):
                j += 1
            # a signature spanning lines: `) -> T {` closes the parameters, not the body
            while j < len(lines) and lines[j].rstrip().endswith("{"):
                j += 1
                while j < len(lines) and not (lines[j].startswith(indent + "}")):
                    j += 1
        start = i
        while start > 0 and lines[start-1].startswith(indent + "//"):
            start -= 1
        first_label = None
        if kind == "func":
            signature = " ".join(l.strip() for l in lines[i:min(j, i+12)+1])
            pm = re.search(re.escape(name) + r"(?:<[^(]*>)?\((.*?)\)\s*(?:async\s*)?(?:throws\s*)?(?:->|\{)", signature)
            params = pm.group(1) if pm else ""
            first_label = re.findall(r"(?:^|,)\s*(\w+)(?:\s+\w+)?\s*:", params)
        yield dict(name=name, kind=kind, start=start, decl=i, end=j, private=bool(access), first_label=first_label)

def referenced(member, texts_without_decl):
    name = re.escape(member["name"])
    if member["kind"] == "func":
        labels = member["first_label"] or []
        bare = [rf"Self\.{name}\b(?!\s*[(<])", rf"\((?:Self\.)?{name}\)"]
        if not labels:
            pats = [rf"(?<!func )\b{name}\(\s*\)"]
        elif labels[0] == "_":
            pats = [rf"(?<!func )\b{name}\((?!\s*\w+\s*:\s)(?!\s*\))"]
        else:
            alternatives = "|".join(l for l in labels if l != "_")
            pats = [rf"(?<!func )\b{name}\(\s*(?:{alternatives})\s*:", rf"(?<!func )\b{name}\(\s*\)", rf"(?<!func )\b{name}\(\s*$"]
        pats += bare
    else:
        pats = [rf"\b{name}\b"]
    return any(re.search(p, t, re.MULTILINE) for p in pats for t in texts_without_decl)

def main():
    args = sys.argv[1:]
    dry = "--dry-run" in args
    files = [pathlib.Path(a) for a in args if a != "--dry-run"]
    all_tests = None
    removed = 0
    for file in files:
        while True:
            lines = file.read_text().split("\n")
            found = None
            for member in members(lines):
                own = "\n".join(lines[:member["decl"]] + [""] + lines[member["end"]+1:])
                # the declaration's own body may call itself; exclude the whole member
                texts = [own]
                if not member["private"]:
                    if all_tests is None:
                        all_tests = {p: p.read_text() for p in pathlib.Path("Tests").rglob("*.swift")}
                    texts += [t for p, t in all_tests.items() if p.resolve() != file.resolve()]
                if not referenced(member, texts):
                    found = member; break
            if not found: break
            print(f"{file}:{found['decl']+1}: {found['kind']} {found['name']} ({found['end']-found['start']+1} lines)")
            removed += 1
            end = found["end"] + 1
            if end < len(lines) and lines[end].strip() == "" : end += 1
            new = lines[:found["start"]] + lines[end:]
            if dry:
                # simulate to reach the fixed point without writing
                file_backup = file.read_text(); file.write_text("\n".join(new)); 
                BACKUPS.setdefault(file, file_backup)
            else:
                file.write_text("\n".join(new))
            all_tests = None
    if dry:
        for f, t in BACKUPS.items(): f.write_text(t)
    print(f"{removed} members")
BACKUPS = {}
main()
