# Slice 2 timeline of work and waits

Slice 2 is the leak-fix slice that turns a seam's builders into structs. Times are UTC on 2026-11-15 unless a row says 11-16. Sources: the ledger and slice 2's `progress.md` (stamped in PST, converted at +8 hours), the run logs of lane `s2-2` (under `~/Library/Caches/SafeDIScratch/lanes/s2-2/`), and `gh run view` for every run ID those files cite. A run's start is its first job's start and its end is its last job's end. A row marked "(inferred)" takes an edge from a ledger or file time, not from a run.

Span: implementer start 18:10 to code final 02:03 (11-16) is 473 min. The review ends 02:23. The review fixes are still open at the last ledger entry, 03:25.

**Queue time.** Every run in the table started its first job 1 to 3 s after creation, so a run never queued at the front. The queue sits inside a run: a shard waits for a runner after the build ends. See "Queue inside a run" below.

## Table

| Start | End | Dur (min) | What | Waiting on |
|---|---|---|---|---|
| 18:10 | 18:35 | 25 | Implementer starts; regenerator cherry-pick; base filter green | work |
| 18:35 | 19:08 | 33 | Generator commit 57d6c980f | work |
| 19:08 | 19:29 | 21 | Rebase onto new slice-1 head dd94eb73b (lane hand-off from slice 1, cleared 19:19) | slice 1 review fixes |
| 19:32:25 | 20:11:33 | 39.1 | Graph Fuzzer, run 43752987923, on 9ec166caa | pins |
| 19:40 | 20:53 | 73 (inferred) | Hand edits of red seam tests; 21 stay red, "waiting on the fixed fragment regenerator" (progress 20:12); regenerator on hold (ledger 20:11) | fragment regenerator |
| 19:56:02 | 20:33:18 | 37.3 | Verify, 43755164161, bf1dcb031: failure | red seam expectations |
| 20:19:15 | 20:57:47 | 38.5 | Verify, 43757397194, ce64b6e5c: failure (overlaps the row above) | red seam expectations |
| 20:53:47 | 21:22:52 | 29.1 | Verify, 43760608315, 4ad19ed12: failure | about 14 manual items |
| 21:25 | (continues) | | Interim hand-back 1 at head 4ad19ed12 (3 h 15 min in); stops ruled (S2-SLICE2-STOPS) | orchestrator |
| 21:25 | 21:47 | 22 | Matrix helper writes 17 tests (23 cases) in parallel with the worker; cherry-picked 21:49 | helper lane |
| 21:25 | 22:16 | 51 (inferred) | Hand-update of remaining red seam tests, three generator fixes, compiled seam run | local suite runs (about 3.5 min each) |
| 22:16:13 | 22:50:04 | 33.9 | Graph Fuzzer, 43768337332, cc465388e: failure | pins |
| 22:16:14 | 22:45:05 | 28.9 | Verify, 43768338749, cc465388e: failure | the 2.7 roll's fixture hash |
| 22:16:44 | 22:26:32 | 9.8 | Mac probe 2.9, 43768385517, Xcode 26 | macOS probe |
| 22:54 | 23:04 | 10 | Review round: rulings workflow wf_7bdf0f68 on hand-back 2 | rulings |
| 22:55 | 23:06 | 11 (inferred) | Round 3: guard probe, values probe, 2.7 package roll built and dropped | probes |
| 23:06 | 23:38 | 28 | Wait for the new base SHA (progress 23:10: "waiting for new base SHA") | orchestrator restack |
| 23:13 | 01:44 (11-16) | 151 | Hand-off: fresh implementer for compile of C and three draws (ledger 23:13; hand-back 01:44) | work, runs parallel to slice 2 |
| 23:24 | | | Hand-off: slices 3, 5, 6 start speculatively on 163f93d08 | |
| 23:38 | 00:02:49 | 25 (inferred) | Rebase onto 971acd4cf, triage of stale lists, resolve scripts | none |
| 00:02:49 | 00:27:39 | 24.8 | Verify, 43778050803, 2f239d961: success; build step 18.8 | rebase verification |
| 00:23:31 | 00:48:58 | 25.4 | Verify, 43780086593, 6d7643891 (compile of C): failure, two smoke tests | compile of C |
| 00:23:31 | 01:27:25 | 63.9 | Graph Fuzzer, 43780085712, 6d7643891 (compile of C): its shards started up to 37.7 min after the build ended | pins |
| 00:29 | 02:05 | 96 | Slice 2 head 9458387b8 "ready for code review"; the snapshot push denied twice (00:29, 00:36); the orchestrator pushed a new branch at 02:05 | a push that only the orchestrator may make |
| 00:29:25 | 01:26:10 | 56.8 | Graph Fuzzer, 43780663310, 9458387b8: failure, 26 problems; build 16.3 min | pins |
| 00:36 | | | Rebase onto bb23017fe (slice 1's coverage test moves the base) | slice 1 |
| 01:26 | 01:41 | 15 (inferred) | Pins and lists applied as commit 8f0574412 | the pins report |
| 01:35:42 | 01:41:27 | 5.7 | Fast Verify, 43787169509, b0373225a (compile of C): success | compile of C |
| 01:41:14 | 02:02:52 | 21.6 | Verify, 43787699752, 8f0574412: success | final verification |
| 01:44 | | | Hand-off: compile of C handed back (42c8f2092 to b0373225a) | |
| 02:03 | 02:05 | 2 | Final head 8f0574412; the worker's force-push refused; the orchestrator pushes a new branch | the permission classifier |
| 02:05 | 02:23 | 18 | Review round: wf_aeaa46bd, three lenses and a Fable pass; 3 blocking, about 13 should-fix | review |
| 02:09:15 | 02:41:07 | 31.9 | Graph Fuzzer, 43790406446, a5d91bd9f (compile of C rebased onto 8f0574412), preview pins: failure, 69 problems | pins; valid only for that head |
| 02:23 | open | | Review-fix lane "to start"; compile of C waits for the review-fix head, then one final pins run | review fixes |
| 02:36 | 02:59 | 23 (inferred) | Migration lane reruns on 8f057441: 451 comparisons written out, helper-built 342 to 17 | slice 2 snapshot |
| 02:59:38 | 03:20:13 | 20.6 | Verify, 43795430677, eb3d3c0d3 (migration): success | verification |
| 03:20 | open | | Review of the migration launched | review |

## Queue inside a run

All runs were created and began their first job within 1 to 3 s. After the build job, the shard jobs waited for runners.

| Run | Build (min) | Shards: first start after build | Last start after build | Mean wait |
|---|---|---|---|---|
| 43752987923 (9ec166caa) | 23.1 | 0.1 | 14.9 | 1.7 |
| 43768337332 (cc465388e) | 20.2 | 0.0 | 12.5 | 1.4 |
| 43780085712 (6d7643891) | 25.1 | 0.3 | 37.7 | 12.1 |
| 43780663310 (9458387b8) | 16.3 | 0.3 | 39.2 | 15.7 |
| 43790406446 (a5d91bd9f) | 11.5 | 4.3 | 19.4 | 7.5 |
| 43778050803 (Verify, 2f239d961) | 18.8 | 0.0 | 5.5 | 1.2 |
| 43795430677 (Verify, eb3d3c0d3) | 11.4 | 0.2 | 6.6 | 2.8 |

The two runs that overlapped (43780085712 and 43780663310, dispatched 6 min apart) had a mean shard wait of 12 to 16 min. Runs on a quiet pool had 1 to 8 min.

## Ran in sequence but could have run in parallel

1. **Slice 2's review after its verify, not with it.** The final head 8f0574412 was ready at 01:41, when its Verify started. The review began at about 02:05, after the Verify finished at 02:02:52. The ledger's own rule B1 (review and verify start together at the last content commit) would have started it at 01:41. Lost: **24 min**. The 15:20 re-plan ("review after green verify") chose this order, so it is a rule to revisit.
2. **Migration waited for the slice 2 snapshot.** The head 9458387b8 was ready at 00:29. The migration lane reran its tool on 8f057441 at about 02:36 (23 min of tool rerun and written-out expectations, then a 20.6 min Verify). The ledger says at 16:40 PST that it waited on the snapshot, whose push the classifier denied. Lost: **about 126 min** of lane time (inferred, from 00:29 to 02:36), 96 min of them in the denied push.
3. **Slices 3, 5 and 6 idle behind slice 2's head.** Slice 5 finished at 00:27 and waited for a base. Slice 3 reported "waits for base" at 01:58 and slice 6 at 02:31. Each had all its pre-rebase work done. The base they wait on is 8f0574412 plus the review fixes. Lost: slice 5 **at least 158 min** (00:27 to 03:05, the last ledger entry still showing it waiting; inferred). They started on 163f93d08 speculatively at 23:24 so that they would not wait; the rebase onto the final head was then serialized behind pins, verify and review.
4. **Two coverage pins runs at once.** Compile of C's pins on 6d7643891 (00:23) overlapped slice 2's pins on 9458387b8 (00:29) for 57 min, and both were competing for the same runners. The last shard started 37.7 and 39.2 min after the build ended; a solo run (43790406446) had 19.4. About **20 min** lost on slice 2's pins. The 6d7643891 result (63.9 min, 445 problems) was invalid after the rebase, since "a rebase invalidates every value". The ledger's re-plan chose one pins run at the end; slice 2's lane ran three (9458387b8, 6d7643891, a5d91bd9f), and the final one is still to come.
5. **Pins, then apply, then verify, one after the other.** Pins 9458387b8 ended 01:26:10; the list edits took until 01:41 (15 min, inferred); the Verify ran 01:41 to 02:02:52. The edit commit changes only lists, pins and hashes. Starting a Verify of the pre-edit head with the pins run would have taken the first of those off the chain, but its green would not have covered the edit commit. Lost: **at most 22 min**, only if the final verify is allowed to cover the pre-edit head and a Fast Verify the edit commit.
6. **Slice 2's red seam tests waited for a regenerator that was on hold.** From 19:40 the lane waited for the fragment regenerator (ledger 11:40: hand edits allowed; 12:11: regenerator held; progress 12:12: "waiting"). The 14:10 PST ledger entry puts the manual editing of the remaining tests at about 10 min. Lost: **about 41 min** (19:40 to 20:53, inferred).
7. **Three Verify runs that failed on the same class of cause.** bf1dcb031, ce64b6e5c and 4ad19ed12 (19:56 to 21:22:52, 87 min, each failing on remaining seam expectations). Their runs overlapped, so the runs themselves were parallel. The loss is that each ran a full 29 to 38 min build and test to learn what a local compiled seam run (about 3.5 min) reports. Lost: **about 60 min** of wall (inferred).

## The three biggest gaps

1. **00:29 to 02:05 (96 min): pins, apply, verify and the denied snapshot push** between "ready for review" and the final head 8f0574412. Pins took 56.8 min, applying 15 min, the Verify 21.6 min.
2. **22:54 to 00:29 (95 min): from hand-back 2 to a rebased, green head.** Rulings 10 min, probes 11 min, the wait for a base 28 min, the rebase and triage 25 min, the Verify 24.8 min. Only about 21 min of it was work.
3. **19:40 to 21:22 (102 min): red seam tests, three failing Verify runs and the regenerator hold.** The runs took 37.3, 38.5 and 29.1 min and all failed on the same remaining expectations.
