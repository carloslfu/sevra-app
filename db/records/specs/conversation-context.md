---
type: spec
meta-type: conclusion
id: 01m5x2pp178p3a4ay7hbfx7wdg
created: 2026-10-26T21:43:43.399273+00:00
updated: 2026-10-27T03:38:53.260949+00:00
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
locators. Cite original versions for business claims, not the digest alone. Original
conversation statements use a separate message:ID citation returned only after
reading an eligible message. The current request and later messages cannot be
presented as earlier evidence. In-app links open that original exchange; they do
not make the message a business Record or grant permission. Track
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
A controller now measures the exact rendered prompt and acts before each normal
agent dispatch and after completed tool groups. The 8K policy can itself exceed
that provisional threshold, so this development profile uses a measured irreducible
floor plus reclaimable-history allowance. It still reserves 1,800 output tokens.
The full provisional next-result/recovery reserve is not a qualified guarantee
under that adaptive threshold; wider profiles and context-sized projections remain
required. A too-large request or latest result fails without cutting originals.

The storage foundation now supports durable, chained context checkpoints at
completed-turn or recorded tool-result boundaries. A mid-run checkpoint preserves
the original request and does not close the task. Checkpoints include
original-history hashes, exact evidence references and current-state inspection.
History FTS, exact message/payload reads and keyset paging are available through
the shared core and CLI. Schema-1 migration and offline export/reopen are tested.
New runs link to their request messages and completed native receipts preserve
call/run identity. Legacy messages remain intact without invented metadata.

With a qualified compaction-capable adapter, the shared agent can load its latest
verified checkpoint, reconstruct current
host state and compact original history into a smaller working context. It can
call history_search/history_read for older originals in its conversation.
Search excludes the current run's request and subsequent messages so a question
cannot masquerade as the earlier answer. Append-safe cursors survive receipt writes.
A real native 8K probe retrieves an original beyond 110 closed messages, reads it
and answers the exact purchase code without inventing a currency.

Prepared tool-call journals precede execution. Completion atomically saves the
full result and a bounded conversation projection. Large results are navigable with
tool_result and remain exact; the model never receives cut JSON. Only whole fields/elements actually shown from
fresh tool results grant the existing citation/calculation evidence automatically.
Older receipts require refreshed evidence before reusing claims. Prepared calls
with missing final receipts expose real committed-operation proof, retain uncertainty
for partial intake and cannot be replayed under the same call identity. Resumed
conversation includes a bounded host report of unresolved calls, not authorization.

The candidate controller now creates tool-free, schema-validated notes with exact original
message references. It preserves the current request and latest call/result group,
reconstructs current proposal meaning/status and committed operation identities,
and retains an eight-entry unresolved-call report with the total count. Tool-only digest claims are projected as historical retrieval references, rather
than competing prose about mutable status. A digest cannot grant citations. After compaction, calculation/currency evidence that left
the working context must be inspected again. Checkpoints publish atomically only
after validating the unchanged source range and refreshing the workbook revision.

The first native attempt exceeded its summary output budget. A shorter schema
finished, but a stronger check found it forgot an exact earlier user value. The
current conversation-notes-v2 format keeps bounded typed notes; the host preserves
previous user-backed fact/constraint/decision notes instead of letting routine
progress displace them. Raw generated notes have at most six entries, 240 Unicode
scalars each and one or two exact references. The merged saved digest remains at
most 16 KiB. The host does not claim the initial model extraction is infallible:
original messages remain retrievable, older unstructured checkpoints remain
verbatim in a bounded legacyDigest field, contradictions stay visible, and unlimited
note growth or semantic retirement is not solved by dropping old constraints.

Backfill currently processes at most 128 original messages at a time, with whole
entries and token-measured smaller batches. Its latency is foreground work. Native repeated-compaction, authority and recovery results are mixed: a later
retry still searched business documents instead of recalling original conversation.
Repeated end-to-end continuity is not qualified. Detailed results belong in the implementation
register and evidence; synthetic controller checks alone are not model quality.
The preserved Slotstream adapter has a separate opt-in qualification probe. It
failed recall by searching business documents instead of conversation history, so
production Slotstream keeps automatic compaction disabled. This is an explicit
capability gate, not a runtime switch or hidden provider fallback.

