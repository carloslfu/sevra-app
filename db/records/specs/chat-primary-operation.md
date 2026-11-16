---
type: spec
id: 01m7e557d8k5f1xwp3t90c69rb
created: 2026-11-14T23:09:24.264197+00:00
updated: 2026-11-16T05:24:34.633001+00:00
summary: Chat-first workbook and mini-app operations through shared typed actions, durable human approval and native transaction receipts.
title: Chat-primary operation
status: implemented
---
# Chat as the primary operator

Owner direction: [[sources/notes/2026/11/chat-primary-operation]]. Implementation and measured checks: [[records/plans/chat-primary-operation]]. The runtime remains [[records/specs/programmable-native-engine]]; local authoring remains [[records/specs/local-model-native-apps]].

## Interaction contract

Conversation supplies business inputs, invokes actions and reports their outcomes. Native views display the same state and remain optional controls. Operating an app does not require opening its view, accessibility dispatch, pointer movement or keyboard simulation. The agent discovers operation families with `workspace_actions`, then supplies the declared arguments to `workspace_action`. Exact identities and versions come from inspection. Missing required business values must be asked for, not filled from guesses or incidental visual defaults.

The workspace catalog covers app inspection, named actions, existing inputs, row selection/activation, canvas movement, undo/redo and execution grants; record decisions; form inspection/submission; generated document edits; table schema/history, row insertion/update/deletion and undo; workflow execution, retry, cancellation and clarification; automation inspection/grants/pause; file intake, table mapping and reviewed updates; original/table/app/workbook exports; and Excel planning, example comparison, table use and checked app building. Existing tools still own evidence/search, calculations, proposals, app/space/definition authoring, history, navigation and conversation organization. OS permission dialogs, model installation and choosing which local files to attach remain native system interactions, not model-granted authority.

## Shared app operations

`Sevra.action(id, {title,description?,inputs,enabled?}, handler)` registers a business operation and returns the same async function an optional button calls. Inputs declare text, decimal, boolean, number, date or record identity, requiredness and finite choices. Decimal inputs are strings. The SDK validates declared inputs; the shared handler validates business rules, awaits transactions and returns a small result. No visual selection or field population is required for a named action.

Existing control-based apps remain operable through semantic `set`, `select`, `activate` and `drop` commands. Native dispatch checks current app version, mount identity, enabled/hidden ancestors, supported event and input type. Table rows resolve through the scoped broker; canvas movements use deltas. Bulk field filling runs the same validation in order. Table browsing, filtering, sorting and paging share their query state with the optional native view. These invoke the same handler and bound signals as the optional UI. A handler returning does not prove a business write: chat receives committed transaction receipts, handler/broker errors and current display state. New app authoring guidance requires explicit named operations; `run_action` synthetic checks exercise them in the signed isolated check worker.

The workbook session owns each enabled runtime rather than the visible view. Chat and the renderer share its state, data broker and device grant. Closing the workbook stops its sessions; source changes replace stale sessions. Inputs declared with `draftSignal` and committed rows survive reopening. Undo reverses the latest saved app transaction, with the existing row/schema fences. After Undo, `canUndo` is false and `canRedo` is true; `app.redo` restores that transaction. Repeated Undo cannot silently redo a change. A new successful write replaces Redo, while a refused action preserves it. The direction survives reopening and remains scoped to the exact app version. This is one reversible latest transaction, not a multi-step history stack. An ordinary signal is transient; restarting the app intentionally resets it. Inspecting a stopped app never executes its saved code. Explicit restart or an authorized mutation can start an already approved app. Before a conversational command, the session waits for pending work and saved drafts, refreshes the current workbook revision and lets subscriptions settle; saved chat receipts must not make the command stale.

## Authority, history and failure

The agent cannot synthesize a human approval. Enabling an exact app version, accepting/withdrawing/undoing a reviewed record, submitting a human form/clarification and enabling a device automation prepare an exact preview in chat. The run stops at that preview. The person types Confirm or Cancel approval. The host saves the human message, checks its conversation and ordering, and claims the exact pending preview before applying it. Preview, claim and result are append-only conversation receipts. Reopening preserves a pending preview; an interrupted claimed action is never replayed automatically. Changes to referenced definitions or targets require a new preview. Further work can continue in chat after confirmation.

Already authorized direct table edits use the existing atomic native data transaction implementation, including immutable versions, formula recalculation and inverse receipts. They retain AI/programmatic attribution and request lineage, not a fabricated human decision. Read-only requests cannot invoke mutations. App grants stay bound to this physical workbook, exact saved version and package digest; copying files cannot copy permission. Host-action retries within a model run replay a completed receipt or refuse an uncertain attempt. Cancellation revokes the active app session; changes already committed remain saved and must be inspected before retrying. Exports require a user-supplied destination, refuse overwrites and preserve workbook originals.

## UX and qualification

Excel attachment saves/indexes the original and prepares its import. Chat asks for the intended work; analysis, clarification and building are explicit conversational operations. Native import controls remain available. The composer and active-view context direct work back through chat, rather than instructing the person to fill screens.

This is an action-access contract, not proof that every model request succeeds or every generated app is correct. Saved apps can contain incomplete business rules or swallowed validation errors; receipts distinguish invocation from persistence. Authoring tests cover supplied cases. Current verification and the live-model qualification limit are recorded in the implementation plan. No active user UI was controlled for this task.


### Completion evidence

Every finished request records unresolvedActionFailure alongside its finish basis. Saved business journeys must have no unresolved failure and use completed_action; persisted state alone does not establish a truthful completion. Reporting can settle a malformed app.run only against the same operation: unambiguous nested envelopes match exact ID/version/action/inputs, and ordinary outer-envelope repairs preserve all supplied business inputs. SDK missing/mistyped-input correction uses the captured pre-invocation contract, requires zero writes and preserves every already-valid value. It never infers validation from an app-selected error code or message. Different transactions, actual handler refusals and partial writes retain their failure evidence. If a table has no selection handler, the native host can identify the exact current scoped row without dispatching an operation. A later successful named action can settle that failed preparatory selection only with a newly committed update to the same app version, table and logical row. Both receipts remain durable. Malformed calls remain refused and are never executed automatically.
