#!/usr/bin/env python3
"""Splits a large Swift source file into files by concern, moving whole declarations and changing nothing else.

  python3 -I split-generator.py [--map MAP.json] [--checkout DIRECTORY] [--dry-run] [--list]
  python3 -I split-generator.py --self-test DIRECTORY

The map (default: `split-map.json` beside this script) names, for each source file, the type whose members move and
the runs of members that go to each new file. The script reads declarations, not line numbers, so it can be run again
on a later commit of the same file: a member added inside a run goes where its run goes.

What moves
  - A unit is one member of the type (with the comments and attributes above it), or one top-level declaration after
    the type (an extension of it or of another type). Units are read from the source file's text as it is.
  - `runs` is a list of `[anchor, file]`. An anchor is a unit's kind and name, such as `func generateMockCode` or
    `extension Instantiable`; it names the first unit in source order with that kind and name, and
    `func name#2` the second. A unit belongs to the
    run of the nearest anchor at or above it, and the units above the first anchor stay. `file` is a new file's name,
    or `stay`. An anchor no unit matches is an error: the map is then older than the source, and is to be updated.
  - A stored instance property, an initializer and a deinitializer never move: an extension cannot hold them.
  - A moved member goes into `extension <Type> { … }` in its file, in source order, with its text unchanged. A moved
    top-level declaration follows that extension. A `// MARK:` line above a moved unit is dropped. The new file starts
    with the source file's leading comment (the license) and its imports.
  - When a file the map names already exists, its units are read too and stay where they are, so a second run over a
    split tree changes nothing.

Access
  A `private` or `fileprivate` declaration that a unit in another file names loses that modifier, since `private`
  reaches only the same file. So does a `private` or `fileprivate` type that a declaration which is no longer private
  names in its signature. Nothing else changes level. A name is matched as a word, so two private declarations that
  share a name are treated alike.

What else it updates (each only when the map asks, and each reported)
  - `relocate`: string literals that pair a path with a piece of code (`ErrorReportingSite(path:code:)`): the path
    stays when the source file still holds the code, and otherwise becomes the first file, in path order, that does.
  - `replace`: literal text replacements in named files, for prose that names the source file. One whose old text is
    missing is reported and skipped, unless its new text is already there.
  - It reports, and does not edit: `Scripts/unmeasured-files.txt` (a new file needs a line only when it holds no
    executable code, which the coverage check then says), and every other file that names the source file.

It checks its own work: every line of every unit is in exactly one file afterwards, in the same order within its unit,
with only the access modifiers above removed. It does not build: build, run the suite, and run `./CLI/lint.sh`
afterwards. Exit status 0 when it wrote (or would write), 1 when the tree was already split as the map says, 2 on an
error, with nothing written.
"""

import json
import os
import re
import shutil
import sys

DECLARATION = re.compile(
    r"^(?P<attributes>(?:@\w+(?:\((?:[^()]|\([^()]*\))*\))?\s+)*)"
    r"(?P<modifiers>(?:(?:public|private|fileprivate|internal|package|open|static|class(?=\s+(?:func|var|let|subscript))|nonisolated|lazy|final|indirect|mutating|nonmutating|override|required|convenience|isolated|consuming|borrowing|weak|unowned)(?:\(\w+\))?\s+)*)"
    r"(?P<kind>func|var|let|struct|enum|class|actor|protocol|typealias|init|deinit|subscript|extension|case|import|associatedtype)\b[?!]?\s*"
    r"(?P<name>`[^`]+`|[\w.]+(?:<[^>{]*>)?|)",
)
TYPE_KINDS = ("struct", "enum", "class", "actor", "protocol", "typealias")
PRIVATE = re.compile(
    r"\b(?P<level>private|fileprivate)(?!\()\s+(?P<modifiers>(?:(?:static|class|nonisolated|lazy|final|indirect|mutating|nonmutating|override|required|convenience|weak|unowned)\s+)*)"
    r"(?P<kind>func|var|let|struct|enum|class|actor|protocol|typealias|init|subscript)\b[?!]?\s*(?P<name>`[^`]+`|\w+|)",
)


class Problem(Exception):
    pass


# MARK: Reading Swift

def string_end(text, index, interpolations=None):
    """The index after the string literal that starts at `index`, whose interpolations may hold literals of their own.
    Where `interpolations` is a list, the (start, end) of each interpolation's code is appended to it."""
    length = len(text)
    hashes = len(re.match(r"#*", text[index:]).group(0))
    index += hashes
    quote = '"""' if text.startswith('"""', index) else '"'
    index += len(quote)
    closing = quote + "#" * hashes
    escape = "\\" + "#" * hashes
    while index < length and not text.startswith(closing, index):
        if text.startswith(escape + "(", index):
            index += len(escape) + 1
            interpolation_start = index
            depth = 1
            while index < length and depth:
                if text[index] == '"' or re.match(r'#+"', text[index:]):
                    index = string_end(text, index, interpolations)
                    continue
                depth += {"(": 1, ")": -1}.get(text[index], 0)
                index += 1
            if interpolations is not None:
                interpolations.append((interpolation_start, index - 1))
        elif text.startswith(escape, index):
            index += len(escape) + 1
        else:
            index += 1
    return min(length, index + len(closing))


