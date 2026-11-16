---
type: operational
meta-type: operational
id: 01m78qhn7q81ha6w72smnkerxt
created: 2026-11-12T20:35:19.415048+00:00
updated: 2026-11-16T16:40:47.552139+00:00
summary: Reviewed architecture and implementation gates for sandboxed JavaScript, reactive native UI, scoped workbook data, packaging and end-to-end verification.
title: Programmable native app engine implementation
---
# Programmable native app engine

## Owner direction and scope

The November 12 owner requests a reviewed architecture, a complete implementation plan, implementation and end-to-end verification. The subsequent explicit answer authorizes installing and operating Sevra Native Preview for this work. This supersedes the paused/no-app-launch restriction for this task. No VoiceOver or system-setting changes are implied. See [[sources/notes/2026/11/programmable-native-engine]].

Deliver a usable v1 of programmable spaces: ordinary bundled JavaScript/TypeScript logic, composable native UI, reactive queries, scoped transactional data commands, portable code and shared workbook data, native installation/permission/recovery flows, CLI authoring, examples and measured verification. This does not claim infinite OS access, full Excel compatibility, arbitrary npm/native modules, cloud sync, unattended execution, or production notarization. Existing workbook functions, formulas, actions, workflows and fixed spaces remain usable.

## Architecture decisions after review

1. **Authority review:** use the existing workbook, managed tables, immutable items, operation tokens and committed-change capture. Save an app package as part of a versioned space definition; no parallel ledger or code execution on import, replay or export. Binding aliases identify permitted datasets. The native host binds permissions to exact package digest, physical workbook and space version. Save/update is separate from enabling code. An imported copy has no grant.
2. **Reactivity review:** component functions construct scoped bindings; signals/computed/effects own presentation reactivity. Reuse the pinned Preact signals core, not Preact DOM or React internals. JSX is optional syntax lowered at authoring time. A keyed retained AppKit tree owns focus, scrolling, selection, composition, layout and gestures. Native input revisions prevent asynchronous acknowledgements replacing newer edits. UI batching is not a database transaction. Persistent writes only happen through explicit commands.
3. **Process and transport review:** pinned QuickJS C code runs only in a sandboxed XPC helper. No std/os modules, native module loader, filesystem/network APIs, native pointers or Objective-C reflection enter JavaScript. The helper is the process isolation boundary; runtime contexts are logical isolation, not a claim of one OS process per space. XPC connections bind host-side sessions. An initial tree is followed by bounded batched node changes, semantic events and request/result messages. Every payload is decoded/validated before touching AppKit or data. Session/sequence fencing, deadlines, output budgets and restart stop stale work and queue floods. Main actor never blocks on script or data work.
4. **Data and consistency review:** bounded live-query subscriptions run off-main and refresh after committed revisions. Native tables page directly through the host, avoiding a JS copy of large datasets. Read results identify revision and exact row versions. Commands require expected revision plus operation token, perform authorization inside the writer transaction and record the exact app package as programmatic attribution. Retry returns the original receipt; stale writes refuse. No SQL or schema changes from arbitrary script text.
5. **Lifecycle review:** mount/unmount disposes bindings, callbacks, subscriptions and connections. Navigating away cancels pending work. Durable draft values survive runtime failure; grants do not travel with workbooks. Restart restores the saved app and drafts without replaying commands. Errors appear in trusted host chrome outside script control. Version updates revoke execution until reviewed again.
6. **Flexibility review:** ship semantic stacks/grid/split/scroll/section, text/buttons/fields/editor/toggle/picker/slider/date/progress, native tables, tabs/disclosure and a native drawing scene with hit regions and accessibility. Components compose without adding Swift for each business workflow. Native SDK capabilities remain explicit/versioned. Arbitrary logic is supported within execution budgets; long jobs must yield/use host operations. Layout and animation remain native.

## Implementation sequence and acceptance

- [x] P1: package/binding contracts, strict validation, versioned space save/install/export/restore, scoped query and atomic record commands, recoverable drafts through existing storage.
- [x] P2: pinned QuickJS and signals, offline JS runtime SDK, TypeScript/JSX authoring/bundling, source/notice integrity, timeout/memory/output bounds.
- [x] P3: typed wire contract, helper service, sandbox entitlements, async XPC host session, sequence fencing, cancellation/restart, explicit permissions.
- [x] P4: retained keyed AppKit renderer, bounded dynamic primitives, native control semantics/input revisions, native query-backed tables, canvas hit regions/accessibility, cleanup.
- [x] P5: native import/enable/revoke/restart/export flows and space routing, CLI package lifecycle, exact-version history, updated packaging/install.
- [x] P6: three materially different synthetic apps (inventory, job tracker, visual planner), executable SDK/storage/runtime/renderer/IPC tests and adjacent refusal cases. Verify data reuse, edits and reactivity, stale write refusal, source updates, malformed payloads, permission denial, infinite loops, queue bounds, reopen and portable copy.
- [x] P7: review integrated diff for authority, state/identity races, resource lifecycle and usability; fix findings. Run focused checks during iteration, then required suite and packaged sandbox/installation checks. Install exact candidate once, verify identity, exercise native journeys. Preserve measured evidence, limits and failures. Commit/push on main and inspect hosted checks.

