---
type: operational
meta-type: conclusion
id: 01m5rbxz8vn3x44zb6n5k97y8q
created: 2026-10-25T01:48:47.259629+00:00
updated: 2026-10-29T12:45:51.261194+00:00
summary: Independent context, goals, specification, architecture and implementation order for the Sevra app.
title: Start here
---
# Sevra app

Sevra rethinks the work people do with spreadsheets: gathering messy information,
checking it, calculating, deciding, and explaining. The first audience hypothesis
is a small-business owner reconciling supplier quotes, purchases and inventory.
Mac-first is an implementation choice, not evidence that all such owners use Macs.
The success measure is a completed, explainable job with user-owned evidence.
Token throughput is useful but cannot replace correctness or useful interaction.

The product name is Sevra; Sevra Workbooks is a descriptive offer. This public
repository is `sevra-app` because the separate website business already uses
`sevra`. Workbook is Sevra's primary product and homepage; a small Websites top-navigation link
leads to the secondary service. Website pricing/support does not apply to this app.
Slotstream remains independent. The native qualification build integrates upstream
Splash C++/Metal through Swift, with no Python runtime. The prior Slotstream build
is retained as a separate baseline until native adoption gates pass. See [[records/specs/splash-integration]].

## Reading order

- [[records/specs/inventory-condition-consumers]]: schema 23 saved incremental inventory conditions, exact clocks/cursors/observations and inert candidate backpressure; causal dispatch remains next.
- [[records/specs/inventory-event-state]]: exact batch/effective-time inventory reconciliation and remaining incremental condition state.
- [[records/specs/business-events]]: schema22 committed semantic feed, indexed inert delivery, atomic batch/coverage limits and remaining condition consumers.
- [[records/specs/condition-transitions]]: inert numeric condition preview and remaining real event/cursor/causality contract.
- [[records/specs/native-automation-owner]]: current native schedule controls, device grants and active-app qualification limits.
- [[records/specs/identity]]: approved Sevra logo, app icon and native appearance.
- [[records/specs/product]]: requirements and user experience.
- [[records/specs/application-definitions]]: schema19 versioned inert automations/extraction/interpretation/functions/queries plus registered inventory/document actions and recoverable native forms have scoped automated proof. Agent authoring/invocation, focused native forms, reusable native computation and exact result publication have scoped proof; full EJ, workflows and release qualification remain open.
- [[records/specs/native-app-engine]]: adopted customizable Home/application-engine direction, shared definitions/actions/forms and manual workflow core/CLI foundations, native workflow Activity/forms and agent queued starts, explicit native AI interpretation and planned automations, code gaps and phased acceptance. E1 Home/editing foundation is implemented with scoped evidence; full journeys and E2-E6 remain open.
- [[records/specs/storage]]: package, data, transactions, history and calculations.
- [[records/specs/managed-datasets]]: adopted reserved core and managed native dataset tables over shared immutable authority/replayable history. Schema12 native storage, exact-base definitions and typed stored-scalar query/index paths have scoped proof, supporting E2 catalog work; full E0-D/MJ and Excel continuity remain open.
- [[records/specs/persistence-readiness]]: required audit and complete/replayable local persistence for future syncing; no cloud, sync protocol, replica coordination or new resolver. Schema-10 foundation, schema 12 registered projections/definitions and scoped FJ qualification are tracked in [[records/operations/persistence-coverage]]; whole-release gates remain open.
- [[records/specs/search]]: intake, extraction, indexes, retrieval and scaling.
- [[records/specs/contextual-import]]: adopted startup/ongoing entry points, role-aware CSV/data intake and Excel work continuity; current saved-value importer does not meet the expanded contract.
- [[records/specs/references-and-relationships]]: version-safe body/extracted-text bindings, backlink CLI, native link views, focused visible keyboard correction/navigation and bounded scoped agent discovery; broader usability, voice authoring and retrieval qualification pending.
- [[records/specs/document-composition]]: source-bound exact copies; bounded native fidelity and focused visible text-source provenance checks pass; broader interaction qualification pending.
- [[records/specs/intelligence]]: local model, tools, native generated UI and voice.
- [[records/specs/conversation-context]]: automatic compaction, durable history and context qualification.
- [[records/specs/distribution]]: install, CLI/skill, testing and release contracts.
- [[records/research/foundations]]: primary references and technical findings.
- [[records/reviews/design-passes]]: three explicit adversarial review passes.
- [[records/operations/implementation]]: ordered implementation and acceptance state.

