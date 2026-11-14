---
type: operational
id: 01m7d2cc2ahngzgpw3nakfnwsd
created: 2026-11-14T13:01:38.250838+00:00
updated: 2026-11-14T16:16:56.182341+00:00
summary: Repair local-model Excel conversion failures and verify fresh unassisted apps across business cases
title: Automatic Excel conversion reliability
status: in-progress
---
# Automatic Excel conversion reliability

Authority: [[sources/notes/2026/11/automatic-excel-reliability]]. Continues [[records/plans/excel-application-reconstruction]] and its retained failures in [[records/reviews/excel-reconstruction-and-engine-review]].

## Acceptance

Fresh local-model generation must save working native apps without manual repairs to generated source. Use actual originals and user workflow descriptions, not reference JavaScript or repaired candidates. Keep host-owned original comparisons, sandboxing, exact bindings, atomic persistence and independent UI/behavior probes. Retain failed trials and distinguish prompt/tool improvements from generation success. Finite business coverage is not universal Excel equivalence.

## Work

- [x] Trace retained Inventory and Loan failures and reproduce integration defects with focused regressions.
- [ ] Improve generic conversion contracts and recovery; do not special-case fixture names, hardcode reference solutions, weaken comparisons or manually patch generated packages.
- [ ] Extend independent fresh-generation coverage to the ten business cases, multiple difficult-case attempts and boundary inputs; repair observed product and harness defects.
- [ ] Adversarial pass, full integrated checks, final native packaging/install and actual UI inspection of fresh generated apps.
- [ ] Record exact outcomes, remaining limits, commit/push main and hosted verification.

## Initial findings

1. Loan reads c2/c3/c5 as Excel cell addresses. Missing properties become undefined/NaN, allowing misleading numeric fallbacks and repeated incorrect repairs instead of a precise invalid-address error.
2. Inventory copies row-editor selection/disable logic into a fixed-cell action and selects a header fixture as editable data. Its error exposes labels but not the preceding selected values. Earlier attempts also returned derived cells from an action whose write set only permits the input cell.
3. The general builder mixes behavior, UI, synthetic fixture coordinate systems and a long row-editor template. Measured fresh trials will determine whether tighter contracts and feedback suffice or whether phase separation is needed.

## Diagnostic iterations, November 14

Fresh generation is still in qualification; do not treat the code changes or deterministic fixtures as a completed model-reliability result.

- Trial 1 passed Inventory without editing its generated app. Loan passed original comparisons but the independent probe caught a header guard using an inferred friendly label instead of the original header.
- The first ten-case diagnostic cohort uses an earlier copied binary. It passed Invoices, Timesheets, Cash flow, Loan and Production so far. Inventory repeated an invalid Table selection binding; Commission followed incorrect reviewer feedback that removed its successful-save reset; Lookup quotes oscillated between correct and incorrect translations. All attempts are retained locally under `.build/excel-reliability`.
- Review errors were concrete: treating the test runner's numeric row index as the runtime row event, treating the string `0` as falsy, and requesting removal of a correct post-save reset. Revised Excel reviews require a runnable counterexample before giving a functional revision to the builder. Passing probes and invalid setup are sent back to the reviewer; a ready verdict remains mandatory, with at most three review calls. Generic mini-app review retains its existing gate.
- The repair context retains the original request/evidence and latest complete candidate/comparison exchanges, removes superseded failed programs and ephemeral reasoning, and preserves all durable receipts and existing step/failure limits.
- A matched comparison retains the exact calculation program inside this request; omitted save attachments reuse it and are rechecked. Failed/mismatched comparisons clear it. Explicit replacements are never overwritten.
- Original-result mismatch feedback now includes bounded input deltas for failing scenarios. This exposes changed rates and lookup reference keys without feeding any reference implementation to the model. Original output cells are excluded from these input deltas.
- Focused tests cover invalid cell reads, header/disabled-control diagnostics, draft invalidation, preserved request/plan roles, repair-context retention, false reviewer concerns, invalid reviewer setup and genuine failed assertions. The full suite is running; final fresh-generation, packaging/UI, publication and hosted verification remain open.

## Later diagnostic passes, November 14

- Cohort 1 finished 6/10: Invoices, Timesheets, Cash flow, Loan, Production and Due dates passed. Inventory, Commission, Lookup quotes and Reference codes failed. Trial 1 passed Inventory and failed Loan's actual-header selection check. These are diagnostic results, not final qualification.
- Cohort 2 was interrupted after Inventory failed and while Loan was incomplete. Its reviewer invented selected-row semantics for a fixed-cell original macro and requested an error for a valid zero principal. Cohort 3 passed Inventory and was stopped during Loan after repeated ready-verdict rejection caused by unused optional tests. Both interruptions and all receipts remain retained; incomplete cases are not passes.
- The Excel review is now limited to native UI/state behavior. Independent host comparisons continue to check calculation/action programs. Proposed and existing calculation source and inferred plans are excluded from this review; actual user intent, input headers, bound tables and declared action signatures remain. Review reasoning uses 2,048 tokens and a 4,096-token total response budget; builder reasoning is unchanged. Every review inference attempt is measured.
- Ready verdicts with an unused optional tests field record that field without running it or treating it as proof. Revisions still need a valid runnable counterexample; setup errors and passing counterexamples return to the reviewer. The host still requires a ready verdict, meaningful builder tests, original comparison, exact bindings and later user access approval.
- Successful save-stage original comparisons now also retain their exact calculation draft across failed UI/review checks. Explicit replacement source is never overwritten. Syntax diagnostics identify the calculation attachment and show its bounded ending. Regression coverage includes this recovery and invalidation after a failed explicit comparison.
- Action-only UI instructions now require writable bindings when the action writes the original, even without a row editor. Read-only binding errors identify the alias and required declaration; native Boolean-property errors identify the component, label and property instead of a generic failure. Permissions remain strict.
- Focused authoring checks pass all 36 groups. The integrated full suite passed an earlier candidate. A fresh ten-case qualification and final native packaging are running; no final reliability claim is made yet.

