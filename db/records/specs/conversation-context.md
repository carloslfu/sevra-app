---
type: spec
meta-type: conclusion
id: 01m5x2pp178p3a4ay7hbfx7wdg
created: 2026-10-26T21:43:43.399273+00:00
updated: 2026-10-28T03:28:56.987647+00:00
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

## Retrieval, optional chapters and Threads

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
A thread inherits only its explicit parent context and saved references; later
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
Exact prompt counts determine output allowance. The October 27 owner policy uses
min(floor(0.75 * configured capacity), capacity - 1,800 output - 2,048 next-result
- 256 recovery/framing). Native ContextBudget and shared ContextMeasurement use
the same function. The thresholds are 24,576 at 32K, 49,152 at 64K, and an earlier
4,088 at 8K because of reserves. These are not newly qualified product capacities.

The controller measures complete template output with schemas, retained history,
digests, receipts and delimiters. Native uses its real frontend/tokenizer; baseline
uses encodeChat and reads the engine's configured window. Measurements include the
full workbook tool set, conservatively reserving that schema even when the next
response is scoped to fewer tools. Actual generation uses its rendered scoped
prompt and an independent hard capacity check. Baseline now includes its 1,800
reply tokens in that hard check and records its exact prompt/capacity/threshold.

After completed tool groups, maintenance compacts only eligible history. Before
each generation, another measurement catches carried handoff proof or recovery
text added after maintenance. If that live group reaches the threshold, fail
explicitly rather than drop it or dispatch beyond the policy. Required policy,
request and host-state floors cannot silently raise the threshold. Refusals state
measured tokens, threshold and preservation of original input/completed work.
A summary that reclaims too little, or a saved checkpoint whose remaining context
still reaches the threshold, cannot count as successful maintenance. Saved
checkpoints and originals remain available. Checkpoint metrics distinguish its
publication from admission of the next generation and retain actual floor, trigger
and available before/candidate counts. No model weights, reasoning budget, KV
handling, user settings or automatic-compaction product gate changed.

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

## Stopped requests in automatic context
Requests linked to cancelled, failed or interrupted runs enter automatic context as status plus a reference to the original message. Do not repeat their imperative text as a new pending task. Full original bytes, authorship and message IDs remain available through history_read when the current user request needs them. Exact indexed request-to-run linkage is independent of the recent-run display limit.

Apply the same reference-only projection when preparing summary inputs and presenting existing notes that cite a stopped request. This changes model context, not durable conversation evidence, and does not grant citation eligibility. It does not enable automatic compaction in either product path.

Keep lifecycle recovery and following a new request as separate checks. A clean release is insufficient when the next answer addresses a different task. The preserved reasoning-off baseline still failed a new request to reply Ready after cancellation, including after this projection change. Native bounded512 passed that sequence. Neither establishes universal request relevance. The request-admission follow-up now qualifies crash-left running requests and lease refusal before linkage. Admission atomically preserves the message/run relationship; recovery precedes context projection and a current-message boundary excludes later submissions. An actual packaged-native CLI kill, forced lease refusal and Ready follow-up passed. This does not fix the separately recorded baseline relevance failure or qualify every crash boundary.

## Inherited parent evidence
A tangent may read an exact original message from the same fixed parent excerpt it already inherits. The host admits only those explicit message IDs through history_read, records their owning conversation and links citations back to that original conversation. History search, checkpoint scope and saved tool-result access remain confined to the tangent. Earlier parent messages outside the excerpt, later parent messages, sibling conversations and transitive ancestors remain inaccessible. Merely seeing an inherited excerpt does not grant a citation; history_read must expose the eligible original first. Current/later request messages still cannot be cited as earlier evidence. Bringing an exchange back to main creates a preserved copy with the original conversation link.

This fixes an inconsistency where the context showed inherited messages but exact retrieval refused them. Deterministic direct/nested-tangent checks reproduce the old refusal and cover allowed reads, denied scope, cutoff rules, citation routing and unchanged business records. Native workflow qualification is recorded in [[records/operations/implementation]].

## Checkpoint publication durability harness
The core has a package-only publication observer for an owned-process crash
harness. It is inactive in the product and cannot be enabled by workbook content
or an environment variable. The prepared barrier follows checkpoint/input inserts
inside the transaction; the published barrier follows the committed operation.
The controller checks external visibility, kills its child, reopens the workbook,
retries exact publication and verifies portable state. Separate cancellation and
concurrent acceptance cases exercise rollback and stale-input refusal.

