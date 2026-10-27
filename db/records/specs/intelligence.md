---
type: spec
meta-type: conclusion
id: 01m5rbxzb0mz1b78ergkwybtnp
created: 2026-10-25T01:48:47.328971+00:00
updated: 2026-10-27T07:01:03.960895+00:00
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
cancels work and flushes completed state. The shared product service observes memory
pressure for both app and CLI. Warning pressure defers release until active work
finishes. Critical pressure cancels the active operation, preserves committed
workbook changes and reports the cause, then releases the model after the run
has ended. Idle pressure releases immediately. New work remains excluded while
release is in progress, and a failed release must succeed before a new operation
can reuse the model. Ordinary user unload remains idle-only. Pressure does not
automatically retry a cancelled request. Tests may inject policy events without
forcing actual system memory exhaustion; label that scope explicitly.
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
An explicit read-only request must also prevent reversible drafts, proposals and
spaces. The current host recognizes a narrow set of complete English/Spanish
no-change sentences in the current submission and enforces a read-only tool
allowlist before execution. This additional denial rule is not a general intent
classifier, comprehensive language support, or permission when no phrase matches.
Conversation, request provenance and operational receipts still save normally.
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
[[records/specs/conversation-context]]; a controller is implemented and broader
qualification remains open.

## Durable execution receipts and history tools

The shared agent journals nonterminal tool calls before dispatch, then atomically
records their exact result and conversation receipt. Oversized responses are valid
bounded JSON views with explicit retrieval paths, not truncated output. The tool_result
reader supplies exact saved pages; history_search/history_read retrieve older messages
within the selected conversation. Current requests are excluded from history search.
Historical output cannot grant action authority or acceptance. Failed/unfinished calls
retain operation evidence and uncertainty. The same prepared call ID is never replayed.
This storage boundary is active. Automatic context maintenance is implemented for
the native candidate; the preserved Slotstream build keeps it disabled after its
opt-in recall probe failed. General action recovery after process death remains open.
A read returns the requested exact version plus current-version metadata and a
snapshot revision. Current-version metadata is a navigation pointer, not newly
inspected evidence: read that version before citing its facts.


## Conversation citations

history_read exposes a message:ID citation only for an original message earlier
than the active request. A freshly read original body must actually be visible
before that reference joins the allowed finish citations. Search snippets, omitted
bodies, a derived digest and the current request do not grant it. The app renders
an Earlier message link to its existing conversation navigation. Business item
version IDs retain their existing meaning and lineage rules. Conversation citations
support what someone said, not current inventory, acceptance or permission.

## Bounded reasoning comparison
The native adapter has an internal comparison profile for bounded reasoning.
Thinking mode must agree across the exact chat template, constrained tool grammar,
stream parser and engine request. The first candidate allows 512 thinking tokens per model response
within the existing 1,800-token response limit, with at least 256 tokens reserved
for a complete response after the thinking close. If context cannot hold that
reserve, refuse the request instead of silently truncating or dispatching a partial
call. Under upstream grammar masks, closing can wait for a complete UTF-8 character;
record actual thinking tokens and any overrun. The total output limit still applies. A workbook job can make several model
responses; the existing twelve-step bound limits the overall tool loop. The
512-token limit is not a whole-job thinking allowance.

Reasoning text is separated from answer/tool content and is not persisted as new
user evidence or shown as a completed answer. Tool-free history summaries remain
on their existing configuration during the comparison. This adds no user backend
picker, settings burden, provider fallback or production default. Off remains the
control until measured completion, correctness and latency justify a change.

Record comparison outcomes in [[records/operations/implementation]], including
failed runs and the exact scope of any adopted candidate setting. Preserve the
same model and workbook authority boundaries in either mode.

## Reasoning continuity within a request
Retain parsed reasoning in ephemeral assistant messages between tools within the same request. The exact pinned template places reasoning_content in its thinking block after the latest user query. Count it in preparation and rendered-token budgets. Do not save it in original messages, tool receipts, summaries, Sources or Records. New requests reconstruct evidence from durable history with no old private reasoning. Context maintenance may discard older reasoning while retaining the latest complete tool group, with the same measured budget and citation reset rules. This is model execution state, never authority or independently citeable evidence. Reasoning remains disabled in the non-thinking control and the preserved Slotstream backend; shared host validation applies to both adapters.

## Calculated answer provenance
The host retains the inspected input version IDs used by balance and compare_rows. A final answer must cite all of them, including both opening stock and inventory effects. Reject an incomplete set with a bounded correction opportunity before recording success. Clear obligations when compaction invalidates the corresponding inspected calculations; retain the latest calculation inputs with its visible tool group. Do not add uninspected or historical IDs merely because a summary mentions them.

## Answer grounding

The internal finish tool declares one answer basis. This is a protocol field, not
another user setting:

- evidence: claims about stored business data or earlier conversation. Require
  freshly inspected Source/Record versions or original-message citations, even
  when a digest or host-state pointer already suggests the answer.
