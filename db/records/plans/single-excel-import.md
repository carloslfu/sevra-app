---
type: operational
meta-type: operational
id: 01m7ax1jh6ks73q16h2s9tjezk
created: 2026-11-13T16:49:52.678022+00:00
updated: 2026-11-13T18:48:10.604395+00:00
summary: Single Excel import and native workflow reconstruction
title: Single Excel import and native workflow reconstruction
---
# Single Excel import and native workflow reconstruction

Owner direction: [[sources/notes/2026/11/single-excel-import]]. Builds on [[records/specs/local-model-native-apps]] and [[records/specs/programmable-native-engine]].

## Product contract

An Excel file enters through the ordinary Add files/drop path. Sevra preserves the original and opens one native conversion workspace. The local model describes the likely business workflow and any questions; the person can clarify it and build a native workspace, use the tables directly without a model, or review an update to existing data. Reopening or retrying resumes the same conversion. A converted app uses the original imported datasets and the existing exact formula engine. Unsupported functions, embedded automation, external dependencies and incomplete inspection remain visible, never silently reclassified as reproduced behavior.

## Architecture passes

1. **Reuse authority.** Store a versioned host-owned conversion record in the current workbook history, tied to the exact immutable source. Use existing intake requests for parsing/import, existing datasets/formula plans, native app installation, sandbox checks and device approval. No new database, remote model, formula interpreter or permission system.
2. **Separate interpretation from execution.** Add bounded structural Excel inspection and a private local-model planning scope. Cell content and metadata are untrusted evidence. Save an explicit inferred plan and questions. Build with a narrow native-authoring tool scope, using only the conversion's imported bindings; keep checks and final installation in host code. Import and update never execute Excel macros or outside connections.
3. **Preserve work and report limits.** A conversion has stable identity and exact-version transitions. Cancel/retry/reopen retain committed import and draft state, cannot duplicate tables, cannot overwrite another conversion or revive stale work. Model failure leaves useful data and an actionable retry. Per-version access approval still applies. Passing synthetic checks does not establish universal Excel equivalence.
4. **Keep the UI singular.** Use one ordinary native workspace, with progressive disclosure for technical details, a short purpose/clarification field, one primary next action, direct table access and a secondary reviewed-update route. No initial reference/analysis/application mode questionnaire for Excel. Existing non-Excel intake remains coherent.

## Implementation gates

- [x] A. Durable conversion identity/state, bounded structure/features/formula inspection and stable reusable import. Record source/plan/binding/version relationships and gaps.
- [x] B. Private local-model planning plus constrained native authoring, exact imported-table bindings, shared sandbox/review gate and truthful resumable outcomes. Improve observed narrow authoring failures where needed.
- [x] C. One Add files/drop/saved-Excel entry and native conversion workspace, including no-model tables, purpose clarification, build/retry/open result and existing-table update. Reopen and navigation fencing.
- [x] D. Deterministic business cases: inventory, sales/orders, quotations, cash flow/expenses, invoices, project/time tracking and cross-sheet calculations. Verify imports, formula preservation/recalculation, original-vs-working values, bindings, edits and Undo, no duplicates, reopen and portable copy. Keep unsupported Excel behavior explicit.
- [x] E. Actual local-model analysis/build on several distinct business files; independently inspect generated behavior, failure/retry and no-model fallback. Preserve all failed attempts, not just successes.
- [x] F. Adversarial review: source prompt injection, forged conversion/approval/proofs, cross-workbook bindings, stale transitions, duplicate requests, cancellation, malformed/oversized archives and plans, missing cached formulas, external links/macros, destructive update routing and partial import. Repair actionable findings and rerun focused regressions.
- [x] G. Installed native UI: initial/working/empty/error/retry states, long names and narrow windows, labels, keyboard focus, spacing, row alignment, access approval and actual operation. Use audit/polish findings to fix and reinspect.
- [x] H. Required suite, exact packaged/installed identity, records/evidence, commit/push and current handoff. Preserve unrelated workbooks, model files, baseline app and historical proof; remove owned disposable test state after retaining receipts.

## Verification strategy

