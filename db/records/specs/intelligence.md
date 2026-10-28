---
type: spec
meta-type: conclusion
id: 01m5rbxzb0mz1b78ergkwybtnp
created: 2026-10-25T01:48:47.328971+00:00
updated: 2026-10-28T16:32:39.785197+00:00
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
The adopted [[records/specs/persistence-readiness]] F06 requires exact persisted
AI/tool outputs, input versions, actual actor and authorizing policy where present.
Reconstruction uses those saved outcomes without inference or execution. Future
semantic conflict handling should prefer automatic resolution and involve the
user when evidence/validation cannot support an outcome; implementing that
resolver or widening today's acceptance authority is outside this requirement.

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
Display permission waiting, microphone startup and active local listening as
distinct states. A Stop control while permission is pending must not imply that
audio capture has begun. Keep the phase accessible to assistive technology.
Partial recognition appends to the current typed draft and replaces only its own
recognized segment. A manual edit, explicit send, conversation/workbook switch or
window close stops dictation; late results cannot overwrite the draft. Sending
always requires an explicit action. Permission requests and capture belong to one
cancellable session from the first tap, with at most one recording owner across
workbook windows. Cancelled permission callbacks may not start capture, and old
recognition callbacks may not publish text, report an error or stop a newer session.
Before microphone capture starts, pause all live workbook playback, including
compact players in other windows. Do not automatically resume it after dictation.
Closing a workbook pauses and releases its players, regardless of view teardown
order. Playback tracking must not keep a closed viewer alive. File transcription
is separate from live dictation and must label supported limits. Lifecycle tests
with injected callbacks do not qualify actual permission prompts, microphone
hardware, supported language assets or recognition accuracy.
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
This storage boundary is active. Automatic context maintenance is implemented and
opted into by dedicated native evaluation probes. Both packaged product paths keep
it disabled: NativeProductResources explicitly sets contextMaintenanceEnabled to
false, and the baseline initializer does the same after its recall probe failed.
The native preview currently evaluates 32K with bounded512 reasoning; this is not
a qualified final context profile. General action recovery after process death
remains open.
A read returns the requested exact version plus current-version metadata and a
snapshot revision. Current-version metadata is a navigation pointer, not newly
inspected evidence: read that version before citing its facts.


## Conversation citations
history_read exposes a message:ID citation only for an eligible original message earlier than the active request. Eligibility includes the active conversation and the fixed parent excerpt explicitly inherited by a tangent. It does not include other parent messages, later parent changes, siblings or transitive ancestors. History search and saved tool-result access remain within the active conversation.

A freshly read original body must actually be visible before that reference joins the allowed finish citations. Search snippets, omitted bodies, a derived digest, an unread parent excerpt and the current request do not grant it. The app renders an Earlier message link to the original message's owning conversation, including for nested tangents. Business item version IDs retain their existing meaning and lineage rules. Conversation citations support what someone said, not current inventory, acceptance or permission.
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

## Actionable answer correction and terminal evidence
Complete item UUIDs that meet the typed-reference rendering conditions below become named native links. For remaining full UUIDs or inspected abbreviated references, the host identifies the exact offending text, including source IDs in parentheses and Supporting evidence sections. Correction feedback names up to sixteen offending references and requires checking the whole answer; more matches remain invalid. Prefer human source names in model prose and exact IDs in the citation field. Rendering an already admitted item reference is a presentation operation; it never admits an unknown or uncited reference. Do not silently remove or rewrite unverified factual claims, weaken currency/calculation/evidence checks, or accept a bad answer to improve completion rates.

Preserve every rejected finish candidate with its validation feedback and original arguments. If the fourth candidate still fails, save that final rejection before ending the run with answer_validation. The existing three correction opportunities remain bounded. A failed final answer must not erase committed workbook actions or publish invalid assistant prose. Test both corrected completion and exhausted correction, including the final durable receipt. This policy applies to both inference adapters.

## Typed calculation references
A successful balance calculation returns typed evidence metadata: referenceType=item-version and the exact opening-basis/effect IDs in evidence.citations. These identify immutable workbook Source/Record versions, not conversation messages or count receipts. The host already admits those calculation inputs for citation after an untruncated successful result. Additional source content still requires read; history_read is only for conversation messages.

A balance answer must cite every supporting calculation input. A missing-citation correction names the required IDs and their type and explains that history_read or count_records is not needed to cite the calculation. This clarifies the existing authority boundary; it does not admit fabricated IDs, count receipts as evidence, unread document claims or incomplete tool results. The model must still complete the normal validated finish path. No engine, sampling or caching change is involved.

The motivating I1 case took twelve model steps and three rejected finishes on both frontends after an opening-source UUID was mistaken for a conversation-message ID. Functional regression must check the original balance, complete citations, unchanged business state, no repeat of that confusion, and actual native/reference completions. Latency observations from a small recovery probe do not qualify performance or universal reliability.

