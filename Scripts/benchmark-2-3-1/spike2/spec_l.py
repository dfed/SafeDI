"""Writes shape L's spec (synthetic, invented low-sharing proportions) for about T distinct types under one seam.

The proportions are invented round numbers for a low-sharing tree, used as given:
  places each type is built at: 80% at one, 10% at two, 5% at three, 5% at four to six; one type at 30 or more;
  children each node instantiates: none 50%, one 30%, two 10%, three to five 8%, more 2%;
  shortest depth of a node: mostly 4 to 6, range 1 to 8; at most 10 deep;
  nodes per distinct type: about 2.5;
  wrappers: half Instantiator, half constant.
Holes (also invented): two hole types, `Api` and `Bpi`, each owned by about one type in ten; the fills receive nothing.
Holes are added after the draw, so the children-per-node figures count no hole.

Draws come from a fixed seed (2026). Draw k uses random.Random(2026 * 1000 + k); the first draw whose sharing and nodes
per type are within 20% of the table is kept. The script prints what it reached on stderr.
Usage: python3 -I spec_l.py T > spec.json"""
import json
import random
import sys

TARGET_CHILDREN = {"none": 0.50, "one": 0.30, "two": 0.10, "three to five": 0.08, "more": 0.02}


def bucket(count):
    return "none" if count == 0 else "one" if count == 1 else "two" if count == 2 else "three to five" if count <= 5 else "more"


def draw(total, rng):
    names = ["Hub"] + [f"T{i}" for i in range(1, total)]
    depth_weights = {1: 2, 2: 5, 3: 10, 4: 22, 5: 24, 6: 20, 7: 10, 8: 7}
    depth = {"Hub": 0}
    for name in names[1:]:
        depth[name] = rng.choices(list(depth_weights), weights=list(depth_weights.values()))[0]
    # Every depth from 1 to the deepest drawn has a type, so each type has a parent one level up.
    deepest = max(depth.values())
    for level in range(1, deepest + 1):
        if not any(d == level for d in depth.values()):
            depth[rng.choice([n for n in names[1:] if depth[n] > level])] = level
    by_depth = {}
    for name in names:
        by_depth.setdefault(depth[name], []).append(name)
    parents = {name: [] for name in names}
    children = {name: [] for name in names}
    # A spanning tree with preferential attachment, so that most types have no children and a few have several.
    for level in range(1, deepest + 1):
        for name in by_depth[level]:
            candidates = by_depth[level - 1]
            weights = [1 + 3 * len(children[c]) for c in candidates]
            parent = rng.choices(candidates, weights=weights)[0]
            parents[name].append(parent)
            children[parent].append(name)

    def descendants(name):
        seen, stack = set(), [name]
        while stack:
            for child in children[stack.pop()]:
                if child not in seen:
                    seen.add(child)
                    stack.append(child)
        return seen

    def longest_depths():
        longest = {"Hub": 0}
        order = sorted(names, key=lambda n: depth[n])
        changed = True
        while changed:
            changed = False
            for name in order:
                for child in children[name]:
                    value = longest[name] + 1
                    if longest.get(child, -1) < value:
                        longest[child] = value
                        changed = True
        return longest

    # Shared types: extra places, from parents whose shortest depth keeps the type's shortest depth.
    pool = names[1:]
    rng.shuffle(pool)
    count = len(pool)
    plan = []
    hub_leaf = next((n for n in pool if not children[n] and 3 <= depth[n] <= 6), pool[0])
    plan.append((hub_leaf, 30 + rng.randrange(4)))
    rest = [n for n in pool if n != hub_leaf]
    for share, extra in [(0.10, lambda: 2), (0.05, lambda: 3), (0.05, lambda: rng.randint(4, 6))]:
        for _ in range(round(share * count)):
            plan.append((rest.pop(), extra()))
    for name, places in plan:
        for _ in range(places - 1):
            excluded = descendants(name) | {name} | set(parents[name])
            candidates = [n for n in names if depth[n] >= depth[name] - 1 and n not in excluded]
            rng.shuffle(candidates)
            for candidate in candidates:
                longest = longest_depths()
                if longest[candidate] + 1 + max([0] + [longest_from(child, children) for child in [name]]) <= 10:
                    parents[name].append(candidate)
                    children[candidate].append(name)
                    break
    return names, depth, parents, children


