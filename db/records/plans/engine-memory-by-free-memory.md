---
type: operational
id: 01m88bz0b79gx3a3d8505dd0yv
created: 2026-11-25T03:28:35.687407+00:00
updated: 2026-11-25T03:28:35.687407+00:00
summary: 'The engine''s memory is chosen at each start: 22 GiB, the whole model, when a 48 GiB Mac has room for it with 4 GiB to spare, else 12 GiB.'
title: Engine memory chosen by free memory
---
# Engine memory chosen by free memory

Status: asked for by the owner on November 24, 2026, to be planned, reviewed and built in full
([[sources/notes/2026/11/engine-memory-by-free-memory]]). Built, checked and installed the same
day; see [Results](#results).

## Why

Every Mac gave the engine 12 GiB. The model's weights are about 21.5 GB, so at 12 GiB Splash keeps
part of the experts in memory and reads the rest from the SSD. One run at each size on the 48 GiB
M5 Pro, Splash 1.7.2, 64K context, the context-profile harness (one workbook job and two recall
probes), with the model's files already in the file cache:

| | 12 GiB | 22 GiB |
|---|---|---|
| Workbook job | 18.8 s | 11.9 s |
| 17K and 45K-token probes | 11.1 s, 26.9 s | 7.8 s, 23.0 s |
| Decode | 94 to 106 tokens/s | 208 to 216 tokens/s |
| Prefill, the two probes | 2,017 to 2,739 tokens/s | 2,079 to 3,068 tokens/s |
| Experts | 8.3 GB in memory, 65% decode hits | all in memory |
| Footprint (macOS) | 11.8 GB | 21.3 GB |
| Reclaimable memory before, swap | 26.8 GiB; 5,460 MB, unchanged | same |

Every admitted task passed at both sizes. The prepared header resumed at both. Writing an answer
is about twice as fast when the model is whole; reading a long prompt barely changes.

## Decision

1. **Two sizes, both measured.** Streamed: 12 GiB. Resident: 22 GiB, which holds every expert
   beside 64K of context.
2. **Chosen when an engine starts**: the background start, a request or a workflow that finds no
   engine running. Resident when the Mac has at least 48 GiB and reclaimable memory (free,
   inactive, purgeable and speculative pages) is at least 22 + 4 GiB. Otherwise streamed.
3. **One headroom, 4 GiB**, for this choice and for the background start's room check, which
   was 6 GiB. The resident run left 4.8 GiB and swap did not move.
4. **A running engine keeps its size.** The size changes only at the next start: after the
   ten-minute idle release, memory pressure, Unload or quit.
5. **Splash's own `auto` budget is not used.** It plans from the Mac's total memory, not what is
   free, and would load every expert on a 48 GiB Mac whatever else is running.
6. **Unchanged:** context (64K at 48 GiB or more, 32K below); the memory-pressure response; a
   request that finds too little room still starts, at 12 GiB; the prepared header and
   `sevra header make`, made at 12 GiB.
7. **Model identity names the rule, not the size.** A saved workflow step or an answer waiting
   for input continues only under the same identity, so it must not change from one start to
   the next. The text changes once now, as at an engine upgrade. Each request's metrics record
   its engine's size (`requestedMemoryBytes`).

## Not in this plan

- Refusing a request when even 12 GiB does not fit, and a minimum memory for installing. Both are
  owner decisions.
- Sizes for Macs under 48 GiB, or above 22 GiB. Neither is measured, and at 64K more memory adds
  only context room the context limit does not use.
- Choosing the context by what a task needs.

## Build

1. `NativeWorkbookModel.Configuration`: `memoryBytes` stays the fixed size; an optional
   `chooseMemoryBytes` closure replaces it per engine. The worker calls the closure when it creates
   a session, and the session's configuration carries the result to the launch, the header
   restore and the metrics.
2. `NativeProductResources`: the two sizes, the headroom and
   `engineMemory(physicalMemory:reclaimable:)`. The product configuration passes it as the closure.
3. `ProductAI`: the background start checks room for the size it would choose; `hasRoom` uses the
   4 GiB headroom. The cached `engineBytes` goes.
4. The model identity text says "memory 12 or 22 GiB by free memory at start".

## Checks

Within the light testing rules:

- Model-free, in `sevra-product-checks`: the choice at 48 GiB with 26 GiB reclaimable (resident)
  and 25.9 GiB (streamed), at 36 GiB with 30 GiB reclaimable (streamed), with unknown reclaimable
  memory (streamed), and `hasRoom` at the new headroom.
- `dbmd index rebuild`, the build and the product checks.
- The light set once, `python3 scripts/check_chat_jobs.py --output DIR`, with the app quit; its
  metrics show which size each request started with.
- Install once and match the installed executable's UUID to the build.

Done when these pass and the change is committed and pushed.

## Results

November 24, 2026, on the 48 GiB M5 Pro:

- `sevra-product-checks` passes, including the four size choices and the 4 GiB room check.
  `dbmd validate` reports no issues.
- `scripts/install.sh` built and installed the app. The installed executable's UUID,
  `B311D3F6-937C-3A5C-AD48-56F4A44F71EF`, equals `output/native`'s, and both binaries carry the
  rule text.
- The light set, once: 11 of 11 passed on the first run, 30 model calls in 100 s. Every request
  ran under the new identity. The script keeps no metrics for passing jobs.
- One request through the installed CLI on a fresh demo workbook, with 30.8 GiB reclaimable,
  started its engine at 23,622,320,128 bytes (22 GiB). No engine was left running.

Not run on a Mac under 48 GiB, or with too little free memory to choose 22 GiB; the model-free
checks cover those choices.
