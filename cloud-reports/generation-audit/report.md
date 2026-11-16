# Audit: repeated and uncached work in `SafeDITool generate`

Base: `main` 87e1bc10f. Read only: nothing under `Sources/` is changed on this branch. Linux, Swift 6.2 release build of
`SafeDITool` (`swift build -c release --product SafeDITool`; `--target` builds but does not link), 4 cores, 15 GB.
Profiles: `perf record -e cpu-clock -F 400 --call-graph dwarf` (CPU samples, all threads). Harness and profiles are
beside this file (`harness/`, `profiles/`). Slice 2's head (#738) was not profiled; every site below is on main, and
the seam sites may have moved there.

## Summary

1. **Generation time is roughly linear in emitted lines (30–100 µs a line), but three things are not:** the per-level
   re-indent of child code (quadratic in depth on wide trees, cubic on deep chains), the seam signature work (known,
   plus three more sites below), and the serial phases that cap parallelism near 2× on 4 cores (1× for seams).
2. **Two cheap fixes were prototyped and are byte-identical** on 8 shapes (every `.gen.swift` and `.safedi` compared
   with `cmp`): the re-indent and the mock override-path strings. CPU −29 to −36% on wide production, mock-heavy and
   cycle-heavy shapes, wall −10 to −18%, and a chain 800 deep from 84 s to 13 s (`harness/prototype.patch`).
3. **The biggest lever is structural and belongs in 2.3.1:** a generator exists per *path*, so the per-generator code
   cache Dan designed still exists but never sees a second request across paths, and mock code is not cached at all.
   Emitted size multiplies with depth, and generation follows it. Keying generators (and the emitted builder
   functions) by type plus the context they read is the plan's `BuilderKey`; it removes the repeated work wholesale.

## Measurements (main)

| Shape | What it is | Modules | Lines generated | Slowest `generate` | Total |
|---|---|---|---|---|---|
| w8 / w10 | 1 root, 30 types × 8 / 10 layers, fan-out 3 (`harness/make_wide.py`) | 2 | 31,675 / 265,306 | 1.04 s / 9.0 s | 1.1 s / 9.2 s |
| w8m / w9m | w8 / w9 with `generateMock: true` on every type | 2 | 554,396 / 1,571,554 | 14.4 s / 47.7 s | 19.9 s / 66.2 s |
| chain100 … chain800 | one chain, `Instantiator` every level | 2 | 521 … 4,021 | 0.25 / 1.6 / 10.2 / 83.9 s | cubic in depth |
| issue646-16 / mock-12 | #646 screens (Instantiators, cycles) | 1 | 114,024 / 339,105 | 11.8 s / 18.7 s | |
| E16 / E24 seam | spike 2 shape, seam + filler | 2 | 2,410 / 17,346 | 0.36 / 5.6 s (filler) | 0.69 / 9.0 s |
| layered100 / 200 / 400 | `layered.py` scaled (`harness/make_layered.py`) | 100–400 | 137k / 227k / 489k | 1.0 / 0.58 / 1.1 s | 6.9 / 11.8 / 28.3 s |
| same, `-seams` | | 100–400 | 259k / 875k / 1,734k | 1.05 / 2.7 / 2.2 s | 14.8 / 47.5 / 99.3 s |

- Many modules alone cost nothing extra: the median module takes 45–47 ms at 200 and at 400 modules. Total time follows
  emitted lines; with seams, lines grew 3.4× for 2× the modules (nested builder functions of preview mocks and seam
  calls), which is output growth, not repeated work.
- E24's filler (`App`) spends 52% of its CPU recomputing the foreign seam's signature (item 3).
- CPU over wall: w10 1.8–2.2×, w8m 1.7×, issue646 1.8×, E24 seam 1.0× on 4 cores (item 9).

## Ranked hot spots: (a) output-neutral point fixes for 2.3.0

Order is by measured share at the adopter's scale (wide trees of depth ~11, 100+ modules, seams), then by risk.

### 1. Child code is re-indented at every level of the tree

- **Where:** `ScopeGenerator.generateCode` (`ScopeGenerator.swift:2135–2141`): each child's whole text is split on
  `"\n"`, prefixed and joined again, and its parent's text is re-indented again by the grandparent. The same pattern,
  per node, at `:4741`, `:5676`, `:9618`, `:9641`, `:9897`.
- **Complexity:** O(depth × output bytes). On a chain the text at depth k carries k tabs, so output is O(d²) bytes and
  work O(d³).