def masked(text, keeping_interpolations=False):
    """`text` with every comment and string literal's characters replaced by spaces, so that offsets stay; where
    `keeping_interpolations`, the code inside each string literal's interpolations stays, since it names declarations."""
    out = list(text)
    index = 0
    length = len(text)

    def blank(start, end):
        for position in range(start, end):
            if out[position] != "\n":
                out[position] = " "

    while index < length:
        if text.startswith("//", index):
            end = text.find("\n", index)
            end = length if end < 0 else end
            blank(index, end)
            index = end
        elif text.startswith("/*", index):
            depth, end = 1, index + 2
            while end < length and depth:
                if text.startswith("/*", end):
                    depth, end = depth + 1, end + 2
                elif text.startswith("*/", end):
                    depth, end = depth - 1, end + 2
                else:
                    end += 1
            blank(index, end)
            index = end
        elif text[index] == '"' or (text[index] == "#" and re.match(r'#+"', text[index:])):
            interpolations = []
            end = string_end(text, index, interpolations)
            blank(index, end)
            if keeping_interpolations:
                for start, interpolation_end in interpolations:
                    for position in range(start, interpolation_end):
                        out[position] = text[position]
            index = end
        else:
            index += 1
    return "".join(out)


def matching(code, opening):
    depth = 0
    for index in range(opening, len(code)):
        if code[index] in "{([":
            depth += 1
        elif code[index] in "})]":
            depth -= 1
            if depth == 0:
                return index
    raise Problem("no bracket closes the one at offset %d" % opening)


class Unit:
    """One declaration with the comments and attributes above it: lines [first, last) of its file."""

    def __init__(self, path, lines, code_lines, first, declaration, last, top_level):
        self.path = path
        self.top_level = top_level
        self.lines = lines[first:last]
        self.code_lines = code_lines[first:last]
        self.first, self.last = first, last
        self.head_line = declaration - first
        code = "\n".join(self.code_lines[self.head_line:]).strip()
        match = DECLARATION.match(code)
        if not match or not match.group("kind"):
            raise Problem("%s:%d: not a declaration this script reads: %s" % (path, declaration + 1, code.split("\n")[0][:100]))
        self.kind = match.group("kind")
        name = match.group("name").strip()
        if self.kind == "extension":
            name = re.sub(r"\s+", " ", re.split(r"\s*\{|:\s*\w[\w., ]*\{| where ", code[match.start("name"):], maxsplit=1)[0]).strip()
        self.name = name
        self.modifiers = match.group("modifiers").split()
        self.key = ("%s %s" % (self.kind, self.name)).strip()
        self.code = "\n".join(self.code_lines)
        self.target = None
        self.strip = set()  # offsets into "\n".join(self.lines) of access modifiers to remove

    @property
    def text(self):
        return "\n".join(self.lines)

    @property
    def pinned(self):
        """Whether an extension cannot hold the unit: a stored instance property, an initializer of the type itself."""
        if self.top_level:
            return False
        if self.kind in ("init", "deinit", "case"):
            return True
        if self.kind in ("let", "var") and "static" not in self.modifiers and "class" not in self.modifiers:
            if self.kind == "let" or "lazy" in self.modifiers:
                return True
            code = "\n".join(self.code_lines[self.head_line:])
            brace = code.find("{")
            if brace < 0:
                return True
            equals = re.search(r"(?<![=!<>])=(?!=)", code[:brace])
            if equals:
                return True
            body = code[brace:matching(code, brace) + 1]
            return bool(re.search(r"\b(?:didSet|willSet)\b", body))
        return False

    def stripped_text(self):
        text = self.text
        for offset in sorted(self.strip, reverse=True):
            match = re.compile(r"(?:private|fileprivate)\s+").match(text, offset)
            text = text[:offset] + text[match.end():]
        return text

    def without_marks(self):
        """The unit's text without the `// MARK:` lines above its declaration and the blank lines they leave."""
        kept = [line for index, line in enumerate(self.stripped_text().split("\n")) if not (index < self.head_line and re.match(r"\s*// MARK:", line))]
        while kept and not kept[0].strip():
            kept.pop(0)
        # A dropped line can leave two blank lines together above the declaration.
        kept = [line for index, line in enumerate(kept) if not (index and index <= self.head_line and not line.strip() and not kept[index - 1].strip())]
        return "\n".join(kept)


CONTINUES_LINE = re.compile(r"^\s*(?:\.|->|where\b|[?:=]|&&|\|\||\+|\{)")
ENDS_OPEN = re.compile(r"(?:=|,|->|:|&&|\|\||\+)\s*$")


