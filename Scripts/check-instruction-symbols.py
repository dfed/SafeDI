#!/usr/bin/env python3
"""Fails when an instruction file names a symbol the repository no longer has.

A rule that names a function or type is a pointer an agent follows: when the symbol was renamed or removed, the agent
searches for it, finds nothing, and either loses a turn or reasons from a mechanism that no longer exists. This reads
every Markdown instruction file (`CLAUDE.md` files and everything under `.claude/`), takes each backticked token shaped
like a Swift symbol (`camelCase`, `camelCase(label:)`, `Type.member`, `Type.Nested`), and looks its last name up, as
text, in every other tracked file. A name found nowhere is reported with the lines that use it.

Not checked: a name shorter than six characters, a name with an underscore (an example of a generated or test name),
and the names in EXTERNAL below, which other projects declare.

Usage: Scripts/check-instruction-symbols.py            (from anywhere in the checkout)
"""

import os
import re
import subprocess
import sys

# Names the instructions use that are declared outside this repository, each with where.
EXTERNAL = {
    "pluginGeneratedSources": "SwiftPM's PackagePlugin API",
}

SYMBOL = re.compile(
    r"(?:[A-Z][A-Za-z0-9<>]*\.)+([A-Za-z][A-Za-z0-9]*)(?:\([^)]*\))?"  # Type.member, Type.Nested, Type.method(label:)
    r"|([a-z][a-z0-9]*[A-Z][A-Za-z0-9]*)(?:\([^)]*\))?"  # camelCase, camelCase(label:)
)


def is_instruction(path):
    return path.endswith(".md") and (path == "CLAUDE.md" or path.endswith("/CLAUDE.md") or path.startswith(".claude/"))


def main():
    os.chdir(subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip())
    tracked = [path for path in subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True).stdout.split("\n") if path and not os.path.islink(path)]
    texts = []
    for path in tracked:
        if is_instruction(path):
            continue
        try:
            with open(path, encoding="utf-8") as file:
                texts.append(file.read())
        except (UnicodeDecodeError, OSError):
            continue
    corpus = "\n".join(texts)
    missing = {}
    for path in tracked:
        if not is_instruction(path):
            continue
        with open(path, encoding="utf-8") as file:
            for number, line in enumerate(file.read().split("\n"), 1):
                for token in re.findall(r"`([^`\n]+)`", line):
                    match = SYMBOL.fullmatch(token)
                    if not match:
                        continue
                    name = match.group(1) or match.group(2)
                    if len(name) < 6 or name in EXTERNAL or name in corpus:
                        continue
                    missing.setdefault(name, []).append(f"{path}:{number}")
    for name in sorted(missing):
        print(f"{name}: named by {', '.join(missing[name])}, found in no other tracked file")
    if missing:
        print("An instruction file names a symbol the repository does not have. Name the symbol that replaced it, or describe the behavior without a name.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