def longest_from(name, children):
    """The longest path below `name`, in edges."""
    memo = {}

    def go(n):
        if n not in memo:
            memo[n] = max([0] + [1 + go(c) for c in children[n]])
        return memo[n]

    return go(name)


def statistics(names, depth, parents, children):
    nodes = {"Hub": 1}
    for name in sorted(names, key=lambda n: max_depth(n, parents)):
        if name != "Hub":
            nodes[name] = sum(nodes[p] for p in parents[name])
    total_nodes = sum(nodes.values())
    places = {}
    for name in names[1:]:
        k = len(parents[name])
        places["one" if k == 1 else "two" if k == 2 else "three" if k == 3 else "four to six" if k <= 6 else "30 or more" if k >= 30 else "seven to 29"] = places.get("one" if k == 1 else "two" if k == 2 else "three" if k == 3 else "four to six" if k <= 6 else "30 or more" if k >= 30 else "seven to 29", 0) + 1
    child_buckets = {}
    for name in names:
        child_buckets[bucket(len(children[name]))] = child_buckets.get(bucket(len(children[name])), 0) + nodes[name]
    return {
        "types": len(names),
        "nodes": total_nodes,
        "nodes per type": total_nodes / len(names),
        "places": {k: v / (len(names) - 1) for k, v in places.items()},
        "children per node": {k: v / total_nodes for k, v in child_buckets.items()},
        "shortest depth": {d: sum(1 for n in names[1:] if depth[n] == d) / (len(names) - 1) for d in range(1, 9)},
        "deepest node": max(max_depth(n, parents) for n in names),
    }


def max_depth(name, parents, memo={}):
    key = (name, id(parents))
    if key not in memo:
        memo[key] = 0 if not parents[name] else 1 + max(max_depth(p, parents) for p in parents[name])
    return memo[key]


def within(stats):
    if not 2.0 <= stats["nodes per type"] <= 3.0:
        return False
    return 0.64 <= stats["places"].get("one", 0) <= 0.96


def main():
    total = int(sys.argv[1])
    for attempt in range(2000):
        rng = random.Random(2026 * 1000 + attempt)
        names, depth, parents, children = draw(total, rng)
        stats = statistics(names, depth, parents, children)
        if within(stats) and stats["deepest node"] <= 10:
            break
    else:
        raise SystemExit("no draw within 20%")
    # Wrappers, then holes, in a fixed order.
    types = {}
    for name in names:
        properties = []
        for index, child in enumerate(children[name]):
            kind = "inst" if rng.random() < 0.5 else "const"
            properties.append([f"{child[0].lower() + child[1:]}{'Builder' if kind == 'inst' else ''}", kind, child])
        types[name] = {"properties": properties}
    owners = names[1:]
    for hole, label in [("Api", "api"), ("Bpi", "bpi")]:
        for owner in rng.sample(owners, max(1, round(len(names) / 10))):
            types[owner]["properties"].insert(rng.randrange(len(types[owner]["properties"]) + 1), [label, "hole", hole])
    stats["draw"] = attempt
    stats["hole owners"] = {hole: sum(1 for t in types.values() if any(p[2] == hole and p[1] == "hole" for p in t["properties"])) for hole in ["Api", "Bpi"]}
    print(json.dumps(stats, indent=1, sort_keys=True), file=sys.stderr)
    json.dump({"seam": "Hub", "types": types, "holes": {"Api": "LiveApi", "Bpi": "LiveBpi"}, "fill_receives": {}, "pass_through": [], "root_declares": []}, sys.stdout, indent=1)


main()
