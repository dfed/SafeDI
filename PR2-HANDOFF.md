# PR 2 handoff: the generation phase timer, and one bounded, ordered helper for SafeDICore's task groups

You have an unzipped SafeDI repository and nothing else: no access to our CI, our GitHub Actions or our notes.
This file is your whole brief. Read all of it before you write code.

You are writing one pull request's worth of commits on top of the branch `trial-base`.
You hand back the commits, the full output of each gate below, and a short report.
Everything you need to check your work runs on your machine, with the commands given here.

## 1. What is in the zip

- The repository, checked out on branch `trial-base`. It has no remote. The tag `2.2.0` is in it.
- `trial-base` is one commit on top of `e5536453b`, the commit your work is measured from. That commit adds, and
  changes nothing under `Sources/` or `Tests/`:
  - `PR2-HANDOFF.md`: this file.
  - `docs/pr2-design.md`: the parts of our design note that this PR implements, copied word for word.
    This brief points into it by section number ("design 2.3").
  - `.claude/skills/generate-benchmark/`: the performance gate (section 9, gate 4). Read its `SKILL.md`.
  - `Scripts/byte-identical-gate.sh`: the check that no existing test line changed (section 9, gate 2).
- When we take your commits back, we drop the `trial-base` commit and put yours on `e5536453b`.
- Swift Package Manager still fetches the package's dependencies (swift-syntax and others) from the network on the
  first build. Allow that.

Start your work on a branch of your own:

```bash
git switch -c pr2 trial-base
```

## 2. Read first

1. `CLAUDE.md` at the repository root. Your agent loads it. Section 10 of this brief says which of its instructions
   do not apply outside our setup, and what replaces each.
2. `.claude/rules/generator-design.md`, `.claude/rules/test-design.md` and `.claude/rules/source-rules.md`.
   They load on their own when you edit matching files; read them before, not after.
3. `docs/pr2-design.md`, all of it.
4. The five task groups this PR replaces, all in `Sources/SafeDICore/Generators/`. At `e5536453b` they are every task
   group in `SafeDICore`:
   - `DependencyTreeGenerator.swift:243`: production output, one job per root.
   - `DependencyTreeGenerator.swift:320`: DOT output, one job per root.
   - `DependencyTreeGenerator+MockOrchestration.swift:160`: the union of `Sendable` configuration type names.
   - `DependencyTreeGenerator+MockOrchestration.swift:192`: mock output, one job per mock root.
   - `DependencyTreeGenerator+DeclarationValidation.swift:40`: the walk for `@Sendable` captures.
5. `Sources/SafeDICore/Generators/CodeTaskObservation.swift`: the task-local observer pattern the phase timer follows.
6. `.claude/skills/generate-benchmark/SKILL.md` and `run-gate.sh` beside it.

## 3. The goal, and the boundary

**What PR 2 changes.**
- First commit: a phase timer in `SafeDITool generate` (section 6).
- Then: one helper function, through which every task group in `SafeDICore` runs (section 5).
- Then: the five groups listed above, rewritten as calls of the helper.
- Last: formatting only (section 8).

**What must not change.** Generated code, `.safedi` files and diagnostics stay byte for byte as they are at
`e5536453b`, on every input, at every width (section 5). There is one exception, which is the PR's one fix:

- **The output error fix.** Today, when two or more jobs of the production output group or the mock output group
  throw, the error that is reported is whichever was thrown first. That is completion order, which changes from
  run to run. After PR 2, every failing root reports its error, joined in source order, and the outcome never depends
  on completion order (section 5.4 says exactly what is reported). This fix needs its own fixture (section 7, test 9)
  and is listed as a fix in your report.

**Out of scope. Do not do any of these, even where the design note describes them:**
- The output rewrite of later pull requests: output fragments, serial naming and spelled chunks (design section 4).
- Deleting the detached code starts (`Task.detached` in `Models/Scope.swift`, about line 1928), the unstructured
  `Task {` that deduplicates code in flight (`ScopeGenerator.swift`, about line 2809), the code-task memo, the mock
  parameter tree task (`ScopeGenerator.swift`, about line 4583), or the 64-scope early-start machinery. They stay
  exactly as they are.
- The `SourceRuleTests` rule against `Task.detached` (it lands when the last one is gone, later).
- The three `async let`s inside one mock output job (`MockOrchestration.swift:198`, `:209`, `:213`). They stay as they
  are, inside the helper's job.
- The task groups in `Sources/SafeDIToolLibrary` (parsing, module info, `ConcurrentMapping`). They do not use the
  helper.
- Any cost rule computed from tree sizes. Every job at the five sites has cost 1 in this PR (section 5.3).
- Wrapping construction errors (design 2.2 and 5.2 place that in a later pull request). PR 2 wraps only output
  failures (section 5.4).
- Anything of design sections 2.4 (shared subtrees), 3, 4, 5.5, or of any later pull request ("PR 3" onward).
- Changes to `Documentation/Manual.md`. The phase timer is an environment variable, not an option, so nothing
  appears in help or in the Manual.

## 4. The concurrency model

These rules bind the code you add or change under `Sources/`. The constructs that stay (section 3, "Out of scope")
stay as they are. Test code may use what a test needs: for example, a test cancels a helper call by running it inside
a task group of its own and calling that group's `cancelAll()`. Each rule comes with its reason.

1. **Structured task groups only.** No `Task.detached`, no unstructured `Task {`, and no stored task.
   Reason: a detached or unstructured task can outlive the work that started it, its error can be dropped, and a
   stored task keeps the memory of its async frames until it is released (13 to 18 KB per generated line was
   measured when finished tasks were kept). A task group's children cannot outlive the call that made them.
2. **Bounded fan-out.** A call admits jobs only while the costs of the jobs in flight, plus the next job's cost, are
   at most its `width`. Reason: an unbounded group starts every job at once, so every job's contexts and partial
   results are alive together. Bounding by `width` bounds memory and the number of tasks running job code.
3. **Admission in index order.** The helper admits the lowest index not yet admitted. It never admits a later job past
   one that is waiting for slots. Reason: which jobs ran must not depend on timing, so that the first failure and
   everything before it always ran (rule 5).
4. **Outcomes by index.** The helper returns one outcome per job, in the order of the jobs. The parent writes each
   child's outcome into its index; only the parent touches that storage. Reason: completion order changes from run to
   run, and no order of completion may reach output or diagnostics (section 11).
5. **Stopping, without cancelling.** A call made to stop at the first failure admits no later job once it has
   collected a failure. It cancels nothing: jobs already running finish, and their outcomes are kept as they are.
   Reason: a task group can cancel all of its children or none. Cancelling some needs a handle per job, which is an
   unstructured task, or a shared stop flag, which is shared mutable state. Both are banned (rules 1 and 10), and
   `Synchronization.Atomic` is not available at the package's macOS 11 floor.