## Verification contract

Acceptance requires the actual production SDK -> QuickJS -> XPC -> host -> native renderer -> workbook path. Headless mock transport tests alone do not qualify the bridge. The packaged helper must have sandbox entitlements; verify that an in-helper file/network probe is denied. Malformed/oversized messages, wrong sequence/session, unknown components, unsupported SDK, unavailable bindings, stale commands, permission revocation and helper termination must fail without canonical data mutation. Render-only failure must leave the trusted shell usable.

Use disposable synthetic workbooks only. Verify saved code/data survive reopen, export/import and deterministic reconstruction, with inert import and fresh permission for the copy. Benchmark incremental updates and table paging on this host, recording counts/timings without universal performance claims. Exercise typing, selection, scrolling and native actions in the installed app; document any remaining accessibility/hardware/release limits.

## Findings and evidence

Append implementation and verification findings here. Checkboxes reflect passed acceptance, not merely source presence. Existing broader release limits remain in [[records/operations/agent-handoff]].

### Integrated review findings, November 12

- Packaged XPC initially failed to find the SwiftPM SDK bundle outside the build tree. The worker now locates its embedded resource bundle first; the signed, packaged XPC harness passes.
- AppKit testing exposed constraints activated before a common view ancestor and removal of a child not yet in an arranged stack. Both native crashes are fixed and the control gallery mounts/layouts in the packaged harness.
- A live table refresh originally emitted an onSelect event and overwrote unsaved form fields. Refresh-driven selection is now silent, explicit user selection is deduplicated, and controlled logical-key selection clears after save. Both the regression check and the installed external-edit counterexample retain the draft; saving its stale row refuses without overwriting newer data.
- The owner noticed row text sitting too high. Cells now contain an intrinsic-height label centered vertically, use 28-point plain native rows and 12-point column spacing, right-align numbers and expand columns to fill the viewport. Packaged checks assert the center and column fill; installed visual confirmation follows.
- The required full suite stopped at an existing formula-cell click regression introduced by the earlier accessibility changes. Restored the AppKit responder-validation path using the current logical row/column focus model. The unchanged failing check now passes, as does the remaining suite. This is a repaired gate, not a skipped check.
- The broad suite before that failure passed all 650 core invariant groups and the preceding durability/CLI/automation/document checks. The continuation reran the table gate and all remaining steps successfully. Native package checks will run explicitly on the final installed candidate; the preserved baseline product is not rebuilt by this native task.
- The final engine harness passes 13 groups, including actual XPC sandbox denial, native actions through JS into saved records, reactive refresh, preserved control identity, draft recovery, malformed input and execution budgets. Five SDK tests cover keyed state, conditional trees, input acknowledgements, batched patches and cleanup. A separate 10,000-record fixture measured 30 alternating first/last 200-row pages: median 16.453 ms, p95 17.692 ms on this host. Thirty small label changes through XPC measured median 2.074 ms, p95 2.138 ms with a 1 ms observation interval. These are scoped measurements, not general latency promises.

- The deeper owner-requested visual pass found forced vertical stretching of empty status text. The renderer now keeps natural content height, with a constraint against overflow. Examples group labels with fields, use a 4-point spacing scale, reduce oversized job counts, separate actions from fields at narrow widths and hide empty status text. App chrome no longer duplicates the running app title. The native check asserts a status label is not stretched, in addition to row centering and column fill.
- Reviewed pending-event causality: edit coalescing now applies only to consecutive edits of the same control. An edit after Save cannot move ahead of Save. The real native/session/XPC test submits that sequence and verifies the saved row. Example forms retain text typed while an asynchronous save completes instead of clearing a newer draft.
- Installed workflow checks pass: inventory create/update/Undo, external update without draft replacement, stale row refusal, explicit re-selection, disable/re-enable draft recovery; job creation and Todo-to-Doing with grouped counts; planner create, native drag and arrow-key move, checked against the saved immutable rows. Native package import stays disabled until enabled. An intentional script failure leaves the shell usable and Restart restores the draft. Native source viewing and template export were exercised; exported bytes decode to the original package.
- The owner made deep visual and functional review a standing instruction. AGENTS.md now records spacing/alignment/hierarchy/density, empty/error states, keyboard behavior and constrained-window review. No VoiceOver or system-setting changes were used.

