# The generator from a clean slate: how many lines the same features need

Written Sun Nov 15 2026, 10:59 PST (`date`), by a research subagent. Read-only: nothing in the SafeDI repository was edited, built or run. Base: origin/main `247598444` (#708).

**Evidence marks.** **measured** = counted on `247598444` by the two inventories' line classifiers (their totals equal 20,938 exactly). **guess** = my estimate; nothing here was built, so every clean-slate number is a guess anchored on a measured number. Where a guess has a calibration point, it is named.

## 1. The answer

**Yes, it is excessive, and no, 5 to 10% is not the limit.** The first assessment answered a narrower question: how much accidental duplication can go while today's architecture stays. That is 600 to 900 lines (3 to 4%). The question asked now is what the same feature set needs under a design chosen with what we know today. My estimate:

| | Code lines | Change |
|---|---|---|
| Today (`Sources/SafeDICore/Generators`, comments and blanks excluded) | 20,938 (measured) | |
| Clean slate, same Manual feature set | **10,600 to 13,600**, most likely near 12,000 (guess) | **−35% to −50%** |
| What the plans already on the books reach (leak fix, between-releases refactor, 2.3.1 rewrite, mock overrides done as a replacement) | 13,500 to 15,500 (guess) | −25% to −35% |

Two corrections to the number in the question. The directory is 29,442 physical lines, of which 7,317 are comments and 1,187 blank; the code is 20,938. And about 6,000 of those code lines arrived in the six days after 2.3.0-alpha-3 (14,957 → 20,938, measured), almost all for the enum-of-places builder design that the leak fix now replaces.

**The calibration that makes the estimate believable.** At 2.2.0 the whole generator was 6,832 code lines (measured). It already had production trees, mocks with overrides, cycles, `LazilyInstantiated`, erasure and source-ordered diagnostics. Everything since (seams, public mocks, `package`/`internal` access, loops through received instantiators, builders for holes) cost 14,100 lines. The clean-slate estimate says those features should cost 4,000 to 6,500. They are real features with a cross-module contract, so 4,000 is plausible; 14,100 is the price of building them per path, twice (seams and public mocks), beside a second emitter (mocks).

**Where the excess is.** Three design choices, not sloppiness:

1. A seam's builder as an enum of places nested by type: about 4,400 lines plus 500 of diagnostics (measured), built once for seams and again for public mocks.
2. Mock emission as a second emitter: 3,140 lines against production's 1,424 (measured). It mirrors production over a snapshot rather than calling it.
3. Three scope-building worlds (production, the seam world, mocks) and a validation model that mirrors the generator's facts because it runs before the generator exists.

**What is not excess.** Validation and diagnostics are about 6,000 lines today and stay near 4,500 to 5,400. Acceptance rules, source-ordered errors and errors that name their remedy are the product. Only 415 of the 2,127 diagnostic lines hold message text (measured); the rest picks the remedy.

## 2. Estimate per concern

Concerns and today's counts are the second inventory's (they sum to 20,938). Confidence: **M** = anchored on a spike, a prototype or a planned deletion with counted lines; **L** = structural argument only.

| Concern | Today | Clean slate | Conf. | What stays | What disappears |
|---|---|---|---|---|---|
| G. Seam builders (holes, places, fills) | 4,370 | 1,200–1,700 | M | Find holes and sites (~250), each place's fields (~280), builder names for two families, one struct emitter, fills in the caller, fill validation | Cases and payloads, `FillDispatcher` and `RoutePlan` (613), `InnerScopeReaders` (338), nesting by type (723), the dominator graph (422), the second copy for public mocks |
| J. Mock emission | 3,140 | 1,100–1,500 | L–M | Flat parameters and defaults, the overrides and configuration structs (one member model), the parameter tree, flat-label disambiguation | The mock body as its own emitter: `generateMockBodyBindings` (372), `generateInstantiatorBinding` (184), loop members (205), most of `MockParameterNode`'s copied fields (359) |
| A. Validation walks | 2,201 | 1,400–1,800 | L | Every acceptance rule; first error per root by source location | The received-property mirror (396, shared with emission's facts), mock-promoted copies of production checks (~250), per-walk frame boilerplate behind one walker, part of `validateTreeBuiltAgainByCycle` |
| B. Diagnostics | 2,127 | 1,500–1,800 | M | Text, fix-its, remedies, source order | `FillFinding`'s route and case wording (most of 267), parallel seam and public-mock tier errors |
| K. Public mocks | 1,520 | 700–950 | L | Public signature and tiers, public configuration, the foreign call, the callers' view | The second call type, guard hash, tier and omission code; the plan computed three times |
| I. Mock orchestration and promotion | 1,486 | 800–1,050 | L | Promotion in first-receive order, mock-versus-hand-written choice, per-root error collection | The mock scope map rebuilt up to four times, validation walks written for the promoted tree |
| F. Seam signatures and roots | 1,430 | 900–1,150 | L | Signatures settled over cycles of seams, tiers, guard, foreign recomputation | The second "seam world" map and generators (~225), `receivers` as a mirror (117), duplicated SCC and tier code |
| C. Orchestration, imports, files | 1,098 | 950–1,050 | M | Nearly all | Five reachability walks become one |
| E. Generator facts | 876 | 350–500 | M | Received, required, alias and `onlyIfAvailable` facts | Per-path cycle redeclarations, rebinds, three hand-copied initializers (~110) |
| D. Production emission | 772 | 450–600 | M | One function per (type, family) | Three branches that each re-derive name, decorator, parameters and call |
| H. Pre-emission analyses | 706 | 350–450 | M | Sendable captures, tier omissions, fulfillers | The second omission walk (about half of 233 shared) |
| D2. Order, loops, cycle closing | 652 | 400–550 | L | Sibling order and loops (semantics) | Per-path recomputation, the copied SCC |
| N, M, L. Access constructions, warnings, `query needs` | 560 | 500–530 | M | All | Little |
| **Total** | **20,938** | **10,600–13,600** | | | |

The range ends are sums of the per-concern ends. All lows together are unlikely; the middle (11,500 to 13,000) is where I would bet. New shared pieces (one tree walker, one spelling module, one call-kind model) are inside the ranges, about 300 to 500 lines.

**Where this is most likely wrong.**

- **J and I (mocks).** The claim "the mock body is the production emitter with an override hook" has no spike behind it. Spike 3 added shared emission beside the per-path body (347 added, 9 removed), which shows the mechanism works and nothing about deletion. If the hook cannot express promoted roots or flat-parameter rebinding, J stays near 2,000 and the total rises by about 600.
- **A (validation).** Sharing one facts model between validation and emission is an argument, not a design. If it fails, A stays near 2,000 and the total rises by about 400.
- **G.** Best anchored. The leak-fix slices already name the deletions, and the per-type prototype emitted the struct form.

## 3. What each step of the path removes

Net code lines; ranges are guesses.

| Step | Status | Net | What it does to the count |
|---|---|---|---|
| **Leak fix** (slices 2 to 7; seams and public mocks take a builder struct of functions) | In flight, for 2.3.0 | **−700 to −1,200** | Deletes cases, `InnerScopeReaders` (338), `RoutePlan` and the dispatchers (most of 613), route wording in `FillFinding`. Adds struct and level-function emission (~400–600). The enum model stays, because the guard hashes it. |
| **Between-releases refactor** (first assessment's B1–B8; no generated byte changes) | Planned | **−600 to −900** | Shared construction, wrapper and `@Sendable` spelling; one mock-root model; shared seam and public-mock pieces; facts value. Its larger effect is the file split, which makes the next steps reviewable. |
| **2.3.1 emitter rewrite**, production and seam bodies (one function per type and family) | Designed; prototype for shape E | **−1,500 to −2,500** after the old emitter is deleted; **+2,000 to +2,500** while both exist | D, D2 and E shrink; the enum-by-type model (723) and the declaration graph (422) can go once the guard hashes the struct model instead; `validateTreeBuiltAgainByCycle` shrinks. |
| **Mock overrides**, done as a replacement (one configuration model, shared builders, mock body on the production emitter) | Spike 3 exists for storage and shared emission; the replacement is not designed | **−1,800 to −2,500**; done only as spike 3 did it, **+340** | J drops to its essential part; I loses the promoted-tree copies it no longer needs. |
| **One tree model** (validation, seam world and mocks read one set of facts; seams and public mocks are one call kind) | **On no plan** | **−1,500 to −2,500** | The mirror (396), `receivers` (117), the seam world (225), the mock map rebuilds, K's parallel half. |
| **Sum** | | **−6,100 to −9,600** | 20,938 → about 11,300 to 14,800 |

The first four rows are the plans on the books and reach about 13,500 to 15,500. The fifth row is the difference between that and the clean slate, and it is the riskiest row, because it touches which error is reported.

One caution on the fourth row: the mock-overrides work as currently designed is additive. To pay back, its plan must say that the per-path mock body is deleted, with the same oracle discipline as production. Otherwise the generator grows.

## 4. Rewrite the emitter, or refactor step by step?

**Recommendation: a deliberate rewrite of the emitter, and only the emitter. Refactor validation in place.**

**Why a rewrite for emission.** The emitter's size comes from its shape (per path, per route, three branches, a mirrored mock body), and refactors keep the shape. The first assessment already reached this conclusion from the other side: it listed production's three branches, names, argument sources and cycle parameters under "inside 2.3.1's rewrite, do not refactor separately", because refactoring them first is paid twice. The scope is today's D, D2, E, G and J, about 9,800 lines (measured), replaced by about 3,500 to 4,850 (guess, the table's rows).

**Why not for validation.** Validation's outputs are diagnostics: which one, where, with what text. There is no cheap oracle for "the same error is still chosen" beyond the existing exact-text tests and the rename-invariance oracle, and a wrong acceptance decision ships uncompilable code or rejects a working app. Its excess is also smaller (about 600 to 1,000 of 4,300). Shrink it by extracting one walker and one facts model behind the existing tests, one walk at a time, after emission has settled.

**How the rewrite is made safe.**

- **Today's emitter is the oracle.** It stays behind a test-only option until the new one has passed everything, then it is deleted in one pull request. The 2.3.1 design already says this.
- **The oracle is values, not text.** Per-type output is not byte-identical to per-path output, so the comparison is: both compile, and both build the same object graph (the fuzzer's differential value comparator and the retention oracles), over the corpora and long runs.
- **The fuzzer corpora are the net, with a known hole.** They catch what the fuzzer draws. Late defects came from shapes it did not draw yet (CLAUDE.md says so), so each rewrite pull request states which draws exercise its new code, using the fuzzer coverage report on the changed lines.
- **No expectation is reviewed by eye.** Thousands of full `==` expected outputs regenerate (897 test functions contain an internal `SafeDIOverrides` alone, per the slice plan's count). Regenerated expectations are trusted only because each also compiles in the suite and passes the value oracle; the diff is sampled, not read.

**Cost** (guess; in work, not dates).

- About 4,000 to 5,000 new emitter lines and about 10,000 deleted, in roughly six to eight pull requests for production and seams (the per-type plan's shape) and four to six for mocks.
- For that whole period the generator is larger than today by 2,000 to 2,500 lines, and every emission fix lands twice or waits.
- Most of the wall clock is expectation regeneration, CI and the fuzzer's long runs, not writing code.

**Risks, largest first.**

1. **Mocks do not fit.** The mock half rests on an unspiked claim (section 2). Gate: before the production rewrite is committed to, spike the mock body on a per-type emitter for one promoted root with overrides, a loop and a lazy cycle. If it fails, the rewrite still pays for production and seams (about −2,500) but the total stops near 15,000.
2. **Compile time in a real application.** In April, per-type build methods were +5% lines with compile time unchanged, and were then removed in favour of inline. The per-type prototype shows large wins on wide seams (17,120 → 985 lines, `-O` 5.19 → 0.86 s at 24 screens) and the per-type research found the copies are only 7.7% of a lifelike mock body. So the win is on large seams and public mocks, and the standing rule applies: measure runtime and compile cost on adopter-shaped graphs before trading.
3. **Observable changes.** The design already has two: a lazy value at a cycle's closing call is created at first read, and start order in existing seam output can move. Each is a release-note item and needs a ruling before code, not after.
4. **Isolation and `@Sendable`.** One function per type and family doubles the surface where the main-actor-default question (#661, F5) bites. Decide F5 before the rewrite's first emitting pull request.
5. **The oracle retires with the old emitter.** After deletion the net is the corpora alone. Keep the deletion as the last step, after a full corpus run on the dispatched commit.
6. **Two rewrites at once.** The leak fix is rewriting the seam builder now. The emitter rewrite starts after slice 7 and after the between-releases file split, never in parallel with either.

**What I would not do.** A whole-generator rewrite. It discards validation that was paid for shape by shape through fuzzer findings, and it has no oracle for diagnostics.

## 5. What to say to the maintainer

- 20,938 code lines for this feature set is about 40% more than it needs. A clean design lands near 12,000, give or take 1,500.
- The earlier "600 to 900 lines" was the duplication inside today's architecture, not the limit.
- About 6,000 lines of the excess came in six days, for a builder design the leak fix is already replacing.
- The work already planned removes about a quarter to a third. Reaching the clean-slate number needs one more step that is on no plan: one tree model shared by validation, seams and mocks.
- Roughly 5,000 lines are validation and diagnostics, and those are the product.
- The emitter should be rewritten, with today's emitter as the oracle. Validation should not.
- Every number here is an estimate. The one check that would firm up the largest uncertain piece is a spike of the mock body on the per-type emitter.
