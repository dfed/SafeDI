"""normalize-mocks.py OFF ON

Compares two combined outputs of one graph, OFF written by the mock walk and ON with mock bodies laid out from node
records, after undoing each byte difference the lead approved for mock bodies (approved-byte-differences.md, numbered as
there). Prints one line, `APPROVED <number>=<count> ...` or `UNAPPROVED <reason>`, and exits 0 only for APPROVED.

Each normalization counts the sites it changes, so a run's totals show whether a class grows. What the normalizations
cannot tell apart, and so let through: an approved difference that also moved a statement within one function (difference
2 is checked as a set of lines per mock, so order inside a mock body is not compared), and a value read through another
path of the overrides (difference 1 keeps no label of a read but `safeDIBuilder`). Everything outside the
bodies of the generated `mock(` functions, the file's other lines, is compared byte for byte.
"""
import re
import sys

MOCK_FUNCTION = re.compile(r"^[^\n]*\bfunc (?:__safeDI_)?mock\(", re.M)


def blocks(text):
    """The body of each generated `mock(` function, from its declaration's line to its closing brace, matched by counting
    braces, and the rest of the file with each body replaced by a marker. A mock is compared whether or not a mock
    condition wraps it, since a module can set `mockConditionalCompilation: nil`."""
    found = []
    rest = []
    index = 0
    for match in MOCK_FUNCTION.finditer(text):
        if match.start() < index:
            continue
        opening = text.find("{", text.find(")", match.end()))
        depth = 0
        position = opening
        while position < len(text):
            if text[position] == "{":
                depth += 1
            elif text[position] == "}":
                depth -= 1
                if depth == 0:
                    break
            position += 1
        end = text.find("\n", position)
        end = len(text) if end < 0 else end + 1
        rest.append(text[index : match.start()])
        rest.append("<mock>\n")
        found.append(text[match.start() : end])
        index = end
    rest.append(text[index:])
    return found, "".join(rest)


def subn(pattern, replacement, text, flags=0):
    return re.subn(pattern, replacement, text, flags=flags)


def drop_override_arguments(block, counts, laid_out):
    """Removes each `safeDIOverrides: …` parameter or argument, and every argument after it in its list (difference 5's
    overrides of unavailable dependencies), matching parentheses, so a type such as `((String) -> Child)?` is one value.
    """
    out = []
    index = 0
    key = "safeDIOverrides: "
    while True:
        found = block.find(key, index)
        if found < 0:
            out.append(block[index:])
            return "".join(out)
        # Only an element of a parenthesized list: after `(` or `, ` (possibly after a newline and indentation).
        before = block[:found].rstrip(" \t\n")
        if not (before.endswith("(") or before.endswith(",")):
            out.append(block[index : found + len(key)])
            index = found + len(key)
            continue
        depth = 0
        position = found
        extra_arguments = False
        while position < len(block):
            character = block[position]
            if character in "([{<" and not (character == "<" and block[position - 1] == "-"):
                depth += 1
            elif character in ")]}>" and not (character == ">" and block[position - 1] == "-"):
                if depth == 0:
                    break
                depth -= 1
            elif character == "," and depth == 0:
                extra_arguments = True
            position += 1
        # `mock()`'s own `safeDIOverrides: SafeDIOverrides = .init()` goes from both texts alike.
        if laid_out and "SafeDIOverrides = .init()" not in block[found:position]:
            counts[1] += 1
            if extra_arguments:
                counts[5] += 1
        cut = len(before)
        if before.endswith(","):
            cut -= 1
        out.append(block[index:cut])
        index = position