Use real workbook APIs and the signed workers; deterministic expected values come from independent business fixtures and the existing external spreadsheet-engine fixtures. Reuse existing formula, intake, native runtime and authoring checks instead of duplicating them. Add tests for the new boundaries and failure counterexamples. Run the full suite once on the integrated candidate, then focused checks for any final repairs. Test the actual installed local model and UI separately from scripted inference. Never mark a gate complete based solely on compilation or a model's claim.

## Initial findings and open decisions

- The current Add files route saves Excel as reference and sends users through a separate saved-file use dialog. That route will converge on the conversion workspace.
- Current worksheet import preserves row identities and the formula plan. Reusing those datasets avoids an additional copy and independent calculation truth.
- Existing generic authoring can repeat syntax errors or select fixed-layout tools. Conversion must supply SDK context and restrict the relevant phase to the intended tools; it cannot inherit an unconstrained chat loop and call that a reliable conversion.
- Inspection currently covers cells/formulas but does not qualify advanced Excel features. Extend structural reporting and retain gaps; do not promise macro or arbitrary Excel-function emulation.

Append implementation decisions, failures and measured outcomes below as gates advance.

## Implementation findings, November 13

The current implementation reuses a host-owned technical record and the existing intake/formula/native-app infrastructure. The native file and saved-file routes now converge, and Home can resume a conversion. The source original remains immutable; table-only use needs no model.

Focused deterministic checks pass eight business cases (inventory, invoices, timesheets, cash flow, quotes, production, bookings and project budgets), plus multiple worksheets/cross-sheet recalculation, empty files, unsupported saved formulas, feature warnings and cancellation/bounds. Cases exercise actual formula edits and Undo, exact bindings, duplicate retries, rebuilds, copied workbooks, stale capabilities, foreign reads/writes, hidden-table refusal and independent verification. Logs remain in the task's ignored build directory pending the final public receipt.

The checks exposed and repaired a nested-transaction publication failure and native Undo incorrectly restoring protected formula outputs. App and conversion publication now share one captured transaction; Undo restores edited inputs and lets the host recalculate.

Actual-model trials exposed ambiguity around dataset IDs, aliases, schemas and app versions. The conversion-specific save contract now asks the model only for source, name, per-alias write flags and tests. The host supplies the exact schema, binding and app version, and both core dispatch and final publication enforce the capability. This is a narrower schema for the existing native save tool, not another importer or app runtime.

The initial actual-model trials were stopped after retaining their failures, including schema copying, absent synthetic rows and incorrect independent-review expectations. One complete trial failed all three cases on an unsupported grammar keyword; the schema was corrected and both private grammar policies now have deterministic construction checks. The Excel-specific reviewer now receives the actual host semantics: header labels are valid UI constants, filtered row assertions count matching rows, native tables refresh automatically, and isolated fixtures do not contain Excel formula plans. Actual-model acceptance and installed UI review are still in progress; these are not claimed complete.

A release-build attempt overlapped an ongoing core edit and correctly refused changed compiler inputs. It is retained as a failed attempt; installation must use a later completed build with verified identity.

## Final acceptance, November 13

All implementation gates are complete for the bounded native preview. The broad suite passed once on the integrated candidate. Final small repairs passed 17 native and 21 authoring/conversion groups, strict Swift formatting, native release compilation and package/install/extraction checks. Actual-model Inventory, Invoices and Timesheets pass independent repeated-edit/header checks; the fresh installed UI also built and exercised Inventory through the real ProductAI route. Final installed main UUID is `B5E2EA5A-48DA-35F1-BB95-685E69B130D0`, matching the packaged product.

The [[records/reviews/single-excel-import]] contains all 14 repaired findings, final native observations and qualification boundaries. It links the public receipt and compressed failed/successful evidence. Model generation remains fallible; synthetic acceptance does not establish arbitrary Excel equivalence or production certification. Existing formula, VBA/external-refresh and new-row formula-extension limits remain explicit.

The final UI pass repaired offscreen keyboard focus, stale cancellation feedback, empty-file choices and the duplicate saved-Excel update shortcut. Focused reproductions/counterexamples and installed reinspection passed. Owned disposable test workbooks, grants and recent entries were cleaned after retaining evidence; unrelated workbooks, model files and baseline app remain intact. No VoiceOver or OS settings were changed. This checkpoint is committed and pushed directly on main with the current handoff; hosted CI is recorded separately from local acceptance.