The host may render a complete item UUID in plain answer prose as a named native citation only when that exact item version was inspected in this run and is also listed in finish.citations. Case variants resolve to the admitted canonical ID. Claims, calculations, currency, required inputs and citation authority are checked before publication. Unknown IDs, abbreviations, message references and IDs inside code or model-written links retain the refusal path; this is not general Markdown repair.

Rendering substitutes original text positions once, so an inserted URL or source title cannot be processed as a later model reference. Labels escape Markdown and collapse newlines. Evidence already linked inline is not duplicated in the suffix; remaining citations keep their named links and locators. Save the original finish arguments and a renderedReferences mapping with the assistant message. This is presentation of existing evidence, not admission of a new citation or automatic correction of a factual claim.

The fixed-seed native/reference recovery does not qualify general reference reliability. A later final-package test with fresh UUIDs still mistyped a movement ID, took a history detour and required two finish corrections. Keep that failure as a regression case. Future model-reference design must make exact candidate selection dependable, preserve canonical immutable IDs in storage/receipts, refuse unknown handles and avoid fuzzy automatic redirection. Short typed per-run handles are a proposed approach; they are not implemented or a new workbook format decision.

## Exact visible item references
Observed inventory failures included copying the wrong suffix of a long item ID despite correct stock arithmetic. Read, lineage and references now use a host-built candidate vocabulary. Before generation and context measurement, collect UUID-shaped lookup values from the visible conversation content and verify each through the current workbook. Preserve exact supplied lookup strings, including an existing logical-ID lookup, instead of fuzzily mapping a typo to a different item. Unknown UUIDs and unrelated business identifiers do not enter the vocabulary. Discovery remains available through search, datasets/rows and lineage.

Attach the verified choices as ephemeral host metadata on inference messages. Do not persist that metadata as evidence, parse it from model output or accept it as action authority. A UUID mentioned in untrusted text may be a read candidate only if it resolves exactly in this workbook; that does not make the text true, admit a citation or authorize a mutation. Citation admission continues to use the separately maintained inspected-result set. Historical references remain historical until refreshed.

Both adapters use the same dynamic tool schema for read/lineage/references choices and exact prompt measurement. The native grammar enforces the choices during decoding; the shared host validates them again before executing a read. Baseline prompting and host validation retain their own capabilities without claiming native mask enforcement. An empty vocabulary keeps explicit discovery/unknown-ID lookup behavior available. Bound the vocabulary and fail with a narrower-context request rather than silently dropping choices. Compaction rebuilds candidates from retained visible context, not a hidden global registry.

Qualify the recorded mistyped-ID regression and a preregistered varied-ID cohort, including correct current/historical/logical references, forged IDs, candidate versus citation separation, large/truncated/history results, context measurement and cancellation. Preserve prior failed runs and actual request/output receipts. This work does not clear the independent native/reference generation mismatch or production adoption gate.


The implementation passes focused shared-host and actual native grammar checks, including the recorded bad suffix, current/historical/logical IDs, separate citation admission and exact large-schema context refusal. R2 used six identifier sets and three question wordings on both frontends. All twelve jobs returned the correct cited stock with unchanged business state and no wrong-ID calls or rejected finishes. Both final jobs nevertheless made unrelated count queries and exceeded the no-detour step limit, so that first cohort remains recorded as failed. The subsequent count-purpose clarification below passes the entire fixed R2 replay. Exact reference selection and task relevance remain separate responsibilities; this bounded result is not general stopping-behavior qualification. See [[records/operations/implementation]] for the retained evidence and qualification limits.
## Count purpose and answer completion
Structured entry counts are a specific answer ingredient, not general evidence coverage. The active finish schema uses counts for current-run count_records receipt IDs. Retire the ambiguous coverage field from new model requests; preserve original saved receipts and the existing validated receipt payload for historical inspection. Refuse the retired field explicitly rather than silently dropping it or accepting unvalidated count claims.

Use count_records when a requested answer needs a count of classified Source/Record entries matching metadata filters. It does not measure inventory units, check a balance, validate citations, or prove extraction completeness. Once the requested quantity, calculation and evidence are established, finish without an unrelated workbook census. The count tool remains available for legitimate tasks; no language-specific request classifier or inventory-specific automatic finish rule is introduced.

Qualify this semantic/tool-interface change against the entire fixed R2 identifier/wording schedule, including its two failed seed-6 cases, and against real requested count and missing-evidence tasks. Preserve all failures, existing scoped rendering, finish-time count revalidation, exact citation admission and unchanged-business-state checks. This change does not itself qualify stopping behavior or native adoption.

