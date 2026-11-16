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
