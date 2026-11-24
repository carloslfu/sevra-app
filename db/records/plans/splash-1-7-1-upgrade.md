---
type: operational
id: 01m86y1mtcv239smreage19r29
created: 2026-11-24T14:06:07.692881+00:00
updated: 2026-11-24T14:59:06.949687+00:00
summary: 'Move the pinned engine from Splash 1.6.1 to 1.7.1: wire protocol 15, tree grammar masks, the tool grammar fix and a new prompt header, within the light testing rules.'
title: Splash 1.7.1 upgrade
---
# Splash 1.7.1 upgrade

Status: approved by the owner on November 24, 2026 ([[sources/notes/2026/11/splash-1-7-1-upgrade-approval]]),
with int8 cached states and the header-test run. Implemented, installed and committed on November 24; the
release gate stops at a failure older than this upgrade ("Progress", Step 9).
Revision 2, after three review passes (see "Review passes").

The integration contract is [[records/specs/splash-integration]].

## Summary

Move the pinned engine from Splash 1.6.1 (protocol 13, commit `d8af1054`) to the tagged
1.7.1 (protocol 15, commit `1988a72f26a6031127efc29f861bfb46d36286c4`). The engine files,
model, model folder format, status schema, launch flags and cache file names stay the
same. The host changes in five places: the wire codec, the tool grammar text, grammar
masks over a draft tree, the pins and the checks that hard-code protocol 13. The prepared
header is made again. The launch options are part of the header's identity, so launch
decisions are settled before the header is made.

Splash 1.7.2 is on upstream `main`, untagged (commit `2afc733`, November 23). It keeps
protocol 15 and status schema 8, and its Qwen change is GGUF prefill only. This plan pins
the tagged 1.7.1 on purpose.

## What 1.7.1 changes for this app

The app runs the 35B MLX 4-bit target with its DFlash2 draft, one request at a time,
inside a 12 GiB engine budget, so part of its experts stream from disk (the November 16
admission runs recorded "decreasing resident target weights" at 12 GiB). It launches with
`--verify-rows all`, bf16 activations, int8 KV, fp32 states and the Neural Engine on, and
keeps the prepared header in the persistent cache.

