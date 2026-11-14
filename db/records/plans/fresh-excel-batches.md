---
type: operational
meta-type: operational
id: 01m7dz3m6wjyxx4w9nvbf6e783
created: 2026-11-14T21:23:40.380890+00:00
updated: 2026-11-14T21:40:26.676561+00:00
summary: Fresh ten-workflow local-model batches with two consecutive complete passes required; no reused apps or manual source repairs.
title: Fresh Excel conversion batches
status: in-progress
---
# Fresh Excel conversion batches

Authority: [[sources/notes/2026/11/fresh-excel-batches]]. Continues [[records/plans/automatic-excel-reliability]], whose previous accepted set combined separate fresh runs and therefore did not prove a complete fresh batch.

## Acceptance defined before the first batch

Two consecutive complete ten-workflow batches on unchanged final production code. Each batch starts with new workbooks and new local-model requests, without replayed packages, previous model conversations, reference JavaScript or manual generated-source edits. Automatic repairs within the normal bounded product flow are allowed. After any product or acceptance-check change, the consecutive-pass count restarts at zero. Preserve every failure and interrupted run.

The workflows are Inventory, Invoices, Timesheets, Cash flow, Commission, Loan, Production, Lookup quotes, Due dates and Reference codes. Retain the existing 89 independent originals, including five held-out states, plus independent UI interactions, saved edits, reopen, Undo, portable copies and Inventory invalid-state action checks. Native visual checks inspect newly generated packages rather than substituting older accepted apps.

## Work

- [ ] Run a complete fresh diagnostic batch on the current verified code.
- [ ] Diagnose and fix observed failures in generic product behavior; add focused regression checks and retain failed attempts.
- [ ] Pass two consecutive complete fresh batches on the final code without manual repairs or reused apps.
- [ ] Inspect the newly generated native interfaces and fix observed issues.
- [ ] Complete applicable code/package/CI and evidence checks, publish exact results, commit and push.

## Limits

Two batches provide bounded repeated-run evidence on these synthetic business workflows, not a universal Excel compatibility guarantee or a statistically established production success rate. Original VBA never executes. External dependencies, exact original layout and original macro execution equivalence remain outside the measured coverage.

## Progress

Starting from code 8c8d014 and documentation checkpoint 83f05e0. No new batch results are claimed yet.

## Batch 1 findings

- A launch-path error occurred before inference and is retained separately. The first actual batch uses the frozen prior production binary and fresh workbooks, with replay explicitly unset.
- Inventory failed independent initial-readiness verification: its generated Quantity input and action handler incorrectly require a selected row. Its own tests selected a row first and the separate reviewer returned ready. No generated source is repaired. A generic publication gate is being added to require successful user-triggered fixed-cell action coverage before table selection; rejected transactions and mount-time writes cannot count. Regressions and the next full fresh batch remain pending.

- The fixed-cell action coverage change compiles and passes 38 authoring/conversion groups, including refusal after table selection, refusal of validation-only or mount-time coverage, allowed picker navigation, and a mocked builder recovery that retains the compared calculation draft. Strict Swift formatting passes. This is a product regression result, not a fresh-model batch pass. The focused build/check ran alongside part of batch 1; elapsed generation times are observations, not performance claims. The batch runtime had already been copied and remains unchanged.
