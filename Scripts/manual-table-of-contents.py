"""usage: manual-table-of-contents.py [--check] [MANUAL]

Regenerates the "## Contents" section of MANUAL (default
Documentation/Manual.md) from its headings: every second-level heading other
than Contents, with its third-level headings nested beneath it, each linked to
the anchor GitHub gives it. Headings inside fenced code blocks are skipped.

With --check, it changes nothing: it prints the difference and exits non-zero
when the committed section differs from the one it would write.
"""

import difflib
import os
import re
import sys

CONTENTS_HEADING = "## Contents"
HEADING = re.compile(r"^(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$")
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})")


def headings(lines):
    """Yields (index, level, text) for each heading outside a fenced code block."""
    fence = None
    for index, line in enumerate(lines):
        match = FENCE.match(line)
        if fence is None and match:
            fence = match.group(1)
        elif fence is not None:
            if match and match.group(1)[0] == fence[0] and len(match.group(1)) >= len(fence) and not line.strip().strip(fence[0]):
                fence = None
        else:
            heading = HEADING.match(line)
            if heading:
                yield index, len(heading.group(1)), heading.group(2)


def slug(text):
    """The anchor GitHub gives a heading, before it makes repeated anchors unique."""
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)  # A link's text.
    text = re.sub(r"<[^>]+>", "", text)  # Inline HTML.
    text = text.replace("`", "")
    return re.sub(r"[^\w\- ]", "", text.lower()).replace(" ", "-")


def contents(lines):
    entries = []
    used = {}
    for _, level, text in headings(lines):
        base = slug(text)
        anchor = base
        while anchor in used:
            used[base] += 1
            anchor = f"{base}-{used[base]}"
        used[anchor] = 0
        if level == 2 and f"## {text}" != CONTENTS_HEADING:
            entries.append(f"- [{text}](#{anchor})")
        elif level == 3:
            entries.append(f"  - [{text}](#{anchor})")
    return [CONTENTS_HEADING, ""] + entries + [""]


def main(arguments):
    check = "--check" in arguments
    paths = [argument for argument in arguments if argument != "--check"]
    repository = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = paths[0] if paths else os.path.join(repository, "Documentation", "Manual.md")
    with open(path, encoding="utf-8") as file:
        lines = file.read().split("\n")

    second_level = [index for index, level, _ in headings(lines) if level == 2]
    starts = [index for index in second_level if lines[index] == CONTENTS_HEADING]
    if starts:
        start = starts[0]
        end = next((index for index in second_level if index > start), len(lines))
    elif second_level:
        start = end = second_level[0]
    else:
        print(f"{path} has no second-level heading to put the contents before", file=sys.stderr)
        return 1

    updated = lines[:start] + contents(lines) + lines[end:]
    if updated == lines:
        return 0
    if check:
        sys.stdout.writelines(difflib.unified_diff(
            [line + "\n" for line in lines],
            [line + "\n" for line in updated],
            fromfile=f"{path} (committed)",
            tofile=f"{path} (regenerated)",
        ))
        print(f"The Contents section of {path} is out of date; run python3 -I Scripts/manual-table-of-contents.py to regenerate it.")
        return 1
    with open(path, "w", encoding="utf-8") as file:
        file.write("\n".join(updated))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
