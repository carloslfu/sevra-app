---
type: operational
meta-type: operational
id: 01m659x4nd2q89tkpzzsssd7yr
created: 2026-10-30T02:23:30.477380+00:00
updated: 2026-11-12T03:17:10.180073+00:00
summary: November 11 fixes and checks; final automation live-refresh observation, VoiceOver and external release qualification remain open.
title: Minimum-feature continuation handoff
---
# Minimum-feature continuation handoff

## Current checkpoint

The owner resumed on November 11 and requested end-to-end completion and verification:
[[sources/notes/2026/11/minimum-features-completion-resume]]. Increments 1 through 9 remain accepted
for their bounded scope. Continue directly on main; no branch or pull request. The current app is
a source test preview, not a notarized production release. Read [[records/operations/implementation]]
for the latest observed failures, fixes, checks and limits.

The November 11 pass fixed three observed defects: exact historical automation lookup, pasted
originals left unindexed after Done, and a stale Open saved run target on an automation page.
The first two have installed-window proof and nearby counterexamples. The third has its reproduced
failure, implementation, compiled candidate and automated checks; final visible verification was
interrupted by the screen locking. Do not mark that last check complete from code inspection.

The five keyboard shortcuts, Transcribe from File actions with Stop and retry, both trigger-description
cases, paste Done and subsequent table conversion, and historical version status were exercised.
The real model ran successfully. Neither memory nor a need for a different automation interface is
an outstanding blocker. Full local checks and fresh real-model regression are recorded in
[[records/operations/implementation]].

## Resume with the remaining observation

1. Unlock the Mac and bring Sevra Native Preview to the front. App-scoped control may leave it
   inactive, which correctly pauses automatic work. No global security-setting workaround is needed.
2. Use a fresh synthetic workbook or the retained local fixtures under
   `.build/acceptance-2026-11-11/`. `Window-checks.sevra` has an inert deterministic workflow returning
   6, custom/stock trigger examples and historical automation versions. `fixture-definitions.json`
   contains their exact IDs. `due-final-version.json` names the latest due-test definition. Test activations were paused
   after the lock, so explicitly enable a newly scheduled version for the remaining check.
3. Save a new calendar version due a few minutes ahead, then explicitly enable that version in the
   native page with local AI off. Leave the page open and Sevra active through its due time.
4. Check that the upcoming list advances and Open saved run opens the newly created run, not its
   predecessor. Repeat with an unsaved checkbox change: the checkbox must stay as chosen while the
   actual stored permission remains unchanged until Enable is explicitly used. Inspect the exact run
   and activation through the CLI. Pause the synthetic activation after testing.
5. VoiceOver itself requires the owner's pending approval to toggle the macOS setting and an unlocked
   screen. Restore the original setting afterward. AX labels alone do not establish spoken VoiceOver
   qualification.

Use `output/native/bin/sevra` or the installed `~/.local/bin/sevra`; a bare `sevra` may resolve an
unrelated retired CLI. Never modify a real business workbook. Recreate selected disposable fixtures
with `create` and `demo`; there are no pre-1.0 format migrations. The model, engine, Slotstream and
website repositories are unchanged by this pass.

## Remaining qualification gates

- Finish the visible live-refresh observation and approved VoiceOver check.
- Obtain an actual uncoached external user trial of the supplier journey.
- Production signing/notarization and additional supported hardware require their own evidence.
  `security find-identity -v -p codesigning` returned zero valid identities on this Mac.

These are unfinished gates, not accepted exceptions or a reason to restart the completed increments.
The ordered scope stays in [[records/operations/minimum-feature-delivery]]. Earlier handoff details
and failed iterations are preserved in Git and the dated implementation/evidence records.
