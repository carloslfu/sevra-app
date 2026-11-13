---
type: spec
id: 01m7b1b0m1hsrhhgtybew4xqqa
created: 2026-11-13T18:04:56.321049+00:00
updated: 2026-11-13T18:48:10.619023+00:00
summary: One native Excel import with reviewed local workflow inference, shared tables and constrained app generation
title: Single Excel import
status: implemented
---
# One Excel import, native working data and apps

Owner direction: [[sources/notes/2026/11/single-excel-import]]. Implementation plan: [[records/plans/single-excel-import]]. Uses [[records/specs/contextual-import]], [[records/specs/local-model-native-apps]] and [[records/specs/programmable-native-engine]].

## Customer path

Add or drop an `.xlsx` file into a workbook. The original is included/indexed through the existing intake pipeline, and one Excel workspace opens. With an installed local model, inspection starts automatically. The model describes the likely work, inputs, calculations and daily tasks; any material questions and the optional workflow field let the person correct that interpretation. The proposal is an inference, not a claim of complete reconstruction.

Choose **Build workspace** after reviewing the plan. Sevra imports working tables once, preserves supported spreadsheet calculations, and asks the local model to build native controls over those same tables. Isolated behavioral checks and a separate local-model review must pass before the app and its conversion record publish atomically. Choose **Open workspace**, review actual table access, then enable that version. A host-owned origin banner links back to import details and states the conversion limits.

**Just use the tables** needs no model. Failed or stopped planning/building preserves the original and any committed working tables. Home resumes the saved import. Retry uses the same data; rethinking/rebuilding replaces the same app identity with a newly reviewed version. New clarification invalidates the previous build even when the inferred plan text happens to be identical. Table updates remain a secondary **Update an existing table…** action with the existing target/mapping/preview/review flow. No automatic append, merge or replacement is inferred from a file name.

Saved Excel files also enter this workspace through **Use saved file**. Other formats retain their existing intake. The raw importer, formula engine and reviewed updater remain shared implementation capabilities; customers no longer choose among competing Excel import modes at the start.

## Reused architecture and authority

- A host-owned, immutable-version `excel-conversion` record ties the preserved source hash, bounded inspection, reviewed plan/clarification, stable dataset IDs, worksheet mapping, formula report and checked app version together. It uses normal captured history and portable workbooks. Generic model writes cannot forge this kind.
- Planning gets only bounded reads of this original and a structured description tool. At most six calls, 30 rows per requested range, 24 columns per range, bounded cells/formulas/notes. No write, execution, network or device authority comes from an imported cell or inferred plan.
- Building uses the existing native authoring loop with a host-created capability tied to the physical workbook, conversion version and exact imported table definitions. Only scoped table reads, SDK/source inspection, calculations and checked app publication are available. It cannot create duplicate datasets, choose foreign bindings or write business records during generation.
- The model supplies code, name, short aliases with write flags, fixtures and tests. The host fills exact dataset identities, titles, columns and app identity/version. Every imported nonempty worksheet must remain accessible through a native Table. This is one narrowed contract on the existing save tool, not another app runtime.
- Native app code runs in the existing sandboxed JavaScript worker; UI is AppKit. All business writes go through the broker and checked current row versions. Per-version enable/access review stays on the device. Copying a workbook carries the app and records, not grants.
- Existing-row editors use controlled selection, disable edits while saving, retain failed drafts and clear selection/input after success. Header selection clears the previous editable row. Repeated-save and header counterexamples are required in authoring guidance and independent model verification.
- Customer conversation messages describe the requested workspace in plain language. Full host context remains in request evidence; schema/alias instructions are not presented as something the person typed.

## Continuity and limits

Data retains Excel coordinates, including header rows. Supported formulas stay in the shared deterministic engine and recalculate on input edits, including supported cross-sheet dependencies. Native app Undo restores edited input fields and recalculates outputs; it does not overwrite formula cells. No generated JavaScript formula implementation becomes a second source of truth.

Inspection reports hidden sheets, named ranges, merged cells, validations, sheet protection, conditional formatting, Excel table definitions, charts/pivots, macros, embedded objects and outside links/connections when detected. These notes indicate work to review, not fully converted features. Original files remain available. Unsupported formulas keep saved results where available, with explicit counts; missing saved results retain existing importer diagnostics. Excel layout, protection settings, VBA, external refresh, every Excel function and automatic formula extension into newly inserted rows are not implemented. Formula worksheets therefore do not receive generated insert/delete controls by default.

Native builds are bounded to 1–12 nonempty worksheets and 64 KB of prepared context; larger imports can still be used as tables within existing parser/import bounds. Empty files preserve the original without inventing a working table. The model can fail or misunderstand a workflow; a saved app proves only its reported checks. An uncoached user and real business workbook qualification remain separate from synthetic acceptance. No universal Excel replacement or production security certification is claimed.

## Verification and manual walkthrough

The eight synthetic business cases are inventory, invoices, timesheets, cash flow, quotes, production, bookings and project budgets. Deterministic integration checks exercise real storage/formulas, source preservation, retries, app publication/rebuild, edits/Undo, portable copy, wrong bindings, stale capabilities, malformed conversion records, empty/hidden/multiple sheets and unsupported saved formulas. Actual installed local-model checks separately infer/build forms and independently exercise their native events. Final receipts and UI observations live in [[records/reviews/single-excel-import]].

To test manually: add an `.xlsx`, inspect the inferred workflow and compatibility disclosure, clarify it, build and enable the app, edit the same record twice, verify calculations and Undo, search, select the header, return to import details and open the original/table, then close/reopen and retry. Also stop analysis and choose tables, and review an existing-table update without applying it. Confirm that enabling a copied or rebuilt app requires fresh access review.
