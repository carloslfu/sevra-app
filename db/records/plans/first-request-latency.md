---
type: operational
id: 01m7znqk3eh5x0fhfxthaekadp
created: 2026-11-21T18:26:08.622746+00:00
updated: 2026-11-21T18:26:08.622746+00:00
summary: The first answer waited for the engine and read half the prompt again. Prewarm, one header for every chat turn, and reads by real IDs cut "hi" from 14 s to 3.7 s.
title: First request latency
---
# First request latency: prewarm, one header for every chat turn, and reads by real IDs

Owner request: [[sources/notes/2026/11/first-request-latency]]. Status: built, checked and measured on November 21, 2026. Not committed.

## What the 14-second "hi" spent

A new thread in the installed app answered "hi" in 14 seconds. Its saved metrics and one cold command line run on a copy of the same workbook give this, in seconds:

| Phase | Time |
| --- | ---: |
| Session setup: model files, tokenizer, grammar, header check (not saved by the app; from the cold run) | 1.3 |
| Engine start: header restore, process, model load, 11 warm-up steps, status check | 4.8 |
| First decision: prefill of 3,032 tokens after 2,752 resumed | 2.2 |
| First decision: 64 thinking tokens, then a read of an earlier message by a made-up ID | 3.0 |
| Second decision: prefill of 257 tokens, then 37 thinking tokens and the answer | 3.3 |

The prepared header was resumed in full: 2,752 of its 2,770 tokens, the last complete 32-token page. It covered half of the 5,784-token prompt. The 1,819 tokens after it, the chat scope instructions and the `save` declaration, were read again on every cold first decision. The follow-up "ho" resumed only the header and read 3,476 tokens again. A later decision in the same conversation that changed tool scope showed fewer tools and resumed only 2,528 tokens.

## Causes and fixes

1. **The engine started at Send.** `ProductAI.prewarm` starts the session and engine with no request when a workbook opens, and again when typing starts after the idle timer stopped it. It takes the inference lock like a run and then follows the ordinary 10-minute idle release and memory-pressure release. A request waits for a start under way, and unloading or quitting cancels it first. A failed prewarm is silent; the request that follows reports the failure. Each request now also saves `sessionSetupSeconds`, which was the one unmeasured phase; a session the prewarm made reports zero.
2. **The header held only part of what every turn shares.** Chat now shows the same seven tools in every chat scope, and the scope instructions are part of the header's instructions, so the header grew from 2,770 to 5,234 tokens and has no scope block after it. A read-only turn keeps its own note after the header, and the grammar still offers only what each scope allows. The no-model header check now requires every chat scope, with and without app building, to have the header's inputs.
3. **A follow-up after a new conversation's first turn resumed only the header.** With no saved history, the first turn has no point at the end of its history, so the follow-up fell back to the header checkpoint. With the scope block in the header, that checkpoint now covers everything before the history.
4. **`read` accepted any ID.** The seven general tools replaced `history_read`, whose IDs the grammar limited to messages in the context. The general `read` took `ref` as free text, so a made-up message ID cost a whole decision. The tool grammar dialect now accepts alternative closed shapes at the root of a tool's arguments. In the grammar only, `read` offers a message only by an ID this context shows, a document or record only by a known item ID, and each kind only when something of it is known. The prompt shows the same declaration as before, so the header does not change with the choices.
5. **The first decision's 64-token thinking limit stays.** It was the trigger, not the cause: after the read fix, "hi" used 20 of its 64 tokens and answered in one decision.

## Measurements after the fixes

All on this Mac with the installed model, one run each, on copies of the same workbook.

| Run | Before | After |
| --- | ---: | ---: |
| App path, "hi" in a new thread, Send to answer | 14 (2 decisions) | 3.68 (1 decision) |
| App path, follow-up "ho" | 5.10 (model time) | 4.33 (whole turn) |
| Engine start, now before Send | at Send | 6.52 ahead |
| Command line, cold "hi" (cannot prewarm) | 14.50 | 12.66 |
| Header resumed on a first decision | 2,752 of 5,784 | 5,216 of 6,407 |

After the fixes, the "hi" decision read 1,191 tokens in 1.63 s and generated 80 tokens in 1.95 s, with the first answer text at 2.74 s. The follow-up resumed 5,216 tokens and read 1,352. The app-path figures come from `sevra-product-checks --first-request MODELS_ROOT PACKAGED_BIN WORKBOOK`, which builds the product's model configuration from a packaged build, prewarms the engine, then sends both messages as composer input in a new thread. `--first-request-prompt TOKENIZER WORKBOOK` prints what a composer turn reads after the header, without the model. Launching the installed app on a workbook copy started its engine 1.6 s later with no message sent.

## Checks

- No model: header checks, the grammar checks with 769 reference masks and 11 new `read` cases, the default agent suite, and the product lifecycle checks with a new prewarm check.
- The light set, once on the packaged build: 11 of 11 in 29 decisions and 3 minutes 33 seconds.
- Packaged and installed; the installed executable UUID matches the packaged build.

## What is left

- Every request pays about 0.85 s of prefill inside the engine before any token, plus about 0.45 ms per new token. A turn reads about 820 tokens after its history: host state with fixed notices, and the chart and question instructions. Moving the stable part into the header would save about 0.1 s, so it was left.
- Decoding, mostly hidden thinking, is now the largest part of a warm turn.
- The engine start itself, about 1.3 s of setup and 4.5 s of start, still takes that long; prewarm moves it before Send rather than removing it. A request sent sooner than that after opening a workbook waits for the rest.
