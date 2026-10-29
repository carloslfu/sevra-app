---
type: operational
meta-type: conclusion
id: 01m5rbxz8vn3x44zb6n5k97y8q
created: 2026-10-25T01:48:47.259629+00:00
updated: 2026-10-29T03:18:54.584593+00:00
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

- [[records/specs/identity]]: approved Sevra logo, app icon and native appearance.
- [[records/specs/product]]: requirements and user experience.
- [[records/specs/application-definitions]]: schema16 versioned interpretations/functions/queries plus registered inventory actions and recoverable native receiving forms have scoped automated proof. Agent authoring/invocation, focused native forms, reusable native computation and exact result publication have scoped proof; full EJ, workflows and release qualification remain open.
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
[[records/specs/manual-workflows]] defines the schema16 manual execution boundary: exact typed sequential steps, saved evaluation outputs, inventory drafts and exact review waits, transactional checkpoints/outbox, worker fencing, explicit retry/cancel and inert reconstruction. Native Activity and recoverable workflow forms have scoped automated proof. Conversation workflow authoring, workflow forms and truthful queued starts also have scoped actual-model and automated proof. Explicit native AI interpretation now has core/CLI, conversation authoring/queueing, actual-model, process-death and focused earlier visible UI proof. Import/document workflow steps, richer graphs, schedulers, background execution and full accessibility qualification remain open. This does not change the repository's working-development-build status.
