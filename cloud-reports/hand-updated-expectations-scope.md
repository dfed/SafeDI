# Hand-updated test expectations: why, and what removing them takes

Scope only. Nothing here is built. Evidence: slice 2's hand-edit commits (9636f4b2 and c6d5883f on
`dfed--claude/s2-builder-struct-snapshot`), its regenerator report and records
(`cloud-reports/slice-2-regen/` on `dfed--claude/productivity-retros`), and counts over `Tests/` at 4ad19ed1.
I classified every hunk of the two hand-edit commits by how the test builds the expectation it changes. I did
not rerun the regenerator on the tree before the hand edits (the records were taken after them), so the
"would be covered" column is a classification, not a measured run.

## What slice 2 edited by hand

103 edited places in 18 files (747 lines changed).

| Kind | Places | Why the regenerator skipped it | What removes it |
|---|---|---|---|
| A. A literal with an interpolation on a line that changed | 35 | The line holds the seam's guard name and `\(integration.seamCallComment(…))`. The guard hash changes with every change to a seam's shape, so the line always changes, and the script puts an interpolation back only where the line is untouched | Regenerator extension 1 |
| B. Literals a helper joins into one file (`Self.generatedFiles(module:…, """…""")`, `expectGeneratedCode(rootFiles:)`) | 26 | No fragment mapping at the time | Already solved by the fragment mapping (ef0c16e2); slice 2's rerun rewrote these |
| C. A guard name passed as an argument or switch case (`guardName: "__safeDI_Hub_479B…"`, `case .generic: "__safeDI_Host_CC41…"`) | 29 | The literal is one token of the output, never a whole output or a fragment | Regenerator extension 2 |
| D. A shared expectation function outside any test (`appFile(guardName:)`, 7 to 13 interpolations) | 2 | Interpolations in changed regions, as A | Extension 1 covers the body; C's sites are its arguments |
| E. Assertions on counts or filtered lines (`.filter { $0.contains("public init(") }`, `components(separatedBy: "@frozen public enum ")`) | 10 lines in 2 tests | Not an expected output at all | Nothing: these are judgment edits. A rule should keep new ones rare |
| F. A hand-written fixture input (a call the test's source makes) | 1 | It is input, not expectation | Nothing |

So of the 77 places still out of reach after the fragment mapping, 66 come from one cause: the guard hash,
and the other 11 are kinds E and F.
It sits on a line with an interpolation (A, D) or travels alone as an argument (C). The lead's four reasons
(interpolation in a changed region, ambiguous captures, non-literal expected value, shared per-module helpers)
are the same thing seen from the report's side.

How widespread the cause is, at 4ad19ed1: 220 lines hold a guard hash and an interpolation (162 in the seam
tests), 152 literals use `seamCallComment`, and 38 sites pass a guard name as an argument or switch case, all in
the seam tests. Every slice that changes a seam's shape changes every one of these hashes.

## Recommendation: two regenerator extensions, a rule, and a narrow migration

### Extension 1: put an interpolation back on a changed line (2 to 3 lane-hours)

Today a capture is put back only when its captured text lies in a part of the output the change left alone.
Add: when the captured text of an interpolation occurs exactly once in the head line that pairs with its base
line, and the text around it on that line differs, the interpolation is put back at that occurrence. The capture
itself must be unchanged; a capture whose own text changed stays manual. Self-tests: a hash beside a comment
interpolation; a capture that occurs twice on the head line (manual); a capture whose text changed (manual); two
interpolations on one changed line.

### Extension 2: a literal that is one token of the output (3 to 4 lane-hours)

A rules-file list names token patterns (for slice-style changes, `__safeDI_\w+_[0-9A-F]{16}`). A plain literal
whose whole value matches a pattern is rewritten when, in every record of the tests that can reach it (the
test's own records, or for a `case` in a helper every test that calls the helper), each occurrence of the old
token in the base output is the new token at the same place in the head output, and the new token is one value.
Otherwise it is manual with the reason. This covers C without touching how tests are written. Self-tests: one
token, two tests that share a helper with different tokens, a token whose replacements disagree (manual), a
token that also occurs unchanged (manual).

### A rule in `.claude/rules/test-design.md` (half an hour, with either extension)

- An expected output is a literal the regenerator maps: a whole file, fragments through the file's
  `generatedFiles` helper, or a literal with interpolations of values the test's arguments decide.
- A value the generator computes (a guard hash) is spelled in the literal or passed as a whole-token literal; it
  is never assembled from parts.
- A count or line-filter assertion is used only where the whole output would be thousands of lines, and says so.
- A new test file's expectations are checked with the regenerator's mapping statistics before review.

### Migration: narrow, not the whole-literal rewrite

I recommend against migrating every fragment-built or interpolated expectation to whole literals:

- 578 mapped literals hold 805 interpolations, and 546 tests of the four tool test targets take arguments (324 in the seam tests). An
  interpolation there stands for a value an argument decides (`integration`, a tier, a wrapper kind). A whole
  literal per argument value multiplies those expectations by 2 to 11 and makes each future change that much
  larger to read.
- Fragment-built tests are mapped now. Slice 2's rerun rewrote them.
- A rewrite of roughly 150,000 lines of seam and mock tests is itself a large review, for a gain the two
  extensions give in a day.

What is worth migrating, once, output-neutral (2 to 3 lane-hours): the 2 tests of kind E to a whole-file
comparison where the file is small enough, and any expectation the acceptance check below still cannot map
after the extensions.

### Acceptance check (1 to 2 lane-hours, built with extension 1)

`--audit`: with one record directory, perturb every guard hash in a copy of it and report, per test function,
whether every literal that holds a perturbed value would be rewritten. It prints the tests that would need a
hand edit if every seam's shape changed. The gate before slices 3 to 7: the audit lists only kind E and F tests,
by name. This replaces "maps 100% of every migrated test" with something that runs in CI's self-test job.

## Cost and order

| Piece | Lane-hours |
|---|---|
| Extension 1 and its self-tests | 2 to 3 |
| Audit mode | 1 to 2 |
| Extension 2 and its self-tests | 3 to 4 |
| Rule, skill text, narrow migration | 2 to 3 |
| Adversarial review rounds (the fragment mapping took four) | 3 to 5 |
| Total | 11 to 17, about one working day elapsed |

It changes only the skill's script, its self-test and test files, so it can merge under the lane's standing
permission. It has no dependency on the leak-fix slices and rebases cleanly under them: it should sit at the
bottom of the stack that carries slice 3, so slices 3 to 7 regenerate with it. Expected effect, from slice 2's
numbers: the 77 places slice 2 still edited by hand after the fragment mapping become about 11 (kinds E and F).

## Found in passing

The script stops with a `UnicodeDecodeError` on a record directory unpacked from a Mac archive, which carries
`._*` files beside the records. It should skip files that are not records. A few lines, with extension 1.
