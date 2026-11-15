---
name: apply-edit
description: Replace exact text in files with the old and new text read from files, when an edit holds tabs, quotes, backslashes or many lines, or several edits must apply all or none. Use instead of a one-off script or shell quoting.
---

# Apply an exact-text edit

`apply-edit.py`, beside this file, replaces exact text in a file. The old and the new text come from files, so nothing has to be quoted for a shell. Run it from the repository root with `python3 -I`.

One edit: write the old text and the new text to two files outside the checkout, then

```bash
python3 -I .claude/skills/apply-edit/apply-edit.py FILE OLD_FILE NEW_FILE
```

- Text that occurs more than once is refused unless `--all` is given; occurrences that overlap are refused either way. Give more of the surrounding text instead.
- `--trim-final-newline` drops the one final newline an editor adds to `OLD_FILE` and `NEW_FILE`.

Several edits, all or none: write `[{"file": "path", "old": "…", "new": "…", "all": false}, …]` to a JSON file and pass `--edits EDITS.json`. Edits apply in order, and a later edit of a file sees the earlier ones.

Nothing is written unless every edit applies; exit status 1 names the edit that does not, and 2 is wrong usage. A file is replaced whole and keeps its permissions; a file with a second hard link is refused. The script's own help (`--help`) is the full contract.

After changing the script, run `python3 -I .claude/skills/apply-edit/apply-edit.py --self-test DIRECTORY` with a directory that does not exist; "Check Line Coverage on Linux" runs the same.