- Compact-height review exposed a clipped footer. App surfaces now accept the proposed SwiftUI viewport size and use an AppKit scroll view around natural-height content. A 520×300 native test scrolls to the exact document bottom and verifies reachability; normal-width alignment and retained controls still pass.
- The native history dialog requested 100 entries from an API bounded to 50. It now loads 50 at a time with an Earlier versions action and visible failures. Installed restore verification is part of the final acceptance.
- The standing UI direction is preserved in [[sources/notes/2026/11/native-interface-quality]].

### Final local acceptance, November 12

The [portable acceptance receipt](../../../integration/evidence/2026-11-12-native-app-engine.json.gz) preserves source hashes, sanitized check logs, installed identity, synthetic saved records, measured timings and the actual UI journeys. The final packaged harness passes 13 groups and the SDK passes 5 tests. The broad suite passed after repairing and rerunning the existing table gate plus all remaining checks. The final native release package, resource-denial checks, installer and extraction checks pass. No check was bypassed. The preserved baseline app was not rebuilt locally; hosted CI checks both packaging paths.

The installed main executable UUID is `F6DAAB08-A438-3317-A0F4-BC2AE21EE8B7`; the helper UUID is `445BBF8F-7DA7-30FC-BF41-868AE2D81E1F`. Main UUID matches the packaged build; installer signing changes the parent SHA. Worker SHA and UUID both match. This is the latest local native preview, not a public production release.

Installed history now loads and restores correctly: two restores create new versions, require enabling the exact version again, retain existing business records and allow a new job to save. Compact-window scrolling reaches the table footer. Planner content extends its document height so cards below the original board are reachable. A card at y=780 was visibly reached, then its original position restored. Filtered inventory now says “matching items”; the zero-result state and clearing search were visually verified. The table label is centered, numeric header/cells align right, and the form controls use consistent grouping. The synthetic workbook verifies with no asset/database issues and is left open on Inventory.

Final measurements through the current packaged harness: 30 label events through XPC, median 2.061 ms and p95 2.100 ms at a 1 ms observation interval. The unchanged 10,000-record paging measurement remains median 16.453 ms and p95 17.692 ms. These are one-host scoped checks. Full assistive technology, other hardware, external use and production signing remain unqualified.

All local P7 work is complete. Commit/push and the hosted run are the remaining acceptance steps; append their result here.

### Hosted packaging finding and repair, November 12

