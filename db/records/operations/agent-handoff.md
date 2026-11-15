---
type: operational
meta-type: operational
id: 01m659x4nd2q89tkpzzsssd7yr
created: 2026-10-30T02:23:30.477380+00:00
updated: 2026-11-15T21:50:38.743237+00:00
summary: Rich visuals and inline-chat plan revision 12 passes four complete readiness reviews; start with native chat inputs, then charts. Implementation remains proposed.
title: Minimum-feature continuation handoff
---
# Minimum-feature continuation handoff

## Rich visual-system planning checkpoint, November 15

The owner-requested [[records/plans/rich-native-visuals]] is researched and reviewed through three revision passes. [[records/research/rich-native-visuals]] maps clean source `89c8ed70d8f5b18824cccf13932b035d0d424857` and primary technology references; [[records/reviews/rich-native-visuals-plan-review]] records concrete findings, revisions and remaining gates. The recommendation is a common typed native visual system for Home and mini apps, beginning with a complete charts/metrics/exceptions workflow, then richer analysis, boards/time views, diagrams and scoped media.

The subsequent owner request adds native inline chat interactions to the same plan, reaching revision 8. [[records/research/inline-chat-interactions]] records the code/primary-source audit; three further review passes cover questions, compact forms, exact action/review controls, captured visual answers and durable input handoff. P0a delivers useful chat controls before chart/diagram dependencies. Historical results stay distinct from current live views, and the existing text and business-operation paths remain authoritative.

The owner then requested a complete implementation-readiness review. [[records/reviews/rich-native-visuals-readiness]] records four whole-plan passes and section-by-section coverage, producing revision 12. It resolves standalone chat/Home ownership, stable state versus result keys, captured historical provenance, exact receipt Undo/Redo, partial action outcomes, direct form dispatch and stage dependencies. Relevant code was rechecked at `886edc8` and the Redo grammar follow-up at `f90529a`. The plan is ready to start P0-chat/P0a, followed by the P0-visual/P1 chart workflow. Diagram selection and performance remain explicit stage gates; no proposed feature is marked implemented.

The plan distinguishes package capabilities from versioned presentation-only edits, reuses exact query/transaction authority and requires chat parity, native visual review and independent data acceptance. ELK/Graphviz selection and performance are explicit implementation gates. This checkpoint changes documentation only: no new component, dependency qualification, UI launch or installed-app change is claimed. The existing accepted Excel, Home and chat-operation checkpoints below retain their original scope.

## Current Home checkpoint, November 14

The owner-directed [[records/plans/home-working-overview]] implements a useful default Home with attention, continued work and pinned spaces, plus chat-customizable layouts and live mini-app bindings. Home, the full app and chat share app data, actions and input state. Removing a view preserves the app/data; explicit Reset Home and version history preserve recovery. Native conversation, navigation and access remain stable.

The [Home acceptance evidence](../../../integration/evidence/2026-11-14-home-working-overview.json) qualifies exact code `b1557b6ac6e0ccd0ba8a19dc70dae740f7723fe6`. A fresh pinned local-model walkthrough passed all five requests: embed, chat-operate, move, remove and reset; all saved layouts preserve unrelated sections, and reopen retains Pencils quantity 3. Six read-tool recoveries and 27–94 second request times limit the result. Local regression, complete agent/grammar, native package/install/extraction and native visual checks pass under the plan's explicit rerun boundaries. [Exact-code hosted CI](https://github.com/carloslfu/sevra-app/actions/runs/43666871100) passed. This is finite coverage, not universal model reliability.

Final packaged main UUID is `F41F2AB4-DEBD-3CFA-908A-687E0EC0D602`; the isolated visual-review main UUID is `31276427-F1B6-3868-A290-1E49AC9C2E5F`. Later chat-only repairs reuse unchanged visual evidence. The review app was closed, and the active installed app was not controlled or replaced. Verify the exact bundle before any future opening or installation. Concurrent Excel business changes are preserved and excluded from this frozen candidate. VoiceOver, other hardware and production distribution remain unqualified. Earlier checkpoints below retain their original scope.