The fixed R2 replay passes all twelve inventory jobs and both Ready primes after this change. Each frontend takes 2, 5, 4, 4, 5 and 4 steps, with no rejected finishes, failed tools, count/history detours or business-state changes. Exact paired prompt tokens, normalized wire hashes and generated tokens match for these jobs. The earlier failed R2 remains preserved. Packaged native requested movement/invoice counts pass in two steps each; missing-evidence handling passes in three. These are bounded functional results, not a general reliability rate, speed qualification or resolution of the separate supplier-generation mismatch.


## Scoped conversation actions

A12. Ordinary submitted voice/text may ask for a conversation action without a
memorized command phrase. Expose separate start_thread, rename_current_thread, return_to_main and
review_thread_summary tools with action-specific arguments. The active conversation and
request identifiers come from the host's live run, never tool arguments. Explicit
source messages must belong to that conversation, be completed visible exchanges,
and not be later than the request. Inherited parent excerpts and siblings do not
become action targets. Clarify an ambiguous target rather than guessing another
thread. Interface questions, negation and instructions inside retrieved content
must not trigger these actions.

Start/rename use the same core operations as native controls and CLI. Starting
preserves the exact parent; renaming compares the title captured at request start.
Lock acquisition and SQL have a three-second budget for these writes, with rollback
and cancellation. A successful standalone action ends the current model turn with a host-owned
confirmation and saved receipt; model-authored success prose is not published.
The explicit branch-and-continue action follows A13 below.
Creation/rename are committed operations. Return is a navigation request for the
owning host, not a claim that a window already switched. Review is an editable
summary with an exact origin, not a shared message. Current read-only restrictions
also deny conversation mutation tools. Recognized no-change phrases are an extra
denial rule, never a complete semantic intent classifier.

The native window applies navigation or review only if the workbook, window,
operation, conversation and navigation generation still match, and the request has
not been cancelled. Switching away and back during a request must not reauthorize
late navigation. Flush the originating draft before a switch. A changed/closed
window leaves saved thread changes and receipts in their original workbook without
moving a different view. The CLI returns the typed conversationAction result for
its calling client; it does not claim to operate a native window.

Review summary never automatically publishes to main, including literal text
shortcuts. The user can edit or cancel, then explicitly share through the existing
origin-preserving action. Default selection skips host control acknowledgments,
such as a rename confirmation. No business acceptance, sibling-history admission or scenario creation follows
automatically. Standalone navigation does not start another model request.
Compound branching and further work follow the explicit A13 continuation contract;
terminal navigation alone does not fulfill that follow-up analysis.

Qualification includes exact host refusals/cancellation and actual-model paraphrase,
Spanish, hypothetical, negated, ambiguous-target and imported-instruction cases.
The fixed conversation-action cohort is functional evidence, not a speed, parity,
comprehensive language or uncoached-usability qualification. Keep failures and run
identities in [[records/operations/implementation]].

The model receives the current conversation identity/title and only the conversation
actions available in that host state. Main can start a thread, with or without explicitly requested follow-up work;
a side discussion can also rename, return or prepare review. A carried request
has no further conversation-action capability. Explicit read-only mode removes the
action tool. Both backends use the same declarations for measurement and generation;
reference annotations and compaction preserve this host metadata. These are
capability limits, not proof that a requested action was interpreted correctly.
Tool descriptions distinguish creating a new discussion, renaming the current one,
returning without sharing, and reviewing findings. When the requested target is
unavailable, clarify instead of substituting an available action. Repeating the
current title is refused as an unnecessary rename. Default branching keeps the
latest preceding exchange including its answer; selecting an earlier message
requires an explicit user selection. Late asynchronous summary lookup obeys the
same navigation-generation boundary as model results.

## Conceptual explanations and shared workbook scope

Interface guidance may finish directly with basis=general. A conceptual use of
"difference" or "differences" is not a calculation claim. Do not force a dummy
calculation or unrelated dataset lookup to explain a thread, a Source or a Record.
The numeric-comparison backstop recognizes explicit numeric-difference statements
alongside the existing cost/percentage expressions; it is a narrow language check,
not a semantic proof of all arithmetic or arbitrary prose. Existing citation,
current-request numeric, calculation-input and percentage validation still applies.
Keep financial-comparison refusal regressions while testing direct explanations.

Give the model verified product facts: one continuing main conversation, side
threads with an explicit parent excerpt and separate subsequent history, and one
shared workbook's Sources, Records, tables and spaces. Starting a thread does not
create a sandbox or inventory scenario. Draft proposals still need acceptance;
accepted business changes affect the same workbook seen from other threads.
Summary review carries a selected discussion finding back to main without moving
or duplicating underlying business records. Test these facts against the actual
shared tool layer as well as generated explanations. Conceptual explanations need
no business search, data mutation or calculation merely to satisfy validation.

The comparison backstop must not read numbered Markdown items after a conceptual
heading as a numeric difference. Numeric-difference patterns stay within one text
line. This remains deliberately bounded: it is not a complete multilingual or
spelled-number arithmetic validator. The declared answer basis is still not an
independent truth warrant.

