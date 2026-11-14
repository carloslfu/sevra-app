---
type: review
id: 01m7bq0edchzvpjc6ts2nw0ny1
created: 2026-11-14T00:23:38.668417+00:00
updated: 2026-11-14T01:10:55.279161+00:00
summary: Multiple-pass boundary review, repaired defects, independent business references and explicit qualification limits; final integration in progress
title: Excel reconstruction and app-engine review
---
# Excel reconstruction and app-engine adversarial review

The engine changes and reviewed example workflows pass their bounded checks. **Unassisted local-model conversion is not consistently reliable.** The latest fresh Inventory and Loan trials stopped after repeated unsuccessful actions. Manually repaired examples are retained separately and are never counted as fresh model successes.

Authority: [[sources/notes/2026/11/excel-application-reconstruction]] and [[sources/notes/2026/11/app-engine-adversarial-review]]. Plans: [[records/plans/excel-application-reconstruction]] and [[records/plans/app-engine-adversarial-review]]. The [acceptance receipt](../../../integration/evidence/2026-11-14-excel-engine-review.json) records exact source and log hashes, installed identities and limits. The [candidate evidence](../../../integration/evidence/2026-11-14-reconstructed-model-apps/README.md) separates original model output, failed trials and reviewed derivatives.

## Review coverage

Three passes traced untrusted input to execution and storage, attacked state/permission/transaction invariants, and integrated the repaired candidate. Direct source review covered the QuickJS C bridge, SDK runtime, native wire/session/renderer/table/canvas, package access and installation, local authoring/review tools, Excel evidence/CFB/VBA readers, original comparison and publication, behavior evaluator, formula plans and data transactions, workbook mutation/SQLite/archive/assets, stored spaces, model process/wire/stream/download and product resources. CLI and the remaining business, automation, search, document, intake and persistence surfaces received the repository integration suite and targeted boundary scans. An inventory or passing suite is not a manual review of every upstream/vendor line or proof of every possible behavior.

The app remains SwiftUI/AppKit over SQLite, with separate JavaScript workers and the pinned native inference engine. No web view, hosted fallback, parallel business database or persistent execution grant was introduced. Original VBA and external connections remain inert evidence.

## Repaired findings

| Finding | Repair and verification |
|---|---|
| Translated automatic outputs could include input cells. | Outputs must equal the original formula-cell set. Actions use separately declared non-formula writes. Wrong outputs refuse publication atomically. |
| Rebuild could attach Excel coordinates to replacement rows with the same row count. | Bind ordered logical-row digests and exact alias order. Both replacement-row and alias-order counterexamples refuse. |
| Same-type controls remounted at the same native path retained old text/edit revisions; queued events could reach the replacement. | Mount identity travels through SDK, wire, renderer and event acknowledgement. Actual signed XPC/native regression passes; stale mount events are discarded. |
| Ordinary multi-worksheet transactions recalculated intermediate states. | Apply all input edits before one recalculation; normalize returned and Undo row versions. Linked-sheet updates, Undo and invalid-final-state rollback pass. |
| Corrupt export totals and revision metadata trapped the host. | Checked size accumulation/multiplication and canonical exact revision admission. Original crashes were reproduced. Overflow, negative sizes, malformed counters and the last exact revision have refusal/counterexample coverage. |
| Duplicate/deep stored layout identities reached render/edit code assuming bounded unique IDs. | Validate structure on reads and saved version bounds. Invalid layouts refuse before keyed collections; normal initial Home remains readable. |
| Removed canvas regions retained keyboard and accessibility actions. | Clear removed selection/drag state and check current accessibility-element identity. The original native regression fails before and passes after; remaining regions stay actionable. |
| Independent app review lacked the calculation evidence it was instructed to inspect. | Forward actual `calculationEvidence` alongside inert source parts. An eight-case header/formula context assertion fails before and passes after. |
| Action errors and review policy confused return-cell keys, fixture columns and fixed original writes. | Diagnostics identify the behavior function and its return object. Attachment errors distinguish missing behavior. Review preserves fixed-cell semantics and valid selection-clearing helpers. |
| Generated apps used placeholder labels and success coloring for failures. | Authoring/review guidance requires business labels and correct feedback. Reviewed derivatives have persistent labels and neutral feedback, inspected in the installed app. |
| Ordinary validation errors exposed QuickJS stack frames in forms. | Preserve the useful error message without internal frames. The exact-message regression fails before and passes after; installed UI confirms clean feedback. |
| Identical original filenames obscured calculation versus action examples. | Included examples now show comparison mode and named action arguments. Installed UI displays `Ship stock · Quantity: 2` distinctly from calculation examples. |

## Model and business behavior evidence

Forty-three checked-in synthetic workbooks cover ten business cases: inventory shipment/reorder, invoices, timesheets, cash flow, commissions, loan payments, conditional production, lookup quotes, due dates and reference codes. LibreOffice 25.8.7.3, build 30742500f2d3eb4366ac312fa33d3dcabdb3eba5, independently saved the expected results. This is not Microsoft Excel or original VBA execution qualification. VBA parsing includes a genuine licensed XlsxWriter fixture and synthetic business logic.