General persisted-job restart after process death remains unfinished. A prepared
journal makes an uncertain interval inspectable; it is not the complete action
recovery controller. Resolution UI, streamed large-result memory checks, broad
kill/restart injection, sustained larger-context jobs and full J10 remain required.

See [[records/specs/intelligence]], [[records/specs/storage]],
[[records/specs/product]], [[records/specs/splash-integration]] and
[[records/operations/implementation]].

## Native continuity search follow-up
The shared agent now searches business evidence and original conversation together
on an unfiltered first page, preserving separate types, citations, filters and
cursors. See [[records/specs/search]]. Three consecutive native 32K continuity
probes passed the long-history, original-citation, portable-reopen,
false-digest/current-acceptance and cancellation/retry sequence. A final repeat
after the pagination repair passed recall/reopen but reached the step limit while
inspecting the draft forecast, after reading its real record. Later acceptance
and cancellation stages were not reached in that final trial. All four attempts
are retained in integration/evidence/2026-10-26-scoped-search.json. The earlier
routing failure remains in its original context-maintenance evidence.

The host retrieval and receipt-stable pagination checks pass. Repeated general
model completion does not. This is not C12/J10 qualification, a statistical
reliability claim or a production context-size decision. Longer jobs, different
wording, many durable constraints, process death, hardware and performance gates
remain open. Native adoption and baseline automatic compaction remain disabled.

## Bounded reasoning and inspection recovery checkpoint
The next investigation isolated off versus bounded512 on frozen workbook archives, then separately repaired within-request reasoning continuity, final-answer provenance and recovery. Reasoning is ephemeral execution state, counted in context budgets and absent from durable history, checkpoints and later requests. Original messages, current record versions and deterministic calculation results retain their separate authority.

The R5 follow-up passes 15/15 automatic task checks, two complete native continuity sequences and the autonomous workflow. Controlled fault injection verifies that an uncited evidence answer or unsupported current_request number requires an actual inspection-only model call before retry. The final repeated fixture passed with both thinking modes after the separate non-compacting history correction. That path now presents earlier messages as historical data, preserving IDs, authorship and proposal status, while leaving only the current request as a live user message. Original history is unchanged and automatic compaction remains disabled in Slotstream. Keep this deliberate recovery test separate from autonomous completion, and retain its initial wording-sensitive assertion failure.

These results do not erase earlier failed continuations or qualify every narrative assertion. Manual review found a workbook-wide absence overclaim after non-exhaustive searches despite correct forecast status/meaning. C12/J10, broad grounding, long-lived constraints, process death, physical hardware and performance remain open. Native adoption, a larger production context default and baseline automatic compaction remain disabled. See [[records/specs/intelligence]], [[records/reviews/design-passes]] and [[records/operations/implementation]]; complete evidence is in integration/evidence/2026-10-26-bounded-reasoning.json.

## Historical context without automatic compaction
The preserved backend keeps automatic compaction disabled. Its recent-context path now presents up to eight prior conversational entries as explicitly historical data, rather than replaying earlier requests as active user turns. Preserve original message IDs, authorship, states, bounded text and truncation flags. Text projection is limited to 1,600 characters per entry; full originals remain available through history_read and keep their original bytes.

Parent-conversation excerpts remain separate. Pending-review messages carry current proposal version, acceptance, meaning and dataset identity from the workbook. Unresolved-call notices remain host information, not new user requests or authority to replay an action. The actual current request follows this context. At the start of the run, historical user messages do not become live user-role messages. Existing validation feedback later in the run remains host-controlled.

This projection aligns the authority boundary with native context maintenance without enabling summary generation, changing stored history or granting citation eligibility. Actual-model qualification must include a completed task followed by a different task, historical recall, review-state changes and cancellation/retry.
