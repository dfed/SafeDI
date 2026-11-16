# Brief N5: the re-runnable split script (productivity lane)

For the developer productivity lane. Plan: `plans/2.3.1-plan.md` (items N5, S1). Ruling NO-STANDALONE-FILE-SPLIT, amended (in `cloud-reports/facts-for-2-3-1-plan.md`): the productivity lane does a scripted, pure-move split by concern of the code that survives the rewrite (validation, tree building, shared infrastructure, mostly `DependencyTreeGenerator.swift`), self-merged under the standing permission, the moment the 2.3.0 stack completes; the emitter half is not split (the rewrite writes it as small files).

**Now (no `Sources/` change on main):** write the script (Python or Swift, your choice; it parses declarations rather than cutting by line numbers, so it survives edits) that moves top-level and extension members into files by concern, turns `private` members used across the new files into `fileprivate`-free internal ones only where needed, and updates `Scripts/unmeasured-files.txt`, scoped rules' `paths:` lists and the fuzzer coverage report's file filters. Concerns: use `generator-simplification.md` B1's list for `DependencyTreeGenerator.swift` (seam driver, seam errors, mock orchestration, mock-root promotion, validation walks) and leave `ScopeGenerator.swift`'s emission areas in place. Dry-run it on the newest slice head and on main: the result builds, the suite passes, no expectation or pin changes, and a rerun on a later head works.

**At the 2.3.0 stack's completion:** run it at the bottom of the 2.3.1 base stack (S1) and self-merge; rerun whenever a late 2.3.0 fix lands.

**Hand-back:** script location (branch and commit), dry-run results on both heads, the file map, anything the script cannot move mechanically.
