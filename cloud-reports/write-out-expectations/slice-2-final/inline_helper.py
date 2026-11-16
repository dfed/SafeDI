#!/usr/bin/env python3
"""Inlines a test helper whose body is one expression at each call that passes it string literals.

    inline_helper.py FILE HELPER_NAME

Each `\\(parameter)` in the body becomes the literal's text. The helper stays; delete_unreferenced.py removes it.
"""
import pathlib, re, sys

def main():
    path, name = sys.argv[1], sys.argv[2]
    f = pathlib.Path(path); lines = f.read_text().split("\n")
    decl = next(i for i, l in enumerate(lines) if re.match(rf"\t(private )?(static )?func {name}\(", l))
    indent = "\t"
    end = next(j for j in range(decl + 1, len(lines)) if lines[j] == indent + "}")
    params = re.findall(r"(\w+)(?:\s+(\w+))?\s*:", re.search(rf"{name}\((.*)\)\s*->", lines[decl]).group(1))
    params = [(label, inner or label) for label, inner in params]
    body = lines[decl + 1:end]
    assert all(l.startswith("\t\t") or l == "" for l in body)
    body = [l[2:] for l in body]
    call = re.compile(rf"(?:Self\.)?{name}\(([^()]*)\)")
    out = []; count = 0
    for i, line in enumerate(lines):
        if decl <= i <= end or not call.search(line):
            out.append(line); continue
        m = call.search(line)
        arguments = dict(re.findall(r'(\w+):\s*"((?:[^"\\]|\\.)*)"', m.group(1)))
        values = {}
        for label, inner in params:
            assert label in arguments, (i + 1, label, line)
            values[inner] = arguments[label]
        line_indent = re.match(r"\t*", line).group(0)
        new = []
        for k, b in enumerate(body):
            b = re.sub(r"\\\((\w+)\)", lambda mm: values.get(mm.group(1), mm.group(0)), b)
            new.append(b if k == 0 else (line_indent + b if b else b))
        replaced = line[:m.start()] + "\n".join(new) + line[m.end():]
        out.append(replaced); count += 1
    f.write_text("\n".join(out)); print(f"{path}: inlined {count} calls of {name}")
main()
