---
type: operational
id: 01m7qevmqegzcztj7bqb2x02r0
created: 2026-11-18T13:52:05.870578+00:00
updated: 2026-11-18T14:22:32.911408+00:00
summary: 'Follow-ups recompute every earlier turn. Plan: append-only history and a replay state at its end, with real-model acceptance.'
title: Resume follow-up turns from the previous turn's cache
---
# Resume follow-up turns from the previous turn's cache

Status: implemented on top of `9d044b2`. CPU checks and real-model acceptance pass; the repository gate result is under Results.

## Finding

A follow-up message resumes only the fixed prompt header. Everything after it, including
earlier turns already computed, is computed again on every follow-up.

Two cold two-turn replays on the test Mac measured this on product code `a41c05e`. The first
call of each follow-up resumed at 10,976 tokens, the scope block's checkpoint, and computed
977 and 1,580 tokens. The engine's own counters agree: in all nine calls, its deduplicated
tokens equal the whole pages it computed again between the resumed state and the longest
prompt prefix it already held. The [[records/plans/conversation-latency-fix]] five-turn
trace shows the growth: its fourth turn computed 1,632 tokens that the previous turn had
already computed.

Two causes combine.

1. [ContextMaintenance.swift](../../../Sources/SevraAI/ContextMaintenance.swift) renders the
   saved conversation as one JSON array. A new turn adds entries before the closing `]`, so
   the previous prompt stops being a prefix about 90 tokens after the header.
2. Splash resumes only from a captured state, because the target's GDN layers carry
   recurrent state. A request publishes its replay state at the last whole 32-token page
   before its generation prompt (`Engine::promptReplayBoundary` in Splash 1.6.1). That is the
   end of the prompt, after the host state, request rules, visible context and request that
   the next turn replaces. Rolling checkpoints every 4,096 tokens and lazy junctions at least
   2,048 tokens past a state do not cover this boundary.

## Change

1. **Append-only history.** Render the saved conversation as one JSON object per line,
   each line ending in a newline, with the same per-entry view as today. Mark the message as
   the conversation history. A later turn then only appends lines.
2. **Replay state at the end of history.** `NativePreparedRequest` records a token four
   tokens before the history's end token. The template trims the final newline, so the last
   entry's closing tokens merge differently once a later turn appends a line. On the
   first decision of an interactive request, the dispatch sets `generationTokens` so the
   engine's replay state lands on the last whole page of the history. The engine uses that
   field only for this boundary. Later decisions in the same request keep the default, so
   each tool step still resumes where the previous call stopped.
3. **Priming.** Skip a header or scope prime when a known replay prefix deeper than it
   starts the prompt. Forget a replay prefix when a later resume falls short of it, as the
   existing checkpoint rule already does.
4. **Metrics.** Record the requested replay boundary on each call.

A follow-up's first call then computes the previous turn's saved entries and the new
request, independent of how long the conversation is. The second decision of a multi-call
request recomputes the request tail it no longer resumes past, about 900 tokens. At the
measured marginal rate of 0.28 ms per token that is about 0.25 seconds.

Unchanged: the tool schemas and scope split, each entry's content, context maintenance and
the [[records/plans/native-chat-prompt-routing]] tool-group plan, whose header stays ahead
of history. A scope change between turns still resumes only the shared header. After
context maintenance, the first turn resumes the header and later turns append again.

## Acceptance

- **Layout, tokenizer fixture.** For consecutive turns, the later prompt starts with the
  earlier prompt through the earlier history boundary. The boundary lies inside the history
  and on its final line. A prompt without history has no boundary.
- **Agent fixture.** Over two turns, the second saved conversation starts with the first.
  Only the first decision of a request carries the boundary.
- **Existing checks.** Conversation surfaces, grammar fixtures, context threshold checks and
  the full agent suite pass.
- **Real model.** Repeat the two-turn sequences and a four-turn sequence on the same Mac.
  Each same-scope follow-up resumes past the scope block, at the previous turn's history
  boundary, and its computed tokens exclude turns before the previous one. Answers keep the
  correct values and citations. Swap does not grow. `--conversation-cache-trace` asserts
  that same-scope follow-ups resume past the scope block, and scope changes still resume
  the shared header.
- **Gate.** `dbmd index rebuild`, then `scripts/check.sh`.

## Results

**Implemented, November 18.** [ContextMaintenance.swift](../../../Sources/SevraAI/ContextMaintenance.swift)
renders one entry per line under `savedConversationHeader` and marks the message
`conversationHistory`. [NativePreparedRequest.swift](../../../Sources/SevraNativeAI/NativePreparedRequest.swift)
exposes `historyBoundary`. [NativeWorkbookModel.swift](../../../Sources/SevraNativeAI/NativeWorkbookModel.swift)
moves the first decision's replay state there, skips header and scope primes that a known
replay prefix covers, forgets one when a resume falls short and records
`replayBoundaryTokens` on every call.

**CPU checks.** All pass.

- `sevra-agent-checks --conversation-latency-checks` includes the new three-turn fixture
  check. With the old array rendering restored, it fails with "Turn 2 rewrote the saved
  conversation instead of appending to it".
- `python3 scripts/check_splash_grammar.py` runs the new tokenizer check: literal delimiter
  text, a scope change and a conversation with no history.
- `sevra-agent-checks --conversation-surfaces` and the full `sevra-agent-checks` suite, 59
  groups, pass.

**Real model.** One 48 GiB M5 Pro, Splash 1.6.1, 64K context, one cold model per sequence,
synthetic demo workbook, 15 seconds between turns. Command:
`sevra-agent-checks --conversation-followup-trace MODELS_ROOT GUIDANCE_LIBRARY SPLASH_EXECUTABLE NEW_OUTPUT_DIRECTORY PROMPT...`.
[Portable evidence](../../../integration/evidence/2026-11-18-follow-up-cache.json)

First call of each follow-up in the same four-turn conversation:

| Turn | Before: resumed, computed, prefill | After: resumed, computed, prefill |
| --- | --- | --- |
| 2 | 10,976 · 1,613 · 1.81 s | 11,072 · 1,480 · 1.71 s |
| 3 | 10,976 · 6,239 · 3.23 s | 11,776 · 5,071 · 2.90 s |
| 4 | 10,976 · 9,146 · 5.34 s | 15,840 · 3,725 · 2.57 s |

Each follow-up resumed where the previous turn's history ended and computed only that
turn's entries and the new request. The separate 2.0-second scope prime is gone from the
first turn's second call and from the call after a one-call greeting. As planned, the
second decision of a multi-call request computed about 725 more tokens, about 0.28 seconds.

`--conversation-cache-trace` passed all five turns with its new assertion. Same-scope
follow-ups resumed 6,688 tokens against a 6,606-token header and 12,576 against 10,989.
The scope change resumed only the shared header. The final read-only turn, after 125 idle
seconds and a scope change, resumed 7,456 tokens from the read-only state saved two turns
earlier. Answers kept their values and citations in every run. Swap stayed at 1,752.69 MiB.

Limits: single runs on synthetic data. Model decisions vary between runs, so turn totals
are not compared. The app interface and a packaged build were not exercised.


**Repository gate.** After `dbmd index rebuild`, `scripts/check.sh` passed on November 18 with no store validation errors. It skipped its packaged app and packaged native journeys, because no package was rebuilt from these sources.
