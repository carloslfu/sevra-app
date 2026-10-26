---
type: spec
meta-type: conclusion
id: 01m5x2pp178p3a4ay7hbfx7wdg
created: 2026-10-26T21:43:43.399273+00:00
updated: 2026-10-26T22:27:33.065083+00:00
summary: Automatic compaction, preserved conversation history, authoritative continuation state and measured larger-context qualification.
title: Continuing conversation and context management
status: reviewed
---
# Continuing conversation and context management

Revision 1, October 26, 2026. Reviewed design; implementation and hardware
qualification remain open. The owner requested continuity through automatic
compaction and larger-context qualification in a related design conversation.
That requirement was relayed into this implementation session. The 32K and 64K
sizes below are evaluation proposals, not established capabilities or a fixed
owner-selected product default.

## Product contract

C01. A workbook has one continuing main conversation with chapters and scoped
tangents. Users do not need to count tokens, select a context window, periodically
start new chats or manually summarize their work. Compaction changes the model's
working context, not the saved conversation. All original messages, complete
executed tool calls/results and terminal outcomes remain inspectable and portable.
This extends P06–P09; it does not introduce another conversation type.

C02. Perform context maintenance automatically before exhaustion. Ordinary
compaction is quiet. If it causes a noticeable pause, show a brief progress state
and retain cancellation. Navigation, search and previews remain usable. On failure,
keep the last valid checkpoint and all completed work; do not claim the request
finished. Recover or retry from saved state without repeating completed actions.
Do not silently switch to a cloud model or a different workbook.

## Context profiles and budgeting

C03. The existing 8,192-token native context with at most 1,800 output tokens is
a development setting. Qualify 32,768 first, then 65,536 where practical on the
reference hardware. Larger contexts become a default only after complete workbook
jobs, input processing latency, memory pressure and correctness pass. A model's
advertised maximum or an engine accepting a number does not establish usable
capacity. Keep physical hardware, model/draft revisions, memory/SSD budgets and
runtime configuration in each result. No universal context size or speed claim.

C04. Count the exact rendered prompt tokens, including policy, tool schemas,
context, summary, history, tool receipts and template delimiters. Reserve output
capacity, a bounded next tool result and framing/recovery headroom before deciding
to generate. Check again after each tool result and before final generation.
Reserve sizes are measured profile policy, not character-count approximations.
At a threshold, compact completed history and bounded completed tool groups before
another request. Never split a tool-call/result group or truncate action arguments.
A tool result larger than its allocation returns a truthful bounded projection
with an exact persisted locator and retrieval path.

C05. The current request, stable application policy and host-reconstructed action
state have priority over summarized history. Retrieval narrows long documents and
tables before they enter the context. Oversized irreducible input fails truthfully
without discarding the original. Do not shrink away constraints to make a prompt
fit. If compaction cannot reclaim enough space, narrow retrieval or continue from
a durable checkpoint; only surface a task-specific clarification when necessary.

## Durable checkpoints and authority

C06. A checkpoint is a versioned derived context artifact in the workbook, not a
new source of business truth. Preserve the covered conversation/message range,
content hashes, exact evidence/version locators, run identity, parent checkpoint,
model/template/transformation versions and the workbook snapshot revision used.
Keep original messages and receipts append-only. Avoid copying all earlier
summaries into every new checkpoint. Link to them and to their original evidence.
A checkpoint may be superseded without erasing its history.

C07. Publish a validated checkpoint atomically. Cancellation, process death or a
failed summary leaves the prior checkpoint usable and the original history intact.
Use expected covered-message identity and current workbook revision when publishing;
if state changed, refresh authoritative fields or retry rather than committing a
stale status snapshot. Reopen and portable export include checkpoints and original
history. Derived retrieval indexes can be rebuilt without losing either.

C08. Separate a bounded model-written digest from host-owned operational state.
The digest preserves user constraints, decisions, unresolved questions, pending
work and pointers to exact supporting messages. Unknowns and conflicting versions
remain explicit. Preserve identifiers, units, formulas and quantities exactly where
needed, otherwise keep an exact retrieval pointer. The summarizer receives no
mutation tools. It cannot accept a proposal, change a rule, run a transaction or
establish new authority. A fluent summary is never proof of a completed action.

