# N2: the mock body as the per-type emitter plus an override hook (spike)

Spike only: nothing under `Sources/` changed, no pull request, nothing posted. Every shared form here is hand-written
(F1–F4) or written by a small script over today's text (F5); spike 1's emitter was not extended.

## Answer

**Yes: one function per key serves every place of a mock body**, with each place passing its own configuration, and
gives inline's values and frees and exactly today's override reads, in all five fixtures. Public mocks can take the
full shared form in 2.3.1.

**But the key is bigger than "reads a configuration".** To give exactly today's reads, the key must also hold, for
each child a function builds, where that child's configuration comes from: the function's own configuration's field
(`param.<label>`), none (`nil`), or one fixed path (`safeDIOverrides.<path>`). Today's closing calls re-enter a
function that reads a fixed path, and today's cycle edges leave a reopened place reading none, so these differ by
place, and the difference spreads up through every function that reaches it.

What that costs, on #646's mock variant at 12 screens (13 mocks in one file):

| Form | Functions (all mocks) | Root mock: places → functions | Lines | `-Onone` compile | Values, frees | Override reads |
|---|---|---|---|---|---|---|
| today (per path) | 6,592 places | 672 → 672 | 339,108 | 6 min 15 s, 13.2 GB | reference | reference |
| shared, today's reads (`s`) | 2,549 | 672 → 150 | 39,933 | 48 s, 1.7 GB | = today | **= today** |
| shared, one read rule (`u`) | 156 | 672 → 12 | 10,858 | 8 s, 0.27 GB | = today | 47 trace lines differ |

(`-O` figures and runtime: section F5.) So the shared form is a large win either way, and the remaining choice is
whether R3 keeps today's reads beneath cycles (about 12 functions per type in this graph) or adopts one read rule
(one function per type). That choice is the maintainer's; it is question 1 below.

## Setup

- Base: `origin/main` `a6d44af` (#725). Branch `claude/project-thread-71tust` (this machine may push only its own
  `claude/…` branch). The harness is spike 2's (`spike/per-type-seam/common/`, from `claude/project-thread-ea2rdt`
  via `claude/project-thread-trnjpn`) with one change, in `spike/n2-mock-body/common/Harness.swift`: a
  `tracingEnabled` switch so timing runs measure the generated code and not the trace.
- Swift 6.2.4 (`swift-6.2.4-RELEASE`, x86_64 Linux, swift.org Ubuntu 24.04 tarball, signature checked), Ubuntu
  24.04, 4 cores, 15 GB. `SafeDITool` from main's debug build (`swift build --traits sourceBuild`).
- Every fixture compiles with `-swift-version 6 -warnings-as-errors` at `-Onone` and `-O`, as spike 2's
  `build.zsh` does. A trace holds every value created and what it received, override reads (each override closure
  notes its path, then builds what the default would), and what is alive after dropping everything and after holding
  one deep value.
- Variants: `p` production (the same types under `isRoot`, the inline reference for values), `b` today's mock
  (`SafeDITool generate`), `s` the shared form, `a` inline (F4: one module), `c2` and `h` the W1 derisk spike's
  public-mock bodies (F4), `u` the shared form under one read rule (F5).
- Rerun: `spike/n2-mock-body/run-all.sh`.

## Results per fixture

"= today" means the whole trace, overrides included, equals `b`'s byte for byte at `-Onone` and `-O`. "= inline"
means the trace without overrides equals `p`'s (F1–F3: except `Top#1`, the production root that F1's mock promotes
`service` out of).

