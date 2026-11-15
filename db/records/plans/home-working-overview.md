---
type: spec
id: 01m7ebth3kem18z80b38s5wraz
created: 2026-11-15T01:05:53.779633+00:00
updated: 2026-11-15T01:19:41.617770+00:00
summary: Chat-customizable Home with live app views, a useful default, attention and recovery.
title: Home working overview
status: reviewed
---
# Home as a working overview

Owner direction: make Home useful by default, customizable through chat, and able to use live mini-app capabilities; implement end to end and verify. This continues [[records/specs/chat-primary-operation]] and [[records/specs/programmable-native-engine]].

## Design and implementation

Home answers where work stands and provides a place to resume. Keep conversation, navigation, approvals and recovery in the native shell. A small default shows attention, continued work and pinned spaces; it does not list every table and file. Existing authored layouts remain intentional. Empty Home offers a concrete chat entry point. No automatic rearrangement of authored layouts.

A live app component binds to an existing app space, uses its workbook-owned session and exact-version grants, and displays the same native interface. Layout edits never duplicate business data or grant app execution. Missing or disabled apps have recoverable states. App updates flow through the binding. Multiple views must subscribe independently without stealing renderer callbacks. Snapshots cannot pretend to freeze running programs.

Home edits use existing versioned edit_space, with history and an explicit reset operation. The layout editor and app menu expose the same operation. Chat schemas and guidance describe the live binding. Pending decisions remain discoverable if their authored section is removed. Workbook tables and all files stay reachable through existing navigation/search.

## Acceptance

- [ ] Versioned live app composition, invalid binding and stale edit refusal, history/reset/reopen/reconstruction.
- [ ] Shared app runtime and independent renderers; data and chat actions stay synchronized, grants stay explicit.
- [ ] Default, empty, customized, disabled/unavailable and constrained native layouts reviewed.
- [ ] Chat tools and real local model customization checked with a disposable workbook.
- [ ] Required checks, native package, commit/push and hosted CI.

## Findings

Implementation started. No completion claimed. Preserve the active user app; use an isolated synthetic workbook and candidate process for native review.

## Verification in progress

- Core suite: 656 checks passed before the final recent-document refinement. Signed native runtime: 18 groups passed, including two renderers sharing one session and detaching one without disconnecting the other.
- Native isolated candidate UUID 5E2B1CD1-29A8-33CF-BA22-C0A014150FE2: Home-to-app data continuity and Undo passed. Arrange Home in chat focused and filled the composer. Disabled access stayed explicit. The review exposed technical table-creation observations in Continue working; the next candidate filters that projection to actual documents/files and accepted notes.
- The real local-model Home probe initially refused model_busy because another existing process owns inference. That process and the active user app remain untouched. Retain this failed attempt; retry only when inference is available. Scripted chat checks cover composition/reset/read-only refusal separately.
- The first broad check stopped on a missing token argument in a new test. Corrected, and the required suite is running again.
