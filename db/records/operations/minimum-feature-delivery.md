---
type: operational
id: 01m6578ccnp83zedvmr7gpp45q
created: 2026-10-30T01:37:13.109871+00:00
updated: 2026-11-12T17:14:42.318600+00:00
summary: Ordered bounded implementation, test and polish increments for the audited Sevra feature gaps.
title: Minimum usable feature sequence
---
# Minimum usable feature sequence

## Controlling instruction

**Current state, November 12: paused.** [[sources/notes/2026/11/accessibility-review-and-pause]] selected static review and skipped accessibility testing. The later [[sources/notes/2026/11/accessibility-code-fixes-and-pause]] authorizes all ten code fixes while preserving the no-UI/no-accessibility-test boundary; those fixes are implemented and compiled. The requested review, known-limit plan and final functional results are in [[records/operations/agent-handoff]]. Earlier resume instructions below are historical; do not restart UI work or VoiceOver from them.

The owner authorizes sequential work on the gaps in
[[records/reviews/design-feature-audit]]: [[sources/notes/2026/10/minimum-feature-delivery]].
This extends the next-work order in [[records/specs/mvp-delivery]]. Earlier
infrastructure deferrals no longer prohibit these bounded follow-ups, but the
entire expanded specification does not become a prerequisite for each increment.
Finish one coherent interaction, test a nearby counterexample and polish it before
advancing. Keep at most three active blockers. Do not silently convert an untested
feature or external qualification gate into completion.

## Ordered increments

| Order | Minimum usable increment | Acceptance before moving on |
|---|---|---|
| 1 | Better evidence coverage for ordinary multi-document questions. Surface relevant original excerpts alongside an inspected source, with bounded retrieval and truthful limits. | Actual supplier CSV/PDF comparison includes available delivery/tax evidence and qualifies unknown all-in costs. Nearby missing, unrelated, partial and hostile evidence cases remain safe. |
| 2 | Readable native comparison tables and reference CSV previews. | The actual model answer and original CSV display tabular content, with selection/copy, source access, scrolling and compact presentation. Existing working-table edit semantics stay explicit. |
| 3 | Less manual reviewed updates. Suggest exact unambiguous mappings, preserve an in-progress mapping draft and support bounded saved-value XLSX updates. | Preview accurate append/merge/replace, preserve leading zeros and refuse ambiguous keys/types. Returning/reopening retains the draft; acceptance and Undo remain explicit. |
| 4 | Bounded bulk intake. | A larger fixture ingests in resumable batches within the saved-change budget; cancellation/retry produces no duplicate rows and truthful progress. Preserve transaction bounds and originals. |
| 5 | An explicit useful Excel formula subset. | Translate declared simple cell references/formulas and recalculate dependent values after edits/reopen; clearly identify saved-only and unsupported cells. Do not claim Excel parity. |
| 6 | Qualified bounded conversation continuation. | Current-model context maintenance preserves original evidence, current request and completed work through repeated continuation; failure/cancellation remains recoverable. Enable only the qualified profile. |
| 7 | Essential text/voice command parity. | Existing exact native automation preview/confirmation can be reached through submitted text or dictation with the same live authority boundaries; ambiguous language grants nothing. |
| 8 | A small reusable workflow/template and folder intake experience. | Reuse one saved job from a portable inert template; a selected folder can be reconciled under an explicit bounded policy. State foreground/background limits accurately before any helper expansion. |
| 9 | Searchable longer audio. | On-device chunked transcription preserves timestamps/provenance and supports cancellation/retry; unsupported speech availability leaves the original usable and sends nothing remotely. |
| 10 | Release qualification and static accessibility review. | Preserve completed functional keyboard/appearance/install evidence. Accessibility testing is skipped by the owner on November 12; all ten static findings now have code closures, not a runtime test pass. External use, hardware and production signing/notarization still require evidence. |

These are implementation slices, not a promise that arbitrary file formats,
workflows, devices or language cases are supported. Follow the full owning specs
for data integrity, meaning, review, current-format reconstruction and authority.

## Accepted work before the November 12 pause

