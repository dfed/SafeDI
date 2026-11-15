#!/usr/bin/env python3
"""Usage: apply-edit.py FILE OLD_FILE NEW_FILE [--all] [--trim-final-newline]
       apply-edit.py --edits EDITS.json [--trim-final-newline]
       apply-edit.py --self-test DIR

Replaces exact text in a file, with the old and the new text read from files, so that an edit holding tabs, quotes,
backslashes or many lines never has to be spelled in a shell command. Run it with `python3 -I`.

FILE OLD_FILE NEW_FILE replaces the one occurrence of OLD_FILE's content in FILE with NEW_FILE's content. Text that
occurs more than once is an error unless --all is given, which replaces every occurrence.

--edits EDITS.json applies a list of edits, in order: [{"file": "path", "old": "…", "new": "…", "all": false}, …].
A path is relative to the current directory. A later edit of a file sees the earlier ones.

--trim-final-newline drops one final newline from each old and new text read from a file, for an editor that ends
every file with one. Texts of EDITS.json are taken as they are.

Nothing is written unless every edit applies: a file that does not exist, old text that is empty, equal to the new
text, absent, or present more than once without --all, stops the script with exit status 1 and names the edit.
Files are read and written as UTF-8, byte for byte otherwise (no newline translation). Exit status 2 on wrong usage.

--self-test DIR writes fixtures into DIR, which must not exist, and checks each case.
"""
import argparse
import json
import os
import sys


class EditError(Exception):
    """An edit that does not apply; nothing is written."""


def read_text(path):
    try:
        with open(path, encoding="utf-8", newline="") as text_file:
            return text_file.read()
    except (OSError, UnicodeDecodeError) as error:
        raise EditError(f"{path} cannot be read: {error}")


def trimmed(text):
    return text[:-1] if text.endswith("\n") else text


def apply_edits(edits):
    """Applies `edits`, each (name, path, old, new, replaces all), and writes the files only when all apply. Returns
    the number of replacements per path, in the order the paths first appear."""
    contents = {}
    counts = {}
    for name, path, old, new, replaces_all in edits:
        if path not in contents:
            contents[path] = read_text(path)
            counts[path] = 0
        if not old:
            raise EditError(f"{name}: the old text is empty")
        if old == new:
            raise EditError(f"{name}: the old and the new text are equal")
        occurrences = contents[path].count(old)
        if occurrences == 0:
            raise EditError(f"{name}: {path} does not hold the old text")
        if occurrences > 1 and not replaces_all:
            raise EditError(f"{name}: {path} holds the old text {occurrences} times; pass --all (or \"all\": true) to replace each")
        contents[path] = contents[path].replace(old, new)
        counts[path] += occurrences
    for path, content in contents.items():
        with open(path, "w", encoding="utf-8", newline="") as text_file:
            text_file.write(content)
    return counts


def edits_of(arguments):
    if arguments.edits is not None:
        try:
            entries = json.loads(read_text(arguments.edits))
        except json.JSONDecodeError as error:
            raise EditError(f"{arguments.edits} is not JSON: {error}")
        if not isinstance(entries, list) or not entries:
            raise EditError(f"{arguments.edits} must hold a list of edits")
        edits = []
        for index, entry in enumerate(entries):
            name = f"edit {index + 1}"
            if not isinstance(entry, dict) or set(entry) - {"file", "old", "new", "all"} or not all(isinstance(entry.get(key), str) for key in ("file", "old", "new")) or not isinstance(entry.get("all", False), bool):
                raise EditError(f"{name}: an edit is {{\"file\", \"old\", \"new\"}} strings and an optional \"all\" boolean")
            edits.append((name, entry["file"], entry["old"], entry["new"], entry.get("all", False)))
        return edits
    old, new = read_text(arguments.old_file), read_text(arguments.new_file)
    if arguments.trim_final_newline:
        old, new = trimmed(old), trimmed(new)
    return [("the edit", arguments.file, old, new, arguments.all)]


