---
name: split-generator
description: Split DependencyTreeGenerator.swift into one file per concern by moving whole declarations, with no other change, from a map of where each run of declarations goes. Use to run or rerun the 2.3.1 file split on a new commit, or to split another large source file the same way.
---

# Split a large source file by concern

`split-generator.py`, beside this file, moves the members of one type into `extension` files by concern. It reads declarations, not line numbers, so it runs again on a later commit. Run it from the repository root; `S` below is `.claude/skills/split-generator/split-generator.py`, and `--help` is its full contract. `split-map.json`, beside it, is the map for `DependencyTreeGenerator.swift`: each `[anchor, file]` starts a run of declarations that goes to `file` (`stay` keeps it), up to the next anchor. `ScopeGenerator.swift`'s emission is not in the map: 2.3.1 rewrites it as small files.

1. `python3 -I S --list` prints every declaration of the source with its line and size; `python3 -I S --dry-run` prints what would move and which declarations would stop being `private`.
2. Run it without `--dry-run` on a clean checkout. It moves the declarations, removes `private` or `fileprivate` only from what another file now names (and from a private type such a declaration shows in its signature), keeps `ErrorReportingSite` paths true and applies the map's text replacements.
3. Read its `to read:` lines, each a file that still names the source file, and its `NOT REPLACED` lines.
4. Build the tests, run the whole suite, and run `./CLI/lint.sh`. No expectation and no fuzzer pin may change: the split moves text only. A compile error means a case the access rule does not read: fix the script and run it again on a clean checkout, never the output by hand.
5. Commit the split alone. `Scripts/unmeasured-files.txt` needs a line only for a new file with no executable code, which "Check Line Coverage on Linux" then names; scoped rules' `paths:` that name `Sources/SafeDICore/Generators/**/*` already cover the new files.

An anchor the source no longer holds stops the run ("the map is older than the source"): point the map at the declaration that now starts that run. To rerun after a late change, run it on the unsplit file of the new commit; on a tree that is already split it changes nothing and exits 1.

After changing the script, run `python3 -I S --self-test DIR` with a directory that does not exist, outside the checkout and the system temporary directory.