## Current chat operation checkpoint, November 14

The owner-directed [[records/plans/chat-primary-operation]] implements chat as the primary operator for workbook and mini-app work. Named actions and existing fields, selections, tables and canvas actions execute through the same signed worker and data broker without a rendered app. Workbook editing, workflow execution, approvals, automations, Excel conversion and explicit-path exports also have conversational operations. Views remain optional clients of shared state. The [[records/specs/chat-primary-operation]] contract records coverage and authority.

The [acceptance evidence](../../../integration/evidence/2026-11-14-chat-primary-operation.json) includes a final actual-model add/edit/missing-input/Undo/reopen walkthrough and all earlier failures. Core, signed native, SDK, agent, grammar, release-package, isolated install and extraction checks pass with the plan's exact rerun boundaries. Prompt budgets remain unchanged. This is finite action coverage, not a universal local-model success guarantee.

Packaged main UUID is 039A908F-28BB-36CA-8E57-32EEE8862C92. The active user app was left untouched under the owner's no-control instruction. The newer package has not replaced the installed frozen Excel build described below; verify the exact bundle before any later opening or installation. No current visual/VoiceOver or production distribution qualification is claimed. The frozen Excel batch evidence remains separate and is preserved.

## Current Excel checkpoint: two fresh complete batches, November 14

The owner-requested [[records/plans/fresh-excel-batches]] is complete on the explicitly selected [[sources/notes/2026/11/frozen-excel-checkpoint]]: `da3c4720e05033b5aaea620ebb01abde28123d9e`. Two consecutive 10/10 batches created twenty new native apps using the local model, with no replayed apps, previous conversations, workflow reference JavaScript or manual source repairs. Each batch passes 89 independent originals (84 visible plus five held-out), 302 UI steps, 79 saved-edit/reopen/Undo cases and ten portable copies. The [receipt](../../../integration/evidence/2026-11-14-fresh-excel-batches.json) and [retained trials/packages](../../../integration/evidence/2026-11-14-fresh-excel-apps/README.md) preserve all failures, model repairs, source provenance and scope.

The diagnostic batch failed Inventory's copied row-selection guard and Lookup quotes' renamed fields. Generic publication coverage now requires successful fixed-cell actions before Table selection, and authoring/review preserve requested labels. The action check accommodates all 24 declared actions within its bounded 32 transactions. All 38 focused groups pass. The frozen full suite passes through desktop compilation; a model-busy interruption at the package test is closed by rerunning that check with inference idle, and the remaining tail checks pass. Exact-code hosted CI, release build, native package/install/extraction, formatting, links and db validation pass. The concurrently edited shared checkout's compile failure is retained and is outside this acceptance.

All ten fresh batch-2 interfaces pass observed native wide/compact layout, edit/recalculate/reset/Undo and access checks. Installed main UUID `F1FBB363-C04F-34D8-BDF0-67794F636F29` matches the frozen package; helpers/workers and SDK resources are verified. Test edits were undone, app grants disabled and task recents removed while preserving all four original recents. The baseline app, real workbooks and models are unchanged; the preview is on Welcome. Newer unbuilt source or chat-operation changes must not be described as verified by this build.

This is bounded repeated-run evidence, not a first-attempt guarantee or a statistical production success rate. Some apps needed several automatic repairs. Original VBA never executes; original macro execution equivalence, exact Excel layout, unavailable dependencies, binary XLS/XLSB, inserted-row formula extension, VoiceOver, external security/hardware/customer qualification and production notarization remain unqualified. Earlier sections are historical.

## Earlier checkpoint: automatic Excel conversion, November 14

