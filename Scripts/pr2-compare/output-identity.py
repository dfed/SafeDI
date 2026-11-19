#!/usr/bin/env python3
"""output-identity.py WORK: for each shape stage2.py ran, whether the HEAD tool wrote the same bytes as the BASE tool
(every `<Module>.generated.swift` and `<Module>.safedi`). Prints one line per shape and a last line
`IDENTICAL n/n` or `DIFFERENT on <shapes>`."""
import hashlib, os, sys

work = sys.argv[1]
different, shapes = [], sorted(os.listdir(work)) if os.path.isdir(work) else []


def outputs(directory):
    if not os.path.isdir(directory):
        return None
    return {
        name: hashlib.sha256(open(os.path.join(directory, name), "rb").read()).hexdigest()
        for name in sorted(os.listdir(directory))
        if name.endswith((".generated.swift", ".safedi"))
    }


for shape in shapes:
    base, head = outputs(f"{work}/{shape}/BASE"), outputs(f"{work}/{shape}/HEAD")
    if not base or not head:
        print(f"{shape}: missing output (a tool rejected the shape)")
        different.append(shape)
    elif base != head:
        changed = sorted(n for n in set(base) | set(head) if base.get(n) != head.get(n))
        print(f"{shape}: DIFFERENT in {', '.join(changed)}")
        different.append(shape)
    else:
        print(f"{shape}: identical ({len(base)} files)")
print(f"DIFFERENT on {', '.join(different)}" if different else f"IDENTICAL {len(shapes)}/{len(shapes)}")