def units_in(path, lines, code_lines, first, last, top_level):
    """The declarations among lines [first, last), each from the first comment above it to its last line."""
    units = []
    start = None  # the first line after the previous unit that is not blank
    declaration = None
    depth = 0
    index = first
    while index < last:
        code = code_lines[index]
        if start is None and lines[index].strip():
            start = index
        if declaration is None and code.strip():
            # An attribute on a line of its own belongs to the declaration below it.
            if not re.fullmatch(r"\s*(?:@\w+(?:\((?:[^()]|\([^()]*\))*\))?\s*)+", code):
                declaration = index
            elif start is None:
                start = index
            if declaration is None:
                declaration_attribute = index
                index += 1
                continue
        if declaration is not None:
            for character in code:
                if character in "{([":
                    depth += 1
                elif character in "})]":
                    depth -= 1
            if depth == 0:
                following = next((code_lines[later] for later in range(index + 1, last) if code_lines[later].strip()), "")
                if not (ENDS_OPEN.search(code) or CONTINUES_LINE.match(following)):
                    attribute_start = declaration
                    while attribute_start - 1 >= start and code_lines[attribute_start - 1].strip() and re.fullmatch(r"\s*(?:@\w+(?:\((?:[^()]|\([^()]*\))*\))?\s*)+", code_lines[attribute_start - 1]):
                        attribute_start -= 1
                    units.append(Unit(path, lines, code_lines, start, attribute_start, index + 1, top_level))
                    start = declaration = None
        index += 1
    if declaration is not None:
        raise Problem("%s:%d: a declaration does not end" % (path, declaration + 1))
    return units, start


class SourceFile:
    """A Swift file as its leading comment and imports, its top-level declarations, and the members of one type."""

    def __init__(self, path, text, type_name):
        self.path = path
        self.text = text
        self.lines = text.split("\n")
        self.code_lines = masked(text).split("\n")
        self.type_name = type_name
        top, trailing = units_in(path, self.lines, self.code_lines, 0, len(self.lines), True)
        self.header_end = 0
        self.imports = []
        self.containers = []  # (unit, [member units]) for the type's declaration and its extensions that hold only members
        self.top_units = []
        self.trailing_start = trailing
        for position, unit in enumerate(top):
            if unit.kind == "import":
                self.imports.append(unit)
                continue
            is_type = unit.kind in ("actor", "class", "struct", "enum") and unit.name == type_name
            is_extension = unit.kind == "extension" and unit.name == type_name
            if is_type or is_extension:
                opening_line = next(line for line in range(unit.first + unit.head_line, unit.last) if "{" in self.code_lines[line])
                members, _ = units_in(path, self.lines, self.code_lines, opening_line + 1, unit.last - 1, False)
                self.containers.append((unit, opening_line, members))
            self.top_units.append(unit)
        if not top:
            raise Problem("%s: no declaration" % path)
        # The leading comment: the comment lines at the top of the file, up to its first blank line.
        license_end = 0
        while license_end < len(self.lines) and self.lines[license_end].startswith("//"):
            license_end += 1
        self.license = self.lines[:license_end] if license_end < len(self.lines) and not self.lines[license_end].strip() else []

    def primary(self):
        for unit, opening_line, members in self.containers:
            if unit.kind != "extension":
                return unit, opening_line, members
        return None


# MARK: The split

def private_declarations(unit):
    """(offset of the level in the unit's text, level, kind, name, nesting depth) of each private declaration."""
    found = []
    code = unit.code
    depth_at = []
    depth = 0
    for character in code:
        depth_at.append(depth)
        if character in "{([":
            depth += 1
        elif character in "})]":
            depth -= 1
    for match in PRIVATE.finditer(code):
        found.append((match.start("level"), match.group("level"), match.group("kind"), match.group("name").strip("`"), depth_at[match.start()]))
    return found


def exposed_code(code, start):
    """The part of the declaration at `start` that other declarations see: its signature, and for a type the
    signatures of its members that are not private."""
    match = DECLARATION.match(code, start) or PRIVATE.match(code, start)
    brace = code.find("{", start)
    line_end = code.find("\n", start)
    line_end = len(code) if line_end < 0 else line_end
    kind = re.search(r"\b(func|var|let|struct|enum|class|actor|protocol|typealias|init|subscript|case)\b", code[start:]).group(1)
    if kind in ("struct", "enum", "class", "actor", "protocol"):
        if brace < 0:
            return code[start:line_end]
        end = matching(code, brace)
        text = [code[start:brace]]
        depth = 0
        position = brace + 1
        line_start = position
        while position < end:
            character = code[position]
            if character in "{([":
                if depth == 0 and character == "{":
                    head = code[line_start:position]
                    head_start = max(head.rfind("\n"), 0)
                    declaration = code[line_start:position]
                    if not re.search(r"\b(?:private|fileprivate)\b(?!\()", declaration.split("\n")[-1]) or re.search(r"\b(?:struct|enum|class)\b", declaration.split("\n")[-1]):
                        text.append(declaration)
                depth += 1
            elif character in "})]":
                depth -= 1
                if depth == 0 and character == "}":
                    line_start = position + 1
            elif character == "\n" and depth == 0:
                line = code[line_start:position]
                if line.strip() and not re.search(r"\b(?:private|fileprivate)\b(?!\()", line):
                    text.append(line)
                line_start = position + 1
            position += 1
        return "\n".join(text)
    if kind in ("var", "let", "typealias"):
        stop = min(brace if brace >= 0 else len(code), line_end)
        equals = re.search(r"(?<![=!<>])=(?!=)", code[start:stop])
        if equals and kind != "typealias" and not re.search(r"\b(?:var|let)\s+[\w`]+\s*:", code[start:start + equals.start()]):
            # No annotation: the type is the initial value's, so what it names is seen too.
            return code[start:line_end]
        return code[start:start + equals.start()] if equals and kind != "typealias" else code[start:stop]
    # A function: up to the brace that opens its body.
    depth = 0
    for position in range(start, len(code)):
        character = code[position]
        if character in "([":
            depth += 1
        elif character in ")]":
            depth -= 1
        elif character == "{" and depth == 0:
            return code[start:position]
        elif character == "\n" and depth == 0 and not ENDS_OPEN.search(code[start:position]) and not CONTINUES_LINE.match(code[position + 1:position + 200]):
            return code[start:position]
    return code[start:]


