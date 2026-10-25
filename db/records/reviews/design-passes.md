---
type: review
meta-type: conclusion
id: 01m5rbxzcb321z9rweagje7715
created: 2026-10-25T01:48:47.371698+00:00
updated: 2026-10-25T01:48:47.371698+00:00
summary: Three first-principles reviews resolve UX, data integrity, search coverage, installation and scope risks before implementation.
title: Design review passes
---
# Design passes

## Pass 1: user job and interaction

Reviewed the design against importing invoices, correcting stock, finding evidence
and sending the result. Problems: a chat-only UI would make browsing dependent on
inference; every result becoming a tab would create clutter; an unsaved preview
could lose generated work. Resolutions: immediate native viewers, searchable space
picker, permanent main conversation, temporary right-pane stack, autosaved drafts
and independent explicit space saving (P01–P16). Text/voice remains the principal
control but direct table interaction and native menus remain available.

Rejected a separate database setup wizard. The first window creates a workbook
and makes useful actions discoverable. Setup and indexing have honest states;
no simulated AI success while weights are missing. Native controls and keyboard
paths support a user who cannot or does not want to speak.

## Pass 2: data correctness and failure recovery

Adversarial cases: two receipts for one delivery; two identical real deliveries;
accepted forecast mistaken for actual; file copied halfway; live SQLite copied
during a write; linked original changes; model output tries arbitrary SQL. Added
separate occurrence/effect/version identities, independent meaning/acceptance,
immutable assets with stage-before-commit, coherent backup, explicit external
version handling, typed mutation tools and Decimal calculations (S01–S16).

Research surfaced the SQLite WAL reset advisory. Updated S11 from generic WAL
recommendation to serialized rollback journaling until a fixed library is verified.
This favors reproducible correctness over an unmeasured performance assumption.
Archive review adds traversal/symlink/collision/expansion defenses and schema
validation before trusting a portable workbook. No blanket repair on opening.

## Pass 3: agentic search, scale and distribution

Problems: FTS alone misses synonyms; embeddings alone miss identifiers; generic
chunking loses PDF pages; partial extraction can make absence claims misleading;
whole-corpus prompts and in-memory asset copies fail at scale. Resolutions:
lexical+filename+structured indexes, bounded iterative agent tools, exact version
locators, explicit coverage, streaming copies, paged tables and corpus benchmarks
(Q01–Q15). Embeddings are a later measured index, not required to call search agentic.

Native inference review requires matching Metal resources and a pinned complete
build rather than a local sibling package path. CLI/app use the same core and
concurrency rules. A public clone must build without a private brain. Added exact
fresh-install, offline reopen, real-model and failure-path gates (D01–D10).

## Review disposition

Specification revision 1 is ready for implementation, with measured acceptance
pending. Further passes occur after core tests, real-model evaluation and rendered
UI inspection. Failures change the implementation/spec and remain in verification
history; they must not be hidden by reducing the requirements retroactively.
