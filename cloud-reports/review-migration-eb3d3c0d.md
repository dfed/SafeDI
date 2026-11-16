# Adjudication: eb3d3c0d (write out expectations, slice 2)

All seven findings hold; none dropped. I raised finding 7 from nit to should-fix and kept the other severities. I checked each against `eb3d3c0d`, its parent `8f0574412` and the next commit `1c27451e5`, read-only. I did not recount the 451 figure, the "38 real switches" figure, the per-file `@Test`/`#expect` counts, or check CI run 43795430677.

Nothing was weakened or lost by any finding below: every comparison is still a full `==`. The one blocking item is a rule breach (a SafeDI-computed value interpolated), not a weaker assertion.

Line numbers are on `eb3d3c0d`. Everything below is still present at `1c27451e5`.

## Findings

### 1. BLOCKING: a guard hash is interpolated into literals this commit wrote
`Tests/SafeDIToolSeamTests/SafeDIToolSeamDeferredParameterTests.swift`, test `generate_takesSendableAutoclosure_whenOuterSeamsSendableFillReadsPassThroughInnerSiteDoesNotCarry`.

- **Guard hash, `:1081` and `:1118`:** `_ = Inner.\(hole.innerGuard).self…`. `PanelHole.innerGuard` (`:1040`) returns `__safeDI_Inner_EAE20455A0945786` or `__safeDI_Inner_6F608818500B54F2`. The rule says a guard hash is "spelled in the literal, never passed in".
- **Code fragment, `:1082` and `:1119`:** `\(hole.outerFill)` (`:1008`) is a multi-line fragment of generated code.
- **Whole file from a property, `:1069`:** `generatedFileHeader + (hole.innerCode)`, so the Feature file is not spelled at the comparison.
- **Origin:** the parent had the same interpolations (`:1078`–`1079`). The commit copied them into its rewritten literals and counts these comparisons as written out.
- **Duplicate literal:** the App literal is written twice, once per integration, although `pluginComment(integration, …)` already varies the one differing line. That misses the commit's own point (5).

**Fix:** switch on `hole` at the comparison. In each case spell the whole Feature file and the whole App file, hash and fill included. Use one App literal per `hole`, with the integration choosing only the key and the seam comment. Then delete `innerCode`, `outerFill` and `innerGuard`; nothing else reads them.

### 2. SHOULD-FIX: the "left as they are" list is incomplete
The commit message presents the `generate_growsLinearly_…` comparison plus fifteen others as everything left (the task text says 2 + 15). The same-line grep behind that count cannot see `dependencyTreeFiles ==`, `file ==`, or expected values built on earlier lines.

Seam comparisons still built by helpers, some with guard hashes passed in:
- **`SafeDIToolSeamDeferredParameterTests:1607, 1642, 1739`:** `Self.rootPassingTokenInstance(toScreenGuardedBy: "__safeDI_Screen_…")`; helper at `:1579`. This is the rule's own counter-example.
- **`SafeDIToolUnreadTypeAccessTests:3473, 3487, 3501, 3576, 3590, 4213`:** `Self.screenFiles(…, assertions:, tiers:, guardHash:)`. The helper at `:6140` joins header, imports, assertions and tiers, and substitutes `{COMMENT}`. `:4213` also uses `Self.packageThemeTiers`.
- **`SafeDIToolSeamOnlyIfAvailableParameterTests:165-166`:** `sessionPassThroughOutput(guardName:)`. The commit did not touch this file.
- **`SafeDIToolSeamHoleCycleParameterFormsTests:103-117`:** `featureFile(…, guardName:)` and `appFile(guardName:…)`. The commit did not touch this file.
- **`SafeDIToolSeamEscapingTypealiasParameterTests:75, 114, 167, 200, 227, 395, 501, 550`:** `file == Self.expectedFile(code:)`. The commit did touch this file.

Fragment assembly:
- `SafeDIToolSeamAccessProofTests:3553, 3595` (`generatedFileHeader + Self.importLines(…) + """`)
- `SafeDIToolSeamHoleLazyInputTests:1470` (`generatedFileHeader + seam + "\n\n" + mock`)
- `SafeDIToolAccessEnforcementTests:879-880, 983-984, 3721, 4150`

`generatedFileHeader + <non-literal>` appears 276 times in `Tests` at the parent, 194 at `eb3d3c0d` and 192 at `1c27451e5`.

**Fix:** either migrate these here, or correct the commit and PR text to say what is left. Build the follow-up list from a search that spans lines: callers of every helper whose body contains `generatedFileHeader`, plus every `generatedFileHeader + [^"]`. The guard-hash-passing sites should go first, since they are the rule's named violation.