| Fixture | Shape | Places → functions | Values, frees | Override reads | Lines today → shared |
|---|---|---|---|---|---|
| F1 | internal mock; promoted `service`, flat `user`, root `onlyIfAvailable` override `badge`; overrides three deep; `Leaf` at three places | `Leaf` 3 → 1 | = inline, = today | = today | 147 → 141 |
| F2 | `Screen ↔ Step` through `Instantiator`s; `cache` declared again in every `Screen`, read by `Model` in the loop | `Screen` first + reopened → 1, `Step` → 1 | = inline, = today | = today | 90 → 88 |
| F3 | lazy cycle (`Preview` lazily builds `Editor` again); `Toolbar` reads `theme` inside the cycle | already one per type today | = inline, = today | = today | 87 → 90 |
| F4 | public mock with a hole; the fill reads `cache`, bound in the loop (F3 of the per-type seam spike) | `Screen` first + reopened → 1, `Step` → 1 | = inline (`a`) | = `h` and = inline on every field both have | 168 (`h`) → 166 |
| F5 | #646's mock variant, 12 screens, seed 5, 13 mocks | 6,592 → 2,549 (`s`), 156 (`u`) | = today (depth 3, every mock) | `s` = today; `u` differs | 339,108 → 39,933 (`s`), 10,858 (`u`) |

Trace files: `spike/n2-mock-body/F*/results/`. Line counts include the comments the shared forms carry (3–4 lines).

### F1: promoted root, flat parameter, three places

Today writes `Leaf` three times (under `a`, `b`, `cBuilder`), each reading its own path. The shared form is one
function:

```swift
func __safeDI_leaf(badge: Badge?, safeDIOverrides: Leaf.SafeDIMockConfiguration) -> Leaf {
    let detail = if let safeDIBuilder = safeDIOverrides.detail { safeDIBuilder(service) } else { Detail(service: service) }
    return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(service, user, detail, badge) } else { Leaf(service: service, user: user, detail: detail, badge: badge) }
}
```

`service` (promoted) and `user` (flat `mock()` parameter) are one declaration at every place, so they are captured.
`badge` is the root's `onlyIfAvailable` override at two places and `B`'s at one, so it is passed. The mock root's
prologue (promotion, flat parameters, the override binding) stays outside the graph: the graph only sees
declarations visible at the top level. This answers the clean-slate estimate's worry that the hook "cannot express
promoted roots or flat-parameter rebinding": it needs nothing for them. Renamed flat parameters (`user_Draft`) and
uncovered `@Instantiated` parameters were not drawn here; they are more top-level declarations of the same kind.

### F2: a loop of builders with a value declared again

Today's reads are not uniform: the first `Screen` reads `screen`, a reopened `Screen` reads none, and every `Step`,
first or reopened, reads `screen.stepBuilder` (the closing call re-enters the first `Step` function). The shared form
gives exactly that with two argument sources: `Screen` takes its configuration as an optional parameter (`nil` at the
reopened place), and `Step` captures `safeDIOverrides.screen.stepBuilder`, the same at every place. `cache` is a
parameter of `Step`, as today's cycle parameter.

### F3: a lazy cycle with a reader inside

Today's text already has one function per type: the closing call (`LazilyInstantiated<Editor> { __safeDI_editor(theme:
theme) }`) re-enters the first `Editor` function, which reads `editor` at every place. The shared form only moves the
functions to the body's top level. Note the contrast with F2: re-entered through a lazy cycle, the reopened `Editor`
reads the first one's configuration; reopened through an instantiator loop, F2's `Screen` reads none.

### F4: a public mock with a hole (the per-type seam spike's F3)

`s` is W1 derisk variant `h` (the loop-closing function takes its level struct) with `Screen`'s first and reopened
places sharing one function, its configuration a parameter:

```swift
func __safeDI_screen(
    _ __safeDI_apiBuilder_screen: SafeDIMockScope_Api.Screen_Scope.__safeDI_Builder<any Api>,
    safeDIOverrides __safeDI_overrides: __safeDI_Feat_Screen_MockConfiguration?,
) -> Screen { … }
func __safeDI_stepBuilder(_ __safeDI_apiBuilder_step: SafeDIMockScope_Api.Step_Scope.__safeDI_Builder<any Api>) -> Step {
    let screenBuilder = Instantiator<Screen> { __safeDI_screen(__safeDI_apiBuilder_step.screenBuilder(.init()), safeDIOverrides: nil) }
    …
}
let screen = __safeDI_screen(__safeDI_apiBuilder.screen(.init()), safeDIOverrides: safeDIOverrides.screen)
```

Values and frees equal inline (`Live#2(cache: Cache#2)`, screen 1's cache freed when only screen 2's step is held);
`c2`, today's per-path closing, still gives `Live#2(cache: Cache#1)`. The override reads equal `h`'s and the inline
mock's on every field the public configuration has (inline's `Step` configuration also has `api`, the hole, which a
public mock's caller fills). The library-evolution build with a verified interface passes. Main rejects this shape
today (`declarationBoundOnCycleReentry`), so "today" for F4 is `h`.

