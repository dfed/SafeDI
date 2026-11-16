"""Shared pieces for writing a test's expected files out from the records of a run.

    import from_records as fr
    records = fr.Records("~/.cache/RecS2/base")
    fr.rewrite_calls(path, helper, module, records)   # each call of `helper` becomes the files the test generated
"""
import importlib.util, os, re, sys, pathlib

TOOL = os.path.expanduser("~/SafeDI-regen/.claude/skills/regenerate-expectations/write-out-expectations.py")
spec = importlib.util.spec_from_file_location("write_out", TOOL)
tool = importlib.util.module_from_spec(spec); spec.loader.exec_module(tool)
regenerator = tool.regenerator


class Records:
    def __init__(self, directory):
        directory = os.path.expanduser(directory)
        self.header = regenerator.read_header(directory)
        self.generations = {}
        for record in regenerator.read_records(directory):
            if record["kind"] != "generation":
                continue
            name = record.get("testName", "").split("(")[0]
            key = (record["line"], record.get("module"), record.get("integration"), record.get("inputsDigest"))
            self.generations.setdefault(name, {}).setdefault(key, {})[record["outputName"]] = record["content"]

    def find(self, test, module=None, integration=None, containing=(), names=None, line=None):
        """The file sets of `test` that match; each is {output name: content}."""
        found = []
        for (record_line, record_module, record_integration, _), files in self.generations.get(test, {}).items():
            if module is not None and record_module != module: continue
            if integration is not None and record_integration != integration: continue
            if line is not None and record_line != line: continue
            if names is not None:
                files = {name: content for name, content in files.items() if names(name)}
            if not files: continue
            text = "\n".join(files.values())
            if all(piece in text for piece in containing):
                if files not in found: found.append(files)
        return found

    def parts(self, files):
        return {name: tool.file_parts(content, self.header, []) for name, content in files.items()}

    def source(self, files, indentation, kind="files"):
        return tool.value_source(self.parts(files), kind, indentation)

    def source_for_both(self, module_info, plugin, indentation, parameter="integration"):
        """One dictionary for both integrations where they differ only in names and seam call comments; else a ternary."""
        cases = {"moduleInfo": self.parts(module_info), "swiftPackagePlugin": self.parts(plugin)}
        merged = tool.keyed_by_integration(cases, indentation, parameter)
        if merged is not None:
            return merged
        return f"({parameter} == .moduleInfo ? {self.source(module_info, indentation)} : {self.source(plugin, indentation)})"


def call_end(text, opening):
    """The index of the parenthesis that closes the one at `opening`, skipping string literals."""
    depth = 0; i = opening
    while i < len(text):
        if text.startswith('"""', i):
            i = text.index('"""', i + 3) + 3; continue
        c = text[i]
        if c == '"':
            i += 1
            while text[i] != '"':
                i += 2 if text[i] == "\\" else 1
        elif c in "([{": depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0: return i
        i += 1
    raise ValueError("unclosed")


def enclosing_test(text, position):
    names = [(m.start(), m.group(1)) for m in re.finditer(r"\n\t(?:private |mutating |static |nonisolated )*func (\w+)[(<]", text)]
    before = [name for start, name in names if start < position]
    return before[-1] if before else None


def line_indentation(text, position):
    start = text.rfind("\n", 0, position) + 1
    return re.match(r"\t*", text[start:]).group(0)


