# Adjudication: claude/apply-fuzzer-pins @ e7520cd87

All eight findings hold; none is blocking. Three are should-fix and five are nits, and I widened finding 2 by one list.

I checked by reading the script, SKILL.md and the ci.yml diff at e7520cd87, the real `linux-pins-analyze.py`, and eddac9a3d's `pins.json` and `report.md`. I did not re-run the dry runs or the perturbed stress test, so the reviewer's "199 placed, 8 left" result is taken as reported. I created no worktree.

## Should-fix

### 1. Exit 0 and "0 left" while the run moved pins the analysis does not derive
- **Verdict:** confirmed.
- **Where:** `apply()` lines 316–324 and docstring lines 26–27; the script never reads `notDerived`.
- **Evidence:**
  - eddac9a3d's `pins.json` has 7 `notDerived` entries and one pin, `publicMockCorpusFixtureHash`.
  - 971acd4cf, which applied that run, changed three constants: that one plus `seamSmokeAndKnownIssueFixtureHash` and `publicMockSmokeAndKnownIssueFixtureHash`. Both extras are in `notDerived`.
  - So on real data the script would say "0 left" and exit 0 with two pins still to change.
- **Correction to the proposed fix:** `notDerived` is the analyzer's constant `NOT_DERIVED` and is never empty. "Return 1 whenever `notDerived` is non-empty" would make exit 0 unreachable.
- **Fix:**
  - When at least one pin was written or left, print one line: `not derived by the analysis, read from the unit suite's failures in the same run: <notDerived joined>`.
  - Return 1 in that case, because a moved pin means the smoke-and-known-issue hashes may have moved too.
  - Keep exit 0 for a run that moved nothing.
  - Reword docstring lines 26–27 and SKILL.md step 4 to name these pins.
  - Add a self-test case for it.

### 2. An incomplete or unclassified analysis can pass as "nothing to do"
- **Verdict:** confirmed, and widened.
- **Where:** `INTEGRITY_LISTS` line 47 and `check_provenance` lines 267–269.
- **Evidence:**
  - The analyzer's integrity dictionary (line 715) has seven lists. The script checks five; it skips `unclassified` and `rejectedKnownIssueLists`. The reviewer named only `unclassified`.
  - `all_complete = bool(corpora_order) and …` (line 1253) is false with no reports, while `incompleteCorpora` stays empty. `pins.json` is still written, with `"complete": false` and exit 69.
  - `document.get(name)` treats a missing key as empty.
- **Fix:** in `check_provenance`:
  - refuse unless `document.get("complete") is True`;
  - add `unclassified` and `rejectedKnownIssueLists` to `INTEGRITY_LISTS`;
  - refuse when any of those keys is absent or not a list;
  - add a self-test case for each, and update the docstring's list.

### 3. Step 2 of the skill cannot be done from the repository
- **Verdict:** confirmed.
- **Where:** SKILL.md step 2.
- **Evidence:**
  - `git grep` for `pins.json`, `linux-pins` and `validForHead` at e7520cd87, outside the skill directory, finds nothing.
  - The only mention of the skill outside its directory is the new ci.yml step. `.claude/rules/fuzzer-corpora.md` does not name it.
  - The producer of schema 1 is a script of about 1,500 lines that exists only in a local scratch directory. The self-test's fixtures are therefore the only schema contract, and drift goes unnoticed.
- **Fix:**
  - Preferred: check the analyzer and its fetch wrapper into `Scripts/` with a self-test, as a pull request below this one in the stack, and put the exact command in step 2.
  - A local path in SKILL.md is not an acceptable substitute.
  - Either way, add one sentence to "Coverage of a change" in `.claude/rules/fuzzer-corpora.md` pointing at the skill.
- **Severity note:** this is should-fix rather than blocking only because the script fails closed without a valid `pins.json`.

## Nits

### 4. `crashedShards` can never be listed
- **Verdict:** confirmed.
- **Evidence:** the analyzer adds to `crashed` only for a report that is not complete (line 876). That makes its corpus incomplete (lines 899–913), so `incompleteCorpora` is non-empty and the script refuses first.
- **Fix:** remove `crashedShards` from `OTHER_WORK` and from docstring line 26, and say that a crashed shard is refused. The commit message does not mention it, so nothing changes there.