6. **`cancelAll()` only when the parent task is cancelled.** Then the helper calls `cancelAll()`, waits for every
   child, and throws `CancellationError`. It returns no outcomes, so no diagnostic is produced, even when a job had
   already failed. A `CancellationError` from a child is never a diagnostic. Reason: a cancelled run has nothing
   to report, and a partial report would depend on timing. Section 5.2 says how the helper notices cancellation.
7. **Each job's input is released when that job ends.** A job is handed its input as a value it owns. Once the helper
   has admitted a job, it keeps no reference to that input: not in its list of jobs, not in a closure it still holds.
   So the last reference to job `i`'s input dies when job `i` returns, on that job's task, before the call returns.
   This holds at width 1 too. Reason: a later pull request hands each root's tree to its output job and needs the
   tree freed on that job's thread. A helper that kept its job list until it returned would keep every tree alive to
   the end of output and free them all on one thread. In PR 2 the call sites still hold the trees themselves, so this
   rule shows only in the helper's own test (section 7, test 7). Make that test pass; do not rely on the call sites.
8. **Width 1 runs in the caller's task.** At width 1 the helper creates no child task. It runs the jobs one after
   another in index order, checks for cancellation before each, and gives the same outcomes as the parallel path.
   Reason: a nested call made by a job of cost 1 must run without asking for a slot anyone else holds, so it cannot
   deadlock; and one-thread runs measure the work without scheduling.
9. **A nested call runs at its caller's cost, on the slots its caller holds.** A job runs with the task-local `width`
   set to its own cost. A call it makes uses that width. While the job awaits its nested call it runs nothing itself,
   so its children use the slots it holds and no others. There is no pool of free slots and no counter two tasks share.
   Reason: a nested call with its own window of `width` would let work in flight grow as `width` to the power of the
   nesting depth; one window shared by all calls would deadlock when a job holding a slot waits for its children.
   Lending gives up idle slots in some cases (design 2.3, "What lending gives up"); that is accepted and measured later.
10. **No `@unchecked Sendable`, no `nonisolated(unsafe)`, no lock around a shared reference type.** Parallel work reads
    only `Sendable` values, and the compiler must prove it. Reason: SafeDI's own code is proved safe by the compiler,
    not by review. `.claude/rules/generator-design.md` allows `@unchecked` for a tiny, self-contained concurrency
    primitive. That exception does not apply to the helper or to anything in this PR.
11. **An actor only where tasks share a memo of finished values.** There is none in this PR, so add no actor.
12. **The completion-order knob is for tests.** A task-local hook lets a test hold each job's outcome until the test
    releases it, so tests force completion orders instead of relying on timing (section 5.1). The tool never sets it.

`width` bounds the helper's jobs only. It does not bound the process's threads: Swift's cooperative pool still has one
thread per core, and an `async let` inside a job (the three in a mock output job) can add tasks. Those three are a
stated exception to the bound until a later pull request removes them.

## 5. The helper's public signature (frozen)

Another team writes code against this signature at the same time as you. **Do not change any public name, parameter,
type or default below.** The internals are yours. If you find that the signature cannot work, stop and report why,
with the compiler's output, instead of changing it.

Where design 2.3 left a detail open, it is decided here, marked "decided for this PR".

### 5.1 The declarations

Put them in one new file, `Sources/SafeDICore/Generators/GenerationJobs.swift`. A file under `Generators/` is left out
of the macro target automatically (see `Sources/SafeDIMacros/CLAUDE.md`), so no list needs editing.

```swift
import Foundation

/// One job of a `GenerationJobs` call: the value the job is handed, and the slots it holds while it runs.
public struct GenerationJob<Input: Sendable>: Sendable {
	/// The value the job's work is handed, and owns. The helper keeps no reference to it once it admits the job.
	public var input: Input
	/// The slots the job holds while it runs. A nested call the job makes runs at this width.
	public var cost: Int

	public init(_ input: Input, cost: Int = 1)
}

/// The bounded, ordered fan-out through which every task group in SafeDICore runs.
public enum GenerationJobs {
	/// The width of a call made in this task: the most cost its jobs may hold in flight at once. The process's width is
	/// the active processor count. Each job runs with its own cost as its width.
	@TaskLocal public static var width: Int = ProcessInfo.processInfo.activeProcessorCount

	/// Called, when set, with a job's path after the job's work returns or throws and before the helper collects its
	/// outcome. A path is the job's index at each nesting level of the helper, outermost first. Set by tests, which
	/// force an order of completion with it; never by the tool.
	@TaskLocal public static var completionObserver: (@Sendable (_ path: [Int]) async -> Void)?

	/// Runs every job of `jobs`, and returns each job's result, in the order of `jobs`.
	/// - Throws: `CancellationError`, and nothing else, when the calling task is cancelled. Then it returns nothing.
	public static func results<Input: Sendable, Success: Sendable, Failure: Error>(
		of jobs: consuming [GenerationJob<Input>],
		_ work: @escaping @Sendable (consuming Input) async throws(Failure) -> Success,
	) async throws -> [Result<Success, Failure>]

	/// Runs the jobs of `jobs` in order, admitting none after the first failure it collects, and returns each job's
	/// result in the order of `jobs`: `nil` for a job it never admitted.
	/// - Throws: `CancellationError`, and nothing else, when the calling task is cancelled. Then it returns nothing.
	public static func resultsStoppingAtFirstFailure<Input: Sendable, Success: Sendable, Failure: Error>(
		of jobs: consuming [GenerationJob<Input>],
		_ work: @escaping @Sendable (consuming Input) async throws(Failure) -> Success,
	) async throws -> [Result<Success, Failure>?]
}
```

### 5.2 The behavior, point by point

Each point is the design's (2.3), unless marked "decided for this PR".

- **Width.** A call's width is `GenerationJobs.width` in the task that calls it. Decided for this PR: a width below 1
  counts as 1. No trap: shipped code never traps (`CLAUDE.md`, "No traps in shipped code"), and a width of 0 must not
  wait forever either.
- **Cost.** A job's cost is a whole number from 1 to the call's width. Decided for this PR: a cost below 1 counts as 1,
  and a cost above the call's width counts as the width.
- **Admission.** In index order, only while the costs in flight plus the next job's cost are at most the width.
  Never past a waiting job.
- **Running a job.** With `GenerationJobs.width` set to the job's cost and its path set to the caller's path plus its
  own index, for the whole of its work.
- **Outcomes.** One per job, in index order.
- **Stopping.** Design 2.3 names a flag, `stopsAtFirstFailure`. Decided for this PR: it is the second function,
  `resultsStoppingAtFirstFailure(of:_:)`, whose `nil` is the design's "not admitted". Reason: a call that never stops
  then has no "not admitted" case to handle, so its callers carry no branch that no input can reach (coverage stays
  at 100% without dead code).