- **Measured:** 25% of CPU on w8, 30% on issue646-16, 88% on chain400 (`profiles/w8app.txt`, `i646.txt`,
  `chain400.txt`). Chain 100/200/400/800: 0.25 / 1.6 / 10.2 / 83.9 s for 521 / 1,021 / 2,021 / 4,021 lines.
- **Fix A (prototyped, `harness/prototype.patch`):** the same transform in one pass over UTF-8 (`String.split` over
  `Character`s is the cost). Byte-identical on all 8 shapes. CPU: w10 18.4 → 12.2 s, issue646-16 22.9 → 14.7 s;
  chain800 84 s → 13 s. Still O(depth × bytes), with a small constant (`indenting` is 5% of w10 after, 53% of chain800).
- **Fix B (complete):** indent once. A node's leading whitespace is fixed by its position, so either pass the absolute
  indentation down and add it to `UnavailablePropertiesCacheKey`, or have `generateCode` return lines with a relative
  depth and join once at the root. Linear in output. The other five sites take the same change.
- **Risk:** A low (pure function, identical result; `split` omits empty lines, which the loop reproduces). B medium:
  every site that composes child text changes, so a byte comparison over the test suite's expected output is the gate.

### 2. Seam signature: `internalName(ofBuilderLabeled:)` and the `sortKey` comparators (known)

Already measured by the benchmark lane (`e24-seam-profile.md`): `SeamBuilderParameters.swift:163` rebuilds a name union
per hole site (O(sites²)); `SeamBuilderFamilies.swift:306/:321` and `SeamScopeEnumsByType.swift:880` build path strings
inside comparators. Listed here only for the ranking. Two more of the same family:

- `SeamBuilderFamilies.swift:446–460` (`builderLabelByKey` naming): a string `sortKey` per comparison, then per key
  `var taken = reservedNames` (a full copy) plus a `formUnion` of every prefix's names: O(keys × (reserved + depth ×
  names)). Fix: sort precomputed keys; test `taken` membership against `reservedNames` and the prefix sets without
  building the union, as for `internalName`. Neutral; low risk.
- `SeamBuilderFamilies.swift:185` and `:214`, `SeamScopeEnumsByType.swift:623`: `asSource`, `label(of:)` and dictionary
  lookups inside comparators. Small n today; same decorate-sort fix.

### 3. Every caller module recomputes each foreign seam's signature

- **Where:** `DependencyTreeGenerator.foreignSeamRoots` → `seamSignatures(forSeams:…)` (`DependencyTreeGenerator.swift:
  4560–4690`) run in the caller over the seam module's view, with the same fixed point as the seam's own module.
- **Complexity:** per run, O(foreign seams reached × seam cost); across a build, O(caller modules × seam cost) for
  each seam, and the seam cost itself is item 2's quadratic.
- **Measured:** 52% of E24's filler CPU (`profiles/e24app.txt`: `seamSignatures` 51.7%, `seamRoot` 52.7%).
- **Fix (2.3.0, partial):** items 2 and 4 make each recomputation cheap, which is output-neutral. Removing the
  recomputation means carrying the settled signature in the seam module's `.safedi` with a hash of the inputs the
  caller would compute it from, and computing only on a mismatch (S3 below). That changes `.safedi` bytes, not
  generated Swift, so it is a 2.3.1 item.
- **Risk:** the design deliberately has both sides compute from one view so that a stale or foreign `.safedi` cannot
  disagree; any carried signature needs that hash and a fallback.

### 4. Fill name maps are rebuilt per fill

- **Where:** `ScopeGeneratorUnderConstruction.enclosingFillsOfThisCall` (`Scope.swift:1058`), a computed property that
  copies `enclosingFills` and inserts every fill and dispatcher of the call, read once per fill created (`Scope.swift:
  955`) and per scope (`:1225`).
- **Complexity:** O(fills²) per seam call.
- **Measured:** 20% of E24's filler CPU (`ScopeGeneratorUnderConstruction.enclosingFillsOfThisCall.getter`).
- **Fix:** compute it once per call after `fillsOfThisCall` and `dispatchersOfThisCall` are final, and hand the
  dictionary to each fill. Neutral (same dictionary).
- **Risk:** low, if the fills and dispatchers are complete before the first fill is created; check that order first.

### 5. Mock override paths are rewritten with Foundation at every node

- **Where:** `ScopeGenerator.swift:9331–9333` and `:9753–9755`, `PublicMockGeneration.swift:515–517`:
  `nodePath.replacingOccurrences(of: "safeDIOverrides.", with: "").replacingOccurrences(of: ".", with: "_")`, where
  `nodePath` grows with depth.