All four cases passed in hosted CI 40503178418 on c0ac40f. This qualifies those
core durability boundaries on that runner. Local replay remains pending while W1
runs. Actual model compaction quality, repeated compactions within one long
request, occupied contexts, pending tool recovery and the uncompressed comparison
remain separate acceptance work. The result does not enable automatic compaction.

## Active-job qualification protocol
This is a focused C12 probe, not a substitute for the complete C12/C13/J10 matrix.
Use one frozen synthetic workbook for two sequential native arms: automatic
maintenance at 32K, then a 64K arm with maintenance disabled. Both retain bounded512
reasoning, the original 12 GiB engine budget, unchanged pins and the normal
12-step agent limit. The larger reference is a functional comparison; one job per
arm does not qualify latency, memory, occupied-context support or adoption.

The job first saves one named working space, then reads eight inspection reports,
then creates one receiving memo and confirms that it is saved. Each report carries
an exact labeled clearance/unit/disposition and fixed synthetic inspection
fingerprints. They create real token occupancy without altering the threshold,
injecting tool replies or supplying model choices. Preflight requires every full
read to fit the existing 16,000-byte tool result bound. The request preserves an
earlier purchase code and original/corrected packing quantities from conversation.
No acceptance or inventory change is permitted.

The maintained arm must publish at least two checkpoints ending at tool receipts
within this one active job, after the working space already exists. Both arms must
read all eight exact source versions, produce exactly one space and one draft,
preserve each labeled value/unit and both original/corrected quantities, retain all
original heads/history and leave accepted inventory unchanged. The draft's lineage
must contain every report. Export/reopen must preserve the draft, checkpoints,
inventory and integrity. Fewer than two active checkpoints is missing coverage,
not a pass and not permission to lower the maintenance threshold. A failed 64K
reference stays a failure; do not silently increase its capacity or hide it.

Retain both workbooks, original fixture archive, exact request, per-response context
metrics, summarization boundaries, complete history, runs, failures and unload
results. The wrapper observes real inference only. Token occupancy comes from the
native metrics; configured capacity is not occupancy. Cancellation/process death,
concurrent acceptance changes, tangents, hostile content and sustained memory
remain separate C12/C13 cases. Existing passing continuity/checkpoint checks do not
waive this new single-job coverage requirement.

## Active-job v1 result and repair boundary, October 27
The first correctly configured run on frozen 48b1a30 failed both arms. The 32K
maintained job completed twelve responses and three active checkpoints, but saved
four report clearances under the wrong CHECK labels and created Receiving review
twice. Its draft remained an estimate. The 64K uncompressed arm completed eight
responses, reached a largest successful prompt of 60455 tokens, then refused a
request that exceeded context. It created no receiving draft. Both unloaded.
All fourteen original items/heads, inventory effects and starting balances were
unchanged; both workbooks pass integrity. Full C12/C13 and compaction stay disabled.

The trace shows that large read results become historical references during
maintenance, while the host continuation projection omits their bounded source
text and completed space titles. This is a concrete information-loss boundary,
not proof that a prompt change alone will solve the observed errors. The next
repair must retain bounded, exact, explicitly partial source excerpts with their
version/receipt identities and current-vs-historical state, plus host-derived
identities/titles for already saved artifacts. Treat quoted source content as
untrusted evidence, never new instructions. Do not admit summary prose as truth,
load all originals, retain stale acceptance, or replay completed creations.

Add deterministic scope/bounds/stale-state/duplicate-artifact regressions before
retesting the actual maintained job. Preserve the failed 64K comparison; do not
increase its capacity or silently remove it to call v1 passed. Any smaller fixture
or narrower repair-only probe must have its own explicit scope and retained v1
comparison. Evidence and independent state audit:
integration/evidence/2026-10-27-active-context-first-full.json.gz and
integration/evidence/2026-10-27-active-context-first-full-audit.json.

## Bounded continuation evidence repair, October 27
The host now retains exact partial excerpts from completed read receipts in the
current run, with source-version and receipt identities. It checks the observed
text against the immutable source prefix before retaining it. Only fields visible
in the original result count; a projected omission or old-run reference cannot
manufacture observed evidence. Each retained entry separates original meaning and
status from the current head. Titles and text remain untrusted quoted evidence.

The projection examines the newest 100 calls, keeps at most eight distinct read
versions, uses at most 256 Unicode scalars per text prefix and 128 title characters,
and caps serialized excerpt entries at 8192 bytes. It reports omitted versions and
whether older calls were excluded. It reads bounded source prefixes through SQLite
rather than loading complete documents or arbitrary item payloads. Excerpts are
explicitly partial and do not restore citation eligibility. Required omitted facts
must be retrieved from the source or its saved tool result.

