# Adjudication: 5e6b082b (retention oracle "after a call" experiment)

All findings survive: two blocking, two should-fix, two nits. I verified each by reading the code at 5e6b082b; I ran no swift and no corpus, so every "will fail" below is a reading, not an observed failure.

| Finding | Verdict | Final severity |
|---|---|---|
| B1 existing comparator test not updated | Confirmed | Blocking |
| B2 leak signatures miss the "after a call" twins | Confirmed (mechanism); the twin list itself must come from CI | Blocking |
| S1 hand mutation and seed not recorded | Confirmed, fix text narrowed | Should-fix |
| S2 per-shard cost unmeasured | Confirmed | Should-fix |
| N1 stale doc comments | Confirmed | Nit |
| N2 rules wording | Confirmed | Nit |
| Pins and counts note | Correct, no action beyond confirming in the corpus run | Not a finding |

## Blocking

### B1. `compare_reportsWhatTheFeaturePathKeepsAlive_whenItsInstantiatorCapturesAnInstanceTheKnownRightPathDoesNot` now gets four differences, and expects two

- **Location:** `Tests/SafeDIToolFuzzerTests/DifferentialValueComparatorTests.swift:523-534`; fixture `builderCapturingB` at 3045-3049.
- **Why it fails:**
  - `Root.bBuilder` is an `Instantiator` with no forwarded properties, so its traversal is `.instantiate` and `isCalled` is true. It gets the `bBuilder after a call` experiment.
  - On the feature path the closure captures the root's `b` through `withExtendedLifetime(b)`. `collectWeaklyHeldObjects` does not see into a closure, so with only the instantiator held, `b` and its `C` are alive and not reached: B (1), C (1).
  - On the known-right path the closure captures only `a`, so B and C count 0. `A` is 1 on both paths, so it is no difference.
  - `judgment` appends differences in the feature path's experiment order (nothing, `bBuilder`, `bBuilder after a call`, `lazyB`), then by type name.
- **Fix:** replace the expectation and its comment with:

```swift
		// The feature path's builder holds the root's `b`, which the known-right path's does not, as a seam's builder function
		// holds its levels' values: once the root is released, holding the builder keeps `b` and its `C` alive on the feature
		// path only, both with what one call of it builds and alone once that is released. The values the two paths build agree.
		...
		#expect(comparison?.retentionDifferences.map(\.description) == [
			"probe `Root()` keeps B alive holding bBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
			"probe `Root()` keeps C alive holding bBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
			"probe `Root()` keeps B alive holding bBuilder after a call once the probe's value is released: 1 on the feature path, 0 on the known-right path",
			"probe `Root()` keeps C alive holding bBuilder after a call once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		])
```

- Then run `DifferentialValueComparatorTests` with compile verification on CI (`verify.yml -f filter=DifferentialValueComparatorTests`). No other retention expectation in that file changes: the remaining ones expect `[]`, or are the 2→4 count already updated.

### B2. No known-issue retention signature matches an "after a call" difference

- **Location:** `Tests/SafeDIToolTestSupport/GraphFuzzer.swift` around 10622-10645 (`matches`, `allSatisfy` over `difference.contains(text)`); signature lists in `Tests/SafeDIToolFuzzerTests/SafeDIToolGraphFuzzerTests.swift`:
  - `inSeamLeakSignatures` (6238)
  - `handWrittenBuilderRetentionSignature` (6425)
  - `combinationInSeamLeakSignatures` (6563)
  - the public mock combination entries (about 6647)
  - `publicMockLeakSignatures` (7051)