- **Failures are typed by the work.** Decided for this PR: the work's thrown type is generic (`Failure`). Work that
  cannot throw gives `Result<Success, Never>`, so its callers have no failure case to handle. Work that throws
  untyped errors gives `Result<Success, any Error>`.
- **The helper throws only `CancellationError`.** Decided for this PR: its own `throws` is untyped, documented as
  `CancellationError` only. Reason: it keeps the declaration simple across Swift 6.2 and later compilers.
- **The parallel path's group.** Decided for this PR: the helper uses a non-throwing `withTaskGroup` whose children
  return the job's `Result`, never throw. So one job's failure never cancels another job, implicitly or otherwise.
- **Cancellation.** Decided for this PR, how the helper notices it:
  - It admits each job with `addTaskUnlessCancelled`. When that refuses (the calling task is cancelled), the helper
    admits nothing more, calls `cancelAll()`, waits for every child, and throws `CancellationError`.
  - After the last child is collected, it checks `Task.isCancelled` once more. A cancelled call never returns outcomes,
    even when every job finished.
  - At width 1 it checks `Task.isCancelled` before each job and after the last one.
  - Children inherit the cancellation of the calling task. A job's own work may notice it; whatever the job then
    returns or throws is discarded with the rest, since the call throws `CancellationError`.
  - Leaving the call always awaits every child, so no job outlives the call that started it.
- **Width 1.** In the caller's own task, no child task, jobs in index order, a cancellation check before each job.
  The completion observer is called after each job here too. Decided for this PR: only a width of 1 takes this path.
  A call at a width above 1 uses child tasks, even for a single job.
- **Input release.** As rule 7 of section 4. The work takes its input as `consuming`. Design 2.3 notes that it is not
  known whether a task-group child frees what its closure captured when the child ends, or only when the group does.
  Write the plain form first (the child's closure captures the job's input and consumes it into the work). If the
  release test (test 7) shows the input freed on the collecting task, or after the call returns, use this route,
  decided for this PR, and no other:
  - Put the input in a box: a `final class` that is not `Sendable`, made fresh for each job, whose only stored property
    holds the input.
  - Hand the box to `addTaskUnlessCancelled`'s closure. Swift 6's region-based isolation lets a closure that is sent to
    a child take a non-`Sendable` value nobody else references.
  - In the child, move the input out of the box before the work runs, with `swap` into a local and `consume` into the
    work, the pattern `Sources/SafeDICore/Utilities/DeferredRelease.swift` describes for its callers. Then the box is
    empty, whenever the closure itself is freed.
  - Write it so no branch is unreachable: for example, a box that holds an array of one input, which the child drains
    with a loop, rather than an optional the child must unwrap with an `else` no input reaches. Coverage counts that
    `else` (section 7), and a force unwrap is a trap (`SourceRuleTests`).
  - Not `@unchecked Sendable`, not `nonisolated(unsafe)`, not a lock, not an actor (rules 10 and 11).
  If neither form passes test 7 on Swift 6.2, stop and report it with the test's output. Do not weaken the test.
- **The completion observer** receives the job's path. Decided for this PR: the helper keeps the current path in a
  task-local of its own (not public), empty outside any job.

### 5.3 The five call sites

- Every site calls `results(of:_:)`, never the stopping form: across roots, every job runs to its own outcome, and no
  root is stopped because another failed.
- Every job has cost 1. Decided for this PR: no unit makes a nested call yet, so cost 1 is what the design's cost rule
  gives ("With as many similar units as slots, or more, every cost is 1").
- Keep what each site does after its group exactly as it is today, and add no sort. Today the capture walk and the
  `Sendable` configuration union build sets, DOT sorts its strings, the mock output site sorts its roots by type right
  after the group, and the production output site does not sort at all (the tool sorts the generated code later, in
  `GenerateCommand.swift`). With the helper, every site receives its outcomes in job order instead of completion order;
  nothing downstream may come to depend on that.
- Your jobs are in the order the sites list them today: production roots in the order of `rootScopeGenerators`, mock
  roots in the order of `mockRoots`, which the loop above builds in sorted type order.
- **DOT.** Decided for this PR: remove `throws` from `ScopeGenerator.generateDOT()` (`ScopeGenerator.swift`, about line
  2858). It contains no `throw`, only recursive calls of itself. Its jobs then have `Failure == Never`, and the DOT site
  has no failure branch for coverage to find unreached. `generateDOTTree()` keeps its own `throws`, which the
  `rootScopeGenerators` getter needs.
- **The `@Sendable` capture walk and the `Sendable` configuration union** cannot throw, so their jobs have
  `Failure == Never` too.

### 5.4 Which error the output sites report (the fix)

This is decided for this PR, from design 2.2 ("What a job's failure is") and 5.2, and the repository's own rule
(`CLAUDE.md`, "Diagnostics are chosen by source location, never by name order").

After the helper returns, the production output site and the mock output site look at every failure, in index order,
and sort each into one of three kinds:
1. A `DependencyTreeGeneratorError`: taken as it is.
2. Any other error that conforms to `SourceLocatedError`: wrapped in `DependencyTreeGeneratorError.sourceLocated(_:)`
   (`DependencyTreeGenerator+Errors.swift`, about line 114), as the seam loop already does
   (`DependencyTreeGenerator+SeamDriver.swift`, about lines 679 to 681). That case reports the wrapped error's own
   diagnostics, so a run with one such failure prints the same bytes as today.
3. An error with no source location (neither of the above).

Then:
- If there is no failure of kind 3, they throw `DependencyTreeGeneratorError.reportingAll(of:)` of every failure of
  kinds 1 and 2, which joins them in source order. So every failing root reports its own error.
- If there is a failure of kind 3, they throw the kind-3 failure of the lowest job index, and report nothing else.
  The job order is the roots' type order, which is a name order; that is the design's stated exception, for an error
  type no output job is known to throw. Write a comment at both sites saying so.
- A failure is never a `CancellationError`: the helper throws that itself (section 4, rule 6).

Whichever path runs, neither which error is reported nor its text may depend on completion order.

## 6. The phase timer (the first commit)

**What it does.** When the environment variable `SAFEDI_PHASE_TIMES_OUTPUT` names a file, `generate` writes one line
per span of the run to that file. When it is unset or empty, nothing is written and nothing is measured.