def words(code):
    return set(re.findall(r"[A-Za-z_]\w*", code))


def loosen_access(units):
    """Marks the access modifiers to remove so that the units compile in their files."""
    words_by_target = {}
    unit_words = {}
    for unit in units:
        # A name a string literal's interpolation reads is a use too (`"\\(name)"`), which `unit.code` blanks.
        unit_words[id(unit)] = words(masked("\n".join(unit.lines), keeping_interpolations=True))
    declarations = []  # (unit, offset, level, kind, name, depth)
    for unit in units:
        for offset, level, kind, name, depth in private_declarations(unit):
            declarations.append((unit, offset, level, kind, name, depth))
    stripped = []

    def strip(entry):
        unit, offset = entry[0], entry[1]
        if offset not in unit.strip:
            unit.strip.add(offset)
            stripped.append(entry)

    for entry in declarations:
        unit, offset, level, kind, name, depth = entry
        if not name:
            continue
        # `private` inside a nested type reaches only that type, in any file; only its own level, or `fileprivate`,
        # reached the rest of the file.
        own_level = depth == 0 or (unit.top_level and depth == 1)
        if level == "private" and not own_level:
            continue
        if any(other.target != unit.target and name in unit_words[id(other)] for other in units):
            strip(entry)
    # A declaration that is no longer private cannot name a private type in what others see of it.
    private_types = {}
    for entry in declarations:
        if entry[3] in TYPE_KINDS and entry[4]:
            private_types.setdefault(entry[4], []).append(entry)
    position = 0
    while position < len(stripped):
        unit, offset = stripped[position][0], stripped[position][1]
        position += 1
        seen = words(exposed_code(unit.code, offset))
        for name in sorted(seen & set(private_types)):
            for entry in private_types[name]:
                strip(entry)
    return stripped