Explicit current-request clauses such as "Explain only", "Explain without changing
anything" and "leave this workbook unchanged" join the narrow additional denial
rules. Recognize complete punctuation-delimited clauses, including semicolons;
ordinary mentions of these phrases do not grant or deny permission by substring.
Retrieved documents and history never supply this host restriction metadata.
Read-only requests may finish a conceptual explanation directly; allowed read tools
are not mandatory steps. Record unsuccessful semantic interpretations as failures
even when the response passes structural assertions.

The trusted product definitions also state that Sources may be non-documentary
inputs and Records may derive from other Records. Category, meaning and acceptance
are independent fields applying across both categories. Tool receipts do not
implicitly become business Sources. Never promise original sender identity or
an event date absent from captured input.

Simple conceptual questions should receive a few plain sentences, not an internal
execution tutorial. A calculation may contribute to a Record transformation with
its original Source/Record inputs. No extra Source is required for each calculation
receipt. Do not invent that intermediate capture step when explaining lineage.


Each conversation operation has its own model-visible function, rather than a
combined action enum. This keeps creation distinct from renaming or review at
tool selection, including when other operations are unavailable in main. The host
still owns the scoped capability set and the same internal action result. Named
tools cannot override their operation through an action argument. The earlier
conversation_action entry remains a host compatibility alias for existing clients
and receipts, but is not advertised in model schemas. Negative-case checks inspect
all named conversation operations, including the A13 continuation action, as well as the alias; they must not miss an attempted
action after a tool rename. Qualify the unchanged requests, not just new names.


### A13. Branch and continue one explicit request
Implemented in development. Normal completion and away-and-back native navigation
now pass focused checks; full interaction qualification remains open. Expose a distinct
start_thread_and_continue action for a current request that explicitly asks both
to branch and to perform further work. Pure start_thread remains terminal. The
compound action requires a verbatim span of the current request identifying its
additional task. The entire request, a paraphrase, a thread title or inferred work
from earlier history is not a substitute. Reporting an answer in the new thread
is remaining work even when reads and calculations have already completed; a
calculation receipt is not an answer delivered to the user. Respect an explicit
request to read/calculate first, then branch and report using the retained proof.
Exact-span validation proves origin,
not correct semantic interpretation; keep negative intent cases in qualification.

The host carries the exact submitted text, original request Source and visible
selection into the new thread. It never invents a second human instruction from
a model paraphrase. A child user message is explicitly marked as a carried request
with the original message, run, receipt and Source IDs, plus the quoted remaining
task and selected terminal tool. The original request and receipts remain in their
originating conversation. A single atomic, idempotent handoff records the child run
and parent acknowledgement; the parent is marked continued, not complete. Existing
request, payload and operation journals preserve this relation without migration.

Prefer branching before evidence work. Earlier read/calculation calls may precede
it within the same total budget. An earlier attempted change,
including one with an uncertain result, prevents a handoff. A failed handoff call
may be corrected only when it has no committed creation operation. Only one
handoff is allowed. Never restart already completed mutations in another phase.


At that atomic handoff, preserve a bounded set of complete read and calculate
results already shown in this same live request. Verify each completed journal
entry against its original receipt and result hash. The child request payload
records their original receipt/run IDs and exact values. Feed the model only the
original tool calls/results, without assistant prose or reasoning, and restore
citation/calculation eligibility only with those visible values. Do not execute
the calls again or manufacture duplicate tool receipts. A later independent
request must inspect its own evidence; reopening never resumes this handoff.

After the carried business-evidence pairs, show the exact completed creation call
and its actual result from the current live run. This separate progress receipt
makes the already-created thread visible after the unchanged original request.
Use an empty assistant tool-call envelope, without its prose or reasoning. Do not
execute the creation again, grant citation/calculation authority from its result,
expand available tools, or manufacture another durable receipt. Persisted original
creation and continuation records remain the authority. A later independent
request does not replay these in-memory call pairs.

Limit retained entries to eight and their serialized payload to 32,000 bytes.
Only results shown whole within the 16,000-byte tool projection bound qualify.
Check each read's current-head pointer again during the handoff transaction;
discard changed reads. If any read is failed, omitted, oversized or changed,
discard carried calculations too because calculate does not declare a versioned
input graph. Historical versions retain their explicit historical notice when
the head pointer is unchanged. Searches, history reads, paged results, counts,
balances and table snapshots are not transferred. Their evidence and current-state
checks must be obtained again if needed. This bounded carry is not new retrieval
permission, business acceptance, compaction or a general cross-thread receipt API.

