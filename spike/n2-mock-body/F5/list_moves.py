"""Lists every place in every mock of today's F5 file whose override read moves under the one read rule.

A place is a function definition in today's text, named by the chain of builder labels from the mock root to it.
Today a place reads the path its `safeDIBuilder` line names, or none. Under the one rule the read is decided at the
call: a place reads its caller's path plus its label when the caller reads a configuration whose type has that field,
and none otherwise; the mock root's children read the root's field. A place can be reached with several reads under
the rule (through different closing calls), so each (place, rule read) pair is listed.
With --loop, the rule is the loop rule instead: a cycle's closing edge hands the re-entered type the read its nearest
ancestor of that type had, so every override applies on every lap.
Usage: list_moves.py TODAY.swift OUT.json [--loop]"""
import collections, importlib.util, json, os, re, sys

spec = importlib.util.spec_from_file_location("sf", os.path.join(os.path.dirname(__file__), "shared_form.py"))
sf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sf)

text = open(sys.argv[1]).read()
fields = {}
for m in re.finditer(r"extension (\w+) \{\n(?:    ///[^\n]*\n)?    struct SafeDIMockConfiguration \{\n        init\(\n(.*?)\n        \) \{", text, re.S):
    fields[m.group(1)] = {l.strip().split(":")[0] for l in m.group(2).split("\n") if not l.strip().startswith("_ ")}
lines = text.split("\n")
results = []
LOOP = "--loop" in sys.argv[3:]
index = 0
while index < len(lines):
    line = lines[index]
    index += 1
    if not (re.match(r"^    \) -> \w+ \{$", line) and any("static func mock(" in l for l in lines[max(0, index - 8):index])):
        continue
    mocked = re.match(r"^    \) -> (\w+) \{$", line).group(1)
    start, depth = index, 1
    while depth:
        stripped = lines[index].strip()
        depth += stripped.count("{") - stripped.count("}")
        index += 1
    body = lines[start:index - 1]
    if not any(l.strip().startswith("func ") for l in body):
        continue
    root = sf.Place("<root>", "", None, None)
    sf.parse_body(body[:-1] + ["}"], 0, root)
    # Name each definition by its chain of labels (the label of the builder that first calls it, in its parent).
    names = {}

    def name_definitions(place, prefix):
        for label, child_type, callee_name in place.children:
            callee = place.resolve(callee_name)
            if callee.parent is place and id(callee) not in names:
                names[id(callee)] = (prefix + "." if prefix else "") + label
                name_definitions(callee, names[id(callee)])
    name_definitions(root, "")
    seen, queue, reported = set(), [], set()
    # The types a cycle's closing edge re-enters: only their nearest ancestors' reads matter under the loop rule.
    loop_targets = set()

    def collect_targets(place):
        for label, child_type, callee_name in place.children:
            callee = place.resolve(callee_name)
            if place is not root and label not in fields.get(place.type, ()):
                loop_targets.add(callee.type)
        for definition in place.definitions.values():
            collect_targets(definition)
    collect_targets(root)
    for label, child_type, callee_name in root.children:
        queue.append((root.resolve(callee_name), label, "<mock root>", label, ()))
    while queue:
        place, rule_read, via, call_label, ancestors = queue.pop(0)
        key = (id(place), rule_read, ancestors if LOOP else ())
        if key in seen:
            continue
        seen.add(key)
        if LOOP and place.type in loop_targets:
            ancestors = tuple(sorted({**dict(ancestors), place.type: rule_read}.items(), key=lambda item: item[0]))
        if place.path != rule_read and (id(place), rule_read) not in reported:
            reported.add((id(place), rule_read))
            results.append({"mock": mocked, "place": names[id(place)], "type": place.type, "today": place.path,
                            "oneRule": rule_read, "calledFrom": via})
        for label, child_type, callee_name in place.children:
            callee = place.resolve(callee_name)
            if label in fields.get(place.type, ()):
                read = f"{rule_read}.{label}" if rule_read is not None else None
            elif LOOP:
                read = dict(ancestors).get(callee.type)
            else:
                read = None
            queue.append((callee, read, names[id(place)] + " (" + label + ")", label, ancestors))
json.dump(results, open(sys.argv[2], "w"), indent=1)
kinds = collections.Counter()
for r in results:
    if r["today"] is None:
        kinds["today none, rule reads a path"] += 1
    elif r["oneRule"] is None:
        kinds["today reads a path, rule reads none"] += 1
    else:
        kinds["today reads one path, rule reads another"] += 1
print(len(results), "moved (place, read) pairs in", len({(r["mock"], r["place"]) for r in results}), "places;", dict(kinds))
print("by mock:", dict(collections.Counter(r["mock"] for r in results)))
