"""normalize-mocks.py OFF ON

Compares two combined outputs of one graph, OFF written by the mock walk and ON with mock bodies laid out from node
records, after undoing each byte difference the lead approved for mock bodies (approved-byte-differences.md, numbered as
there). Prints one line, `APPROVED <number>=<count> ...` or `UNAPPROVED <reason>`, and exits 0 only for APPROVED.

Each normalization counts the sites it changes, so a run's totals show whether a class grows. What the normalizations
cannot tell apart, and so let through: an approved difference that also moved a statement within one function (difference
2 is checked as a set of lines per mock, so order inside a mock body is not compared), and a value read through another
path of the overrides where the last label agrees (difference 1 keeps only a read's last label). Everything outside the
mock blocks, the file's other lines, is compared byte for byte.
"""
import re
import sys

MOCK_BLOCK = re.compile(r"^#if DEBUG\n.*?^#endif\n", re.S | re.M)


def blocks(text):
    """The mock blocks (each `#if DEBUG` ... `#endif`), and the rest of the file with each block replaced by a marker."""
    found = MOCK_BLOCK.findall(text)
    return found, MOCK_BLOCK.sub("#if DEBUG <mock>\n", text)


def subn(pattern, replacement, text, flags=0):
    return re.subn(pattern, replacement, text, flags=flags)


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
    if not laid_out:
        block, n = subn(r"^[ \t]*let __safeDI_\w+__overrides = safeDIOverrides[.\w]*\n", "", block, re.M)
        counts[3] += n
        block = re.sub(r"\b__safeDI_\w+__overrides\b", "safeDIOverrides", block)
    # 1 and 5: a function handed its node's overrides, and after them each unavailable dependency's override. Both go,
    # from declarations and calls, in both texts, where the argument list ends on its line.
    def drop(match):
        rest = match.group(2)
        if laid_out and re.search(r",\s*\w+:", rest):
            counts[5] += 1
        if laid_out:
            counts[1] += 1
        return match.group(1) + ")"
    block = re.sub(r"(\(|, )safeDIOverrides: ([^()\n]*(?:\([^()\n]*\)[^()\n]*)*)\)", lambda m: ("(" if m.group(1) == "(" else "") + drop(m)[len(m.group(1)) :], block)
    # 1: the closure a wrapper takes where its function is handed an argument, written as production writes it.
    if laid_out:
        block, n = subn(r"(\w+<[^<>\n]+>) \{\n[ \t]*(__safeDI_\w+)\(\)\n[ \t]*\}", r"\1(\2)", block)
        counts[1] += n
    # 1: a read of the overrides spells the path from the function's own argument rather than from `mock()`'s parameter.
    block = re.sub(r"\bsafeDIOverrides\.(?:\w+\.)*(\w+)", r"safeDIOverrides.\1", block)
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
        print("UNAPPROVED outside-mock-blocks")
        return 1
    if len(off_blocks) != len(on_blocks):
        print("UNAPPROVED mock-block-count")
        return 1
    counts = {number: 0 for number in (1, 2, 3, 4, 5, 6)}
    off_lines_total = on_lines_total = wrapper_closures = 0
    for off_block, on_block in zip(off_blocks, on_blocks):
        off_lines_total += off_block.count("\n")
        on_lines_total += on_block.count("\n")
        wrapper_closures += len(re.findall(r"\w+<[^<>\n]+> \{\n[ \t]*__safeDI_\w+\(safeDIOverrides:", on_block))
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