**How it is built.** Decided for this PR, all of it:
- In `SafeDICore`, in a new file under `Generators/` that follows `CodeTaskObservation.swift`:

  ```swift
  /// The phases of a generation run whose time `SAFEDI_PHASE_TIMES_OUTPUT` records. Later pull requests may split a
  /// span into these phases, never rename one.
  public enum GenerationPhase: String, Sendable, CaseIterable {
  	case validation = "validation"
  	case signatures = "signatures"
  	case productionConstruction = "production construction"
  	case mockPlans = "mock plans"
  	case mockConstruction = "mock construction"
  	case wholeModuleGates = "whole-module gates"
  	case productionOutput = "production output"
  	case mockOutput = "mock output"
  	case dot = "DOT"
  }

  public enum GenerationPhaseObservation {
  	/// Called, when set, as a span of `phases` starts. The closure it returns is called as that span ends, whether
  	/// the span returns or throws. Set by `generate` when `SAFEDI_PHASE_TIMES_OUTPUT` names a file, and by tests.
  	@TaskLocal public static var observer: (@Sendable (_ phases: [GenerationPhase]) -> @Sendable () -> Void)?
  }
  ```

- A span is bracketed as `let end = GenerationPhaseObservation.observer?(phases)` followed by `defer { end?() }`.
  This works in the synchronous `rootScopeGenerators` getter and in async functions alike, and with no observer set
  it costs one task-local read.
- In `SafeDIToolLibrary`: reading the variable, the clocks and the file. The observer `generate` installs reads the
  clocks when a span starts and returns a closure that captures those start readings as immutable values; that
  closure reads the clocks again and writes the span's line. So no reading is shared mutable state, and no lock,
  `@unchecked`, `nonisolated(unsafe)` or actor is needed (section 4, rules 10 and 11).
- The file: opened once, when `generate` starts and the variable names a file, with
  `open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)`, and closed when `generate` ends, whether it returns or throws.
  Each line is one `write` call on that descriptor, so lines from several processes sharing one file never interleave.
  Do not use `FileHandle`'s seek-then-write, which is not atomic across processes. If `open` fails, no observer is
  installed, no line is written, and `generate` goes on as it would without the variable. A test covers that
  (section 7, test 8).
- System calls: import the C library as `UnreadTypeComment.swift` (lines 21 to 27) and `DeferredRelease.swift` do
  (`Darwin`, else `Glibc`, else `Musl`). On Linux, `getrusage`'s first argument is likely `RUSAGE_SELF.rawValue`, since
  Glibc imports `RUSAGE_SELF` as an enumeration case. We have not compiled it there; list any line that only one
  platform compiles in your report (section 7).

**The spans.** PR 2 brackets exactly these, at these places, and no others. Decided for this PR: spans never nest.
In `DependencyTreeGenerator.generatePerRootCodeTrees()`:
1. `validation + signatures + production construction`: the line `let rootScopeGenerators = try rootScopeGenerators`.
   The getter (`DependencyTreeGenerator.swift`, about line 381) validates, computes seam signatures and builds the
   production trees in one pass, so these three phases are one span in PR 2. Do not split them, and put no bracket
   inside the getter: `generateDOTTree()` evaluates the getter again, inside the `DOT` span.
2. `whole-module gates`: `validateFills`, `validateSendableBuildersCaptureNoNonSendableWrapper` and
   `validateNoSeamTierOmitsProvidedValue`.
3. `production output`: from the output group to the function's return.

In `DependencyTreeGenerator.generateMockCode(…)`:
4. `mock plans + mock construction`: from the function's start (the `mockScopes(…)` call) through the throw of
   `reportingAll(of: mockRootErrors)`, so the loop that plans and builds each mock root in turn and the checks of other
   modules' public mocks that follow it are in this span.
5. `whole-module gates`: `validateFills` and `validateSendableBuildersCaptureNoNonSendableWrapper`.
6. `mock output`: from `computeCycleEdges` to the function's return. The third whole-module gate,
   `validateConfigurationsAreBuiltOneWay`, runs inside this span and has no line of its own in PR 2.

In `DependencyTreeGenerator.generateDOTTree()`:
7. `DOT`: the whole function, which validates and builds the production trees again before it writes the graph.

A span writes its line whenever its code runs, even when it finds nothing to do. A span whose code does not run (no
mocks are generated, no DOT file is asked for) writes no line. Parsing, module info, warnings and writing files have
no line. Do not add phase names.

So a run that generates production code, mocks and a DOT file writes these seven lines, in this order:

```
validation + signatures + production construction
whole-module gates
production output
mock plans + mock construction
whole-module gates
mock output
DOT
```

A name may repeat in one run (`whole-module gates` does); a reader sums the lines of one name.

**The line.** One line per span, written when the span ends:

```
<name>\t<wall seconds>\t<CPU seconds>\t<peak RSS bytes>\n
```

- `<name>`: the span's phases' raw values joined by ` + `, in the order of the enumeration.
- `<wall seconds>`: from the monotonic clock (`clock_gettime(CLOCK_MONOTONIC)`), end minus start, six decimal places.
  Not `ContinuousClock`, which needs macOS 13; the package supports macOS 11.
- `<CPU seconds>`: the process's CPU over the span, from `getrusage(RUSAGE_SELF)`, user plus system time, end minus
  start, six decimal places.
- `<peak RSS bytes>`: the process's peak resident size at the span's end, from the same `getrusage` call, as a whole
  number of bytes. `ru_maxrss` is in bytes on macOS and in kilobytes on Linux; convert.
- Example: `production output	0.412345	2.103456	134217728`

**What the timer cannot claim yet.** The process's CPU over a span is that span's CPU only when no task outlives the
span that started it. Before later pull requests, two kinds do: a production generator starts its code on a detached
task when it is created, so production output's CPU is partly charged to production construction; and a mock root's
parameter tree runs on an unstructured task started by its first reader, in construction or in output. So PR 2 claims
no span's CPU is clean. Wall per span is exact. Your test does not assert that no task outlives a span. Say this in
your report.

**Reading the variable in tests.** Tests run in parallel in one process, so no test may set the process's environment.
Decided for this PR: read the variable through a parameter that defaults to `ProcessInfo.processInfo.environment`
(or an equivalent seam), so that the line that reads it runs in an in-process test.

## 7. The tests owed

Write each test before the code that makes it pass. Names follow the repository's `method_expectation_conditionUnderTest`
pattern. Test 1's name is given; the others' names are yours. Keep each behavior exactly.

**Where they go.** The helper's tests go in `Tests/SafeDICoreTests`. Tests that run `generate` go in the
`SafeDITool` test target whose subject they test (`CLAUDE.md`, "`SafeDITool`'s tests span five test targets"):
production output and test 10 in `SafeDIToolDependencyTreeTests`, mock output in `SafeDIToolMockTests`, the phase
timer in `SafeDIToolTests`. Take every temporary path from `TestTemporaryDirectory`, never the system temporary
directory.

**Every test sets the width.** Each test that runs the helper or `generate` with forced orders sets
`GenerationJobs.width` itself, with `GenerationJobs.$width.withValue(…)`. No test's outcome may depend on the default
width, which differs from machine to machine.