def rewrite_calls(path, helper, module, records, integration_of=None, names=None, kind="files", contain=None, dry=False):
    """Replaces each call of `helper` outside its declaration with the files its test generated for `module`.

    `integration_of(call_text)` returns "moduleInfo", "swiftPackagePlugin" or a parameter name whose value chooses;
    the default reads the call's first argument. `contain(call_text)` returns texts the files must hold (default: every
    16-digit hash in the call). Returns what it left, with the reason."""
    text = pathlib.Path(path).read_text()
    left = []; done = 0
    pattern = re.compile(rf"(?<!func )(?:Self\.)?\b{helper}\(")
    position = 0
    while True:
        m = pattern.search(text, position)
        if not m: break
        end = call_end(text, m.end() - 1)
        call = text[m.start():end + 1]
        position = m.end()
        test = enclosing_test(text, m.start())
        where = f"{path}:{text.count(chr(10), 0, m.start()) + 1} ({test})"
        first = re.match(r"\s*\.?(\w+)", text[m.end():]).group(1)
        integration = integration_of(call) if integration_of else first
        containing = contain(call) if contain else re.findall(r"[0-9A-F]{16}", call)
        indentation = line_indentation(text, m.start())
        try:
            if integration in ("moduleInfo", "swiftPackagePlugin", None):
                found = records.find(test, module, integration, containing, names)
                if len(found) != 1:
                    left.append(f"{where}: {len(found)} recorded file sets match"); continue
                new = records.source(found[0], indentation, kind)
            else:
                first_found = records.find(test, module, "moduleInfo", containing, names)
                second_found = records.find(test, module, "swiftPackagePlugin", containing, names)
                if len(first_found) != 1 or len(second_found) != 1:
                    left.append(f"{where}: {len(first_found)} and {len(second_found)} recorded file sets match"); continue
                new = records.source_for_both(first_found[0], second_found[0], indentation, integration)
        except tool.Left as reason:
            left.append(f"{where}: {reason}"); continue
        text = text[:m.start()] + new + text[end + 1:]
        position = m.start() + len(new); done += 1
    if not dry:
        pathlib.Path(path).write_text(text)
    print(f"{path}: wrote out {done} calls of {helper}; left {len(left)}")
    for line in left: print("  left " + line)
    return left


def property_cases(path, type_name, property_name):
    """{case: text} of `var property_name: String { switch self { case .x: "text" … } }` in `type_name`."""
    text = pathlib.Path(path).read_text()
    start = text.index(f"enum {type_name}")
    start = text.index(f"var {property_name}: String", start)
    end = text.index("\n\t\t}\n", start)
    return dict(re.findall(r'case \.(\w+):\s*"([^"\n]*)"', text[start:end]))


def switch_on_argument(path, test, parameter, cases, records, integration=None, dry=False):
    """In `test`, each comparison of a module's generated files whose expected side reads `parameter` becomes a switch
    on `parameter` between the whole files each case generated. `cases` is {case name: [texts its files hold]};
    `integration` names the test's integration parameter when it has one."""
    text = pathlib.Path(path).read_text()
    start = re.search(rf"\n\t(?:mutating )?func {test}\(", text).start()
    end = text.index("\n\t}\n", start)
    pattern = re.compile(r'(expectGeneratedFiles\(|#expect\()((?:try #require\()?\w+\.modules\["(\w+)"\]\)?\??\.generatedFiles)(, | == )')
    done = 0; left = []; position = start
    while True:
        m = pattern.search(text, position, end)
        if not m: break
        close = call_end(text, m.start(1) + len(m.group(1)) - 1)
        statement = text[m.start():close + 1]
        position = m.end()
        if not re.search(rf"\b{parameter}\.", statement[m.end() - m.start():]):
            continue
        module = m.group(3)
        indentation = line_indentation(text, m.start())
        inner = indentation + "\t"
        lines = [f"switch {parameter} {{"]
        try:
            for case, containing in cases.items():
                if integration:
                    first = records.find(test, module, "moduleInfo", containing)
                    second = records.find(test, module, "swiftPackagePlugin", containing)
                    if len(first) != 1 or len(second) != 1:
                        raise tool.Left(f"case {case}: {len(first)} and {len(second)} recorded file sets match")
                    source = records.source_for_both(first[0], second[0], inner, integration)
                else:
                    found = records.find(test, module, None, containing)
                    if len(found) != 1:
                        raise tool.Left(f"case {case}: {len(found)} recorded file sets match")
                    source = records.source(found[0], inner)
                tail = ")" if m.group(1).startswith("expect") else ")"
                lines.append(f"{indentation}case .{case}:")
                lines.append(f"{inner}{m.group(1)}{m.group(2)}{m.group(4)}{source}{tail}")
        except tool.Left as reason:
            left.append(f"{path} {test} module {module}: {reason}"); continue
        lines.append(indentation + "}")
        new = "\n".join(lines)
        text = text[:m.start()] + new + text[close + 1:]
        end += len(new) - (close + 1 - m.start()); position = m.start() + len(new); done += 1
    if not dry:
        pathlib.Path(path).write_text(text)
    print(f"{path} {test}: {done} comparisons now switch on {parameter}; left {len(left)}")
    for line in left: print("  left " + line)
    return left


