#!/usr/bin/env python3
"""Rewrite SafeDITool test expectations for E3 (SB-14): every generated `@Sendable` local function is spelled
`@Sendable nonisolated func`.

Run from the repository root:  python3 -I .claude/skills/sendable-nonisolated-sweep/sweep.py [--check] [--root DIR]

What it rewrites: in every Swift file of the `SafeDITool…Tests` targets (never `Tests/SafeDIToolTestSupport`,
whose readers of generated code are edited by hand in the source commit), each `@Sendable func __safeDI_` becomes
`@Sendable nonisolated func __safeDI_`. Every function SafeDI generates is named with the reserved `__safeDI_` prefix
(`SourceRuleTests` keeps the prefix in `ReservedName.swift`), and no fixture a person writes may use it (the graph
fuzzer checks that no label begins with it), so the pattern matches generated code only: the hand-written inputs and
`buildsTheSameValuesAs:` references that spell `@Sendable func a()` are left alone, and listed.

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
        text = path.read_text(encoding="utf-8")
        count = text.count(OLD)
        for number, line in enumerate(text.splitlines(), start=1):
            if LEFT.search(line):
                left.append(f"{path}:{number}: {line.strip()}")
        if count == 0:
            continue
        rewritten_total += count
        print(f"{'would rewrite' if arguments.check else 'rewrote'} {count:4d}  {path}")
        if not arguments.check:
            path.write_text(text.replace(OLD, NEW), encoding="utf-8")
    print(f"total: {rewritten_total} occurrence(s) in {sum(1 for p in files if OLD in p.read_text(encoding='utf-8')) if arguments.check else 'the files above'}")
    print(f"left for a person to confirm as hand-written input: {len(left)}")
    for line in left:
        print(f"  {line}")
    return 1 if arguments.check and rewritten_total else 0


if __name__ == "__main__":
    sys.exit(main())