## Native UI and final hardening pass

- Qualification 1 completed Inventory and Loan successfully before being stopped to test the larger translation budget. Qualification 2 completed Inventory, Loan and Lookup quotes headless checks before the UI follow-up below. These copied-binary runs retain their exact runtime manifests and interruption records; any started next case is incomplete.
- Translation now also receives 2,048 reasoning tokens. Measured Loan repairs under the prior 512-token policy repeatedly inverted PMT's sign and reached the reasoning cutoff; the later fresh Loan passed in 236 seconds. The total builder output allowance remains 8,192 tokens. This is a bounded policy change, not a model/engine weight change.
- A read-through found save-stage comparison failures could retain an older program. Any new original-result comparison now clears the draft first and retains only the exact successful candidate. Regression cases cover failed explicit comparisons, failed replacement saves and later omitted attachments.
- The UI review needs action validation source as an existing service contract. Pure calculation source remains outside the UI review; action programs are supplied so it does not invent valid-input requirements conflicting with original positive-only rules. No original macro executes.
- Invalid action return objects, cell write sets and value types are distinct structural failures. Preflight propagates them even when UI code catches the error; a handled business validation error remains valid. Structural failures invalidate the retained draft. Tests cover caught invalid writes, bare-string results and refusal to reuse the broken program after a failed save.
- The first installed Inventory UI exposed an untested initial-state defect: Quantity stayed disabled until a row was selected despite the original fixed-cell action. The previous independent probe selected a row before every action and therefore missed it. Its passed flag is not acceptance of the stronger requirement. Native shipping, invalid overdraw, draft preservation, recalculation and Undo worked after selection; the app was disabled and closed after observation.
- The checker now supports explicit `expect_enabled` assertions, including inherited guards, so reviewers can reproduce an incorrectly disabled control without mistaking it for an invalid interaction. Conversion guidance supplies a separate action-only form pattern and requires a test before any row selection. The independent Inventory probe now enforces this initial readiness and preservation of rejected inputs.
- Comparison input-delta collection now reuses its output-cell set, avoiding repeated set construction for every original input cell.
- The final ten-case fresh cohort is in progress under the updated action-readiness contract. Native packaging is rebuilt after the changes. The full suite is retained in flight and will finish its model-dependent package checks after the live cohort releases the local-model lease. No check is skipped or labeled passed because of a concurrent model-busy refusal.

## Final qualification follow-up

- The fresh qualification cohort passed Loan, Lookup quotes, Commission, Reference codes, Invoices, Timesheets and Cash flow. Reference codes repaired a syntax error; Cash flow repaired missing synthetic fixtures. Inventory failed because its original-style `ShipStock` action ID was rejected by an undocumented lowercase-first restriction. Case-sensitive ASCII identifiers now accept either initial letter case, retain the 64-character bound, and consistently validate stored original examples. Invalid paths, whitespace, trailing newlines and the reserved recalculate name remain refused. A fresh Inventory retry is required.
- The grammar supports bounded string lengths but not a pattern schema keyword. An attempted pattern declaration was rejected by the existing policy normalizer; the final tool schema uses supported length constraints and precise descriptions, with exact host validation. The focused 36-group authoring check passed after this correction.
- Installed Loan UI passed zero-principal and repeated-edit calculations, original-header protection, clearing after save and Undo. The minimum-width/height layout exposed vertical scroll gestures being consumed by a short embedded table. The native table now forwards such gestures to its surrounding form while retaining horizontal/overflow scrolling, and uses row separators instead of stripes across empty space. These changes apply to all native mini apps without altering generated source.
- Native test execution now requires its completion summary in addition to a zero exit status. A diagnostic run returned early; this is retained as a failed verification attempt until its cause and regression coverage are resolved. The resumed full suite still needs to finish, followed by final installed UI, evidence and publication.

## Expanded acceptance and publication checkpoint