def property_literals(path, type_name, property_name):
    """{case: text} of a `String` property of `type_name` that switches on self between multi-line literals."""
    lines = pathlib.Path(path).read_text().split("\n")
    i = next(k for k, l in enumerate(lines) if re.search(rf"\benum {type_name}\b", l))
    i = next(k for k in range(i, len(lines)) if re.search(rf"\bvar {property_name}: String \{{", lines[k]))
    indentation = re.match(r"\t*", lines[i]).group(0)
    end = next(k for k in range(i, len(lines)) if lines[k] == indentation + "}")
    result = {}; k = i
    while k < end:
        m = re.match(r"\t+case ((?:\.\w+(?:, )?)+):\s*$", lines[k])
        if m and lines[k + 1].strip() == '"""':
            close = next(j for j in range(k + 2, end) if lines[j].strip() == '"""')
            strip = len(lines[close]) - 3
            body = "\n".join(l[strip:] for l in lines[k + 2:close])
            for case in re.findall(r"\.(\w+)", m.group(1)):
                result[case] = body
            k = close
        k += 1
    return result


ALLOWED = {"generatedFileHeader", "integration", "moduleInfo", "swiftPackagePlugin", "try"}
COMPARISON = re.compile(
    r'(expectGeneratedFiles\(|#expect\()'
    r'((?:try #require\()?(\w+)\.modules\["(\w+)"\]\)?\??\.generatedFiles|(\w+)\.(dependencyTreeFiles|mockFiles))'
    r'(, | == )'
)
SUFFIX = {"dependencyTreeFiles": "+SafeDI.swift", "mockFiles": "+SafeDIMock.swift"}


def blanked(source):
    """`source` with the contents of its string literals removed."""
    out = []; i = 0
    while i < len(source):
        if source.startswith('"""', i):
            i = source.index('"""', i + 3) + 3; out.append('""'); continue
        if source[i] == '"':
            i += 1
            while source[i] != '"':
                i += 2 if source[i] == "\\" else 1
            i += 1; out.append('""'); continue
        out.append(source[i]); i += 1
    return "".join(out)


def expression_end(text, start, close):
    """The end of the expression that starts at `start` inside a call that closes at `close`: the next comma at the
    call's own depth, or `close`."""
    depth = 0; i = start
    while i < close:
        if text.startswith('"""', i):
            i = text.index('"""', i + 3) + 3; continue
        c = text[i]
        if c == '"':
            i += 1
            while text[i] != '"':
                i += 2 if text[i] == "\\" else 1
        elif c in "([{": depth += 1
        elif c in ")]}": depth -= 1
        elif c == "," and depth == 0: return i
        i += 1
    return close