- **Complexity:** O(depth) per node through `NSString` bridging (a mutable copy, a find-results array).
- **Measured:** 25.8% of w8m's mock module, 17.5% of issue646-mock-12, 11% of a layered seams module.
- **Fix A (prototyped):** the same rewrite in one native pass. Byte-identical. With fix 1A, w8m CPU 23.8 → 16.8 s, wall
  13.5 → 11.4 s.
- **Fix B:** carry the relative path down beside `nodePath` (`parent + "_" + label`), O(1) per node. Identical for every
  label except one ending in `safeDIOverrides`, whose `.` today's rewrite would also eat; such a label is legal but
  improbable, and B's spelling is the intended one. Take A for 2.3.0 if that label must stay byte-identical.
- **Risk:** low.

### 6. Builder-function parameter lists are built as SwiftSyntax and printed

- **Where:** `initializerFunctionParameters(amongTypesDeclaredEscaping:).map(\.description).joined()` at
  `ScopeGenerator.swift:5203, 5245, 5315, 5356, 9486, 9978, 10215`, through `Property.asFunctionParameterSyntax`.
- **Measured:** 4.5% of issue646-16 and of issue646-mock-12.
- **Fix:** spell the parameter text directly, or memoize it per (forwarded properties, escaping types), which repeat
  across paths. Neutral if the spelling matches SwiftSyntax's `description` exactly; gate on byte comparison.
- **Risk:** low to medium (trivia and attribute spacing).

### 7. Whole trees are created again, and production trees validated again

- **Where:** `Scope.createScopeGenerator` (`Scope.swift:402–453`) repeats the whole root's tree while cycle parameters,
  fill-bound labels, builder loops or start order change anywhere in it. `seamSignatures` builds each seam's whole
  tree at least twice (a pass to find the signature, one to confirm it settled), again for the callers' view when one is
  built, and in every caller (item 3). In a module with mocks, `mockScopes` runs `validatePropertiesAreFulfillable`
  (`cyclesOnly`) over every production root's tree again (`DependencyTreeGenerator.swift:1029`; 10% of w8m's mock
  module), and each mock root builds its subtree from scratch.
- **Fix (2.3.0):** none cheap and neutral that I would take before release; the confirming seam pass could be skipped
  when the pass's output equals its input signature in everything `seamRootGenerator` reads, which needs a proof
  that nothing else feeds the tree. Measure pass counts first (an instrumentation counter, not done here).
- **2.3.1:** S5 below.

### 8. Comparators and hashes that recompute spellings

- `TypeDescription.<` (`TypeDescription.swift:210`) builds `withoutAny` (a new tree) and `asSource` for both sides,
  and `asSource` again on ties; `Property.<` (`Property.swift:83`) builds `typeDescription.asSource`.
  `TypeDescription.hash` walks the tree each time (`Property` caches its hash; `TypeDescription` does not). Sorts over
  types: mock roots (`DependencyTreeGenerator.swift:327–328`), generated roots (`:544`, `:562`), cycle-edge DFS
  (`:1314`, `:1319`), seam types. `Hasher.combine` is 4–11% of samples in seam shapes, mostly `Set<String>`.
- **Fix:** decorate-sort-undecorate where n can be large (keys computed once); leave small sorts. Neutral.
- **Risk:** low. Value: small today, grows with type count.

### 9. Serial phases and per-node tasks cap parallelism

- `rootScopeGenerators` creates each root's tree serially (`DependencyTreeGenerator.swift:3139`), the mock-root loop
  creates every mock root's tree serially (`:325`), validation is serial, and `seamSignatures` walks components one at
  a time. Code generation is parallel: each generator is an actor whose code starts on a detached task at creation
  (`Scope.swift:1317`), which on w10 costs 10–15% in task creation, allocation and enqueueing.
- After fixes 1A and 5A, w10's remaining CPU is tree creation 24%, validation 10%, emission 17%, task overhead ~12%
  (`profiles/w10p.txt`); wall stays near 7.4–8.8 s because creation and validation are serial.
- **Fix (2.3.0, neutral):** start a detached task only for subtrees above a size threshold and generate small subtrees
  inline in the parent's task. **2.3.1:** S4.

### 10. Not measured hot, worth knowing

- `NearestDeclarations` subscript (`Scope.swift:1755`) walks a chain of layers as long as the tree is deep for a label
  declared far up: O(depth) per miss. Not visible behind item 1 on chains; recheck after it.
- Parsing and module-info loading: under 10% of a small module; flat across 100–400 modules.