Up to sixteen saved-space identities retain the recorded creation title and the
current title/version or missing state. This gives the model exact IDs for work
already saved, without replaying a mutation or keeping stale definitions. Existing
idempotency and acceptance boundaries remain unchanged. Deterministic checks cover
scope, deduplication, omissions, Unicode/NUL, source integrity, live acceptance,
renames and export/reopen; the repeated-maintenance fixture inspects the actual
host envelope.

The next actual-model check is explicitly active-job-context-v1-maintained-repair:
the unchanged eight-report, 100-fingerprint v1 fixture, same 32K allocation,
bounded512 reasoning, 12 GiB budget and twelve-step limit. It requires every exact
association, one space/draft, all eight lineage inputs, unchanged original state,
at least two real active checkpoints and successful portable verification. The
--active-context-maintained flag runs only this repair diagnostic. Its result
cannot set completeComparisonPassed, clear the failed 64K reference, qualify
C12/C13 or enable production compaction. Freeze code before execution and retain
identities and failures.

## Maintained v1 repair result, October 27
Both maintained32K repair replays on frozen b1e6e5e pass the unchanged v1 fixture.
Each completes twelve responses and four active checkpoints, saves exactly one
Receiving review space and one draft/estimate memo, preserves all eight exact
label/value associations, and retains every source in the draft lineage. Original
items/heads, earlier messages, inventory bases/effects, export/reopen and integrity
checks pass; native resources unload. An independent SQLite audit also confirms
that fixture items match the original failed v1 fixture exactly.

The first replay overlapped the explicitly approved human dictation test and is
retained as an uncontrolled functional observation. Its original identity statement
about the idle preview is corrected by an attached conditions addendum. The second
runs with dictation stopped, no overlapping builds or workbook inference, and
unchanged source/binary/helper/grammar identities. It is the controlled repair
result. Their 251.02/339.46 seconds include verification and are not a latency
comparison or throughput claim.

This resolves the observed maintained-job fact-binding and duplicate-space failure
for this fixture. It does not clear the earlier uncompressed64K failure or complete
C12/C13, hostile/tail-only evidence, interruption or sustained-memory coverage.
Automatic compaction remains disabled. Retained inputs, traces, conditions,
independent audits and reopen hashes are in
integration/evidence/2026-10-27-active-context-maintained-repair.json.gz.

## Conversation and Threads terminology

The main history is called Conversation. Optional discussions are Threads, created
with Start a thread and revisited by descriptive title. Back to conversation returns
to main. Chapters remain optional message-boundary headings. Older tangent IDs,
fixtures and API names remain compatible and retain their original scoped-context
semantics; terminology alone does not widen access.

Share summary with conversation preserves the exact source conversation/message
link and user-selected text. The summary is a historical user contribution, not a
new business acceptance or live request to the model. Existing history envelopes
continue to distinguish saved information from current instructions. The original
exchange remains in its thread; sharing does not make sibling or source history
implicitly searchable from main. The link explicitly opens that original scope.
See [[records/specs/product]] and [[sources/notes/2026/10/conversation-threads-refinement]].

## Owner-selected 75% trigger, October 27
The owner decision relayed from the side conversation selects 75% of the actual
configured context capacity. The original ephemeral conversation could not be
re-read through the thread API; this records the relayed decision and its stated
constraints, not an independent transcript verification.

Use min(floor(0.75 * capacity), capacity - requiredReserves). Thus 32,768 gives
24,576 and 65,536 gives 49,152 before any earlier reserve requirement. The complete
rendered prompt count includes policy, tool schemas, retained history, summaries,
receipts and template delimiters. Preserve output, next-result and recovery/framing
reserves. Audit both native and preserved-baseline adapters and the controller's
adaptive threshold. Never silently raise above 75%. An irreducible policy, current
request or authoritative-state floor must produce an explicit measured outcome,
without loops, dropped constraints or false successful compaction.

Compact completed history/tool groups only. Preserve current instructions, exact
identities/quantities, accepted/current/pending state and retrieval pointers.
Original transcripts and receipts stay immutable and searchable. Check after tool
results and before generation, with an independent hard overflow check. No new
user context setting, periodic permission prompt, weight/reasoning/memory change,
or inference-cache policy change accompanies this conversation policy.

