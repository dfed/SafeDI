# PR 2 design excerpt: the helper and the phase timer

This file holds the parts of the generator's parallel-construction design note that PR 2 needs. Each part is copied
word for word from the note. Nothing inside a part was reworded. What was left out is listed below, so that you know
where a reference points to text you do not have.

How to read it:
- The handoff (`PR2-HANDOFF.md`) is what binds you. Where this excerpt and the handoff differ, the handoff wins. It
  states every rule in plain words, and the places where it decides something this note leaves open. In particular,
  the wrapping of a `SourceLocatedError` in `.sourceLocated` that 2.2 and 5.2 place in "PR 6b" covers construction
  errors there; PR 2 applies it to output failures only, as handoff section 5.4 says.
- File and line references (`DependencyTreeGenerator.swift:243`) were read at a commit a few commits beneath
  e5536453b. Most still match; where one does not, find the code by the name around it.
- Labels this note uses for things outside PR 2. None of them is your work:
  - "PR 3", "PR 6", "PR 6b", "PR 7b" and the like are later pull requests of the same plan.
  - "E1" to "E6" (with "E6a", "E6b" and "E6d") are stages of the emitter and construction rewrites that those pull
    requests belong to. E1 is already beneath e5536453b.
  - "R0" is a construction memo that lands separately. "S1" is the commit series beneath e5536453b; its head,
    a39c6766a, is an ancestor of e5536453b. "X1" and "X2" are later release checkpoints.
  - "v1", "v2", "v4" and "the first writing" are earlier drafts of this note. "The challenge" is a review of an
    earlier draft.
  - Section numbers this excerpt does not hold (1.2, 1.4, 2.1, 2.4, 3, 4, 6, 8.1, 8.2, 8.5 and others) point into the
    parts left out.
  - "The schedule oracle" (defined in 2.5) and "the sharing oracle" are fuzzer checks later pull requests add. "The
    rename-invariance oracle" is an existing fuzzer check (`CLAUDE.md`, "Determinism").
- Names in capitals (such as SHARE-SUBTREES-FROM-START or EVERY-MOCK-REPORTS) are decisions recorded elsewhere. None of
  them binds PR 2 beyond what the handoff states.
- `measure.py` and "the concurrency lane's harness" are a timing harness of ours that is not in the repository. You
  do not need it: the handoff gives you the scripts to run, and we run the harness ourselves on the hand-back.

Left out, by section:
- Everything before "Words", and sections 0, 1.1 to 1.5, 2.1, 2.2 (except "What a job's failure is"), 2.4, 3, 4, 5.5,
  6, 7.1, 8.1, 8.2, 8.5 and 8.6: they design later pull requests, or (7.1) gate on a benchmark that is not public.
- In 5.2, "Shared waits (from PR 7b)" and "Test (PR 11)": later pull requests.
- In 5.4, every bullet after the third, and the paragraph on where memory regresses: later pull requests, and
  figures measured on a benchmark that is not public.
- In the section 7 introduction, the paragraph that lists the shapes, which include a benchmark that is not public.
  The handoff states PR 2's gates and shapes.