def split(checkout, source, dry_run, out):
    path = source["file"]
    directory = os.path.dirname(path)
    type_name = source["type"]
    with open(os.path.join(checkout, path), encoding="utf-8") as file:
        main = SourceFile(path, file.read(), type_name)
    primary = main.primary()
    if primary is None:
        raise Problem("%s declares no type named %s" % (path, type_name))
    runs = source["runs"]
    targets = sorted({file_name for _, file_name in runs if file_name != "stay"})
    for file_name in targets:
        if not re.fullmatch(r"[\w+.-]+\.swift", file_name) or file_name == os.path.basename(path):
            raise Problem("`%s` is not a new file's name" % file_name)
    # The units of the source file, in source order: the type's members, then the top-level declarations after it.
    type_unit, opening_line, members = primary
    extension_units = [unit for unit in main.top_units if unit is not type_unit and unit.first > type_unit.first]
    before_type = [unit for unit in main.top_units if unit.first < type_unit.first]
    if before_type:
        raise Problem("%s:%d: a declaration above %s, which this script leaves no place for" % (path, before_type[0].first + 1, type_name))
    ordered = members + extension_units
    # Files a previous run wrote: their units stay in them.
    existing = {}
    for file_name in targets:
        full = os.path.join(checkout, directory, file_name)
        if os.path.exists(full):
            with open(full, encoding="utf-8") as file:
                existing[file_name] = SourceFile(os.path.join(directory, file_name), file.read(), type_name)
            for unit in existing[file_name].top_units:
                unit.target = file_name
            for _, _, file_members in existing[file_name].containers:
                for unit in file_members:
                    unit.target = file_name
    already_moved = set()
    for file_name in existing:
        already_moved.update(unit.key for unit in existing[file_name].top_units)
        for _, _, file_members in existing[file_name].containers:
            already_moved.update(unit.key for unit in file_members)
    by_key = {}
    for unit in ordered:
        # `kind name` is the first declaration of that kind and name, `kind name#2` the second, and so on.
        count = 1
        while ("%s#%d" % (unit.key, count) if count > 1 else unit.key) in by_key:
            count += 1
        by_key["%s#%d" % (unit.key, count) if count > 1 else unit.key] = unit
    starts = {}
    for anchor, file_name in runs:
        if anchor not in by_key:
            if anchor in already_moved:
                continue
            raise Problem("%s: no declaration `%s`; the map is older than the source" % (path, anchor))
        if id(by_key[anchor]) in starts:
            raise Problem("%s: two runs start at `%s`" % (path, anchor))
        starts[id(by_key[anchor])] = file_name
    current = "stay"
    for unit in ordered:
        current = starts.get(id(unit), current)
        unit.target = "stay" if (current == "stay" or unit.pinned) else current
    every_unit = list(ordered)
    for file_name in sorted(existing):
        for unit in existing[file_name].top_units:
            if not any(unit is container for container, _, _ in existing[file_name].containers):
                every_unit.append(unit)
        for _, _, file_members in existing[file_name].containers:
            every_unit.extend(file_members)
    moving = [unit for unit in ordered if unit.target != "stay"]
    for file_name in targets:
        if file_name not in existing and not any(unit.target == file_name for unit in moving):
            raise Problem("%s: nothing goes to %s" % (path, file_name))
    if not moving:
        return None
    stripped = loosen_access(every_unit)

    # The source file without what moves.
    removed = set()
    for unit in moving:
        removed.update(range(unit.first, unit.last))
    replaced = {}
    for unit in ordered:
        if unit.target == "stay" and unit.strip:
            new_lines = unit.stripped_text().split("\n")
            for offset, line in enumerate(new_lines):
                replaced[unit.first + offset] = line
    kept = []
    for index, line in enumerate(main.lines):
        if index in removed:
            continue
        line = replaced.get(index, line)
        if not line.strip() and kept and not kept[-1].strip():
            continue
        kept.append(line)
    # A `// MARK:` line left with nothing beneath it before the next one, or before a closing brace, goes too.
    cleaned = []
    for index, line in enumerate(kept):
        if re.match(r"\s*// MARK:", line):
            following = next((later for later in kept[index + 1:] if later.strip()), "")
            if re.match(r"\s*// MARK:", following) or following.strip() == "}" or not following:
                continue
        if not line.strip() and cleaned and not cleaned[-1].strip():
            continue
        cleaned.append(line)
    for index in range(len(cleaned) - 1, 0, -1):
        if cleaned[index].strip() == "}" and not cleaned[index - 1].strip():
            del cleaned[index - 1]
    while len(cleaned) > 1 and not cleaned[-1].strip() and not cleaned[-2].strip():
        cleaned.pop()
    new_main = "\n".join(cleaned)
    if not new_main.endswith("\n"):
        new_main += "\n"

    outputs = {path: new_main}
    import_text = "\n".join("\n".join(unit.lines[unit.head_line:]) for unit in main.imports)
    for file_name in targets:
        mine = [unit for unit in moving if unit.target == file_name]
        if not mine and file_name not in existing:
            raise Problem("%s: nothing goes to %s" % (path, file_name))
        member_texts = [unit.without_marks() for unit in mine if not unit.top_level]
        top_texts = [unit.without_marks() for unit in mine if unit.top_level]
        if file_name in existing:
            previous = existing[file_name]
            if mine:
                raise Problem("%s exists and the source file still holds declarations of its runs (`%s`): move them by hand, or delete the file and run again on the unsplit source" % (file_name, mine[0].key))
            continue
        parts = []
        if main.license:
            parts.append("\n".join(main.license))
        if import_text:
            parts.append(import_text)
        if member_texts:
            parts.append("extension %s {\n%s\n}" % (type_name, "\n\n".join(member_texts)))
        parts.extend(top_texts)
        outputs[os.path.join(directory, file_name)] = "\n\n".join(parts) + "\n"

    check(main, ordered, outputs, path)
    report = []
    for file_name in targets:
        mine = [unit for unit in moving if unit.target == file_name]
        report.append("%s: %d declarations, %d lines" % (file_name, len(mine), sum(len(unit.lines) for unit in mine)))
    report.append("%s keeps %d declarations, %d lines" % (os.path.basename(path), len([unit for unit in ordered if unit.target == "stay"]), new_main.count("\n")))
    for unit, offset, level, kind, name, depth in stripped:
        report.append("no longer %s: %s %s (%s)" % (level, kind, name, unit.target if unit.target != "stay" else os.path.basename(path)))
    return outputs, report, moving


def normalized(text):
    lines = []
    for line in text.split("\n"):
        if not line.strip() or re.match(r"\s*// MARK:", line):
            continue
        lines.append(re.sub(r"\b(?:private|fileprivate)\s+", "", line).strip())
    return lines