The compound action inherits the latest completed exchange; explicit earlier-message
selection remains with standalone start_thread. The child receives only that
explicit inherited parent excerpt and carried request,
not unrestricted parent or sibling history. It cannot navigate or branch again.
A separate thread can hold a separate discussion or analysis of the shared
workbook data. Do not confuse conversation separation with an independent
business scenario.
Both phases share the inference lease, cancellation and twelve-response budget.
The selected work bounds its tools: answer permits only reads, calculations and
finish. A requested draft, save_space, propose_movement, propose_record,
propose_table or propose_table_edit additionally admits exactly that named tool.
The model must select work and quote task; trusted older calls that omit work
default to answer. Every write selection requires that work in the current request. A thread title does not request a same-named space
or table. Semantic selection still requires qualification; the capability mask
and host refusal enforce the selected bound on both inference backends.

Business acceptance, citation checks, deterministic arithmetic, bounded retrieval
and proposal review remain unchanged. Continuation does not create another request
Source. Failure/cancellation preserves the created thread and exact completed
receipts, without claiming the remaining task finished. Restart never replays it.

The final native result identifies the new thread and any generated view/proposal.
Apply navigation and focus only while the original window and navigation generation
still own the result. CLI clients receive the same typed result. Qualification
covers pure branching, compound calculation and evidence retrieval, one Source,
exact lineage, prior-change/repeated-handoff refusal, inherited-history isolation,
cancellation, failure, total budget, unfinished reopen and original negative cases.
Retain failed cohorts and distinguish corrected fixture ambiguity from product fixes.
### A14. References extend retrieval without granting authority

Apply [[records/specs/references-and-relationships]] to reference tools and
native generated views. Explicit mentions/backlinks and bounded indexed traversal
come first. Navigation references, possible associations, accepted business claims
and exact-version derivations remain distinct. The model must inspect resolved
original evidence before citing it; a backlink is neither proof of a business fact
nor permission to access another conversation. Substantive inferred relationships
are derived Records with evidence, meaning and status, never automatically accepted
facts. The bounded October 28 tool/read slice below has focused evidence; complete reference acceptance remains open.

## Conversation language and request metadata
Use ordinary voice/text language for interface help. Simple conceptual answers
normally take two to four short sentences, without headings, lists, a repeated
summary, internal function names, IDs or finish-basis instructions. Give an example
of what the user can say or type. Use the user's language. Explicit requests for
technical integration details, examples or a longer explanation take precedence;
brevity must not remove important distinctions or evidence limits.

Preserve the submitted user text exactly in its captured Source and in the current
user turn, apart from the separately labeled visible selection context. Put the
request Source identifier and continuation progress in structured host context.
The already visible request is not another document to retrieve. It is available
for provenance and automatically contributes to proposal/document lineage, but
cannot prove that an external document exists or contains the requested facts.
A continuation retains the same original Source and exact remaining task; it must
not repeat thread creation or substitute an earlier discussion.

Qualify these changes against both the shared agent and the actual local model.
The eleven-case interface-guidance protocol covers English and Spanish explanations,
explicit technical and detailed exceptions, acceptance boundaries, a request-only forecast proposal,
supplied arithmetic and stored quote retrieval. Its 100-word bound for the fixed
simple explanation cases is a test criterion, not a global product truncation rule.
No post-generation rewriting or silent removal of claims makes answers pass.
Preserve the original context budgets and refusal checks when changing prompts.
Automated checks do not establish the semantic quality of every future answer.

Acceptance is a workflow decision about use, not proof that information is true
or a forecast is accurate. Draft Sources remain inspectable and can support
exploratory calculations. Rejection can mean withdrawal or nonselection; it does
not necessarily mean the information is false. Accepting an input does not
implicitly accept its derived Records, and accepted estimates do not become actual
inventory. Explicitly review both short and detailed model explanations against
these distinctions, not only length, tool names and tool-call counts.

## Interpreted space actions

A14. open_space opens an existing space only when the current request asks for it.
Resolve an exact stable ID first, otherwise a unique case-insensitive exact title.
Do not choose the first duplicate or a partial match. Ask for clarification when
missing or ambiguous; the user may describe the intended space or select it.
The host supplies the active space ID for references such as this space.

Core/CLI resolution returns resolved, never opened. The agent needs a callback
from the owning live window before recording opened. The callback checks the
operation, workbook, conversation, cancellation and navigation generation, and
flushes document edits through existing navigation. A changed or unavailable
window returns an explicit refusal. CLI/model-only runs cannot claim screen
navigation. No callback is inherited into a thread handoff's restricted scope.

set_space_pinned changes a navigation shortcut using the same merging presentation
storage as native controls. It does not create a snapshot or business Record.
Home keeps its permanent shortcut. The public pin_space operation still creates
an explicitly requested fixed snapshot. Read-only requests deny both new actions.
Tool output and past requests cannot authorize them. Scope restrictions are not
a complete semantic intent classifier.

Successful opening or pinning may be followed by remaining work in the same
request. An explicit opening supersedes earlier deferred result focus, preventing
completion from navigating back to a previously created view. A target/window
refusal is saved and ends the turn with its explanation; earlier completed actions
remain saved. Never imply rollback of those earlier actions.