Resumed by the owner after the handoff pause:
[[sources/notes/2026/10/minimum-features-resume]]. Exact checks and limits are in
[[records/operations/implementation]]; next steps are in
[[records/operations/agent-handoff]].

Increment 1 is accepted for its bounded scope. Both actual supplier cases qualify
known goods-plus-shipping costs and leave the all-in ordering open, and a narrow
finish check rejects the earlier "Total" and "Cheapest quote" wording when the same
answer says costs are unknown. Increment 2 is accepted after its installed-window
pass, which found and fixed four defects. Increment 3 is accepted: exact heading
suggestions, a saved in-progress review and saved values from one XLSX worksheet all
ran in the installed app through explicit acceptance and Undo. Every stored column must
still be mapped. Increment 4 is accepted: a 30 MB file that failed on its first batch and
a 99,999-row file now save in batches inside the saved-change limit, and Stop, a killed
process and retry repeat no rows, with progress counting committed rows only. A short row
still costs about 10 KB of workbook storage. Increment 5 is accepted: a declared Excel
subset recalculates after edits, Undo, export and reopen, 3,600 formulas calculated by
LibreOffice match it on import and after edits, and every other formula keeps its saved
value with a stated reason. It is not Excel, and no file written by Excel itself has been
tested.

The owner kept the whole queue and asked for fewer tests:
[[sources/notes/2026/10/ship-with-enough-testing]]. Each remaining increment took its smallest
reliable version, the real failure and one counterexample, with the suite and install run once on
the candidate. Increments 6 through 9 are accepted for their bounded scope, with the limits in
[[records/operations/implementation]]. Continuation is on for the native 32K profile. Increment 10
has its real-model journey, install, suite and window pass, including Add a folder, template export
and import, and Transcribe on real audio. A later 27-minute check replaced the speech engine after
the old one lost words before a pause. The keyboard pass finished apart from five menu shortcuts read
from the menu but not pressed. A whole-app review on November 1 found 32 ranked defects, all
fixed on main, and its follow-up fixed the open list. The November 2 window pass fixed a crash on
reopening a closed workbook and an empty window left by each opened file, leaving the window cases
that need an unlocked screen. VoiceOver itself, signing and the hardware matrix remain open. Next is an external
user, as [[records/specs/mvp-delivery]] requires.

## November 11 continuation

The owner resumed again in [[sources/notes/2026/11/minimum-features-completion-resume]]. The remaining
file shortcuts, transcription menu/Stop/retry, trigger-description cases, historical automation
review and paste-table lifecycle were exercised. Three observed defects were corrected. The final
automation result-link observation was interrupted by the locked screen and remains open, along
with actual VoiceOver, external use, production signing and additional hardware. The exact evidence
and final build/check status are in [[records/operations/implementation]]; the concise restart point
is [[records/operations/agent-handoff]]. Do not repeat the accepted earlier increments by default.

## November 12 completion and pause

The remaining due-time/result-link observation and its unsaved-checkbox counterexample both passed. The exact code commit also passed its full hosted check. [[records/operations/implementation]] preserves run IDs and receipts. This closes the earlier screen-lock blocker.

Accessibility testing is skipped by owner. [[records/reviews/accessibility-static-review-2026-11-12]] records ten open findings and the static review's limits. [[records/plans/known-limit-closure-2026-11-12]] gives concrete closure directions without restarting implementation. Increments 1 through 9 retain scoped acceptance; increment 10 does not become fully qualified because runtime accessibility was omitted. All product work is paused after the requested record updates, commit and push.

## November 12 code-fix checkpoint

The owner's follow-up [[sources/notes/2026/11/accessibility-code-fixes-and-pause]] is complete as code work: all A1–A10 changes are implemented, statically reviewed and compiled. Strict lint covers 40 changed Swift files. The exact scope, original findings and owner-testing suggestions are in [[records/reviews/accessibility-static-review-2026-11-12]]. No UI, accessibility test, installation, model execution or system setting was used. Runtime qualification remains unclaimed; the owner intends to test afterwards. Work is paused after the requested commit and push.