75% is an owner-selected policy, not a measured optimum for this Qwen/Splash
quantization. Earlier evidence and 8–12K errors retain their original scope and
cannot be attributed to this threshold. Automatic compaction remains disabled
until repeated real jobs pass under the revised policy. Boundary accounting,
earlier reserve triggers, irreducible floors, repeated maintenance, cancellation,
reopen, authoritative state, retrieval and no replayed actions require focused
verification. Implementation alignment is complete; the first native policy replay failed
functional acceptance as recorded below.
An irreducible floor now refuses explicitly instead of taking a silent policy
exception. The owner-selected threshold is unchanged by that refusal.

## 75% policy checks and native failure, October 27
Deterministic checks pass the selected boundary, equality and one-token-below
cases, integer rounding, earlier 8K reserve trigger, irreducible floor, no eligible
history, insufficient reduction, and published-checkpoint-but-still-full refusal.
A malformed-response retry now proves that additional live context is checked
before the next generation. Existing repeated maintenance, original IDs/quantities,
accepted-estimate state, cancellation, invalid digest, tangent scope, retrieval,
portable continuation and no duplicate writes checks also pass.

The old synthetic active-job fixture exposed a required floor of 4,120 tokens
against the 8K reserve threshold of 4,088. The explicit refusal is retained. Its
repeated-success controller fixture now uses a declared synthetic 12,288 capacity;
this is not an added model profile. Dedicated 32K scripted boundary tests exercise
a 24,000 floor that the former adaptive +1,024 allowance would have raised above
75%. No further threshold exception is used.

One real native maintained32K replay of the unchanged eight-report workload FAILED
functional acceptance. It completed 12 responses and 8 checkpoints in 245.626
seconds including test verification. Every normal response's actual prompt stayed
below 24,576 tokens (range 10,019 to 24,271). The checkpoints measured above-trigger
prompts and smaller candidates; these observations establish the policy path on
this sample, not capacity or latency qualification.

The saved Receiving memo preserved MAPLE-27, 0.10 kg, 0.25 kg, unspecified currency,
all eight clearances/dispositions and source lineage, but replaced every requested
exact X-CHECK label with Inspection X. The final answer claimed exact labels were
included. It also attempted save_space twice; the identical request was idempotent
and only one space exists. Do not call this a no-retry success. The generic test
error Expected complete tool candidate was independently traced to missing exact
labels. Original rows and business state remain unchanged. Failed work and all
checkpoints survive export/reopen and integrity checks. The model unloaded normally.

The source/model budget was not changed during execution; bound source/binary,
engine and grammar hashes match before/after. No repeated run was launched to seek
a passing result. Existing bounded exact read excerpts already exist in continuation
state; do not assume loss of all source evidence or blame the threshold itself.
Inspect drafting-time inputs and repair exact-copy behavior and completion claims
before repeating the failed job and nearby counterexamples. C12/C13/J10 and automatic
compaction remain unqualified. The preserved baseline adapter compiled and shares
the threshold, but no new baseline-model inference cohort was run.

Evidence: [75% policy receipt](../../../integration/evidence/2026-10-27-context-75-policy.json.gz) (95,680 bytes compressed, 354,037 bytes decoded;
SHA-256 67ac05d72b3a51facba84b8075284c696d63203ef771a2adc626e9c4c68d5f87).

## Literal-copy follow-up and rejected review gate, October 27
A second unchanged 75% job still failed exact labels even though its actual
drafting input contained all eight original CHECK labels. The saved-result message
now confirms only storage through host receipts; this does not pass the document
job. The instrumented inference wrapper retains complete pre-render messages and
tool scope without supplying any extra model text or altering the fixture.

An independent literal-copy reviewer passed small native cases but failed this
full job with false refusals and incomplete findings. It demanded lineage IDs in
the body, then refused corrected content; two draft attempts failed and the
existing response budget expired. One idempotent space remained, no draft was
saved, and original state and integrity stayed intact. The experimental reviewer
was removed from the app path. Do not enable compaction, enlarge the response or
context budget, or relabel either job as passing on this evidence.

Next investigate source-bound document composition which inserts selected original
spans/blocks through the host. Preserve exact-copy requirements separately from
paraphrased prose, lineage metadata and completed interface actions. The future
contract must fit [[records/specs/references-and-relationships]] and cover source
tails and earlier conversation without making a summary authoritative. This is a
next design step, not a completed API or qualification result. See
[[records/specs/intelligence]] and [[records/operations/implementation]].

Evidence: [saved-artifact and rejected-review receipt](../../../integration/evidence/2026-10-27-artifact-fidelity.json.gz), 377,349 bytes compressed; SHA-256 `83f309ea041dd4b939f6c37b16266d03a59c44e399260043440487a7770666fe`. Final native visual verification is pending manual unlock.
