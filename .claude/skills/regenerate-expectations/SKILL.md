---
name: regenerate-expectations
description: Rewrite the expected string literals of SafeDITool's tests after a generator change alters generated code or diagnostics, from what the tests recorded before and after, and list every change the predicted transform does not explain. Use instead of pasting actual output into tests.
---

# Regenerate test expectations

`regenerate-expectations.py`, beside this file, rewrites the expectations a change alters. Never paste actual output into a test. Run every command from the repository root; `S` below is `.claude/skills/regenerate-expectations/regenerate-expectations.py`. Its `--help` is the full contract: what is matched, the rules format, the report, the exit statuses.

The hook is `Tests/SafeDIToolTestSupport/ExpectationRecording.swift`: with `SAFEDI_TEST_RECORD_DIRECTORY` naming a directory outside the checkout and the system temporary directory, `executeSafeDIToolTest` and `executeSafeDIToolMultiModuleTest` record every output, and the exact-match assertion helpers every mismatch, with run paths replaced by placeholders. Without it they record nothing, and recording never changes what a test compares.

1. Record the base: on the old generator (the commit that adds the change's failing tests), run the tests with `SAFEDI_TEST_RECORD_DIRECTORY=BASE` (`SAFEDI_SKIP_COMPILE_CHECK=1` may skip compiles), then `python3 -I S --write-manifest BASE --checkout .`.
2. Record the head the same way on the new generator, over the same `Tests/`, into `HEAD`.
3. Write the change's rules file, which predicts its renames and rewrites (`rename`, `rewrite`, `normalize` lists).
4. Try it: `python3 -I S --base-records BASE --head-records HEAD --rules RULES.json --report REPORT --checkout . --dry-run`, read `REPORT/report.txt`, improve the rules, then run it without `--dry-run` into an empty report directory.
5. Read every unexplained residual diff, every manual item, the changed outputs no literal matched, the compile-skipped list and the sample of explained literals in the report. Update the manual and unmatched ones by hand, and check that each new expectation would compile and is what the change intends: the actual output may itself be wrong.
6. Run the tests with the variable unset, so compile verification checks the new expectations.

What it rewrites: a literal that equals a whole recorded output, in the test that recorded it (found by the location of the test the record carries when the call goes through a helper function), and literals a helper joins into one output as fragments (header, imports, fragments, blank lines between) when they tile it in exactly one way and the change touches no fragment's edge. An expectation assembled any other way, an assertion wrapper's parameter, `assertThrowsError(containing:)` and the query helpers are left to a person; the report says why each record was not mapped.

After changing the script, run `python3 -I S --self-test DIR` with a directory that does not exist; "Check Line Coverage on Linux" runs the same.
