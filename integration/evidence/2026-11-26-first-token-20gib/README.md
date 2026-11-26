# Time before the first token at the app's memory size, November 26, 2026

One run with the real model and debug chat timing on, for [Chat response time](../../../db/records/plans/chat-response-time.md): is the "about 1 second before each call's first token" of the 12 GiB runs still there when the engine gets the size the app chooses?

- `chat-timing.jsonl`: the log as written, one engine start and two turns. No message text, arguments or answers.
- `comparison.txt`: `python3 scripts/chat_timing.py chat-timing.jsonl --compare`.

The run, from the repository root, with a new demo workbook (`sevra demo`):

```sh
swift build --scratch-path .build/chat-timing-release -c release -Xswiftc -enable-testing --product sevra-product-checks
SEVRA_TRACE_MEMORY=app SEVRA_CHAT_TIMING=1 SEVRA_CHAT_TIMING_LOG=chat-timing.jsonl SEVRA_TRACE_PAUSE=4 \
  SEVRA_PROMPT_HEADER=.build/prompt-header \
  .build/chat-timing-release/release/sevra-product-checks --first-request \
  MODELS_ROOT output/native/bin DEMO_WORKBOOK "hi" "how many brass bolts do we have?"
```

- Code: `545ccc5` plus the harness change that adds `SEVRA_TRACE_MEMORY=app`. Harness UUID `52C480BF-54D2-37A3-B9A6-7BB3955CF147`. Engine from `output/native/bin`: Splash 1.7.3, commit `d40c250`.
- Machine: Apple M5 Pro, 48 GB. Reclaimable memory before the run about 24.9 GiB, so the app's rule gave the engine 20 GiB (`requestedMemoryBytes` 21,474,836,480). Qwen3.6 35B A3B 4-bit with DFlash 2, 64K context, prepared header of 4,992 tokens resumed.

| Call | Computed tokens | Before first token (s) | State from | Generated | Decode (s) |
| --- | ---: | ---: | --- | ---: | ---: |
| "hi" | 791 | 1.00 | disk | 87 | 0.50 |
| bolts 1 | 984 | 0.40 | memory | 106 | 0.62 |
| bolts 2 | 1,011 | 0.39 | memory | 73 | 0.40 |
| bolts 3 | 146 | 0.16 | memory | 215 | 1.05 |
| bolts 4 | 117 | 0.13 | memory | 218 | 1.11 |

- **Resumed from memory, the time before the first token fits 0.10 s + 0.29 ms per computed token.** At 12 GiB on 1.7.1, calls of about 1,000 tokens took 0.80 to 1.07 s and calls of 110 to 150 tokens 0.42 to 0.73 s. The near-fixed second of those runs is gone at 20 GiB.
- **The first call after an engine start takes back the header's state from disk** and paid about 1.0 s for 791 tokens, about 0.6 s more than the same work from memory.
- **Decoding: 190 tokens a second** over the five calls, against 92.9 on the 1.7.1 timing conversation at 12 GiB.
- **"hi"** took 2.53 s from Send, of which 1.02 s waited for the engine start (its launch took 3.66 s) and 1.50 s was the engine. **The bolts question** took 4.44 s in four calls: 1.06 s before first tokens, 3.18 s decoding, about 0.2 s in the host.

Limits: one run, one machine, one workbook. The engine's own breakdown of each first token is on its stderr and was not kept. The bolts answer said the search found no brass bolts; its correctness was not part of this run.
