---
type: operational
meta-type: conclusion
id: 01m5rbxz8vn3x44zb6n5k97y8q
created: 2026-10-25T01:48:47.259629+00:00
updated: 2026-10-28T16:32:39.943101+00:00
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
- [[records/specs/native-app-engine]]: adopted customizable Home/application-engine direction, proposed reusable actions/forms/workflows and automations, code gaps and phased acceptance; implementation open.
- [[records/specs/storage]]: package, data, transactions, history and calculations.
- [[records/specs/persistence-readiness]]: required audit and complete/replayable local persistence for future syncing; no cloud, sync protocol, replica coordination or new resolver. Open F01-F08/FJ01-FJ06 gates.
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