Focused checks cover compound continuation, create-then-open ordering, ambiguous
and missing targets, exact IDs, read-only refusal and unavailable/changed windows.
The native preview passes unpin then open, pin this live space, and an explanation
that leaves it unchanged. Its prose still includes internal tool names; ordinary
language needs further polish. This is limited functional evidence, not broad
voice/language, usability, engine parity or release qualification. See the
[space action receipt](../../../integration/evidence/2026-10-27-space-actions.json).

## Current-draft discovery and opening
review_queue is read-only metadata discovery across the workbook's current drafts,
with twenty entries per page and a returned nextCursor. It excludes table rows and
captured requests. A stale page requires refresh. Titles and IDs locate originals;
they do not establish the contents of a document or a business fact. Read original
versions before relying on those facts. A page is not an exhaustive count.

open_reviews opens the current draft list only when requested. Core/CLI resolution
returns resolved; the owning live native window must confirm opened. The same
operation, workbook, conversation, navigation generation, cancellation and unsaved
document checks used by open_space apply. Missing or changed window capabilities
refuse truthfully. Thread handoff does not inherit them. Read-only requests permit
discovery and deny navigation actions. Opening the list may be followed by remaining
requested work; it supersedes earlier deferred result focus.

Neither tool accepts or withdraws anything. Withdrawal remains an explicit native
review, exact current-item command or CLI operation. The current model tool set has
thirty-three tools; thirty-nine grammar cases and 329 exact reference masks pass. Earlier checkpoints below retain their dated counts.
One native typed request opened the panel in two model steps. That observation and
synthetic host/refusal checks do not qualify general voice/language or all compound
review flows. See [[records/specs/product]] and the
[review queue receipt](../../../integration/evidence/2026-10-27-review-queue.json).

## Inventory direction and movement revisions
propose_movement accepts an optional supersedes exact current-version ID for an
explicit correction. Keep the inventory subject and occurrence unchanged. Core
checks refuse a different subject/occurrence, stale target and duplicate exact
occurrence; the revision stays a draft. The agent may not invent a fresh occurrence
to bypass duplicate refusal. The request Source is retained with original evidence.

Positive quantity adds to our stock; negative quantity leaves it. Establish direction
relative to the user's inventory from the original evidence or current request.
A receipt, delivery or handover alone may not name sender/recipient. Ask when that
meaning is unclear before proposing an actual movement. This is the required
behavior, not a claim that the present model follows it reliably.

The October 27 J11 attempt and retained-history replay both guessed +2 for an
ambiguous handover. The replay also changed the occurrence to a resubmit variant
after refusal. Guidance in the tool description alone is insufficient. Neither
draft was accepted. This remains open material reliability work: qualify direction
clarification and event identity without conflating genuinely separate events or
silently overwriting prior interpretations. Exact-string duplicate checks alone
cannot establish that two descriptions refer to different real-world events.

The nearby explicit outgoing clarification passed: two model steps read the current
withdrawn movement and proposed -2 with its exact supersedes and unchanged occurrence.
Native review displayed Decrease: 2 brass bolts. Stock remained 20 until explicit
acceptance, then 18, and Undo restored 20. This positive result does not erase the
ambiguous failures or qualify unrestricted inventory autonomy. See the
[supplier journey receipt](../../../integration/evidence/2026-10-27-supplier-journey.json).

## Isolated inventory direction check
Before app/ask executes propose_movement, run one separate local model response
with a host-only review_movement_direction tool. The normal workbook tool set
cannot invoke this reviewer, and the reviewer cannot invoke workbook tools. It
sees the current request, the inventory subject and a bounded original Source
excerpt. Exclude previous assistant reasoning, proposed sign, derived Record
interpretations and file-title assumptions. Current explicit human clarification
may establish a direction absent from the document.

Classify incoming, outgoing or unclear and return an exact quote with its request
or evidence origin. The host verifies quote membership and compares direction
against the proposed signed quantity. An unclear, unsupported or opposite-direction
result ends this attempt with a direction question and no movement write. A valid
result may create only the existing reviewable draft. Save the exact reviewer
inputs/verdict with the tool receipt and its metrics with the run. Malformed or
cancelled responses cannot create a movement.

This is a fallible semantic check. Exact quote matching establishes origin, not
entailment or physical truth. The first isolated prompt still guessed incoming;
explicit-versus-inferred ownership guidance passed the five revised native cases
and the fresh native clarification/follow-up. The full retained-history UI replay
instead falsely described a withdrawn proposal as waiting for review without
calling propose_movement. The following citation/current-status repair addresses this observed path.
General semantic reliability and J11 remain unqualified.

