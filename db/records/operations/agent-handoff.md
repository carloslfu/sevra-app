---
type: operational
meta-type: operational
id: 01m659x4nd2q89tkpzzsssd7yr
created: 2026-10-30T02:23:30.477380+00:00
updated: 2026-11-13T04:51:08.173613+00:00
summary: Local-model native app creation and editing accepted as a source preview with isolated checks, independent review, actual UI tests and explicit generation limits.
title: Minimum-feature continuation handoff
---
# Minimum-feature continuation handoff

## Current checkpoint: local-model native authoring accepted, November 12

The owner-requested [[records/plans/local-model-native-apps]] is implemented and verified as a source preview. Ordinary local chat can create and edit native mini apps using the shipped SDK. Generated source runs in a separate sandbox check process, receives a separate local-model review, and saves only after both pass. Each source version remains disabled until the person reviews actual table access and enables it. Apps run independently of the inference model once enabled.

Seven actual-model scenarios plus an inventory edit have independent checks. Installed UI exercised chat creation, edits preserving data, per-version enable, validation, exact decimals, search, live counts, Undo, narrow layout and canvas drag/keyboard/reopen. A final fresh-thread calculator generation repaired refused attempts and passed actual 0, 7.2 and invalid-input checks. The long-conversation retry still repeated syntax errors and stopped safely; successful examples do not establish universal generation reliability. [[records/reviews/local-model-native-apps]] preserves findings, repairs and remaining limits.

The [final acceptance receipt](../../../integration/evidence/2026-11-12-local-model-native-app-final.json) records source hashes and installed identities. Main UUID `6F410451-9213-3901-AE05-925898D789BA` matches the packaged candidate; both isolated worker identities use UUID `1AFBF675-2DF8-3840-B235-BDE64AF75671` and match their exact packaged bytes. Native resource/signature, installation and extraction checks pass. The broad functional suite passed through desktop compilation; a model-busy packaging interruption was closed by rerunning that tail with inference idle. Final local fixes passed all 10 authoring groups and the full agent/grammar suite. Hosted CI for this source is not yet claimed.

The synthetic workbook is left open on Price check with invalid-input feedback visible. Existing workbooks and the old baseline app were not modified. No VoiceOver or system settings were used. External user testing, security assessment, additional hardware and production signing/notarization remain open. The accepted native-engine checkpoint below is historical and does not supersede this authoring evidence.

## Earlier checkpoint: native app engine accepted, November 12

The owner-authorized [[records/plans/programmable-native-engine]] is complete through
P7 for the bounded SDK 1. The contract and manual walkthrough are in
[[records/specs/programmable-native-engine]]. Native programmable spaces, shared-data
transactions, reactive controls, permission/recovery flows and three example apps
are implemented and accepted for their scope.