**Forcing completion orders.** Every test that depends on completion order forces it with
`GenerationJobs.completionObserver`, never with sleeps or timing. A test-side actor that holds each completing job
and releases held jobs in a chosen order is a good shape. Two limits:
- A releaser may wait only for jobs the helper has already admitted. At width 4, a job past the first four is admitted
  only after a held job is released, so "release in reverse order of all twenty" deadlocks there. At a width below the
  job count, force orders among the jobs in flight: wait until every job that must be in flight is held (for twenty
  cost-1 jobs at width 4 that never stop, `min(4, 20 - released)`), then release the one your order picks (the highest
  index for "reverse", a seeded draw for the others).
- A full order over every job (index, reverse, seeded) needs a width of at least the job count.
At width 1 jobs complete one at a time in the caller's task, so a test there can only release them in index order.

The seven tests of design 5.2 (1 to 7):

1. `resultsStoppingAtFirstFailure_admitsNoLaterJob_whenOneOfTwentyJobsFails`: twenty jobs in one stopping call; job
   `i` fails. Run it at width 4, with orders forced among the jobs in flight (reverse, and several drawn by seed), and
   at width 1. No job above `i` is admitted after `i`'s failure is collected; every job below `i` has an outcome; the
   lowest failing index's error is the one a caller would report. Run it for several values of `i`, including the
   first and the last.
2. Two units, each making a nested stopping call: a failure in one stops no job of the other.
3. **Nesting at width 1, two levels:** three units, each making a nested call over three jobs. The run finishes; at no
   instant do two tasks run job code; all nine outcomes are in index order; no child task is created. Check the last by
   having each job record its task (`withUnsafeCurrentTask`) and asserting that every job ran in the caller's task.
4. **Nesting with costs, at width 4:** twenty units with costs drawn from 1 to 4, each making a nested call over twenty
   jobs, completion orders forced among the jobs in flight. At every instant the costs in flight in the outer call sum
   to at most 4, the jobs running in each unit's nested call are at most that unit's cost, and the tasks running job
   code are at most 4. A unit of cost 3 waiting behind a free slot count of 2 is not passed by a later unit of cost 1.
5. **Two roots that throw during output: both are reported, in source order.** Name the two roots so that type order
   and source order disagree. Write it for production output and for mock output.
6. **Cancellation, at width 4 and again at width 1:** the parent is cancelled mid-call. Every job that started has
   finished when the helper returns; no later job starts; the helper throws `CancellationError`; and no diagnostic is
   produced, even when a job had already failed. To cancel mid-call deterministically: run the helper call inside a
   test-side task group, hold a job in the completion observer, call that group's `cancelAll()`, then release the held
   job.
7. **Release:** three jobs whose inputs are objects with an observed `deinit`, at width 1 and at width 4 with
   completion orders forced (index, reverse, and a seeded order). Each input's `deinit` has run when its job's outcome
   is collected, on the task that ran the job, and before the call returns. At width 1, input 0's has run before job 1
   starts. (At width 1 "the task that ran the job" is the caller's task; that is expected.)

Then three more:

8. **The phase timer.** Run `generate` in-process with the variable naming a file under `TestTemporaryDirectory`, on
   a fixture with production roots, a seam, a mock and a DOT file. Assert the exact seven names of section 6, in order;
   that each line has four tab-separated fields; that wall and CPU parse as non-negative numbers and peak RSS as a
   positive whole number. A second test: with the variable unset, no file is written. A third: with the variable
   naming a file in a directory that does not exist, `generate` succeeds and writes its output as without the variable.
9. **The output error fixture (the fix).** At least twenty roots whose output jobs throw, in one module, for production
   output and again for mock output, named so that type order and source order disagree, at a width of at least the
   number of roots. Completion orders forced: index order, reverse order, and at least five orders drawn by seed. The
   reported diagnostic is byte for byte the same in every order, and is section 5.4's. Twenty candidates is the
   repository's rule for any test of choice-making code: fewer lets a wrong order pass by luck (`CLAUDE.md`,
   "Determinism"). Cover each kind of section 5.4: `DependencyTreeGeneratorError`s; other `SourceLocatedError`s, which
   are wrapped and joined with the first kind; and errors with no location, of which the lowest index's is thrown, in
   every order.
10. **Bytes at every width.** Run `generate` in-process on one fixture with several production roots, a seam and
    several mock roots, at widths 1, 2 and 32, and assert that the generated files and the `.safedi` file are byte for
    byte the same at each width.

**Making output throw (tests 5 and 9).** We searched and found no `throw` that an output job reaches on valid input,
so we expect you to need a test hook. Check that briefly: valid means input the `@Instantiable` macro accepts
(`CLAUDE.md`, "Code generation tests should only test paths where the macro would not emit an error"). If you find
some, use it, and say so in your report (see "fuzzer" below). If you find none, say so, with the check that rejects
each candidate you tried (file and line), and make the failure through a task-local test hook that the tool never sets:
an optional closure that each output job calls with its root's type before it generates, and that may throw. That has
a precedent: `seamSignatureComputationLimitOverride` in `DependencyTreeGenerator+SeamDriver.swift` exists so a test
can reach a branch no input reaches. Keep the hook as small as the completion observer. Declare the errors it throws
in test code, not under `Sources/SafeDICore`: `SourceRuleTests` fails on any error type declared there that
`ErrorReportingSite.byErrorType` does not list.

**Repeat the order-sensitive tests.** Our CI runs the suite five times in separate processes to catch
nondeterminism. You have no CI, so run every test you added five times, each run a process of its own (section 9,
gate 1).

**The repository's standing bars, which apply to this PR as to any other:**
- **100% line coverage of every added or changed line under `Sources/` and `Plugins/`.** A line no test runs is
  covered by a new test or removed. Check it with gate 1's coverage command. Our CI unions macOS and Linux; you can
  check one platform, so list in your report any line that only the other platform compiles (inside `#if os(Linux)`
  or `#elseif canImport(Glibc)`, for example), and why it is right.
- **`SourceRuleTests` passes.** It runs in the full suite. It fails on any trap in shipped code (force unwrap, `try!`,
  `as!`, `fatalError`, `precondition`, `assert` and others: `.claude/rules/source-rules.md`), on `try?` under
  `Sources/SafeDICore/Generators`, on an unlisted error type under `Sources/SafeDICore`, and on a straight apostrophe
  between letters in a string literal.
- **Formatting:** `./CLI/lint.sh`, in its own last commit (section 8).
- **The fuzzer's pins are unchanged** (gate 3). PR 2 makes the generator accept or emit no new shape, so it owes no
  new fuzzer draw. But if you find valid input that throws during output, the fix repairs a defect a real input
  reaches, and the repository asks for a fuzzer roll that fails without the fix: read "Drawing a change" in
  `.claude/rules/fuzzer-corpora.md`, add the roll if the fuzzer can draw the shape, or say in your report why it cannot.
  We run the fuzzer's coverage report ourselves on the hand-back.

