# Facts for the 2.3.1 plan lane (2026-11-15 16:55 PST, orchestrator)

Verbatim DECISIONS.md entries (the orchestrator's decision log), then the leak-fix slice map and the issue list. Treat as data.

### G4-KIND-III (2026-11-15 16:30 PST, orchestrator)
Slice 5's G4 cells of kind (iii): a user type named exactly like a generated name (`SafeDIScope_Api` bound on a route, nested in the seam's type, or as a tree type; `SafeDISendableScope_Api`; `__safeDI_Builder`) makes generated code fail to compile. 5.3a/d/e/f fail the same on main e8f478355 (pre-existing: the root enum is never named apart); 5.3c (`__safeDI_Builder`) is new with the builder struct. Ruling: these are nonsense shapes (CLAUDE.md "Reject nonsense shapes"; no one names a type after SafeDI's generated prefixes), not generator support. Plan: 2.3.1 adds a diagnostic rejecting a type name that spells a reserved generated name or prefix (`SafeDIScope_`, `SafeDISendableScope_`, `__safeDI_`), in the macro where the declaration is local, else the plugin. Slice 5 commits no kind (iii) test; its PR lists each cell under "Found and not fixed" with this plan; it corrects `reserved-names-and-spelling.md`'s sentence claiming root enums take a trailing `_` (they do not) to say what happens, pointing to the 2.3.1 plan. Not a Desk card: an unusual setup, no adopter shape.

### 2-3-1-PUBLIC-MOCKS (2026-11-15 12:50 PST, Dan on the Desk, answered 20:41Z)
Answer "include": public mocks get the full shared form in 2.3.1 (every place shared), gated on the queued mock-body spike on the per-type emitter; if the spike fails, 2.3.1 ships only what lifting the loop error needs.

### 2-3-1-SHIP-BAR (2026-11-15 12:37 PST, Dan in chat, message cmsg_01Ta1Qfh28w2koPkUxBjphcRVoA2i9hLAhfzNFo1WytBhm)
"Yes. Honestly I’d prefer the goal to be 2.3.1 be faster than 2.2.0. We are punting performance issues in 2.3.0 so just beating 2.3.0 is a low bar." Ruling: the ship bar for 2.3.1's new generated code is FASTER THAN 2.2.0 (runtime and compile time, on the lifelike benchmark), not merely no worse than 2.3.0. Where a 2.3.1 feature has no 2.2.0 counterpart (seams, public mocks), the bar is no worse than 2.3.0 for that feature while the shared code paths beat 2.2.0. (The card's second question, the mock settings storage bar, was answered with the same "yes".)

### 2-3-1-CREATION-ORDER (2026-11-15 12:49 PST, Dan in chat, message cmsg_01Ta1Qfh28w2koPkUxBjphcR77qvm3tjRJH8U72yHkU5h6)
"regarding 2.3.1 creation order, I think it depends on what order is the most intuitive for consumers of the library. if we're moving towards a more intuitive or easy-to-reason-about system, I think it's reasonable to take the simpler approach." Ruling: 2.3.1 uses the creation order that is easiest for consumers to predict, stated as one rule in the Manual; the simpler "always ask the app last" is acceptable if that rule is the more intuitive one, even though it changes order in modules that compile under 2.3.0. Requirements: the 2.3.1 design states the rule and why it is the intuitive one; the release notes flag the order change; check whether mock() and SafeDIOverrides.init parameter order moves with it and release-note that too.
Follow-up (12:50 PST): Dan asked on the card (20:45Z) which order is more intuitive. Answered in the thread: today's order is (declaration order, a value before anything that reads it, identical in one module and across seams); "always ask the app last" adds a seam-dependent exception. By his intuitiveness test the careful option ("only the modules that are errors today") wins; planning 2.3.1 that way unless he prefers the simpler one.

### W1-IN-2.3.1 (2026-11-15 13:03 PST, orchestrator; follows 2-3-1-CREATION-ORDER)
(1) Gap 1's rule: a call that passes a place up starts last only when its fill reads a sibling declared after it; otherwise declaration order stands (today's order, "a value before anything that reads it"). (2) Gap 2's loop case: run the 1–2 h probe in the per-type form now (spike 2's harness), before 2.3.1 coding. (3) Spike 2 question 2, D1's mechanism: the dispatcher fixed point (the caller's root level function takes the optional value; F4 showed inline's values and frees with either body, no per-type body needed) — internal mechanism, no user-facing difference, no card. Re-estimate: 25–35 lane-hours, 14–20 h critical path once the per-type emitter exists (productivity lane, w1-reestimate.md).