So the objection the per-type seam spike recorded (its F3: one function for the first and a reopened `Screen` needs
the configuration as a parameter) is answered by the parameter, as planned.

### F5: #646's mock variant at 12 screens

`F5_gen.py 12 5` is the issue's script with seed 5 and `mock`, every type a traced class, and `id: Int` where the
issue has `String` (the harness prints integers; the generated shape is the same). `F5/shared_form.py` rewrites every
`mock()` body of today's file: it parses today's nested functions, takes each place's override read from its
`safeDIBuilder` line, applies #646's rule for `context` (each place gets the nearest declaration on the path that
built it), and emits one top-level function per class of places. Classes start from the local key (type, the form of
`context` it is handed, whether it declares `context`, each child's configuration source, the construction's
arguments) and are refined by the classes of the functions each one calls until nothing splits (spike 1's
bisimulation). `F5/driver_gen.py` walks every mock three levels deep (every builder instantiated), once with no
overrides and once with every override field of every configuration set.

The first version keyed by the local key only and failed: 59 trace lines differed, all override reads, because two
places of one type with the same local key called functions that read different paths. The refinement fixed it, and
that failure is the evidence that the key must include, transitively, where each descendant's configuration comes
from.

Why `s` needs 150 functions for 12 types in Root's mock: of 672 places, 37 read a configuration (the rest sit
beneath a cycle edge and read none), and closing calls into those 37 read their fixed paths. Every place whose
subtree, through closing calls, reaches a different set of fixed paths is a different class. No split came from
`context` or from the construction's arguments.

`u` applies one rule instead: a place reads its parent's field for it when the parent's type has one, else none.
That is one function per type in every mock (12 each), with values and frees equal to today's. Its reads differ from
today's at closing calls: 47 trace lines (293 override reads today, 246 under `u`).

FIGURES-F5

## Compile time and runtime, F1–F4

`measure.sh FIXTURE MODULE 5 2000 VARIANT…`: the module that holds the mock body (`App`, or `Feat` for F4), compiled
whole-module five times, median (min–max) wall seconds from `/usr/bin/time`; the module includes the fixture's types
and driver, the same in every variant. Lines are the generated file's.