## 8. Commits

One pull request's worth of commits on `trial-base`, in this order:
1. The phase timer and its tests.
2. The helper and its tests.
3. The five call sites, the output error fix and its tests, and the width test. One commit, or one per site; your
   choice.
4. Formatting: only what `./CLI/lint.sh` changed, nothing else.

Commit messages: what changes and why, in plain words, for a reader of `git log` a year from now. No local paths, no
abbreviations (`dependency`, not `dep`), no history of how you got there.

## 9. The gates, in order

Commit everything before you run the gates. Then set these once, in every shell you use. The names are chosen so
that none is a variable the benchmark skill reads; do not export `W`, `T`, `FX`, `L`, `WORK`, `ROUNDS`, `STEPS` or
`SHAPES` in a shell you run it from.

```bash
export REPO="$(git rev-parse --show-toplevel)"     # the repository from the zip
export SCRATCH="$HOME/Library/Caches/safedi-pr2"   # on Linux: "${XDG_CACHE_HOME:-$HOME/.cache}/safedi-pr2"
export BENCH="$HOME/Library/Caches/SafeDIBenchmarks" # on Linux: "${XDG_CACHE_HOME:-$HOME/.cache}/SafeDIBenchmarks"
export BASE="$(git -C "$REPO" rev-parse trial-base)"
export HEAD_SHA="$(git -C "$REPO" rev-parse pr2)"
mkdir -p "$SCRATCH/swiftpm-tmp" "$SCRATCH/tests"
export TMPDIR="$SCRATCH/swiftpm-tmp" SAFEDI_TEST_TEMPORARY_DIRECTORY="$SCRATCH/tests"
```

`SCRATCH` and `BENCH` are outside the system temporary directory and outside the checkout. `CLAUDE.md` explains why:
SwiftPM leaves folders in `$TMPDIR` on every command, macOS empties the system temporary directory at boot (millions
of leftover entries once kept a Mac at the Apple logo for hours), and test fixtures written inside the checkout would
be read as part of the project. `BENCH` is where the benchmark skill keeps its own worktree, tools, fixtures and logs.

Every command below that writes a log ends it with a line `exit status N`, the command's own status, because a pipe
into `tee` hides that status. Read that line, not the pipe's.

If you amend a commit, set `HEAD_SHA` again and rerun the gates from gate 1.

**Gate 1: build and the full suite.**

First at the base, so you know which tests fail there already on your machine:

```bash
cd "$REPO" && git switch --detach "$BASE"
{ swift test --traits sourceBuild; echo "exit status $?"; } 2>&1 | tee "$SCRATCH/suite-base.log"
git switch pr2
{ swift test --traits sourceBuild; echo "exit status $?"; } 2>&1 | tee "$SCRATCH/suite-head.log"
```

Passing: the head's log ends in `exit status 0`, and its Swift Testing summary line (`Test run with N tests ...
passed`) reports no issue. If a test fails at the base too, on your machine, it may fail identically at the head;
list it. No other test may fail. The head runs more tests than the base, by the tests you added.

Then every test you added, five times, each run a process of its own (name your own suites in the filter):

```bash
for run in 1 2 3 4 5; do
  { swift test --traits sourceBuild --filter '<your new suites, joined with |>'; echo "exit status $?"; } 2>&1 \
    | tee "$SCRATCH/repeat-$run.log"
done
```

Then coverage of the changed lines:

```bash
{ zsh Scripts/changed-line-coverage.sh "$BASE"; echo "exit status $?"; } 2>&1 | tee "$SCRATCH/coverage.log"
```

Passing: the line before `exit status 0` reads `0 changed line(s) no test executed`. It runs the suite in a release
build with coverage, which takes a while.

While you work, `python3 -I .claude/skills/verify-touched/verify-touched.py "$BASE"` runs only the suites your change
reaches, and is much faster. It does not replace the full suite.

**Compilers.** Use Swift 6.2 for at least one full build and suite run before you hand back. On macOS that is Xcode
26's Swift 6.2: select Xcode 26 with `xcode-select` or `DEVELOPER_DIR`. On Linux, a Swift 6.2 toolchain from
swift.org. The repository's 2.x releases build with Swift 6.2, and newer compilers accept code that 6.2 rejects.
`CLAUDE.md` lists two such cases: an actor's `lazy var` (which fails only with Xcode 26's Swift 6.2, so a Linux 6.2
build does not catch it) and long expressions joined with `+`. If you cannot get Swift 6.2, say so in your report and
which compilers you used; do not stop.

`./CLI/lint.sh --check` must also exit 0 at your head.

**Gate 2: byte identity.**

First, which existing test lines changed:

```bash
cd "$REPO"
{ STEPS=tests BASE="$BASE" HEAD="$HEAD_SHA" bash .claude/skills/generate-benchmark/run-gate.sh; echo "exit status $?"; } 2>&1 \
  | tee "$SCRATCH/gate2-tests.log"
```

It runs `Scripts/byte-identical-gate.sh`, which prints `passed` when the change only adds lines under `Tests/`, and
`FAILED` with each file when any existing line under `Tests/` was deleted or modified. Do not read its exit status:
the skill does not pass it on. Read the output (also in `$BENCH/gate-$HEAD_SHA/tests-diff.txt`):
- An existing expectation that changed (an expected generated file, an expected diagnostic, a fuzzer pin) is a failure.
  Stop and report it.
- The script cannot tell an expectation from other test code, so an edit to a test helper or a comment (for example
  in `Tests/SafeDIToolTestSupport`), or a line your formatting commit rewrote, also prints `FAILED`. That is allowed.
  List each such line in your report with what it is, from `git diff "$BASE" "$HEAD_SHA" -- Tests`.

Second, the tool's output on the gate's shapes is byte for byte the same. This builds the three tools and the
fixtures that gate 4 reuses, then runs the base's and your head's tool once on every shape and compares their files:

```bash
cd "$REPO"
{ ROUNDS=1 STEPS=generate SHAPES=issue646-12,N5i-8 BASE="$BASE" HEAD="$HEAD_SHA" \
    bash .claude/skills/generate-benchmark/run-gate.sh; echo "exit status $?"; } 2>&1 | tee "$SCRATCH/gate2-tools.log"
rm -rf "$SCRATCH/bytes"
python3 -I .claude/skills/generate-benchmark/stage2.py --runs 1 "$BENCH/fixtures" "$SCRATCH/bytes" \
  BASE="$BENCH/tools/SafeDITool-$BASE" HEAD="$BENCH/tools/SafeDITool-$HEAD_SHA" > "$SCRATCH/bytes.log" 2>&1
