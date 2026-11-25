---
type: operational
id: 01m89ba964zv0k5zred0dsppqr
created: 2026-11-25T12:36:31.000000+00:00
updated: 2026-11-25T12:36:31.000000+00:00
summary: 'The engine takes free memory less 4 GiB, from 8 to 20 GiB, at each start, and restarts larger when the app comes forward with at least 4 GiB more room.'
title: Engine memory that follows free memory
---
# Engine memory that follows free memory

Status: planned and reviewed on November 25, 2026, at the owner's request
([[sources/notes/2026/11/engine-memory-sliding-size]]). He then wrote "Yes, build it". Built,
checked and installed the same day; see [Results](#results). It replaces the two sizes of
[[records/plans/engine-memory-by-free-memory]].

## Why

Today the engine starts at 22 GiB on a 48 GiB Mac with 26 GiB reclaimable, else at 12 GiB, and
keeps that size while it is loaded. One run per size on the 48 GiB M5 Pro, Splash 1.7.2, 64K
context, the context-profile harness (one workbook job and two recall probes), model files in
the file cache:

| Engine memory | Decode | Prompt reading, 17K and 45K probes | Engine start |
|---|---|---|---|
| 8 GiB | 31 to 37 tokens/s | 8.1 s, 24.6 s | 10.9 s |
| 12 GiB | 94 to 106 tokens/s | 6.4 s, 20.8 s | 14.9 s |
| 16 GiB | 132 to 164 tokens/s | 5.9 s, 19.0 s | 12.9 s |
| 19 GiB | 179 to 213 tokens/s | 6.1 s, 21.3 s | 12.9 s |
| 20 GiB, measured in the build | 187 to 229 tokens/s | 5.6 s, 18.6 s | 11.4 s |
| 22 GiB | 208 to 216 tokens/s | 5.7 s, 20.2 s | 10.6 s |

Every admitted task passed at every size, and the prepared header resumed at each. The start is
the first job's time less its request: launch and header restore with the files cached. No run
moved swap.

What follows from this:

- **Speed rises steadily up to about 19 GiB**, roughly 15 tokens/s for each GiB, then flattens:
  22 GiB adds under 10% for 3 GiB. Two sizes leave a Mac with 24 GiB reclaimable at 12 GiB, where
  20 GiB would write about twice as fast.
- **Prompt reading hardly depends on memory** above 8 GiB. Memory buys writing speed.
- **8 GiB is slow but works.** A slow answer is better than none.
- **A restart costs 11 to 15 s** with files cached, plus reading the conversation again beyond
  the prepared header: seconds for a short chat, 6 to 21 s at 17K to 45K tokens. The light set
  averages under three model calls a job; at up to 500 output tokens each, writing takes up to
  about 44 s a job at 8 GiB, 15 s at 12 GiB, 10 s at 16 GiB and 7 s at 20 GiB. Growing from 8 or
  12 GiB pays back within a few jobs; from 16 GiB it saves about 3 s a job and would take many.

## Decision

1. **Size at each start: reclaimable memory less 4 GiB, rounded down to a whole GiB, at least
   8 GiB and at most 20 GiB.** Reclaimable is free, inactive, purgeable and speculative pages,
   as now. Unknown reclaimable memory gives 8 GiB. The Mac's total memory no longer enters the
   size, only the context (64K at 48 GiB or more, 32K below), which is unchanged.
2. **20 GiB is the cap**: between the measured 19 and 22 GiB, it keeps almost all of the speed
   and leaves 2 GiB more to other apps than the whole model would. The build measures it once.
3. **A background start needs room**: reclaimable at least 8 + 4 = 12 GiB. Below that it waits
   for Send, as now. A request always starts, at 8 GiB if memory is short, gentler than today's
   12 GiB.
4. **Moving up: only an engine of 12 GiB or less, only by at least 4 GiB.** Growing from there
   doubles or triples writing speed; from 16 GiB the gain does not repay the restart. The engine
   stops and starts again at the new size, as a background start, when it is loaded and nothing
   is using, starting or naming with it. The loaded engine's memory is not counted as free, so
   the decision is conservative, except after Splash's own ten-minute idle release has freed
   it, when a restart costs little more than the reload the next request would need anyway. The
   new size is chosen again once the old engine has stopped, so it can use that memory too.
5. **Two moments ask for it, both while the owner is in the app:** the app comes forward, when
   other apps have just been closed; and a reply ends while the app is in front, after its naming,
   so an engine a short-memory request started small does not stay small all session. A request
   sent during the restart waits for it and sees its progress, as during any background start.
   Not typing, which comes seconds before Send; not a timer, which could take memory while the
   owner is away; not a request, which wants its answer now. A start that finds no engine starts
   one as now, and one that finds the engine at its size keeps it and restarts the idle timer,
   as now.
6. **Moving down stays as it is.** Memory pressure releases the engine (after the request, or at
   once with a stop when critical), the idle timer releases it after ten minutes, and the next
   start chooses again. Splash cannot shrink a loaded model by much: a loaded whole model gives
   nothing back, and a streamed store keeps at least 85% of itself.
7. **Model identity names the new rule** ("memory free less 4 GiB, 8 to 20 GiB, at start"). Saved
   continuations from before the change end once, as at an engine upgrade. Each request's
   metrics keep the engine's size in `requestedMemoryBytes`.
8. **Fixed 12 GiB stays where it is used now**: `sevra header make` and the harnesses that set
   `memoryBytes` without a choice.

## Not in this plan

- Shrinking a running engine, which needs Splash. Sevra keeps the engine unchanged.
- A minimum Mac or a refusal when even 8 GiB does not fit. Owner decisions.
- Proof on Macs under 48 GiB. The numbers above read streamed experts through this Mac's file
  cache and fast SSD. A smaller Mac caches less, so its streamed sizes may be slower.
- A note in the interface when memory makes answers slower.
- Choosing the context by what a task needs.

## Build

1. `EngineMemory` (`NativeProductResources.swift`): `floor` 8 GiB, `cap` 20 GiB, `headroom` and
   `step` 4 GiB, `fixed` 12 GiB for the header and harnesses. `choose(reclaimable:)` applies
   decision 1; `grows(loaded:chosen:)` is `loaded <= fixed && chosen >= loaded + step`. The rule
   text follows decision 7. `resident` and `streamed` go; `largeMac` stays for the context tier.
   `MemoryChoice` gains `grows: (loaded) -> Bool`, which reads free memory when called, since
   `SevraNativeAI` cannot see `EngineMemory`.
2. `WorkbookInference.prewarm` gains `resizing: Bool`; the synthetic models take it. In
   `NativeWorkbookModel.prewarm` the lock and `active` are held from `beginRun` to `endRun` as
   now. On the worker queue, with `resizing`, a running session whose `grows` holds for its size
   is closed, and the same `perform` that follows checks
   cancellation and creates the new session. Stop and start share one lock, one queue item and
   one cancellation, so no request, CLI process, Unload or idle timer fits between them. A close
   that fails leaves the engine as it is, as it does today.
3. `ProductAI.prewarm(modelDirectory:resizing:)`, `resizing` false by default, passes it on. The
   room check uses `choose(reclaimable:)`. The start task already makes requests wait, keeps
   naming from starting, and is cancelled by Unload and memory pressure.
4. `resizing: true` from `applicationDidBecomeActive` through `WorkspaceState.prewarmLocalAI`,
   and from `WorkspaceState.nameWork`'s task once naming has ended, when `NSApp.isActive`. The
   launch, workbook and typing starts keep false.
5. Records: this plan's status and results; the earlier plan's status points here.

## Checks

Within the light testing rules:

- Model-free, in `sevra-product-checks`: `choose` at unknown memory (8), 10 GiB (8), 16.5 GiB
  (12), 23.9 GiB (19), 24 GiB (20) and 40 GiB (20); `grows` at 8 to 12 and 12 to 16 (yes), 12 to
  15 and 16 to 20 (no); the room check at 12 GiB and 1 byte less.
- Model-free, with a synthetic model that records `resizing`: `ProductAI.prewarm` passes it only
  when asked, and a request during a resizing start waits for it. The two app call sites are
  one-line reads in review.
- One native resize check in `sevra-agent-checks`, beside the context profile, with the model: a `MemoryChoice` that gives 8 GiB, then 12 GiB with
  `grows` true, run only after reading at least 16 GiB reclaimable, so the simulated choice never
  exceeds the actual reading. The engine starts at 8 GiB, a resizing start moves it to 12 GiB,
  one request answers with `requestedMemoryBytes` at 12 GiB, and the engine is confirmed stopped
  afterwards.
- One context-profile run at 20 GiB, after confirming at least 24 GiB reclaimable, with the
  engine confirmed stopped afterwards. If its decode stays under 179 tokens/s, the lowest at
  19 GiB, stop and report before keeping the cap.
- `dbmd index rebuild`, the build, the product checks, the light set once, and one install with
  the installed executable's UUID matched to the build.

Not run: a move up in the installed app from real memory change. It needs memory taken away at
the start, which the machine's memory rules forbid without the owner's go. The native resize
check covers the same path with a bounded choice.

Done when these pass and the change is committed and pushed.

## Results

November 25, 2026, on the 48 GiB M5 Pro, one run each:

- `sevra-product-checks` passes, with the six size choices, the five growth cases, the 12 GiB
  room check, and a request waiting for a resizing start. The app and both check tools build.
- 20 GiB: every admitted task passed, decode 187 to 229 tokens/s, above the 179 tokens/s bound.
  The cap stays.
- The resize check, `sevra-agent-checks --resize`, with 31.7 GiB reclaimable: a plain start at
  8 GiB, a second plain start that kept it, a resizing start that moved it to 12 GiB, and a
  request that answered 18 on the 12 GiB engine. The engine was stopped afterwards.
- `scripts/install.sh` installed the app. The installed executable's UUID,
  `0EFF511E-BD9D-3294-968F-7B4BE3E8970C`, equals `output/native`'s, and both binaries carry the
  rule text.
- The light set: 11 of 11 passed on the first run, 34 model calls in 93 s, every request under
  the new identity.

Before the model runs, Splash.app was found serving the same model with 7.1 GiB free; the runs
waited until the owner quit it. Not run: a move up from real memory change in the installed app,
and any Mac under 48 GiB.
