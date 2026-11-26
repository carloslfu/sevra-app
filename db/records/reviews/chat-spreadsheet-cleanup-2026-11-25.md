---
type: review
id: 01m8az3aa4k3rb8eg3wh46196j
created: 2026-11-26T03:41:28.772405+00:00
updated: 2026-11-26T03:41:28.772405+00:00
summary: Removed inventory-first leftovers (stock ledger, movements, receiving, stock thresholds, quote guard) and added general saved-tool actions and check-triggered automations.
title: Chat-spreadsheet cleanup
---
# Chat-spreadsheet cleanup, November 25, 2026

Authority: [[sources/notes/2026/11/chat-spreadsheet-cleanup]]. Product loop: [[sources/notes/2026/11/chat-and-spaces-product]] and [[records/specs/product]] ("Product loop").

Sevra's code carried machinery from its inventory-first and evidence-first stages that the chat-spreadsheet loop does not need: a stock ledger, stock movements and balances, a receiving template, stock threshold automations and a supplier-quote answer guard. They were removed, and the two jobs they did in a fixed domain were rebuilt as general features. Pre-1.0 policy applies: workbook formats 34, 35 and 36 refuse older development workbooks, with no migration.

## Removed

- **Stock threshold automations** (commit `c80143d`, format 34): the inventory condition engine, its six `condition_*` tables, the rule template and guide, the threshold trigger in the editor, the `condition-*`, `condition-preview` and `inventory-at-batch` CLI commands, and their checks and scripts. Retired specs: [[records/specs/condition-dispatch]], [[records/specs/condition-transitions]], [[records/specs/condition-transition-inputs]], [[records/specs/inventory-condition-consumers]], [[records/specs/inventory-event-state]].
- **Stock movements, balances and receiving** (commit `08d56be`, format 35): opening balances, movements and their direction reviews, the `effects` and `bases` tables, the stock ledger tables in chat `sql`, the `stock.move`, `stock.balance` and `template.receiving` chat actions, the receiving and movement action primitives, the `balance`, `opening`, `movement` and `receiving-template` CLI commands, the receiving form in the layout editor, and the `inventory-basis` business events.
- **Supplier-quote answer guard**: the cost qualification that ran on every answer.
- **Sample workbook stock**: Willow Workshop now holds the supplier quotes, the Supplier comparison table and Home. Its welcome suggests chat requests on that table.
- **Chat jobs** `read.stock`, `build.rule` and `build.rule_for_workflow`.

## Generalized

Commit `f2cae08`, format 36.

- **Saved tools as actions.** The `tools.run` action primitive runs any saved tool with its declared inputs, through the same recorded, undoable path as a view's button. Workflow steps, forms and chat `action.preview`/`action.prepare` can run one. `records.draftDocument` remains the other primitive.
- **Check-triggered automations.** `check-drafts-v1` starts an automation when a saved read-only check (a SQL tool with no inputs ending in a SELECT) goes from no rows to some rows, and again only after it has returned none. The state is kept in `automation_checks`. It runs while the app is open, about ten seconds after a workbook change or every minute otherwise. An automation can run a workflow or draft an alert for review. The editor offers "On a schedule" or "When a saved check finds rows".

## Verification

No-model checks: all default `sevra-checks` groups (572 passed), `sevra-agent-checks` with field-order, space-action, prompt-header, chat, sql-tool, action-confirmation and saved-action groups, `sevra-automation-ui-checks` (21), `sevra-preview-checks`, the Splash grammar check and the version-asserting scripts. New groups: `--tool-actions` (6) and `--check-automations` (5). The automation editor was reviewed in the UI Catalog in both trigger states, including the empty state with no saved checks.

Not run: a model run of the light chat jobs, because the installed app had its model loaded and a second model would break the one-heavy-process rule; the installed app has not been rebuilt.

## Known limits

- A check automation is pinned to an exact version of its check; editing the check needs the automation's check picked again.
- The first check after enabling counts rows already present, so it fires at once if they exist.
- Changes while the app is closed or the automation is paused are not seen as a transition.
- Overlapping runs of one check are refused as stale rather than ordered.
- Check occurrences reuse the `calendar` causal root kind.
- Chat `save tool` makes every input required; optional inputs need a saved definition.
- Older records and the verification register still describe the removed systems as dated history.
