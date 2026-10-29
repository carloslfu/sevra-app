---
type: spec
id: 01m62fhep3b8sz1bjdqwf4p8nf
created: 2026-10-29T00:04:15.683210+00:00
updated: 2026-10-29T03:18:54.555089+00:00
summary: Manual durable workflow contract and scoped implementation sequence; full E3 remains open.
title: Manual durable workflows
status: reviewed
---
# Manual durable workflows

This elaborates E3 in [[records/specs/native-app-engine]] and reuses
[[records/specs/application-definitions]] and [[records/specs/persistence-readiness]].
It is an implementation contract. Full E3 and EJ06-EJ08 remain open.

## First implementation boundary

Start with a bounded sequential graph of 1 to 16 named steps: evaluate an exact
function/query definition, invoke an exact registered action/form to prepare
inventory drafts, and wait for review of those exact proposals. Each action
must have one subsequent review step. No step silently accepts business data.
Conditions, bounded iteration, subworkflows, import, document composition, explicit
AI steps, automatic retries and triggers require subsequent qualified slices.
Unsupported kinds refuse rather than run arbitrary code or imply completion.

Use the shared immutable application-definition catalog with kind workflow.
Validate all argument mappings at save. A mapping supplies a typed literal,
workflow parameter or prior scalar function result with the same unit. Reject
forward references, unknown fields, cycles, mismatched units and hidden UI inputs.
The first boundary requires exact bindings throughout the definition closure;
editing definitions affects future explicitly edited workflows. Queries read the
latest data at the claimed step and retain their actual read snapshot and exact
result. They must not claim a trigger-time snapshot. Refuse incomplete query
coverage for a completed workflow computation until paged aggregation qualifies.

## Canonical storage and atomic effects

Run, step, attempt, approval and workflow outbox rows are ordinary captured tables
in the existing committed-change ledger. Store the exact workflow version, typed
inputs, exact typed step plan retained by its immutable definition version, authorizing invocation Source, actual actor and fixed
manual-drafts authority policy. Keep completed outputs and actual read revisions.
Ready-work and lease indexes bound inspection. Workflow queue updates alone must
not invalidate business/query read snapshots.

Each claim has a unique attempt ID, owner, monotonic generation for its logical
step, deadline and bounded heartbeat. Claims and result commits hold the shared
package lock only during their transaction. Never hold it for review, inference
or file copying. A worker whose deadline expired, whose claim was replaced or
whose run was cancelled cannot publish. Reclaim preserves completed steps.

Refactor registered action execution into the same trusted in-transaction body
used by ordinary action invocation. Internal drafts, exact result, step checkpoint,
operation receipt and outbox event commit together. Do not nest independent core
mutations or introduce a second effect implementation. Logical step identities
remain stable across claim attempts. Domain delivery/line uniqueness still applies
across different runs. A fault rolls back every part, permitting a safe retry.

## Review and recovery

Review refers to exact draft proposal IDs. Completion requires their direct
accepted successors with unchanged data, meaning and scenario, created through
the canonical acceptance path. A changed/rejected proposal becomes needs attention;
never accept its replacement using an old review request. An accepted forecast
retains its meaning and cannot change actual inventory. Cancellation keeps all
already committed drafts and accepted business effects, expires outstanding claims
and records unfinished work. Retry is an explicit bounded decision; no blind
external-effect retry exists in this boundary.

Manual execution requires a fresh explicit process-local session scoped to the
particular open Workbook and run. Opening, copying, importing or reconstructing
state creates no session and starts no worker. A session cannot operate a different
package/connection or copied workbook. Restart requires deliberate resume. This
is not background execution authority. E4/E5 must add device-local activation and
resource coordination before any automatic worker can claim work.

## Qualification

Test exact retry, claim competition, expiry/reclaim, late completion, cancellation,
review wait without a held lock, changed proposals, accepted estimates, duplicate
business occurrences, transaction faults and actual CLI process interruption.
Reconstruct and export a run while claimed or waiting; compare every canonical row
and preserve outputs without invoking the evaluator/action/LLM. Explicit resume
of the copied package is a new authorization. Retain failure evidence and accurate
scope. Passing this foundation does not close receiving import/AI journeys,
background operation, automation triggers, accessibility or release gates.

## Retry and review budget
A saved logical step can be claimed at most 32 times between explicit retry decisions, across processes and manual sessions, before inspection is required. Exhaustion records needs attention and an outbox event atomically. Explicit retry renews this budget for the same step and preserves its monotonically increasing fencing generation, exact inputs, previous attempts and completed outputs. Do not restart a receiving run to bypass an exhausted attempt budget: its delivery effects may already exist.