### 5. Misleading refusal for a keyless pin whose constant is not a bare literal
- **Verdict:** confirmed by reading `place()` lines 229–242.
- **Evidence:** `x = other + 3` gives one token, and a mismatch raises "the report is not of this source". Refusing is safe; only the message and the status class are wrong. No current constant has this shape.
- **Fix:** for `key is None`, take the fast path only when the expression is exactly one number or `Name(value: number)`. Otherwise raise `LookupError("`%s` is not a single literal")` so it goes to `left`.

### 6. Small robustness gaps
- **Verdict:** confirmed.
- **Evidence:**
  - A `pins` entry that is not a dictionary raises `AttributeError`, which `except (Refusal, OSError, ValueError)` does not catch. Nothing is written, since writes come after the loop. But the traceback exits with status 1, which is also the "written, some left" status.
  - With neither source directory present, `Sources` is empty and every pin lands in `left`.
  - `spelled()` drops `_` from a hex literal.
- **Fix:**
  - refuse when a pin is not a dictionary;
  - refuse when no `.swift` file is found under `SOURCE_DIRECTORIES` ("not a SafeDI checkout");
  - leave the hex `_` case alone, or note it in the docstring.

### 7. The CI step reports late, and its name sits beside a near-twin
- **Verdict:** confirmed.
- **Evidence:** the step is in the job with `needs: [changes, spm, linux]` (ci.yml line 1424), next to "Check the Script Against Its Fixtures" (line 1440). I did not re-check the reviewer's claim that a `.py` change under `.claude/skills` trips `changes.source`; the author should confirm it.
- **Fix:** rename the step to "Check the Fuzzer Pins Script Against Its Fixtures". Moving it to a job that starts at once, such as "Check Markdown links", is optional; where it sits now follows the `unexecuted-lines.py` precedent.

### 8. The self-test leaves its fixture repositories behind
- **Verdict:** confirmed.
- **Evidence:** `self_test` refuses an existing directory, creates one repository per case under it, and never removes it. SKILL.md's last line lets the caller pick any path.
- **Fix:** `shutil.rmtree(root)` when every case passes, keeping it on failure for inspection. In SKILL.md, tell the reader to use a path outside the system temporary directory and the checkout, for example under `~/Library/Caches/SafeDITests/`.

## Dropped
None.

## Files
- Script under review: `.claude/skills/apply-fuzzer-pins/apply-fuzzer-pins.py` at e7520cd87. `origin/claude/apply-fuzzer-pins` now points at a later commit, ba55b80a4, which I did not review.
- Analyzer: `~/Library/Caches/SafeDIScratch/orchestrator-scratch-2026-11-01/bin/linux-pins-analyze.py`
- Real report: `~/Library/Caches/SafeDIScratch/linux-pins/eddac9a3d-coverage/pins.json`

---

# Adjudication: claude/apply-fuzzer-pins @ e7520cd87, safety-lens review

**Verdict: no blocking finding.** All five numbered findings and all five nits reproduce. I downgraded finding 1 from blocking to should-fix; findings 2 to 5 stay should-fix, and nit 5 moves up to should-fix.

How I checked:
- I read the script, SKILL.md and the ci.yml hunk at e7520cd87 (the branch tip is now ba55b80a4, one commit later, which only touches `Scripts/fuzz-corpus.sh`).
- I ran 15 probes on scratch git repositories built from the script's own fixture.
- I dry-ran both real reports from temporary detached worktrees at their commits.
- The worktrees and the scratch directory are removed. No repo edits, no pushes, no swift.

The guard analysis in the review is correct. `validForHead is not True`, `commit == headSha == HEAD` and the tracked-change check read the fields that `linux-pins-analyze.py` copies from context.json (lines 1271-1297). I found no path that writes a value from another head.

## Should-fix