Earlier actual local Qwen3.6 35B generation produced Inventory, Loan and Lookup apps that passed their original finite probes. Expanded adversarial checks then found missing numeric shipment validation, a reversed zero-interest loan sign, copied lookup keys and invalid numeric results. The old Inventory app fails the independent invalid-input probe. The old Loan and Lookup apps are now refused by the added host-owned originals before publication. Failed and interrupted runs remain failures.

Fresh trials 9 and 10 are retained. Trial 9 Loan reached a saved candidate but a probe still targeted its old Input label; that harness mismatch was corrected to Principal. Its zero-interest implementation was independently wrong. In trial 10 both Inventory and Loan stopped after repeated unsuccessful actions. Some separate-model review verdicts were also mistaken. Better context and diagnostics repair concrete integration defects; they do not establish reliable autonomous generation.

Explicitly reviewed derivatives repair those observed business-logic and presentation defects. They pass 42 independent UI steps with ten saved-value assertions and 15 original-result comparisons across Inventory, Loan and Lookup. They are manually reviewed examples, not new local-model successes. Deterministic integration also exercises all ten business cases, edits/Undo/copies, linked-sheet atomic actions, malformed inputs, stale/foreign access, resource bounds and mismatch rollback.

Original comparison is host-owned: immutable file bytes, matching sheet structure, masked expected output cells, exact program/source identity and bounded examples. The model cannot supply its own expected answer as original evidence. Finite comparisons establish only the included scenarios.

## Automated verification

`bash scripts/check.sh` completed successfully on the integrated candidate: 653 core checks, all 17 native groups, six SDK tests, 36 authoring/conversion groups, local-model adapter/text/grammar checks and the CLI persistence, history, concurrency, workflow, automation and data checks. Native packaging/install/extraction checks passed. The preserved baseline packaged journey was skipped because the old baseline was not rebuilt; the native product was rebuilt.

Later reviewer-context, diagnostics and additional reference cases passed the focused 36-group authoring suite. The final validation-message regression also passes that suite. Final native release compilation, package/resource/signature checks, installation tests and packaged extraction checks pass. Strict Swift formatting, source/link checks and the db.md store are final handoff gates. Hosted CI is a separate check on the pushed commit, not retroactively claimed by local results.

## Installed native interface verification

The verified final main executable UUID is `CA63042B-C1BD-3DD5-8D37-684046FD3AB1`; the extraction helper is `66FBCFAA-0043-3806-B26D-255FA08DCC96`. Both XPC worker UUIDs are `0E54A3DC-5CEE-31E8-8AC7-17F8B237C884`. Installed UUIDs match packaged products; helper/worker signed bytes match exactly. The installer re-signs the outer app, so the main file's full signed-byte hash is separately recorded rather than falsely claimed equal.

Actual native observations include centered rows, aligned controls, permission review/enable/disable, wide and 821-point compact layouts, scrolling and field focus. Loan principal 10000 to 20000 changed payment 888.49 to 1776.98; Undo restored both and header selection cleared the editor. Inventory shipment 2 changed stock 8 to 6 and reorder 4 to 6; invalid text and overdraw left data unchanged, Undo restored 8/4, another valid shipment recovered, and reopening retained 6/6. Final validation feedback has no JavaScript stack. Lookup quantity zero produced total zero; the reviewed form has persistent Quote/SKU/Quantity labels, malformed numeric input produces `#VALUE!`, and Undo restores 3/60.

Original-example removal/addition updates the count and requires Rebuild; duplicate evidence is refused. Adding a Ship stock example with quantity 2 changes the count from three to four and marks prior comparisons stale until rebuilding. The final example list distinguishes the action and arguments from the same-named calculation file. Existing single-import loading/cancel/table-only observations are reused from [[records/reviews/single-excel-import]]; they are not claimed as new manual runs.

All task app grants were disabled. Five task-owned recent entries were removed while preserving the five other entries present at cleanup. Synthetic scratch workbooks remain local evidence under ignored build folders. The preview is installed and closed. Real workbooks, model files and the preserved baseline app were not changed. No VoiceOver or OS settings were changed.

## Remaining limits

- Unassisted generation and separate-model review remain unreliable. A person must test generated workflows; this is not a qualified automatic replacement for arbitrary Excel business applications.
- This is a source preview, not an independent security certification or production-notarized release. Additional hardware, external customer use and assistive-technology conformance remain unqualified.
- Native apps use the shipped components and scoped SDK. They have no arbitrary native/filesystem/network API; resource limits can refuse large or slow programs.
- Inspection covers bounded .xlsx/.xlsm evidence. Legacy binary/encrypted formats, unreadable embedded parts and unavailable external dependencies remain explicit gaps. Recreated programs use fixed original cell coordinates; automatic row extension and pixel-identical Excel layout are not implemented.
- The pure behavior helper has deny-default OS sandboxing plus JavaScript bounds. General file extraction has separate process/resource isolation and must not be described as using that same sandbox profile.
