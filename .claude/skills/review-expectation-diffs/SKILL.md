---
name: review-expectation-diffs
description: Sort every generated output a change alters into structural classes, accept the classes an approved-differences file lists, and show only new classes with one example and a count. Use after a generator change or a stacked merge rewrites expectations, instead of reading every rewritten literal.
---

# Review expectation diffs by class

A generator change can rewrite thousands of expected lines in a handful of forms. This skill reads the forms, not the lines: a person approves a form once, in a checked-in file, and from then on only an output with a form nobody approved reaches a person. Expectations stay whole literals compiled by the tests; this changes how a person reads their diff, not what the tests check. Run every command from the repository root.

`record-and-review.sh --base REF --approved FILE OUT` is the one command: it builds and records the old generator (`REF` with this checkout's `Tests/`) and this checkout at once, rewrites the expectations with `regenerate-expectations` (`--apply`; without it, a dry run), and classifies. `--head-env`/`--base-env NAME=VALUE` record one commit both ways, for a change behind a switch. Base records are cached by what decides them, so the lanes of a stack that merge one base record it once. `--fast` records without compile verification for a first pass; the run with compile checks on still settles the change. Its `--help` is the full contract.

`review-expectation-diffs.py --base-records BASE --head-records HEAD --approved FILE --report DIR [--failed-tests FILE]` is the classifier on its own, on the record directories `regenerate-expectations` reads. Its `--help` says how outputs are compared and shapes are cut.

1. Read `DIR/report.txt`: the count accepted by each combination of entries, then each new class with its shapes, its tests, one example's leftover lines and an `approve` snippet. A class labeled `not approved` matches the file's "Not approved" forms and is a defect; one labeled `withdrawn` matches a withdrawn entry's old form.
2. For each new class, read the example. If it is a defect, fix the generator. If the lead approves the form, add the snippet to the approved file with the ruling, and run again.
3. A failed test with no changed output fails for a reason no output shows: read it.

The approved file is JSON (`approved/mock-layout.json` is the node records mock layout's list, from `lanes/per-type-facts/approved-byte-differences.md`). Each entry is `steps` (rewrites applied in file order before the comparison, and `hoistFunctions`, which compares functions by name wherever they are declared) or `shapes` (exact shapes the report printed), with a `status` of `approved`, `withdrawn` or `notApproved`, and `tests` when the ruling names its roots. Matching an entry classifies a difference; the entry's own conditions (compiling, executed values) still gate it. Keep a step to the side that writes the form: a step applied to both sides that only one side needs hides a change on the other.

After changing the classifier, run `python3 -I .claude/skills/review-expectation-diffs/review-expectation-diffs.py --self-test DIR` with a directory that does not exist.