### 1. Writing a constant silently moves a constant that names it (was blocking)
- **Location:** `apply()` lines 297-301; self-test cases "every kind of key" and "other work in the analysis".
- **Confirmed:** pins = [`acceptedCount` 1234 -> 5] exits 0, and `inspectedCount = acceptedCount` now evaluates to 5 with no pin for it.
- **Real instance:** `static let corpusValueOracleInspectedGraphCount = corpusAcceptedSeedCount` (SafeDIToolGraphFuzzerTests.swift:5410). The analyzer emits pins only for moved values (`pin_source`, lines 487-501), so a missing inspected pin means the run says it did not move.
- **Why not blocking:**
  - The two values are equal by design for the base corpus, so the current source cannot hit it.
  - If the invariant ever broke, the wrong inspected pin fails the next corpus check with a clear message ("inspected N graphs … but M are pinned").
  - It is still a write the run did not derive, with exit 0, and the self-test asserts it.
- **Fix:**
  - Before writing an unkeyed constant `C`, collect every `static let X = C` or `= Self.C` in the masked sources.
  - Write `C` only if each such `X` has a pin with the same `actual`. Those are the `following` entries already collected.
  - Otherwise leave `C` with "`X` names it, and the run did not move `X`", and exit 1.
  - Change the two self-test cases: add the `inspectedCount` pin to `everything`, and add a case "a constant another names is left when that one did not move" that expects status 1 and an unchanged source.
- **Dropped from the reviewer's fix:** the check for one identifier shared by two `Corpus(...)` arguments. There is no instance, and the existing "two pins name one literal" refusal covers the case where both moved.

### 2. A literal that is only part of an expression is replaced
- **Location:** `place()` lines 229-230 and 237; the `NUMBER` pattern.
- **Confirmed, all exit 0:**
  - `max(1_234, Self.floor)` became `max(5, Self.floor)`.
  - `Self.base + 1_234` became `Self.base + 5`.
  - `judged: 62 + extra` became `judged: 5 + extra`.
- **Additional case I found:** the sign is ignored. `static let acceptedCount = -1_234` with pinned 1234 is accepted and written as `-5`.
- **Reach:** no pinned declaration in the current sources has such a shape. The docstring promises "exactly one number", and the code checks only the count.
- **Fix:**
  - No key: require the masked expression to fullmatch `LITERAL` or `\w+\(\s*value\s*:\s*LITERAL\s*\)`. Otherwise raise LookupError "not a single literal".
  - Keyed: require that the text after the token, after an optional `)` of a `value:` wrapper and whitespace, starts with `,`, `)`, `]` or is the end of the expression.
  - Both rules also reject a leading `-`. Add one self-test case per rule.

### 3. Exit 0 when a fixture hash moved
- **Location:** `apply()` lines 316-324; `OTHER_WORK`.
- **Confirmed on the real eddac9a3d report:** one pin, `publicMockCorpusFixtureHash` 0x7A3E59F695DB4AE1 -> 0x9731E1275C7C8651, "1 pins would be written, 0 left", exit 0.
- **What it skips:** `combine.problems` says to re-derive the known issues, smoke seeds and pinned values, and `notDerived` lists seven things the run cannot give. Among them are the smoke and known-issue fixture hashes, which will now mismatch.
- **Why it matters:** the docstring defines 0 as "every pin was written and the analysis lists nothing else". SKILL.md step 4 mentions this, but the script's status and output say done.
- **Fix:** when any placed pin's `corpusLabel` is `fixtureHash` or `corpusPartitionHash`, print "not a pin, left to you: the graphs of <corpus> changed; re-derive <the `notDerived` entries>" and return 1. Add a self-test case.

### 4. `complete`, `rejectedKnownIssueLists` and `unclassified` are ignored
- **Location:** `INTEGRITY_LISTS`, `OTHER_WORK`, `check_provenance()`.
- **Confirmed, each exits 0 with the pin written:**
  - `complete: false, exit: 69` with an empty `incompleteCorpora`. The analyzer's line 1253 makes `complete` false when no report has a `corpora` line, without adding an entry.
  - Non-empty `rejectedKnownIssueLists`.
  - Non-empty `unclassified`.
