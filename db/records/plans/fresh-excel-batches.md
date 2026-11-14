---
type: operational
meta-type: operational
id: 01m7dz3m6wjyxx4w9nvbf6e783
created: 2026-11-14T21:23:40.380890+00:00
updated: 2026-11-14T23:31:20.749194+00:00
summary: Two consecutive fresh 10/10 local-model Excel batches pass on frozen da3c472; all ten native interfaces checked, with no reused apps or manual source repairs.
title: Fresh Excel conversion batches
status: complete
---
# Fresh Excel conversion batches

Authority: [[sources/notes/2026/11/fresh-excel-batches]]. Continues [[records/plans/automatic-excel-reliability]], whose previous accepted set combined separate fresh runs and therefore did not prove a complete fresh batch.

## Acceptance defined before the first batch

Two consecutive complete ten-workflow batches on unchanged final production code. Each batch starts with new workbooks and new local-model requests, without replayed packages, previous model conversations, reference JavaScript or manual generated-source edits. Automatic repairs within the normal bounded product flow are allowed. After any product or acceptance-check change, the consecutive-pass count restarts at zero. Preserve every failure and interrupted run.

The workflows are Inventory, Invoices, Timesheets, Cash flow, Commission, Loan, Production, Lookup quotes, Due dates and Reference codes. Retain the existing 89 independent originals, including five held-out states, plus independent UI interactions, saved edits, reopen, Undo, portable copies and Inventory invalid-state action checks. Native visual checks inspect newly generated packages rather than substituting older accepted apps.

## Work

- [x] Run a complete fresh diagnostic batch on the current verified code.
- [x] Diagnose and fix observed failures in generic product behavior; add focused regression checks and retain failed attempts.
- [x] Pass two consecutive complete fresh batches on the final code without manual repairs or reused apps.
- [x] Inspect the newly generated native interfaces and fix observed issues.
- [x] Complete applicable code/package/CI and evidence checks, publish exact results, commit and push.

## Limits

Two batches provide bounded repeated-run evidence on these synthetic business workflows, not a universal Excel compatibility guarantee or a statistically established production success rate. Original VBA never executes. External dependencies, exact original layout and original macro execution equivalence remain outside the measured coverage.

## Progress

Complete for the owner-selected frozen checkpoint `da3c4720e05033b5aaea620ebb01abde28123d9e`. Batches 2 and 3 each pass all ten workflows from scratch. See the [acceptance receipt](../../../integration/evidence/2026-11-14-fresh-excel-batches.json) and [generated packages and retained trials](../../../integration/evidence/2026-11-14-fresh-excel-apps/README.md). Newer concurrent chat-operation changes are outside this acceptance.

## Batch 1 findings

- A launch-path error occurred before inference and is retained separately. The first actual batch uses the frozen prior production binary and fresh workbooks, with replay explicitly unset.
- Inventory failed independent initial-readiness verification: its generated Quantity input and action handler incorrectly require a selected row. Its own tests selected a row first and the separate reviewer returned ready. No generated source is repaired. A generic publication gate is being added to require successful user-triggered fixed-cell action coverage before table selection; rejected transactions and mount-time writes cannot count. Regressions and the next full fresh batch remain pending.

- The fixed-cell action coverage change compiles and passes 38 authoring/conversion groups, including refusal after table selection, refusal of validation-only or mount-time coverage, allowed picker navigation, and a mocked builder recovery that retains the compared calculation draft. Strict Swift formatting passes. This is a product regression result, not a fresh-model batch pass. The focused build/check ran alongside part of batch 1; elapsed generation times are observations, not performance claims. The batch runtime had already been copied and remains unchanged.

- Lookup quotes passed original-result comparison but failed the independent UI probe because it renamed explicitly requested SKU/Quantity labels to Selected SKU/Selected Quantity. The builder template is being corrected to avoid this prefix, and the builder/reviewer instructions now require exact requested labels. Independent probe labels are unchanged.
- Adversarial inspection of the new coverage gate found that its 24 declared-action limit exceeded the old 16-transaction test limit. The transaction bound is now 32, matching the step limit while preserving request/frame/time bounds. A 24-action synthetic integration case and the full 38-group authoring/conversion check pass. Exact-label guidance also compiles and passes those checks; fresh-model qualification remains pending.

## Batch 1 complete and batch 2 started

