---
type: review
id: 01m8az3aa4k3rb8eg3wh46196j
created: 2026-11-26T03:41:28.772405+00:00
updated: 2026-11-26T05:42:52.112371+00:00
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

Model run, after the installed app released its model: the light set (11 jobs, Splash 1.7.3, one run each, 156 seconds) passed 11 of 11 on the first run with the cleanup's release CLI. One passing answer was wrong: read.supplier_comparison said Cedar Tools has the lower total at 24, when Oak Supply is 24 and Cedar Tools 27.5. The difference and percentage were right, and the job only checks that Oak Supply is named. The installed app has not been rebuilt.

## Follow-up: automations that follow their check and run tools

Format 37. The definition policies are now `calendar-v1` and `check-v1`, since an automation no longer only drafts.

- **The check is followed by its logical ID** (`check: {mode: live, logicalID}`), like a saved filter. Every evaluation validates the latest version again as read-only with no inputs, and a check that was removed, writes or takes inputs makes the automation wait with that reason until it works again. Each change records the exact check version that ran. A check whose statements changed starts fresh, as if just enabled: its rows fire once even if the old rule had found rows, because the person changed the rule. A description-only edit keeps the state. The editor picks the check by name and the list shows its current name.
- **Rows already present at enable fire at once.** This was kept on purpose: a person who asks to be told when a part is below its reorder level wants to know about the parts already below it. The editor, the automation's page and the chat confirmation now say so.
- **Missed transitions.** The earlier limit was wrong: the check state is kept per automation across pauses, resumes and restarts, so the first evaluation after a resume or reopen fires once for rows that appeared meanwhile, and nothing for rows that came and went. A check now covers it.
- **Workflows with saved tool steps can be automated.** The enable notice, shown in the editor after Preview, on the automation's page and in the chat confirmation, names the tools and says their changes apply without review and each run keeps an Undo. Workflow runs show a tool step's result with its Undo. Local AI permission is unchanged.

## Known limits

- Overlapping evaluations of one check, possible only between the app and the CLI, are refused as stale. This cannot double fire, since the refused one commits nothing, and cannot lose a change, since the next evaluation compares with the saved state again. The refused one shows its message as the status until the next check.
- A fired request that is cancelled by a pause before it is dispatched is not offered again while the check keeps finding the same rows. The native owner dispatches in the same step as the check, so this needs a pause in between.
- A workflow's tool step pins the exact tool version, so editing that tool stops the automation's workflow with a stale-tool message until the workflow is saved again.
- Check occurrences reuse the `calendar` causal root kind.
- Chat `save tool` makes every input required; optional inputs need a saved definition.
- Older records and the verification register still describe the removed systems as dated history.

## Follow-up fixes, November 26, 2026

Each open item was checked for whether it was real and fixed for the person using it.

- **Automations** (`7bd8661`, format 37): a check automation follows its check by name, validates the latest version each run and starts fresh when the query changes. A check that already finds rows starts once when enabled, and the editor and chat confirmation say so. Automations can run workflows with saved-tool steps, and enabling one names the tools and says their changes apply without review, with Undo in Workflow runs. Policies are `calendar-v1` and `check-v1`. Not real: changes while the app is closed or paused are caught on reopen (now tested), and overlapping check runs cannot fire twice or miss.
- **Chat tools** (`f1ed798`): `read` names everything with `ref`, so a model that means a kind is no longer forced to pick an item, and `read kind=view` returns one view. The view guide says to save a tool first when none fits a button. A component missing its table says to create it when none exists. Chat-saved tools can have optional inputs. Only visual and image components take `visual` in the grammar. An insert next to a comparison column joins it when there is room.
- **Interface** (`ec4f6f6`, reviewed in UI Catalog captures): the automation page fits the pane, a check automation shows its check instead of an empty calendar, the editor reads "starts, then runs", tool forms run from one named button with readable labels and Undo, and "New prose" and "physical workbook" are gone.
- **Model runs**, one each, Splash 1.7.3: `defaults.home_counter` and `defaults.mark_paid` passed (both had failed before: a metric with no button, and a read loop). The light set passed 11 of 11 on the first run. In `safety.document_instruction` the model first tried a definition read for a document and then read it correctly.

Open: a workflow's tool step still pins the exact tool version, so editing that tool stops its automation with a message until the workflow is saved again.