def check(main, ordered, outputs, path):
    """Every line of the source is in exactly one output, and each unit's lines are together and in order."""
    before = sorted(normalized(main.text))
    after = []
    for output_path, text in outputs.items():
        lines = normalized(text)
        if output_path != path:
            body = [line for line in lines]
            # What the script itself writes: the license, the imports, the extension's braces.
            for written in normalized("\n".join(main.license)) + [line for unit in main.imports for line in normalized("\n".join(unit.lines[unit.head_line:]))]:
                body.remove(written)
            if "extension %s {" % main.type_name in body:
                body.remove("extension %s {" % main.type_name)
                body.reverse()
                body.remove("}")
                body.reverse()
            lines = body
        after.extend(lines)
    if before != sorted(after):
        missing = list(before)
        for line in after:
            if line in missing:
                missing.remove(line)
        raise Problem("%s: the split would lose or change %d lines, the first: %s" % (path, len(missing), missing[0] if missing else "(an added line)"))
    joined = {output_path: "\n".join(normalized(text)) for output_path, text in outputs.items()}
    for unit in ordered:
        text = "\n".join(normalized(unit.text))
        if text and sum(1 for body in joined.values() if text in body) < 1:
            raise Problem("%s: `%s` is not whole in any file after the split" % (path, unit.key))


# MARK: References to the source file

def relocate(checkout, entries, outputs, source_path, report):
    edits = {}
    for entry in entries:
        file_path = entry["file"]
        full = os.path.join(checkout, file_path)
        with open(full, encoding="utf-8") as file:
            text = edits.get(file_path) or file.read()
        pattern = re.compile(r'path:\s*"(?P<path>%s)",\s*code:\s*"(?P<code>(?:[^"\\\n]|\\.)*)"' % re.escape(source_path))
        position = 0
        while True:
            match = pattern.search(text, position)
            if not match:
                break
            code = json.loads('"%s"' % match.group("code"))
            holders = sorted(path for path, body in outputs.items() if code in body)
            if not holders:
                raise Problem("%s: no file holds `%s` after the split" % (file_path, code))
            if source_path in holders:
                report.append("%s: the site of `%s` stays %s" % (file_path, code, source_path))
            else:
                text = text[:match.start("path")] + holders[0] + text[match.end("path"):]
                report.append("%s: the site of `%s` is now %s" % (file_path, code, holders[0]))
            position = match.start() + 1
        edits[file_path] = text
    return edits


def replace(checkout, entries, edits, report):
    for entry in entries:
        file_path = entry["file"]
        full = os.path.join(checkout, file_path)
        if file_path not in edits:
            with open(full, encoding="utf-8") as file:
                edits[file_path] = file.read()
        text = edits[file_path]
        if entry["new"] in text and entry["old"] not in text.replace(entry["new"], ""):
            continue
        if text.count(entry["old"]) != 1:
            report.append("NOT REPLACED in %s (%d matches): %s" % (file_path, text.count(entry["old"]), entry["old"][:80]))
            continue
        edits[file_path] = text.replace(entry["old"], entry["new"])
        report.append("%s: replaced “%s…”" % (file_path, entry["old"][:60]))
    return edits


def mentions(checkout, source_path, skip):
    """The tracked text files that name the source file, for the report."""
    found = []
    name = os.path.basename(source_path)
    for root, directories, files in os.walk(checkout):
        directories[:] = [directory for directory in directories if directory not in (".git", ".build", "node_modules")]
        for file_name in files:
            relative = os.path.relpath(os.path.join(root, file_name), checkout)
            if relative in skip or not file_name.endswith((".swift", ".md", ".txt", ".py", ".sh", ".yml", ".bzl", ".bazel", ".json", ".toml")):
                continue
            try:
                with open(os.path.join(root, file_name), encoding="utf-8") as file:
                    count = file.read().count(name)
            except (OSError, UnicodeDecodeError):
                continue
            if count:
                found.append("%s names %s %d times" % (relative, name, count))
    return sorted(found)


def run(map_path, checkout, dry_run, list_only, out=sys.stdout):
    try:
        with open(map_path, encoding="utf-8") as file:
            split_map = json.load(file)
        writes = {}
        report = []
        changed = False
        for source in split_map["sources"]:
            if list_only:
                with open(os.path.join(checkout, source["file"]), encoding="utf-8") as file:
                    main = SourceFile(source["file"], file.read(), source["type"])
                _, _, members = main.primary()
                for unit in members + [unit for unit in main.top_units if unit.first > main.primary()[0].first]:
                    print("%6d %5d  %s%s" % (unit.first + 1, len(unit.lines), unit.key, "  (cannot move)" if unit.pinned else ""), file=out)
                continue
            result = split(checkout, source, dry_run, out)
            if result is None:
                report.append("%s: already split as the map says" % source["file"])
                continue
            changed = True
            outputs, source_report, _ = result
            report.extend(source_report)
            writes.update(outputs)
            edits = relocate(checkout, source.get("relocate", []), outputs, source["file"], report)
            edits = replace(checkout, source.get("replace", []), edits, report)
            writes.update({path: text for path, text in edits.items()})
            report.extend("to read: " + line for line in mentions(checkout, source["file"], set(writes)))
        if list_only:
            return 0
    except (Problem, OSError, ValueError, KeyError) as error:
        print("nothing written: %s" % error, file=sys.stderr)
        return 2
    if not dry_run:
        for path, text in sorted(writes.items()):
            with open(os.path.join(checkout, path), "w", encoding="utf-8") as file:
                file.write(text)
    for line in report:
        print(line, file=out)
    return 0 if changed else 1


