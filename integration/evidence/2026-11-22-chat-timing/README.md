# Chat timing, one five-message conversation, November 22, 2026

One run with the real model and debug chat timing on, for [Chat response time](../../../db/records/plans/chat-response-time.md).

- `chat-timing.jsonl`: the log as written, one engine-start record (`prewarm`) and five turns. No message text, arguments or answers.
- `comparison.txt`: `python3 scripts/chat_timing.py chat-timing.jsonl --compare`. Run the script without `--compare` for every turn's nested steps.

The run, from the repository root:

```sh
swift build --scratch-path .build/chat-timing-release -c release -Xswiftc -enable-testing --product sevra-product-checks
SEVRA_CHAT_TIMING=1 SEVRA_CHAT_TIMING_LOG=chat-timing.jsonl SEVRA_TRACE_PAUSE=4 \
  SEVRA_PROMPT_HEADER=.build/prompt-header \
  .build/chat-timing-release/release/sevra-product-checks --first-request \
  MODELS_ROOT output/native/bin WORKBOOK_COPY \
  "hi" "what can you do for me?" "tell me more about the first one" "what's in this workbook?" "thanks"
```

- Code: `c474937` with the debug timing changes, before they were committed. The harness executable's UUID was `A87911E0-3F1B-3E69-A94D-FA7A65425CDB`. The packaged runtime came from `bash scripts/build_native.sh` on the same code, packaged app UUID `B04DF7CA-2E87-3FD9-8F59-F303BFC61E2F`, with the 3,809-token prepared header.
- Machine: Apple M5 Pro, 48 GB, macOS 26.6.2. Splash 1.6.1, Qwen3.6 35B A3B 4-bit with DFlash 2, 64K context, 12 GiB engine budget.
- Workbook: a copy of a chat-only workbook with earlier chats and no business tables or documents. A new chat.
- One process, so the engine and its cache stayed warm between turns. Engine resident memory near 2 GB, weights mapped from disk, no swap.
- The app's interface was not used, so the log has no `ui.*` steps.

| Message | Reply done (s) | Model calls |
| --- | ---: | ---: |
| hi | 5.11 | 1 |
| what can you do for me? | 7.11 | 1 |
| tell me more about the first one | 33.52 | 6 |
| what's in this workbook? | 15.93 | 4 |
| thanks | 5.10 | 1 |
