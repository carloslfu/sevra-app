---
type: operational
id: 01m8a3hq3c5ne8gk1tbf2wzr0a
created: 2026-11-25T18:00:00.000000+00:00
updated: 2026-11-25T18:00:00.000000+00:00
summary: 'After memory pressure releases the engine, Sevra starts it again smaller once pressure has stayed normal for 20 s, only while the owner is in the app, at most once until he uses it.'
title: Engine reload after memory pressure eases
---
# Engine reload after memory pressure eases

Status: asked for by the owner on November 25, 2026
([[sources/notes/2026/11/engine-reload-after-memory-pressure]]). Builds on
[[records/plans/engine-memory-sliding-size]]. Built, adversarially reviewed, fixed and installed
the same day; see [Review](#review) and [Results](#results).

## Why

Memory pressure releases the engine: at once when idle, after the request on a warning, with a
stop on critical. That frees the whole engine when other apps need it, which is right. The
engine then starts again at the next sign of use: the app coming forward, typing, a workbook
opening, a request. When pressure hits while Sevra stays in front, none of those come, and the
next message waits 11 to 15 s for a start, less what typing hides.

## Decision

1. **When macOS reports pressure back to normal and it stays normal for 20 s**, Sevra starts the
   engine again in the background, if the owner is in the app. The wait lets the app that
   caused the pressure settle and keeps Sevra from reacting to the memory its own release freed.
2. **Smaller than the engine pressure released, by at least 4 GiB**, and within what fits now
   (free less 4 GiB). An 8 GiB engine is not reloaded this way; it waits for use. Each reload
   after pressure is smaller, so a Mac that keeps running short converges instead of cycling.
3. **At most one such reload until the owner uses Sevra.** If pressure releases the reloaded
   engine too, Sevra waits for the next sign of use. A request or any start the owner causes
   clears that limit.
4. **Only a release by pressure arms it**, with an engine that was loaded. Unload, the idle
   timer, setup and quitting do not.
5. **Only while the owner is in the app**: Sevra active and not quitting. The CLI never reloads.
   Away from the app, coming back starts the engine as it does now.
6. **Pressure rising again during the 20 s, a request, a start already under way, a pending
   release or naming** each cancel or skip it. A request in the meantime starts its own engine
   and disarms the reload.
7. **Nothing new on screen.** A request sent during the reload waits for it with its progress,
   as during any background start.

## Build

1. `SevraAI`: `StartSize` (`chosen`, `growing`, `growingLoaded`, `atMost(bytes)`) replaces `resizing: Bool` in
   `WorkbookInference.prewarm`. `WorkbookInference.loadedMemoryBytes()` reports a running
   engine's size, nil by default.
2. `NativeWorkbookModel`: `atMost` caps a new session's chosen size; `loadedMemoryBytes` reads
   the session on the worker queue.
3. `ProductAI`: the pressure source adds `.normal` and routes it apart from warnings. Releases
   by pressure record the released size. A settle task, cancelled by any later pressure event,
   checks the conditions above and starts `atMost(released - 4 GiB)`. A host closure from the
   app answers the models folder while the owner is in the app, else nil.
4. `SevraApp`: sets that closure at launch: the folder when `NSApp.isActive` and not quitting.

## Checks

Within the light testing rules, model-free in `sevra-product-checks`, with a synthetic model, a
zero settle time and the host closure:

- A pressure release of a 20 GiB engine, then normal pressure: one start at most 16 GiB.
- The same with the owner away: no start. With an 8 GiB engine: no start.
- Pressure again during the settle: no start.
- A second pressure release after the reload: no second reload. After a request, it arms again.
- A release by Unload, then normal pressure: no start.

Then the build, the product checks, one install with the UUID matched, and the light set once.
An actual pressure episode is not induced: the machine's memory rules forbid it without the
owner's go.

## Review

An independent adversarial review of the whole memory machinery (sizes, growing, this reload)
found six problems. Each was confirmed in the code and fixed:

1. **A reply that pressure released started a full engine at once.** The after-reply grow called
   the ordinary start, which cleared the pending reload and loaded at full size. It now uses
   `growIfLoaded` (`StartSize.growingLoaded`), which only grows a running engine and never
   starts one.
2. **A pressure release waited behind a start or a reply** to read the engine's size on the
   worker queue. The worker now keeps that size under a lock, set and cleared with its
   session, and the release stops a start or naming before reading it.
3. **Pressure easing before the reload was recorded lost it**, since macOS reports each level
   once. The size is now recorded before the release, and recording it starts the wait when
   pressure is already normal; a request that held the engine through the ease still reloads.
4. **Pressure rising while the app was asked whether the owner is there did not stop the
   reload.** Every pressure event and every use by the owner now starts a new generation, and
   the reload checks it after each wait.
5. **A growing restart could come back no larger** if another app took memory meanwhile. The
   new engine is now never smaller than the one it replaced.
6. **A release that freed nothing kept a recorded size.** A failed release now restores what was
   recorded before it.

The review confirmed as sound: sizes and units, `atMost` on both paths, overlapping pressure
events, quitting, the main-actor hop, and that a level-change `.normal` behind a 20 s wait that
any warning cancels means normal for 20 s. Two limits remain: the idle timer stopping the engine
between the size read and the release can leave a recorded size, bounded by the owner being in
the app and by the one-reload limit; and the pressure source itself is not driven in checks.

## Results

November 25, 2026, on the 48 GiB M5 Pro, one run each:

- `sevra-product-checks` passes, with every case in Checks plus one per review finding: a request
  holding the engine through the ease, pressure rising during the owner check, and growing after
  a reply with no engine running.
- `sevra-agent-checks --resize`, after the worker changes: 8 GiB, kept by a plain start, grown to
  12 GiB, one correct answer on it, engine stopped afterwards.
- `scripts/install.sh` installed the app; the installed executable's UUID,
  `3176FA31-501D-3090-B6E3-59AF4AB9505F`, equals `output/native`'s.
- The light set: 11 of 11 on the first run, 34 model calls in 112 s.

Not run: a real pressure episode, which the machine's memory rules forbid without the owner's go.