The engine passes 14 production-path native groups and 5 SDK tests. The broad local
suite passed after repairing its table gate. [Hosted Checks](https://github.com/carloslfu/sevra-app/actions/runs/43320623027)
passed all 40 steps for `628bd36780bdd45f82cb22f1053a3f7d9d3e0395`, including both
packaging paths. The later localized permission-label correction at
`2fb90822a20ac83bda852177db90414586520722` has focused native/package tests and actual
installed UI verification; the older CI run is not claimed to cover newer source.
The [initial acceptance](../../../integration/evidence/2026-11-12-native-app-engine.json.gz),
[hosted receipt](../../../integration/evidence/2026-11-12-native-app-ci.json.gz),
[focused correction](../../../integration/evidence/2026-11-12-native-app-access-review.json.gz)
and [final installed receipt](../../../integration/evidence/2026-11-12-native-app-final-ui.json.gz)
preserve exact evidence, failures, repairs and limits.

The unlock blocker is closed. The installed main UUID is
`15F450B0-8377-3D40-9211-F041DCE10EF0`, helper `86B9EB3E-68F7-3121-9426-DBF974EC92F4`.
Both match the latest packaged product. The permission dialog displayed the actual
Stock table despite a misleading package title. The standard inventory package was
restored as version 6, required a fresh Enable action and rendered the saved quantity
32 with the reviewed spacing. The synthetic workshop is left open on Inventory.
No real workbook or preserved baseline app was changed. No required work remains
for this engine increment; broader production, hardware and accessibility
qualification remains as documented below. No VoiceOver or system setting was used.

## Earlier accessibility checkpoint: paused November 12

The owner's earlier instruction, [[sources/notes/2026/11/accessibility-headless-tests-and-pause]], authorized headless testing of all ten accessibility fixes, correction of failures, handoff, commit and push, then pause. **A1–A10 are implemented; 22 headless behavior groups and 10 supplemental static adapter groups pass. Actual UI and assistive-technology behavior remains untested.** No app was opened or installed, no UI or accessibility tree was touched, and VoiceOver, clipboard and system preferences were not used. This narrow check is complete; do not restart work from historical instructions or treat a general resume as permission for UI testing.

The checks execute the same production navigation, presentation, announcement/focus eligibility, reading-size and PDF-search decisions used by the app. Real synthetic workbook checks cover extracted text, description persistence/reopen, stale writes, exact source identities, paste/recalculate/Undo, validation errors and chart values. They run under a sandbox denying UI services, AppleEvents, network and other executable launches, with writes restricted to synthetic fixtures and Foundation atomic-write temporaries. The [headless receipt](../../../integration/evidence/2026-11-12-accessibility-headless-checks.json.gz) records source hashes, results, failures and corrections. [[records/reviews/accessibility-static-review-2026-11-12]] maps all ten findings to coverage and its limits.

The pass fixed discovery metadata appearing as extracted text before extraction or after a failed/unsupported result, preserved text after embedded NUL characters with a bounded Unicode read, and reset PDF-search state when the document changes. The native release `SevraDesktop` product compiles without launch. Strict lint passes for 19 changed/new Swift files. Standard CI is skipped because it runs native UI/accessibility checks outside the owner's authorization; this is scoped local headless evidence.

The earlier code-only checkpoint is `3cdaf775d01d57d0d5dd463537ca94272b991dff`; its [code-fix receipt](../../../integration/evidence/2026-11-12-accessibility-code-fixes.json.gz) remains unchanged. Increments 1 through 9 retain their earlier bounded acceptance. The earlier exercised product commit was `831b7f3b1181b0fa8218f5d77e08cd992fd17246`; its hosted test results do not qualify newer code. Work stays on main. This remains MVP 0.1 source test preview, not a notarized production release.

## What finished today

- **The remaining automation observation passed.** With the exact enabled definition open and Sevra in front, the 8:49 AM Bogotá run completed with result 6, the upcoming list advanced, and Open saved run opened that newly created run.
- **The nearby counterexample passed.** At 8:52 AM, the next run completed with result 6 and its link opened the new run. An unsaved checked Allow local AI option stayed checked through the refresh while the persisted grant remained `allowAI: false`. A display change did not silently grant authority.
- Both occurrences have exact saved run and activation receipts in [[records/operations/implementation]]. The previous screen-lock blocker is closed. The prior code commit's [hosted Checks run](https://github.com/carloslfu/sevra-app/actions/runs/43147307918) finished successfully, including all 39 reported steps. Prior local suite, installed model and packaging evidence is retained without rerunning those broader checks.
- The owner stopped the incomplete VoiceOver attempt. VoiceOver was restored off and the unsent synthetic composer marker was cleared in the earlier session. The attempt establishes no accessibility qualification. The subsequent records/review pass used no computer UI or system-setting changes.
- [[records/reviews/accessibility-static-review-2026-11-12]] now records ten ranked static findings, including table focus/paste, form context, query/snapshot table semantics, extracted-text access, chart values and status discovery. The later code pass implements all ten; this follow-up adds headless logic/storage checks without OS-level qualification. [[records/plans/known-limit-closure-2026-11-12]] gives concrete ways to close them and the broader product limits.

## Already fixed and verified

The November 11 code commit fixed exact historical automation lookup, pasted originals left unindexed after Done, and stale Open saved run targets. The first two had installed-window proof and counterexamples on November 11; today's runs finish the third. File shortcuts, Transcribe from File actions with Stop/retry, trigger-description behavior and paste/table conversion were exercised. The local model ran successfully, so the earlier memory shortage is no longer a blocker on the tested Mac. Earlier window fixes prevent the closed-workbook reopen crash and duplicate blank windows.

The detailed register preserves failures and dated evidence: [[records/operations/implementation]]. Do not restart accepted increments solely because an older section says a check was pending.

## Remaining work and limits

1. All ten accessibility fixes have passing headless coverage. The owner still needs to evaluate actual keyboard and assistive-technology focus, spoken output, native source actions, enlarged layout/contrast and PDFKit behavior. These UI/OS tests remain skipped, not passed; the review preserves a manual follow-up list.
2. Broad AI requests can still miss evidence; Excel supports a declared subset; automations intentionally run only while Sevra is active. The closure plan proposes a per-question evidence checklist, bounded formula expansion and a separately opted-in background policy. These broader proposals were not implemented by the accessibility work.
3. An uncoached external user, production signing/notarization and additional hardware qualification remain. Prior code-signing inspection found zero valid identities. Transcript accuracy and large-workbook storage costs also retain their stated limits.

These are precise unfinished items, not a production-readiness claim. The earlier accessibility pause remains historical; the later native-engine task
explicitly authorized its own implementation and UI verification. It does not
expand into the broader closure plan or VoiceOver/system-setting qualification.

## Paused state and retained fixtures

The due-test activation was paused through the CLI at `2026-11-12T13:52:29Z`, generation 7, with local AI off. The other historical test activation was already paused at generation 2. Neither the review, code fixes nor headless checks re-enabled either. At the earlier pause, the app was left open and idle; this handoff does not claim the app quit or every window was closed. No test/model worker was left running by the earlier stopped session, and this follow-up ran only compiler, headless, static and records tools, all completed before delivery. It did not operate the app or inspect its live UI state. Its fresh `.build/accessibility-headless/` workbook fixtures were cleaned up; the harness now completes cleanup before returning a failure exit too; retained acceptance fixtures were not used.

Disposable fixtures remain under `.build/acceptance-2026-11-11/`, including `Window-checks.sevra` and the two `nov12-*-workflow.json` receipts. The [portable result receipt](../../../integration/evidence/2026-11-12-final-automation-observation.json.gz) preserves the synthetic proof without depending on the local fixture surviving. No real workbook was modified. The new runner is reproducible with the commands in the implementation record; it is not scheduled or left running. Do not operate retained fixtures while paused.

If later work needs the CLI, use `output/native/bin/sevra` or the installed `~/.local/bin/sevra`; a bare `sevra` can resolve an unrelated retired CLI. Recreate selected disposable fixtures with `create` and `demo` when needed, with no pre-1.0 migrations. The model, engine, Slotstream and website repositories are unchanged.
## Native engine implementation, November 12

The owner explicitly requests complete native programmable app-engine implementation and verification, and explicitly permits installation and UI testing for this task: [[sources/notes/2026/11/programmable-native-engine]]. The earlier no-launch/UI restriction is superseded for this work; VoiceOver and system-setting changes remain outside it. The bounded implementation is accepted on main under [[records/plans/programmable-native-engine]]. The architecture and SDK contract are [[records/specs/programmable-native-engine]]. Existing accepted features and historical test receipts remain unchanged.
## Earlier local model authoring checkpoint

The owner now explicitly requests [[records/plans/local-model-native-apps]], continuing the accepted engine's installation/UI authorization. Local SDK discovery, source inspection and sandbox-checked save/update are implemented and have focused production-path tests. Real local-model use cases, adversarial review, installed visual verification and release checks remain in progress. [[records/reviews/local-model-native-apps]] records observed failures and repairs. The accepted SDK 1 checkpoint below remains historical evidence, not completion of this new authoring task.
