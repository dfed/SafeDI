# Overnight retro, 2026-11-16 05:45Z to 14:50Z

Dan's question (15:43Z): why did only slice 2 land overnight when it looked ready at bedtime, and why does anything wait on a landing when we stack?

Sources: slice-2-live.md and slice-3-live.md on this branch, the Actions run list (184 runs created in the window), this lane's 30-minute process-watch notes, and the lead's slice state relayed at 15:44Z. Not seen: the lead's own journal, and what slices 4 to 7a did hour by hour; those gaps are marked.

## The answer in four lines

1. Slice 2 was not ready at 05:45Z. It needed 244 more minutes to reach a green pull request (09:49Z).
2. It then waited 299 minutes on Dan: 82 for the ready mark (11:11Z) and 217 because the merge was blocked until "land #738" was written in the lead thread (14:47Z).
3. Stacking should have made that wait free, but nothing was stacked on it. The stack ran as a chain: each slice waited for the "final head" of the slice below. Slice 3 logged "waits for slice 2's final head" at 06:46Z and 07:12Z; slices 4 to 7a waited about ten hours on slice 3's final head.
4. So no slice waited on a landing by rule, but all of them waited on something that only settles at about the time of a landing.

## Slice 2, 05:45Z to 14:48Z (543 minutes)

| From | To | Min | What | Kind |
|---|---|---|---|---|
| 05:47 | 06:20 | 33 | pins run on the rebased head 7e94f056b (43812452993) | CI wait |
| 06:20 | 07:01 | 41 | classify 69 rename-order findings from that run | work |
| 07:01 | 07:20 | 19 | assemble pins-and-lists and the expectation migration | work |
| 07:20 | 07:42 | 22 | wait for #735 to land (its CI: one run cancelled at 18 min, then 46.5 min) | wait on a landing |
| 07:42 | 07:58 | 16 | final rebase onto main 87e1bc10, open #738 | work |
| 07:58 | 08:42 | 44 | CI run 1; a fuzzer shard fails seed 566 | CI wait, wasted |
| 08:42 | 09:08 | 26 | fix (rename oracle, no generator change), push ae0883f05 | work |
| 09:08 | 09:49 | 41 | CI run 2, green (43837045576) | CI wait |
| 09:49 | 11:11 | 82 | green, waits for the ready mark | wait on Dan |
| 11:11 | 14:48 | 217 | ready, merge blocked until "land" is written in the lead thread | wait on Dan |

Work 102 minutes, CI and pins waits 118, a wait on #735's landing 22, waits on Dan 299 (55% of the window).

Two avoidable costs inside the first 244 minutes:
- **Seed 566, 70 minutes** (run 1 plus the fix). The lead's answer (15:46Z): the pre-PR pins run did reproduce it, but it was classified "stays red until #735 lands" and never re-run on the head rebased onto #735, so CI caught it again. Shard coverage was fine; the classification was wrong. Rule now in use: a finding marked as fixed by another change is re-run on a head that contains that change before the pull request opens.
- **The wait on #735, 22 minutes or more.** Slice 2's pins commit was held for #735 to land so that seed 566's pin could be written once. This is the one place a slice waited on a landing outright.

## Slice 3

- 06:01 to 06:46: final restack onto slice 2's 7e94f056b, conflicts resolved (45 min of work).
- 07:12: head 45c851447 green on a filtered run, "waits for slice 2's final head".
- 07:12 to 13:01: no timeline entry for 349 minutes, but the lane was working throughout (the lead, 15:46Z): 07:58 to 08:15 final rebase onto slice 2 and pins; about 09 to 10 pins applied by hand (the apply script refused a stale line), a label reader fix, leak signatures, and four stops (file-name reversal changing generated code on 12 seeds, floors below 10, seed 566's diagnostic order, seed 391's traversal limit); 10:01 full Verify and coverage; 10:42 rebased onto ae0883f05; 11:17 pins amended; 11:36 hand-back with the stops open; 11:45 ruling; 12:03 to 12:09 stop fixes; 12:31 five smoke seeds failing under normalization; 13:01 hand-back 4. The lead's split: about 45% runs and waits, 35% fixes, 20% stops and rulings.
- 15:44: on its last pins and coverage runs, re-parented onto main.
- Never opened as a pull request on top of #738: it was not green until after #738 landed.

