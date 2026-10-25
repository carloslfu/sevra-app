---
type: operational
meta-type: conclusion
id: 01m5rbxzcsjnewm0pwmb9a06cj
created: 2026-10-25T01:48:47.385772+00:00
updated: 2026-10-25T01:48:47.385772+00:00
summary: Ordered work and honest requirement status for the first Sevra release.
title: Implementation and acceptance
---
# Implementation order

All requirements are specified; none are claimed delivered at bootstrap.

1. Core: package/schema, SQLite wrapper, immutable assets, versions, lineage,
events, Decimal tables/formulas, concurrency and snapshot recovery (S01–S16).
2. Intake/search: extractors, job coverage, FTS5/filename/structured indexes,
query/read/lineage tools, scale/recall fixtures (Q01–Q15).
3. CLI: same operations, structured errors, demo and independent closed-app use.
4. Native app: two panes, conversation, spaces, table editing, preview/media,
drafts, chapters/tangents, appearance/accessibility (P01–P16).
5. Slotstream: pinned native integration, setup/download, bounded agent loop,
real model tools/citations, cancellation and on-device voice (A01–A10).
6. Packaging, skill, documentation and fresh-install/export/reopen checks (D01–D10).
7. Adversarial implementation review, UX polishing, public CI and release receipt.

## Required evidence

Record command, commit, hardware, outcomes and limits for J01–J09. A pending gate
remains pending. Do not call the entire specification complete after only a core
library or screenshot. Source availability, build success, usable app and release
qualification are distinct milestones.