C09. On every resumed turn, reconstruct proposal acceptance, current item heads,
meaning, completed operation IDs, idempotency keys and terminal run outcomes from
workbook state. Keep the current user request intact. Accepted forecasts remain
estimates. Failed/cancelled/interrupted requests remain closed unless the user
reopens them. A summary saying a draft is accepted must not override a current
draft or withdrawn state. Actions that already succeeded cannot be repeated merely
because the summary calls them pending. Historical instructions and retrieved
source text remain untrusted for present authority.

## Retrieval, chapters and tangents

C10. Provide bounded, searchable conversation history and exact message/tool
receipt retrieval in addition to the existing document/record search. The agent
can recover details omitted by a summary using message IDs, ranges and evidence
locators. Cite original versions for business claims, not the digest alone. Track
what evidence is present in the current working context; an ID remembered in a
summary alone does not count as newly inspected evidence. Disclose retrieval gaps.

C11. Checkpoints are scoped to one conversation. Chapter boundaries are useful
navigation hints, not new authority or a reason to lose cross-chapter constraints.
A tangent inherits only its explicit parent context and saved references; later
parent changes do not silently rewrite that inherited history. Bringing a result
back to main preserves origin and scope. Rebuild current business status from the
same workbook, while keeping scenario and actual/estimate distinctions. No other
workbook's private context can enter a checkpoint or retrieval result.

## Required qualification

C12. Test repeated compactions over a long multi-step job, not just one synthetic
summary. Check first and latest instructions, exact values/units/IDs, tool-result
pairing, source version recovery, many chapters, tangents and return to main.
Change a draft to accepted or withdrawn during maintenance; verify reconstructed
status and no duplicate inventory effects. Include hostile instructions in old
history/documents, failed and cancelled requests, restart after checkpoint publish
and interruption before publish. Reopen/export offline and inspect original
history. Persist failures and compare to the uncompressed reference workflow.

C13. Measure prefill and first-token latency, complete task latency including
compaction/retrieval, peak resident memory and memory pressure, success/correctness,
bytes read and thermal/power context where available. Compare 8K/32K/64K at recorded
prompt occupancy; a short prompt in a large allocation is only a startup check.
Use sustained realistic workbook tool jobs with enough repeats to expose variance.
Select the smallest qualified context that supports useful continuity on each
supported profile. Never trade away source history or acceptance guarantees for a
faster decode number.

## Implementation sequence and current limits

1. Add explicit candidate context profiles, exact-token budget decisions and
   inspectable metrics. Keep current product behavior labeled until qualification.
2. Add durable checkpoint storage, versioned serialization, complete tool receipts,
   indexed history/range retrieval and migration/export/recovery tests.
3. Add tool-free structured summarization, host-owned continuation state and
   proactive compaction in the shared agent loop. Maintain cancellation and leases.
4. Test repeated maintenance and adversarial state transitions through the actual
   native model, then qualify 32K and practical 64K on complete workbook jobs.
5. Select a measured product profile, integrate progress/recovery in the app, and
   verify J10 plus the existing J01–J09 before adoption.

The first instrumentation stage now provides internal 8K/32K/64K evaluation
profiles. Native startup and prompt rendering use the same configured capacity.
Exact prompt counts determine output allowance and a maintenance recommendation
with provisional reserves of 1,800 output, 2,048 next-result and 256 recovery tokens.
The recommendation is currently diagnostic; no controller acts on it yet. The 8K
profile's tool policy can itself exceed that provisional threshold. A controller
must detect this irreducible floor rather than repeatedly compact unchanged
history; reserve sizes or supported profiles require measured selection.

The storage foundation now supports durable, chained context checkpoints at
completed-turn or recorded tool-result boundaries. A mid-run checkpoint preserves
the original request and does not close the task. Checkpoints include
original-history hashes, exact evidence references and current-state inspection.
History FTS, exact message/payload reads and keyset paging are available through
the shared core and CLI. Schema-1 migration and offline export/reopen are tested.
New runs link to their request messages and completed native receipts preserve
call/run identity. Legacy messages remain intact without invented metadata.

The agent still uses bounded recent history and explicit closed outcomes. It does
not yet create summaries, schedule compaction, use older-history retrieval tools
or resume a persisted multi-step job after process death. The interval between a
business mutation and its tool-receipt write needs explicit recovery from operation
state. Oversized tool results also need a bounded valid projection and durable
retrieval instead of the current character-prefix projection; the 128,000-byte
message ceiling must not lose a successful action receipt. These are required
remaining work, not claims about the installed app.

See [[records/specs/intelligence]], [[records/specs/storage]],
[[records/specs/product]], [[records/specs/splash-integration]] and
[[records/operations/implementation]].