def rewrite_file(path, records, dry=False, only=None):
    """Every comparison of generated files in `path` whose expected side is not spelled out, in a test whose records
    hold one file set for it, gets the files spelled out. Returns the comparisons it left, with the reason."""
    text = pathlib.Path(path).read_text()
    done = 0; left = []; position = 0
    while True:
        m = COMPARISON.search(text, position)
        if not m: break
        position = m.end()
        close = call_end(text, m.start(1) + len(m.group(1)) - 1)
        end = expression_end(text, m.end(), close)
        expression = text[m.end():end]
        names = set(re.findall(r"(?<![.\w])[A-Za-z_]\w*", blanked(expression))) | set(re.findall(r"\bSelf\b", blanked(expression)))
        if names <= ALLOWED:
            continue
        if re.search(r"\.(generatedFiles|dependencyTreeFiles|mockFiles|modules)\b", blanked(expression)) or re.fullmatch(r"\s*\w+\[[^\]]*\]\s*", expression):
            # Another run's output, which the test compares this one with, or a table of whole files.
            continue
        test = enclosing_test(text, m.start())
        local = None
        if re.fullmatch(r"\s*[a-z]\w*\s*", expression):
            # A local constant: spelled out already when its own value is.
            local = local_definition(text, expression.strip(), m.start())
            if local is None:
                continue
            definition_names = set(re.findall(r"(?<![.\w])[A-Za-z_]\w*", blanked(text[local[1]:local[2]])))
            if definition_names <= ALLOWED | {"switch", "case", "String"}:
                continue
        if only and not re.search(only, test or ""):
            continue
        where = f"{path}:{text.count(chr(10), 0, m.start()) + 1} {test}"
        module = m.group(4)
        suffix = SUFFIX.get(m.group(6))
        name_filter = (lambda name, s=suffix: name.endswith(s)) if suffix else None
        signature_start = text.rfind(f"func {test}(", 0, m.start())
        signature = text[signature_start:text.index("{", signature_start)]
        parameters = re.findall(r"(\w+): ", signature[len(f"func {test}("):])
        indentation = line_indentation(text, m.start())
        try:
            first = records.find(test, module, "moduleInfo" if module else None, (), name_filter)
            second = records.find(test, module, "swiftPackagePlugin", (), name_filter) if module else []
            if "integration" in parameters and module:
                if len(first) != 1 or len(second) != 1:
                    raise tool.Left(f"{len(first)} and {len(second)} recorded file sets")
                new = records.source_for_both(first[0], second[0], indentation)
            else:
                found = first + [files for files in second if files not in first]
                if len(found) != 1:
                    raise tool.Left(f"{len(found)} recorded file sets" + (f"; parameters {parameters}" if parameters else ""))
                new = records.source(found[0], indentation)
        except tool.Left as reason:
            left.append(f"{where}: {reason}"); continue
        text = text[:m.end()] + new + text[end:]
        position = m.end() + len(new); done += 1
        if local is not None and len(re.findall(rf"(?<![.\w]){expression.strip()}\b", text[local[3]:text.index(chr(10) + chr(9) + "}" + chr(10), local[3])])) == 0:
            # Nothing else in the test reads the constant: delete its statement.
            text = text[:local[0]] + text[local[3]:]
            position -= local[3] - local[0]
    if not dry:
        pathlib.Path(path).write_text(text)
    print(f"{path}: wrote out {done}; left {len(left)}")
    for line in left: print("  left " + line)
    return left


def local_definition(text, name, before):
    """(statement start, value start, value end, statement end with its newline) of the nearest `let name… = value`
    above `before`, or None."""
    matches = list(re.finditer(rf"\n(\t+)let {name}(?:: [^=\n]+)? = ", text[:before]))
    if not matches:
        return None
    m = matches[-1]
    value_start = m.end()
    # The value ends at the first newline at depth zero outside literals.
    depth = 0; i = value_start
    while i < len(text):
        if text.startswith('"""', i):
            i = text.index('"""', i + 3) + 3; continue
        c = text[i]
        if c == '"':
            i += 1
            while text[i] != '"':
                i += 2 if text[i] == "\\" else 1
        elif c in "([{": depth += 1
        elif c in ")]}": depth -= 1
        elif c == "\n" and depth == 0:
            nxt = text[i + 1:].lstrip("\t")
            if not nxt.startswith(("+", "?", ":", ".")):
                break
        i += 1
    return m.start() + 1, value_start, i, i + 1
