---
type: spec
id: 01m63cpj1935rn8n5qwh7bwp6j
created: 2026-10-29T08:33:51.657763+00:00
updated: 2026-10-29T08:44:37.907065+00:00
summary: Inert exact-bound calendar automation definitions over shared immutable versions, typed evidence lineage and capture. Activation and dispatch remain separate.
title: Inert automation definitions
status: implemented
---
# Inert automation definitions

This is the next E4 storage slice under [[records/specs/native-app-engine]], following [[records/specs/automation-schedules]]. Save versioned intentions before implementing activation or dispatch. A saved definition, including one imported, reconstructed or produced by an agent, grants no runtime authority.

## Shared definition contract

Add automation to the existing app_definitions kind family, keeping the same immutable Source, exact-base version/head operation, dependency/lineage, FTS catalog, committed-change capture and inert reconstruction. No parallel automation definition ledger or executable code. The canonical SQL kind constraint changes physical schema18 to19 under [[records/specs/distribution]] pre-1.0 policy. Preserve existing files; never reset user workbooks or add legacy compatibility adapters. Fresh selected synthetic fixtures qualify the new schema.

An automation content object has kind automation, a title, description, parameters [] and payload with exactly policy, workflow, arguments and schedule. Policy is calendar-drafts-v1. Workflow is an exact binding {mode:exact,versionID} to a saved workflow. Schedule is a validated native-calendar-v1 descriptor. Arguments are fixed typed workflow inputs, normalized through the shared parameter machinery; no ambient defaults, runtime expressions, inferred domain identities, files, network paths or trigger interpolation. Item inputs retain exact versions, including nested repeating-entry items. Bind the workflow as one exact definition dependency and every argument item as authoring Source lineage. Bound argument evidence to256 distinct item versions and the existing64,000-byte definition limit.

The payload has no enabled flag, catch-up permission or local path. Reject unknown fields, live/logical bindings, nonworkflow targets, incomplete or mistyped arguments, invalid schedules and nonempty automation parameters. The exact authoring Source retains original submitted content/actor. Normalized arguments appear separately in preview. Restoring an old automation creates a new definition version; saving/editing/restoring never invokes its workflow. Reject use as a function, form target, action or workflow step.

## Read-only preview and discovery

Use the existing definition-save/read/history/restore/search CLI surfaces. Definition search accepts kind automation and indexes its title/description. Add automation-preview WORKBOOK EXACT_DEFINITION_ID AFTER_ISO [COUNT] [HORIZON_DAYS], returning exact automation and workflow version IDs, normalized arguments, an explicitly inert execution status and the shared calendar preview. It changes no revision, operation, Source/Record, run, event or business effect. It requires an exact inspected version; logical heads are not accepted as stable previews. Shared source history, dependency and item links remain inspectable after newer workflow or argument versions appear.

The existing agent save tool deliberately continues refusing automation, and no new model tool, registry prose or prompt-budget growth ships in this storage slice. Native configuration and voice/text authoring need separate intent, exact-scope and activation qualification. Ordinary searches/reads may discover saved definitions but retrieved content cannot activate them.

## Three review passes

1. Storage: reuse the existing immutable definition family instead of new duplicate history. Exact-base edits, idempotent operation retries, dependency pins, canonical item lineage, FTS and complete capture must survive inert reconstruction. All historical versions validate against exact dependencies, without rebinding to current workflow/data heads.
2. Authority: a portable intention cannot grant this device background or execution rights. No enabled/control state, local registry, timer, watcher, run start or inference in these APIs. A future activation operation must separately bind a reviewed exact automation version and scope to the authorized workbook/device; importing or opening cannot create that grant. Recurring trigger identity must never stand in for a real delivery identity.
3. Adversarial integration: malformed fields/types, live/nonworkflow targets, missing/foreign item IDs, nested item lineage, stale edits, altered retry content, cancellation, mutation rollback, corrupted dependencies and copied workbooks need focused cases. A schema boundary justifies a fresh full shared core run and native-package/CLI proof. Reuse unchanged actual-model/engine evidence, clearly scoped; do not imply a new model or release qualification.

## Next execution contract

Still open: explicit enable/edit/pause/resume authority, versioned trigger state and durable occurrences/cursors, missed-run/overlap policy, one active run, bounded backlog, fenced foreground dispatch, business-event/condition triggers and native controls. Use the existing committed-change ledger and workflow checkpoints/outbox, preserving completed business effects. Device-local active authority must remain separate from portable state; reconstruction remains inert. App-quit operation, watched folders and model/resource fairness stay E5. Full E3/richer graphs and release gates remain independently open.

## Qualification

Schema19 adds automation to the existing app_definitions kind constraint, using the same immutable versions/heads, exact workflow dependency, authoring Source/actor, FTS and committed-change capture/apply. No new canonical family or parallel history. Payload policy calendar-drafts-v1 accepts exactly an exact workflow binding, fixed typed arguments and native calendar schedule, with empty definition parameters. Typed values normalize for preview while original submitted content remains unchanged. Exact item arguments, including nested entries, become Source lineage; at most256 distinct argument versions. Invalid or enabled/ambient payloads refuse atomically. No compatibility adapter or reset of existing/user files; recreate selected synthetic fixtures under the adopted pre-1.0 policy.

The shared definition save/read/search/history/restore CLI and new automation-preview expose inert intent. Preview pins exact automation/workflow versions and returns normalized arguments, inert/disabled status and bounded calendar outcomes without changing revisions, Sources/Records, operations, runs or events. Later workflow heads cannot silently retarget it. The ordinary agent can inspect metadata but save_definition explicitly still refuses automation and start_workflow refuses it as a target. It is also invalid as a function, form target or workflow step. No new model tool or prompt/grammar expansion.

Final frozen V2 passes all326 core groups/0, including8 focused automation groups and13 calendar groups, and strict10-file Swift lint. The schema boundary justified a fresh full core run. Core cases cover exact nested evidence/dependency lineage, stale edit and retry-content refusal, original versus normalized values, pinned history/restore, invalid targets, live bindings, typed-input/activation-field refusals, publication rollback, cancellation, agent boundary, corrupted dependency/lineage and inert reconstruction. Initial V1 seven groups pass; V2 adds the agent boundary. No hidden failing variant.

Final native app/CLI build passes36 independent-process automation CLI calls plus31 installed calendar calls, including version edits, no-mutation previews, exact lineage, FTS search, refused execution and inert copied history. Installed-resource checks with build reads denied,10 missing-resource and altered-resource refusals, and ad-hoc signature pass. Both installed CI products and scripts/check.sh include the new job. Exact9d0f15c previous CI is fully green; latest commits are dispatched separately. Existing inference/grammar/engine proof remains scoped to its unchanged paths and prior schema; this slice does not claim a new inference, whole crash matrix, UI or engine/performance qualification.

Evidence: [inert automation definition receipt](../../../integration/evidence/2026-10-29-automation-definitions.json.gz),52306bytes, SHA-256 b837e7b50ef0cae81fc0e246f5f963889e4fc61d37e49d7b0a11539f74e37ed7. All134 preceding evidence artifacts remain byte-identical. The latest native inventory still reports locked, so Activity/conversation/dictation/VoiceOver/narrow/appearance remain unverified. Explicit enable/edit/pause/resume and device-local authority, durable triggers/occurrences/cursors, catch-up/overlap, foreground dispatch, event/condition triggers and E5 helper/resource work remain open. Full E3/richer graphs, Excel continuity, supported hardware/performance and production distribution remain open. The app and active goal are unfinished.
