# Brief N2: the mock body on the per-type emitter (spike)

Read `briefs/common-cloud-lane.md` first; this brief overrides it where they differ. Plan: `plans/2.3.1-plan.md` (items N2, E4, R3). Base: current `origin/main`. Branch: your own `claude/…` branch. Spike only: no PR; `Sources/` edits only on your spike branch, never merged.

**Why.** Dan's ruling 2-3-1-PUBLIC-MOCKS: public mocks get the full shared form in 2.3.1 (every place shared), gated on this spike; if it fails, 2.3.1 ships only what lifting W1's loop error needs. The clean-slate estimate's largest unproven claim is that a mock body can be the production per-type emitter plus an override hook (`generator-clean-slate.md`, section 2 "Where this is most likely wrong" and section 4 risk 1, on `dfed--claude/productivity-retros`).

**Read first.** `handbacks/spike-1-per-type-production.md` (the per-type production emitter, branch `claude/project-thread-4xgw6h`), `handbacks/spike-3-mock-overrides.md` (enum-box storage; one builder per key with the configuration as a parameter; its "never shared" list), `per-type-seam-spike.md` sections F3 and "Recommended design", and section 5 of `/mnt/project-files/w1-derisk/report.md` (the loop-closing function taking its level struct as a cycle parameter, variant `h`).

**Question.** Can one function per key (concrete type, form, read outcomes, plus "reads a configuration") serve every place of a mock body, with each place passing its own override configuration, and give inline's values and frees and exactly today's override reads?

**Fixtures** (hand-written per-type bodies, or the spike 1 emitter extended, your choice; say which): (1) an internal mock with a promoted root, overrides two deep, one type built at three places; (2) a loop of builders (`Screen ↔ Step` through `Instantiator`s) with a value declared again inside the loop; (3) a lazy cycle (`LazilyInstantiated`) with a reader inside the cycle; (4) a public mock with a hole and a fill that reads a value bound in the loop (the per-type seam spike's F3, which today's mock gets wrong); (5) #646's mock variant at 12 screens for cost. Use spike 2's harness (`spike/per-type-seam/common/` on `claude/project-thread-ea2rdt`): trace values, construction order and what is alive; compare against inline and today's mock.

**Done when.** For each fixture: equal to inline in values and frees (or not, with the diff); the override each place reads equals today's text's; compile time and runtime against today's per-path body; generated lines. A yes/no answer for "public mocks fully shared in 2.3.1", the list of shapes that cannot share (against spike 3's never-shared list), and E4's hook interface sketched in one page. If no: the shape that breaks and what the fallback (cycle parameter only, variant `h`) costs.

**Hand-back** as in the common brief.