- **Fix:**
  - Refuse unless `document.get("complete") is True`. This covers `exit == 69`, which the analyzer sets exactly when `complete` is false.
  - Add `rejectedKnownIssueLists` to `INTEGRITY_LISTS`.
  - Add `("unclassified", "combine problems nothing accounts for")` to `OTHER_WORK`.
  - Do not gate on `combine.exit` or `exit == 1`. Both are non-zero whenever any pin moved.
  - Update the docstring's list and SKILL.md's last paragraph. Add the `complete` key to the self-test's base document, with one case per new rule.

### 5. A malformed entry exits 1 with a traceback
- **Location:** `apply()` line 302 (`except (Refusal, OSError, ValueError)`), line 284.
- **Confirmed:** a non-object entry in `pins` raises AttributeError and exits 1 with nothing written, including when it follows a valid pin. SKILL.md reads 1 as "the rest was written".
- **Fix:**
  - At the top of the loop: `if not isinstance(pin, dict): raise Refusal("a pin that is not an object")`.
  - Refuse a `key` that is a bool or not None/str/int. This also closes the nit below where `key: true` was applied as index 1 (confirmed: `[4, 11, 0, 26]` became `[4, 5, 0, 26]`).
  - Widen the handler before the writes to `except Exception`, returning 2.
- **Lowered to nit:** the reviewer's temporary-file and `os.replace` write. An OSError between two file writes is remote, and git restores the files.

### 6. SKILL.md step 2 names nothing a reader can run (was nit 5)
- **Confirmed:**
  - Step 1 dispatches `verify.yml`, whose workflow name is `Verify`.
  - The only producer of `pins.json` is the scratch `linux-pins`, which is not in the repository.
  - Its line 168 refuses any run whose `workflowName` is not `CI` or `Graph Fuzzer`.
  - So step 2 cannot be done from step 1's run. This is outside the script's safety.
- **Fix, either:**
  - make `linux-pins --from-run` accept `Verify` runs with `pins=true`, and have step 2 say what produces the file; or
  - change step 1 to the `graph-fuzzer.yml -f coverage=true` dispatch that the tool accepts today.

## Nits (all confirmed, none can write a wrong value in the current sources)

1. **Masking and interpolation.** The reviewer's description is overstated.
   - Quotes inside `\( … )` come in pairs, so the masker is back in step by the end of the literal. Only the inner string's content is read as code.
   - My probes with `"\(names.joined(separator: " and "))"` inside a pinned initializer, and with a leaked `[` before a pinned declaration, changed nothing.
   - Fix if wanted: track `\(` depth in non-raw strings.
2. **Clean check.** `git status --porcelain --untracked-files=no` does not see `assume-unchanged` or `skip-worktree` files. Comparing `git hash-object <path>` with `git rev-parse HEAD:<path>` for each path to be written closes that. Optional.
3. **Group prefix.** `(token.group or "").startswith(group)` lets `skip` match `skippedCounts`. In my probe it ended as "2 literals could hold it" and was left, which is safe. Use `token.group == group + "Counts"`.
4. **Self-test.**
   - It leaves its repositories behind. Add `shutil.rmtree(root)` when it passes.
   - Its `git commit` runs a developer's global hooks. Pass `-c core.hooksPath=/dev/null`.
   - Neither affects CI, which uses `$RUNNER_TEMP`.
5. **Write atomicity.** See finding 5.

## Dropped
- Nit 3's "negative or leading-zero literal refuses the whole file" as a defect. The refusal is the right outcome. The real sign problem is the opposite direction, now under finding 2.

## Real-report dry runs
- **eddac9a3d:** 1 pin would be written, exit 0 (the instance for finding 3).
- **cc465388:** exit 1.
  - 6 pins would be written: three seam retention counts, the seam and public-mock fixture hashes, and `seamCorpusValueOracleInspectedGraphCount` 205 -> 189.
  - 1 "(no pin)" draw key left.
  - 4 unknown failures, 1 stale and 7 misfiled seeds listed.
  - Every "would write" line named the literal the source held.