---
type: spec
id: 01m62fhep3b8sz1bjdqwf4p8nf
created: 2026-10-29T00:04:15.683210+00:00
updated: 2026-10-29T00:33:30.356731+00:00
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

Final core checks pass 242 groups; focused workflow checks pass 11 groups. Independent debug/native/baseline CLI and actual SIGKILL checks pass. The broad shared suite passed before the final retry-budget refinement; final core, focused persistence, native package and isolated installation checks cover the final schema/claim change. The [manual workflow receipt](../../../integration/evidence/2026-10-28-manual-workflows.json.gz) preserves source identities, diagnostics, limits and all prior evidence hashes. Full E3 is open: native workflow activity/forms, agent authoring/invocation, explicit model interpretation/import/document steps, broader typed graph features, general business outbox consumers and EJ06-EJ08 remain to qualify. E4-E6 and release gates also remain open.
