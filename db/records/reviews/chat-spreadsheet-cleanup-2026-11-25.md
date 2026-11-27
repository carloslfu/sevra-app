---
type: review
id: 01m8az3aa4k3rb8eg3wh46196j
created: 2026-11-26T03:41:28.772405+00:00
updated: 2026-11-26T11:07:25.162068+00:00
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

## Freeform scenario testing, November 26, 2026

The owner asked for many freeform ways people might start using Sevra, with every gap and error fixed and the tools kept generic. About 30 scenarios were written and run once each with the real model (34 scenarios, 41 turns, about 13.5 minutes): empty workbooks from one sentence (grooming appointments, expenses, habits, books, a CRM), CSV, pasted lists, text and PDF documents, Excel, dashboards, buttons, forms, checks and reminders, a mini app, edits and Undo, multi-turn follow-ups, vague requests and safety limits. First run: 13 passed, 7 gaps, 14 errors.

Fixes, each with no-model checks:

- `e53746d` (format 38): tables keep INTEGER PRIMARY KEY numbering, defaults, NOT NULL and UNIQUE on every later row from any path; AUTOINCREMENT accepted; `AS (expression)` becomes a formula column; chat dates are local; a table's sql name or title works where its id is expected.
- `a38c070`: table, chart and metric components take a read-only `query` for filtered live data; unused fields refused; the view guide teaches replace, remove and move.
- `a797084`: host lines for every table change with Undo; no false save claims; large deletions need the person's confirmation; the local date in every request; honest limits (no online connections, app saving needs the app).
- `b862842`: reminders, alerts and tool runs as automations in one step; Excel header rows; split deletions counted per request.
- `8692a93`: recovered failures settled; script tools tried once at save; the same refused call twice ends the request; date, title and total-row guidance.
- `5af1ea4` (format 39): harmless stray fields left out with a notice; replace merges with the saved component; unique column sets with INSERT OR IGNORE and ON CONFLICT.
- `affda2e`: a component's `size` now follows its title in the grammar. The model writes `id, type, title, size`, and size last had closed off the tool binding and chart style, which caused the remaining view failures.
- `f36c330`: an edit that changes nothing says what the component already shows; a placeholder sql tool name is ignored.

Re-runs, once each: after the first four fixes 13 of the 19 failing scenarios passed; after the rest, the expense tracker, habit tracker, CRM, appointments, low-stock and expense alerts, overdue invoices, reminders, delete-everything confirmation, bank and email limits all pass. The light set passed 11 of 11 on the final build. Open: the multi-turn sales chart (C2) varies between runs (once a no-op loop, now stopped by the repeat rule; once a static totals table and a total row against the guidance), and an overdue-invoices query counted cancelled invoices as unpaid. Both are model judgment, not tool errors. Transcripts are in the session scratchpad, not the repository.

## Freeform follow-up and business scenarios, November 26, 2026

The two open freeform items were fixed generically, then the owner asked for business-centred uses of the workbook. `540fa68` lists each category column's values in the request, so filters use the values a column really holds (the overdue-invoices query had counted cancelled invoices), flags a table copied from another as a static copy, and keeps the guide's examples generic. `ef2e481` rewrites today's date written into a saved query as `date('now')` and holds the first save of a summary copy in a request with a notice that a query stays current. After them the multi-turn sales chart (C2) charts its table live, says it is already a bar chart and adds a total metric, and the overdue invoices (C5) return the right three.

28 business scenarios were then written with expected answers computed from their fixtures and run once each (about 8 minutes of model time): receivables aging, payroll with overtime, tiered commissions, a purchase-order tracker from empty, job costing, weighted pipeline, double bookings, ticket resolution times, cash flow from pasted text, MRR and churn, inventory value, a quote builder and a mark-paid button (both pressed), cheapest vendor, budget against actual, PTO, on-time rate, a price raise as a draft, a Friday reminder, top customers, duplicate customers, quarterly sales tax, contract-end alerts, project hours, a three-turn revenue dashboard, bills due, gross margin and onboarding. 21 passed the first time. The rest, and the fix for each:

