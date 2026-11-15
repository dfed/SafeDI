# Spike 1: one generated function per type in production trees — CHECKPOINT (paused)

Status: paused at the tech lead's request (usage pause), after section A's failure classification.
Not yet done: Examples/ CSV comparison, section A full-suite rerun with the latest edits, section C, section B, final report.

- Branch: `claude/project-thread-4xgw6h`; base `2475984` (main).
- `swift --version`: Swift version 6.2 (swift-6.2-RELEASE), x86_64-unknown-linux-gnu.

## What is built

- `Sources/SafeDICore/Generators/PerTypeEmission.swift`: a post-pass over a root `init()` body (production `.dependencyTree` only). It parses the per-path text with SwiftParser, resolves references lexically, and groups builder functions by key (function text without indentation, its own name abstracted, leading `@Sendable` dropped). Every group with two or more places is hoisted into one function at the innermost body all sites pass through, just before the first statement reaching a site. Reads are captured when every member resolves them to one visible declaration; otherwise they become parameters, in first-read order. The pass repeats, innermost groups first, until nothing more is shared. `SAFEDI_PER_PATH_EMISSION=1` keeps today's text.
- A tree in which every key has one place is byte-identical by construction: the pass edits nothing without a group.
- `Tests/SafeDIToolTestSupport/SafeDIToolTestExecution.swift`: `SAFEDI_SPIKE_DUMP_DIRECTORY` dumps every test's generated files.
- `Tests/SafeDIToolFuzzerTests/SpikePerTypeCorpusTests.swift`: corpus differential (text, idempotence, values and retention through `DifferentialValueOracle`). It is built but has not run yet.
- `bench/wide_graph.py` (from the brief), `bench/measure.py` (written, untested), `bench/compare_dumps.py`.

## Worked example

Matches the brief's 27-line form: grandchildA and grandchildB hoisted, `@Sendable`, and grandchildB takes `recreated:`. The body goes from 33 to 24 lines.

## Section A (SafeDIToolDependencyTreeTests + SafeDIToolTests, both emitters)

Command: `/home/user/runA.sh`, which runs `swift test --traits sourceBuild --filter 'SafeDIToolDependencyTreeTests|SafeDIToolTests'` once per emitter with `SAFEDI_SPIKE_DUMP_DIRECTORY` and `SAFEDI_SPIKE_STATS_FILE`; then `python3 bench/compare_dumps.py dump-base dump-spike --json A-compare.json`.

| Measure | Base (per path) | Spike (per type) |
|---|---|---|
| Tests | 1712 passed (2 known issues) | 12 fail, all `Expectation failed` text mismatches; no compile-verifier failure |
| Root trees | 738 | 738 |
| Root-tree lines | 13,853 | 13,801 (0.375% were copies) |
| Trees building a type in 2+ functions | 34 | 21 |
| Tests whose files changed | | 15 (13 real; 2 only differ in a temporary fixture path) |

The ten largest reductions are 34→25, 35→32, 28→22, 28→24, 24→20, 15→11, 11→7, 27→24, 23→20 and 22→19.

Failure classes:

- **(a)**: 12. Each is an expected-text change in a tree that builds a type in two or more places; every changed root file has a type with 2+ functions in the base. The compile verifier compiled all of them without warnings. The failing tests:
  - CodeGeneration ×4, including the `cBuilder` self-loop shared in `passesNearestRebindingToOnlyIfAvailableReceiver…`
  - KeywordLabel ×2
  - LazyCycleNearestDeclaration ×6
- **(a′)**: 0. The lazy closing-call fix is not implemented in the spike; cycle parameters keep `x.instance`.
- **(b)**, **(c)**, **(d)** and **(e)**: 0 so far.
- **(f)**: not yet run, because the full suite is still pending.
- The non-root file changes are temporary-path noise only.

Spike stats over 1,314 trees (debug suite run):

- Shared: 33 groups, 66 places.
- Not shared:
  - 6 groups where "members call different enclosing functions" (cycles and loops of builders);
  - 1 group where "members read different labels".
- Trees skipped: 7 where "does not parse" (to investigate) and 5 that are "deeper than 48 levels".

## Synthetic DAG, lines only (worst case, labelled as such)

`wide_graph.py` DAG, root body lines, base / spike:

| Layers | Base | Spike |
|---|---|---|
| 3 | 377 | 145 |
| 4 | 1,133 | 197 |
| 5 | 3,401 | 249 |
| 6 | 10,205 | 301 |

No not-shared cases.

## Deviations so far

- The key includes whether a declaration exists, so a `nil` path and a value path stay separate functions. The stats count these as `typesSplitOnlyByNil` and `placesSplitOnlyByNil`.
- The lazy closing-call fix (a′) is not done.
- A `@Sendable` shared function takes every read as a parameter.
- Fills, `_ =` guards, control flow and closures with signatures are not shared.

## Where I stopped / next on restart

1. Rebuild is done with the latest edits: closure placement and nil-split stats. Next, rerun section A's spike side and the full suite for class (f).
2. Investigate the 7 "does not parse" trees.
3. Examples/ CSV.
4. Section C: corpus differential 0..<5000, seam and public-mock text-only runs, traced synthetic configurations.
5. Section B through `measure.py`.
6. Final report.