### 3. SHOULD-FIX: helpers this commit left dead
Each has zero callers at `eb3d3c0d` and at `1c27451e5`, and none is referenced from another file. The commit message says "Helpers and locals nothing reads any more are deleted."

| File | Line | Helper |
|---|---|---|
| `SafeDIToolSeamHoleLazyInputTests` | 1626 | `generatedFiles(module:integration:imports:rootFiles:)` |
| `SafeDIToolSeamReceivedBuilderCycleTests` | 2245 | `generatedFiles(module:imports:rootFiles:)` |
| `SafeDIToolSeamBuilderParameterTests` | 6909 | `static func generatedFiles(module:integration:imports:rootFiles:)`; its only callers are the two wrappers above (103 references at the parent, 2 now) |
| `SafeDIToolAccessEnforcementTests` | 4982, 4989 | `rootFiles(under:constructing:assertions:)`, and `activeAssertion(_:)`, which only it uses |
| `SafeDIToolSeamAccessProofTests` | 2107 | `generatedFiles(of:sourceFile:_:under:)`; this one also regex-inserts the seam comment |
| `SafeDIToolSeamDeferredCycleParameterTests` | 145 | `appFile(guardName:…)` |
| `SafeDIToolSeamFillImportTests` | 235 | `generatedFile(importing:_:)` |
| `SafeDIToolSeamPlainInitializerOptInTests` | 114 | `appFiles(_:)`; `:331` is an unrelated local |
| `SafeDIToolPublicMockDefaultIsolationTests` | 350, 359, 428, 471 | `screenFiles(integration:)` and the constants only it reads: `screenCombinedFile`, `screenMockFile`, `screenConfigurationFile` |
| `SafeDIToolPublicMockNestedTypeTests` | 1943 | `rootMock(building:ofType:configuredBy:construction:)` |
| `SafeDIToolFulfillerImportTests` | 2374 | `mockFiles(integration:mockedTypeName:importing:_:)` |
| `SafeDIToolModuleMembershipTests` | 818 | `generatedFiles(importing:)` |

**Fix:** delete all of them. After deleting, check again for helpers that only these called (for example `importBlock` and `rootCode(constructing:)` in AccessEnforcement stay, because `:3721` and `:4150` still use them).

### 4. SHOULD-FIX (raised from nit 7): three SendableFill tests interpolate each file's body from the argument enum
`Tests/SafeDIToolSeamTests/SafeDIToolSeamSendableFillTests.swift`:
- `:672` and `:682`: `\(route.hostCode)`, `\(route.rootCode)`
- `:1141` and `:1151`: `\(wrapper.hostCode)`, `\(wrapper.rootCode)`
- `:3270`: `\(nearerDeclaration.hostCode)`

The literal at the comparison holds only the import lines; the body is a multi-line fragment from elsewhere. That is the rule's "assembles expected text from fragments", in comparisons this commit rewrote. It is the same pattern as `hole.outerFill` in finding 1, without a hash passed in, so it is not blocking.

**Fix:** switch on the argument at the comparison between whole literals, and delete the `hostCode`/`rootCode` properties.

### 5. NIT: three switches this commit wrote differ only in the file key
- **`SafeDIToolAccessEnforcementTests:675-730`:** the App literal is repeated per case, though `pluginComment` already depends on the integration.
- **`SafeDIToolAccessEnforcementTests:1163-1262`:** the FeatureImpl literal is repeated per case.
- **`SafeDIToolMultiModuleTests:498-538`:** I diffed the two case bodies; they are identical except for the key.
- **Shared `let`:** the first two also compare `generatedFileHeader + seamCode` / `+ featureCode`, a `let` shared by both cases instead of a literal at the comparison.

**Fix:** let the integration choose only the key (and the comment), with one literal at the comparison.

### 6. NIT: `Self.pluginComment(integration)` is interpolated inside a case that already fixes the integration
`SafeDIToolSeamHoleLazyInputTests:602` and `:635` sit under `case .moduleInfo` (`:588`); `:672` and `:710` sit under `case .swiftPackagePlugin` (`:658`).

**Fix:** spell the comment (or its absence) in each case, or collapse the switch to one literal as in finding 5.

### 7. NIT: `SafeDIToolSeamBuilderParameterTests:1717` is a partial comparison with no comment, and the commit message does not list it
It compares only `Self.seamExtension(in:named: "Flow")` of `Feature.swift`. The expected side is a literal. The rule allows filtered lines to stand in for a whole file only for output of thousands of lines, with a comment saying so.

**Fix:** write out the whole `Feature.swift`, or add the justifying comment and name the site in the "Left as they are" text.

