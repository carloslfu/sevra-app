---
type: operational
id: 01m825qdf8dt9kd5yaxyawt1cc
created: 2026-11-22T17:44:08.936320+00:00
updated: 2026-11-22T17:44:08.956730+00:00
summary: 'Debug-mode chat timing and one measured five-message conversation: 96% of reply time is the engine, and the number of model calls per message decides it.'
title: Chat response time
---
# Chat response time: where each turn's time goes

Owner request: [[sources/notes/2026/11/chat-response-time-analysis]]. Status: debug timing built, and one five-message conversation measured on November 22, 2026. Ways to make it faster are left for later, as he asked. Nothing here changes behavior, prompts or engine settings.

## The answer in short

In the measured conversation, 96% of the time from Send to the finished reply was the engine: reading the prompt (28%), hidden reasoning (33%) and writing the tool call or answer (35%). Waiting for the engine to finish starting took 3%, only on the first message. Everything the app does around the model, including the database, tools, prompt building and context maintenance, took 1.1%.

What decides how long a message takes is how many model calls the model chooses to make. Each call costs about 1 second before its first token, plus its reasoning and its output. Two of the five messages used 6 and 4 calls instead of 1, and those later calls were 60% of the whole conversation's time.

The conversation's length does not make a message slower by itself: each follow-up resumes the previous turn's cache. What a follow-up pays again is the previous turn's new entries, including its tool calls and results, and about 630 tokens of host state and request after them.

The interface's own steps are timed but were not measured here. Carlos declined control of the app's interface for this run, so the conversation went through the product layer the app uses.

## The path of one message

1. **Send** ([WorkspaceState.swift](../../../Sources/SevraApp/WorkspaceState.swift)): `send()`, then `runChat`, which saves workflow drafts, yields to automation and calls `ProductAI.run` with the current view as context.
2. **Product** ([ProductAI.swift](../../../Sources/SevraProduct/ProductAI.swift)): waits for an engine start under way (the app starts the engine when a workbook opens), then takes the model.
3. **Agent setup** ([WorkbookAgent.swift](../../../Sources/SevraAI/WorkbookAgent.swift)): the inference lock, the table and tool listings, saving the request and its source.
4. **Context maintenance** ([ContextMaintenance.swift](../../../Sources/SevraAI/ContextMaintenance.swift)): reads the history, builds the messages, and measures the full prompt and the minimum prompt, each by building and tokenizing it. It summarizes only past the maintenance threshold, which this conversation never reached.
5. **Each step**, up to 12: annotate references, measure the context again, then one model call ([NativeWorkbookModel.swift](../../../Sources/SevraNativeAI/NativeWorkbookModel.swift)). The call builds the prompt (or reuses one built moments before), compiles the grammar and sends the tokens to the engine. The engine resumes its cache, reads the rest (prefill), then decodes hidden reasoning and the tool call, asking the host for a grammar mask at every decode cycle. Then the host runs the tool, bounds its result, runs maintenance again and starts the next step. A `finish` call saves the answer.
6. **Back on screen**: the streamed answer text reaches the main thread as it is written, the request returns, and a refresh reads the saved reply from the workbook and draws it.

## Debug timing: how to turn it on and read it

Off by default. When off, each timer is one check of a value read once per process, and nothing is written.

- **App:** `defaults write com.sevra.workbooks SevraChatTiming -bool true`, then reopen Sevra. `defaults delete com.sevra.workbooks SevraChatTiming` turns it off.
- **Command line and check harnesses:** `SEVRA_CHAT_TIMING=1`. `SEVRA_CHAT_TIMING_LOG=PATH` writes somewhere other than the default.
- **Log:** one JSON line per chat turn in `~/Library/Logs/Sevra/chat-timing.jsonl`, plus one line for each engine start ahead of a request (kind `prewarm`). Times are seconds from Send (from `product.run` when there is no screen). No message text, arguments, results or answers are written. Nothing leaves the Mac.
- **Read it:** `python3 scripts/chat_timing.py` prints each turn as a nested list of steps, then one comparison row per turn. `--compare` prints only the table, `--last N` the last N records, `--all` adds each background refresh read. `--self-test` checks the reader without a log.

### What is timed

[ChatTiming.swift](../../../Sources/SevraCore/ChatTiming.swift) holds the timers. One turn is open at a time, as one request uses the model at a time.

