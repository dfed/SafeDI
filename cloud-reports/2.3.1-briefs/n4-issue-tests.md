# Brief N4: failing tests for #718, #719 and #720

Read `briefs/common-cloud-lane.md` first; this brief overrides it where they differ. Plan: `plans/2.3.1-plan.md` (items N4, I1–I3). Base: current `origin/main`. Branch: your own `claude/…` branch; it stays a branch (not main, no PR) until the 2.3.1 base stack picks it up. No `Sources/` edits.

**Goal.** Each of #718, #719 and #720 (read the issue bodies; each has a reproduction) gets, on a branch, a test that fails on main for the issue's reason, so that the fix PRs in 2.3.1 start from a red test.

- **#718**: a mock is rejected when a type receives a label only if available and another receives it in another form. 2.3.0 keeps the rejection as a release-noted break; the fuzzer seeds 871, 1095, 1138, 1525, 2598, 2754 and 4311 are known breaks for this reason. Write the handwritten test from the issue's reproduction, expecting the mock to generate and compile with inline's values; record it as a known issue with the issue number. Confirm the seven seeds fail on main for this reason and list each one's failing check.
- **#719**: a dependency labeled `Type` makes the generated mock overrides declare an unescaped member. Test: the mock generates and compiles. Also add a fuzzer roll (a label drawn from Swift's member-declaration reserved words) that fails on main; if a roll needs a generator change in the fuzzer only, keep it additive.
- **#720**: a mock reads a `SafeDIMockConfiguration` that is never generated, for a type built only beneath a repeated ancestor. Test the issue's input: the generated configuration file declares `Gamma.SafeDIMockConfiguration` and the mock compiles. Add a roll for "type built only beneath a cycle edge repeating an ancestor, with a hand-written mock omitting it" that fails on main.

Use `withKnownIssue` (or the suite's own mechanism for recorded known issues) so the branch is green and each test flips to unexpected-pass when fixed. Expected output is whole literals (`.claude/rules/test-design.md`). Full suite once at the end; lint.

**Done when.** Three handwritten tests and their rolls on the branch, each failing on main for the issue's stated reason (quote the failure), the branch green with the known issues recorded, and the seed list for #718.

**Hand-back** as in the common brief.
