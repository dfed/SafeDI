#!/usr/bin/env python3
"""Usage: apply-edit.py FILE OLD_FILE NEW_FILE [--all] [--trim-final-newline]
       apply-edit.py --edits EDITS.json
       apply-edit.py --self-test DIRECTORY

Replaces exact text in a file, with the old and the new text read from files, so that an edit holding tabs, quotes,
backslashes or many lines never has to be spelled in a shell command. Run it with `python3 -I`.

FILE OLD_FILE NEW_FILE replaces the one occurrence of OLD_FILE's content in FILE with NEW_FILE's content. Text that
occurs more than once is an error unless --all is given, which replaces every occurrence; occurrences that overlap,
as "aa" occurs twice in "aaa", are an error either way.

--edits EDITS.json applies a list of edits, in order: [{"file": "path", "old": "…", "new": "…", "all": false}, …].
A path is relative to the current directory. A later edit of a file sees the earlier ones, also when it names the
file by another path, in another case on a volume that ignores case, or through a symbolic link. A file with a
second hard link is refused, since replacing it would leave the other name with the old content.

--trim-final-newline drops one final newline from each old and new text read from a file, for an editor that ends
every file with one. Texts of EDITS.json are taken as they are, so the option beside --edits is wrong usage.

Nothing is written unless every edit applies: a file that does not exist or cannot be written, old text that is
empty, equal to the new text, absent, or present more than once without --all, and new text UTF-8 cannot spell, stop
the script with exit status 1 and name the edit. Every new file is then written beside the file it replaces, and
only when all are written does each take its file's place, so a file is never left half written, and it keeps its
permissions. A replacement that then fails stops the script, which names the files already replaced. Files are read
and written as UTF-8, byte for byte otherwise (no newline translation). Exit status 2 on wrong usage.

--self-test DIRECTORY writes fixtures into DIRECTORY, which must not exist, and checks each case.
"""
import argparse
import json
import os
import shutil
import sys
import tempfile


class EditError(Exception):
    """An edit that does not apply. Nothing was written, unless `wrote_files`."""

    def __init__(self, message, wrote_files=False):
        super().__init__(message)
        self.wrote_files = wrote_files


def read_text(path):
    try:
        with open(path, encoding="utf-8", newline="") as text_file:
            return text_file.read()
    except (OSError, UnicodeDecodeError) as error:
        raise EditError(f"{path} cannot be read: {error}")


def trimmed(text):
    return text[:-1] if text.endswith("\n") else text


def occurrence_starts(text, old):
    """Where `old` starts in `text`, counting occurrences that overlap."""
    starts = []
    start = text.find(old)
    while start >= 0:
        starts.append(start)
        start = text.find(old, start + 1)
    return starts


def replace_file(temporary_path, path):
    """Puts the file at `temporary_path` in the place of `path`. The self-test replaces it to fail a replacement."""
    os.replace(temporary_path, path)


