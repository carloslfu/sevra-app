---
type: spec
id: 01m62fhep3b8sz1bjdqwf4p8nf
created: 2026-10-29T00:04:15.683210+00:00
updated: 2026-10-29T00:44:07.687885+00:00
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

Final core checks pass 242 groups; focused workflow checks pass 11 groups. Independent debug/native/baseline CLI and actual SIGKILL checks pass. The broad shared suite passed before the final retry-budget refinement; final core, focused persistence, native package and isolated installation checks cover the final schema/claim change. The [manual workflow receipt](../../../integration/evidence/2026-10-28-manual-workflows.json.gz) preserves source identities, diagnostics, limits and all prior evidence hashes. Full E3 is open: native workflow forms, agent authoring/invocation, explicit model interpretation/import/document steps, broader typed graph features, general business outbox consumers and EJ06-EJ08 remain to qualify. E4-E6 and release gates also remain open.

## Native manual activity and continuation
The native Activity route uses bounded, newest-first saved runs with explicit state filters and coherent continuation cursors. Run inspection exposes its exact definition and start-request Sources, actor, typed inputs, stored step results, proposals, current proposal versions, attempt numbers and worker deadlines. Read/inspection creates no session and does not change saved state. Another process may still be executing a claimed step.

Continue is a deliberate process-local authorization. It executes at most the definition's16 steps and returns at review, needs-attention, cancellation or completion. It does not poll a person or automatically resume after an approval. Retry retains the failed step's fixed inputs and completed prefix. Stop retains completed drafts and accepted effects; the native confirmation explains this consequence. Review links lead to exact proposals and current successors. A later explicit continuation verifies their canonical acceptance.

An activity cursor binds workbook identity, state filter, page size and observed revision. A changed revision refuses the cursor and requires refresh. The native read owner cancels obsolete reads and rejects late completions; opening another workbook or closing its window invalidates effect callbacks through the existing workspace operation owner. The same inspect/activity/continue methods are exposed through CLI. Native forms that start workflows, agent workflow tools, explicit interpretation/import/document steps and E4-E6 remain subsequent work.

Focused core13 groups, independent debug CLI and the native release build pass. Independent packaged CLI, native release resource/refusal/signature, strict Swift lint and CLI skill validation pass. The first release build correctly refused files edited during compilation; the stable-source rebuild passes. The Mac is locked, so visible native/VoiceOver qualification remains pending.

## Workflow forms contract
A native form can bind either a registered action or a manual workflow, with an explicit mutually exclusive action/workflow payload field. The target signature must exactly match the form. A workflow used inside a workflow action step cannot itself launch another workflow through a form. Refuse this path rather than allowing hidden recursion or authority expansion.

Reuse the window-owned form draft, exact opened bindings, unsent fields, alternatives, submission identity and existing close/flush ownership. A preview of a workflow form validates the definition and typed inputs and lists its planned steps; it does not execute a query, import a file, invoke a model or create drafts. Explain that data-dependent failures can still occur when a step runs.

Submission must atomically create the queued run, its invocation Source linked to the exact form and workflow definitions, and a reusable submission receipt in the shared capture path. Refactor the existing workflow-start body into a trusted in-transaction helper rather than nesting public mutations. Reopening the form reconciles its saved submission identity before any new submission. The receipt points to the same run even if that run has since completed. Restored/copied form/run state stays inert.

The native Start workflow action can explicitly continue the newly saved run to review under the same workbook/window ownership. A delayed completion must not redirect a different workbook or start work there. Open workflow stays available from the submitted form. New entry explicitly obtains a fresh identity and follows current target definitions. Unknown/mismatched targets, stale previews and altered arguments refuse while preserving saved input.

This section specifies subsequent work; implementation and end-to-end qualification are not yet claimed.