The current excerpt uses at most the first eight Source chunks plus original item
text, capped at 16,000 characters. Later-page evidence selection remains work;
omitted material cannot establish a direction. Current direct CLI tools retain
mechanical checks and the harness's responsibility to inspect evidence. Both
backends share the reviewer schema; this checkpoint ran native model inference,
not a new baseline-model qualification. Individual revised review calls took
8.58–16.09 seconds on this Mac; improve latency without weakening evidence checks.

An exact duplicate_effect refusal now ends the app/ask attempt with a question
about the existing record versus a separate delivery. It cannot rename and retry
inside that same run. This is not semantic deduplication: different IDs without
an earlier refusal, new runs and independent documents still require a durable
event-identity design which also permits genuinely distinct deliveries.

Evidence: [direction review receipt](../../../integration/evidence/2026-10-27-inventory-direction-review.json).

## Exact citations and current status, October 27
Before publishing an evidence answer, observe each cited exact item version and
its current head in one read transaction. Use bounded metadata reads, without
loading document bodies. A historical version remains a valid historical citation;
never silently redirect it. When its current head has not been inspected, require
inspection before finalizing. Keep that requirement even if a retry removes the
citation or changes its answer basis to general. Existing bounded finish retries
apply; this is not another unconstrained model loop.

A historical citation receives a host-rendered version note and current-version
link. Persist the exact snapshot and workbook revision with the answer. This is
an observation at publication, not a promise of future status or semantic proof
of every sentence. Historical movement creation arguments in data do not override
item.status or currentVersion.status. No English status classifier or additional
semantic model call is introduced.

Deterministic checks refuse the stale-draft answer and citation-drop escape, then
allow a historically accurate answer with both versions. Core checks cover exact
IDs, deduplication, cancellation, no mutation and immutable history. The native
historical question read both versions and correctly said the proposal was no
longer waiting for review; the visible host note said version 2, withdrawn.
That native run voluntarily inspected the head. The exact ambiguous handover replay
instead took direction review and asked for clarification, so it does not establish
the citation gate by itself. Stock stayed 20, no business records changed, and all
original rows and assets were preserved. See [citation version receipt](../../../integration/evidence/2026-10-27-citation-current-version.json).

## Exact-copy and completion gap, October 27
The first native 75% compaction replay preserved required numeric data and lineage
but renamed exact X-CHECK identifiers to Inspection X in its draft, then claimed
the requested labels were present. The fixture is a failed job. Existing completed
write receipts establish that a draft exists, not that every requested content
constraint was satisfied. Inspect actual drafting inputs and preserve literal
identifiers when requested; do not relax the acceptance check or treat repeated
idempotent calls as evidence of no retries. Automatic compaction stays disabled.
See [[records/specs/conversation-context]] and [75% policy receipt](../../../integration/evidence/2026-10-27-context-75-policy.json.gz).

## Saved confirmations and rejected literal-review experiment, October 27
A completed_action answer for a supported document, space, shortcut or opening
uses host text derived from actual successful receipts. It confirms the saved or
opened target, not semantic fulfillment of every requested constraint. Retain the
original model finish arguments and every action receipt for inspection. Repeated
idempotent successes display once. A later success for the same tool and title suppresses its earlier failed
attempt in the final confirmation, while the failed receipt remains in history.
An unresolved failed save is explicit. Discarded model prose and citations cannot
force extra corrective generations for text which the host will never publish.
Pending historical-version inspection obligations still apply. Evidence answers
retain their existing citation, freshness, calculation and scope checks. This
boundary does not validate arbitrary claims under a different answer basis.

The repeated eight-report failure showed all eight original labels in the actual
drafting input. Their replacement by document titles was a copying error; this
trace does not establish missing source context or a threshold cause. A stronger
copy instruction alone still failed. Save confirmation now stays factual even
when the generated draft fails content acceptance. That is a narrow repair, not
successful completion of the document job.

An isolated local literal-copy reviewer was implemented and tested, then removed
from the app path after its full-job failure. It received bounded original read
prefixes and the candidate, had no write tools, and required exact request/source
quotes before refusing. An initial result attributed a real code to the wrong
input. Host resolution of origins fixed that issue and four native cases passed:
missing identifier, permitted paraphrase, already-present code and Spanish, with
an embedded source instruction. Individual observations took 5.76 to 16.77 seconds.

The full job nevertheless failed. The reviewer demanded lineage IDs in prose,
reported only a shared CHECK suffix, and then rejected an already corrected body.
The run exhausted its existing response budget without saving a draft. Original
workbook state stayed intact. These are false refusals and incomplete findings,
not a successful guard. Its full candidate source and retained traces accompany
the evidence receipt; it adds no extra model call to the shipped draft path.

Next, design a source-bound copy operation for document composition: selected
original spans/blocks should be inserted by the host with exact version and
locator identity, rather than regenerated character by character. Review how that
fits ordinary prose, requested paraphrases, source tails and earlier-conversation
values before implementation. No proposed span API or command is implemented yet.
Continue qualification against the unchanged failed job and nearby counterexamples.
Automatic compaction, native adoption and whole-app release remain gated.

