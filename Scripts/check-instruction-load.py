#!/usr/bin/env python3
"""Fails when reading one tracked file would load too many characters of rules.

Each `.claude/rules/*.md` file loads when a session reads or edits a file one of its
`paths:` globs matches, so what a file costs is the sum of every rules file that
matches it. A cap on each rules file's own size does not bound that sum: splitting a
rules file in two under the same globs keeps both halves loading together.

With `--report FILE…` it prints what each named file loads instead, largest first.
"""

import re
import subprocess
import sys
from pathlib import Path

# The most rules one file may load, in characters. Lower it when a change brings
# the largest load down, so that the gain is kept.
BUDGET = 424_000


def braces_expanded(pattern):
    match = re.search(r"\{([^{}]*)\}", pattern)
    if match is None:
        return [pattern]
    expanded = []
    for alternative in match.group(1).split(","):
        expanded += braces_expanded(pattern[: match.start()] + alternative + pattern[match.end() :])
    return expanded


def regular_expression(pattern):
    parts = []
    index = 0
    while index < len(pattern):
        if pattern.startswith("**/", index):
            parts.append("(?:.*/)?")
            index += 3
        elif pattern.startswith("**", index):
            parts.append(".*")
            index += 2
        elif pattern[index] == "*":
            parts.append("[^/]*")
            index += 1
        elif pattern[index] == "?":
            parts.append("[^/]")
            index += 1
        else:
            parts.append(re.escape(pattern[index]))
            index += 1
    return re.compile("".join(parts) + r"\Z")


def rules():
    """Each rules file's name, its length in characters, and its globs as regular expressions."""
    found = []
    for path in sorted(Path(".claude/rules").glob("*.md")):
        text = path.read_text(encoding="utf-8")
        frontmatter = text.split("---", 2)[1] if text.startswith("---") else ""
        globs = re.findall(r'^\s*-\s*"?([^"\n]+?)"?\s*$', frontmatter, flags=re.MULTILINE)
        expressions = [regular_expression(expanded) for glob in globs for expanded in braces_expanded(glob)]
        found.append((path.name, len(text), expressions))
    return found


def load(file, all_rules):
    """The rules files `file` loads, as (name, characters) pairs."""
    return [(name, size) for name, size, expressions in all_rules if any(expression.match(file) for expression in expressions)]


def main():
    all_rules = rules()
    if len(sys.argv) > 1 and sys.argv[1] == "--report":
        for file in sys.argv[2:]:
            loaded = sorted(load(file, all_rules), key=lambda pair: -pair[1])
            print(f"{file}: {sum(size for _, size in loaded):,} characters of rules in {len(loaded)} files")
            for name, size in loaded:
                print(f"  {size:>7,}  {name}")
        return 0
    tracked = subprocess.run(["git", "ls-files"], check=True, capture_output=True, text=True).stdout.splitlines()
    status = 0
    for file in tracked:
        loaded = load(file, all_rules)
        total = sum(size for _, size in loaded)
        if total > BUDGET:
            largest = ", ".join(name for name, _ in sorted(loaded, key=lambda pair: -pair[1])[:3])
            print(
                f"{file}: reading it loads {total:,} characters of rules from {len(loaded)} files, over the budget of {BUDGET:,}; "
                f"narrow the paths: of a rules file that does not govern it (the largest it loads: {largest})"
            )
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