- **Why it fails:**
  - Every signature spells `alive holding <labels> once the probe's value is released: 1 on …`. A twin reads `… holding <labels> after a call once …`, which contains none of them.
  - A twin appears wherever the held wrapper is `.instantiate` and what leaks is held by the closure, not by what the call built. That is the documented in-seam leak. Dropping the built value from `held` can only raise the kept-alive count, and the known-right path's closure still does not capture the level value.
  - Because matching is `allSatisfy`, one unmatched twin turns a documented seed into an unknown failure.
  - Seam smoke seed 68 is in both `seamSmokeSeeds` (5696) and the in-seam leak issue (6072), so `seamSmokeSeeds_produceNoUnknownFailures_whenRunThroughToolAndCompiler` should fail too, wherever compile verification runs.
- **What gets no twin:**
  - Labels that name a `LazilyInstantiated` (`.readInstanceLast`), such as `holeTangleC`, `holeHost`, `cycle1A`.
  - `ErasedInstantiator` and `SendableErasedInstantiator` (`.notTraversed`).
  - Instantiators whose forwarded properties have no registered sample.
  - So do not twin the lists mechanically as the final state. A twin that never occurs is dead text that no check reports, and "as the corpus run observed" would be false.
- **Fix:** in this PR, before it is marked ready:
  - Run the four corpora and the seam smoke batch on CI.
  - Add to each list exactly the `… holding <labels> after a call once the probe's value is released: <n> on the feature path, <m> on the known-right path` lines the reports show.
  - Give any type that only the new experiment reports (an instance both the builder and the built value hold) a known-issue entry with a reason, or fix it.
  - Confirm that all four `retention` pin lines are unchanged and that no `stale` line appears.
  - Say in the PR body that every leak list moved and why.

## Should-fix

### S1. The extension has not been shown to fire on a generated graph for the half it adds

- **Rule:** `.claude/rules/fuzzer-corpora.md`, "A new oracle shows it fires". The commit extends an oracle rather than adding one, but the rule's reason ("an oracle that has never failed may be unable to") applies to the new experiment.
- **What exists:** the new unit test (`Unmanaged.passRetained`) shows the comparator half fires on a hand-written fixture. Nothing shows it on a generated graph, and the commit names no seed.
- **Fix:** in the PR body, record one of these.
  - (a) A seed from B2's corpus run whose graph has a type only an `after a call` experiment reports, with no plain twin at the same labels.
  - (b) If the corpus shows none, a hand mutation of the generator and the seed that fails only in `after a call` under it, with the note that 53955a7de's oracle passes that mutated build.
- The reviewer's suggested mutation (hoisting a `LazilyInstantiated` out of an instantiator's closure) is unverified, and the value oracle may catch it first through `instantiate() again` marks. Treat it as a candidate, not as the fix text.

### S2. Cost per shard is unmeasured

- **Location:** `DifferentialValueComparator.swift:1265-1275`. Each `.instantiate` wrapper now runs two experiments, so a probe runs up to 1 + 2×24 = 49 instead of 25. All of them run inside the `alarm(probeTimeLimitInSeconds)` that `describe(probe:)` sets, and each does a fresh `make()`, a `retentionTargets` walk and a builder call.
- **Fix:** from B2's corpus run, put the per-corpus wall seconds and `cpu` lines (the retention and describe phases) beside 53955a7de's in the PR body. Confirm that no probe hits the alarm, in particular `Corpus.seedsTraversingPastTheBatchBudget` (seam seed 391). If a step's duration grows materially, re-measure its `timeout-minutes` comment.

## Nits

### N1. Stale doc comments in `Tests/SafeDIToolTestSupport/DifferentialValueComparator.swift`

- **Line 1248.** Replace with: `/// How many of the wrappers a probe's value holds `describeRetention(of:)` holds at most, each in one experiment, or two where an experiment calls it.`
- **Lines 418-420** (`DifferentialValueRetentionDifference`). Replace "`nothing`, or the wrapper the labels name, with what one call of it builds" with: "`nothing`, the wrapper the labels name with what one call of it builds or its instance, or (`<labels> after a call`) an instantiator alone once what one call of it built is released".
- **Line 1259** (doc of `describeRetention`). The first sentence can stay; the added sentence already covers the new experiment.