Rechecking an unchanged pending review returns its saved waiting state without consuming another worker attempt. After a proposal is accepted, a new claim validates its exact direct successor. Changed or withdrawn proposals take the ordinary failed-step path and require attention. The step's attempt_base and all claim generations participate in the same captured state and inert reconstruction.

## Current scoped implementation
Development schema 15 extends the shared catalog with workflow plus captured workflow_runs, workflow_steps, workflow_attempts, workflow_approvals and workflow_outbox. Ready-work, run-order and lease indexes avoid full-history scans during ordinary execution. Each run keeps its exact definition, normalized typed arguments, original invocation Source and actor. The same registered action body serves ordinary invocation and workflow checkpoints.

The implemented public core and CLI support manual start/read/list, a single bounded advance, claim/heartbeat/fenced finish, explicit retry/cancel and bounded event pages. An explicit process-local session belongs to one Workbook object and run. Imported/reconstructed copies retain operational history without that session. There is no automatic worker on opening a package.

Outputs retain their read revision, actual typed arguments and exact definition. Query outputs also retain the exact scoped candidate population, bounded to 5,000 versions. The whole retained step output and provenance are limited to 512 KiB. A query with a continuation refuses completion. Queue/claim updates preserve the business data read snapshot.

Final core checks pass 242 groups; focused workflow checks pass 11 groups. Independent debug/native/baseline CLI and actual SIGKILL checks pass. The broad shared suite passed before the final retry-budget refinement; final core, focused persistence, native package and isolated installation checks cover the final schema/claim change. The [manual workflow receipt](../../../integration/evidence/2026-10-28-manual-workflows.json.gz) preserves source identities, diagnostics, limits and all prior evidence hashes. Full E3 is open: agent execution beyond queued starts, import/document steps, broader typed graph features, general business outbox consumers and EJ06-EJ08 remain to qualify. E4-E6 and release gates also remain open.

## Native manual activity and continuation
The native Activity route uses bounded, newest-first saved runs with explicit state filters and coherent continuation cursors. Run inspection exposes its exact definition and start-request Sources, actor, typed inputs, stored step results, proposals, current proposal versions, attempt numbers and worker deadlines. Read/inspection creates no session and does not change saved state. Another process may still be executing a claimed step.

Continue is a deliberate process-local authorization. It executes at most the definition's16 steps and returns at review, needs-attention, cancellation or completion. It does not poll a person or automatically resume after an approval. Retry retains the failed step's fixed inputs and completed prefix. Stop retains completed drafts and accepted effects; the native confirmation explains this consequence. Review links lead to exact proposals and current successors. A later explicit continuation verifies their canonical acceptance.

An activity cursor binds workbook identity, state filter, page size and a captured workflow-run family clock. A changed run row refuses the cursor and requires refresh. Unrelated conversation, business and agent-journal writes do not invalidate pages; the response separately reports the actual workbook revision. The clock is part of the same committed-change capture and inert reconstruction, not another ledger. The native read owner cancels obsolete reads and rejects late completions; opening another workbook or closing its window invalidates effect callbacks through the existing workspace operation owner. The same inspect/activity/continue methods are exposed through CLI. Workflow-form integration is qualified below. Conversation workflow tools and explicit interpretation are qualified below; import/document steps and E4-E6 remain subsequent work.

Focused core13 groups, independent debug CLI and the native release build pass. Independent packaged CLI, native release resource/refusal/signature, strict Swift lint and CLI skill validation pass. The first release build correctly refused files edited during compilation; the stable-source rebuild passes. The Mac is locked, so visible native/VoiceOver qualification remains pending.

## Workflow forms contract
A native form can bind either a registered action or a manual workflow, with an explicit mutually exclusive action/workflow payload field. The target signature must exactly match the form. A workflow used inside a workflow action step cannot itself launch another workflow through a form. Refuse this path rather than allowing hidden recursion or authority expansion.

Reuse the window-owned form draft, exact opened bindings, unsent fields, alternatives, submission identity and existing close/flush ownership. A preview of a workflow form validates the definition and typed inputs and lists its planned steps; it does not execute a query, import a file, invoke a model or create drafts. Explain that data-dependent failures can still occur when a step runs.

Submission must atomically create the queued run, its invocation Source linked to the exact form and workflow definitions, and a reusable submission receipt in the shared capture path. Refactor the existing workflow-start body into a trusted in-transaction helper rather than nesting public mutations. Reopening the form reconciles its saved submission identity before any new submission. The receipt points to the same run even if that run has since completed. Restored/copied form/run state stays inert.

