# N1 hand-back: the 2.3.1 ship-bar benchmark against 2.2.0 (synthetic half)

Branch `claude/project-thread-7eql0r` (this machine may push only its own `claude/…` branch), base `origin/main` a6d44aff. No `Sources/` edits, no pull request. Everything here is **synthetic**: shapes with invented names and invented proportions. The lifelike half (check 7's private fixtures) runs on the maintainer's Mac through the same script (see "Mac command list").

## Done-when, item by item

| Item | State | Evidence |
|---|---|---|
| Script that takes two `SafeDITool` paths and prints one table | Done | `Scripts/benchmark-2-3-1.sh TOOL_A TOOL_B [FIXTURES]` → `Scripts/benchmark-2-3-1/bench.py`; fixtures from `make_fixtures.py`; any directory in the same layout works, so the private fixtures run through the same command |
| Baseline table, 2.2.0 and main | Done except the 100-module rows, which follow as an addendum (rerun with the fixed harness, about 17:30Z) | `results/run2-table.md` (primary), `results/run1-table.md` |
| Two full runs agreeing within 3% on wall-time medians | **Not met.** 99 of 113 wall-time medians differ by more than 3% between runs, and 28 of 36 main/2.2.0 ratios do too (13 by more than 10%). This cloud VM's run-to-run noise is 5–25% even at load ≤ 1.1 with nothing else running | `results/agreement.md`; see "Noise" |
| Every shape where main is slower than 2.2.0, ranked | Done, with both runs' ratios | below |
| Machine, compiler and load recorded | Done | Intel Xeon @ 2.10 GHz, 4 vCPUs, 15 GB, Ubuntu 24.04, kernel 6.18; Swift 6.2 (swift-6.2-RELEASE); load ≤ 1.07 before each shape in run 2, ≤ 1.0 in run 1 |
| Addendum 1: #646 per-phase profile | Done as CPU-time shares; instructions per phase need the Mac (callgrind crashes here) | below |
| Addendum 2: speculative generation on and off | Done (wall, CPU, memory); instructions on the Mac | below |
| Addendum 3: lifelike compile and both-families count | Mac half; commands below; `Scripts/benchmark-2-3-1/families.py` counts the families | |

## Shapes

All single-module shapes generate module `App` (or `Feature` then `App`). `-seam` shapes and D have no 2.2.0 counterpart (2.2.0's macros reject `generateDependencyTree`), so they show main only.

- `issue646-12`, `issue646-16`: #646's generator (verbatim, plus the `: Instantiable` conformance the compiler needs; `generate` does not), seed 1. Runtime: `Root()` and a walk 4 screens deep through the `Instantiator`s, per screen.
- `issue646-mock-12`: seed 5, `mock`. **`generate` only**: its 339,105 generated lines could not be compiled here (the first attempt took the 16 GB machine down), so `shape.txt` sets `measures=generate`.
- `E8`, `E16`, `E24`, `E32` (`-inline` and `-seam`), `L60`, `L240` (`-inline`, `-seam`): spike 2's `spec_e.py`, `spec_l.py`, `emit.py`, vendored unchanged. Runtime: `Root()` and every path, per value.
- `D8` … `D24`: the mock-overrides spike's shape D with `--walk` (one public seam per module). Runtime: `Root.mock()` building every screen.
- `layered100` (and `layered100-seams`, main only): 100 modules in layers 20/20/20/20/15/5, `generate` once per module, from the `safedi-positions` bench's `make_fixture.py` scaled from 40 to 100 modules (proportions in `layered.py`'s header: the lead ruled this synthetic shape fine; check 7's statistics are private). 2,119 types, 668 mocks, 5 roots, 7,116 values per iteration.
- `example-package`: `Examples/Example Package Integration`, generate and compile only. The other examples need SwiftUI and do not build on Linux.

Per-module invocation as each version's integration passes it: main gets direct dependencies' `.safedi` files plus `--transitive-module-info-file-path`, `--module-name`, `--package-name` (as its Bazel rule); 2.2.0, which has none of those, gets every module beneath as dependent module info (as its SwiftPM plugin does; its Bazel rule's direct-only list cannot resolve `example-package`).

## Where main is slower than 2.2.0, ranked (run 2's ratio, run 1's beside it)

| Ratio run 2 | Ratio run 1 | Shape | Measure |
|---|---|---|---|
| 4.52 | 4.14 | issue646-16 | generate wall |
| 4.44 | 4.47 | issue646-16 | generate peak memory |
| 3.55 | 3.60 | E32-inline | generate peak memory |
| 3.50 | 3.50 | issue646-mock-12 | generate wall |
| 3.26 | 3.72 | issue646-12 | generate wall |
| 2.78 | 2.76 | issue646-mock-12 | generate peak memory |
| 2.76 | 2.77 | E24-inline | generate peak memory |
| 2.44 | 2.43 | issue646-12 | generate peak memory |
| 1.54 | 1.52 | E16-inline | generate peak memory |
| 1.38 | 1.05 | L240-inline | generate wall |
| 1.28 | 1.28 | L240-inline | generate peak memory |
| 1.26 | 1.34 | E24-inline | generate wall |
| 1.22 | 1.09 | L60-inline | runtime per value |
| 1.19 | 1.23 | E32-inline | generate wall |
| 1.17 | 1.03 | E8-inline | runtime per value |
| 1.16 | 1.17 | E16-inline | runtime per value |
| 1.15 | 1.12 | issue646-16 | compile -O |
| 1.12 | 1.02 | L60-inline | compile -Onone |
| 1.08 | 0.92 | E16-inline | compile -O |
| 1.06 | 1.14 | E16-inline | generate wall |
| 1.05 | 1.09 | issue646-12 | compile -O |
| ≤ 1.02 | | E32-inline compile -O and runtime, issue646-12 compile -Onone, E8-inline compile -O, example-package compile -O, L240-inline compile -O and runtime, E32-inline compile -Onone | |

Reading: what both runs agree on is (1) `generate` is 3.3–4.5× slower on #646's graphs and 1.2–1.3× on inline E, (2) `generate` peak memory is 1.3–4.5× higher (memory is stable run to run), (3) E16-inline's runtime is 1.16–1.17× slower in both runs and issue646-16's `-O` compile 1.12–1.15×. Every other compile and runtime ratio moved across 1.0 between runs or stayed within ±10%: this machine cannot resolve them. Main is faster than 2.2.0 on #646's runtime (0.66–0.88×), on `generate` for the example package (0.6×) and on E8-inline `generate`.

## Noise

Same binaries, same fixtures, interleaved tools, load ≤ 1.1: wall-time medians of five moved 4–40% between runs (`results/agreement.md`); single long runs (E32-seam `generate`, 416 s / 448 s / 516 s on three occasions) by 20%. Ratios do not cancel it (28 of 36 differ by more than 3%). The ship bar at a few percent needs the Mac's instructions retired (deterministic) and a quiet machine for wall time; this VM can rank large effects only.

## Seams (main only, and slice 2's head)

| Shape | Lines | `generate` | Compile -Onone / -O |
|---|---|---|---|
| E8-seam | 530 | 0.12 s | 0.44 / 0.52 s |
| E16-seam | 2,410 | 0.61 s | 1.34 / 2.17 s |
| E24-seam | 17,346 | 8.6 s | 8.7 / 20.9 s |
| E32-seam | 149,786 | 416–516 s | 83 / 178 s |
| D8 / D12 / D16 / D20 | 693 / 1,317 / 2,493 / 5,229 | 0.27–0.83 s | 1.3 / 2.2 / 3.6 / 10.6 s at -Onone |
| D24 | 12,549 (App 10,933) | 1.4 s | **aborts**: swift-frontend exceeds an 11 GB address-space cap at -Onone |

- **E seams: `generate` is quadratic in hole sites.** E24 → E32 is about 9× the lines and 60× the time; inline grows 9×. Profile of E24's seam module (`e24-seam-profile.md`): 57% under `seamRoot`; `internalName(ofBuilderLabeled:)` (`SeamBuilderParameters.swift:163`) rebuilds a union of every builder function name and every name bound so far, once per site; `Hole.Site.sortKey` and two other sort keys rebuild path strings on every comparison. Candidate fixes in that file. The productivity lane owns the fix.
- **D24 does not compile on main** (nor at slice 2's head): App's mock file (10,933 lines) needs more than 11 GB at -Onone; D20's 4,013-line App takes 10.6 s at -Onone and 5.2 s at -O. Fixtures and the generated D24 code are in `fixtures/` and `D24-generated-main/` for the lead's cause analysis.
- **Slice 2's head (8dae4da1) against main:** E seams +170 to +530 lines (the builder struct), `generate` and D compiles within noise, D's output byte-identical in size. Neither seam problem changes.

## #646: per-phase profile of main (addendum 1)

`perf record -e cpu-clock --call-graph dwarf` (CPU-time samples, every thread), split by `Scripts/benchmark-2-3-1/phases.py`: each sample counts once toward the first phase in this order with a frame anywhere in its stack.

| Phase | 12 screens | 16 screens | mock, 12 screens |
|---|---|---|---|
| validation walks | 6.2% | 5.5% | 5.8% |
| `ScopeGenerator.init` facts | 18.1% | 21.7% | 28.3% |
| `createScopeGenerator` passes (outside init) | 11.7% | 10.9% | 13.3% |
| emission (`generateCode` and other `ScopeGenerator` methods) | 52.5% | 54.7% | 49.7% |
| parsing and scope maps | 0.9% | 0.0% | 0.0% |
| unattributed (stack not unwound past the runtime) | 10.3% | 7.2% | 2.7% |

Emission dominates, then init's facts; validation is about 6% throughout. **Instructions per phase:** not from Linux. This VM exposes no hardware counters, and `valgrind --tool=callgrind` (3.22) crashes in Swift 6.2's libdispatch (`_dispatch_sigsuspend`) on every attempt. Exact totals and the Mac's own split are in the Mac command list.

## Speculative generation on and off (addendum 2)

Main against main with `ScopeGeneratorUnderConstruction.startCodeGeneration` emptied (local patch, never committed). Medians of five, wall / CPU (user + system) / peak memory:

| Graph | Speculation on | Speculation off |
|---|---|---|
| #646, 12 screens | 0.47 s / 0.90 s / 126 MB | 0.42 s / 0.85 s / 127 MB |
| #646, 16 screens | 12.6 s / 25.9 s / 1,948 MB | 12.7 s / 24.6 s / 2,090 MB |
| #646 mock, 12 screens | 18.0 s / 27.4 s / 915 MB | 18.3 s / 27.8 s / 919 MB |

Output byte-identical in all three. Speculation buys nothing measurable on these graphs; `generate` stays about two cores busy without it.

## Mac command list (the lead, on a quiet machine)

Needs: Xcode 26 (Swift 6.2), `python3` (the system one is fine), about 15 GB free memory for the largest compiles, and nothing else running. `/usr/bin/time -l` adds instructions retired automatically on macOS.

```sh
X=~/Library/Caches/SafeDIScratch/benchmark-2-3-1; mkdir -p "$X" && cd ~/source/SafeDI && git fetch origin
git worktree add "$X/2.2.0" 2.2.0
git worktree add "$X/main" a6d44aff                       # or the 2.3.0 stack head to measure
git worktree add "$X/harness" origin/claude/project-thread-7eql0r
git worktree add "$X/nospec" a6d44aff && (cd "$X/nospec" && git apply "$X/harness/cloud-reports/benchmark-2-3-1/speculation-off.patch")
export TMPDIR="$X/tmp"; mkdir -p "$TMPDIR"
for d in 2.2.0 main nospec; do (cd "$X/$d" && swift build -c release --product SafeDITool && swift build -c release --target SafeDI); done
# --target SafeDI, not --product SafeDI: at slice 2's head the product build also compiles SafeDIToolTestSupport, which fails in release.
cd "$X/harness"

# 1. Synthetic shapes with instructions (about 4 hours; --skip-shapes to trim)
Scripts/benchmark-2-3-1.sh --labels 2.2.0,main --json "$X/synthetic.json" "$X/2.2.0/.build/release/SafeDITool" "$X/main/.build/release/SafeDITool" > "$X/synthetic.md"

# 2. Lifelike half: the private fixtures in the same layout (FIXTURES/<shape>/modules.txt, <Module>/, optional bench/, shape.txt)
Scripts/benchmark-2-3-1.sh --labels 2.2.0,main --json "$X/lifelike.json" "$X/2.2.0/.build/release/SafeDITool" "$X/main/.build/release/SafeDITool" PRIVATE_FIXTURES > "$X/lifelike.md"
#    report pass/fail and percentages only

# 3. #646 exact instructions, speculation on and off (16 screens and the mock variant included)
python3 -I Scripts/benchmark-2-3-1/make_fixtures.py "$X/fixtures" >/dev/null
for s in issue646-12 issue646-16 issue646-mock-12; do
  ls "$X/fixtures/$s/App/"*.swift | paste -sd, - > "$X/$s.csv"
  for t in 2.2.0 main nospec; do for i in 1 2 3; do
    /usr/bin/time -l "$X/$t/.build/release/SafeDITool" generate "$X/$s.csv" --combined-output "$X/$s-$t.swift" --active-compilation-conditions DEBUG 2>&1 | grep -E "instructions retired|real"
  done; done
done

# 4. Instructions per phase (main): a CPU Counters trace, then the same phase split by symbol
xcrun xctrace record --template 'CPU Counters' --output "$X/646-16.trace" --launch -- "$X/main/.build/release/SafeDITool" generate "$X/issue646-16.csv" --combined-output "$X/p.swift" --active-compilation-conditions DEBUG
#    group by the phases in Scripts/benchmark-2-3-1/phases.py (validate*, ScopeGenerator.init, createScopeGenerator, emission)

# 5. Types built in both families (inside and outside a @Sendable builder), lifelike benchmark, main's output
python3 -I Scripts/benchmark-2-3-1/families.py ~/.cache/safedi-benchmark-2-3-1/<lifelike shape>/main/*.gen.swift
```

## Defects found beyond those named

1. Seam `generate` quadratic in hole sites (above; productivity lane).
2. D24's generated mock file does not compile within 11 GB at -Onone (above; lead's analysis).
3. At slice 2's head 8dae4da1, `swift build -c release --product SafeDI` fails: it compiles `SafeDIToolTestSupport`, whose `GraphFuzzerCallingMocks.swift` uses `@testable import SafeDIToolLibrary`, which a release build without `-enable-testing` rejects (CLAUDE.md requires the support target to import the library without `@testable`).

## Deviations

- Check 7's lifelike benchmark is private: the synthetic half here, the lifelike half on the Mac (lead's ruling).
- #646's generator gets `: Instantiable` added to each class so the generated code compiles.
- `issue646-mock-12` measures `generate` only.
- Instructions: none on Linux (no counters; callgrind crashes).
- Run 2 skips the two 100-module shapes (lead's ruling); their rows come in the addendum.
- Run 1's `layered100-seams` was stopped for the slice 2 seam check; its rows also come in the addendum.
- The 3% agreement is not met on this VM (see "Noise").
- Compiles run under an 11 GB address-space cap (`BENCHMARK_COMPILE_MEMORY_LIMIT_GB`), so a runaway compile is reported, not an out-of-memory reboot; macOS ignores the cap.

## Leftovers

- 100-module rows: addendum at about 17:30Z (running now).
- Instructions and the lifelike half: the Mac command list.
- The 3% bar: rerun items 1 and 2 of the Mac list there; this VM cannot reach it.
- Seam `generate` fix: productivity lane. D24 compile: lead's cause analysis.
- Whether the script moves into `Scripts/` for good: not merged, per the brief.

## Draft PR description (if the harness is ever merged)

**Add a benchmark that compares two SafeDITool builds on generated-code compile time, runtime and `generate` time**

`Scripts/benchmark-2-3-1.sh TOOL_A TOOL_B [FIXTURES]` runs `SafeDITool generate` from two release builds over a set of shapes, one module at a time as Bazel does, compiles each generated module at `-Onone` and `-O` (timing the compiler's frontend job), links a driver that builds each root or `mock()` in a loop, and prints one table of medians of five with min–max and the ratio, then every measure where the second tool is slower. The synthetic shapes come from `Scripts/benchmark-2-3-1/make_fixtures.py`: #646's screen graphs, a growth shape and a low-sharing shape inline and as a seam, a one-seam-per-module shape, a 100-module layered app, and the example package. Any directory in the same layout works, so a private fixture set runs through the same command. On macOS, `generate`'s instructions retired come from `/usr/bin/time -l`. `phases.py` splits a `perf` profile of `generate` into its phases, and `families.py` counts the types a generated file builds both inside and outside a `@Sendable` builder. No SafeDI source changes; the scripts are checked by running them, not by the test suite.

## Time and friction

About 12.5 hours of wall time (01:02–13:30Z), mostly unattended benchmark runs; no CI runs. Friction: the first Swift download was cut off by the proxy (resumed); a compile of the 340,000-line mock file rebooted the VM (now capped); a reused build directory broke the slice 2 build (stale module cache); callgrind crashes on Swift's libdispatch; no hardware counters; VM noise of 5–25% makes the 3% bar unreachable here; each 100-module pass costs about 2 hours.