Batch 1 passed Invoices, Timesheets, Cash flow, Commission, Loan, Production, Due dates and Reference codes. Production, Due dates and Reference codes repaired their own failed attempts inside the normal bounded loop. Inventory and Lookup quotes remain failures. Batch 2 uses new workbooks and model requests on da3c472, with both replay and case-filter environment variables explicitly removed. No prior app or generated source is supplied. Hosted CI for superseded c5aa19b was canceled after da3c472 was pushed; the final-code gate remains required.

## Frozen verification scope after concurrent edits

The owner selected [[sources/notes/2026/11/frozen-excel-checkpoint]] rather than coordinating the active chats. The full local suite in the shared checkout stopped on compile errors in concurrently added chat-operation code. Its failed log is retained, and it is not a passing gate. The live second batch had already copied its runtime before those edits; nine workflows have passed, including automatic Due dates repair, with Reference codes running.

A separate read-only checkout at exact da3c472 now runs the full suite. The next fresh batch will use that checkout and the same copied test binary/resources, with new workbooks and requests. Newer chat-operation source is explicitly outside this acceptance; it is preserved untouched. No generated app source is repaired, and the consecutive-pass requirement remains two complete batches on this frozen code.

## First complete pass on frozen code

Batch 2 completed 10/10 from scratch in 2,730 observed seconds. The full original-result, independent UI, saved-edit/reopen/Undo and portable-copy checks pass. Inventory and Reference codes each needed several automatic repairs; no generated code was manually edited. The complete manifest matches all 392 source hashes and 95 fixture-directory file hashes in the frozen checkout. The required consecutive-pass count is one.

Batch 3 starts all ten anew with replay and filtering unset. It uses the frozen checkout and copied batch-2 engine binaries/resources, not any generated apps. The isolated full suite and native release build are running; neither is yet claimed passing. The final native visual pass will inspect the newly generated batch-2 interfaces.

## Final verification and adversarial pass

Two consecutive full batches pass on unchanged frozen code: twenty newly generated apps, 178 evaluations of the same 89 unique independent originals, 604 independent UI steps, 158 saved-edit/reopen/Undo cases and twenty portable copies. Every final UI source matches its completed local-model save; calculation/action source comes from that save or an earlier compared draft in the same request. Distinct new datasets, runtime/source/fixture/resource hashes and real model metrics are checked. No app replay, prior model conversation, workflow reference JavaScript or manual generated-source repair is used. Automatic repair is part of the normal flow, including Loan's rejected PMT drafts, Lookup quotes' missing synthetic fixtures and Due dates' initially omitted behavior.

The bounded adversarial pass checked successful-action accounting, failed/mount-time/Undo exclusions, actual Table selection versus Picker navigation, every declared action and consistent 24-action/32-transaction limits. Requested labels remain exact; independent UI checks and original expectations were not weakened. All 38 focused authoring/conversion groups pass. No additional defect was found in this bounded pass; it is not an exhaustive security proof.

The frozen full suite passed 654 core checks and native/SDK, extraction, persistence, UI/lifecycle, text, authoring, agent/grammar and performance-harness checks through desktop compilation. Its missing-model package test then encountered the model held by the live batch. That exit-1 log is retained. The native package check passed after inference ended; the remaining installer/extraction/link/db checks also pass. The earlier shared-checkout compile failure is also retained. [Exact-code hosted CI](https://github.com/carloslfu/sevra-app/actions/runs/43645166748) passes, including baseline and native packaging. Strict formatting and a fresh native release build/install pass.

All ten newly generated batch-2 apps were inspected in the native preview at wide and compact sizes. The checks exercised input labels, centered table rows, validation, real edits/recalculation, form reset, neutral feedback, Undo and exact-version enable/disable. Specific cases include zero principal, negative commission rounding, lookup-price changes, leap-day dates and accented reference codes. These are observed screenshots/accessibility states, not exported screenshot files. The installed main UUID is `F1FBB363-C04F-34D8-BDF0-67794F636F29`; helper/workers, SDK resources and signatures match the frozen package.

All UI test changes were undone, ten task recent entries removed in two batches before the list could evict unrelated entries, and task app grants disabled. The original four recent entries and preserved baseline executable remain unchanged. Workbooks, model files and synthetic evidence are retained. The preview is left on Welcome. This acceptance does not qualify the newer chat-operation work or universal Excel behavior.
