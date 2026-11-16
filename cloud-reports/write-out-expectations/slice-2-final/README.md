# Write-out migration on slice 2's final head (8f057441)

Records: one run of the suite on 8f057441 with `SAFEDI_TEST_RECORD_DIRECTORY` set (5,443 tests pass).

1. `write-out-expectations.py --records … --checkout . --report …`: 451 comparisons written out. New since the run on
   main: a second pass rewrites a comparison of a module's generated files whose expected side calls a helper, from the
   records of the generation it is compared with; and the two integrations' files become one literal when they differ
   only in file name and in the comment on a seam call (key chosen by the integration, the comment through
   `integration.seamCallComment(type:declaringModule:)`).
2. `delete_dead.py 8f057441`: deletes helpers of the tests nothing reads any more and that were read at the base.
3. `inline_generated_files.py FILE:LINES…`: inlines calls of `generatedFiles(module:integration:imports:rootFiles:)`
   and SendableFill's `expectGeneratedCode` whose text an argument decides, keeping the interpolations.
4. `by_release.py`: the three UnreadTypeAccess tests that loop over `isReleaseConfiguration`.
5. By hand: the two namespace-chain comparisons in AccessEnforcement, the eight-screens mock comparison in
   ReceivedBuilderCycle, the guard hashes spelled in place in SeamDeferredParameter, the `Self.comment([…])`
   interpolations spelled out, SendableFill routed through `expectGeneratedFiles`, three stale comments deleted.

`left-as-they-are.txt` is the tool's report of step 1 (what its first pass could not tile; the second pass and the hand
steps then covered what the helper-built search finds in seam tests).

## Follow-up commit: the fifteen comparisons in the tool's and the mocks' tests

Recorded only the three suites on the migrated head (`swift test --filter '…'` with the record variable, then
`--write-manifest`), and ran `write-out-expectations.py … --helpers-only`, which skips the fragment pass and rewrites
each comparison whose expected side calls a helper whole, from the records: 13 written. `tail_hand.py` holds the five
whose text an argument decides.

## Redoing this after a rebase

Where a rebase brings new or changed tests: record the changed suites on the rebased head (filter run, a few seconds
each with a built tree), write the manifest, run the tool without `--helpers-only` and with `--only <file name>` per
changed file, lint, delete helpers nothing reads (`delete_dead.py <base>`), and run the changed suites.

## After the lead's review (c4437122 and the commit above it)

The same-line search missed helpers called on an earlier line, shared constants and locals. Scripts added here:

- `from_records.py`: a library over the records of a run. `rewrite_calls` replaces each call of a helper with the
  files its test generated (matching a guard hash in the call); `switch_on_argument` turns a comparison that reads a
  property of the test's argument into a switch between whole files; `rewrite_file` writes out every comparison of a
  file whose expected side is not spelled out, where the test has one recorded file set. It leaves, with the reason,
  tests that take another argument, run the tool several times, or name a checkout path, and never touches a
  comparison of one run's files with another's.
- `delete_unreferenced.py FILE…`: deletes private members nothing references, to a fixed point (stricter than
  `delete_dead.py`: it matches a call by its argument labels, so a helper named like a property is found).
- `delete_unused_locals.py < build output`: deletes the locals `swift build` warns were never used.
- `delete_nested.py FILE NAME…`: deletes a nested property no `.NAME` reads.
- `inline_helper.py FILE HELPER`: inlines a one-expression helper at calls that pass it string literals.

Loop used: rewrite, `delete_unreferenced.py`, build, `delete_unused_locals.py`, repeat until no warning, lint,
`verify-touched.py HEAD`, then the whole suite once.