The owner-requested [[records/plans/automatic-excel-reliability]] qualifies ten local-model-generated native business apps without manual UI or calculation-source repairs. The accepted candidates come from successive fresh runs. All ten pass a final replay on `8c8d0140bb4198112b8731330b366b0f425113f3` against 89 independently LibreOffice-recalculated originals: 84 comparison cases available during generation and five held-out states never supplied to the model. See the [acceptance receipt](../../../integration/evidence/2026-11-14-automatic-excel-reliability.json) and [retained trials and generated apps](../../../integration/evidence/2026-11-14-automatic-excel-apps/README.md).

Inventory now ships twice from current saved stock, rejects malformed/overdrawn quantities and invalid current stock without writes, preserves failed drafts, recalculates and supports Undo. Loan and Commission reuse native formulas; the model creates the interface rather than reimplementing supported financial arithmetic. A separate 24-scenario PMT corpus checks 48 saved payment/rounding results and is not counted as generated-app coverage. Other repaired failures include recoverable planning read failures, invented selection requirements, stale/contradictory authoring instructions, calculation-draft invalidation, repeated mismatch handling, ambiguous syntax/action diagnostics, incorrect reviewer objections, deterministic date arithmetic and native table spacing/scrolling.

The final replay passes 302 independent UI steps, 79 saved-edit/reopen/Undo cases and ten portable copies. Final focused checks pass 37 authoring/conversion groups; core PMT and CLI import/edit checks pass. Earlier full local suites and subsequent regressions are retained with their exact versions. [Hosted Checks](https://github.com/carloslfu/sevra-app/actions/runs/43634947457) passes the exact final code, including full core/agent/grammar and baseline/native packaging checks. Final local package/resource, installation and extraction checks also pass.

Installed native UI was inspected for Inventory, Loan, Commission, Invoices, Due dates and unchanged Reference codes, including actual input edits, errors, Undo, original-header guards, row alignment and constrained-window scrolling. Candidate origins and the exact build used for each observation are recorded separately; unchanged UI evidence is reused. The final installed main UUID is `B713C26D-4750-32D3-BCE5-5FE5EC7BE608`, matching the current package; helper/workers and SDK resources are verified. The preview is left on Welcome. All task app grants are disabled, task recent entries removed, current unrelated recents/preferences preserved, and synthetic workbooks retained as ignored evidence. Earlier recent-limit eviction is documented; no unrelated workbook, model file or preserved baseline app was modified.

This is finite coverage across successive runs, not a single ten-of-ten cohort, a first-attempt success rate or universal Excel equivalence. Fresh generation can still fail or take minutes; failed attempts, superseded narrower passes and harness corrections remain recorded. Original VBA never executes; Inventory original action-execution equivalence remains unverified despite independent shipment checks. Exact Excel rendering, missing dependencies, external services, row-insertion formula extension, production notarization, external security/customer testing, VoiceOver and additional hardware remain unqualified. Earlier sections below are historical.

## Earlier publication verification, November 14

The implementation was committed and pushed as `34f1f00`. [Hosted Checks run 43539274889](https://github.com/carloslfu/sevra-app/actions/runs/43539274889) passed on exact commit `34f1f006ef02e883411ded6aaff33067d97c1296`, including the baseline and native packaged products. All recorded code hashes match that tested revision. This publication receipt changes only documentation/evidence; its db.md and link checks are separate from the unchanged code's full CI result. Autonomous model-generation reliability remains open.

## Earlier checkpoint: reconstruction and adversarial review, November 14

The Excel reconstruction engine is implemented with inert original/VBA evidence, bounded pure behavior programs, scoped native actions and host-owned original-result comparisons. The multi-pass review repaired calculation/write-scope, row identity, atomic transactions, native remount/event state, canvas actions, corrupt metadata, reviewer context and interface defects. See [[records/reviews/excel-reconstruction-and-engine-review]] and the [acceptance receipt](../../../integration/evidence/2026-11-14-excel-engine-review.json).

The integrated full suite passes: 653 core checks, 17 native groups and six SDK tests. Final focused authoring checks pass all 36 groups across ten business cases and 43 independently recalculated originals. Explicitly reviewed Inventory, Loan and Lookup derivatives pass 42 independent UI steps plus 15 original comparisons. Installed native permission/edit/validation/Undo/reopen/example flows and wide/821-point compact layouts were inspected. Final main UUID is `CA63042B-C1BD-3DD5-8D37-684046FD3AB1`; package/install/extraction checks pass. All task grants are disabled, five task recent entries are removed, and the installed preview is closed. Scratch evidence stays under ignored build folders. The baseline app, real workbooks and model files are preserved.

**Autonomous authoring reliability remains open.** Stronger checks exposed wrong zero-interest logic, missing numeric validation and copied lookup constants in earlier model outputs. Latest fresh Inventory and Loan builds both stopped after repeated mistakes. Manually repaired samples are labeled separately; their success is not fresh-model acceptance. This is a bounded source preview, not a universally correct Excel replacement, a security certification or a production-notarized release. VoiceOver, external customers and additional hardware remain unqualified. Commit checks on GitHub qualify the containing pushed revision separately from local evidence.

## Earlier checkpoint: single Excel import, November 13

The owner-approved [[records/plans/single-excel-import]] is implemented as one native Add files/start/drop/saved-Excel flow. A local model infers a reviewable workflow, then builds a checked native app over the same imported tables and supported formulas. Table-only use requires no model; existing-table updates remain a secondary reviewed action. Stable conversions preserve originals and avoid duplicated data on retry. Host-owned capabilities, sandbox checks, separate model review and exact-version device access remain enforced.

The [[records/reviews/single-excel-import]] and [acceptance receipt](../../../integration/evidence/2026-11-13-single-excel-import.json) qualify the result. The full integrated suite passed, followed by 17 native and 21 authoring/conversion groups for final repairs. Eight deterministic business workflows and two edge groups pass; actual-model Inventory, Invoices and Timesheets pass independent 14-step repeated-edit/header checks. A fresh installed UI build also completed in 1m 2s and passed real edits, formula recalculation, Undo, search, header protection, validation, reopen, table-only fallback and normal/narrow layout inspection. Fourteen review findings were repaired, including offscreen keyboard focus. Earlier failed trials are retained.

Installed main UUID `B5E2EA5A-48DA-35F1-BB95-685E69B130D0` matches the current packaged build. Both workers use UUID `BF55355D-6CE6-3FB2-9FD7-9CD0F1A39DAD` and match exact signed bytes. Package/install/extraction checks pass. The owned UI app was disabled; 20 test workbooks and two task-owned recents were removed after retaining evidence. No native grants remain. The app is left on Welcome; unrelated workbooks/preferences, model files and preserved baseline are unchanged. No VoiceOver or system settings were changed.

This qualifies a bounded source preview, not all Excel applications. Unsupported formulas keep declared saved results; VBA, external refresh, original layout/protection and automatic formula extension to new rows are not implemented. Generation can still fail or misunderstand business rules. The earlier generic calculator failure below is not retroactively qualified by the narrower Excel authoring successes. No external security certification, additional hardware or production notarization is claimed.

## Earlier checkpoint: fresh mini-app baseline, November 13

The owner-approved [[sources/notes/2026/11/mini-app-fresh-start]] is implemented for the selected development artifacts: obsolete mini-app workbooks/packages, 20 approvals and their recent entries are retired, with unrelated workbooks, model files, canonical examples and historical evidence preserved. Test runners now dispose of temporary host bundles; native tests return before process exit so their workbook cleanup runs, and test preference domains clear. No migration or compatibility path was added. Normal initial review and per-version approval remain required.

The [[records/reviews/native-app-fresh-start-2026-11-13]] and [receipt](../../../integration/evidence/2026-11-13-native-app-fresh-start.json) separate the outcomes. All 17 native and 11 authoring groups pass. A fresh canonical Inventory app passed native import, initial access review/enable, validation, save/reactive row count, Undo and normal/narrow spacing inspection. Its workbook, grant and recent entry were then removed; the installed app is on Welcome. Installed main UUID `C1206D73-F023-3CB9-8A3B-C052F9A93B38` matches the packaged product; runtime source is unchanged.

**Open authoring reliability issue:** a new local-model calculator request exhausted its steps on repeated syntax/test errors; a guided follow-up selected the wrong fixed-layout tool and stopped. Neither saved an app; integrity and permissions held. This occurred in a fresh workbook, so failures are not limited to long prior conversations. The imported example's success does not qualify this model request. No broad generation-reliability claim is warranted.

## Earlier checkpoint: native-app adversarial review completed, November 13

The owner-requested [[records/reviews/native-app-adversarial-review-2026-11-13]] is complete for the native engine and local-model authoring scope. Six findings are repaired: two P1 permission issues (schema read expansion and stale live-session grants), plus four P2 native-state/presentation issues (initial table state, tab state/titles, disabled interactions and disclosure labels/state). Reproducing failures were retained; no known finding from this bounded review is left open. The old approvals belonged to disposable development fixtures. The later [[sources/notes/2026/11/mini-app-fresh-start]] retires that test state instead of defining a user upgrade task.

The [review receipt](../../../integration/evidence/2026-11-13-native-app-adversarial-review.json) records source and log hashes, actual failures, repairs and limits. `scripts/check.sh` completed successfully, including 650 core checks, native groups and full agent/grammar checks. Final presentation-only changes passed all 17 native groups, strict Swift lint, a fresh native release build and package/resource/signature checks. Installer/extraction checks also pass, with unchanged evidence reused for the last header-only change. The 11 authoring groups pass. No new actual-model inference is claimed; the seven actual-model cases and retained generation failures below remain relevant.

Installed main UUID **`C1206D73-F023-3CB9-8A3B-C052F9A93B38`** matches the current packaged candidate. Both worker UUIDs are **`CB5298EB-B04D-3387-99B0-A220BF0DCF35`** and their exact signed bytes match their packaged products. The installed UI passed approval, disable/re-enable, saved-data preservation, initial/reverse sort and selection, tabs/titles, disabled and re-enabled actions, disclosures, centered rows and a narrowed scrollable layout. The disposable review workbook is left open with the working disclosure expanded. No real workbook, preserved baseline app, VoiceOver or system setting was changed.

The baseline `9c59650d56260c75c4662a87ccd8c6224462208f` passed [hosted CI](https://github.com/carloslfu/sevra-app/actions/runs/43368224770). That run does not qualify these newer fixes; new hosted CI is not claimed here. This remains an internally reviewed source preview, not a production-notarized or independently security-certified release. Generated apps still need human testing. No further implementation is implied by the historical sections below.

## Earlier checkpoint: local-model native authoring accepted, November 12

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

## Inference and context upgrade plan, November 15
The owner requested a thorough implementation plan for context-accounting fixes, Splash and related integration upgrades, and context/memory qualification. [[records/plans/inference-context-upgrade]] is revision 4 after three sequential readiness passes; [[records/reviews/inference-context-plan-readiness]] records findings and revisions, and [[records/research/inference-context-upgrade]] records source/evidence limits.

Planning only. No engine/model/configuration change, candidate GPU benchmark, installation or UI work occurred in this checkpoint. The native preview remains at its existing 32K/12 GiB configuration and Splash 1.4.1 pin. Candidate 1.6.1 provenance is recorded from source/release metadata; archive/component verification and qualification remain implementation steps. The next implementation sequence is P0/P1 accounting and preparation, P2/P3 same-configuration engine integration and qualification, then P4/P5 controlled context/memory selection, followed by UX and release gates. No automatic mid-job capacity-growth ladder is planned for the first implementation.

The current W1 exact-parity blocker and D9 repeatability evidence remain open; passing historical timings do not qualify promotion. Candidate context research may proceed only after behavioral/lifecycle/admission prerequisites, with promotion gated separately. This planning checkpoint does not alter other workstreams' status or restart cross-chat coordination.