So slice 3 was not idle; it was slow, and nearly half of that was runs and waits. Two rebases with pins each (07:58 and 10:42) are the cost the "pins once, on the top commit" rule removes. The timeline gap itself is a process miss: the slice lane appends its own entries from now on.

## Slices 4 to 7a

From the lead at 15:44Z: slice 4 is ten hours old with commit 3, F1 and F2 owed; slices 5 and 6 are rehearsal branches on an old base; 7a started early; 7b not started. All "had been waiting on slice 3's final head". A replay lane started at about 15:45Z.

Why they were not replayed onto slice 3's interim heads, as far as the records show:
- **A replay is expensive, so waiting looked cheaper.** The trial rebases at 05:51Z measured it: slice 3 onto slice 2's new head was 4 conflict hunks in the generator and 6 in the fuzzer files, by hand, and every new base needs a new pins run (35 to 64 minutes) because the corpus hashes move.
- **Nobody owned the replay.** Each slice's lane ended at its hand-back; the restack was a step the lead would do at the end. The restack skill written for this (claude/restack-lane-3, 0dd6f951) has waited for review since 06:54Z.
- **The lanes were given other work.** After 09:49Z there were 33 Verify and pins dispatches on 22 heads, against 16 on 15 heads before it; the heads that became pull requests at 13:46Z were fix branches (#740 to #745), not slices.

## Mac runners in the window

| From | To | Holder |
|---|---|---|
| 06:27 | 07:31 | #735 (two runs) |
| 07:58 | 09:48 | #738 (two runs) |
| 09:50 | 12:28 | #739, this lane's tooling PR (three runs, one failed on this lane's own mistake) |
| 12:28 | 13:46 | idle |
| 13:46 | 14:59 | six PRs opened in one minute; the pool saturated, jobs queued 34 minutes and more |

From 09:49Z to 13:46Z no slice had anything ready for a Mac runner. The runners went to a tooling change that Dan closed the same afternoon, then sat idle. This lane asked at 08:21Z, 11:56Z and 13:43Z whether slice 3 could open on top of #738; the answer each time was that it was not ready.

## What to change

Each item names its home.

1. **Replay continuously, not at the end.** Every slice above a moving slice is replayed onto it on each push, by a standing replay lane, with a filtered Verify as the check. Home: the lead's handbook, and the restack skill in the repo (review claude/restack-lane-3 now).
2. **Pins once per stack.** The pins run is what makes an interim replay cost an hour. Interim heads carry stale pins; one pins run happens on the top of the stack when it is about to land. Needs the lead's confirmation that no gate between slices reads the pins. Home: the lead's handbook.
3. **Open the pull request when Linux is green.** A slice becomes a draft PR on top of the one below as soon as its Verify passes, CI on the top only, so a wait on Dan is always spent on the next slice's Mac run. Home: the lead's handbook.
4. **One ask per stack before Dan leaves.** The coordinator lists every gate that needs Dan in the next eight hours and asks for all of them at once, including a sentence that covers the stack ("land #A to #F as each goes green"). Whether the merge block accepts a sentence written before the PRs exist is untested; this lane will test it on the next stack. Home: project memory.
5. **Re-run a finding on the head that is said to fix it.** Seed 566 was known before the pull request opened and filed as fixed by #735; it was not, for slice 2. Home: the lead's handbook (in use since 08:51Z). A parity check between `verify -f pins=true` and CI's fuzzer shards would not have caught this; this lane compares the two shard sets and builds the check only if they differ.
6. **A slice's lane lasts until the slice lands.** Hand-back is not the end: the lane that wrote a slice answers its rulings and does its replays. Home: the lane briefs.

One ROI line for the lookahead ledger: the rehearsal restacks of slices 3, 5 and 6 at 04:15Z to 04:33Z cost about 20 minutes each and none was replayed again for ten hours, so their realized value so far is slice 3's 45-minute final restack; slices 5 and 6 are on a base three heads old.
