---
type: spec
meta-type: conclusion
id: 01m5rbxzb0mz1b78ergkwybtnp
created: 2026-10-25T01:48:47.328971+00:00
updated: 2026-10-26T22:43:08.523475+00:00
summary: Native Splash direction, Swift adapter, bounded tools, proposal acceptance, on-device voice and declarative spaces.
title: Local intelligence and rendering
status: reviewed
---
# Local intelligence

A01. Adopt upstream Splash C++/Metal with the Python-free Swift adapter described
in [[records/specs/splash-integration]]. Pin and qualify upgrades; preserve the
existing Slotstream build as a comparison baseline until adoption passes. First
model remains Qwen3.6-35B-A3B 4-bit with matching DFlash2. No universal 100–150 tok/s
claim. Measure complete workbook jobs, tool success, context latency and memory.
A02. Setup explains download size, disk, memory and hardware before starting.
Native download is resumable/cancellable and digest verified. Reuse explicitly
selected compatible model files; never copy weights into workbooks. Model absence
must not crash normal browsing. Final setup and inference require no Python.
A03. A single serialized inference service owns engine/model lifecycle. Loading and
generation stay off the main actor. Cancellation reaches engine callbacks. Validate
terminal error/truncation before storing an answer as completed. App shutdown
cancels work and flushes completed state. Memory pressure can release idle engine.
A04. Prompt contains stable policy, available tools, selected context, a bounded
recent conversation and retrieved evidence. Historical content never grants new
authority. Context assembly has explicit byte/token bounds and preserves tool-call
relationships. Tool results are data, not instructions. No hidden cloud fallback.
A05. Agent loop has maximum steps, per-tool result budgets and cancellation. Typed
JSON actions: search, read, lineage, list datasets/spaces, query rows, calculate,
propose records/events/edits, create/update space, draft document and finish.
Missing/invalid arguments receive structured errors the model can correct.
A06. Read tools execute immediately within the workbook. Mutations use shared core
commands and idempotency tokens. Reversible view/draft creation can happen within
a user's request. Business interpretations are proposals until explicitly accepted
or covered by a user-approved import rule. Imported instructions cannot authorize
filesystem access, network capture or acceptance. Clarify ambiguous mutations.
A07. Agent output has citations, assumptions and affected records. Deterministic
arithmetic comes from tools, not guessed model prose. Persist proposed/accepted
outputs and exact model/transformation identity. Re-running after model upgrade
creates new proposals, never silently rewrites existing accepted records.
A08. View descriptions are Codable JSON schema v1: bounded component list, allowed
component enum, typed binding, limited presentation properties and action IDs.
Validate data identifiers, maximum component count/depth and chart row budgets.
No executable source or arbitrary URL-loaded components. Unknown components show
an actionable error and preserve the previous valid composition.
A09. Voice uses Apple's on-device speech recognition only. Request microphone and
speech permission at first explicit use. Require on-device capability; unavailable
languages/assets produce a clear fallback to text, never a server request.
Partial recognition stays editable and is sent only by an explicit send action.
Voice stops or pauses media capture/playback appropriately. File transcription is
separate from live dictation and must label supported limits.
A10. A small decision model is a research opportunity, not a hidden v1 dependency.
No unverified model marketed as a Jev replacement. Versioned deterministic scenario
calculations and explicit assumptions provide the initial decision support.

A11. Preserve one continuing conversation with proactive automatic compaction,
exact token budgeting and recoverable context checkpoints. Retain all original
history and reconstruct action/acceptance status from workbook state. Qualify
32K first and 64K where practical rather than treating the current 8K candidate
setting as the product default. Detailed contract and gates C01–C13 are in
[[records/specs/conversation-context]]; implementation remains open.

## Durable execution receipts and history tools

The shared agent journals nonterminal tool calls before dispatch, then atomically
records their exact result and conversation receipt. Oversized responses are valid
bounded JSON views with explicit retrieval paths, not truncated output. The tool_result
reader supplies exact saved pages; history_search/history_read retrieve older messages
within the selected conversation. Current requests are excluded from history search.
Historical output cannot grant action authority or acceptance. Failed/unfinished calls
retain operation evidence and uncertainty. The same prepared call ID is never replayed.
This storage boundary is implemented; automatic recovery and context compaction are not.
