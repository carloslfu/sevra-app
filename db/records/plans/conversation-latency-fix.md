---
type: operational
id: 01m7nc1jrbsfn0cmkjmzpk4w1r
created: 2026-11-17T18:24:25.867198+00:00
updated: 2026-11-18T02:29:06.648862+00:00
summary: Bounded product conversation, stable prompt vocabulary and provisional answer delivery with measured replay and preserved authority.
title: Conversation latency and answer quality
---
# Conversation latency and answer quality

Owner request: [[sources/notes/2026/11/conversation-latency-fix]].

## Scope

Improve simple conversation without weakening business evidence, calculations or action authority. Use the unchanged Splash 1.6.1 engine, installed Qwen3.6 model and 12 GiB budget. Preserve existing user workbooks; qualify using disposable fixtures. No model download or OS setting change.

## Acceptance

- [x] Greeting and introductory product help use app-owned, bounded English/Spanish copy without loading inference. Compound/business requests keep the full agent. Vague follow-ups use the small route only after host-marked product help.
- [x] Stable prompt vocabulary preserves exact-ID grammar and terminal validation.
- [x] Only provisional finish.answer text is displayed while generating; reasoning and action arguments remain private. Retry, Stop and completion clear the preview; delayed updates cannot restore it.
- [x] Replay hey, what can you do for me?, tell me more and tldr. Record cold/warm timing, prompt/reasoning tokens, tool calls, actual answers and first-preview latency. Preserve failed iterations.
- [x] Verify an actual business-evidence counterexample and strict ID/citation refusal.
- [x] Run relevant regression, native package/install and installed UI checks.
- [x] Commit/push and verify the exact code CI.

## Findings

The initial investigation observed waits of 19, 14, 23 and 20 seconds. Every new turn had zero matched prompt tokens and a first-pass prompt of 13,041 to 14,727 tokens. About 61% of generated tokens were internal reasoning. Greeting inspected spaces; expansion discovered workspace actions. Cold setup explains only part of the first delay. Database reads and grammar-mask waiting were small. A fixed larger memory budget is not adopted because the diagnostic arm reported pressure warnings.

First implementation probe: greeting 10.30 seconds cold, capabilities 3.69 seconds warm. Expansion failed its length check and repeated the rejected candidate. Retain this failed trial; tighten the example and prevent a passing claim until the actual replay succeeds.


## Later iterations

A second all-model trial completed in 10.15, 3.57, 3.77 and 3.71 seconds, but independent semantic review rejected the summary: it claimed the hypothetical quote comparison had been performed. This trial is not passing quality evidence. Introductory help now comes from app-owned copy, with explicit durable identity `Sevra product help` and `backend=product-help`, rather than pretending that inference occurred. Vague follow-ups enter it only after a marked product-help reply. No changes to actual workbook facts or authority are inferred from those phrases. Pre-cancelled requests retain their diagnostic; help does not interrupt another process's running business task.

Three complete final introductory replays (12 replies) passed the actual agent/save path: 0.0055 to 0.0076 seconds, zero model calls, zero tools and no fabricated completed work. These are host-agent timings, not screen-paint or universal inference speed measurements.

The real-model counterexample still checks the existing synthetic brass-bolts balance of 18, its basis/effect citations, original-item preservation and workbook integrity. The first iteration's warm follow-up used four calls and 33.67 seconds because it copied host-added links from history and retried their formatting. Historical projection now separates citation lookup IDs from prose labels, leaving saved originals unchanged. The repaired replay passed both questions in two calls each, at 24.15 seconds cold and 14.55 seconds warm. The warm first call reused 4,096 prompt tokens. Provisional answer text arrived before completion and was cleared afterward. Full model work therefore still takes seconds; this is not a claim that general inference became instantaneous.

## Local acceptance and installation

The installed native executable UUID is `66DE9F08-606F-3EF6-A388-2B4B73EDC5D3`, matching the fresh packaged product. Its signature and resources verify; isolated native installation/update/uninstall, unrelated-CLI protection and extraction checks pass. The previous installed bundle was preserved locally. Relocation left an obsolete compiler module-cache path; preserving and rebuilding that generated cache repaired the build without recreating the former checkout.