## Agreed, no finding
- `generate_growsLinearly_…` (`SafeDIToolSeamReceivedBuilderCycleTests:2053`) predates this commit and is a size test.
- The fifteen deferred comparisons are the ones `1c27451e5` rewrites.
- Claims (2), (4) and (6) hold as stated. Claim (3) holds for the five named helpers only (finding 3). Claims (1) and (5) hold only in the narrow sense (findings 2 and 5).

My extracted trees for the three commits are in `/private/tmp/claude-501/-Users-dfed-source-SafeDI--claude-worktrees-friendly-northcutt-b8db4d/4b10a5e4-7c24-466e-b50a-83051cce126f/scratchpad/adj` (`par`, `head`, `next`).

---

# Adjudication: review of eb3d3c0d3 (parent 8f0574412), `claude/write-out-expectations-s2`

All seven findings hold; none is dropped and none blocks. Three change severity or wording, and finding 1 grows by seven helpers. I used git show, grep and diff only, and ran no swift. I did not check run 43795430677. The branch head is now 1c27451e5; I say below where it changes a finding.

## Blocking

None. I did not re-derive the reviewer's per-test counts, but nothing I read contradicts them.

## Should-fix (before merge)

**1. Dead helpers left behind — confirmed, and the list is longer.**

The reviewer's seven are confirmed: each is referenced only at its declaration at eb3d3c0d3.
- `SafeDIToolSeamPlainInitializerOptInTests.swift:114` `appFiles(_:)` and `:137` `featureFiles(_:screen:)`. The `featureFiles(userType:)` overload at :52 is still used; keep it.
- `SafeDIToolModuleMembershipTests.swift:818` `generatedFiles(importing:)`.
- `SafeDIToolSeamDeferredCycleParameterTests.swift:145` `appFile(guardName:…)`.
- `SafeDIToolSeamHoleLazyInputTests.swift:1626` and `SafeDIToolSeamReceivedBuilderCycleTests.swift:2245`, the private `generatedFiles(…)` wrappers.
- `SafeDIToolSeamBuilderParameterTests.swift:6909` `static func generatedFiles(module:integration:imports:rootFiles:)`, whose only callers are those two wrappers.

My scan of the head adds seven more, each with zero callers:
- `SafeDIToolAccessEnforcementTests.swift:4982` `rootFiles(under:constructing:assertions:)` (5 callers at the parent).
- `SafeDIToolSeamAccessProofTests.swift:2107` `generatedFiles(of:sourceFile:_:under:)` (6 at the parent).
- `SafeDIToolSeamFillImportTests.swift:235` `generatedFile(importing:_:)` (3 at the parent).
- `SafeDIToolPublicMockDefaultIsolationTests.swift:350` `screenFiles(integration:)` (1 at the parent).
- `SafeDIToolFulfillerImportTests.swift:2765` `mockFiles(integration:mockedTypeName:importing:_:)`, dead since eb3d3c0d3.
- `SafeDIToolFulfillerImportTests.swift:2870` `rootFiles(integration:importing:_:)`, dead since 1c27451e5.
- `SafeDIToolMockEscapingTypealiasParameterTests.swift:1501` `mockFiles(under:…)`, dead since 1c27451e5, whose message says such helpers were deleted.

Two more were already dead at the parent, so they are optional here: `SafeDIToolDependencyTreeGenerationTests.swift:8250` `coreTokenModule` and `SafeDIToolSeamBuiltWrapperTests.swift:2743` `sendableFulfillingType`.

Fix: delete all fourteen, then any helper only they called (check `importLines`/`importBlock` in each file). With 6909, reword the comment at `.claude/skills/regenerate-expectations/regenerate-expectations.py:762`, which says "Keep in step with `SafeDIToolSeamBuilderParameterTests.generatedFiles`".

**2. Claim (1), "every seam test the helper-built grep finds migrated" — confirmed false.**

- A same-line grep still finds `SafeDIToolSeamOnlyIfAvailableParameterTests.swift:165-166`: `sessionPassThroughOutput(guardName: "__safeDI_Screen_…")`, a guard hash passed into a helper. The commit did not touch that file.
- The other sites are confirmed, but the grep cannot see them because the helper call is not on the comparison line. All predate the commit:
  - `SafeDIToolSeamDeferredParameterTests.swift:1579`, called at 1607, 1642 and 1739.
  - `SafeDIToolUnreadTypeAccessTests.swift` `screenFiles(…, guardHash:)` at 3473-3508, 3576-3597, 4213 and 5883; the helper is at 6140. It had 79 references at the parent and has 8 now.
  - `SafeDIToolSeamHoleCycleParameterFormsTests.swift:103-117`.
  - `SafeDIToolModuleInfoViewTests.swift:293` with 1097 and 1113 (still there at the head, at 1114 and 1130).
  - `SafeDIToolSeamBuiltWrapperTests.swift:350-366`.