- current_request: information supplied in the current request, or checked
  arithmetic using that information. Asking a question does not supply its answer.
- completed_action: confirmation of an actually successful action in this run.
  A failed or partially completed action cannot establish success.
- general: guidance, greeting, clarification or verified interface labels, without
  assertions about stored business facts or earlier conversation.
- unresolved: an explicit inability to establish the requested facts, without
  substituting a guessed answer.

The host rejects missing/unknown bases, evidence without eligible citations and
completed-action claims without successful action receipts. Existing checks for
calculated provenance, unsupported currency, arithmetic and opaque IDs still apply.
Pure action confirmations and unresolved gaps do not require unrelated calculation
citations. Validation feedback is bounded; exhaustion remains a truthful failure.

A declared basis is not an independent truth verifier. The model can misclassify
an answer or misinterpret evidence, so semantic evaluation remains required. The
field does not authorize actions or change acceptance, lineage or business state.
All actual tool schemas and pinned reference grammar masks include this contract.
The implementation register retains the earlier retrieval-only guard and its
failure to catch an uncited answer generated directly from saved context.

## Date semantics
An event's effective date, a Source's creation time and an acceptance decision's time are separate facts. Do not infer one from another. If inspected evidence does not establish a timestamp, omit that claim. The agent policy states this explicitly after a real-model inventory answer mislabeled the starting date. This policy is not a deterministic semantic verifier; preserve and review complete answers in evaluations.

## Evidence inspection recovery
When an evidence-based finish has no citations and the current run has no eligible inspected evidence, the next model response must use a read-only inspection tool. Temporarily remove finish and mutation tools from the available set. Native generation constrains the same set in its grammar; the shared host checks the selected scope again before dispatch, including for the preserved backend. After one valid inspection call, restore the ordinary tool set and validate the next answer normally.

This recovery step prevents repeated identical invalid finishes after reopening. It does not import citation eligibility from an earlier run, infer source facts from a digest, automatically accept a proposal or replay a completed mutation. Unknown/failed inspection results still need truthful handling. Existing format, final-validation and twelve-step limits remain; cancellation continues to release the run. Scope is ephemeral host execution state and appears in request metrics, never an instruction accepted from retrieved text. Exact prompt budgeting may conservatively count the full tool set before a narrower recovery response.

## Current-request numeric grounding
For basis=current_request, each numeric value in the answer must occur in the current prompt or in a successfully completed, fully visible calculate call's inputs/result. Normalize ordinary decimal spelling without binary-float rounding; distinguish signs and skip numbered-list labels. Values mentioned only in a digest or older history do not qualify. Unsupported numbers receive bounded validation feedback; when there is no fresh evidence, require a read-only verification step before another finish.

Spelled-out arithmetic remains possible: the model can use calculate to establish the operation and result. Retain its checked numbers only while the matching operation is visible; compaction clears omitted calculation evidence. This guard does not verify the meaning of prose, units, a calculation's relevance, or classification into other answer bases. It complements original citations and semantic evaluation rather than establishing general factual correctness.

## Search claim boundaries
Search matches and complete structured counts have different authority. The host rejects recognized unsupported absence/exhaustiveness wording and renders exact current-record counts only from visible current-run count_records receipts, revalidated before finish. See [[records/specs/search]] for scope, cancellation, history and language limits. This rule applies to the preserved baseline and native candidate. A valid citation alone does not prove a global absence claim.

When an uncited unresolved response follows empty searches, the host renders their actual query receipts and the most recent search's incomplete-source count. The same search report accompanies a count-only response after empty searches, so an unrelated total cannot hide the retrieval limitation. Original model arguments stay in the diagnostic payload, separate from the displayed answer. Query text is escaped and treated as quoted search input, not a factual claim or executable link. A report of no incomplete sources describes the search's indexing status, not proof that the requested document does not exist.

Before comparing, displaying or proposing tabular data, inspect existing datasets even when the user has not supplied a table name. Reuse existing rows for analysis and space components. A request to show a table does not itself call for a duplicate data-entry proposal. Calculations still use deterministic tools.

## Request admission and restart
Acquire the exclusive inference lease before recovering abandoned runs. Persist the original user message, its run and their exact linkage in one workbook transaction. If admission fails, roll back the complete write and release any lease actually acquired. Do not call endRun for a lease that was refused.

A model-lease refusal or cancellation before acquisition saves the original request, a linked terminal run and its assistant diagnostic atomically, without interrupting another run. Keep the original failure visible. A storage failure is an error, not evidence that the request was saved.

With exclusive ownership, the admission transaction also marks earlier running jobs interrupted. Assemble historical context only after that transaction commits. Exclude the current request and later messages from earlier history using a conversation-validated message boundary. Stopped requests remain status/reference entries; the new request is the only live user turn. Preserve unfinished tool receipts and committed operation proof. Recovery must not automatically repeat an uncertain action.