| Layer | Steps |
| --- | --- |
| Interface ([WorkspaceState.swift](../../../Sources/SevraApp/WorkspaceState.swift)) | `ui.send`, `ui.task_started`, saving workflow drafts, yielding to automation, `ui.request_saved` and `ui.request_attached` (the message bubble), `ui.first_answer_text`, `turn.request_finished`, `ui.reply_in_view` (the saved reply in the chat's messages) and `ui.reply_drawn` (the next main run-loop pass, after SwiftUI lays out and draws it). Each background refresh read and its message preparation. How late progress and answer-text updates reach the main thread, and main-thread lateness over 20 ms from a 50 ms watch |
| Product ([ProductAI.swift](../../../Sources/SevraProduct/ProductAI.swift)) | waiting for an engine start under way, building the model configuration, the prewarm record |
| Agent ([WorkbookAgent.swift](../../../Sources/SevraAI/WorkbookAgent.swift), [ContextMaintenance.swift](../../../Sources/SevraAI/ContextMaintenance.swift)) | the inference lock, table and tool listings, saving the request and its source, context maintenance (history read, messages built, references annotated, the full prompt and the minimum prompt measured, a summary when it compacts), and per step: reference annotation, context measurement, the model call, the tool's run, bounding the tool result, maintenance after the tool, saving the answer |
| Model ([NativeWorkbookModel.swift](../../../Sources/SevraNativeAI/NativeWorkbookModel.swift)) | waiting for the inference queue; session setup (engine file hashes, model files, tokenizer, grammar library, header check); engine start (header restore, launch with each warm-up step, status check); prompt building and tokenizing, or reuse of a prompt already built; grammar compile; prefix prime; the engine request, with when the engine admitted it, the first tokens, the switch from hidden reasoning to the answer and the first answer text, the engine's own prefill and decode, resumed and computed tokens, draft tokens, grammar mask count and host time, and host time handling events; parsing and validating; and the saved per-call metrics |
| Workbook ([Workbook.swift](../../../Sources/SevraCore/Workbook.swift)) | total wait for the workbook's lock, split by main thread and others |

## The measured conversation

One run on November 22, 2026: Apple M5 Pro with 48 GB, macOS 26.6.2, Splash 1.6.1, Qwen3.6 35B A3B 4-bit with DFlash 2, 64K context, 12 GiB engine budget, the 3,809-token prepared header. A copy of the owner's usual chat workbook, which holds only earlier chats and no business tables or documents. A new chat, five messages in English:

```sh
SEVRA_CHAT_TIMING=1 SEVRA_TRACE_PAUSE=4 SEVRA_PROMPT_HEADER=.build/prompt-header \
  sevra-product-checks --first-request MODELS_ROOT output/native/bin WORKBOOK_COPY \
  "hi" "what can you do for me?" "tell me more about the first one" "what's in this workbook?" "thanks"
```

The harness builds the product's model configuration from the packaged build, starts the engine as the app does when a workbook opens, waits 4 seconds, as a person reading and typing, and sends each message as composer input with the context the app sends from Home. It is one process, so the engine and its cache stay warm between turns, as in the app. It was a release build with testing enabled, so host times are at release speed. The engine's resident memory stayed near 2 GB, with its weights mapped from disk, and swap stayed at zero. The log and comparison are in [the evidence](../../../integration/evidence/2026-11-22-chat-timing/README.md).

| Message | Reply done | First answer text | Model calls (tools) | Engine | Prefill | Reasoning | Output | Host |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| hi | 5.11 | 4.30 | 1 | 3.20 | 1.35 | 0.54 | 1.29 | 0.03 |
| what can you do for me? | 7.11 | 3.10 | 1 | 7.04 | 1.32 | 1.18 | 4.53 | 0.08 |
| tell me more about the first one | 33.52 | 31.55 | 6 (read, search, read, read, read) | 33.20 | 8.38 | 15.78 | 9.00 | 0.31 |
| what's in this workbook? | 15.93 | 14.10 | 4 (search, sql, a refused finish) | 15.69 | 5.62 | 3.26 | 6.81 | 0.24 |
| thanks | 5.10 | 4.13 | 1 | 5.02 | 1.93 | 1.58 | 1.51 | 0.09 |

Seconds from Send. Reasoning is from the first generated token to the end of hidden reasoning, and output is the rest of the call: the tool call, or for `finish` the answer. "hi" also waited 1.86 s for the engine start; host is everything outside the engine and that wait.

## Where the time goes

### Starting the engine, once

The engine start took 6.07 s from opening the workbook: 1.38 s of session setup (0.62 s loading the tokenizer, 0.69 s loading the grammar library, 0.05 s checking the header, 0.03 s hashing the engine files), then 4.69 s for the engine process: 1.94 s from launch to the start of its warm-up, which includes loading the model, and 2.71 s for 11 warm-up steps, the first of which took 1.25 s. "hi" was sent 4.2 s after opening, so it waited the remaining 1.86 s. A message sent after the start finishes waits for none of it, and no later message pays it again while the engine stays up (ten idle minutes, or until memory pressure).

### Each model call

- **Before the first token: about 1 second, plus 0.38 ms per token not already computed.** Over the 13 calls the engine's prefill fits 1.02 s + 0.38 ms per computed token, from 0.75 s for 153 tokens to 2.30 s for 3,741. Time to first token equals prefill within a few milliseconds, and the engine admitted each request within 26 ms. Prompt length itself, 4,400 to 9,400 tokens here, added nothing measurable. The fixed second is inside the engine, and the host cannot see its parts.
- **Decoding: about 50 tokens a second.** 2,264 tokens in 45.5 s: 605 decode cycles of about 75 ms, each yielding 3.7 tokens with 39% of draft tokens accepted. The host's grammar masks, computed synchronously at every cycle, took 1.29 s of that.
- **Hidden reasoning is the largest part.** 1,247 of the 2,264 generated tokens were reasoning. The first decision of a chat turn may reason 64 tokens, and later decisions 512. The search call in "tell me more about the first one" used all 512, 8.5 s on its own, the largest single item in the conversation.
- **Output.** The first answer text appears 0.35 to 0.59 s after reasoning ends, the time to write the opening of the `finish` call before its answer. A long answer is written at decode speed: the 232-token capability list took 4.5 s.
- **Host work per call is small.** Building and tokenizing the prompt took 6 to 24 ms and happened two or three times a step (maintenance measures the full and the minimum prompt, then the step measures again). Compiling the grammar took 7 to 8 ms, running a tool at most 1 ms in this workbook, bounding its result 3 ms, maintenance after a tool about 30 ms, and saving the request and its source 7 to 13 ms. Each step's host work came to about 50 ms.

### How many calls a message takes

This is the deciding variable. "hi", "what can you do for me?" and "thanks" took one call each. "tell me more about the first one" took six: the model read its own request source, searched for its earlier answer, read the request again, and read it twice more, where the host answered each repeat with "This exact call just ran", before it finished. The earlier answer it needed was already in the saved conversation in its prompt. "what's in this workbook?" took four: a search, an SQL listing of tables, then a `finish` that the host refused for claiming the workbook was empty from search alone, then a second `finish`. The calls after the first in a message took 40.4 s of the conversation's 66.8 s.

### First message and follow-ups

- **Paid once:** the engine start, 6.07 s, before the first message or overlapping it.
- **Paid by every message:** about 1 s before the first token of each call, the reasoning, the output, and about 630 tokens after the history (host state, the request and its visible context) computed again on every message's first call. With nothing else to read, that is what "hi" computed: 627 tokens past the header.
- **Paid by the next message:** what the previous turn added to the conversation. The first call resumed the prepared header on the first and second messages (3,808 tokens), because a first message has no history to leave a resume point in. From the third message on it resumed where the previous turn's history ended: 3,936, 4,224 and 7,136 tokens. It then computed the previous turn's new entries plus the tail: 825, 1,020, 3,741 and 2,242 tokens. The 3,741 after the six-call turn were mostly its saved tool calls and results, and took 2.30 s of prefill against 1.32 to 1.93 s for the others.
- **What grows:** the prompt, from 4,435 tokens on the first call to 9,378 on the fifth message's first call. Its length did not slow prefill or decoding measurably at this size. The conversation never reached the maintenance threshold, so no summary was made.
- **"hi" against "thanks":** 3.20 s and 5.02 s of model time for the same kind of reply. "thanks" computed 2,242 tokens instead of 627 (0.58 s more prefill), reasoned 64 tokens instead of 26, and wrote a longer reply.

## Not measured, and limits

- **The interface.** Its timers are in place (Send, the request bubble, the first answer text on screen, how late updates reach the main thread, refresh reads, the saved reply in view and drawn, main-thread stalls and workbook lock waits), but this run had no screen. Turning on `SevraChatTiming` in an installed build of this code and chatting fills them in.
- **Workbook lock and database.** No lock waits happened: there were no interface refreshes competing with the agent. With the interface, each progress update starts a background refresh read under the same workbook lock as the agent's saves.
- **One run, one machine, one workbook with no business data.** Model decisions vary between runs, so the call counts above are what this run did, not a rate. Tools ran in at most 1 ms here because the workbook holds no tables or documents; real data would add tool time and larger results.
- **The engine's fixed second before the first token** is the engine's own figure. The host sees only its total.
- **The answer timing above is from the engine's stream.** On screen it would also include the hop to the main thread and drawing, which the interface timers measure.

## Checks

- No model: `sevra-agent-checks --conversation-latency-checks` and the `sevra-product-checks` lifecycle checks pass with `SEVRA_CHAT_TIMING=1`. The product checks wrote 14 records, and nothing is written with timing off. `python3 scripts/chat_timing.py --self-test` passes.
- The packaged build (`bash scripts/build_native.sh`) builds and seals the unchanged 3,809-token header. It was not installed: the app was open and its interface was not available for this run.
- One real-model conversation, as above.