- In 7.2, the paragraphs after "Not verified" (how later pull requests read a phase's speedup).
- In 7.3, every row but PR 2's. In the claims table, every row whose last column does not name PR 2.
- In "What would make this wrong", in 8.3 and in 8.4, every item that is not about the helper or the phase timer.

---

## From the opening: words

Words: a **place** is one position in a generated tree where a value is built. A **world** is one set of scopes: the validated world (every seam inlined), a seam world (a reach of a seam is a call), a mock world. A **declaration map** is one module's view of the declarations: this run's own, one per foreign module whose seams or public mocks are computed, and the callers' view. A **body** is one generated function body. A **job** is one unit of parallel work, with an index. The **driver** is the one task that runs `generate` from top to bottom. The **helper** is the bounded, ordered task-group function of section 2.3. A **unit** is a job that makes helper calls of its own: a body, a mock root, a tree, a component. A **sharing domain** is one set of places that R0's rules let share subtrees: one pass of one tree, or the first passes of the mock roots that read one table of the run's own mock world. A domain never spans two tables. An **entry** is what the actor of 2.4 holds for one memo key. A **sharing handle** is the one value a job is given for one pass of one tree: that tree's table, the actor that pass shares through (or none), and a **front memo**, which holds the candidates built or taken through that handle and nothing else. A handle is never carried to another tree or another pass. A job's **path** is its index at each nesting level of the helper, outermost first; one path **precedes** another when it is lower at the first index where they differ, so a path never precedes its own descendants.

---

## Section 1.6: the concurrency model, phase by phase

### 1.6 The concurrency model, phase by phase

| Phase | Model | State shared between tasks | Why this model |
|---|---|---|---|
| Parsing, module info loading | Task group per file (today's, in `SafeDIToolLibrary`) | none | unchanged; outside the generator |
| Declarations, foreign signatures, the validated world and its walks, mock scope maps, mock root plans, every freeze | Serial, in the driver, on the generator actor | the `Scope` class and validation's identity memos, isolated to the actor and never left half-built across an `await` | order and identity decide diagnostics here; samples say it is cheap (1.4), except signatures (section 3) |
| Own signatures | Serial per component until PR 9; then one job per component of a wave, and chunks of sites inside a seam | none: wave-start values in, overlays out | section 3 |
| Tree construction | Helper jobs over snapshot layers | the finished-subtrees actor of the job's sharing domain, which is never wider than one table (2.4), reached through the job's sharing handle; the handle's front memo is the job's alone, for that one pass of that one tree | the measured cost; independence per section 2.1 |
| Whole-module gates | Serial in the driver, reading finished trees; the one that walks every tree (`@Sendable` captures) as helper jobs | none | they need every tree |
| Planning fragments, spelling chunks | Helper jobs | none | section 4 |
| Naming and numbering | Serial, once per body, inside that body's job | none | order-dependent |
| Sharing finished subtrees | One actor per sharing domain, from PR 7b | finished values, by key and by generator; for a build in flight, its key, its token, its owner's path and its waiters; per key, a "not stored" mark | SHARE-SUBTREES-FROM-START; the one place an actor holds waiters |

Nesting (2.3), by phase:
- output: two levels (a body, then its fragments or chunks);
- construction: one level until PR 11, then two (a tree, then its subtree jobs);
- signatures: one level until PR 9, then three (a component, a seam, a chunk of sites).

A nested call's window is the slots the job that makes it holds. No phase has a pool of slots that tasks share.

Fixed across every phase:
- No `@unchecked Sendable`. No new `nonisolated(unsafe)`. No lock around a shared reference type. No `Task.detached` and no unstructured `Task {`. No stored task: the finished-subtrees actor holds waiters' continuations, never a task (2.4).
- The generator actor stays, as the home of the driver's `Scope` graph. That is where an actor fits: one owner of non-`Sendable` state.
- `ScopeGenerator` stops needing to be an actor once E2–E4 remove its isolated state. Whether it then becomes a final class of `let`s is E5's choice; nothing here depends on it.

---

## From section 2.2: what a job's failure is

*What a job's failure is.* `reportingAll` takes `DependencyTreeGeneratorError`s (`…+Errors.swift:124`), and today's loop catches only that type (`:97`). A tree build can throw another: `ErasedInstantiatorForwardedPropertiesMismatchError`, a plain `SourceLocatedError` (`Models/Scope.swift:1342`, `:2071`), from the first tree (`…+MockRootPromotion.swift:456`) or any later one. Today the first mock root in type-name order that throws it ends `generateMockCode`, and no other root reports. v2's "as today" hid that. Now:
- The job's failure is one of two cases: a `DependencyTreeGeneratorError`, or any other error.
- A `SourceLocatedError` thrown while the tail builds a tree is caught in the job and wrapped in `.sourceLocated` (`…+Errors.swift:114`), as the seam loop already does (`…+SeamDriver.swift:679–681`). It is then that root's error and joins `reportingAll` with the rest.
- That is a diagnostic change: a run can report more errors, and the first can differ. It lands serially in PR 6b, for mock roots as for production roots and seams (5.2), so PR 8 gates "diagnostics identical" against a commit that already has it.
- Any other error type: none is known to be thrown. If one is, the driver throws the one of the lowest job index, in the type order of today's loop, and reports nothing else. That is today's behavior, and no parallel PR changes it.
- The same two cases apply to a throw from step 6 and to the callers' world's held failure.

---

## Section 2.3: the helper

### 2.3 The helper: bounded, ordered, nested by lending slots

Every task group in `SafeDICore` is this one function. It replaces five:

| Group today | What it does | Arrival order reaches output? |
|---|---|---|
| `DependencyTreeGenerator.swift:243–265` | production output | No (the caller sorts), but the first error thrown wins |
| `…+MockOrchestration.swift:192–233`, with `async let` at `:198`, `:209`, `:213` | mock output | Same |
| `…+MockOrchestration.swift:160–174` | union of `Sendable` configuration names | No (a set) |
| `…+DeclarationValidation.swift:40–54` | `@Sendable` capture walk | No (a set the error sorts) |
| `DependencyTreeGenerator.swift:320–332` | DOT output | No (sorted at `:331`) |

The three `async let`s inside a mock output job stay as they are until E4 removes the actor hops they wait on; they are children of a helper job, so they add at most two tasks per admitted job. Until E4 that is a stated exception to the bound below.

**What one call does:**
- It has a **width**: the task-local `width` of the task that calls it. The driver's is the process width.
- It takes jobs in index order, each with a **cost**: a whole number from 1 to the call's width. The default is 1.
- It admits the lowest index not yet admitted, and only when the costs in flight plus that job's cost are at most the width. It never admits a later job past one that is waiting.
- It runs each job with the task-local `width` set to that job's cost.
- It returns one outcome per job, in index order: the job's `Result`, or "not admitted".
- Called with `stopsAtFirstFailure`, it admits no later job once it has collected a failure. It cancels nothing.
- When the parent task is cancelled, it calls `cancelAll()`, waits for the children, and throws `CancellationError`.
- Leaving it awaits every child, so no job outlives the call that started it.
- At width 1 it runs the jobs in the caller's own task, in index order, with no child task. The outcomes are the same. It checks for cancellation before each job, and throws `CancellationError` as the other path does.
- **It releases each job's input when that job ends.** A job is given its input as a value it owns. The helper keeps no reference to an input once it has admitted the job: not in its job list, not in a closure it still holds. So the last reference to job *i*'s input dies when job *i* returns, on that job's thread, and before the call returns. This holds on the width-1 path too.
  - Why it is a contract: 8.2 and 5.4 need a body's tree to die on its output job's thread. A helper that held its list of jobs, each a closure capturing a tree, until the call returned would keep every tree alive to the end of output and free them all on the driver.
  - **Proof owed (PR 2):** the release test of 5.2. PR 3's driver-release gate (8.2) would also catch a miss, but late.
  - Not verified: that a task group's child frees what its closure captured when the child ends, and not when the group does. The test shows it on CI's compilers; if it does not hold, the helper hands each input over through the job's parameter and the note is amended.

**Nesting: a unit lends the slots it holds.** The first writing of v2 said "one helper, one window of `width`" and then nested helper calls in three places without saying how the windows relate. If each nested call had its own window of `width`, the work in flight would be `width` to the power of the depth. If all calls shared one window, a unit holding a slot while it awaited its children would deadlock at width 1. The rule is neither:
- A nested call's width is the cost of the unit that makes it. While the unit awaits that call it runs nothing itself, so its children run on the slots it holds, and on no others.
- There is no pool of free slots and no counter two tasks share. So there is nothing to wait on: a unit of cost 1 runs its nested call in its own task, and width 1 cannot deadlock.
- This is the challenge's option B (the awaiting parent gives up its slot), in the one form a task group allows without shared state: the slot goes to the parent's own children, not back to a pool.

**The bound.** At each nesting level, the costs of the jobs in flight sum to at most the process width. So:
- at most `width` tasks run job code at any instant, at any depth;
- the jobs in flight are at most `width` per level, and the depth is 2 for output and construction and 3 for signatures (1.6).
- **Proof owed (PR 2):** the two nesting tests of 5.2.

**What lending gives up.** Slots a unit holds and is not using are idle:
- during a unit's serial step (a body's naming pass; a public mock's `holes` stage 3);
- when its nested call has fewer jobs than its cost;
- when the next job in index order costs more than the slots free, since no later job is admitted past it.
- while a job waits for another job's build of a subtree it needs (2.4). The wait is no longer than the owner's remaining build, which is about what building the subtree itself would have taken. When the build ends stored, the wait saved that CPU and the second copy's memory. When it ends abandoned (a place that turns out to hold a hole, 2.4), the wait saved nothing: the waiter then builds the place itself. That happens at most once per key per domain, because the key is marked.

A unit that returns gives its slots back to its own call's window, where the next unit takes them. The loss is measured as CPU over wall per phase, with the phase timer (section 7), in PR 10.

**Costs.** The caller sets them, serially, from sizes it already has, by one rule: a job's cost is its share of the call's total size times the call's width, rounded, and at least 1.
- With as many similar units as slots, or more, every cost is 1 and every nested call runs in its unit's task. That is the common case: many mock roots, many bodies.
- With one large tree among a few small ones, that tree gets nearly every slot; alone, every slot.
- Sizes: for output, the finished tree's place count; for construction, 2.3's estimate below; for signatures, the component's seam count and a seam's site count.
- Until PR 11 a construction unit makes no nested call, so its cost is 1.
- The rule is a guess. PR 10 compares it with cost 1 everywhere.
- Output never depends on a cost. The schedule oracle (2.5) takes costs as an input.

**Why not the other two forms.**
- *Flat stages* (every unit's first step in one call, then every unit's second): no job would call the helper, and the bound would be exact. But every unit waits at each stage for the slowest unit, and between stages every unit's partial result is alive at once: with output, every body's plan. That is against 5.4 on the path where memory already regresses.
- *A shared pool of slots*: it wastes nothing, but the free count is mutable state that tasks share. A lock around it is banned. An actor that keeps it must hold suspended waiters, and the ruling allows an actor "only where tasks share a memo of finished values". SHARE-SUBTREES-FROM-START now lets the memo's actor hold waiters for a build in flight. It does not extend to a pool of slots, and this note does not ask for that: lending also keeps a waiting job from blocking the job it waits on, since no two units draw on the same slots.

**`width` bounds generation jobs only.** It does not bound the process's busy threads:
- the seven groups in `SafeDIToolLibrary` (parsing, module info, `ConcurrentMapping`) do not use it;
- Swift's cooperative pool still has one thread per core, and an actor hop or an `async let` can run on any of them.

`width` defaults to the active processor count and is a task-local in tests, as `seamSignatureComputationLimitOverride` is (`…+SeamDriver.swift:554`). Section 6 says what this means for measurement and for Bazel.

**Inside a tree (PR 11), each pass is:**
1. **Size estimate, serial, in the driver, per record.** The unfolded subtree size ignoring context, a cycle counted once, memoized over the table, and handed to the jobs as a value. It is only a split heuristic: output never depends on it, and it is not a bound on a job's real size.
2. **Spine walk, serial, in the tree's job.** From the root, descend while a place's estimate is at or over the threshold. This builds the few contexts near the top and yields a flat list of jobs in pre-order. A root under the threshold is built in the tree's job with no nested call. A spine place reads finished candidates, and stores its own generator after the join. It never claims an entry in flight, because its build spans the nested call and a job must not wait on its ancestor (2.4). Two large equal subtrees are therefore both split, and their jobs share one level down.
3. **One nested helper call per tree per pass**, made by the tree's job with `stopsAtFirstFailure`, at the width of the tree's cost. Each subtree job costs 1. The jobs share through one actor: for the first pass of a mock root's first tree, its table's actor, so that they share with the other roots' jobs as well as with each other; for every other pass of every tree, the tree's own actor for that pass. Paths are whole (outermost index first), so the wait rule of 2.4 orders jobs of different trees as it orders jobs of one.
4. **Join by index, serial, in the tree's job** (2.5). Then the spine's places are finished bottom-up.

The first writing had "one helper call over all jobs of all trees". That cannot hold a mock root's three trees, where the second is built from what the first's tail computed, nor a tree's passes, where each pass reads the one before.

Threshold: start at 64 places, the value `scopeCountOfLargeSubtree` was measured at for output (`Scope.swift:1162–1165`: 16, 64 and 256 were indistinguishable there). That is a measurement of another phase, so for construction 64 is a guess. PR 10 measures 16, 64, 256 and 1,024 and records the figures beside the constant.

---

## Section 2.5: the join, and how determinism holds

### 2.5 The join, and how determinism holds

The helper returns outcomes in input order. The parent task collects children as they finish and writes each into a slot by its index; only the parent touches the slots. Rule by rule:

| Rule (quoted) | How it holds | What proves it |
|---|---|---|
| "A task group's results arrive in completion order. None of these orders may reach output." | Outcomes are placed by job index. No code path appends in arrival order. | Schedule oracle; the helper's join tests |
| "use declaration order, source path order, or a sorted order. Never use first-found or last-write-wins over an unordered collection." | `ScopeID` order is 1.2's total order. Jobs are listed in pre-order. Roots, seams and mock roots are listed in sorted type order, as today. | The freeze test of 1.2 |
| "`Scope` hashes by object identity, so the order of a `Set` or `Dictionary` changes between runs" | No task holds a `Scope`. `idByKey` is never iterated. The freeze sorts; it iterates no `Set<Scope>`. | The freeze test |
| "Every root … reports the first error its own walk finds, and `reportingAll(of:)` joins them in source order" | Section 5.2. | PR 2's two-roots fixture; the rename-invariance oracle |
| "a memo shared across roots … keeps only walks that completed" | A build that throws is removed: the actor has no insert path for it, and its waiters build the place themselves (5.2). A build that completes and may not be stored is abandoned the same way (2.4). A subtree whose own build completed is kept even when its tree fails elsewhere later; that is narrower than R0's cross-root condition 3 (8.5 item 8). Validation's memos stay serial in the driver. | The sharing oracle; 5.2's failing-builder tests; R0's memo oracle |
| "Generated code and signatures, which graphs are accepted, and which diagnostic is reported never depend on names or order." | Width, threshold, core count, scheduling and sharing are all "order". Two oracles make them test inputs. | Schedule oracle; sharing oracle |
| "A test of choice-making code needs enough candidates … twenty or more, or a permutation of six." | The join's tests use at least twenty jobs under forced completion orders. | PR 2 |
| "Parallel generator work reads only `Sendable` values." | Jobs capture snapshot layers, a context value and a previous-pass tree. | The compiler, on Swift 6.2 in CI |
| "A generator keeps finished code, never a finished task." | A group child is released when its outcome is collected. Nothing stores a task. A build in flight is a key, a token, an owner's path and waiters' continuations, replaced by the finished value or removed when the build ends (2.4). | `SourceRuleTests` (5.1); 5.2's end-state test |

**The schedule oracle** (new, lands with PR 8): each corpus graph is generated with the pool on one thread, at width 1, at the default width, with jobs completed in reverse order, at thresholds 1, 64 and unbounded, and with unit costs forced to 1, forced to the width, and drawn by seed. All bytes and all diagnostics must be equal. Its hand mutation: place outcomes in arrival order; the PR names the seed. CI's five Linux passes then cover real scheduling. From PR 8 it also runs each graph with the sharing schedule drawn by seed, candidate order and walk direction included, and with waits forced and forbidden (2.4).

---

## Sections 5.1 to 5.2: cancellation and errors (through PR 2's tests)

## 5. Cancellation, errors and memory

### 5.1 No detached or unstructured tasks

Removed, each in the PR that replaces its user:
- `Task.detached` in `startCodeGeneration` (`Scope.swift:1928`, `:1934`), whose error is dropped: E2.
- `Task { … }` deduplicating in-flight code (`ScopeGenerator.swift:2809`): E2.
- `Task { await collectMockParameterTree() }` (`ScopeGenerator.swift:4583`): E4.
- The 64-scope early-start machinery (`Scope.swift:1150–1165`, `:1906–1918`): E2.

`SourceRuleTests` gains a rule that fails on `Task.detached` and on an unstructured `Task {` under `Sources/SafeDICore` and `Sources/SafeDIToolLibrary`, added when the last one is gone. The plugin's one use (`InstallSafeDITool.swift:72`) is outside the generator.

The finished-subtrees actor (2.4) adds none: it creates no task of any kind. A build in flight runs in the job that claimed it, and what the actor keeps for a waiter is a continuation, resumed exactly once when that build ends.

### 5.2 Errors, and stopping, with a task group only

**What a task group can do.** It can cancel all of its children or none. `addTask` returns no handle. A handle per job is an unstructured task (banned, 5.1). A shared stop flag is lock-wrapped mutable state (banned), and `Synchronization.Atomic` is not available at the package's macOS 11 (`Package.swift:17`). So v1's "cancel every job with a higher index" cannot be written, and this design does not cancel selectively at all.

**Across trees** (roots, seams, mock roots): every job runs to its own outcome. No tree is stopped because another failed: the outer call is never made with `stopsAtFirstFailure`. The driver passes every failure to `reportingAll`, which joins them in source order. No group lets the first error thrown stand as the diagnostic, which both output groups do today (`for try await` at `DependencyTreeGenerator.swift:259` and `…+MockOrchestration.swift:229`).

**This changes which construction errors production roots report, on purpose.**
- Today: `try rootScopesToGenerate.map` (`DependencyTreeGenerator.swift:439`) builds the roots in sorted type order (`:435`) and throws the first construction error. That is name order, and no later root is built. The seam-world path (`…+SeamDriver.swift:424` on) I did not read past `:425`.
- The error that can be thrown there: an erased instantiator's forwarded-properties mismatch (`Models/Scope.swift:1342`, `:1383`). That valid input reaches it after validation has passed is the challenge's reading; I did not run it.
- After: every production root and seam reports its own first construction error, joined in source order. That is what CLAUDE.md's determinism rule already asks ("Every root (production, …) reports the first error its own walk finds, and `reportingAll(of:)` joins them in source order"), so today's behavior is the deviation.
- It is a diagnostic change: a run can report more errors, and the first one can differ. So it is its own PR (6b), serial, beneath every PR that builds production roots in parallel. PRs 7 to 9 then gate "diagnostics identical" against a commit that already has it. X1 lists it as a fix.
- **Fixture (PR 6b):** two roots, each with a construction error, named so that type order and source order disagree. Both are reported, in source order. A second fixture: two roots that reach one failing declaration, to pin whether the error is reported once or twice. If neither fixture can be written with valid input, the PR cites the check that rejects it, the change has no observable effect, and this paragraph is struck.

**Mock roots get the same change, in the same PR.** v2's PR 6b covered production roots and seams only.
- Today: a mock root's tree build that throws the same error is not caught by the loop (`…+MockOrchestration.swift:97` catches `DependencyTreeGeneratorError` only), so the first such root in type-name order ends `generateMockCode` with that one error.
- It is more likely to be reachable here than on a production root: the mock scope map holds types no production root reaches, so production validation never walked them. Read, not run.
- After: every mock root reports its own construction error, wrapped in `.sourceLocated` and joined in source order (2.2, "What a job's failure is").
- **Fixture (PR 6b):** two mock roots that no production root reaches, each with an erased instantiator whose first generic argument mismatches, named so that type order and source order disagree. Both are reported, in source order, beside another mock root's ordinary error. If it cannot be written with valid input, the PR cites the rejection and wraps nothing for mock roots; 2.2's rule for any other error type then covers this one too.

**Inside a tree (PR 11): stop admitting, cancel nothing.**
- Jobs are admitted in index order. So when job *i* of a tree fails, every lower job of that tree is already admitted, and each runs to its outcome.
- The tree's jobs are one nested call made with `stopsAtFirstFailure` (2.3), so no later job of that tree is admitted. Other trees are other units of the outer call, which never stops.
- Later jobs of that tree already in flight, at most the tree's cost minus one, finish; their outcomes are discarded, success or failure.
- **The walk's first error** is chosen from one ordered list of events, in the serial walk's order: entering a spine place, each job, finishing a spine place (after everything beneath it). The first failing event in that list is the tree's error. The spine walk is serial and stops listing at its own first failure; jobs listed before that point still run, since one of them may fail earlier in the order. Spine finishes run in the join, in list order, and stop at the first failure of any kind.
- This is deterministic because every event before the first failure always runs, whatever the schedule.

**The waste is bounded, not zero.** After a failure, at most the tree's cost minus one in-flight jobs of that tree run on. Each is a subtree the estimate put under the threshold, but the estimate is not a bound (2.3), so the test measures places built after a failure and does not assume it.

**Cancellation proper** happens in one case: the parent task is cancelled. Then the helper calls `cancelAll()`, awaits the children and throws `CancellationError`, and nothing else is reported. A `CancellationError` from a child is never a diagnostic.

**Tests (PR 2):**
- Twenty jobs in one call made with `stopsAtFirstFailure`, job *i* fails, completion orders forced: no job above *i* is admitted after *i*'s failure is collected; every job below *i* has an outcome; the reported error is the lowest failing index's.
- Two units, each with a nested call made with `stopsAtFirstFailure`: a failure in one stops no job of the other.
- **Nesting at width 1, two levels:** three units, each making a nested call over three jobs. The run finishes; at no instant do two tasks run job code; all nine outcomes are in index order; no child task is created.
- **Nesting with costs, at width 4:** twenty units with costs drawn from 1 to 4, each making a nested call over twenty jobs, completion orders forced. At every instant the costs in flight in the outer call sum to at most 4, the jobs running in each unit's nested call are at most that unit's cost, and the tasks running job code are at most 4. A unit of cost 3 waiting behind a free slot count of 2 is not passed by a later unit of cost 1.
- Two roots that throw during output: both are reported, in source order.
- Parent cancelled mid-phase, at width 4 and again at width 1 (the caller's-task path): every job that started has finished when the helper returns; no later job starts; the helper throws `CancellationError`; and no diagnostic is produced, even when a job had already failed.
- **Release (2.3's input contract):** three jobs whose inputs are objects with an observed `deinit`, at width 1 and at width 4 with completion orders forced. Each input's `deinit` has run when its job's outcome is collected, on the task that ran the job, and before the call returns. At width 1, input 0's has run before job 1 starts.

---

## Sections 5.3 and 5.4 (first three bullets)

### 5.3 Cancellation checks

`Task.checkCancellation()` at each subtree boundary: once per place popped in the construction loop (`Scope.swift:502`), once per site chunk, once per fragment, once per spelled chunk. Never inside a per-element inner loop. They act only when the whole phase is cancelled (5.2). And once when a waiter is resumed (5.2), before it reads what it was resumed with.

### 5.4 Bounded fan-out, and memory under EVERY-MOCK-REPORTS

- One helper for every phase, nested by lending (2.3). At each level the costs of the jobs in flight sum to at most `width`. So the tasks running job code are at most `width`, and the contexts, memos and partial results in flight are at most `width` jobs' worth per level, over two levels (three for signatures).
- What a suspended unit holds while its nested call runs is counted in that: a body's plan so far and early chunks, a tree's spine and job list. At most `width` units are in flight.
- A tree's spine walk and job list hold one context per job: the tree's size over the threshold.

---

## From section 7: the introduction (without its shapes)

## 7. The PR sequence (the plan)

Every gate is measured with the concurrency lane's harness (`harness/measure.py`: one warm-up, five timed rounds, load gate, normal mode and the pool-variable one-thread mode), reporting **wall, CPU and peak RSS**, for **one process** and for **K = 1, 4, 8, 16 concurrent processes**. Mac for instructions and the K table on a quiet machine; Linux for the banded comparisons; one Linux reading of each parallel gate.

- **Timings and memory are compared with a built 2.2.0 `SafeDITool generate`** (never 2.2.0's tests) on the shapes 2.2.0 accepts, and with 2.3.0 on the shapes it does not (seams, public mocks).
- **Output is byte-identical across the runs of one commit:** every round, both modes, and every width, cost assignment, threshold and sharing schedule the PR introduces; and, for an output-neutral PR, with the commit beneath. It is never compared with 2.2.0's output, which differs by design.
- **Every gate reports three columns: the commit beneath, the anchor, and 2.2.0.** The anchor is one fixed commit, S1's head a39c6766a, built once and kept beside the 2.2.0 binary. v2 gated each PR only against the commit beneath, within a band of up to 3%. Ten such gates can pass while the sum drifts by about 30%, and nothing held wall or memory against a fixed point until PR 11.
  - **The cumulative allowance is one band, in total.** At every PR, on every shape under the bar, wall, CPU (both modes) and peak RSS are at or under the anchor's, within the band of that run. Not one band per PR.
  - A PR that is under the commit beneath and over the anchor fails its gate. The per-PR reports say which earlier PR spent the allowance.
  - Other lanes' PRs (R0, E6a, E1) land in between and lower some figures. The anchor column cannot tell this design's drift from their gain, so the commit-beneath column stays; the anchor catches the net.
  - The figure is this note's choice (8.5).

---

## Section 7.2: timing a phase (through "Not verified")

### 7.2 Timing a phase

`measure.py` times processes, and a `sample` profile gives shares of samples, not a phase's wall. So the phase gates of the first writing ("output phase at least 2× its one-thread time") named nothing that could be read. They need a timer in the tool.

**The phase timer** (PR 2's first commit, so that every later PR has a commit beneath that carries it):
- The code that runs the phases (the entry points until PR 6, the driver after) reports each phase's start and end to a task-local observer, as `CodeTaskStart` does (`CodeTaskObservation.swift:27`).
- When the environment variable `SAFEDI_PHASE_TIMES_OUTPUT` names a file, `generate` installs an observer that writes one line per phase: its name, its wall from the monotonic clock, the process's CPU over it (`getrusage`, user plus system), and the process's peak RSS at its end.
- The process's CPU over a phase is that phase's CPU only where no task outlives the phase that started it. v2 said that holds everywhere. It does not, before E2 and E4:
  - creating a generator starts its code on a detached task (`Models/Scope.swift:1923–1937`, reached from `:1906–1918`; the comment at `DependencyTreeGenerator.swift:433` says so), so production output's CPU is partly charged to production construction;
  - a mock root's parameter tree runs on an unstructured task started by its first reader (`ScopeGenerator.swift:4583`), which can be in the construction tail or in output.
- So per-phase CPU is clean for production from PR 3's commit, and for mocks from PR 4's. Before those commits `measure.py` labels the affected CPU columns "overlapping", and only their sum from construction's start to output's end is compared. Wall per phase is unaffected: a phase's start and end are the driver's.
- An environment variable, not an option: nothing appears in help or in the Manual. It is covered by a test like any other line.
- Phase names are fixed in PR 2 and may only be split later: validation, signatures, production construction, mock plans, mock construction, whole-module gates, production output, mock output, DOT.
- `measure.py` gains one column per phase, in both modes.
- **Not verified:** that the phases as they stand before PR 6 can be bracketed without overlap, since `rootScopeGenerators` validates and constructs inside one getter (`DependencyTreeGenerator.swift:381–457`) that `generatePerRootCodeTrees` evaluates (`:235`). PR 2 shows it, or brackets coarser phases until PR 6. Nor that the two task kinds above are the only work that outlives its phase; PR 2's timer test asserts that no child is alive at a phase's end on the commits that claim clean phases.

---

## From section 7.3: PR 2's row

| # | PR | Stage | Depends on | What changes | Gate |
|---|---|---|---|---|---|
| 2 | **The helper** | E2's first commit | E1 | First commit: the phase timer (7.2). Then section 2.3: the window with costs, a nested call at its caller's cost, the width-1 path in the caller's task, outcomes by index, `stopsAtFirstFailure`, `cancelAll()` only on parent cancellation, each job's input released when that job ends, `width` and the completion-order knob. Replaces the five `SafeDICore` groups. | The seven tests of 5.2, with at least twenty jobs, the two nesting tests and the release test among them; the cancel test at width 1 too. The phase timer's own test. Bytes identical. |

---

## From section 7.3: the claims PR 2 proves

| Claim | Section | Proved by | In PR |
|---|---|---|---|
| At most `width` tasks run job code, at any nesting depth | 2.3 | The two nesting tests | 2 |
| A job's input dies with the job, on the job's thread | 2.3 | The release test; the driver-release gate | 2; 3 and 4 |

---

## From "What would make this wrong"

- A task-group child keeps what its closure captured until the group ends. Then the helper must pass inputs another way (2.3), or every tree is freed by the driver after output and PR 4's 1% gate fails.

---

## From section 8.3: found, not fixed

2. **Two groups report whichever error was thrown first** (`DependencyTreeGenerator.swift:259`, `…+MockOrchestration.swift:229`). Reachable only when two roots throw during output. Plan: PR 2 fixes it with a fixture.

---

## From section 8.4: not verified

- That a task-group child frees its closure's captures when it ends (2.3).
- That the detached code starts and the mock parameter tree task are the only work that outlives its phase today (7.2).
- That the phases before PR 6 can be bracketed by the phase timer without overlap (7.2).
- Any nested helper call: the helper does not exist yet.
- Anything on Linux, including whether the pool variable works there.