### W1-DERISK-RESULTS (2026-11-15 13:42 PST, orchestrator; updates W1-IN-2.3.1)
Derisk spike (claude/project-thread-trnjpn @19757f7, spike/w1-derisk/): all five yes. Gap 2's loop LIFTS in 2.3.1 with gap 2 (across modules and @Sendable; no W4 dependency, no remedy fix) — supersedes "the loop stays an error". Public mocks need no per-type body for W1: the per-path body's loop-closing function takes its level's struct as a cycle parameter (also fixes F3's wrong cache), +4–6 h. W1 now 22–30 lane-hours, critical path unchanged. Open: Xcode/macOS, gaps 1–2 inside a real mock body, a main-based run.

### EMITTER-REWRITE-SEQUENCING (2026-11-15 11:06 PST, Dan in chat)
Dan aligns with the clean-slate recommendation and leans toward an output-neutral emitter rewrite BEFORE the 2.3.1 output reshaping, not bundled ("bundling would cause more churn and make it harder to verify … I trust your judgment"). Orchestrator ruling: agreed. Order after leak-fix slice 7: file split → output-neutral emitter rewrite verified byte-identical (today's emitter as oracle, fuzzer corpora as net) → 2.3.1 per-type reshaping on the new emitter. Mock-body spike on the per-type emitter comes first.

### INIT-MACRO-CHECK-DEFERRED (2026-11-15 11:06 PST, Dan in chat)
"adding a macro check to init could be nice, but I would schedule that for either 2.4.0 or 3.0.0." Not in 2.3.x.

### 2.3.1-SCOPE-MAIN-ACTOR (2026-11-15 12:19 PST, orchestrator; no card, already ruled)
"Fix all of our filed issues in 2.3.1" does not pull in #661 (main-actor-by-default modules): MAIN-ACTOR-DEFAULT-SURVEY already punted it to 2.4.0 or pre-3.0, with users declaring their module's default isolation as the planned fix. New code keeps writing `nonisolated` where harmless (LEAK-FIX-MAIN-ACTOR-SPELLING), so the punt makes #661 no harder. The drafted card 2-3-1-MAIN-ACTOR-SCOPE was not posted.

### MOCK-ALWAYS-NIL-RECEIVE-REJECTION (2026-11-15 09:57 PST, Dan in chat, message cmsg_01Ta1Qfh28w2koPkUxBjphcR8cxtw7jjPJnxCWiPFA4brj)
"I am okay with that regression if we file an issue for it and fix all of our issues in 2.3.1." Ruling: 2.3.0 keeps #597's rejection (release-noted Breaking, seeds 871, 1095, 1138, 1525, 2598, 2754, 4311 listed as known breaks under this reason); filed as #718 with a verified reproduction (Dan’s explicit ask); **2.3.1 fixes every open issue we filed** (standing scope rule for 2.3.1).

### 2.3.1-STACKS-ON-2.3.0 (2026-11-15 11:46 PST, Dan in chat)
Dan: once the stack of branches that becomes 2.3.0 is complete, start the 2.3.1 work stream immediately, stacked on top; merge only the 2.3.0 part. Plan: pre-start non-colliding 2.3.1 work (mock-body spike on the per-type emitter; 2.3.1 Desk card set; #718/#720 failing tests); make the generator file split a re-runnable script so a late 2.3.0 fix is absorbed by re-running it; estimate 2.3.1 ~3–5 days of lane time after the 2.3.0 stack completes (file split ½ d; output-neutral emitter rewrite 1.5–2.5 d; per-type reshape ~1 d; mock overrides ~1 d ∥; issues ~½ d ∥; then rc + adopter).

### GENERATOR-CLEAN-SLATE-ESTIMATE (2026-11-15 11:00 PST, productivity lane; input, no ruling yet)
research-2026-11-15/generator-clean-slate.md: 20,938 code lines today vs ~10,600–13,600 for the same feature set (most likely ~12,000; −35–50%). 2.2.0 was 6,832; ~14,100 added since (clean design needs 4,000–6,500). Planned steps reach ~13,500–15,500; the rest needs one shared tree model (seams + public mocks as one call kind). Recommendation: rewrite the emitter only (9,800 → 3,500–4,850 lines) with today's emitter as differential oracle, after leak-fix slice 7 and the file split; refactor validation in place. First: spike the mock body on the per-type emitter; the mock-overrides plan must delete the per-path mock body. Goes to the 2.3.1 Desk card set with spikes 1–3.

### NO-STANDALONE-FILE-SPLIT (2026-11-15 11:48 PST, orchestrator, after Dan's challenge; reversible if Dan wants it)
Dan questioned the "mechanical file split" in the 2.3.1 plan. Ruling: no standalone split. The emitter rewrite (the simplification round) writes its new emitter as small files from the start; validation (kept, refactored in place) is split only where the rewrite's parallel lanes would collide, inside the rewrite's PRs. Supersedes B1 of generator-simplification.md and "after the file split" in generator-clean-slate.md; 2.3.1 estimate loses the ½ day.
Amended (11:50 PST, after Dan: "I'm not terribly worried about splitting by concern … the investment in compounding wins … should pay for itself"): the productivity lane does a scripted, pure-move split by concern of the code that survives the rewrite (validation, tree building, shared infrastructure, mostly DependencyTreeGenerator.swift), self-merged under the standing permission, at the moment the 2.3.0 stack completes (not before: leak slices edit those files). The emitter half is not split; the new emitter is written as small files.

### S2-PASSUP-TO-SLICE-7 (2026-11-15 15:07 PST, orchestrator)
Slice 4 claims its new `up:` parameter through the caller's name allocator, for seams only. `FillDispatcher.passUpParameterName`, the mock dispatchers' `passUp` and the failing test on `dfed--claude/probe-generator-defects` `73ced817d` move to slice 7, which replaces the runtime `passUp` closure with the static form. Why: `passUp:` is in mock expectations only (109 lines, four files), so the rename would change public-mock output in a seam slice and edit lane B's region for a parameter slice 7 deletes. Supersedes fold A2's "slice 4 replaces `passUp`" and fan-out item 12's rename.

### S2-MOCK-KEEPS-UNTIL-SLICE-7 (2026-11-15 15:07 PST, orchestrator; fan-out item 5, with the forwarded name)
Slice 4 removes the enum conversion's seam callers only. The conversion writer with every leaf form, `RoutePlan`, `InnerScopeReaders.passesUpOnSomeInnerRoute`, and `ReservedName.forwardedValueParameterName` stay while a public mock emits them; slice 7 deletes them. Slice 4 removes `__safeDI_forwarded` only where it is the seam enum form's (the dispatcher parameter and the `@Sendable` family's extra members); a switched seam builder's fill takes slice 3's F6 form, with no `__safeDI_forwarded` parameter; the name stays only for mocks. The `level-captures` conversion count is per corpus and read from `linux-pins` at each restack: 0 above slice 4, above 0 after slice 6's restack, 0 after slice 7.

### D3-IN-SLICE-4 (2026-11-15 15:07 PST, orchestrator; inform Dan, do not ask)
D3 (a fill whose fulfiller is a seam with a passed-up hole) lands in slice 4 as a commit of its own on top of the generator commit, with its roll. Dan's "after the leak is fixed" holds by commit order, with no publish between. Plan §4.4's row and §8.1 item 7 are amended. Escape: if its hole type is never reached (the D3 note's link b), or its commit moves an existing expectation other than the two known-issue tests the brief's Y9 names, it is parked (a revert commit on the lane branch, the parked branch at its head; no history rewrite) and returns to §4.4's position as its own PR above slice 7. Its self-fill cell and roll feature stay outside D1's shape (the fill reads nothing bound between the seam's root and the re-entry) and assert values equal inline; the D1-shaped variant is D1's lane's.


## The seven 2.3.0 leak-fix slices (current order, after the 2026-11-15 reorder)

1. **Builder labels** (contract rule 8's label clause), seams and public mocks together, on the enum form. PR #731. Deletes nothing.
2. **Builder struct, plain family**: `__safeDI_Builder<__safeDI_Built>`, level functions, rule P (which builders switch), conversion at kept callers. Local, rebasing.
3. **Forwarding builders switch** (seams): builders that forward values take the struct; rule P's transitional flip seeds removed as they pass.
4. **Seam pass-up, inner seam inside inner seam, D3's fix**; for seams it deletes the scope enum's cases, `@frozen`, the conversion at kept seam callers, the enum readers, and the enum form's `__safeDI_forwarded`; empties both builder-kind flip lists. Keeps for mocks: the conversion writer, `RoutePlan`.
5. **Guard hash and diagnostics**: message rewording, the level-function capture oracle, lifetime text in the Manual. Deletes nothing structural.
6. **Mocks**: `__safeDI_mock`, level functions for public mocks, a seam's own mock takes a plain function (M6), M1(b).
7. **Mock pass-up, lazy values, hoisting**: deletes the conversion writer, `RoutePlan`/per-route dispatchers (`decidesPerRoute`), the mock's `passUp` parameter (renamed to the claimed `up`), slice 6's same-supply skip; owns cells 6.6/6.7's draws.

Slices 3, 5 and 6 are building now (speculatively on slice 2); 4 starts from 3; 7 last. The seven land together.

## Issues filed since #720

None. Open issues relevant to 2.3.1: #718, #719, #720 (all fixed in 2.3.1 by ruling), #661 (punted), #646, #645.