The full repository check passed the 661 core groups, SDK, imports/recovery, lifecycle, text and authoring checks, then stopped at an obsolete test requiring exact-ID choices to enlarge the prompt. That assertion now requires identical prompt tokens for 0, 1 and 256 choices. Exact grammar masks and invalid-ID rejection remain required. The complete grammar/agent gate and every remaining script check were rerun and passed. No gate was disabled or budget enlarged. Native packaging checks used the new product separately.

The Streaming catalog variant is registered, rendered and visually reviewed at 900 points and a requested 520-point compact canvas (actual native minimum 740), including 1.5 reading scale. The provisional label, wrapping, Stop and composer do not overlap. Scripted catalog rendering does not qualify actual inference.

The installed app replayed the same four introductory messages in a disposable workbook. Complete answers were present at the first UI snapshots, 0.613, 0.589, 0.642 and 0.661 seconds after clicking Send, including control/snapshot overhead. All show 0s in activity; this is an upper bound, separate from the 5.5–7.6 millisecond agent/save measurements. The 22-word summary stays local and hypothetical examples do not claim completed work.

A separate full-UI cold stock question returned the correct 18 with both original citations, but took 38 seconds/four model calls, including two additional original-source reads. Its context includes native UI actions and differs from the minimal agent probe. Stop on another real request closed as cancelled, restored controls and saved no completed answer. No provisional text survived completion or Stop. This work solves the four introductory delays, reduces a measured history-repair loop and adds provisional delivery; it does not solve universal model latency.

The original user workbook's inspect, history and run snapshots remain unchanged. Disposable replay and stock workbooks both pass integrity. The updated preview is left open on the completed introductory replay. Portable synthetic evidence: [conversation latency receipt](../../../integration/evidence/2026-11-17-conversation-latency.json). Raw failed experiments and UI captures remain local and ignored.

## Publication verification