- `SafeDIToolSeamDeferredParameterTests.swift:1081` and `:1118` are the one place this commit added to the problem. `\(hole.innerGuard)` is a guard hash read from the argument enum's table, and the commit copied it from one site into two new literals.

Fix, in this PR:
- At 1081/1118, switch on `hole` and spell each hash and fill in whole literals; delete `innerGuard` and `outerFill`. Finding 5's fix folds the two branches into one first.
- Spell the hash at the three `rootPassingTokenInstance` sites and at OnlyIfAvailable 165-166.
- Either migrate the rest or reword the claim to "every seam comparison whose own line calls a helper, except …" and list them for the follow-up.

**3. The helper-built count is understated — confirmed; this is about the commit and PR text.**

- My same-line grep (`generatedFiles`/`dependencyTreeFiles`/`mockFiles ==` or `expectGeneratedFiles(` with `Self.x(`/`…Tests.x(`) gives 347 at the parent, 22 at eb3d3c0d3 and 7 at the head.
- The 22 include lines the "17" omits: `SafeDIToolLazyCycleReadLabelTests.swift:225` and `:305`, `SafeDIToolMockReceivedBuilderCycleTests.swift:768`, and OnlyIfAvailable 165-166.
- The sites the reviewer says the grep cannot see are confirmed present:
  - `SafeDIToolGeneratedAttributesTests.swift:443-455`.
  - `SafeDIToolDependencyTreeGenerationTests.swift:4668-4680` (`<COMMENT>` and `<DETAIL-PATH>` filled by `replacingOccurrences`).
  - `SafeDIToolMultiModuleTests.swift:577`.
  - `SafeDIToolImportAccessLevelTests.swift`: 20 remaining `Self.file(importing:bodies:)` calls.
  - `SafeDIToolSeamDeferredCycleParameterTests.swift:181`, read at 632 and 793.
  - `SafeDIToolSeamEscapingTypealiasParameterTests.swift`: 8 × `expectedFile(code:)`.
  - `SafeDIToolSeamPlainInitializerOptInTests.swift:200`.

Fix: state the numbers as "same-line helper calls" and give the grep. Build the follow-up list from a scan that also follows locals assigned before the comparison, shared constants, and `file ==` comparisons.

## Nit (follow-up is fine)

**4. `SafeDIToolSeamBuilderParameterTests.swift:1717` — confirmed, downgraded from should-fix.**

- It compares only `seamExtension(in:named: "Flow")`, the first `extension Flow { … }` of `Feature.swift`, with no comment saying why.
- Downgraded because it is byte-for-byte the parent's comparison (parent line 1585) and the commit message declares it kept. The rule's exception does not cover it, so it belongs on the follow-up list with the others.
- Fix: compare `output.modules["Feature"]?.generatedFiles == ["Feature.swift": …]` in full. That needs the file's text from a run, so it cannot be done from git alone.
- `generate_growsLinearly` (`SafeDIToolSeamReceivedBuilderCycleTests.swift:2053`) is justified by its comment at 2035-2037.

**5. `SafeDIToolMultiModuleTests.swift:498-539` — confirmed.**

The two 18-line cases, added by this commit, differ only in the key. Fix: one literal, with the key `integration == .moduleInfo ? "App.swift" : "Root+SafeDI.swift"`. `\(carPath)` stays, since it is a checkout path.

**6. File bodies taken from argument-enum properties — confirmed.**

- `SafeDIToolSeamSendableFillTests.swift` 672/682, 1141/1151 and 3270: header and imports at the comparison, body in `hostCode`/`rootCode`.
- One more site of the same kind: `SafeDIToolSeamDeferredParameterTests.swift:1068`, `generatedFileHeader + (hole.innerCode)`.
- Nothing is weakened: the parent passed the same properties to `expectGeneratedCode`.
- Fix: have each property return the whole file, or switch on the argument at the comparison.

**7. Integration comment helper inside a branch that already fixes the integration — confirmed.**

- `SafeDIToolSeamDeferredParameterTests.swift:1081` and `:1118` sit inside `integration == .moduleInfo ? … : …`.
- `Self.pluginComment(integration)` in `SafeDIToolSeamHoleLazyInputTests` went from 13 to 15 uses.
- Fix: where the branches differ only in key and comment, fold them into one literal, which makes the interpolation legitimate. Otherwise spell the comment in each branch.

## Net

Before merge: finding 1 (delete fourteen helpers and fix the script comment), the sites this commit wrote or already passes spelled hashes to in finding 2, and the claim and count wording in findings 2 and 3. Findings 4 to 7 can go on the follow-up list.