The native Start workflow action can explicitly continue the newly saved run to review under the same workbook/window ownership. A delayed completion must not redirect a different workbook or start work there. Open workflow stays available from the submitted form. New entry explicitly obtains a fresh identity and follows current target definitions. Unknown/mismatched targets, stale previews and altered arguments refuse while preserving saved input.

This scoped form integration is implemented. Core247/0, focused workflows16/0, native-session ownership checks and existing scripted agent checks pass. Debug and packaged native CLI pass six independent-process cohorts. Actual SIGKILL checks pass five boundaries, including form publication before and after COMMIT; after-commit recovery reconciles the original receipt and one queued run without execution. All114 preceding evidence files remain unchanged. The [workflow-form receipt](../../../integration/evidence/2026-10-28-workflow-forms.json.gz) retains source/build hashes and diagnostics, including the corrected optional-field test failure. Native release build, package resources/refusals/signature and strict18-file formatting checks pass. Visible keyboard, VoiceOver and full EJ06-EJ08 are not claimed while the Mac is locked.

## Conversation workflow authoring and queued starts
The conversation can author exact workflow definitions and workflow-backed forms, inspect bounded run activity and start a queued manual run. New host tools are workflow_activity, read_workflow and start_workflow. Definition discovery includes workflow, and form_template accepts a current action/workflow. Workflow metadata is untrusted executable intent, never original business evidence or permission. The same typed catalog validation rejects live closures, hidden recursion, unsupported executable steps and absent review.

start_workflow takes an exact workflow version and explicit typed inputs. Its captured current request/run is revalidated inside the atomic start mutation; the invocation Source retains the actual AI actor and request lineage. Exact retries return the original run. Read-only and unrelated request handoffs cannot queue work. A successful call terminates with a host-owned queued-run confirmation and native Activity destination. It states that no steps ran or drafts were prepared. Starting a queue entry does not authorize an automatic worker or inventory review.

This staged conversation surface does not yet execute a whole workflow on the agent's behalf. Subsequent worker integration must independently validate each action's actual plan/evidence at its execution boundary, preserve completed model results and bound authority. Do not reuse a historical run or text as permission to resume. General AI/import/document steps and full E3 journeys remain open. Retain real-model and grammar prompt gates before claiming model workflow qualification.

## Conversation workflow qualification
Core251/0 and focused workflow20/0 pass, including real prepare/complete tool-journal paging across13 saved runs, unrelated writes, reconstructed continuation and changed-run refusal. The complete final scripts/check.sh passes. Native release build, independent packaged CLI six cohorts, five actual SIGKILL boundaries, installed-resource/refusal/signature checks, strict16-file formatting and repo skill validation pass.

The actual pinned native Qwen3.6-35B-A3B/DFlash2 runner completes three synthetic jobs: author an exact one-step workflow (11 calls,88.087 s), add its form to Home without execution (12 calls,87.871 s), and queue it with truthful host confirmation (2 calls,18.913 s). Saved Home history independently retains all six previous components and adds exactly one form. Model results/metrics/history and limitations are in the [agent workflow receipt](../../../integration/evidence/2026-10-28-agent-workflows.json.gz). That model run precedes the final Activity-family-clock correction; final scripted/core/native checks qualify the correction. Its historical runner binary hash was not captured before rebuilding. Final binary hashes must not be attributed to that earlier model run.

The original expanded prompt exceeded existing compaction and grammar budgets. Compacting redundant descriptions/policy preserves structural tool fields, required sets, bounds and host checks. All60 actual-tool grammars and511 exact reference masks pass, largest8179/8192 tokens. Earlier failing8271/8192 and8223/8192 diagnostics remain retained. Do not widen budgets to hide regressions. Whole-workflow execution, AI/import/document steps, richer graphs and full E3 remain open. Mac remains locked, so no latest visible Activity/form/VoiceOver proof.

## Explicit interpretation implementation contract
Development schema16 implements reusable interpretation definitions and exact interpret workflow steps with the scoped qualification below. The canonical development schema may advance without a legacy adapter; preserve existing workbooks and recreate only selected synthetic fixtures.

An interpretation declares instruction text, explicit required item-valued evidence parameters and typed output fields. It has no tools, arbitrary paths, network, search, acceptance or other effects. Inputs are exact local business Source/Record versions. Capture the full bounded input body/data or an exact retained ready/untruncated extraction snapshot; refuse incomplete/oversize material instead of silently truncating it. Retained extraction completeness is not proof of every fact in the original file. The first bound is eight evidence items and 64 KiB of actual input material.

