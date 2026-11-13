---
type: review
id: 01m7aq9rpes5eak19txj2329bp
created: 2026-11-13T15:09:29.678593+00:00
updated: 2026-11-13T15:48:16.211016+00:00
summary: 'Native-app adversarial review completed: two permission repairs, four UI repairs, full local checks and installed visual verification; source-preview limits remain.'
title: Native mini-app adversarial review, November 13
---
# Native mini-app adversarial review

Owner: [[sources/notes/2026/11/native-app-adversarial-review]]. Reviewed baseline: `9c59650d56260c75c4662a87ccd8c6224462208f`. Its [hosted Checks run](https://github.com/carloslfu/sevra-app/actions/runs/43368224770) completed successfully. That does not qualify this review’s newer changes. Related contracts: [[records/specs/programmable-native-engine]] and [[records/specs/local-model-native-apps]].

## Findings and repairs

1. **P1: approved reads silently expanded after schema changes.** `nativeAppPage`, typed queries and subscription fingerprints did not require the saved binding’s columns to match the current table. Adding a private column could expose it under an old approval; writes already refused this. All read paths now validate active, exact columns inside the same database read transaction as authorization and execution. A table rename remains valid; schema changes and archival refuse; updating the binding and issuing new access works. The regression failed before the fix and passes afterward with synthetic private-field data.
2. **P1: disabling one session left another session’s capability live.** A persisted boolean and in-memory revoke protected only the session receiving Disable. Approval now has an immutable generation; data admission and final write commit check the current generation. Reapproval cannot revive a stale worker. Polling removes a stale session’s interface. The real two-session regression failed before the fix and now denies old reads/writes, allows new approval and proves a revocation after admission rolls back the transaction. Earlier development boolean approvals were inert after this change. The later [[sources/notes/2026/11/mini-app-fresh-start]] retires those disposable fixtures; this is not a supported user upgrade path. This proves same-host-session fencing, not hostile-local-process or OS-account security.
3. **P2: the native table ignored initial sort and controlled selection.** Initial properties were stored before change detection, so the first page used default order and no selection. Initialization now applies both, including the native sort indicator, with actual native table checks against intentionally reversed rows and a selected logical row ID. Reversing sort preserves that row selection.
4. **P2: initial tab selection and reactive titles were ignored.** Selection ran before tab children existed; the arrangement cache omitted titles. Selection is now applied after children are installed, titles participate in invalidation, and an uncontrolled selection is preserved where its child still exists. Actual NSTabView assertions cover initial second-tab selection and a later title change.
5. **P2: disabled containers and composite controls remained actionable.** Native buttons under disabled containers, table selection, disclosure headers and tab switches could still act; the checker also ignored disabled ancestors. One host tree calculation now supplies effective interaction state to the renderer, event dispatcher and checker. Native controls show disabled state and actions are fenced; re-enabling a parent restores its child. A failing probe confirmed all five mismatches before correction. Installed inspection then found that disabled tabs still looked active; they now expose disabled state, dim and disable their native header controls, while the delegate and host still fence actions.

6. **P2: disclosure titles were invisible.** AppKit’s disclosure-style button did not draw the assigned title. A real native title label now sits beside the expander, the button has its accessible name, and a toggle button type keeps the arrow consistent with its open state. Native checks cover labeled disabled disclosure and an enabled open/close counterexample; the installed UI confirms appearance.

## Coverage

| Boundary | Review and evidence |
| --- | --- |
| Local-model authority | SDK/source discovery, tool scope and read-only dispatch, current request attribution, exact-source preflight/review proofs, version checks, cancellation and saved-disabled receipts. Existing agent integration tests plus the new disabled-ancestor refusal/counterexample. |
| Runtime and sandbox | Worker startup/sequence handling, poisoning, QuickJS wrapper memory/stack/deadline/job/rejection limits, wire/tree validation, XPC watchdogs, separate check/active service identities, minimal entitlements and installer identity checks. Real worker tests deny foreign-file/network access and refuse loops, unavailable APIs and invalid trees. |
| Data and recovery | Alias translation to typed queries, exact schema/read/write scope, atomic edits, stale rows, operation-token replay, Undo ownership, revocation commit guard, draft isolation, history/portable copy and reconstruction. New schema/revocation probes plus existing data invariants. |
| Native UI | Renderer identity and child arrangement, form events, editing acknowledgements, table loading/search/sort/selection, live refresh, tabs, disclosure, canvas movement, disabled state, source/permission/history flows and import/export. New actual AppKit assertions and installed inspection. |
| Build and dependencies | Pinned upstream file hashes, reproducible SDK/examples, main app does not link QuickJS, both worker packages/signatures, source/resource identity and installation. Vendored engine internals are not claimed to have received a line-by-line independent security audit. |

## Verification

The initial probes produced 14 passing groups and three failing groups: schema read authority, shared revocation and controlled native state. A further disabled-control probe produced five specific failures. After repairs, all 17 native groups and 11 authoring groups pass, including the enabled-control counterexample. The full local suite completed successfully, including 650 core checks and the agent/grammar, SDK and native integration paths. Its stale packaged journeys were explicitly skipped; the fresh native product separately passed package/resource, installer and extraction checks. Later presentation-only corrections have a fresh release build, all 17 native groups passing, strict Swift lint and an installed visual recheck. Unchanged authoring, core and extraction evidence is reused under the focused verification policy. Only three repair areas were active: authority, revocation and native state. No unrelated product increment is being implemented.

## Installed result

The [synthetic receipt](../../../integration/evidence/2026-11-13-native-app-adversarial-review.json) retains exact code/log hashes and qualification scope. Final installed main UUID `C1206D73-F023-3CB9-8A3B-C052F9A93B38` matches the packaged product; both signed worker executables match their respective package bytes and strict signature verification passes. The final UI confirms exact-version approval, revoke/re-enable, saved three-row data, initial and reversed sort with retained selection, tab selection/titles, blocked actions and enabled counterexamples, disclosure titles/open state and wide/compact spacing. The narrowed window scrolls to its last control. No known finding from this review remains open; broader limitations below remain explicit.

## Limits

This is an internal adversarial review, not proof that every possible program is safe or correct. The previous actual local-model cases and recorded long-conversation generation failures remain valid: generated apps still require human behavioral and visual inspection. SDK capabilities are finite. External security review, production signing/notarization, VoiceOver, broader hardware/load testing and hostile-local-account security remain unqualified. No real business data is used.