for shape in $(ls "$BENCH/fixtures"); do
  diff -r -x '*.log' -x '*.csv' "$SCRATCH/bytes/$shape/BASE" "$SCRATCH/bytes/$shape/HEAD" > /dev/null \
    && echo "$shape identical" || echo "$shape DIFFERS"
done | tee "$SCRATCH/bytes-diff.log"
```

The first command is the skill's own check run (one round of two small shapes; it is a check that the scripts and
tools work, not a verdict). Passing for the second half: thirteen lines, every one `identical`, and `bytes.log` has no
line that contains `BASE rejected` or `HEAD rejected`. A shape the base or your head rejects is a failure, even though
the gate script would only leave it out. (The `.csv` files name their own folder, so they differ by design; the
generated files and `.safedi` files are what is compared.)

**Gate 3: the fuzzer's pins.**

The graph fuzzer generates three corpora of graphs and pins how many it accepts, their seeds' sum and hashes of the
fixtures. A change to generated output or to which graphs are accepted moves a pin. PR 2 must move none. The pins in
the repository were recorded on Linux, so run each corpus at the base and at your head, and compare the two:

```bash
cd "$REPO"
for side in base head; do
  if [ $side = base ]; then git switch -q --detach "$BASE"; else git switch -q pr2; fi
  { zsh Scripts/fuzz-corpus.sh --iterations corpus; echo "exit status $?"; } 2>&1 | tee "$SCRATCH/pins-$side-corpus.log"
  { zsh Scripts/fuzz-corpus.sh --features generateDependencyTree --iterations corpus; echo "exit status $?"; } 2>&1 \
    | tee "$SCRATCH/pins-$side-seam-corpus.log"
  { zsh Scripts/fuzz-corpus.sh --features generateMockPublic --iterations corpus; echo "exit status $?"; } 2>&1 \
    | tee "$SCRATCH/pins-$side-public-mock-corpus.log"
done
git switch pr2
```

Each command runs the whole corpus and checks its pins itself, then prints a line `--- pins (report: ...)` and the
pin lines. Passing: for each corpus, your head's `exit status` equals the base's, and its lines after `--- pins` that
start with `shard`, `seeds`, `corpus` or `problem` are the same as the base's, line for line. (The `cpu` line is a
cost measure and differs between runs.) On a machine where the base passes, that means every command exits 0 and no
line starts with `problem`. These are long runs (on CI the three corpora take about 100 minutes of runner time in ten
shards, and here you run them twice); run them one after another, not at once. If your head's pins differ from the
base's, stop and report both logs: do not update a pin.

**Gate 4: the performance gate (stage 2).**

The benchmark skill measures `SafeDITool generate` on thirteen synthetic shapes, the base against your head against
SafeDI 2.2.0, and judges your head against the base. Read `.claude/skills/generate-benchmark/SKILL.md` first: it
names the shapes, the steps and the variables. It builds 2.2.0's tool from the tag itself (gate 2 already did), keeps
everything under `BENCH`, works in a worktree of its own there, and never touches your checkout.

The suite step fills a file of passed compile checks at the base, and your head's run then adds its own passes to
that same file. So remove the file before every run of this gate, or a second run reads your head's passes as the
base's:

```bash
cd "$REPO" && rm -rf "$BENCH/passed-$BASE"
{ BASE="$BASE" HEAD="$HEAD_SHA" bash .claude/skills/generate-benchmark/run-gate.sh; echo "exit status $?"; } 2>&1 \
  | tee "$SCRATCH/run-gate.log"
```

Run it on a quiet machine (gate 5), in the background: the whole gate takes a few hours (three debug suite runs and
15 rounds of three tools on thirteen shapes). Its logs are in `$BENCH/gate-$HEAD_SHA/`: `tests-diff.txt`,
`suite-base-fill.log`, `suite-base-second.log`, `suite-head.log`, `tool-*.log` and `stage2.log`.

What it does, in order:
1. `tests`: gate 2's first half again.
2. `suite`: the suite without the fuzzer's tests, in a debug build, three times: twice at the base, the first filling
   the passed-compile-check file, then once at your head reading it. A compile check whose generated code did not
   change is skipped at the head, so the head's `Compile checks:` line counts the checks whose generated code changed
   or is new, and the head's log names them. Passing:
   - every check the head compiles belongs to a test you added;
   - the head's `Value comparison programs:` count of programs compiled is the base's second run's plus your new
     tests' (a program that fails to compile is never kept, so it compiles on every run; compare with the base's
     second run, never with 0);
   - the head fails exactly the tests the base's second run fails in this mode (some tests fail there already: those
     that test the passed-check file itself, and a few that measure time), no more.
3. `generate`: `stage2.py`, 15 rounds per shape, the three tools in a rotated order each round.
4. The verdict table, then `GATE PASSED` or `GATE FAILED on <shapes>`.

The script's exit status is the `generate` step's only. Read each step's lines yourself.

How to read the verdict. Each row is one shape. It compares your head with the base (`HEAD/BASE`), on medians of 15
rounds (minimums for `N1-200`, whose runs are few and long). The band, from `bands.json`:
- CPU and peak memory: at most 3% over the base.
- Wall: at most the shape's own run-to-run spread over the base, which is between 3% and 6%; 3% for a shape
  `bands.json` does not list (the four `E6d` shapes).
- A row whose wall is inside its band but whose CPU is more than 3% over fails on CPU.

PR 2 changes no output and adds a helper, so every shape must pass: at or under the base, within the band. And a
shape the base or your head rejects has no verdict, so the table can say `GATE PASSED` without it: any table row
`| <shape> | BASE | rejected` or `| <shape> | HEAD | rejected` is a failure (gate 2 should already have caught it).

The bands were measured on a Linux cloud machine. On another machine, read the spreads the verdict table gives
(range over median). When a wall or CPU failure comes with spreads several times the band, the machine was not quiet
enough to judge it: rerun on an idle machine before you believe it, as `SKILL.md` says. Peak memory repeats within
about 2% between runs, so a memory failure is real when the two tools' ranges do not overlap. We read the gate again on
Linux from your commits.

To rerun one shape, copy `$BENCH/gate-$HEAD_SHA/stage2.log` aside first (the rerun replaces it), then:

```bash
{ STEPS=generate SHAPES=<shape> BASE="$BASE" HEAD="$HEAD_SHA" bash .claude/skills/generate-benchmark/run-gate.sh; \
  echo "exit status $?"; } 2>&1 | tee "$SCRATCH/rerun-<shape>.log"