def apply_edits(edits):
    """Applies `edits`, each (name, path, old, new, replaces all), and writes the files only when all apply. Returns
    the number of replacements per path as first given, in the order the files first appear."""
    contents = {}  # the file's real path, as first given → its content
    given_paths = {}
    counts = {}
    real_paths = {}  # the file's device and inode → its real path, as first given
    for name, path, old, new, replaces_all in edits:
        real_path = os.path.realpath(path)
        try:
            status = os.stat(real_path)
        except OSError as error:
            raise EditError(f"{path} cannot be read: {error}")
        # One file has one device and inode, however its path is spelled; realpath keeps the case it is given.
        real_path = real_paths.setdefault((status.st_dev, status.st_ino), real_path)
        if real_path not in contents:
            if status.st_nlink > 1:
                raise EditError(f"{path} has {status.st_nlink} hard links; replacing it would leave the others with the old content")
            contents[real_path] = read_text(real_path)
            given_paths[real_path] = path
            counts[real_path] = 0
        if not old:
            raise EditError(f"{name}: the old text is empty")
        if old == new:
            raise EditError(f"{name}: the old and the new text are equal")
        starts = occurrence_starts(contents[real_path], old)
        if not starts:
            raise EditError(f"{name}: {path} does not hold the old text")
        if any(following - start < len(old) for start, following in zip(starts, starts[1:])):
            raise EditError(f"{name}: {path} holds the old text {len(starts)} times, some overlapping; give more of the text around the one meant")
        if len(starts) > 1 and not replaces_all:
            raise EditError(f"{name}: {path} holds the old text {len(starts)} times; pass --all (or \"all\": true) to replace each")
        contents[real_path] = contents[real_path].replace(old, new)
        counts[real_path] += len(starts)
    encoded = {}
    for real_path, content in contents.items():
        try:
            encoded[real_path] = content.encode("utf-8")
        except UnicodeEncodeError as error:
            raise EditError(f"{given_paths[real_path]}: the new text cannot be written as UTF-8: {error}")
        if not os.access(real_path, os.W_OK):
            raise EditError(f"{given_paths[real_path]} cannot be written")
        if not os.access(os.path.dirname(real_path), os.W_OK):
            raise EditError(f"{given_paths[real_path]} cannot be replaced: its directory cannot be written")
    temporary_paths = {}
    replaced = []
    try:
        for real_path, data in encoded.items():
            try:
                descriptor, temporary_paths[real_path] = tempfile.mkstemp(dir=os.path.dirname(real_path), prefix=".apply-edit-")
                with os.fdopen(descriptor, "wb") as temporary_file:
                    temporary_file.write(data)
                shutil.copymode(real_path, temporary_paths[real_path])
            except OSError as error:
                raise EditError(f"{given_paths[real_path]} cannot be written: {error}")
        for real_path in encoded:
            try:
                replace_file(temporary_paths[real_path], real_path)
            except OSError as error:
                written = f", after writing {', '.join(replaced)}" if replaced else ""
                raise EditError(f"{given_paths[real_path]} cannot be replaced{written}: {error}", wrote_files=bool(replaced))
            del temporary_paths[real_path]
            replaced.append(given_paths[real_path])
    finally:
        for temporary_path in temporary_paths.values():
            if os.path.exists(temporary_path):
                os.unlink(temporary_path)
    return {given_paths[real_path]: count for real_path, count in counts.items()}


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
    # A relative link target would be read from the link's directory.
    root = os.path.abspath(root)
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
    expect(run("--edits", write("empty.json", "[]")) == 1, "an empty list is refused")
    expect(run("--edits", write("extra.json", json.dumps([{"file": first, "old": "one", "new": "two", "more": 1}]))) == 1, "an edit with an unknown key is refused")
    expect(run("--edits", edits, "--trim-final-newline") == 2, "--trim-final-newline beside --edits is wrong usage")
    expect(run("--edits", edits, "--all") == 2 and run("--edits", edits, first) == 2 and run(first) == 2 and run("--self-test", root, "--all") == 2, "wrong usage is exit status 2")
    expect(run(first, os.path.join(root, "absent.old"), os.path.join(root, "absent.new"), "--al") == 2, "an abbreviated option is wrong usage")

    # One file named two ways, also through a symbolic link, is one file: the second edit sees the first.
    spelled = write("spelled.swift", "one two\n")
    link = os.path.join(root, "link.swift")
    os.symlink(spelled, link)
    edits = write("spelled.json", json.dumps([
        {"file": spelled, "old": "one", "new": "three"},
        {"file": os.path.join(root, ".", "spelled.swift"), "old": "two", "new": "four"},
        {"file": link, "old": "three four", "new": "five"},
    ]))
    status = run("--edits", edits)
    expect(status == 0 and read_text(spelled) == "five\n" and os.path.islink(link), "one file named three ways takes every edit, and the link stays a link")

    # Occurrences that overlap are counted, and refused even with --all.
    target = write("overlap.swift", "aaa\n")
    expect(run(target, write("overlap.old", "aa"), write("overlap.new", "b")) == 1, "overlapping occurrences are refused")
    expect(run(target, os.path.join(root, "overlap.old"), os.path.join(root, "overlap.new"), "--all") == 1 and read_text(target) == "aaa\n", "overlapping occurrences are refused with --all")

    # Text UTF-8 cannot spell, and a file that cannot be written, stop every write, and no file is left empty.
    kept = write("kept.swift", "keep me\n")
    other = write("other.swift", "other\n")
    edits = write("surrogate.json", '[{"file": ' + json.dumps(other) + ', "old": "other", "new": "changed"}, {"file": ' + json.dumps(kept) + ', "old": "keep", "new": "\\ud800"}]')
    status = run("--edits", edits)
    expect(status == 1 and read_text(kept) == "keep me\n" and read_text(other) == "other\n", "new text UTF-8 cannot spell writes nothing")
    os.chmod(kept, 0o444)
    edits = write("readonly.json", json.dumps([{"file": other, "old": "other", "new": "changed"}, {"file": kept, "old": "keep", "new": "lose"}]))
    # The superuser can write a read-only file, so there the edit applies.
    if os.access(kept, os.W_OK):
        print("skipped: a file that cannot be written (this user can write a read-only file)")
    else:
        status = run("--edits", edits)
        expect(status == 1 and read_text(kept) == "keep me\n" and read_text(other) == "other\n", "a file that cannot be written stops every write")

    # A rewritten file keeps its permissions, and nothing is left beside it.
    mode = write("mode.swift", "other\n")
    os.chmod(mode, 0o755)
    status = run(mode, write("mode.old", "other"), write("mode.new", "changed"))
    expect(status == 0 and os.stat(mode).st_mode & 0o777 == 0o755 and read_text(mode) == "changed\n", "a rewritten file keeps its permissions")
    expect(not [name for name in os.listdir(root) if name.startswith(".apply-edit-")], "no temporary file is left")

    # A file named in another case is the same file where the volume ignores case.
    cased = write("cased.swift", "one two\n")
    other_case = os.path.join(root, "CASED.swift")
    edits = write("cased.json", json.dumps([{"file": cased, "old": "one", "new": "three"}, {"file": other_case, "old": "two", "new": "four"}]))
    if os.path.exists(other_case):
        expect(run("--edits", edits) == 0 and read_text(cased) == "three four\n", "one file named in two cases takes both edits")
    else:
        print("skipped: one file named in two cases (this volume tells cases apart)")

    # A file with a second hard link is refused, and both names keep the content.
    linked = write("linked.swift", "one\n")
    second_name = os.path.join(root, "linked-again.swift")
    os.link(linked, second_name)
    status = run(linked, write("linked.old", "one"), write("linked.new", "two"))
    expect(status == 1 and read_text(linked) == "one\n" and read_text(second_name) == "one\n", "a file with two hard links is refused")

    # A replacement that fails leaves no temporary file, and names what was replaced before it.
    global replace_file
    earlier = write("earlier.swift", "one\n")
    later = write("later.swift", "two\n")
    edits = write("replace.json", json.dumps([{"file": earlier, "old": "one", "new": "three"}, {"file": later, "old": "two", "new": "four"}]))
    genuine_replace_file = replace_file

    def failing_replace_file(temporary_path, path):
        if path == os.path.realpath(later):
            raise OSError("the self-test fails this replacement")
        genuine_replace_file(temporary_path, path)

    replace_file = failing_replace_file
    try:
        status = run("--edits", edits)
    finally:
        replace_file = genuine_replace_file
    expect(status == 1 and read_text(earlier) == "three\n" and read_text(later) == "two\n", "a failed replacement keeps the file it could not replace")
    expect(not [name for name in os.listdir(root) if name.startswith(".apply-edit-")], "a failed replacement leaves no temporary file")

    for failure in failures:
        print(f"FAILED: {failure}", file=sys.stderr)
    if failures:
        return 1
    print("self-test passed")
    return 0


def main(argv):
    parser = argparse.ArgumentParser(description="Replace exact text in a file, with the texts read from files.", allow_abbrev=False)
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
    if (arguments.edits is None) == (None in positional) or (arguments.edits is not None and (any(positional) or arguments.all or arguments.trim_final_newline)):
        print(__doc__.split("\n\n")[0], file=sys.stderr)
        return 2
    try:
        counts = apply_edits(edits_of(arguments))
    except EditError as error:
        print(f"apply-edit: {error}" if error.wrote_files else f"apply-edit: {error}; nothing was written", file=sys.stderr)
        return 1
    for path, count in counts.items():
        print(f"{path}: {count} replacement{'' if count == 1 else 's'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