# MARK: Self-test

SELF_TEST_SOURCE = '''// License line one
// License line two

import Foundation

public actor Generator {
	// MARK: Initialization

	public init(value: Int) {
		self.value = value
	}

	// MARK: Public

	/// Runs.
	public func run() -> Int {
		helper() + Self.constant + stored
	}

	private let value: Int
	private var stored = 0
	private lazy var cache = [String: Int]()

	// MARK: Mocks

	/// Makes mocks.
	/// With "a { brace" in a string: \\(value).
	@discardableResult
	public func makeMocks() -> [String] {
		[Mock(name: Self.name(of: value)).name]
	}

	private struct Mock {
		let name: String
		private let secret = 1
	}

	private static func name(of value: Int) -> String {
		"mock \\(value)"
	}

	// MARK: Validation

	private func helper() -> Int {
		let report = Report(count: value)
		return report.count + offset
	}

	private struct Report {
		let count: Int
	}

	private var offset: Int {
		value + 1
	}

	private func report(for count: Int) -> Report {
		Report(count: count)
	}

	fileprivate static let constant = 2

	private static var limit: Int?

	private func untouched() -> Int {
		report(for: 1).count
	}
}

// MARK: - Int

extension Int {
	fileprivate var doubled: Int {
		self * 2
	}
}
'''

SELF_TEST_MAIN = '''// License line one
// License line two

import Foundation

public actor Generator {
	// MARK: Initialization

	public init(value: Int) {
		self.value = value
	}

	// MARK: Public

	/// Runs.
	public func run() -> Int {
		helper() + Self.constant + stored
	}

	let value: Int
	private var stored = 0
	private lazy var cache = [String: Int]()
}
'''

SELF_TEST_MOCKS = '''// License line one
// License line two

import Foundation

extension Generator {
	/// Makes mocks.
	/// With "a { brace" in a string: \\(value).
	@discardableResult
	public func makeMocks() -> [String] {
		[Mock(name: Self.name(of: value)).name]
	}

	private struct Mock {
		let name: String
		private let secret = 1
	}

	private static func name(of value: Int) -> String {
		"mock \\(value)"
	}
}
'''

SELF_TEST_VALIDATION = '''// License line one
// License line two

import Foundation

extension Generator {
	func helper() -> Int {
		let report = Report(count: value)
		return report.count + offset
	}

	private struct Report {
		let count: Int
	}

	private var offset: Int {
		value + 1
	}

	private func report(for count: Int) -> Report {
		Report(count: count)
	}

	static let constant = 2

	private static var limit: Int?

	private func untouched() -> Int {
		report(for: 1).count
	}
}

extension Int {
	fileprivate var doubled: Int {
		self * 2
	}
}
'''