- **Tool-call markup in a reply** (PTO): the model closed its answer without the newline and wrote its basis inside the answer. The output parser now ends a string value at a closing tag followed by the next parameter. The grammar stays identical to upstream Splash, whose exact reference masks the checks compare.
- **Friday saved as Saturday** (reminder): the weekday was counted from Sunday. A weekly schedule whose own title, description or alert names weekdays it never runs on is refused with the ISO numbers, and the save confirmation says when it runs, such as every Friday at 16:00 (America/Bogota).
- **Later rows never alerted** (contract ends): a check fired only on the change from no rows to some. It now fires when it finds a row it did not find before, told apart by the check's first column, so each contract alerts once as it comes due, and a row that stays does not alert again. The state stays in the check's Source, with no format change. An alert with `{placeholders}` is refused, since it is fixed text.
- **Row numbers added up** (onboarding): a metric over the table's id gave 36 for 2 items left. A metric or chart that sums or averages a numbering column is refused with how to count instead.
- **A line chart drawn as bars** (revenue dashboard): reads now show a chart's default `chartStyle: bar`, which the model copied and never wrote before, and a chart titled as a line without `chartStyle: line` is refused.
- **Analysis choices** (on-time rate, bills due, onboarding year, PTO dates): the sql guidance now says a date without a year is in the year of Now, a row missing the value a calculation needs is left out of it, a period such as the next 2 weeks starts today with earlier rows named apart, and a value the request does not give stays empty.
- **A made-up table id beside a query** (PTO, re-run): it was refused, and the model made a copy table to satisfy it. A component with a query now leaves out a datasetID that names no table.
- **Fixed on the way:** `sevra automation-activation` added an empty check state to scheduled automations, so `check_automation_execution.py` had been failing since the check trigger landed.

Re-runs, once each, on the installed build: the PTO tracker (no markup; the dates it was not given are still filled in), on-time rate (BlueLine 100, FastFreight 75, RoadRunner 33.3 percent), the Friday reminder (saved for Friday, and the confirmation says so), bills due (the overdue bill named apart), onboarding (2026 dates, no metric over the id), contract alerts (a plain alert on a new-row check) and the revenue dashboard (the chart becomes a line, then month-over-month growth is added) all pass. The light set passed 10 of 11. `steps.script` failed on the model's own arithmetic: its script wrote `stock = ? * ?` with twice the reorder level and 2, so the stock became four times the level. That is not a tool error, and no generic check would catch it.

Open: the model still sometimes fills in exact dates the request did not give, and invents a definition id before saving (refused, then saved correctly).

## Root-cause fixes for the open gaps, November 27, 2026

The owner asked for a first-principles look at what was still wrong, then for all six gaps fixed. The rule used: a value in the workbook comes from the user or from a calculation. A correction first: the PTO scenario had not been re-run after its datasetID fix. Its latest run still filled in Ben's July dates and built a static copy of its summary.

- **Values not given:** the model made `start_date` NOT NULL, so it had to put a date on Ben's row. The sql guidance now says a column is NOT NULL only when the request gives it for every row, and a value keeps the detail given (a month with no day). When the answer-grounding check refused the made-up dates, the model deleted Ben's row. That refusal now says such a value is set empty, never fixed by deleting the row.
- **Copy tables:** a component without a query that names no table is refused, and the refusal now says to give the component a query, which follows the rows, rather than making a new table.
- **Check alerts:** a fired check names its new rows by their first column on its Source, in its result and on the automation page. A check whose first column repeats in the rows it finds now is refused when its automation is saved. The drafted alert's sentence stays the fixed text saved with the automation; adding names there would change the run integrity rules.
- **Line charts:** the rule that refused a chart titled with "line" is removed, because it also refused titles such as "Product line sales". A replace that changes nothing on a chart now names the other style, such as `chartStyle: "line"`.
- **Weekdays:** weekly schedules name their days, such as `["friday"]`, so nothing is counted. A new schedule with numbers is refused; one saved earlier with ISO numbers still reads. The English weekday-name check is removed.
- **Definition ids:** an edit base that names no saved definition saves as new, unless one of that kind already has the title, which the refusal names with its id. The save grammar now requires the content's kind, title and description; listing only title and description made the model leave kind out. A schema helper that dropped every `description` key also dropped fields with that name, and now keeps them.
- **The model's arithmetic** in `steps.script` stays recorded: no generic check knows the number meant.

Checked once each: sevra-checks 596, the grammar check with regenerated reference masks (ordinary prompt 7663/8448, authoring 10226/10240), the schedule preview and automation definition and execution scripts, `check_chat_sql.py` and `check_chat_run.py`. On the installed build, matching its packaged UUID: the Friday reminder saves for Friday with no refusal; the revenue dashboard draws its line chart in one edit; the contract alert saves after three refusals the model caused (placeholders, then a stray schedule field), each naming the fix, with no made-up id; the PTO tracker saves Ben's 5 days with empty dates and shows remaining days with a live query. The light set passed 11 of 11.

Open: the PTO tracker kept Ben's days but not the month, and its reply listed what was saved without the remaining days. The model still sometimes writes NOT NULL first and recreates the table after the insert fails.