Evidence: [saved-artifact and rejected-review receipt](../../../integration/evidence/2026-10-27-artifact-fidelity.json.gz), 377,349 bytes compressed; SHA-256 `83f309ea041dd4b939f6c37b16266d03a59c44e399260043440487a7770666fe`. Final native visual verification is pending manual unlock.

## Source-bound composition foundation, October 27

Adopt [[records/specs/document-composition]] after the retained exact-label
failure and rejected generative reviewer. Swift now resolves original text from
an immutable completed read receipt and atomically composes it with new prose.
Copies preserve exact UTF-8 text and Source/Record version provenance, even after
reindexing or a newer head. Drafts remain estimates, and storage does not prove
content completeness. The final deterministic core run passes 90 checks, including business-field compatibility.

This foundation is not connected to the agent draft schema, native copy choices
or CLI yet. Implement bounded selectable originals, continuation identity and
compatible typed draft parts next, then qualify the changed grammar and rerun
the unchanged eight-report job plus nearby paraphrase cases. Earlier-conversation
values and native provenance navigation remain explicit gates. The existing
truthful host confirmations remain unchanged. No new inference/checker call,
threshold increase, step-budget increase or model/engine change was made.


## Agent document-copy integration, October 27

The implementation in [[records/specs/document-composition]] now publishes bounded
original-passage choices from actual reads, supplies compatible draft parts, and
re-presents independently verified originals across checkpoints. Dynamic grammar
choices come only from host context annotations. Repeated spans are deduplicated;
summary prose grants neither copy choices nor renewed citation/action authority.
The deterministic integration and 38 actual-tool grammar/323 reference-mask checks
pass. This supersedes the earlier pending-agent status only. Actual-model fidelity,
conversation-origin copies, native provenance interaction, production compaction,
engine adoption and release remain unqualified. See [[records/operations/implementation]].


## Source-copy integration checkpoint

The unchanged eight-report maintained32K task passes at 0d62807; it used new prose
rather than source-copy IDs. A subsequent unchanged nearby replay at 770ba05
passes actual English/Spanish copy selection and permitted paraphrase delivery,
including original versions, exact Unicode/CRLF and portable integrity. Native
provenance display is implemented and programmatic document checks pass; its
visible interaction remains pending. These results do not qualify full 64K
comparison, production compaction, all generated semantics, engine adoption or
release. Evidence and exact limits: [[records/operations/implementation]] and
[[records/specs/document-composition]].


## Canonical reference discovery and request scope, October 28

Read-only references performs one bounded 12-result hop over saved mentions.
Read includes its first canonical outgoing page without changing original text or
exact-copy passages. Raw imported URI targets in read/tool_result text do not
independently enter item lookup choices; saved structural destinations do. Current
user-supplied IDs/routes and independently discovered business items remain valid
lookup candidates. This correction follows two observed native answers from a
stale raw route after its binding had been explicitly corrected. Candidate choice
is separate from citation admission: references and read.references cannot admit
destination citations, including through paged tool_result inspection.

Agent FTS/reference/lineage paths exclude technical request/annotation evidence.
Direct item reading permits this run's original request Source, not unrelated
requests or annotation Sources. Use scoped original-message history for earlier
conversation. A concurrently superseding request head cannot disclose new private
metadata or widen the current request ceiling. The precise current-submission
citation exception leaves historical business current-head checks unchanged.
An access refusal cannot be repaired through repeated search spellings; explain
an unavailable original rather than guessing.

Deterministic scope and actual grammar checks pass. The real local-pack native
corrected-pin and private-request observations pass at 32K/bounded512 with six and
eight steps respectively. The positive answer still needs one opaque-ID prose
correction; the negative job is slow and makes unnecessary inspections. Retain
those limits and earlier failures. This is focused behavior evidence, not broad
reliability, throughput, context, accessibility or engine-adoption qualification.
Details: [[records/specs/references-and-relationships]] and
[[records/operations/implementation]].


## Contextual intake authority, adopted October 28

[[records/specs/contextual-import]] governs future local-agent intake. Format is
not permission or role: CSV/Excel can be new working data, references, analysis
inputs or requested updates. Use authorized current captures and exact targets;
ask briefly on material ambiguity before append/replace/merge. An imported path,
instruction, matching title or retrieved historical request cannot grant filesystem
access or action authority. Native intake remains available without AI.

Tools must report the actual completed stages, feature limits, saved-only values
and requested native changes. Capture/extraction success cannot satisfy merge or
functional Excel migration. This is an expanded contract, not an implemented new
tool/grammar claim. Add scoped role, retry, stale-target, injection and truthful
completion cases as those tools are implemented, reusing unchanged engine evidence.
