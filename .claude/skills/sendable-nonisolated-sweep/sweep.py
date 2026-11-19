#!/usr/bin/env python3
r"""Rewrite SafeDITool test expectations for E3 (SB-14): every generated `@Sendable` local function is spelled
`@Sendable nonisolated func`.

Run from the repository root:  python3 -I .claude/skills/sendable-nonisolated-sweep/sweep.py [--check] [--root DIR]

What it rewrites: in every Swift file of the `SafeDITool…Tests` targets (never `Tests/SafeDIToolTestSupport`,
whose readers of generated code are edited by hand in the source commit), each `@Sendable func __safeDI_` becomes
`@Sendable nonisolated func __safeDI_`. Every function SafeDI generates is named with the reserved `__safeDI_` prefix
(`SourceRuleTests` keeps the prefix in `ReservedName.swift`), and no fixture a person writes may use it (the graph
fuzzer checks that no label begins with it), so the pattern matches generated code only: the hand-written inputs and
`buildsTheSameValuesAs:` references that spell `@Sendable func a()` are left alone, and listed.

Expectations a test assembles by interpolation get the same rewrite where a `let NAME = CONDITION ? "@Sendable " : ""`
declares the prefix that `\(NAME)func __safeDI_` reads: where every use of `NAME` in its function precedes a generated
function, the declaration becomes `"@Sendable nonisolated "`; where `NAME` also spells a closure type, a declaration
`let NAMEFunctionPrefix = CONDITION ? "@Sendable nonisolated " : ""` is added after it and the function uses read it.
An inline `\(CONDITION ? "@Sendable " : "")func __safeDI_` is rewritten in place.

It is idempotent: a file already rewritten matches nothing. `--check` rewrites nothing and exits 1 when anything
would change. The report lists, per file, the lines rewritten, and every `@Sendable func ` the pattern left, which a
person reads: each must be a hand-written input, not generated code.
"""
import argparse
import pathlib
import re
import sys

OLD = "@Sendable func __safeDI_"
NEW = "@Sendable nonisolated func __safeDI_"
LEFT = re.compile(r"@Sendable func (?!__safeDI_)")
DECLARATION = re.compile(r'^(?P<indent>\t+)let (?P<name>\w+) = (?P<condition>[^\n?]+?) \? "@Sendable " : ""$')
MEMBER_FUNCTION = re.compile(r"^\t(?:(?:private|fileprivate|static|mutating|nonisolated|public|internal|@\w+(?:\([^)]*\))?)\s+)*func\s")
INLINE = re.compile(r'\\\((?P<condition>[^()"]+?) \? "@Sendable " : ""\)func __safeDI_')


def rewrite_interpolations(text: str) -> tuple[str, int]:
    """Rewrites the interpolated prefixes of generated functions; returns the text and how many uses changed."""
    lines = text.split("\n")
    changed = 0
    for index in range(len(lines)):
        match = DECLARATION.match(lines[index])
        if not match:
            continue
        name = match["name"]
        use = "\\(" + name + ")"
        function_use = use + "func __safeDI_"
        end = index + 1
        while end < len(lines) and not MEMBER_FUNCTION.match(lines[end]) and not re.match(r"^\t+let " + name + " = ", lines[end]):
            end += 1
        body = lines[index + 1:end]
        function_uses = sum(line.count(function_use) for line in body)
        if function_uses == 0:
            continue
        other_uses = sum(line.count(use) for line in body) - function_uses
        changed += function_uses
        if other_uses == 0:
            lines[index] = lines[index].replace('"@Sendable "', '"@Sendable nonisolated "')
        else:
            prefix_name = name + "FunctionPrefix"
            for offset in range(index + 1, end):
                lines[offset] = lines[offset].replace(function_use, "\\(" + prefix_name + ")func __safeDI_")
            lines.insert(index + 1, f'{match["indent"]}let {prefix_name} = {match["condition"]} ? "@Sendable nonisolated " : ""')
    text = "\n".join(lines)
    text, inline = INLINE.subn(lambda m: '\\(' + m["condition"] + ' ? "@Sendable nonisolated " : "")func __safeDI_', text)
    return text, changed + inline


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--root", default=".")
    arguments = parser.parse_args()
    tests = pathlib.Path(arguments.root) / "Tests"
    files = sorted(path for path in tests.glob("SafeDITool*Tests/**/*.swift"))
    if not files:
        print(f"no test files under {tests}", file=sys.stderr)
        return 2
    rewritten_total = 0
    left = []
    for path in files:
        original = path.read_text(encoding="utf-8")
        text, interpolated = rewrite_interpolations(original)
        count = text.count(OLD) + interpolated
        for number, line in enumerate(text.splitlines(), start=1):
            if LEFT.search(line):
                left.append(f"{path}:{number}: {line.strip()}")
        if count == 0:
            continue
        rewritten_total += count
        print(f"{'would rewrite' if arguments.check else 'rewrote'} {count:4d}  {path}")
        if not arguments.check:
            path.write_text(text.replace(OLD, NEW), encoding="utf-8")
        if interpolated:
            print(f"      of which {interpolated} interpolated")
    print(f"total: {rewritten_total} occurrence(s)")
    print(f"left for a person to confirm as hand-written input: {len(left)}")
    for line in left:
        print(f"  {line}")
    return 1 if arguments.check and rewritten_total else 0


if __name__ == "__main__":
    sys.exit(main())
