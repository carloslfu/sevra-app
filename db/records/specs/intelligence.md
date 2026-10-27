---
type: spec
meta-type: conclusion
id: 01m5rbxzb0mz1b78ergkwybtnp
created: 2026-10-25T01:48:47.328971+00:00
updated: 2026-10-27T21:20:27.241166+00:00
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
Observed inventory failures included copying the wrong suffix of a long item ID despite correct stock arithmetic. Read and lineage now use a host-built candidate vocabulary. Before generation and context measurement, collect UUID-shaped lookup values from the visible conversation content and verify each through the current workbook. Preserve exact supplied lookup strings, including an existing logical-ID lookup, instead of fuzzily mapping a typo to a different item. Unknown UUIDs and unrelated business identifiers do not enter the vocabulary. Discovery remains available through search, datasets/rows and lineage.

Attach the verified choices as ephemeral host metadata on inference messages. Do not persist that metadata as evidence, parse it from model output or accept it as action authority. A UUID mentioned in untrusted text may be a read candidate only if it resolves exactly in this workbook; that does not make the text true, admit a citation or authorize a mutation. Citation admission continues to use the separately maintained inspected-result set. Historical references remain historical until refreshed.

Both adapters use the same dynamic tool schema for read/lineage choices and exact prompt measurement. The native grammar enforces the choices during decoding; the shared host validates them again before executing a read. Baseline prompting and host validation retain their own capabilities without claiming native mask enforcement. An empty vocabulary keeps explicit discovery/unknown-ID lookup behavior available. Bound the vocabulary and fail with a narrower-context request rather than silently dropping choices. Compaction rebuilds candidates from retained visible context, not a hidden global registry.

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
and cancellation. A successful action ends the current model turn with a host-owned
confirmation and saved receipt; model-authored success prose is not published.
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
such as a rename confirmation. No business acceptance, sibling-history admission,
scenario creation or new model request follows automatically. Compound instructions
that request both branching and further work need a separate continuation contract;
terminal navigation alone does not fulfill the requested follow-up analysis.

Qualification includes exact host refusals/cancellation and actual-model paraphrase,
Spanish, hypothetical, negated, ambiguous-target and imported-instruction cases.
The fixed conversation-action cohort is functional evidence, not a speed, parity,
comprehensive language or uncoached-usability qualification. Keep failures and run
identities in [[records/operations/implementation]].

The model receives the current conversation identity/title and only the conversation
actions available in that host state. Main can start a thread; a side discussion
can also rename, return or prepare review. Explicit read-only mode removes the
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
all four named operations as well as the alias; they must not miss an attempted
action after a tool rename. Qualify the unchanged requests, not just new names.