Code commit `1c97ab0b4038fae0b4f6a90568f7482eac56cd1c` is pushed to main and [hosted Checks](https://github.com/carloslfu/sevra-app/actions/runs/44154194013) passed. The portable receipt retains exact changed-code hashes, matching the measured and installed candidate. This publication receipt changes documentation only; installed UUID `66DE9F08-606F-3EF6-A388-2B4B73EDC5D3`, model, engine and tested behavior are unchanged. General model-latency, hardware and distribution limits above remain.

## Removal and exact-question trace, November 17

Carlos directed removal of the hardcoded introductory replies and an analysis of the observed four-call turn. The phrase matcher, authored answers and special request path are removed. Greetings and follow-ups use the ordinary model path. The routing check verifies the former matches reach inference with their submitted text, and the installed preview generated a new reply to “hey” in 18 seconds on the synthetic workshop workbook. Saved earlier replies still read as historical messages.

The exact question was “What is the current stock of brass bolts? Use the balance tool and cite the evidence. Do not change the workbook.” The original full UI run saved the balance at 16s, opening-source read at 24s, delivery-record read at 28s and final answer at 38s. Its two original reads consumed 11.83s in model invocations. The saved balance had already calculated 18 from the original inputs and supplied both citations for automatic attachment. The broad prompt says to inspect originals before citing. This plausibly encouraged the reads, although the request only asks for the cited balance.

A new cold actual-model replay with the exact same wording and fresh synthetic demo data dispatched only balance and finish. At 7.40s model startup and prompt preparation gave way to the first model call. It called balance at 15.20s; the host saved and projected that result about 8 ms later. The final model call began at 15.45s, matched 8,384 of 8,936 prompt tokens, and generated 512 reasoning tokens. The first provisional answer arrived at 27.59s, and the correct answer and two source links were saved by 29.45s. Workbook integrity and original items passed. These are observed choices with different prior conversations and presentation context.

The engine settings, evidence rules and general reasoning policy stayed in place for this diagnostic. Hosted and installed evidence for the earlier fixed replies remains in its dated scope. The [decision trace](../../../integration/evidence/2026-11-17-conversation-decision-trace.json) retains timing anchors, engine breakdowns and the new installed build identity.

## Native prompt and KV reuse, November 17
The native agent now puts the shared, permitted tool schemas and general workbook policy first. Scope-specific instructions and tools follow, ahead of historical messages. Current submission IDs, dates and host state follow history. Tool results append to that turn. The model still chooses each action. Exact citation, candidate and operation restrictions remain enforced by the grammar and host. Source excerpts remain untrusted. Spreadsheet conversion keeps its own policy and reasoning allowance.

The tokenizer can reuse the exact system-message tokens, and context admission and dispatch can reuse the same prepared request. The live helper primes the shared KV boundary and, when large enough, the scope boundary. Priming costs one discarded output token and never executes a tool. The engine reports how many tokens it actually resumed. Additional deduplication is recorded separately. A miss can re-arm an evicted checkpoint. Idle retention is ten minutes with explicit unload, process shutdown and memory-pressure release. KV stays in memory. A cold start still loads the model and pays for the first prefill.

The [five-turn measurement and per-call trace](../../../integration/evidence/2026-11-17-native-prompt-cache.json) uses the same real agent, model, machine, five messages and 125-second pause as the baseline. Times below are seconds. Prefill includes the entire explicit prime. Wall time includes model setup, tools and saving.

| Turn | Wall before | Wall after | Prefill before | Prefill after | First visible answer after |
| --- | ---: | ---: | ---: | ---: | ---: |
| Cold stock lookup | 30.84 | 25.67 | 5.73 | 8.09 | 21.62 |
| Rephrased stock question | 14.51 | 12.73 | 4.02 | 3.81 | 10.66 |
| First greeting, change in tool scope | 9.68 | 8.47 | 7.33 | 5.88 | 7.49 |
| Second greeting | 11.24 | 6.26 | 2.08 | 2.42 | 5.26 |
| Stock lookup after 125 seconds idle | 22.99 | 13.04 | 6.38 | 3.84 | 9.80 |

The shared 6,020-token header yielded 6,016 immediately resumed tokens on the rephrased question and after idle. On transition to the broader scope, its 10,989-token prime itself resumed 6,016 tokens. The next greeting resumed 10,976 with no prime. All three stock turns used balance then finish, returned 18, and cited the actual basis of 20 and delivery of −2. Both greetings used finish alone. Cold prefill and the already-warm repeated greeting took longer in this replay. Model loading, changed tail tokens and output generation still cost time. Local builds and the repository suite overlapped parts of this run.

The first layout put the large scope-specific schemas after history; one repeated greeting took 17.63 seconds and used two unnecessary tools. An intermediate desktop build repeated the same successful balance twelve times before hitting its step limit. Its screen context was appended to the submitted question, the inventory instruction asked for a balance on every pass, and the next-decision budget left little room to recover. The native template now separates screen context from the request. The balance returns the opening quantity and date. A verified calculation supplies explicit completion guidance and up to 128 reasoning tokens for the next ordinary read-only decision. The agent reuses an immediate duplicate by original receipt ID, permits distinct arguments and closes from available evidence after two consecutive duplicate attempts. Another replay produced an invalid count reference; the exact finish grammar now permits only count_records receipts from that run. Evidence and citations are still verified at completion.

The installed desktop preview replayed the original 38-second question in 20 seconds with two model decisions and one executed balance tool. The rephrased follow-up took 13 seconds. Both answers correctly cited the opening balance of 20 and delivery of 2. Eight separate real-model conversation-action cases passed. These results describe this Mac and these fixtures.

The regression entry point is `sevra-agent-checks --conversation-cache-trace MODELS_ROOT GUIDANCE_LIBRARY SPLASH_EXECUTABLE NEW_OUTPUT_DIRECTORY`. It saves answers, per-call metrics, first visible answer time and progress, and checks actual KV matches, citations, unchanged original items, preview clearing and workbook integrity. The context-accounting probe also compares cached tokens against a fresh canonical template, with hostile delimiters, Unicode, historical tool calls and different scopes.