| Change | From | Reaches this app | Note |
| --- | --- | --- | --- |
| Draft verified as a best-first tree | 1.7.0 | Yes | Under `all`: eight rows a cycle, the same count and expert reads as 1.6.1's chain; estimates use a fixed prior ("under --verify-rows all nothing learns") |
| Prompt lookup chain in the tree | 1.7.0 | Yes | During and after reasoning; during it, no deeper than the budget left. Tool calls that copy IDs and values can gain |
| Decode attention in 3 dispatches, not 5 | 1.7.0 | Yes | |
| Draft head reads only English, Chinese and chat rows | 1.7.0 | Yes | 1.2% to 1.7% less GPU time a step |
| Cached states stored as int8 codes | 1.7.0 | Yes, unless `--cached-states exact` | 20 MiB a 35B state instead of 64, in memory and on disk |
| A reply's state kept where its retained tokens reach | 1.7.0 | Sometimes | Only when the next prompt renders the reply back and it is 2,048 tokens past the replay point; `observeResume` tolerates deeper resumes |
| Clean stop leaves nothing the next start cannot take back | 1.7.0 | Yes | The header check requires `left_behind` 0; a stop now takes up to 15 s |
| Streamed experts load once at start | 1.6.2 | Yes | 0.9 s sooner for the 35B at 18 GiB |
| Streamed expert repack at 1.1x to 1.35x a copy, not 4x | 1.7.1 | Yes | Prefill with streamed experts |
| 16-row verify arena in every lane | 1.7.1 | Yes, a cost | At four lanes the expert store, sized from what remains of 12 GiB, shrinks; D3 |
| Lanes option (1 to 8) | 1.7.1 | If it frees memory | D3, measured in Step 7 |
| Faster spawn to ready and weight loads | 1.7.1 | Unmeasured here | Measured on GGUF and the 27B |
| Splash's 1.14x decode on the 35B MLX | 1.7.0 | No | Measured with experts in memory under `auto` on a 64 GB Mac; expect modest gains and measure |
| State at a shared head | 1.7.1 | Only with `head_tokens` | F3 |
| Forced-token chains | 1.7.0 or 1.7.1 | Only if forced tokens are returned | F4 |
| int8 MoE prefill | 1.7.1 | No | Resident experts only, and the app passes bf16 |
| Neural Engine prefill and its calibration | 1.7.1 | No | The split runs dense FFNs only (`AneFfnStartup.cpp:46`) |
| Metal budget leaves 10% unwired | 1.7.1 | No | Automatic budget only; the app passes 12 GiB |
| Tree-mask fix (#790), control-token quoting, JSON whitespace, U+0000 mapping | 1.6.2 to 1.7.1 | Python server only | Ported where they affect parity (Steps 3 and 4); the rest are D6 and F5 |

Unchanged, checked in the source: the executable and both Metal library names; every
launch flag and positional argument the app passes (new options: `--cached-states`,
`--ane-calibration`, `--max-concurrent-requests`); status schema 8 and the `taken_back`
fields; the four cache files and the single 32-hex namespace folder; Ready, Tokens, Done,
Error, Status, StartFailed, Warming, progress, Cancel and Stop frames and every failure
class, issue code and StartFailed kind; the 32-token page; the replay-boundary formula,
so priming and `observeResume` hold; the model pairing (`install/families.py:73-74`) and
`model.json`; both pinned model revisions, still the latest on the Hub (target
`38740b84`, draft `51ef7b69`), so no model download; `server/output.py` and
`server/thinking.py`; LLGuidance 1.8.0, tokenizers 0.22.2 and transformers 5.15.1;
`LICENSE` and `THIRD_PARTY_NOTICES` (byte-identical source copies); the M3 and macOS 26.4
floor. Calibration and step costs live in macOS's per-user cache folder (`splash-ane`),
not in the app's cache directory.

## Decisions before the header is made

- **D1. Verify rows: keep `all`.** In 1.7.1 `all` verifies one eight-row draft block a
  cycle, now as a tree, so it gains the tree at 1.6.1's step size and keeps output
  repeatable for a request alone. It also creates no step-cost table or cost line
  (`Runtime.cpp:775,2702-2703`). Splash has no measurement of `auto` against `all`; its
  streamed-expert figures compare 1.7.0 with 1.6.2. `auto` is F1.
- **D2. Cached states: take the int8 default.** A 35B state is 20 MiB instead of 64, so
  a conversation's states take a third of the room. Every resume, the header's included,
  is close to but not bit-identical with computing it. Splash measured that drift only on
  the 27B (mean KL 1.1e-4, below its 1.5e-4 cold-run noise). The header tests cannot gate
  this: their comparison arm primes the header and resumes from an int8 state too. The
  decision rests on upstream's measurement and the light set. A header test that differs
  only in wording, with equal decisions, is recorded and does not switch to
  `--cached-states exact`. Trying `exact` is a separate header make and header-test run,
  on the owner's word.
- **D3. Lanes: decide in Step 7.** Four default lanes each reserve a 16-row verify arena,
  and the expert store gets what is left of 12 GiB. The app runs one request at a time.
  `--max-concurrent-requests 1` gives the arenas back (roughly 0.1 to 0.25 GiB by reading
  the source) and drops three warm-up steps. Take one lane if its startup shows a larger
  expert store.
- **D4. Head field: send 0.** Ordinary chat already resumes the prepared header.
- **D5. Forced tokens: send none.** An empty list is valid. F4.
- **D6. Literal control tokens: keep the space after `<`.** 1.7.1 keeps such text as
  exact characters and maps U+0000 to U+FFFD; the app does neither. Both are recorded as
  known differences. F5.

## Preconditions

1. The owner authorizes this plan, including the header tests' estimated run (Testing).
2. The in-flight chat work in this checkout is committed by its own session. It edits
   `ToolPolicy.swift`, makes the header 4,215 tokens and plans to regenerate
   `workbook-tools.json` and the grammar reference masks; this upgrade touches the same.
   Start from a clean `main`.
3. The model-free checks pass on 1.6.1 first: `sevra-splash-checks`,
   `scripts/check_splash_text.py`, `scripts/check_splash_grammar.py` (which runs the whole
   default `sevra-agent-checks` suite; the handoff says it currently stops at its last
   group because `workbook-tools.json` is stale) and
   `scripts/check_request_cache_isolation.py`. Otherwise later failures cannot be
   attributed.
4. Every engine run follows this Mac's memory rules: Sevra closed and no `splash` process
   (`pgrep -x splash`), reclaimable memory read with `vm_stat` before each launch, one
   engine at a time, helpers confirmed reaped afterward, and no memory size forced past the
   engine's own planning.

## Steps, in dependency order

### Step 0. File the plan, back up, take the baseline

- Back up for rollback: `ditto` the installed `~/Applications/Sevra.app` and the current
  header folder `.build/prompt-header/<inputs digest>` into `.build/rollback/`.
  `install.sh` deletes the previous app once the new one is in place, and
  `PromptHeader.make` replaces a header folder with the same inputs digest
  (`PromptHeader.swift:463-465`), which holds no engine identity.
- Record the installed executable UUID, the header manifest and the 1.6.1 pin.
- Speed baseline: one five-message timing conversation on 1.6.1, the November 22 command
  and messages (`SEVRA_CHAT_TIMING=1 … sevra-product-checks --first-request …`). The header
  and prompts changed since that run, so its numbers are not comparable.
- Correctness baseline: reuse the in-flight session's light-set result on the final
  header. Do not rerun it.
- Exit: backups in place; baseline identities and timing log saved under
  `integration/evidence/`.

### Step 1. Pin, fetch, reference, protocol-version checks

- `integration/splash.json`:
  - Copy the current 1.6.1 pin to `integration/splash-1.6.1-preserved.json` and point
    `previousNativePreviewPin` at it (today it names the 1.4.1 file).
  - Release `1.7.1`, commit `1988a72f…`, `protocolVersion` 15, runtime URL
    `https://github.com/incoai/splash/releases/download/1.7.1/splash-1.7.1-arm64-macos26.tar.gz`,
    `sha256` `ee520768e0eb408eb9342df998cad16e6391043a953dd274b5a3589542162714` (release
    `SHA256SUMS`), `archiveBytes` 102085714 (release asset size).
  - `statusSchemaVersion` stays 8. `nativePreview.release` becomes 1.7.1.
    `golden.sha256` takes the new golden's digest (Step 2).
  - Surface statuses become `1.7.1-candidate`; add `server/tokenization.py` to the
    templates-tokenizer surface. `qualification` keeps its broader-production `blocked`.
- Run `python3 scripts/fetch_splash.py` unchanged. Its whitelist extracts only the three
  engine files, `LICENSE` and `THIRD_PARTY_NOTICES`, so the Python bytecode new in the
  1.7.1 archive stays out. Copy the receipt's per-file digests into the pin. Confirm the
  archive's `LICENSE` and `THIRD_PARTY_NOTICES` match `integration/licenses/`.
- Reference: reuse `.build/splash-reference`. It already holds the versions 1.7.1's
  `install/requirements.txt` names. `splash_reference_identity.verify` reads the pin, so
  the generators import the 1.7.1 clone's `server/`.
- Protocol-version checks that run in `check.sh` and CI:
  - `scripts/probe_request_cache_isolation.py:22`: append one `I` (`head_tokens`) to
    `REQUEST` and update its comment to the 118-byte body.
  - `scripts/check_request_cache_isolation.py:27-30`: append a `head_tokens` 0 field and
    write `WIRE_VERSION` instead of the literal 13.
- Exit: the fetch receipt matches the pin; the clone's HEAD is the pinned commit.

### Step 2. Wire protocol 15 (`Sources/SevraSplash`)

Layouts confirmed by decoding the 1.7.1 protocol golden and reading `Protocol.hpp/.cpp`:

- Request: `head_tokens` u32 after `alsoEnds` (fixed part 114 to 118 bytes), before the
  arrays. Add `Request.headTokens = 0`; require `headTokens < prompt.count`.
- Start: id u64, lane u32, matched u32, prefix u32, state source u8 (0 none, 1 memory,
  2 disk), lost state u8 (16 to 22 bytes). `Event.start` carries a `SplashWire.Start`.
  Matched is the resumed state's tokens and prefix the KV-matched tokens, the state's
  included (`Types.hpp:185-194`). Validate as the reference does (source at most 2, lost
  at most 1) and both counts at most the prompt length; record, not refuse, prefix below
  matched.
- Mask request: id, mask id, words u32, count u32, `count` tokens, then `count` parents.
  Token 0's parent is `0xFFFFFFFF`; every other parent is an earlier index. Frame bound
  `24…24 + 32 × 8`. Rows are `count + 1`: row 0 before token 0, row i+1 after token i's
  path. Each row has up to four children, in preorder.
- Mask response: id, mask id, words u32, forced words u32, the mask words, then forced
  pairs (row, token) with rows non-decreasing. `SplashWire.mask(…, forced: [])`. The
  engine checks only shape (even count, row in range, rows non-decreasing, token in the
  vocabulary; `Runtime.cpp:4200-4203`), ends the request with `invalid_mask_response`
  otherwise, and never compares forced tokens with the mask. At most 544 forced words.
- Ready: `mask_rows` 9 becomes 17, and a mask request carries at most 16 tokens
  (`Bootstrap.mm:121,137`). Under `all` a lane verifies at most eight rows, anchor
  included (`StepCosts.cpp:204-210`). `maxConcurrentRequests` reports the lane count.
- `NativeProcess.generate`: the mask provider becomes
  `(SplashWire.MaskQuery) throws -> SplashWire.MaskReply` (committed tokens, draft tokens,
  parents, words; mask words, forced pairs). Check rows `<= ready.maskRows`.
- `StreamState`: accept the new start; progress still starts at `matched`.
- Tests in `IntegrationTests/Splash/main.swift`:
  - Replace `protocol_golden.txt` with `dev/tests/engine/protocol_golden.txt` from the
    pinned clone (the GitHub tarball leaves `dev/tests` out).
  - Set `headTokens = 2` in `example()` to match the golden request.
  - Peer start (`:138-141`): also zero prefix, source and lost (payload bytes 16-21), so a
    4-token prompt passes the new count check.
  - `mask-rows` peer (`:145-152`): append 9 tokens and 9 valid parents (72 bytes), so the
    frame fails only on rows, not on tree shape.
  - Mask-response parity (`:263-265`): pass forced pairs `[1, 40, 1, 41, 2, 50]`.
  - Refusals: a parent that is not earlier, a first parent that is not `0xFFFFFFFF`,
    decreasing forced rows, an odd forced count, source 3, lost 2.
- `IntegrationTests/Agent/NativeLifecycleChecks.swift:87-103`: replace the three
  protocol-13 frames with the 1.7.1 golden's `error_retry_after`, `start_failed_memory`
  and `error_engine` (only the version byte changes, `0d` to `0f`).
- Exit: `sevra-splash-checks` passes, golden byte parity and fragmented decoding
  included; the lifecycle group of `sevra-agent-checks` passes.

### Step 3. Tool grammar text (`ToolPolicy.swift`)

- Port 1.6.2's `tool_schema.py` change, its whole 24-line diff: whitespace after
  `</think>` belongs to the thinking rule, and a call starts at its first token. In
  `ToolPolicy.swift:115-122` (lines may shift with the in-flight work) that is two edits: the required and named body
  `"WS \(alternatives) WS"` becomes `"\(alternatives) WS"`, and `think: TEXT <[248069]>`
  becomes `think: TEXT <[248069]> WS`. The automatic body (`TEXT (…)?`) is unchanged. The
  reference's `%json` start and `answer:` rules changed the same way; the app never
  builds them. With reasoning off, a reply can no longer spend its output on whitespace
  before the call.
- This comes before Step 4, because the tool fixtures regenerated there come from the
  1.7.1 grammar and their row-0 masks differ until this lands.
- Exit: covered by Step 4's mask equality.

### Step 4. Grammar masks over a tree (`NativeGrammar.swift`)

- `masks(query)`, as 1.7.1's `server/constraints.py` `masks`, `_reach` and `_walk` do:
  - Consume the committed tokens on the committed matcher, keeping the stopped-EOS no-op
    rule, and fill row 0.
  - Map token i to row i+1 and its parent to row `parent + 1`, or row 0 for
    `0xFFFFFFFF`. Walk depth first on a clone of the committed matcher; at a row with
    several children, every child but the last gets its own clone.
  - Skip, without consuming, a child whose token is outside the vocabulary or a stop
    token (248044, 248046), and a child the grammar refuses
    (`llg_matcher_validate_tokens` returns 0); otherwise consume it and fill its row. This
    differs from today's chain code. The think-end token 248069 is not a stop token.
  - Every row the walk did not reach takes its parent row's mask, in row order. Every row
    must admit a token.
  - Never roll a matcher back: LLGuidance 1.8.0 keys its last mask by lexer state and
    parser row, so a branch reached again after a rollback can get another branch's mask
    (Splash #790, LLGuidance #390).
- Replace `simulation.count < 9` with the wire bound (at most 32 tokens; `NativeProcess`
  enforces Ready's 17 rows). D1 keeps requests within eight tokens; the bound must follow
  Ready for F1. Update spec I14, which fixes eight tokens.
- Forced tokens stay empty (D5). Update every mask call site and `observeMask`
  (Inventory). `observeMask` gains parents; the diagnostics in
  `Performance/main.swift:155-167` and `WorkflowPerformance/ReferenceModel.swift:31-56`
  compute each row's path from them instead of `committed + simulation.prefix(index)`.
- Fixture generators (`generate_splash_grammar_fixtures.py`,
  `generate_splash_tool_fixtures.py`):
  - Build the factory as 1.7.1 does: `ConstraintFactory(ConstraintFactory.table(tokenizer,
    QWEN, vocabulary), ready)` (`constraints.py:256-269`).
  - Call `masks(simulation, parents)`; it returns `(mask bytes, forced pairs)`. Hash the
    bytes as today; store the pairs for F4 but do not compare them now.
  - Add a `parents` field to every step. Keep today's chains (parents none, 0, 1, …) and
    add a branch, a refused branch, a stop-token branch and the #790 shape (two branches
    that reach the same lexer state). Add automatic and named tool cases with reasoning
    on, which today's set lacks (`generate_splash_tool_fixtures.py:134-138`).
  - Read `parents` in `Grammar/main.swift` and `Agent/GrammarChecks.swift`.
- `Grammar/main.swift:98-101` refuses a 9-token simulation; move it to 33 tokens and add a
  malformed-parents refusal.
- Exit: every row of every chain and tree case equals the 1.7.1 reference masks for all
  real tools; `sevra-splash-grammar-checks` and the `sevra-agent-checks` grammar groups
  pass.

### Step 5. Text and output parity (`Sources/SevraSplashText`)

- Regenerate the text and output fixtures with the 1.7.1 reference. Confirm
  `template-patch.json`'s digest: the patched part of `chat_templates.py` is
  byte-identical.
- Limit: `generate_splash_text_fixtures.py:73-75` tokenizes the rendered text directly and
  pre-applies the app's space rewrite to message content only (`:64-68`). It bypasses
  1.7.1's `quote` path, so it proves template parity, not 1.7.1's literal-token handling.
  The Text checks' own hostile-literal cases keep covering the app's protection (D6).
- `output.py` and `thinking.py` are unchanged, so the output parser and reasoning budget
  need no port. `frontend.py` adds `_head_tokens` and reasoning-effort plumbing; the
  generation suffix is unchanged.
- Exit: `sevra-splash-text-checks` passes.

### Step 6. Product identity and diagnostics

- Constants: `PromptHeader.release` and `.commit`, the manifest check in
  `NativeProductResources.swift:27-28`, the identity string and `runtimeRelease` metric in
  `NativeWorkbookModel.swift`, `ProductAI.revision` (`splash-1.7.1`), the comments that
  name 1.6.1 (`Wire.swift:18`, `OutputParser.swift:37`, `ModelPreparation.swift:85`,
  `NativeWorkbookModel.swift:448`, `HeaderCacheProbe.swift:156`) and the fixture commit
  fields.
- Metrics: add `prefixTokens`, `stateSource` and `lostState` beside
  `matchedPromptTokens` and to the timing log. A missed header resume keeps its rule
  (`matched >= headerPage`) and logs the source and lost flag.
- Launch flags stay as they are unless D3 adds `--max-concurrent-requests 1`. Then add it
  to `PromptHeader.engineOptions` and to `HeaderCacheProbe.swift`'s two hand-copied lists,
  which check product header behavior. The development probes (`Splash/NativeProbe.swift`,
  `Performance/main.swift`, `Agent/ReasoningBoundaryProbe.swift`,
  `Grammar/NativeProbe.swift`) keep their own lists; they cannot import `PromptHeader`,
  which is package-internal to SevraNativeAI.
- Exit: `sevra-product-checks` lifecycle checks pass without a model.

### Step 7. Engine starts, lanes and the header

The first real engine runs. Each start follows Precondition 4.

- Admission, startup only, no request. Let `sevra-splash-checks --admit-engine` take
  optional trailing engine arguments (it accepts exactly four today,
  `NativeProbe.swift:28`). Run three starts directly, not `probe_context_admission.py`,
  whose fixed six cells include 128K and 24 GiB budgets this upgrade does not need:
  64K at 12 GiB, 32K at 12 GiB, and 64K at 12 GiB with `--max-concurrent-requests 1`.
  For each, require Ready's context to equal the request and no StartFailed; record the
  status `memory_plan`, the expert store from the startup line "Routed experts stream
  from their files…" (`RuntimeResources.mm:412`), helper footprint, swap and time to
  Ready.
- Decide D3: one lane if its store is larger. If 64K is refused at four lanes but admitted
  at one, take one lane.
- No first-start calibration is expected: the Neural Engine split skips MoE targets, and
  `all` creates no step-cost table. Warm-ups become prefill row classes plus lanes plus 2,
  so the app's "n of m steps" shows a different total.
- Header: `sevra header make .build/prompt-header`, the folder `prompt_header.py` and
  packaging use, so `install.sh` reuses it. The 1.7.1 namespace
  (`persistentCacheNamespace`, `RuntimeResources.mm:534`) is a digest of the cache format
  version (2), the weight layout and the KV, GDN and draft state layouts. It holds no
  path, build id, context, memory, lanes, verify rows or activations, so the header stays
  portable across Macs and both context tiers, given a byte-identical `model.json`
  (phase H2). Only its GDN line changed, so the 1.6.1 header cannot be reused. The header
  request (max output 1) still leaves exactly one state, at its replay boundary.
  Splash keeps an older version's cache folder for 14 days beside the new one, but the
  app's cache never holds one: `PromptHeader.restore` empties the cache folder before it
  copies the header in.
- A clean stop now takes up to 15 s: 6 s writing waiting restore points, up to 2 s
  freeing KV copies no state needs, then syncs (`Supervision.hpp:51-62,74`).
  `PromptHeader.stopCleanly` waits up to 120 s. The app's other stops delete the cache
  directory, so their 1 s grace is unaffected.
- `sevra-agent-checks --header-tests` once.
- Abort, keep 1.6.1 and report if: a context tier is refused at 12 GiB at both lane
  settings; the header is not taken back whole after the one retry the app makes; or a
  header test fails for a reason other than wording (D2).
- Exit: both tiers start, the lane decision is recorded, the header is made, and the
  header tests pass.

### Step 8. Model runs

- The light set once: `python3 scripts/check_chat_jobs.py --output DIR` (11 jobs,
  3 min 51 s on 1.6.1).
- The five-message timing conversation once, compared with Step 0: decode tokens a
  second, accepted tokens a cycle, time before the first token, host mask time.
- Exit: the light set passes. A drop of more than 10% in decode speed or complete turn
  time stops the upgrade for the owner's decision. One run each, so smaller differences
  are noise.

### Step 9. Records, release check, install, commit

- Records: `splash-integration` revision 11 (I02 pin, I14 tree masks and bound, the
  header's launch options, a dated 1.7.1 section with D1 to D6); `integration/splash.json`;
  `overview/start-here.md` (lines 7 and 26 name 1.6.1); the progress register
  `operations/implementation.md`; `inference-context-execution`; `build-and-run`;
  `agent-handoff`; the log. Note there that the performance and differential harnesses
  cannot run until ported (Not in scope).
- `dbmd index rebuild`, then `bash scripts/check.sh` once on the candidate (its first step
  validates the records).
- `bash scripts/install.sh`, `check_native_package.py`, `check_install.py`; the installed
  executable UUID equals `output/native`'s; one chat turn in the installed app resumes the
  header.
- Commit on `main` with a message that never says Claude. Push only on the owner's word.
- Exit: the commit exists, `check.sh` passed and the installed app runs 1.7.1.

## Rollback

Revert the upgrade commit, run `python3 scripts/fetch_splash.py` (the 1.6.1 archive is
still in `.build/upstream`), restore `.build/rollback/<inputs digest>` into
`.build/prompt-header/`, and run `bash scripts/install.sh`, or restore the backed-up app
with `ditto`. Model files and workbooks are untouched by the upgrade.

## Inventory

- Mask call sites: `NativeWorkbookModel.swift` (summary 853, titles 916, chat 1031),
  `Grammar/main.swift:64,93,100`, `Grammar/NativeProbe.swift:87`,
  `Agent/GrammarChecks.swift:89`, `Agent/ReasoningBoundaryProbe.swift:79`,
  `Agent/ReasoningChecks.swift:44`, `Performance/main.swift:155`, the `Splash/main.swift`
  mask test (~524-550). `observeMask`: `NativeWorkbookModel.swift:30,52,1033`,
  `WorkflowPerformance/Runner.swift:373`, `WorkflowPerformance/ReferenceModel.swift:31-56`.
- Start call sites: `Wire.swift:291`, `StreamState.swift:20`, `NativeProcess.swift:158`,
  `NativeWorkbookModel.swift:435,856,1085`, `PromptHeader.swift:403`, the
  `Splash/main.swift` start and stream tests (~138-158, ~349-373),
  `HeaderCacheProbe.swift:303,501`, `Performance/main.swift:173`.
- Hard-coded protocol 13: `NativeLifecycleChecks.swift:87-103`,
  `check_request_cache_isolation.py:30`, `probe_request_cache_isolation.py:22`.
- No edit needed: `package_native.py`, `check_install.py`, `check_release_package.py`
  and CI read the pin; `fetch_splash.py` and `check_splash_grammar.py` need no change.

## Testing, within the light rule

`AGENTS.md` "Keep testing light" binds this plan. The spec's W1 cohorts, the update-splash
skill's real-model differential suite and the 5% and 10% adoption gates are heavier than
that rule allows and do not run; the spec's broader production `qualification` stays
`blocked`, as on 1.6.1.

- **No model, every change:** `sevra-splash-checks`, `sevra-splash-grammar-checks`,
  `sevra-splash-text-checks` (through `check_splash_grammar.py` and
  `check_splash_text.py`), the `sevra-agent-checks` groups for grammar, lifecycle, the
  prompt header and conversation latency, `check_request_cache_isolation.py`,
  `sevra-product-checks` lifecycle checks and `dbmd validate`. Fixture generation runs the
  Python reference with no model weights.
- **Engine, no generation:** three admission starts and the header's two starts.
- **Model, once each:** the 1.6.1 timing baseline (about 70 s); the header tests, about
  ten engine starts and a few chat turns, estimated at 3 to 5 minutes from the November 22
  timings (engine start about 5 s, turns 5 to 15 s), approved with this plan; the light set
  (3 min 51 s measured); the 1.7.1 timing conversation (about 70 s).
- **Release gate, once:** `bash scripts/check.sh` on the candidate.
- Nothing is rerun to see whether it passes. A failure's transcript is read, then fixed or
  recorded. Anything beyond this list asks the owner first.

## Risks and how each is caught

| Risk | Caught by |
| --- | --- |
| A tree mask is wrong, so a valid draft is refused or an invalid token admitted | Row-by-row fixture equality with the 1.7.1 reference, including branch, refused, stop and #790 cases; `constraint.finish` validates the whole output; the light set |
| A stale mask after a rollback (#790) | The walk never rolls back; the #790-shaped fixture |
| The expert store shrinks at 12 GiB (16-row arenas at four lanes, the lookup index at 89 bytes a token) and decoding slows | Step 7 records the store at four lanes and one; D3; Step 8 timing. The spill cache and Neural Engine reservations do not apply here |
| int8 cached states change answers after a resume | Upstream's measurement and the light set; the header tests cannot see it (D2) |
| Decode gets slower | Step 8 against the Step 0 baseline |
| The header is not portable | Namespace inputs read in the source; the existing header test that prepares the model in another folder |
| A check that hard-codes protocol 13 breaks `check.sh` or CI | Inventory, Steps 1 and 2, and Precondition 3's baseline |
| The performance and differential harnesses load 1.7.1 code through the pin and fail (`splash_reference_identity.py:9-13`, `splash_performance_reference.py:172`) | Recorded as unrunnable until ported; `check.sh` only imports their pure helpers |
| The concurrent session's work collides | Precondition 2 |

## Follow-ups, after the upgrade lands

Each is its own change with one measurement.

- **F1. `--verify-rows auto`.** Splash's default. With streamed experts it verifies only
  rows whose chance of a token is worth their expert reads, one to sixteen a lane, and
  learns its estimates. Costs run-to-run repeatability. Measure with the timing
  conversation and the light set.
- **F2. Keep options that do not change restore points out of the header's identity.**
  The engine's namespace ignores verify rows and lanes, but `PromptHeader.Manifest.mismatch`
  compares the whole option list, so F1 or a lane change forces `sevra header make` for no
  engine reason. Activations stay in the identity: the namespace ignores them, but they
  change the numbers the header state was computed with.
- **F3. `head_tokens` for prompts without a prepared header** (Excel conversion, reviews,
  scope blocks), replacing one-token prime requests in `primePrefix`. The engine keeps a
  head state only at least 2,048 tokens past where the request resumed and not past the
  replay boundary (`Engine.cpp:1271-1291`), which matches `primePrefix`'s floor.
- **F4. Forced tokens.** Bind `llg_matcher_compute_ff_tokens` (in the LLGuidance 1.8.0 C
  header) and return them as `_reach` does: every reached row from 1, row 0 only for a
  first-token request, at most 16 a row. The engine uses a row's run only when its first
  token is the one the target selected, proposes the rest next cycle and grows no tree
  that cycle. Qwen tool calls are mostly grammar-forced framing; Splash measured +16%
  accepted tokens on schema-heavy output. Step 4's fixtures already store the reference
  pairs.
- **F5. Literal control tokens as exact characters and U+0000 as U+FFFD,** as 1.7.1's
  tokenizer does, instead of a space after `<`.

## Not in scope

The model, context tiers and 12 GiB budget; Splash 1.7.2; publishing a release; porting
the performance and differential harnesses (`compare_*_performance.py`,
`splash_performance_reference.py`, `check_splash_reference.py`); F1 to F5.

## Review passes

1. **Draft and source reading.** The plan was drafted against the app's integration code,
   then checked against two independent readings of the 1.6.1 and 1.7.1 sources: one of
   the protocol, grammar and reference frontend, one of engine runtime behavior. They
   settled the wire layouts, the tree-mask rule, verify rows, the namespace, memory, the
   Neural Engine, step costs and the clean stop, and moved the lane choice into the
   upgrade (D3).
2. **Independent adversarial review** of revision 1 against the code and both sources:
   3 blockers (two checks hard-code protocol 13 and would break `check.sh` and CI; the
   tool-fixture exit could not pass before the grammar text change), 14 should-fix items
   (fixture-generator API, D2's gate, the admission probe's six cells, test-peer offsets,
   the 9-token refusal, chain-only diagnostics, harness reachability, a passing baseline,
   Step 9's order and missing records and pin fields, rollback, the header-test estimate,
   Step 4's exit, the text-fixture limit) and 8 minor ones. All were verified against the
   code and applied in revision 2.
3. **Consistency pass** over revision 2: step order follows dependencies, every exit is
   checkable, and every test fits the light rule. The Splash source references (clean
   stop, forced-pair check, mask rows, block step, head state, namespace, Neural Engine
   gate, factory table, start fields, model pairing) and the app references were
   re-read at their lines; four line numbers were corrected, and the restore's emptying
   of the cache folder was added to Step 7.

## Sources

Splash `v1.6.1` and `v1.7.1` source trees (`runtime/`, `server/`, `docs/`), release notes
1.6.2, 1.7.0 and 1.7.1, the protocol golden at both tags, the 1.7.1 release `SHA256SUMS`
and asset list, and the Hugging Face model API for the pinned revisions.

## Progress

All steps ran on November 24 on the 48 GiB M5 Pro, one run each. Evidence: `integration/evidence/2026-11-24-splash-1-7-1/`.

- **Preconditions.** Another session's chat work was still uncommitted in the checkout; the owner said that session had finished, so the upgrade ran on top of it without changing it. On 1.6.1 the model-free checks passed first: 39 Splash checks, the text checks, the request-cache checks and the grammar and agent suite (81 groups).
- **Step 0.** The installed app (UUID `93E75F7C-B777-3C74-ABF1-8A454C8C60C5`), header `84872aa4…` (4,429 tokens) and the 1.6.1 pin are backed up in `.build/rollback/`. Timing baseline on 1.6.1: 50.7 tokens a second, 3.91 tokens and 77.1 ms a cycle, grammar masks 2.04 ms each, on a fresh synthetic demo workbook (`chat-timing-1.6.1.jsonl`).
- **Step 1.** Pin 1.7.1 with archive and file digests from the fetch receipt; `integration/splash-1.6.1-preserved.json`; `LICENSE` and `THIRD_PARTY_NOTICES` byte-identical to 1.6.1. Both request-cache scripts read protocol 15 and its 118-byte request. The repository's `integration/licenses/Splash-third-party.txt` was already older than the archive's notices under 1.6.1 and is not shipped (packaging copies the archive's); left as it is.
- **Step 2.** Protocol 15 codec, start fields, tree mask requests, forced pairs and one-lane Ready; 39 Splash checks pass, including byte parity with every 1.7.1 golden, fragmented decoding and the new refusals. The lifecycle check's three frames are the 1.7.1 goldens.
- **Steps 3 and 4.** The tool grammar fix and the tree walk. Fixture generators use 1.7.1's factory table and tree masks; fixtures add parents, a tree at every step (a valid, a refused and a stop branch) and Splash's #790 case, and store forced pairs for F4. 214 grammar and 1,441 workbook tool masks equal the reference; with siblings sharing one matcher the checks fail at the first tree. New tool cases: automatic and named finish with reasoning on.
- **Step 5.** Text, output and template-patch fixtures are byte-identical under 1.7.1 apart from the commit label; 24 prompt and 31 text checks pass.
- **Step 6.** Identity strings, `ProductAI.revision` and the new start metrics (`prefixTokens`, `stateSource`, `lostState`, and a `model.header_missed` timing mark). Product lifecycle checks pass.
- **Step 7.** Admission at 12 GiB, startup only: 64K and 32K admit at four lanes; 64K at one lane has an expert store of 7,901 MiB against 7,705 and shared decode memory of 66 MiB against 261. D3: one lane, added to `PromptHeader.engineOptions` and the header probe. No calibration or step costs ran; the Neural Engine is off for this model. `build_native.sh` remade the header (state file 20.5 MB against 66.7; namespace `d792618e…`) and checked it is taken back. Header tests: the first run stopped at the forced-kill step, where the app's model-load guard read 12.6 GB right after the kill, and its `sameAnswers` result had failed without a kept detail. The harness now waits up to 30 s for memory after a stop and prints a failed test's detail at once; the complete run passed all eight (`header-tests.json`, first run in `header-tests-first-run.txt`).
- **Step 8.** Light set 11 of 11 on the first run, 112 s of wall time. Timing conversation: 92.9 tokens a second, 4.23 tokens and 45.6 ms a cycle, masks 0.92 ms, first tokens 0.85 s on average against 1.63; 17 model calls against 8, as model decisions vary. Cycle times were steady through both runs, but page-cache state between them was not controlled. The first turn waited 6.4 s because the header tests' hard links changed the model files' times and the app verified them again once; the engine itself started in 2.07 s against 4.94.
- **Step 9.** Records: [[records/specs/splash-integration]] revision 11, start-here, the execution, build and progress records and the handoff. Release gate, after `dbmd index rebuild`: `check.sh` stopped three times on failures that predate this upgrade. (1) `dbmd validate --all` refused log kinds `fix` (committed November 22) and `install` (the other session's uncommitted entry); both are now declared under `### Validation log kinds` in `DB.md`, as the log is append-only. (2) The extraction descriptor check expected a new workbook at revision 0, but since `1833318` (November 21) a new workbook holds its first chat; the check now compares with the workbook's own revision. (3) The native app authoring check "native app authoring through a scoped conversation continuation" scripts `start_thread_and_continue`, a thread tool removed by the same commit, and is refused; not fixed, as what replaces a removed feature's test is the owner's call. 992 checks passed before it, the Splash, text, grammar, request-cache and agent checks among them; the 40 scripts after it did not run. Install: `install.sh`, `check_native_package.py` and `check_install.py` pass; the installed executable UUID `499AD265-C0EB-34E2-8F5D-C559C8FD1A7C` equals `output/native`'s. One question through the installed app's own CLI on a fresh demo workbook answered "We have 18 brass bolts" with citations in 9 s; its first call resumed the bundled header from disk (4,416 tokens, no prime, no restart), its second from memory. Commit, at the owner's word: the other session's finished chat work first, as its own commit with its own tool fixture and record indexes rebuilt without this upgrade's records, then this upgrade on top. The final tree is the one tested above.
