---
type: spec
id: 01m7ebth3kem18z80b38s5wraz
created: 2026-11-15T01:05:53.779633+00:00
updated: 2026-11-15T03:21:07.139799+00:00
summary: Chat-customizable Home with live app views, a useful default, attention and recovery.
title: Home working overview
status: implemented
---
# Home as a working overview

Owner direction: make Home useful by default, customizable through chat, and able to use live mini-app capabilities; implement end to end and verify. This continues [[records/specs/chat-primary-operation]] and [[records/specs/programmable-native-engine]].

## Design and implementation

Home answers where work stands and provides a place to resume. Keep conversation, navigation, approvals and recovery in the native shell. A small default shows attention, continued work and pinned spaces; it does not list every table and file. Existing authored layouts remain intentional. Empty Home offers a concrete chat entry point. No automatic rearrangement of authored layouts.

A live app component binds to an existing app space, uses its workbook-owned session and exact-version grants, and displays the same native interface. Layout edits never duplicate business data or grant app execution. Missing or disabled apps have recoverable states. App updates flow through the binding. Multiple views must subscribe independently without stealing renderer callbacks. Snapshots cannot pretend to freeze running programs.

Home edits use existing versioned edit_space, with history and an explicit reset operation. The layout editor and app menu expose the same operation. Chat schemas and guidance describe the live binding. Pending decisions remain discoverable if their authored section is removed. Workbook tables and all files stay reachable through existing navigation/search.

## Acceptance

- [x] Versioned live app composition, invalid binding and stale edit refusal, history/reset/reopen/reconstruction.
- [x] Shared app runtime and independent renderers; data and chat actions stay synchronized, grants stay explicit.
- [x] Default, empty, customized, disabled/unavailable and constrained native layouts reviewed.
- [x] Chat tools and real local model customization checked with a disposable workbook.
- [x] Required checks, native package, commit/push and hosted CI.

## Initial findings

Implementation started. No completion claimed. Preserve the active user app; use an isolated synthetic workbook and candidate process for native review.

## Earlier verification checkpoint

- Core suite: 656 checks passed before the final recent-document refinement. Signed native runtime: 18 groups passed, including two renderers sharing one session and detaching one without disconnecting the other.
- Native isolated candidate UUID 5E2B1CD1-29A8-33CF-BA22-C0A014150FE2: Home-to-app data continuity and Undo passed. Arrange Home in chat focused and filled the composer. Disabled access stayed explicit. The review exposed technical table-creation observations in Continue working; the next candidate filters that projection to actual documents/files and accepted notes.
- The real local-model Home probe initially refused model_busy because another existing process owns inference. That process and the active user app remain untouched. Retain this failed attempt; retry only when inference is available. Scripted chat checks cover composition/reset/read-only refusal separately.
- The first broad check stopped on a missing token argument in a new test. Corrected, and the required suite is running again.

## Earlier chat qualification repairs

The fresh native probe exposed repeated insert attempts with an outer title instead of component.title. The tool grammar now refuses that combination, while ordinary rename/title edits remain legal. Invalid layout edits name the unexpected and allowed fields. A new scripted request also exposed that the explicit read-only guard recognized a whole sentence only; it now recognizes an instruction beginning with "Explain only" followed by its topic. The Home reset test confirms no mutation before the later explicit reset.

The complete agent and reference-grammar checks pass after these repairs, including 84 actual-tool grammars and 787 reference masks. Shared tool prose was shortened without raising the existing prompt gates: ordinary 8448/8448 and authoring 9804/10240 tokens. Earlier wider schema attempts exceeded the prompt gate and were rejected; those are not the shipped schema. The final actual-model retry waits for an existing process to release inference. The active installed app remains untouched.

## Accepted Home checkpoint, November 14

The implemented Home is a working overview with a useful default, chat customization and live mini-app bindings. The default surfaces attention, continued work and pinned spaces; an empty workbook offers a concrete chat entry. Chat and native layout controls use the same versioned edits. A binding shares its original app, data, access grants and runtime; removing it only removes the view. Native navigation, pending decisions, history and Reset Home remain recoverable. An independent subscription registry and shared input revision clock keep Home, the full app and chat synchronized.

The [acceptance evidence](../../../integration/evidence/2026-11-14-home-working-overview.json) records code commit `b1557b6ac6e0ccd0ba8a19dc70dae740f7723fe6`, source identity, exact results, retained failures and limits. All 399 source files in the actual-model runtime manifest match that commit. Concurrent Excel business work was excluded using a frozen ordinary candidate directory; unrelated working changes remain untouched.

A fresh five-request walkthrough with the pinned local model passed: embed Stock room on Home, add Pencils quantity 3 through chat, move the live app first, remove its view while retaining the app/data, and reset Home. Every saved Home version preserves unrelated sections; the final record and reopened workbook are correct. No failed writes occurred. Six recoverable read-tool errors remain, and individual requests took about 27 to 94 seconds. This is bounded actual-model evidence, not universal or first-attempt reliability.

The full `bash scripts/check.sh` run passed 656 core checks, 18 signed native groups, 10 SDK groups and the preceding CLI/integration/authoring checks before stopping at the new explain-only regression. The repaired full agent/reference-grammar rerun passed, including 84 actual-tool grammars and 787 reference masks, and every remaining performance, desktop, link and db check passed. Ordinary and authoring prompt gates stay at 8448/8448 and 9804/10240. The final optimized package, complete packaged-resource/missing-model/refusal checks, isolated install/update/conflict/uninstall checks and packaged extraction passed. Changed Swift files pass strict formatting. [Hosted Checks](https://github.com/carloslfu/sevra-app/actions/runs/43666871100) passed on the exact code commit. This documentation-only acceptance adds no code change to that qualification.

Native review used a separate `com.sevra.home-review` app and synthetic workbooks. Empty, default, customized, disabled/failing app and wide/821-point constrained layouts were inspected, along with real Home/full-app data continuity, Undo, chat focus, preservation of an unsent draft and default reset. Reviewed main UUID is `31276427-F1B6-3868-A290-1E49AC9C2E5F`; final packaged main UUID is `F41F2AB4-DEBD-3CFA-908A-687E0EC0D602`. Only chat constraints/guidance, explicit read-only handling and precise layout errors changed after visual review, so unchanged UI evidence is reused. The review process was closed. The active installed app was not replaced or controlled; the final qualified package remains a separate local build. No VoiceOver, system-setting, additional-hardware or production-notarization qualification is claimed.
