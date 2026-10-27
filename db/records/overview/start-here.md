---
type: operational
meta-type: conclusion
id: 01m5rbxz8vn3x44zb6n5k97y8q
created: 2026-10-25T01:48:47.259629+00:00
updated: 2026-10-27T21:45:28.720233+00:00
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
Slotstream remains independent. The existing build uses its public library; the
adopted direction replaces it with a Swift integration of upstream Splash C++/Metal,
with no Python runtime. See [[records/specs/splash-integration]].

## Reading order

- [[records/specs/identity]]: approved Sevra logo, app icon and native appearance.
- [[records/specs/product]]: requirements and user experience.
- [[records/specs/storage]]: package, data, transactions, history and calculations.
- [[records/specs/search]]: intake, extraction, indexes, retrieval and scaling.
- [[records/specs/references-and-relationships]]: adopted inline references, backlinks and version-safe traversal; implementation pending.
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
