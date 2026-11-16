#!/usr/bin/env python3
"""Reads `swift build` output on stdin and deletes each local constant it warns was never used."""
import pathlib, re, sys
sys.path.insert(0, "/root/.cache/RecS2")
import from_records as fr
sites = {}
for line in sys.stdin:
    m = re.match(r"(/\S+?/Tests/\S+\.swift):(\d+):\d+: warning: (?:initialization of )?immutable value '(\w+)' was never used", line)
    if m: sites.setdefault(m.group(1), set()).add((int(m.group(2)), m.group(3)))
for path, found in sites.items():
    text = pathlib.Path(path).read_text()
    for line, name in sorted(found, reverse=True):
        offset = sum(len(l) + 1 for l in text.split("\n")[:line])  # the end of the warned line
        definition = fr.local_definition(text, name, offset + 1)
        if definition is None or text.count("\n", 0, definition[0]) + 1 != line:
            print(f"left {path}:{line} {name}"); continue
        start = definition[0]
        # A comment that is only about the constant goes with it.
        text = text[:start] + text[definition[3]:]
        print(f"{path}:{line}: deleted {name}")
    pathlib.Path(path).write_text(text)