```

Report both runs.

**Against 2.2.0.** The first table also gives 2.2.0's medians (`V220`). Compare your head with 2.2.0 only on the
shapes a 2.2.0 user can write: `issue646-12`, `issue646-16`, `issue646-mock-12`, `N5inline-8`, `N5inline-10`,
`E6d-600-inline` and `E6d-1200-inline`. 2.2.0 rejects `N1-40` and `N1-200`; its figures on the `N5i` and seam `E6d`
shapes are not a build a 2.2.0 user has, so ignore them. Your head may be slower than 2.2.0 on some shapes, as the
base already is. Report every one of those seven shapes where your head's median is above 2.2.0's, with the ratio. A
pass against the base that is over 2.2.0 is reported, never left out.

**What this gate does not cover.** It uses public synthetic shapes only. On the hand-back we measure further
ourselves: on other shapes, against an earlier fixed commit as well as the base, and with Swift's concurrency pool held
to one thread. You do not run those.

**Gate 5: a quiet machine.** The stage 2 gate interleaves the tools round by round, so slow drift affects all three
alike; but other load still widens every range and can fail a shape. While gate 4 runs: no other builds, test runs or
heavy programs on the machine; plugged in, not in a low-power mode. Say in your report what the machine is (model,
cores, memory, operating system) and whether anything else ran.

When all gates are done, keep the logs you hand back, then delete the rest:
`git -C "$REPO" worktree remove --force "$BENCH/checkout"`, then `rm -rf "$SCRATCH" "$BENCH"`, and the fuzzer's
reports in `SafeDIFuzzReports` beside them in your caches directory.

## 10. What in `CLAUDE.md` does not apply here, and what replaces it

`CLAUDE.md` is written for our own setup. These parts of it assume things you do not have:

- **GitHub workflows** (`verify.yml`, `graph-fuzzer.yml`, `ci.yml`), `gh` commands, "Manage CI without asking", and
  every instruction to dispatch, cancel or read a CI run. Replaced by the gates of section 9.
- **The `pre-review` skill** (`.claude/skills/pre-review`): it dispatches a CI run. Replaced by section 9 and the
  report of section 12.
- **The `apply-fuzzer-pins` skill**: it reads CI's output to move pins. PR 2 moves no pin (gate 3).
- **The `regenerate-expectations` skill**: no existing expectation may change in PR 2 (gate 2).
- **"Check Line Coverage on Linux", `Scripts/unexecuted-lines.py` and `Scripts/fuzzer-coverage-report.sh`**: they
  read CI's reports. Replaced by `Scripts/changed-line-coverage.sh` (gate 1). We run the fuzzer's coverage report.
- **The fuzzer's "Coverage at hand-back" and "Coverage of a change"** (`.claude/rules/fuzzer-corpora.md`): they
  push a branch to CI. We run them on the hand-back.
- **CI's cache of passed compile checks** (`.claude/rules/passed-compile-checks.md`): its workflows are ours. The
  benchmark skill uses a local file of its own (gate 4).
- **"CI settles whether a change compiles" on Swift 6.2**: build with Swift 6.2 yourself (gate 1).
- **"CI runs the suite 5 times on Linux"**: replaced by gate 1's five repeated runs of your tests.
- **Any lock or queue for heavy jobs, if your agent finds one mentioned:** run one heavy job at a time (gate 5).
- **The `PreToolUse` hook that lints before `git push`**: you do not push. Run `./CLI/lint.sh --check` yourself; it
  must exit 0 at your head.
- **"Pull requests"** (titles, descriptions, stacks, landing): you hand back commits, not a pull request. Its rules for
  what to write still apply to your commit messages and your report, including "Found and not fixed" with a plan for
  each item.
- `zsh` runs `CLI/lint.sh`, `Scripts/fuzz-corpus.sh` and `Scripts/changed-line-coverage.sh`. On Linux, install it.

Everything else in `CLAUDE.md` applies: the code style, the source rules, the determinism rules, the testing rules
and the temporary directory rules. The `generate-benchmark` and `verify-touched` skills run locally and apply.

## 11. Determinism rules that touch this PR

Copied from `CLAUDE.md` and design 2.5. Everything SafeDI produces must be identical on every run over the same inputs:
generated code, diagnostics (their text, their order, and which one is reported first), and the bytes of `.safedi`
files.

- "Swift seeds hashing per process, and `Scope` hashes by object identity, so the order of a `Set` or `Dictionary`
  changes between runs. A task group's results arrive in completion order. None of these orders may reach output."
- "When code chooses among candidates or emits a list, use declaration order, source path order, or a sorted order.
  Never use first-found or last-write-wins over an unordered collection."
- "A test of choice-making code needs enough candidates that a wrong order fails on nearly every run: twenty or more,
  or a permutation of six."
- Outcomes are placed by job index. No code path appends in arrival order (design 2.5).
- "Diagnostics are chosen by source location, never by name order." Every root reports the first error its own walk
  finds, and `reportingAll(of:)` joins them in source order.
- Width is an input like any other: output and diagnostics are the same at every width (test 10).

## 12. What to hand back

1. Your commits, as a bundle or as patches. The range starts at `e5536453b`, so it holds the `trial-base` commit too;
   we drop that one:

   ```bash
   git -C "$REPO" bundle create pr2.bundle e5536453b..pr2 && git -C "$REPO" bundle verify pr2.bundle
   # or: git -C "$REPO" format-patch e5536453b..pr2 -o pr2-patches
   ```

2. The full output of each gate: from `$SCRATCH`, `suite-base.log`, `suite-head.log`, the five `repeat-*.log`,
   `coverage.log`, `gate2-tests.log`, `gate2-tools.log`, `bytes.log`, `bytes-diff.log`, the six `pins-*.log`,
   `run-gate.log` and any rerun log; and the whole folder `$BENCH/gate-$HEAD_SHA`, with any `stage2.log` you copied
   aside.
3. A short report:
   - What changed, in plain words, and the output error fix, listed under fixes.
   - What you decided where this brief or the design left something open, with your reason.
   - Whether valid input makes an output job throw (section 7), and what you used instead if not; if it does, the
     fuzzer roll you added or why there is none.
   - Whether the release test needed the box of section 5.2.
   - That no span's CPU is clean, and that your timer test does not assert that no task outlives a span (section 6).
   - For each test of a choice or an order, how many candidates it has.
   - Every changed line only the other platform compiles, if any.
   - Every existing test line that changed (gate 2), with what it is.
   - Every test that fails at the base on your machine (gates 1 and 4), if any.
   - Every one of the seven 2.2.0 shapes where your head is above 2.2.0, with its ratio (gate 4).
   - What you did not verify, and anything you found and did not fix, each with a plan.
   - The compilers, the machine, and how long the work took from start to hand-back, in wall-clock time.

If something in this brief is wrong or cannot be done, stop at that point and say so in the report, with the evidence.
A precise stop is worth more than a workaround we did not ask for.