[Checks run 43315081956](https://github.com/carloslfu/sevra-app/actions/runs/43315081956)
on implementation commit `e518fef19b6fbcfabb846faace6b5be856bd9d6e` passed the new
engine/sandbox, core invariant suite and all other functional steps through store
validation. The baseline release compiled, then its signature verification failed:
`Contents/MacOS/mlx.metallib` was unsigned. Removing parent deep signing to preserve
the sandboxed helper exposed that unsigned baseline leaf.

The baseline build now signs its Metal library explicitly before the parent; the
baseline installer does the same for the embedded CLI copy. Native runtime bytes
and helper signing remain unchanged. Installer regression checks now verify the
worker retains its exact packaged SHA and only its sandbox entitlement in both
variants. The baseline release/signature, both isolated installers and baseline
packaged extraction pass locally. The preserved installed baseline was not touched.
See the [signing repair receipt](../../../integration/evidence/2026-11-12-native-app-signing.json.gz).
This repairs the failing gate; the follow-up hosted run remains required.

### Permission-review labels and pending final inspection

A later review found that the Enable surface displayed the package's claimed table
title. It now resolves names from the actual bound workbook tables off the main
actor, and keeps Enable disabled until all bindings are available and match their
schemas. Failed access review is visible and retryable. A meaningful regression
uses a package title of “Harmless settings” for a real “Records” table and verifies
the authoritative name; unbound and missing tables refuse.

The updated production-path native harness passes 14 groups. Strict formatting,
the native release build, path/resource/signature checks and the isolated native
installer pass, including the sandboxed worker's exact bytes and entitlement.
The new packaged main UUID is `15F450B0-8377-3D40-9211-F041DCE10EF0` and helper UUID
is `86B9EB3E-68F7-3121-9426-DBF974EC92F4`. This package has not yet replaced the
installed preview. The installed F6DAAB08 candidate retains the previously observed
UI acceptance.

The Mac locked before the affected dialog could be inspected. The owner has been
asked to unlock it. Final acceptance remains open for installing this exact newer
candidate and inspecting the authoritative table label and enable/re-enable flow.
The prepared synthetic package points the Inventory binding at its existing Stock
table while claiming “Harmless settings”; after verifying the real name, restore
the ordinary inventory package. No real workbook is involved.

This is a localized permission-review presentation correction, covered by the
owner's focused-verification policy. Reuse unchanged integration evidence and
state the exact hosted commit separately from this follow-up's local proof; do not
claim a skipped or older CI run tested newer source.

### Hosted acceptance passed; final dialog inspection pending

[Checks run 43320623027](https://github.com/carloslfu/sevra-app/actions/runs/43320623027)
passed all 40 reported steps for `628bd36780bdd45f82cb22f1053a3f7d9d3e0395`, including
the repaired baseline release/signature, packaged CLI/installation journeys and
isolated Native Preview build/package checks. The [hosted receipt](../../../integration/evidence/2026-11-12-native-app-ci.json.gz)
records the exact commit and conclusions. The earlier failed signing run remains
preserved; no failing gate was bypassed.

The later bounded access-dialog refinement has [separate focused evidence](../../../integration/evidence/2026-11-12-native-app-access-review.json.gz)
for its exact source hashes, 14 passing native groups, release build, package and
isolated installer checks. Its ordinary native UI flows reuse the earlier installed
proof where unchanged. The follow-up commit intentionally avoids a third unrelated
full integration rerun under the owner-approved focused-verification policy; an
older CI run is not claimed to test newer source.

P7 stays open only for the actual installation and visual inspection of this latest
permission dialog. The Mac is locked and the unlock request is pending. The latest
packaged main UUID is `15F450B0-8377-3D40-9211-F041DCE10EF0`; the currently installed,
previously exercised main UUID is `F6DAAB08-A438-3317-A0F4-BC2AE21EE8B7`. Resume by
quitting the existing preview normally, installing the latest exact bundle, matching
its main/helper UUIDs, then inspecting the real Stock label with the synthetic
misnamed-binding package and restoring/enabling the standard inventory example.
Do not redo accepted unrelated workflows or operate any real workbook.

### Final installed acceptance completed, November 12

After the owner unlocked the Mac, the prior preview was quit normally and the
latest packaged candidate was installed with `bash scripts/install.sh --native
--no-build`. The installed main UUID `15F450B0-8377-3D40-9211-F041DCE10EF0` and helper
UUID `86B9EB3E-68F7-3121-9426-DBF974EC92F4` match the packaged product. The worker SHA
also matches exactly; parent signing changes the installed main SHA as expected.
The exact verified Native Preview bundle was then opened.

The installed access dialog showed **Stock · Read and change records** while the
synthetic package claimed **Harmless settings**. Enabling succeeded and displayed
the original Brass screws record with quantity 32. Restoring the standard inventory
package created version 6, revoked execution for the replaced version, presented the
correct Stock access again and required a fresh Enable action. The normal inventory
then rendered with the same saved row. Permission wrapping/alignment, field/action
grouping, centered table text, right-aligned numbers and footer were inspected in
the native split-workspace layout. Workbook verification reports no asset or database
issues. The standard inventory example is left enabled and open; no real workbook
or preserved baseline app was modified.

The [final installed receipt](../../../integration/evidence/2026-11-12-native-app-final-ui.json.gz)
preserves the exact source hashes, installed identities, visible observations and
saved synthetic data. It closes the unlock blocker and P7. **P1 through P7 are
complete for SDK 1.** The 14-group localized native verification and 40-step hosted
integration run retain their exact separate scopes. This final records-only update
uses fresh store/link/whitespace checks and reuses unchanged implementation proof.
Production signing, other hardware, broad assistive technology and AI JavaScript
package-authoring remain the separately documented product limits.

### Workbook images in mini apps

The Image component now renders approved included images with the same native
decoder as the workbook preview. The app manifest names the specific assets and
the enable screen identifies them by workbook filename. The worker receives
the aliases and the native host retains the files and decoded pixels.

The signed XPC and AppKit check imports a PNG, removes the source path, mounts
the installed mini app, checks decoded pixel dimensions, switches to an SF Symbol
and back, and verifies that revocation removes the image. It also refuses an
external linked image and a direct asset ID supplied in place of an alias.
All 20 signed native checks and all 28 SDK checks passed.

The native preview was packaged, signed and installed with matching executable
UUID 97C09DE0-B8DE-38C4-A81C-EBEC46984B15. In a disposable workbook, the access
screen named the included PNG. The image rendered proportionally after Enable,
switched to the SF Symbol and back, and disappeared after Disable.

### Click to enlarge

The inline photo opens a sheet with the same ImageViewer used by workbook
documents. It decodes the same approved asset at the viewer's larger resolution
and initially fits the photo in the sheet. Done or Escape returns to the mini app.
The signed native checks verify both mouse and accessibility actions resolve the
displayed alias and a symbol offers neither action. All 20 checks passed.
The installed preview matched UUID A4AF21E2-1B9E-3757-B8F2-091C630658FD.
The disposable PNG demo opened from the inline photo, offered the native zoom
controls, returned on Escape and removed the enlarge action after Disable.