| Fixture | Variant | Lines | `-Onone` s | `-O` s |
|---|---|---|---|---|
| F1 | today (`b`) | 147 | 0.53 (0.48–0.57) | 1.00 (0.85–1.12) |
| F1 | shared (`s`) | 141 | 0.57 (0.54–0.64) | 0.99 (0.83–1.13) |
| F2 | today | 90 | 0.46 (0.44–0.49) | 0.51 (0.48–0.61) |
| F2 | shared | 88 | 0.45 (0.40–0.46) | 0.52 (0.49–0.62) |
| F3 | today | 87 | 0.43 (0.39–0.50) | 0.54 (0.49–0.66) |
| F3 | shared | 90 | 0.45 (0.42–0.46) | 0.57 (0.50–0.65) |
| F4 | `h` (per path, W1's cycle parameter) | 168 | 0.45 (0.39–0.45) | 0.51 (0.49–0.64) |
| F4 | `c2` (today's per-path closing, wrong values) | 165 | 0.44 (0.40–0.48) | 0.52 (0.48–0.59) |
| F4 | shared | 166 | 0.41 (0.41–0.44) | 0.61 (0.55–0.67) |

Runtime (`BENCH=3000`, then `BENCH=20000` for F4 `-O`; nanoseconds per walk, which includes the harness's counting)
varied by up to 50% between rounds of one binary, and no variant was consistently faster: F4 `-O` over five rounds
gave `h` 5,430–8,354, shared 5,343–6,770, `c2` 5,239–5,919 (`bench-F1-F4.txt`). The four small fixtures are within
noise of today's per-path body at both levels, as expected: they build each type at one to three places.

## Shapes that cannot share

None of the five fixtures has a place that one function per key cannot serve. Against the mock-overrides spike's
"never shared" list:

| Never shared (spike 3) | Here |
|---|---|
| a subtree with a cycle (flags, cycle parameters, closed-on declarations) | shared: F2, F3, F5 (cycle parameters become function parameters) |
| a loop of builders | shared: F2 (`Screen ↔ Step` through `Instantiator`s), F5. Not drawn: a received loop the mock root promotes (`ReceivedBuilderLoops`, `loopMembersReadOnlyInsideTheirLoop`) |
| `LazilyInstantiated` instances | shared: F3 |
| every public mock | shared: F4 |
| fills, calls of public mocks | F4's fill and its call of `Home`'s public mock are on the calling side (level functions), which the shared body does not change; a public mock called from inside a shared function was not drawn |
| `onlyIfAvailable` aliases, unavailable receives | F1's `badge` (an `onlyIfAvailable` receive, the root override at two places, `B`'s at one) is a passed read. Aliases were not drawn |
| a `@Sendable` builder, a configuration that requires `Sendable` | not drawn |
| scope payloads | gone with the leak fix |

Not drawn at all, so they stay on the never-shared list until a fuzzer draw shows the shared form right for them:
`@Sendable` builders and their override locals (`SendableOverrideExtractor`), `@Sendable` autoclosure parameters,
hand-written mocks (`customMockName`, `mockOnly`), default-valued parameters, uncovered `@Instantiated` parameters,
renamed flat parameters and aliases, a public mock called inside a shared function, and a promoted received loop.
None of these looks like a blocker: each is a top-level declaration or a construction detail the key already has a
slot for. That is an argument, not evidence.

## E4's hook interface (one page)

The production per-type emitter (plan section 3) builds a function graph of keys. A mock body is that graph with a
hook that adds configuration. Production passes no hook, and its output does not change.

**Key.** `BuilderKey` (concrete type, provided form, each read's outcome: a declaration, `nil`, or passed) plus,
for a mock, a `ConfigurationRead`:

```swift
enum ConfigurationSource: Hashable {
    case parameter               // the function's own configuration parameter (optional)
    case field(label: String)    // the parameter's field for a child: `__safeDI_overrides?.<label>`
    case none                    // `nil`
    case fixed(path: [String])   // `safeDIOverrides.<path>` from the mock's own parameter, visible everywhere
}
struct MockKey: Hashable {
    let builder: BuilderKey
    let ownConfiguration: Bool                       // false: the function takes no configuration (every place reads none)
    let childConfigurations: [ConfigurationSource]   // one per child the function builds through a function
}
```

Classes are refined by the classes of the functions each calls (bisimulation), so two places share a function only
when everything they build reads the same. Under one read rule (question 1), `childConfigurations` is decided by the
type alone and drops out of the key.

**Hook.** Four calls the emitter makes, each with a production default:

1. `parameters(for: MockKey) -> [Parameter]`: appends `safeDIOverrides __safeDI_overrides:
   <Type>.SafeDIMockConfiguration?` (public: the module-level configuration) when `ownConfiguration`. Production: none.
2. `bindingValue(for child: Property, default: Expression) -> Expression`: a constant child the function builds in
   place (`cache`, `context`) becomes `if let safeDIBuilder = __safeDI_overrides?.<label> { safeDIBuilder(<args>) } else
   { <default> }`. Production: the default.
3. `construction(of: MockKey, arguments: [Argument]) -> Expression`: `if let safeDIBuilder =
   __safeDI_overrides?.safeDIBuilder { … } else { <init> }`, or for a public mock `<Type>.__safeDI_init(…,
   safeDIBuilder: __safeDI_overrides?.safeDIBuilder)`. Production: the initializer call.
4. `configurationArgument(at call: Call) -> Expression?`: the `ConfigurationSource` of the callee at that call,
   spelled. Production: none.

**What stays outside the graph.** The mock root's prologue: promotions, flat parameters and their defaults, the
`onlyIfAvailable` override bindings, root aliases and their renames, `@Sendable` autoclosure locals. The graph sees
them as declarations at the body's top level, captured when every place reads the same one (F1). `SafeDIOverrides`,
the configuration structs, `mock()` and its parameter order are unchanged; with the enum box storage (spike 3) the
configuration a parameter carries is one reference.

**Public mocks.** The same graph with the leak fix's level struct as a parameter where a function leads to a hole
(plan section 3 item 1), and `ownConfiguration` typed as the module-level configuration. F4 is that form.

## If the answer were no

It is not, so the fallback is not needed for public mocks. For the record, the fallback (W1 derisk variant `h`: per-path
body, the loop-closing function takes its level struct as a cycle parameter) costs 4–6 h per the W1 derisk report and
keeps #646's mock variant at today's size (339,108 lines, 6 min 15 s and 13.2 GB at `-Onone` for 12 screens here).

## Findings on main

- **Override reads beneath cycles are not uniform** (F2, F3, F5). Re-entered through an instantiator loop, a
  reopened type reads no configuration while the type its closing call re-enters reads the first place's (F2:
  reopened `Screen` reads none, its `Step` reads `screen.stepBuilder`); re-entered through a lazy cycle, it reads the
  first place's (F3). Which places read none follows the cycle edges, which D16 says a type-name order chooses, so
  which override a place reads can depend on type names. Not a value defect: overrides were never promised beneath a
  cycle edge, and the Manual says a node beneath one reads none. It is why exact reads cost about 12 functions per
  type in F5.
- **Today's #646 mock at 12 screens needs 13.2 GB to compile at `-Onone`.** A 16 GB machine is the floor for that
  graph today.

## Questions (not mine to decide)

1. **Exact reads or one read rule in R3?** Exact reads keep every override where it is (F5: 2,549 functions, 39,933
   lines); one rule (each place reads its parent's field for it when the parent's type has one, else none) gives one
   function per type (156 functions, 10,858 lines) and changes which override some places beneath a cycle read.
   Recommendation: one rule, landed with R2a's D16 fix, which already changes which configuration fields exist beneath
   cycles, so the two changes ship as one known break with one release note. If the maintainer wants no override
   change in 2.3.1, exact reads are still 8.5 times smaller than today and compile 8 times faster here.
2. **Placement.** Every shared function here sits at the body's top level, as spike 3's D2 did. The plan places at the
   lowest body every call passes through; both compile, and top level never needs to thread a captured value through
   an intermediate function, because every captured value here is a top-level declaration.

## Leftovers

- The shapes listed as "not drawn" under "Shapes that cannot share": R3's fuzzer draws, per the plan ("never shared
  until a draw shows the shared form is right for it").
- F5 at 16 screens: today's generate for the 12-screen mock already takes minutes in a debug build; a release-build
  run belongs to N1's benchmark.
- The enum box storage was not combined with F5's shared form; its configurations are small here (37 configuration
  reads in Root's mock). Spike 3 measured the box where configurations nest deeply.

## Draft PR description

Not applicable: spike, no pull request. For R3's eventual description: "Mock bodies now build each type in one local
function per way it is built, with the override configuration as a parameter, so a mock's size grows with its types,
not with the paths to them. #646's 12-screen mock variant goes from 339,108 generated lines to …".
