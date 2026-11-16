Adjudication of the two reviews of `origin/claude/project-thread-i43ot8:release-notes/2.3.0-draft.md` @ 8e456efe. Checked against tag 2.2.0, origin/main (a6d44aff6), the PR bodies and main's `Documentation/Manual.md`. No swift was run, so "2.2.0 compiled this" claims rest on PR text and the 2.2.0 sources; the two that need a 2.2.0 `SafeDITool generate` run are marked.

Line numbers are the draft's. New breaking items are appended as 12 and 13 so existing item references keep their numbers.

## Blocking

- **1. "Builder labels" (L67–69) and its pointer on L10 describe #731, which is not on main.** Both reviews; confirmed.
  - #731 is OPEN with base `dfed--claude/check-6-release-acceptance`.
  - Main's Manual (L835, L847) names a builder for its type (`userServiceBuilder`). It adds the returned type only on a collision (`impl_ServiceBuilder` beside `impl_AnyServiceBuilder`).
  - Fix: replace L67–69 with `<!-- BUILDER LABELS (#731): one entry, under the seams section, when #731 lands on main with its Manual change. -->`.
  - Fix: delete the last sentence of L10, "How builders are labeled is under “Builder labels” below."

- **2. Breaking changes omit the lazy-cycle graphs 2.2.0 compiled and main rejects.** Both reviews; confirmed for #639, probable for #533.
  - #639's body: "These shapes compile on 2.2.0, where the type built again read the wrong copy."
  - #533 adds `validateTreeBuiltAgainByCycle` (hidden-label and dependency-cycle errors for the tree built again). #621 says of that check: "arrived in the 2.3.0 alphas: 2.2.0 does not have it."
  - Not run: confirm the #533 half with 2.2.0's `generate` on #533's M9, M10 and M12 cells. If it does not hold, drop the first sentence of the item and cite #639 only.
  - Fix: add item 12:
    > 12. **One label in two forms inside a lazy cycle.** A type a lazy instantiator cycle builds again receives each label from the nearest declaration above it. So a scope between the cycle’s two ends that declares the label in another form is now the hidden-label error, and a required receive whose nearest declaration is still being built is a dependency-cycle error. Forms of one label that no one value can carry are an error too: `x: X?` beside `x: Instantiator<X>?`, or a `LazilyInstantiated<X>` beside its own `X`. 2.2.0 compiled these and passed the declaration from above the cycle. Receive the forms under different labels (#533, #639).
  - Fix: append " See Breaking changes." to L85.

- **3. Performance presents as gains work that only recovers cost added after 2.2.0.** Review 2's B2 and review 1's S3; confirmed. Blocking because it breaks the stable-relative rule.
  - L79: #596 is measured "relative to the stack just before #585". #663 trims a check #519 added. #665 says 62M instructions "where SafeDI 2.2.0’s normalization cost about 1.3 million". #681 says `generate` "still executes about 19% more instructions than 2.2.0".
  - L78: #680 says "scan still uses about 6% more CPU and wall time than 2.2.0".
  - #668 is a real gain: 2.2.0's `BinaryCoding` used `String(reflecting:)`.
  - L77: #635's 88% and 20% are against its parent, where `SafeDICore` was far larger than 2.2.0's 17,199 lines. 2.2.0 also compiled all of `SafeDICore` into the macro, so the direction holds but the figures do not.
  - Fix: delete L79.
  - Fix: L78 becomes "Writing and reading `.safedi` files and the scan cache no longer reflects over their types at run time, which was most of a small module’s `generate` under Bazel or Tuist (#668)."
  - Fix: L77 becomes "The macro plugin compiles only the parts of `SafeDICore` the macros use, so the macro module builds faster and the plugin binary is smaller (#635)." Add figures only if re-measured against 2.2.0.
  - Optional: move L55 (rewrite only on change, #577) here, as review 2 suggests.

## Should-fix

- **4. #519's user-visible changes are missing.** Both reviews; confirmed. 2.2.0 has the `errors.sorted().first!` trap at `InstantiableMacro.swift:2020` and the label-keyed `Dictionary(uniqueKeysWithValues:)` at `ScopeGenerator.swift:2451` and `:4373`.
  - Fix: add under "Errors SafeDI now reports":
    > - An `instantiate(…)` parameter without a default value that is named `_`, with a fix-it that names it after its label where the label can name it; and two names in one declaration that look the same but are encoded differently, such as `café` written with U+00E9 and with `e` followed by U+0301 (#519). See Breaking changes.
  - Fix: add item 13:
    > 13. **`_` and differently encoded names.** The macro rejects an `instantiate(…)` parameter without a default value named `_`, and two names SafeDI matches in one declaration that differ only in encoding. These compiled only where no tree built the type. Name the parameter, and spell both names the same way (#519).
  - Fix: add under Fixes > Generated code:
    > - `generate` reports a declaration that repeats a dependency label with an error at the declaration: two `instantiate(…)` parameters named `_`, names encoded differently, or one dependency declared in each clause of an `#if` only the compiler decides, such as `#if os(iOS)`. 2.2.0 crashed or generated code that did not compile. Declare such a dependency once, outside the `#if` (#519).
    > - The macro no longer crashes on an initializer or hand-written mock with two problems no fix-it addresses, such as `public init() async throws {}` (#519).

- **5. L163's exception list leaves out item 4.** Both reviews; confirmed. #572's release note says of the cycle-error shape "which 2.2.0 passed it".
  - Fix: "A graph SafeDI now rejects did not compile before, except the shapes in items 2, 3, 4, 5, 6, 8, 9, 10, 12 and 13."
  - Review 2's proposed remedy for item 4 is not verified against #572's tests. Add a remedy only after checking one there.

- **6. L182 credits the macro with `generate`'s errors.** Both reviews; confirmed. `validateAdditionalMocksToGenerate` is called at `GenerateCommand.swift:588–595`, and item 2 itself says `generate` rejects the `#if` chain.
  - Fix: "**Macro errors.** The macro reports items 5, 9, 10 and 13, and item 2’s renames on one declaration, as you type, each with a fix-it where one is safe. `generate` reports item 3, item 2’s `#if` chains and item 12 at build time."

- **7. L9 overstates what breaks a hand-written seam call, and misstates what the seam keeps.** Both reviews, plus review 1's N1; confirmed by Manual L785 and L827–829.
  - Fix: replace from "which takes every parameter…" to the end of the bullet with: "which takes every parameter as a plain value and keeps nothing of the caller but the builders for its holes (#615, #631). No parameter has a default, so a hand-written call stops compiling when the seam’s tree starts to receive another dependency the initializer it calls takes. A new parameter narrower than the seam goes on a narrower initializer, and the wider one passes `nil` for it (#561, #611)."

- **8. Bazel adopters are not told their dependency graph moves, and L118 misnames a module.** Review 2's S5; confirmed by the `MODULE.bazel` diff and #599's own release note. The registry module is `swift_argument_parser`.
  - Fix: L118's last sentence becomes "SafeDI depends on the Bazel Central Registry’s `swift-syntax` and `swift_argument_parser` modules instead of rules_swift_package_manager (#599)."
  - Fix: add to Upgrading:
    > - **Bazel.** Your graph now resolves at least `rules_swift` 3.6.1, `apple_support` 2.5.4 and `rules_apple` 4.5.0. Raise the versions your `MODULE.bazel` declares to match, or Bazel warns that it declares lower ones (#599).

- **9. L53 contradicts L52 and the Manual under Bazel.** Review 1's S6; confirmed by the "Which modules to list" table (Manual L1649–1656).
  - Fix: second sentence becomes "Under Tuist and in a custom build, a module that declares a root still lists every module beneath it; under all three, a mock builds only the types of the modules its run reads (#577, #581, #610)."

- **10. L24 leaves out Xcode projects.** Both reviews; confirmed by Manual L98 and L1408.
  - Fix: "SwiftPM passes it. In an Xcode project, and under Tuist, set `SWIFT_PACKAGE_NAME` to one name on every target; under Bazel, `package_name` on `safedi_swift_library`; in a custom build, `generate --package-name` (#567, #574, #647)."

- **11. Performance says nothing of shapes still slower than 2.2.0.** Review 1's S8; confirmed.
  - #621: dense lazy cycles are 1.5x to 2.2x 2.2.0. #638: the redeclared-value shape is about 2.5x. #681: `generate` is about 19% more instructions on the 15-module app. #680: `scan` is about 6% more.
  - Wording is the maintainer's call: the rules want a linked issue, and filing one needs his ask.
  - Fix now: extend L75's placeholder to "…measured after the leak stack lands; include the dense lazy-cycle and redeclared-value shapes (#621, #638), and link an issue for any shape still slower than 2.2.0."

- **12. L131 promises SafeDI 3.0.** Both reviews; confirmed as a rule conflict. The shipped text says the same (`GenerateCommand.swift:39`, `:47`, `:826`; `InjectableMacro.swift:372`; Manual L376), so this needs the maintainer's ruling.
  - Default fix: "Each still works and now warns; the warning names what replaces it (#558):"

- **13. Item 3's remedy (L149) reads as two alternatives, one of which keeps the error.** Review 2's S4; confirmed. #557 says a fake whose method is named `mock` "already was" an error.
  - Fix: "Remove the entry, and call the fake’s own method or rename it `mock` (#557)."
  - Review 2's extra sentence about a production declaration in another module is not verified; leave it out.

- **14. Every HTML comment is visible in the raw release body.** Review 2's S7; valid, since `gh release view` and the API print them.
  - L103 and L105 are evidence, not placeholders. Move them to an evidence file beside the draft and delete them here.
  - Before publishing, `grep -c '<!--'` on the body must return 0.

- **15. L184 misses the one new warning.** Review 1's N3; half right. `mockAttributesOnMockOnly` is new (#557). The `Self` warning is not: L126 says "still warns".
  - Fix: "A build that treats warnings as errors fails on the three deprecations, and on `mockAttributes` on a `mockOnly` declaration, until each is addressed."

## Nits

- **16. L118 `bazel run` label.** Review 2's S6, downgraded. `@safedi//bazel:safeditool` still works (#599) and is the label #560 fixed, but the Manual (L1668) uses the other. Fix: "`bazel run @safedi//:SafeDITool -- <arguments>` accepts relative paths (#560, #599)."
- **17. No path for 2.1.x readers.** Review 2's N7; 2.2.0's notes had "From 2.0.x". Fix: add "### From 2.1.x or earlier" with "Read Upgrading in the [2.2.0 release notes](https://github.com/dfed/SafeDI/releases/tag/2.2.0) as well."
- **18. L10 is one 150-word bullet.** Review 2's N4. Split after "…with the values in scope at each place." and start a new bullet at "The builder returns…".
- **19. L124 "in the reader’s build".** Review 2's N5. Fix: "in your build".
- **20. L111 is abstract.** Review 2's N6; #605's example is typed throws. Fix: append "such as a closure’s `throws(Failure)`" after "its spelling carries".
- **21. L127 repeats L185.** Review 2's N9. Fix: delete "A script that matches SafeDI’s text needs updating." from L127.
- **22. Item 2's second sentence (L148).** Review 2's N10. Fix: "Where the chain’s start is unavailable, the fix-it’s rename is `nil`, even if an ancestor declares the middle label the chain used to read."
- **23. L9 "guard enum".** Review 2's N3; the Manual does not use the term. Fix: "Generated calls also name a check of the seam’s signature, so a stale generated call is a compile error."
- **24. L85 "as the Manual’s rule says", and L12.** Review 2's N8. Fix L85: "as a `@Received` property does everywhere else". Link the Manual section L12 names.
- **25. Heading levels.** Review 2's N1. 2.2.0 had Diagnostics and "Errors SafeDI now reports" as `###` under Fixes; the draft has `##`. Either works; match 2.2.0 unless Deprecations needs the level.
- **26. Xcode remedy for item 1.** The valid half of review 2's S10. The generated comment exists (`DependencyTreeGenerator.swift:272`). Optional addition to L147: "In an Xcode project, add the SafeDIGenerator plugin to the target that declares the root."

## Dropped

- **Review 1 S9, #686.** Its body says the failure "comes from how mocks bind a renamed override since 2.2.0", so 2.2.0 did not have the defect.
- **Review 1 S9, #537.** Unverified. `isProvidedByEnclosingScope` exists in 2.2.0, so the defect may predate 2.3.0, but the PR only says "the defect is main’s". Add a Fixes bullet only if 2.2.0's `generate` on seed 4724's fixture shows `nil` for the alias.
- **Review 1 N2, the "2026-11-16" stamp.** Not an error: the commit time is 2026-11-16T01:10Z, so the stamp is the UTC date. Moot once finding 14 removes the comments.
- **Review 2 S10, the diff's `dependencies: ["SafeDI"]`.** Wrong: SwiftPM resolves a by-name dependency to a product whose package has the same name. The Manual's own snippet (L1439–1443) shows only the `plugins:` lines.
- **Review 2 N2.** Folded into finding 1's placeholder text.