- Qualification 3 completed 9/10 against the original 43-workbook corpus. Inventory's old-binary PascalCase rejection is retained as its failure; Loan, Lookup quotes, Commission, Reference codes, Invoices, Timesheets, Cash flow, Production and Due dates passed without manual changes to generated packages. This is not acceptance of the later expanded boundaries.
- Adversarial inspection found untested zero-period loans, negative rounding, blank/text inputs and intentional whitespace. The reference corpus now has 72 independently recalculated XLSX/XLSM files. The original 43 files retain their exact bytes; 29 new synthetic originals add these cases. Separate independent UI steps exercise permitted blank/text/negative inputs and saved values. Model inputs never include the deterministic reference translation.
- Row-editor guidance now preserves exact cell text and avoids invented required/numeric validation; original action validation still applies. Existing workbook formulas are preferred. Translation guidance explains negative rounding, zero-period errors and unavailable Date APIs. The UI reviewer uses actual string cell semantics and the supplied fixture state, rather than assuming a selected 80-valued row should initially show zero.
- Expanded reference checks exposed two errors in the development-only reference JavaScript (negative floating-point rounding and TEXT preserving nonnumeric text), plus a test that did not write the changed loan-period input. These were corrected against independently saved originals. No generated app was repaired. All 36 authoring/conversion groups now pass with 72 originals.
- The integrated suite passed through its authoring stage after the earlier core/CLI/UI checks, then refused stale normalized tool-schema fixtures. Those fixtures and 759 independent grammar masks across 81 scenarios were regenerated with the pinned reference environment. The repaired suite tail passes grammar, performance-harness, desktop, links and db.md checks. Automatic packaged journeys were skipped as stale; explicit current native package, missing-model refusal, signature, install and extraction checks pass separately. Hosted clean CI remains required.
- The final native table pass removes viewport-wide striping/separators that resembled extra records. All 17 native groups pass. Actual installed compact-window scrolling over a short table reaches the form and returns to the records; the diagnostic grant was disabled and the preview closed. Synthetic wheel events caused an incomplete headless run, so real installed input is the scroll proof. The harness now requires a completion summary and retains failure output.
- Qualification 4 is a fresh complete ten-workflow run against all 72 originals and the stronger UI boundaries. It has no replayed or manually repaired candidate source. Final results, installed checks of those fresh apps and publication closure remain pending.

## Expanded run and installed Inventory follow-up

- Qualification 4 generated Inventory from scratch and passed its four original saved states, 20 independent UI steps, real saved edits/reopen/Undo and portable-copy verification. No row selection is needed for its Quantity form. The installed byte-verified preview also passed ship 2, reject 999 and nonnumeric text with draft preservation, Undo, centered rows, clean empty-table space and compact-window wheel scrolling to the form. Its disposable UI copy was disabled and closed.
- Inspection of the live qualification harness found its saved-edit phase did not update Loan's period input when exercising the new zero-period originals. The deterministic reference check already updates that input. The live probe now updates E2 as well; qualification 4 keeps its frozen older binary, and a fresh corrected Loan run is required. This is a test-harness correction, not a repair to generated source.
- Implementation checkpoint `af14f25df08792719717a0e579bb4958e232c053` is pushed. Hosted run 43612094593 and expanded model qualification remain in progress.

## Repair-loop and SDK follow-up

- Qualification 4 Loan matched all nine original states and passed its independent repeated-edit and blank/text UI checks, then failed at the known missing-period write in the live saved-edit harness. The run remains failed until the corrected fresh rerun.
- Invoices matched seven originals but first repeated a misplaced initial enabled assertion copied from the action-form example. The generic guide now explicitly distinguishes initially disabled row editors from initially enabled fixed-cell action inputs. Enabled-assertion diagnostics report when no table row has been selected; regression checks cover both states without removing selection guards.
- The saved Invoices app correctly produced `0.00`, but its independent UI probe expected the exact string `0`. The probe now verifies a translated output against the independent original using the existing Excel numeric comparison before using its presentation in exact UI assertions. Input text, whitespace, blanks and error strings remain exact. No generated source is changed.
- The fresh Inventory source exposed an SDK bug: unknown event-handler names were silently discarded from the native tree. Native components now reject unsupported handlers with their supported event names; valid bound onChange handling still passes. Existing qualification-4 source is retained as an older-runtime diagnostic, and affected workflows require fresh generation under the stricter runtime. SDK tests pass seven groups.
- SDK builds now set their working directory explicitly so npm and repository-root invocations produce identical generated bundles. Live runtime manifests additionally hash packaged resources and SDK source, closing the resource-identity gap in earlier manifests. Qualification 4's actual copied resources were separately hashed while its frozen bundle was still running.
- Commission passed its seven-original, repeated-edit/boundary, saved edit/reopen/Undo and portable-copy checks. Remaining cases continue on the frozen qualification-4 candidate. A full suite is running after the event-contract and repair-guidance changes.

- Numeric output equivalence now requires the entire cell string to be canonical numeric text. Regression checks retain `0.00`/`0` equivalence and reject blank/zero, leading-zero identifiers and trailing-newline text mismatches. The 36 focused authoring/conversion groups pass on this candidate.
- The byte-unchanged generated Commission and Lookup packages from qualification 4 also pass independent original/UI/persistence/portable-copy checks under the stricter current SDK in `strict-runtime-replay-1`. These are compatibility rechecks of automatically generated source, explicitly labeled replay rather than new inference trials.
