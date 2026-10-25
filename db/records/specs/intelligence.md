---
type: spec
meta-type: conclusion
id: 01m5rbxzb0mz1b78ergkwybtnp
created: 2026-10-25T01:48:47.328971+00:00
updated: 2026-10-25T01:48:47.328971+00:00
summary: Pinned native Slotstream integration, bounded tools, proposal acceptance, on-device voice and declarative native spaces.
title: Local intelligence and rendering
status: reviewed
---
# Local intelligence

A01. Use the latest reviewed public Slotstream revision at implementation start,
currently `7578fb21e57ec362d19f5050922e0f583914935d` (after v0.2.30). Pin it and
transitive Package.resolved. Revisit upgrades deliberately; do not depend on a
moving branch. Native Swift API, Swift/MLX/Metal and the engine's Fast pack
(Qwen3.6-35B-A3B 4-bit with DFlash2) are the first configuration to qualify.
No universal 100–150 tok/s claim. Measure time to first useful result, tool success,
context latency, memory and throughput on this app's tasks and reference hardware.
A02. Setup explains model download size, disk and memory before starting. Download
is resumable/cancellable and digest verified using Slotstream's pinned deployment.
Reuse an explicitly selected existing compatible model directory without copying
its weights into workbooks. Model discovery/absence must not crash normal browsing.
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