Prepare a durable model request under the current worker claim, then release the workbook lock before inference. Preserve exact normalized arguments, evidence versions/extraction identities, instruction, host policy/messages, schema, model identity, observed revision and budget. The model returns only structured ready/needs_input state, declared values, exact input quotations for every returned top-level field and explicit issues. Schema and quotation validation constrain shape/attribution; they do not prove semantic truth. Missing/ambiguous required data pauses for attention with empty values and explicit issues. Exact quotations may explain an unresolved declared field; a quotation does not establish its absent value. Unknown fields and fabricated quotations still refuse. Never invent missing facts through output defaults.

Retain the bounded raw model envelope as a captured operation before validation, so a rejected response remains inspectable without becoming business evidence or execution authority. Then publish validated output, its draft interpretation Record with exact lineage, step checkpoint, attempt result, operation receipt and outbox together under a fresh final lease guard. An asynchronous worker renews a bounded lease while model work proceeds; cancellation, expiry, replacement or stopped runs prevent late publication. Completed AI results are saved and reconstructed without inference. Uncommitted responses after process loss may require another attempt; do not claim exactly-once model invocation. Typed mappings may consume a named prior interpretation output field with the same signature/unit, never execute text from the output. Intermediate calculations preserve transitive interpretation lineage. Actual proposals refuse mapped estimates/plans or a different scenario, even through a scalar calculation.

The same ProductAI resource owner and installed native model serve this explicit workflow step. Deterministic-only runs still work without loading a model. Native Continue/form Start and CLI explicit continuation reuse this coordinator. Agent start_workflow remains queue-only until a separate whole-workflow authority gate qualifies. Proposals and inventory acceptance remain separate; a model step cannot approve either its interpretation or later actions. Inspectable outputs show exact evidence/model/issues. Test async lock release, fencing/heartbeat/cancel, malformed/unknown outputs, forged quotations, prompt injection, incomplete extraction, typed mappings and inert reconstruction before claiming the slice. Full import/document steps and receiving EJ06-EJ08 remain open until separately qualified.

## Explicit interpretation qualification, October 28
Schema16 core256/0 and focused workflows25/0 pass. The broad V16 scripts/check.sh passes; final raw-response equality/normalized reconstruction, lineage guard and display refinements are covered by final core/product lifecycle, native release, package and nine actual SIGKILL boundaries. No broad rerun after those final refinements is claimed. Strict27-file Swift formatting and repo skill validation pass. All116 prior evidence files remain byte-identical. The [interpretation receipt](../../../integration/evidence/2026-10-28-workflow-interpretation.json.gz) retains identities, diagnostics, actual requests/results and limits.

Actual pinned Qwen3.6-35B-A3B-4bit/DFlash2 under32K/bounded512 completes a clear count and pauses an ambiguous count with empty values and a useful exact quotation. Embedded evidence instructions cannot accept inventory. Earlier runs expose a malformed decimal and an overly strict unresolved-citation rule; failure evidence is retained. Exact attribution does not establish semantic truth. Raw rejected responses remain diagnostics, not accepted business facts.

The final packaged native CLI imports/extracts a delivery receipt, interprets count5 (8.802 s model request), maps it into a registered stock proposal and waits for review with stock20. Explicit synthetic human acceptance changes stock to25. Subsequent continuation completes using an intentionally absent model directory, and inert reconstruction preserves the completed run/balance with integrity checks passing. Input extraction is an ordinary preceding intake operation, not a workflow import step.

Native Activity exposes completed values, draft warning, model and exact quotations with source navigation. Command-Shift-Y opens it from a source preview. A fresh queued run remains inert until native Continue, then the installed model saves one draft count5. The final native build displays the ambiguous quantity issue once. The earlier actual native Continue has its own V15 binary identity; the final packaged CLI job has the final V17 identity. Full VoiceOver, appearance/narrow/media and release qualification remain open.

Asynchronous integration checks cover free workbook writes while inference waits, competing conversation refusal, cancellation, critical memory pressure, late response fencing and no duplicate inference on completed copies. Four additional real process-death barriers cover saved request, retained raw response, pre-COMMIT and post-COMMIT publication. Completed results reconstruct without inference; an uncommitted attempt may need another model call.

Interpretation definitions now have scoped conversation discovery/authoring qualification below, within unchanged grammar/prompt limits. Agent start_workflow remains queue-only. Import/document steps, richer graphs, general business outbox consumers and full EJ06-EJ08 remain open, followed by E4-E6 and release gates.