## Per-scope memoization and actor parallelism today (Dan's question)

- **Still there:** `ScopeGenerator` is an actor (`ScopeGenerator.swift:26`) and caches its dependency-tree code per
  context (`unavailablePropertiesToGenerateCodeTask`, keyed by unavailable properties, properties generated later and
  builder function names, `:2096–2125`); generation starts on a detached task per generator, so siblings and subtrees
  emit in parallel.
- **What changed around it:** generators are created per *path*, one per node of the inlined tree
  (`Scope.createScopeGenerator`), not per scope. A type reached by 1,000 paths gets 1,000 generators, each asked once
  by its parent, so the cache coordinates the early start with the parent's request and never returns another path's
  work. Mock code is not cached at all (`:2104`, "the context varies per call site"). Seams build generator trees with
  `startsCodeGeneration: false` for signatures, several times per seam (item 7), and holes, builders and fills are
  computed from those trees per site. Tree creation and validation, now the larger share, run serially and outside the
  actors.
- **So:** the repeated work is not a bypass of a memo that would otherwise hit; it is that the unit of memoization is
  a path. The structure Dan describes, a generator per scope reused across paths, needs a key that says when two paths
  generate the same text: the scope plus the context its subtree reads.

## (b) Structural options for the 2.3.1 rewrite, mapped onto the plan

- **S1. Indentation-free spelling (E1/E2).** The emitter design splits plan from spell (`plans/2.3.1-emitter-design.md`
  §2). Spell into one buffer with absolute indentation and item 1, and the `split`/`join` at the five other sites,
  disappear. Byte-identical by construction; cheapest to do in E1, since E1 already touches every emission site.
- **S2. Memoize generators by `BuilderKey` (R1–R3, type mode).** Key a generator, and the builder function it emits, by
  (concrete type, the projection of context its subtree reads: the nearest declaration and availability of each label
  in its `receivedProperties`, the builder function names it refers to, the cycle and fill stack entries it closes on).
  Two paths with equal keys share one generator, one validation result and, in type mode, one emitted function, so work
  and output become linear in types × distinct contexts instead of paths. Path mode (E1–E6) can use the same key as a
  memo for tree creation and validation while still spelling per path, which keeps output byte-identical and cuts the
  creation share (24% of w10 after the point fixes). Mocks get the same key with the override path in it, which is what
  makes the mock cache possible that `:2104` gave up on.
- **S3. Per-seam memo across modules.** Compute a seam's settled signature once, in its own module, and write it, with
  a hash of the declarations its computation read, into the `.safedi`; a caller recomputes only on a mismatch. With S2,
  holes and builders are per (seam, site key) rather than recomputed per site, which is where item 2's quadratic comes
  from.
- **S4. Parallel trees from `Sendable` snapshots.** `generator-design.md` already requires immutable snapshots for
  parallel work. Build the per-type facts once, serially, then create and validate each root, each mock root and each
  seam component of one topological level in a task group. Coarse tasks per root replace a detached task per node.
- **S5. Incremental fixed points.** When a pass of `createScopeGenerator` changes cycle parameters or fill labels in
  one subtree, re-create only the generators whose key changed (S2's key makes this a lookup), instead of the whole
  root's tree; likewise only re-run a seam component whose input signatures changed.

## Recommendation

For 2.3.0: items 1 (A now, B if the lead wants linear), 4, 5 (A), and the known seam fixes with item 2's two
siblings. Together they remove every super-linear term measured here except the seam fixed point and output growth, at
low risk, and items 1 and 5 are proven byte-identical on the shapes above. Items 3, 7 and 9 go to 2.3.1 as S3, S5 and
S4; S1 and S2 are the plan's own E1/E2 and R1–R3 with a memo key added, and S2 is the one change that removes the
repeated work wholesale.

## Harness

- `harness/make_wide.py OUT DEPTH WIDTH FANOUT [mock] [modules=M]`: layered single-root shapes and chains.
- `harness/make_layered.py OUT K seams|plain`: `layered.py` with every layer K times as wide.
- `harness/genshape.py TOOL SHAPE OUT`: runs `generate` per module as `bench.py` does, prints per-module times and
  writes the commands for profiling. `harness/prof.sh NAME COMMANDS LINE`: `perf` on one of them.
- Fixtures D, E, L, issue646 and layered100 come from `Scripts/benchmark-2-3-1/make_fixtures.py` on
  `claude/project-thread-7eql0r` f8eeeb87.
- `harness/prototype.patch`: fixes 1A and 5A, for measurement only (no tests, not linted).