def normalize(block, counts, laid_out):
    # 6: an argument with no label, which production spells `_: value`.
    if laid_out:
        block, n = subn(r"(\(|, )_: ", r"\1", block)
        counts[6] += n
    # 4: a wrapper binding of an extension's type, which production annotates with the type it builds.
    if laid_out:
        block, n = subn(r"let (\w+): ((?:Sendable)?(?:Erased)?Instantiator<[^=\n]+>) = \2\(", r"let \1 = \2(", block)
        counts[4] += n
    # 3: the local that held a function's configuration beneath an actor, which the laid-out function is handed.
    # Also the local a `@Sendable` function's override is bound to (`__safeDI_r0__safeDIBuilder`), which the walk's
    # function captures and the laid-out function is handed: counted with 3, in whichever text binds it.
    block, n = subn(r"^[ \t]*let __safeDI_\w+__(?:overrides|safeDIBuilder) = safeDIOverrides[.\w]*\n", "", block, re.M)
    if not laid_out:
        counts[3] += n
    block = re.sub(r"\b__safeDI_\w+__(?:overrides|safeDIBuilder)\b", "safeDIOverrides", block)
    # 1 and 5: a function handed its node's overrides, and after them each unavailable dependency's override. Both go,
    # from declarations and calls, in both texts, where the argument list ends on its line.
    block = drop_override_arguments(block, counts, laid_out)
    # 2: a function declared once in the root's body is handed the values its parent's scope held, which the walk's
    # function, nested in that parent, captured: its parameters, and arguments that pass a value under its own name, go.
    def strip_parameters(match):
        if laid_out and match.group(2):
            counts[2] += 1
        return match.group(1) + "()"
    block = re.sub(r"(func __safeDI_\w+)\(([^()\n]*(?:\([^()\n]*\)[^()\n]*)*)\)", strip_parameters, block)
    def strip_passed_values(match):
        arguments = [argument.strip() for argument in match.group(2).split(",")] if match.group(2).strip() else []
        kept = [argument for argument in arguments if not re.fullmatch(r"(\w+): \1", argument)]
        if laid_out and len(kept) != len(arguments):
            counts[2] += 1
        return match.group(1) + "(" + ", ".join(kept) + ")"
    block = re.sub(r"(?<!func )(__safeDI_\w+)\(([^()\n]*)\)", strip_passed_values, block)
    # 1: the closure a wrapper takes where its function is handed an argument, written as production writes it.
    if laid_out:
        block, n = subn(r"(\w+<[^<>\n]+>) \{\n[ \t]*(__safeDI_\w+)\(\)\n[ \t]*\}", r"\1(\2)", block)
        counts[1] += n
    # 1: a read of the overrides spells the path from the function's own argument rather than from `mock()`'s parameter.
    # A node's override closure is the function's argument itself, where the walk reads it at its path; a configuration's
    # builder is `.safeDIBuilder` of either. So a read keeps no label but `safeDIBuilder`.
    block = re.sub(r"\bsafeDIOverrides(?:\.\w+)*", lambda m: "safeDIOverrides.safeDIBuilder" if m.group(0).endswith(".safeDIBuilder") else "safeDIOverrides", block)
    return block


def main():
    off_text = open(sys.argv[1]).read()
    on_text = open(sys.argv[2]).read()
    if off_text == on_text:
        print("APPROVED")
        return 0
    off_blocks, off_rest = blocks(off_text)
    on_blocks, on_rest = blocks(on_text)
    if off_rest != on_rest:
        print("UNAPPROVED outside-mock-bodies")
        return 1
    if len(off_blocks) != len(on_blocks):
        print("UNAPPROVED mock-count")
        return 1
    counts = {number: 0 for number in (1, 2, 3, 4, 5, 6)}
    off_lines_total = on_lines_total = wrapper_closures = 0
    for off_block, on_block in zip(off_blocks, on_blocks):
        off_lines_total += off_block.count("\n")
        on_lines_total += on_block.count("\n")
        wrapper_closures += len(re.findall(r"\w+<[^<>\n]+> \{\n[ \t]*__safeDI_\w+\(", on_block))
        if off_block == on_block:
            continue
        off_normalized = normalize(off_block, counts, laid_out=False)
        on_normalized = normalize(on_block, counts, laid_out=True)
        if off_normalized == on_normalized:
            continue
        # 2: each node's function declared once in the root's body, where the walk declares it in each parent: the same
        # lines, each function's once, at another indentation.
        off_lines = [line.strip() for line in off_normalized.split("\n") if line.strip()]
        on_lines = [line.strip() for line in on_normalized.split("\n") if line.strip()]
        if set(off_lines) != set(on_lines):
            missing = sorted(set(off_lines) - set(on_lines))[:1]
            extra = sorted(set(on_lines) - set(off_lines))[:1]
            print(f"UNAPPROVED lines off-only={missing!r} on-only={extra!r}")
            return 1
        counts[2] += sum(1 for line in set(on_lines) if on_lines.count(line) != off_lines.count(line))
    if on_lines_total > off_lines_total + 2 * wrapper_closures:
        print(f"UNAPPROVED more-lines off={off_lines_total} on={on_lines_total} wrapper-closures={wrapper_closures}")
        return 1
    print("APPROVED " + " ".join(f"{number}={count}" for number, count in counts.items() if count))
    return 0


if __name__ == "__main__":
    sys.exit(main())