## Conversation interpretation authoring contract
Expose interpretation in the existing definition discovery/save tool schemas and registry format. Reuse the exact schema16 validator, current request actor/lineage, stable create identity and stale-base edits. Saving/discovery must not invoke a model, produce business Records, queue a run or approve anything. Standalone evaluation remains function/query only; interpretation runs only as an explicitly continued workflow step.

Document exact interpret bindings and typed field mappings in the registry. Test author/read/find/edit, missing facts/default refusal, read-only and completed-request refusal, inert reconstruction and no model loading. Keep existing structural requirements, grammar dialect and8192-token prompt ceiling. The subsequent trusted workflow_template refinement adds one tool, with its actual normalized schemas and reference masks qualified together; no context or output budget is widened. Regenerate pinned-reference fixtures and verify exact grammar masks after the schema enum change. Qualify a real native-model authoring request, preserving its exact messages/requests and identities. Do not claim actual model usability solely from scripted checks. Queueing an authored workflow still ends with the host-owned no-execution receipt. Full receiving/import/document steps remain separate.

## Conversation authoring refinement contract
Real-model conversation qualification exposed repeated invalid workflow bindings and Boolean fields. Add a trusted workflow_template discovery operation over an exact current saved function, query, interpretation or registered action/action-form. It copies the declared typed parameters, makes exact argument mappings, inserts the required review for an action, and validates the complete workflow closure without running it. A bounded optional step name preserves the requested naming. Reuse save_template with the current run's successful template receipt, re-derive its content through the same trusted builder, and retain existing retry, edit-base, read-only and request-lineage rules. Refuse workflow recursion, live dependency closures, stale target versions and foreign/completed template receipts. No inference, draft, run, approval or acceptance occurs while generating or saving a template. The scoped qualification below covers this reliability refinement, preserving grammar/prompt ceilings and measuring the changed actual tool set.

## Authoring identity and truthful failure refinement
A subsequent actual-model probe exposed a failed definition save followed by a false success answer relabeled as general. Its assertion failed and no definition, Record or run was created. The scoped qualification below covers this repair; whole-app readiness remains open. For in-app save_definition/save_template, omit expectedDefinitionID on creation; edits supply only that exact inspected version. The host derives the logical identity from the edit base or its stable create token. Remove model-supplied logicalID from this development tool contract, refusing it rather than maintaining an adapter. CLI/core explicit identities remain their separate interfaces.

Action result presentation must derive from saved success/failure receipts independently of the model's answer basis. For general, unresolved and completed-action finishes with tracked artifact actions, show host outcomes instead of unsupported success prose. A failed current-request finish also reports host outcomes. A cited business answer or successful checked current-request calculation remains validated with the explicit host outcomes appended. A failure-only completed_action finish may report the host failure without pretending a save succeeded. Retain original model arguments and receipt diagnostics. workflow_template is a read-only metadata operation; it cannot count as a completed mutation or grant write permission. Exercise basis relabeling, a cited answer with a failed save, exact-base edits, refusal of model-generated logical IDs, stale edits, and read-only template discovery.

## Conversation interpretation qualification, October 28
Schema16 conversation discovery/save now includes interpretation, with one trusted workflow_template metadata tool. New in-app saves omit the edit base; edits provide its exact inspected version. No model-generated logical identity is accepted. Saving templates/interpretations creates no business Record, run or model execution. Final core260/0, scripted agent,62 actual grammars/526 exact reference masks,14-file strict formatting, skill validation, native release and installed resource/refusal/signature checks pass. The largest bare tool prompt is8178/8192; no context/reasoning/output ceiling increased. The [conversation interpretation receipt](../../../integration/evidence/2026-10-28-conversation-interpretations.json.gz) preserves identities, exact requests/messages and119 prior artifacts byte-identically.

The final pinned native model authors Read received count, authors exactly bound Read delivery, and queues it in4/8/3 calls (59.506/79.938/35.055s). Independent saved-state checks confirm one pending run, no business Records, exact actual/actual interpretation metadata and inert reconstruction with integrity passing. The workflow job needed two corrected malformed saves. These are synthetic functional observations under development load, not throughput or general reliability qualification.

V1-V3 failures remain retained, including a V3 false success after a refused save. Host outcomes now come from receipts even when the model relabels finish basis. Failed queueing cannot become a success claim. Cited facts and checked arithmetic remain independently validated with explicit action outcomes appended. Grammar/compaction failures during development led to smaller descriptions and a narrower presentation fix, not widened budgets. The final actual-model source/runner identity was captured before inference. No new visible/VoiceOver/appearance proof is claimed. Agent starts remain queue-only; explicit native/CLI Continue executes. Import/document steps and full E3/EJ06-EJ08 remain next.