### N2. `.claude/rules/fuzzer-gating-checks.md:18`

- "holds an instantiator once more alone" is too broad: only an instantiator the describer calls gets the experiment.
- The sentence now has three en-dash breaks and is hard to parse.
- **Fix:** restore the original clause (`… – holds that wrapper with what one call of it builds, or its instance, releases the value, and prints …`) and add a sentence of its own after that sentence:

> An instantiator the describer calls (an `Instantiator` or `SendableInstantiator` with no forwarded properties or a registered sample; never an erased one) gets a second experiment, `<labels> after a call`, which calls it, releases what the call built, and holds the instantiator alone, so that an instance the call keeps alive that what it built also holds counts as kept alive.

## Pins and counts

The reviewer's note is correct. `pairedWrapperExperimentCount` is not pinned per corpus. `unpairedExperiments` stays 0 because `isCalled` depends only on the wrapper type and the registered samples, which are the same on both paths. The judged counts count graphs, not experiments. Confirm this in the B2 run. When the comboId sample for public mock cell 18 lands, expect more twins in the public mock combination list, not new pins.


---

# Adjudication: review of 5e6b082b ("Hold a called instantiator alone in the retention oracle's experiments")

Verified by reading the code at 5e6b082b only (`git show`); nothing was built or run, so the two blocking findings are static predictions, not observed failures.

| # | Finding | Verdict | Final severity |
|---|---|---|---|
| 1 | Existing capture test now gets four differences | Confirmed | **Blocking** |
| 2 | Exact-text leak signatures miss the `after a call` differences | Confirmed, scope narrowed | **Blocking** |
| 3 | No evidence the extension fires on generated code | Confirmed | **Should-fix** |
| 4 | Rule text claims a masking property the new experiment lacks | Partly wrong; the clause is still literally true | **Nit** (downgraded) |
| 5 | "An instantiator" should be "an instantiator the experiment calls" | Wording point stands; its supporting claim is wrong | **Nit**, corrected |
| 6 | Experiments per probe go from 25 to 49 | Confirmed | **Nit** |

No finding is dropped outright. The reviewer's "checked and found sound" list holds on my reading too (pairing, determinism, unchanged failure kinds, the new test is not tautological, the 2 → 4 count is right).

## Blocking

### 1. `compare_reportsWhatTheFeaturePathKeepsAlive_whenItsInstantiatorCapturesAnInstanceTheKnownRightPathDoesNot` now gets four differences

Location: `Tests/SafeDIToolFuzzerTests/DifferentialValueComparatorTests.swift:523-534`.

Evidence:
- `graphFixture` (line 2863) declares `B: Instantiable` with no `ForwardedProperties`, so `instantiatorTraversal` takes the `() as? ForwardedProperties` branch and returns `.instantiate`. `isCalled` is true and `bBuilder after a call` runs on both paths.
- Under `builderCapturingB` (line 3045) the feature closure captures the root's `b`. In the new experiment only the wrapper is held, and the walk does not follow closures, so the root's `B` and its `C` count 1 each.
- On the known-right path the closure captures only `a`, so `B` and `C` count 0. `A` counts 1 on both paths and is no difference.
- `DifferentialValueRetention.judgment` orders by the feature path's experiments, then type name. That gives `bBuilder` B, C, then `bBuilder after a call` B, C. `lazyB` adds nothing.

Fix — replace the comment and expectation:

```swift
		// The feature path's builder holds the root's `b`, which the known-right path's does not, as a seam's builder function
		// holds its levels' values: once the root is released, holding the builder keeps `b` and its `C` alive on the feature
		// path only, with what one call of it builds and alone after a call alike. The values the two paths build agree.
		...
		#expect(comparison?.retentionDifferences.map(\.description) == [
			"probe `Root()` keeps B alive holding bBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
			"probe `Root()` keeps C alive holding bBuilder once the probe's value is released: 1 on the feature path, 0 on the known-right path",
			"probe `Root()` keeps B alive holding bBuilder after a call once the probe's value is released: 1 on the feature path, 0 on the known-right path",
			"probe `Root()` keeps C alive holding bBuilder after a call once the probe's value is released: 1 on the feature path, 0 on the known-right path",
		])
```