def self_test(root):
    if os.path.exists(root):
        print("%s exists; --self-test writes a new directory" % root, file=sys.stderr)
        return 2
    failures = []
    counter = [0]

    def case(name, runs, expected_status, expected_files, source=SELF_TEST_SOURCE, extra=None, map_extra=None, twice=False):
        counter[0] += 1
        checkout = os.path.join(root, "%02d" % counter[0])
        os.makedirs(os.path.join(checkout, "Sources"))
        with open(os.path.join(checkout, "Sources", "Generator.swift"), "w", encoding="utf-8") as file:
            file.write(source)
        for path, text in (extra or {}).items():
            with open(os.path.join(checkout, path), "w", encoding="utf-8") as file:
                file.write(text)
        entry = {"file": "Sources/Generator.swift", "type": "Generator", "runs": runs}
        entry.update(map_extra or {})
        map_path = os.path.join(checkout, "map.json")
        with open(map_path, "w", encoding="utf-8") as file:
            json.dump({"sources": [entry]}, file)
        with open(os.devnull, "w") as quiet:
            saved, sys.stderr = sys.stderr, quiet
            try:
                status = run(map_path, checkout, False, False, out=quiet)
                if twice:
                    status = run(map_path, checkout, False, False, out=quiet)
            finally:
                sys.stderr = saved
        if status != expected_status:
            failures.append("%s: status %d, expected %d" % (name, status, expected_status))
        for path, expected in expected_files.items():
            full = os.path.join(checkout, path)
            actual = open(full, encoding="utf-8").read() if os.path.exists(full) else None
            if actual != expected:
                failures.append("%s: %s is not the expected text" % (name, path))
                with open(full + ".expected", "w", encoding="utf-8") as file:
                    file.write(expected or "")

    runs = [["func makeMocks", "Generator+Mocks.swift"], ["func helper", "Generator+Validation.swift"]]
    split_files = {"Sources/Generator.swift": SELF_TEST_MAIN, "Sources/Generator+Mocks.swift": SELF_TEST_MOCKS, "Sources/Generator+Validation.swift": SELF_TEST_VALIDATION}
    case("members move by run, and access loosens only where another file names it", runs, 0, split_files)
    case("a second run changes nothing", runs, 1, split_files, twice=True)
    case("an anchor the source does not hold", runs + [["func gone", "Generator+Gone.swift"]], 2, {"Sources/Generator.swift": SELF_TEST_SOURCE, "Sources/Generator+Mocks.swift": None})
    case("two runs at one anchor", runs + [["func helper", "Generator+Mocks.swift"]], 2, {"Sources/Generator.swift": SELF_TEST_SOURCE})
    case("a file name that is the source's", [["func helper", "Generator.swift"]], 2, {"Sources/Generator.swift": SELF_TEST_SOURCE})
    case("a run of only what cannot move", [["let value", "Generator+Stored.swift"], ["func makeMocks", "stay"]], 2, {"Sources/Generator.swift": SELF_TEST_SOURCE})
    case("a stay run ends a run", [["func makeMocks", "Generator+Mocks.swift"], ["func helper", "stay"]], 0, {"Sources/Generator+Mocks.swift": SELF_TEST_MOCKS.replace("private static func name", "private static func name"), "Sources/Generator+Validation.swift": None})
    site = 'let site = ErrorReportingSite(\n\tpath: "Sources/Generator.swift",\n\tcode: "report.count + offset",\n)\nlet other = ErrorReportingSite(\n\tpath: "Sources/Generator.swift",\n\tcode: "helper() + Self.constant",\n)\n'
    case(
        "a site's path follows its code, and prose is replaced",
        runs, 0,
        {"Sites.swift": site.replace('"Sources/Generator.swift",\n\tcode: "report.count', '"Sources/Generator+Validation.swift",\n\tcode: "report.count'), "Notes.md": "`Generator.swift` and its `Generator+*.swift` files hold it.\n"},
        extra={"Sites.swift": site, "Notes.md": "`Generator.swift` holds it.\n"},
        map_extra={"relocate": [{"file": "Sites.swift"}], "replace": [{"file": "Notes.md", "old": "`Generator.swift` holds it.", "new": "`Generator.swift` and its `Generator+*.swift` files hold it."}]},
    )
    interpolation_source = "// License\n\nimport Foundation\n\nactor Generator {\n\tprivate let count = 1\n\n\tfunc describe() -> String {\n\t\t\"count: \\(count)\"\n\t}\n}\n"
    case(
        "a name read only inside a string interpolation loosens too",
        [["func describe", "Generator+Description.swift"]], 0,
        {
            "Sources/Generator.swift": "// License\n\nimport Foundation\n\nactor Generator {\n\tlet count = 1\n}\n",
            "Sources/Generator+Description.swift": "// License\n\nimport Foundation\n\nextension Generator {\n\tfunc describe() -> String {\n\t\t\"count: \\(count)\"\n\t}\n}\n",
        },
        source=interpolation_source,
    )
    private_type_in_signature = SELF_TEST_SOURCE.replace("report.count + offset", "self.report(for: 1).count + offset").replace("private func untouched", "func untouched")
    case(
        "a private type named by a signature that is no longer private loosens too",
        [["func makeMocks", "Generator+Mocks.swift"], ["func helper", "Generator+Validation.swift"], ["func report", "Generator+Reports.swift"]], 0,
        {"Sources/Generator+Reports.swift": "// License line one\n// License line two\n\nimport Foundation\n\nextension Generator {\n\tfunc report(for count: Int) -> Report {\n\t\tReport(count: count)\n\t}\n\n\tstatic let constant = 2\n\n\tprivate static var limit: Int?\n\n\tfunc untouched() -> Int {\n\t\treport(for: 1).count\n\t}\n}\n\nextension Int {\n\tfileprivate var doubled: Int {\n\t\tself * 2\n\t}\n}\n"},
        source=private_type_in_signature,
    )
    for failure in failures:
        print("self-test: %s" % failure, file=sys.stderr)
    print("self-test: %d cases, %d failures" % (counter[0], len(failures)))
    if failures:
        print("self-test: the cases are kept in %s" % root, file=sys.stderr)
    else:
        shutil.rmtree(root)
    return 1 if failures else 0


def main(arguments):
    if len(arguments) == 2 and arguments[0] == "--self-test":
        return self_test(arguments[1])
    options = {"--map": os.path.join(os.path.dirname(os.path.abspath(__file__)), "split-map.json"), "--checkout": "."}
    flags = set()
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        if argument in options and index + 1 < len(arguments):
            options[argument] = arguments[index + 1]
            index += 2
        elif argument in ("--dry-run", "--list"):
            flags.add(argument)
            index += 1
        else:
            print(__doc__, file=sys.stdout if argument == "--help" else sys.stderr)
            return 0 if argument == "--help" else 2
    return run(options["--map"], options["--checkout"], "--dry-run" in flags, "--list" in flags)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
