---
type: operational
id: 01m7e2jp7mc8maq59dx5359a6w
created: 2026-11-14T22:24:19.700159+00:00
updated: 2026-11-15T00:11:59.682627+00:00
summary: Implement chat as primary operator for workbook and mini-app actions, inputs, review and undo.
title: Chat operation coverage
---
# Chat operation coverage

## Direction and authority

Owner request: [[sources/notes/2026/11/chat-primary-operation]]. Chat is the primary operating interface. Visual spaces show state and remain usable optional controls. An operation is not complete merely because chat opens its screen. User-supplied inputs and explicit approvals must also work in conversation. OS-owned file/permission interactions remain OS operations; app actions must not manufacture OS grants.

## Implementation and acceptance

- [x] Inventory existing workbook, table, record, workflow, automation, import and mini-app operations and provide discoverable typed chat access to them.
- [x] Expose mini-app inputs/actions/results through the same running logic and data broker, including apps not currently visible. No coordinate clicks, alternate business rules or raw JavaScript eval tool.
- [x] Provide named SDK actions with typed inputs and structured completion; keep visual controls as clients of those same actions. Cover existing control semantics without requiring a visible renderer.
- [x] Support conversational review, enable/disable, workflow continue/retry/cancel, missing inputs, and undo with exact version/receipt fences and truthful attribution.
- [x] Keep current-request authority, read-only restrictions, cancellation, immutable versions, local device grants and reconstruction intact. Clarify or confirm consequential decisions in chat when needed, rather than redirecting to a button.
- [x] Update agent guidance and chat UX so inputs are requested by their business names and results are readable. Do not dump implementation details into user-facing flows.
- [x] Test ordinary operations plus stale versions, invalid inputs, read-only requests, failed handlers and cancelled execution. Exercise real sandboxed mini-app logic without UI clicks.
- [x] Run relevant integration checks, canonical SDK/schema checks, native build and required release suite; record exact evidence and remaining limits, preserving concurrent unrelated work.

## Findings

November 14: initial code trace confirms table edits are proposals; custom apps have a data broker and JS handlers but no conversational invocation; workflows queue without agent continuation. Native app sessions are currently owned by visible views. The core already provides immutable mutations, validation and Undo, so those paths will be reused.

## Final checkpoint

Implemented: chat supplies mini-app inputs, runs named actions and existing semantic controls, edits tables/documents, submits reviewed forms, operates workflows and automations, handles Excel conversion and exports, and completes exact human approvals and Undo in conversation. Optional native views share the app session and table presentation state. See the [[records/specs/chat-primary-operation]] contract and [machine-readable evidence](../../../integration/evidence/2026-11-14-chat-primary-operation.json).

Final fresh live run 08 passes with the actual installed local model and signed sandboxed worker: add Pencils quantity 3, edit to 5, ask for the missing Notebooks quantity without inserting a row, Undo to 3 and reopen. Both writes use the app's named action and produce committed transaction receipts. No renderer or UI events participate. The evidence retains the earlier failed attempts and the preceding passing run; this is bounded coverage, not a general success rate.

Verification covers 655 core checks, 18 signed native groups, 10 SDK checks, complete scripted agent checks, workflow and automation integrations, authoring/conversion checks, and 84 tool-grammar cases with 787 pinned reference masks. The full scripts/check.sh run passed its core/CLI/native prefix, then exposed outdated assertions and grammar fixtures plus an oversized prompt. The assertions now reflect conversational form submission and per-operation read-only authority; reference fixtures were regenerated from the pinned upstream implementation. Redundant parameter descriptions were removed without changing structural schemas, raising budgets or weakening validation. The failing stage and every remaining suite stage pass on focused rerun. Ordinary tools use 8435/8448 tokens; authoring uses 9791/10240. The final receipt-recovery change also passes the complete scripted agent suite.

The release build is packaged at output/native/Sevra Native Preview.app, main Mach-O UUID 039A908F-28BB-36CA-8E57-32EEE8862C92. Native resource/signature, isolated install/update/uninstall and extraction checks pass; one package attempt correctly refused while the live probe held inference, then was rerun after that probe exited. The running user app was neither controlled nor replaced. This package is newer than the separately qualified installed Excel checkpoint. No fresh visible UI, VoiceOver, external customer/hardware/security qualification or production notarization is claimed. OS-owned dialogs and model setup remain native; model interpretation can still fail even though the operation is available.

## Earlier verification

Implementation is present in the shared SDK, runtime session, core action catalog, agent dispatcher and native chat host. The contract is [[records/specs/chat-primary-operation]].

Focused checks completed: nine SDK tests and reproducible SDK/example bundles; direct row edits with formula recalculation, replay, stale row/schema rejection and Undo; scripted agent discovery/dispatch/replay, read-only refusal and real workflow execution; signed XPC mini-app operation without a renderer, including named writes, legacy input/button dispatch and restored Undo after reopening. Full regression is running. Additional cancellation, selection/canvas and corrected-action receipt checks are being incorporated.

The actual local-model chat probe was attempted with the signed worker and installed model. It refused with model_busy because another existing process owns inference. That process and the active app were not interrupted. No new natural-language success-rate claim is made from the scripted checks. The reproducible live probe is scripts/check_native_app_authoring.py --chat-live.

Release build, final suite result, commit and push remain pending.

November 14 implementation review: fixed silent disabled-app returns, added typed operation argument validation, made approval previews/claims/results durable and conversation-scoped, fenced old confirmation messages, restored the last native transaction after reopening, and preserved programmatic attribution when chat pauses an automation. The Excel attachment flow now asks for intent in chat instead of automatically moving into model analysis through native controls.
Later actual-model probe: after inference became available, the first ordinary inventory add request reached its step limit. Trace inspection exposed a stale worker revision after chat receipts, unclear decimal JSON encoding, and a bulk-fill handler outside the shared session. The revision now refreshes before commands, decimal inputs explicitly declare string encoding, and bulk fill runs in the shared session. The signed worker regression reproduces chat-message and draft writes between operations and passes. Ten SDK checks and eighteen signed native groups pass. A fresh actual-model run is in progress. The broad suite passed 655 core checks and earlier integrations, then found an outdated blanket read-only tool assertion; workspace_action now validates authority per operation and has explicit read-only refusal tests. The assertion was updated accordingly; the complete suite is being rerun.
November 14 local-model findings: fresh run 03 saved the requested add and edit through named actions but invented quantity 1 for an unspecified Notebooks quantity. Run 04 selected a review proposal for a direct edit, leaving the accepted quantity unchanged. Action input policies and tool descriptions now explicitly distinguish required values, direct app operation, source authoring and review-first requests. Run 05 saved add/edit, asked for the missing quantity, and restored the prior quantity with Undo, but its answers exposed another reporting defect: failed read-only lookups could remain in the mutation-failure ledger after a successful action. That classification is corrected and covered by a scripted regression. Workspace operation names are now constrained by the exact catalog enum, preventing confusion with an app-specific action name. Run 06 and packaged/full checks are the final candidate verification; no individual run is a general model reliability claim.