### 2. Leak signatures do not match the `after a call` differences

Location: `Tests/SafeDIToolFuzzerTests/SafeDIToolGraphFuzzerTests.swift` — `inSeamLeakSignatures` (6238), `handWrittenBuilderRetentionSignature` (6425), `combinationInSeamLeakSignatures` (6563), the public mock combination list (~6646), `publicMockLeakSignatures` (7051).

Evidence:
- Every signature spells `"… holding <labels> once the probe's value is released: …"`. That text is not a substring of `"… holding <labels> after a call once the probe's value is released: …"`.
- Matching needs every difference to match a signature (`GraphFuzzer.swift:10625-10643`, `allSatisfy` + `difference.contains(text)`).
- A leak a called instantiator shows in its base experiment shows again in `after a call`. The kept-alive instance is reached from the probe's value, so it is in `objects`, and dropping `built` from `held` cannot free what the wrapper's closure captures.
- The regular suite is affected. `seamSmokeSeeds` (5696) holds 1_450, which `seamSmokeKnownIssuesBeyondTheCorpus` documents with `inSeamLeakSignatures + [handWrittenBuilderRetentionSignature]`. `retainDetailBuilder` is `Instantiator<RetainDetail>` or its `Sendable` form with nothing forwarded (`GraphFuzzer.swift:7273`), so it is called. `seamSmokeSeeds_produceNoUnknownFailures_whenRunThroughToolAndCompiler` should then record an undocumented failure for 1_450, and likely for 68 and 151.

Narrowing the reviewer's scope: not every listed signature gains a twin. A wrapper gets the new experiment only when `wrapperTraversal` is `.instantiate`:
- `ErasedInstantiator` and `SendableErasedInstantiator` are always `.notTraversed` (comparator lines 1144-1154), so `holeTicketBuilder` gets none.
- `LazilyInstantiated` wrappers and by-value labels (`holeTangleC`, `holeHost`, `cycle1A`) get none.
- An instantiator that forwards a value gets one only where a sample is registered.

Only CI's output can give the set, including any new type that appears only in `after a call` (an instance the base experiment excluded because what was built reached it).

Fix:
- Run the seam, public mock and both combination corpora plus the smoke batches on this commit through CI.
- Add each observed `after a call` line as its own entry in the list that holds its base line, with the observed counts, in this same pull request. Do not loosen an existing signature to a prefix: the signature's rule is that it names type, labels and both counts.
- Re-check the pins. Each `…RetentionCounts(… unpairedExperiments: 0)` (5560, 5563, 6510, 6622) should stay 0, since an `after a call` experiment pairs whenever its base does; copy what CI prints.
- `staleLeakEntry` needs no code change. It judges whether the entry's leak is still found, and a fix removes base and `after a call` lines together. Confirm it on the corpus run.

## Should-fix

### 3. Nothing shows the extension fires on generated code

`fuzzer-corpora.md` ("A new oracle shows it fires") and CLAUDE.md ("a new oracle names the seed a hand mutation makes fail") apply: the experiment sees a class of leak the oracle could not see before. The only evidence is the unit test's hand-written `Unmanaged.passRetained`.

Fix — add to the pull request description, after trying it:

> Hand mutation: in a seam's builder function for an instantiator's place, keep what the function builds in a variable the function captures (`var last: T?` declared beside it, assigned before `return`). Seed N of the seam corpus then fails `seamRetainsWhatInlineFrees` with only `… holding <labels> after a call …` lines, and passes without the mutation.