All examples and test data are synthetic. No dependency on the founder's private
brain is required. The product design is adopted from the owner's conversation;
concrete engineering choices are implementer decisions, open to measured revision.

[[records/operations/build-and-run]]

## Development compatibility
Backward compatibility starts with the first notarized, production-ready 1.0
release actually distributed for production use. Until then, schema, format and
interface changes may recreate selected disposable development fixtures instead
of adding legacy migrations/adapters. Test deployments do not activate support.
Current-format integrity and history remain required. The controlling decision is
[[records/specs/distribution]] under Pre-1.0 compatibility policy.

## Manual workflow foundation
[[records/specs/manual-workflows]] defines the schema18 manual execution boundary: exact typed sequential steps, saved evaluation outputs, inventory drafts and exact review waits, transactional checkpoints/outbox, worker fencing, explicit retry/cancel and inert reconstruction. Native Activity and recoverable workflow forms have scoped automated proof. Conversation workflow authoring, workflow forms and truthful queued starts also have scoped actual-model and automated proof. Explicit native AI interpretation now has core/CLI, conversation authoring/queueing, actual-model, process-death and focused earlier visible UI proof. Included-document preparation now has core/CLI, native coordinator, process-death and actual packaged-model proof. Conversation preparation authoring/queueing now has scoped actual-model/grammar proof. Registered document actions now have shared form/CLI/workflow, exact-review, process-death and actual packaged-model receiving/report proof. Reviewed CSV/TSV intake now has exact mappings, shared table-update review, core/CLI/native coordinator/form, process-death and actual packaged-model report proof. Conversation intake authoring now has scoped exact-mapping/template/inert-queue and explicit missing-intent proof. Exact scalar catalog lookup now has scoped typed/lineage/meaning, missing-match repair/retry and actual-model receiving/report proof. Supplied clarification now has scoped core/CLI, original-versus-supplied provenance, separate review, native constrained-response, actual-model and two-boundary process-death proof. Persistent native answers now have scoped typed-editor/session/core/package proof, including incomplete/stale alternatives, conflicts, receipt recovery and failed-save lifecycle gates. Latest visible checks remain unverified. Contextual conversation answer preparation now has scoped current-message/read-receipt, typed-normalization, native-reload and actual packaged-model proof; it leaves workflows paused and inputs unsent. Local Preview my answer and Save/Confirm my answer commands now have scoped exact-preview/current-conversation, canonical confirmation provenance and automated native-session/package proof. Post-reload cancellation ownership is fixed; paused-state wording is correct in the two new model cases. Actual visible text/dictation interaction remains unverified. Full Excel continuity, richer graphs, schedulers, background execution and full accessibility qualification remain open. This does not change the repository's working-development-build status.

## Native calendar preview foundation

The first E4 slice previews exact native daily/weekly/monthly/yearly schedules with named zones, bounded coverage and first-only/shifted DST outcomes. It has13 focused groups and31 installed CLI cases plus native-package proof. No activation, new persistence, trigger dispatch or background execution. See [[records/specs/automation-schedules]]; full E4-E6 and release qualification remain open.

## Inert automation definition foundation

[[records/specs/automation-definitions]] adds exact workflow/calendar intentions to the existing immutable definition/lineage/FTS/capture family. Schema19 has326 full core groups/0,36 automation and31 calendar installed CLI cases plus final native-package proof. Saved and reconstructed definitions are inert; ordinary agent authoring remains closed. The later preparation/execution slices below add scoped authority and dispatch. Persistent device registration/native scheduling remain required. This does not complete E4 or the application.

## Durable calendar preparation foundation

The schema20 preparation checkpoint adds explicit exact-generation process-local planning permission, pause/revocation, bounded/coalesced/late occurrence decisions, source-bound monotonic catch-up and transactional outbox through the same captured ledger.343 full core groups at frozen V4,17 final focused groups and33 final installed CLI cases pass; unchanged36 definition/31 calendar cases are reused. Final native package proof passes. Copies/reconstruction do not acquire authority. No timer or workflow dispatch yet. Persistent device authorization, useful foreground execution/native controls and full E4/E5 remain required. Contract and evidence: [[records/specs/automation-planning]].

## Foreground execution foundation

