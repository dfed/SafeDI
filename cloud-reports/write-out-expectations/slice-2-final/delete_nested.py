#!/usr/bin/env python3
"""delete_nested.py FILE NAME...: deletes each nested `var NAME: T {…}` of FILE that no `.NAME` reads any more."""
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
for name in sys.argv[2:]:
    while True:
        lines = path.read_text().split("\n")
        text = "\n".join(lines)
        if re.search(rf"\.{name}\b", text):
            print(f"{path}: {name} is still read"); break
        found = next((i for i, l in enumerate(lines) if re.match(rf"\t\t+var {name}: [^=]+\{{$", l)), None)
        if found is None: break
        indentation = re.match(r"\t*", lines[found]).group(0)
        end = next(k for k in range(found, len(lines)) if lines[k] == indentation + "}")
        start = found
        while lines[start - 1].startswith(indentation + "//"): start -= 1
        if lines[start - 1] == "": start -= 1
        print(f"{path}:{found + 1}: var {name} ({end - start + 1} lines)")
        path.write_text("\n".join(lines[:start] + lines[end + 1:]))
