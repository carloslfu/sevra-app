---
type: operational
id: 01m7b73ynhcnygb4w4jvzqjfy8
created: 2026-11-13T19:45:56.401181+00:00
updated: 2026-11-14T01:57:19.506765+00:00
summary: Engine and native reconstruction flow verified; autonomous local-model reliability remains open
title: Excel application reconstruction
status: implemented-with-limitations
---
# Understand, recreate and compare an Excel application

Owner direction: [[sources/notes/2026/11/excel-application-reconstruction]]. Extends [[records/specs/single-excel-import]] and [[records/specs/programmable-native-engine]].

## Product contract

One import opens a reviewable understanding of the workbook. Sevra inspects the actual cells, formulas, named ranges, tables, validation/layout metadata, connections and available VBA source. The local model can read more evidence on demand and translate behavior, rather than stopping at the current formula subset. It creates native screens and a reusable pure JavaScript behavior program. Saved calculations keep working without the model. Macro-like actions run through the native host's existing scoped transaction and Undo path. Original macro code and external connections never execute implicitly.

Verification distinguishes original saved-result matches, comparisons with additional original-workbook scenarios, synthetic checks, missing evidence and mismatches. No model-provided expected result becomes original evidence. A pass always names its tested coverage; finite tests do not prove universal equivalence. Missing credentials, inaccessible dependencies, protected/unreadable sources or business ambiguity become specific questions or gaps, not blanket feature rejection. The person can add original Excel scenario files for stronger comparison without changing the working data.

## Architecture passes

1. Reuse the immutable source/intake pipeline and formula-plan history. Extend isolated extraction to .xlsm and bounded workbook evidence/VBA decoding. Never instantiate Office or execute original macros to inspect a file.
2. Add one optional behavior program to the native app package, with explicit derived-cell outputs and named action write sets. Run pure code in the existing isolated extraction helper with the existing QuickJS engine, memory/output/time bounds, no filesystem/network/time/random APIs. The desktop/core never links the JavaScript engine. Recalculation participates in existing atomic table edits and Undo. Actions retain exact app/version/table authorization and captured history.
3. Keep verification host-owned. Derive inputs/expected outputs from immutable original bytes and additional scenario bytes, mask derived output cells from evaluator inputs, reject missing/extra/incorrect outputs and persist exact source/program/case identities. Synthetic native UI checks remain separate. App publication, behavior attachment and report are one transaction, with current inputs preserved and only original formula cells recalculated.
4. Keep the experience singular. Build and compare from the existing conversion screen; show a compact verification result with expandable differences and coverage. Add an original-result example as a secondary action. Preserve original access, useful no-model tables, explicit existing-table updates, cancel/retry/reopen and native access review.

## Implementation and acceptance gates

- [x] A. Bounded deeper evidence, source locators, .xlsm routing and VBA source extraction. Hostile archive/CFB/compression inputs fail safely; unavailable source is explicit.
- [x] B. Pure behavior program and host contract, persistent recalculation, named actions, rollback and Undo; exact write scopes and resource bounds.
- [x] C. Original baseline and added-scenario comparison, host-owned reports, stale/source/program binding, mismatch refusal and clear evidence strength.
- [x] D. Local-model inspect/translate/repair/native-build integration with narrow tools. Preserve existing simple workbooks and deterministic calculation ownership.
- [x] E. Synthetic business matrix including lookup pricing, conditional totals, dates/text, cross-sheet calculations, commission, loans, inventory shipment actions, cross-sheet atomic actions and external-data/manual gaps. Independent spreadsheet-engine reference results plus adversarial wrong/constant programs, missing outputs, injection, loops, stale/foreign access and copies.
- [x] F. Actual local-model runs on several different reconstructed applications, with retained failed trials and independent behavior checks.
- [x] G. Native UI review of understanding, verification, differences, examples, errors/loading/cancel, access, real changes/Undo/reopen and wide/narrow spacing. Fix and reinspect findings.
- [x] H. Adversarial source review, full suite once on integrated candidate, focused final repairs, packaged/install identity, evidence, current records, main commit/push.

## Verification boundaries

Cached values prove only the saved state. Additional saved scenarios establish changed-input/action examples, with source identity and matching workbook structure; they are not proof of every branch. A reference spreadsheet engine can generate controlled development fixtures, but is not silently a production dependency or claimed identical to Microsoft Excel. External side effects require separate explicit integrations/authority; code translation alone cannot grant accounts or reproduce unavailable data. Every workbook gets an inspection/reconstruction attempt within documented parser/resource bounds. Binary/encrypted/unreadable parts remain identified as missing evidence, never claimed converted.

## Initial findings

The existing implementation already has stable conversion identity, isolated extraction, sandboxed native app checks, original table bindings and deterministic formula edit/Undo. Its model scope explicitly forbids JavaScript formula translation and only samples six inspection calls. VBA is detected but not read. The next change removes those design restrictions while preserving the authority boundaries. No parallel database, web view or hosted model is needed.

## Resumed verification findings, November 13

The owner resumed with “Continue and complete all the work”. Implementation and native UI authorization continue; VoiceOver and OS settings remain excluded. The earlier paused process/workbook evidence is preserved.

The focused authoring runner now passes 36 groups, including ten business cases with forty independently recalculated LibreOffice originals, input edits/Undo/copies, a real VBA parser fixture, sandbox denial/resource counterexamples, embedded binary/DTD/coordinate guards, comparison-example correction, 100-row synthetic padding and cross-sheet atomic actions. This does not claim Microsoft Excel or original VBA execution qualification.

Adversarial review found that automatic outputs could include input cells, and that rebuilding could attach coordinates to replacement rows with the same count. Outputs now equal the original formula set; imported ordered logical-row digests protect attachment. Exact alias order is enforced. Authoring policy v2 records the bounded calculation publication accurately. Tests exercise both refusals.

Live trial Inventory passed before the pause; repeated Loan failures were refused. Subsequent trials exposed ambiguous address feedback and a missing direct calculation contract in the build prompt. Exact address/formula evidence, explicit calculation guidance and key-specific diagnostics are now present. Actual-model qualification and installed visual checks remain in progress; no failed trial is counted as a success.


## Final bounded checkpoint, November 14

The full local suite and final focused checks pass; final packaging/install/extraction and installed UI verification pass. Coverage now includes 43 original files and ten business cases. The owning [[records/reviews/excel-reconstruction-and-engine-review]] records all repairs and exact evidence. F records completed actual trials, not a claim they all succeeded. The latest fresh Inventory and Loan trials failed safely; the three final sample apps are explicitly reviewed derivatives. Autonomous conversion reliability remains an open acceptance limit. G includes new examples/action inputs, stale comparisons, duplicate refusal, labels, errors, actual edits/Undo/reopen and compact spacing, plus explicitly reused unchanged single-import observations. H's local gates are complete; the containing commit and its hosted checks record publication. Do not re-label reviewed examples as fresh-model success.

## Publication verification, November 14

The implementation was committed and pushed as `34f1f00`. [Hosted Checks run 43539274889](https://github.com/carloslfu/sevra-app/actions/runs/43539274889) passed on exact commit `34f1f006ef02e883411ded6aaff33067d97c1296`, including the baseline and native packaged products. All recorded code hashes match that tested revision. This publication receipt changes only documentation/evidence; its db.md and link checks are separate from the unchanged code's full CI result. Autonomous model-generation reliability remains open.