Current schema21 has distinct current-process execution/AI permission, atomic occurrence-to-workflow binding, one active run, honest scheduled provenance, source-specific pause fencing and separately attributed manual control. Technical authorization history stays outside business evidence. Final359 full core groups/0,16 focused groups, synthetic model lifecycle,2 actual SIGKILL dispatch boundaries/16 calls,44 execution/33 preparation/36 definition/31 calendar installed CLI cases, strict25 Swift files, skill validation and native package/resource/refusal/signature checks pass. All136 prior receipts remain byte-identical. No fresh actual-model or visible/native release qualification. The run-once CLI installs no timer. Native scheduling/configuration, persistent device-local physical-copy authority, event/condition/background work, Excel continuity and whole-app release gates remain open. Contract and scoped evidence: [[records/specs/automation-execution]].

## Native scheduling preview

Native Activity/Schedules now provides typed create/edit/preview, explicit exact-version Enable on this Mac, pause/removal, manual Run once and saved-run inspection. A private physical-workbook registry restores permission without repeated authorization; copies/reconstructed workbooks stay inactive. A single active-app/key-window owner executes the existing bounded draft workflow path and yields to interactive work. Schema21 is unchanged. Final 17 registry/controller groups, six independent writers, two registry SIGKILL boundaries, 16 execution groups, synthetic ProductAI lifecycle, 44 installed CLI cases, strict 16-file Swift lint and native package/resource/refusal/signature checks pass. All 137 prior artifacts remain unchanged. The 359-group full core pass ran on V4; final focused checks cover subsequent same-guard naming. Native UI remains locked/unverified. Full background/closed-window/event/condition/conversation scheduling, Excel continuity, hardware/performance and release gates remain open. Details and immutable evidence: [[records/specs/native-automation-owner]].

## Condition preview and registry CI repair

The pure numeric preview now has 13 focused groups/243 truth trajectories, 31 installed CLI cases and explicit fixture-only/inert output. It does not activate real condition triggers. Nearby calendar/execution groups pass. Hosted fab2a83 failed the registry concurrency case; atomic private directory creation now passes all 18 owner groups plus five fresh starts/30 workers without repairing unsafe existing directories. The failed CI log is retained. Final native app/CLI, resource/refusal/signature and strict seven-file lint pass; the corrective source needs its own hosted run. All 139 prior artifacts remain unchanged. Schema21 is unchanged and the Mac remains locked. Real business-event outbox/cursors, condition delivery/loops/native authoring, background lifecycle, Excel continuity and release gates remain open. Full evidence: [[records/specs/condition-transitions]].

## Committed business feed checkpoint

The schema22 semantic outbox and bounded core/CLI delivery now have 386 full core groups with zero failures,14 focused groups and 76 installed native CLI calls, including six concurrent publishers and two actual SIGKILL boundaries. Nearby owner/ProductAI/automation and native packaging checks pass. All 140 prior artifacts remain unchanged. Exact proof, source scope and failed test iterations: [[records/specs/business-events]]. No condition execution is enabled. Persistent baselines/cursors, event-time state, causality/backpressure, native/conversational triggers, full background/Excel/visible/hardware/release qualification remain open. A fresh app inventory still reports the Mac locked.

## Historical inventory qualification

The exact retained-batch inventory oracle now passes 11 focused groups, a real 10,000-effect success/10,001-effect refusal, 14 feed regressions, 37 installed native CLI calls and fresh native resource/refusal/signature plus strict Swift checks. It distinguishes committed knowledge from explicit effective time, preserves earlier answers and remains read-only. Its first scale deadline failure and SQL correction are retained. All 141 prior artifacts remain unchanged. Full evidence: [[records/specs/inventory-event-state]]. Persistent condition consumers/cursors, causality/backpressure, native/conversational triggers and full release qualification remain open.

## Durable inventory conditions

Schema 23 now saves bounded incremental inventory conditions across restarts, including baseline establishment, atomic business and clock pages, exact complete observations and distinct inert candidates.416 full groups, 18 focused groups, real 10,000/10,001 projection bound, 94 condition, 76 feed and 37 historical installed calls, 18 registry/controller groups and synthetic ProductAI and native packaging pass. An ordering defect beyond 9 batches is fixed and retained. All 142 prior artifacts remain unchanged. Exact proof: [[records/specs/inventory-condition-consumers]]. Causality-aware dispatch, native/conversational authoring and full product/release qualification remain required. Latest visible checks remain locked and unverified.