def self_test(root):
    if os.path.exists(root):
        print(f"{root} exists; --self-test writes a new directory", file=sys.stderr)
        return 2
    os.makedirs(root)
    failures = []

    def write(name, content):
        path = os.path.join(root, name)
        with open(path, "w", encoding="utf-8", newline="") as text_file:
            text_file.write(content)
        return path

    def run(*argv):
        return main(list(argv))

    def expect(condition, description):
        if not condition:
            failures.append(description)

    # One occurrence, with tabs, quotes, a backslash and a line break.
    target = write("one.swift", 'func a() {\n\tlet b = "c\\(d)"\n}\n')
    status = run(target, write("one.old", '\tlet b = "c\\(d)"\n}'), write("one.new", '\tlet b = "e"\n\treturn\n}'))
    expect(status == 0 and read_text(target) == 'func a() {\n\tlet b = "e"\n\treturn\n}\n', "one occurrence is replaced")

    # A final newline an editor added is dropped only on request.
    target = write("trim.swift", "a b c\n")
    status = run(target, write("trim.old", "b\n"), write("trim.new", "d\n"))
    expect(status == 1 and read_text(target) == "a b c\n", "a final newline is part of the text by default")
    status = run(target, os.path.join(root, "trim.old"), os.path.join(root, "trim.new"), "--trim-final-newline")
    expect(status == 0 and read_text(target) == "a d c\n", "--trim-final-newline drops one final newline of each text")

    # More than one occurrence needs --all.
    target = write("all.swift", "x y x\r\n")
    status = run(target, write("all.old", "x"), write("all.new", "z"))
    expect(status == 1 and read_text(target) == "x y x\r\n", "two occurrences are refused")
    status = run(target, os.path.join(root, "all.old"), os.path.join(root, "all.new"), "--all")
    expect(status == 0 and read_text(target) == "z y z\r\n", "--all replaces each occurrence and keeps the line ending")

    # Absent, empty and unchanged text are refused.
    target = write("refused.swift", "a\n")
    expect(run(target, write("absent.old", "b"), write("absent.new", "c")) == 1, "absent old text is refused")
    expect(run(target, write("empty.old", ""), write("empty.new", "c")) == 1, "empty old text is refused")
    expect(run(target, write("equal.old", "a"), write("equal.new", "a")) == 1, "equal texts are refused")
    expect(run(os.path.join(root, "missing.swift"), os.path.join(root, "absent.old"), os.path.join(root, "absent.new")) == 1, "a missing file is refused")
    expect(read_text(target) == "a\n", "a refused edit writes nothing")

    # A list of edits applies in order, each seeing the earlier ones, and all or none.
    first = write("first.swift", "one two\n")
    second = write("second.swift", "three three\n")
    edits = write("edits.json", json.dumps([
        {"file": first, "old": "one", "new": "two"},
        {"file": first, "old": "two two", "new": "four"},
        {"file": second, "old": "three", "new": "five", "all": True},
    ]))
    status = run("--edits", edits)
    expect(status == 0 and read_text(first) == "four\n" and read_text(second) == "five five\n", "a list of edits applies in order")
    first = write("first.swift", "one two\n")
    edits = write("edits.json", json.dumps([{"file": first, "old": "one", "new": "two"}, {"file": second, "old": "absent", "new": "x"}]))
    status = run("--edits", edits)
    expect(status == 1 and read_text(first) == "one two\n", "a list with an edit that does not apply writes nothing")
    expect(run("--edits", write("shape.json", json.dumps([{"file": first, "old": "one"}]))) == 1, "an edit without new text is refused")
    expect(run("--edits", write("notjson.json", "[")) == 1, "a list that is not JSON is refused")

    for failure in failures:
        print(f"FAILED: {failure}", file=sys.stderr)
    if failures:
        return 1
    print("self-test passed")
    return 0


def main(argv):
    parser = argparse.ArgumentParser(description="Replace exact text in a file, with the texts read from files.", add_help=True)
    parser.add_argument("file", nargs="?")
    parser.add_argument("old_file", nargs="?")
    parser.add_argument("new_file", nargs="?")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--trim-final-newline", action="store_true")
    parser.add_argument("--edits")
    parser.add_argument("--self-test")
    try:
        arguments = parser.parse_args(argv)
    except SystemExit as exit_request:
        return 0 if exit_request.code == 0 else 2
    positional = [arguments.file, arguments.old_file, arguments.new_file]
    if arguments.self_test is not None:
        if arguments.edits is not None or any(positional) or arguments.all or arguments.trim_final_newline:
            print("--self-test takes a directory and nothing else", file=sys.stderr)
            return 2
        return self_test(arguments.self_test)
    if (arguments.edits is None) == (None in positional) or (arguments.edits is not None and (any(positional) or arguments.all)):
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        return 2
    try:
        counts = apply_edits(edits_of(arguments))
    except EditError as error:
        print(f"apply-edit: {error}; nothing was written", file=sys.stderr)
        return 1
    for path, count in counts.items():
        print(f"{path}: {count} replacement{'' if count == 1 else 's'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