The mutation must be one where what was built also holds the leaked instance. Otherwise the base experiment already catches it and the seed proves nothing about the extension.

## Nits

### 4. The rule's "held value" clause (downgraded from should-fix)

The clause "so that a held value holding more instances on one path, a value difference, keeps no more alive" is still true. In `after a call` no built value is held, and one that holds more instances is released, so its extras are freed and uncounted.

What does change: an instance the call keeps alive that what was built also holds was "held" before and is counted now. A graph whose only failure was a value difference of that kind (the seam shares a captured instance where inline builds a fresh one) can now also fail retention. That is intended and is a real leak under rule 3. It is a wording gap, and the finding 2 corpus run will show whether any known value-difference seed gains a retention failure.

Fix — fold into the rewrite under finding 5.

### 5. Say which instantiators get the experiment, and unknot the sentence

The wording point stands: only `.instantiate` traversals get `after a call`.

The reviewer's supporting claim is wrong. Both corpora register samples:
- Seam: `holeDrawForwardedPropertiesSamples + forwardedLabelAcrossSeamCallSamples` (`GraphFuzzer.swift:11766`).
- Public mock: `placeInFillInnerScreenSamples + combinationForwardedValueSamples` (`GraphFuzzerPublicMocks.swift:2353`).

So those forwarding instantiators are called. Never called are erased instantiators and forwarding instantiators without a sample — which is where the pending public mock cell 18 `comboId` sample belongs.

Fix for `.claude/rules/fuzzer-gating-checks.md:18` — replace from "– holds that wrapper with what one call of it builds, or its instance – and holds an instantiator once more alone …" through "… keeps no more alive;" with:

> – holds that wrapper with what one call of it builds, or its instance, releases the value, and prints how many class instances of each type that the value and what is held hold through stored properties are still alive though what is held does not reach them through stored properties (`retained holding <labels>: <Type> (2); …`, `DifferentialValueRetention`), so that a held value holding more instances on one path, a value difference, keeps no more alive. An instantiator the experiment calls (one that forwards nothing, or whose forwarded value has a registered sample; never an erased instantiator) gets one more experiment, `<labels> after a call`, which holds the instantiator alone once what the call built is released, so that an instance the call keeps alive and what it built holds is counted too: there nothing built is held, so such an instance counts on the path that keeps it even where the paths' values differ;

Matching doc-comment fixes in `Tests/SafeDIToolTestSupport/DifferentialValueComparator.swift`:
- Line ~1262: "An instantiator is also held alone" → "An instantiator the experiment calls is also held alone".
- `DifferentialValueRetentionDifference` (~line 418): "or the wrapper the labels name, with what one call of it builds" → "or the wrapper the labels name, with what one call of it builds or, `after a call`, alone".

### 6. Experiments per probe nearly double (≤25 → ≤49)

Confirmed: 1 + 24 base experiments, plus up to 24 more. Each rebuilds the probe's value under the same per-probe `alarm` (60 s, 300 s isolated).

Fix: on the first corpus run, compare each fuzzer shard's duration with its `timeout-minutes` and update the measurements comment beside it if the margin fell below about 2×. No code change.

## Files read

- `~/source/SafeDI/Tests/SafeDIToolTestSupport/DifferentialValueComparator.swift`
- `~/source/SafeDI/Tests/SafeDIToolFuzzerTests/DifferentialValueComparatorTests.swift`
- `~/source/SafeDI/Tests/SafeDIToolFuzzerTests/SafeDIToolGraphFuzzerTests.swift`
- `~/source/SafeDI/Tests/SafeDIToolTestSupport/GraphFuzzer.swift`
- `~/source/SafeDI/Tests/SafeDIToolTestSupport/GraphFuzzerPublicMocks.swift`
- `~/source/SafeDI/.claude/rules/fuzzer-gating-checks.md`
- `~/source/SafeDI/.claude/rules/fuzzer-corpora.md`