---
type: review
meta-type: conclusion
id: 01m84mc0f772a60cwwqap3k4f4
created: 2026-11-23T16:38:32.679342+00:00
updated: 2026-11-24T04:18:36.217043+00:00
summary: 'A Home counter request asked, refused and hit the step limit. Its causes were fixed and made general: buttons run saved tools, choices get defaults. Real requests pass 3 of 4.'
title: Home counter run review, November 23
---
# Home counter run review, November 23

The owner's direction: [[sources/notes/2026/11/defaults-and-step-limit]].

## The run

A new, empty workbook, with the local model, on the build of commit `6f6aaba`. Read from the workbook's own saved record: every call, its arguments, its result and the model's saved thoughts.

| Message | Steps | Time | Outcome |
| --- | ---: | ---: | --- |
| "Change my Home to show a big counter button" | 10 | 59 s | Asked which dataset to count and what style to use |
| The question, skipped | 1 | 12 s | Refused: it could not go on without the answers |
| "invent one and make it big, you figure it out" | 12 | 81 s | "This request reached its step limit" |

Home was unchanged. The workbook kept a Tasks table with ten invented rows. The request was within the app's reach all along: one `view.edit` on Home with a `metric` component does it.

## What was wrong

1. **The step limit was twelve.** It guarded time and nothing else: step twelve used 12,332 of 65,536 context tokens, and context has its own guard. The first turn used ten of the twelve steps to reach its question. Earlier plans record the same limit ending runs three times.
2. **The instructions told the model to ask.** "Never invent a value" and "ask for what is missing" drew no line between a business value and a choice about looks, names and placement. The model's own thought was "maybe I can use a default? No, I should ask."
3. **Skipping a question was a dead end.** The continued request became read-only and was told to explain the limit and not guess. The app also wrote "I decline to provide the requested information" as the person's message.
4. **The question could not be answered.** Its required field asked for a dataset in a workbook with none.
5. **The model took the chart route.** `visual.evaluate` makes a visual for the chat answer. Nothing said that Home is the view `home`, changed with `view.edit`, or that one number is a `metric` component.
6. **One error message stood for five faults.** Four attempts at an aggregate failed on `style: "gauge"` and were told to "use a category, compatible reducer, and measure".
7. **A table's id was refused as its definition,** with "A query's table definition changed". Creating a table returns only the id.
8. **A missing field surfaced as Foundation's own words,** "The data couldn’t be read because it is missing", twice.
9. **An empty workbook was not said to be empty.** Six steps across two turns went to searching for tables.
10. **The activity said little.** A call that created a table read "Query tables", every action read "Workspace Action", and the run ended under a lowercase "failed".

A view has no size setting and no button component. That is a limit of the product, not a fault of this run, and it is unchanged.

## What changed
- **Progress, not a count, stops a chat request** ([WorkbookAgent.swift](../../../Sources/SevraAI/WorkbookAgent.swift)). When an action fails with the same error a second time, the model is told what the action takes in place of the general advice. On the third, or after five failed calls in a row, the request closes: only `finish` is offered, and the model says what it did, what is saved and what blocked the rest. That account is the reply. The host adds one line for each task it could not finish, such as "Couldn’t finish saving the space.", in place of the raw errors ([ActionConfirmations.swift](../../../Sources/SevraAI/ActionConfirmations.swift)). The step count is a backstop at 64, whose last three steps belong to that closing answer. Excel conversion keeps twelve, since each of its steps is long. The stop message no longer says to narrow the question.
- **Choices get defaults** ([GeneralTools.swift](../../../Sources/SevraAI/GeneralTools.swift)). The instructions separate a business value, which is never invented and is asked for, from a choice, which Sevra makes and names in its answer. A table the workbook lacks is a choice too: the model creates an empty one with `sql` and does not ask which table to use, with `ask` or in its answer. A table made this way has no rows unless the person asks for examples. `ask` is for business values only.
- **Skipping hands the choice over** ([ConversationSurface.swift](../../../Sources/SevraCore/ConversationSurface.swift)). The button reads "Skip, you choose", the message reads "Skip this question. You choose.", and the request goes on with its original authority. It may not ask again.
- **Home and one number are in the instructions,** each shape written in the order the grammar makes the model write it. The view description says that Home is the view `home`, that it is changed with `view.edit` and `{id, expectedVersion, edits: [{operation: "insert", at, component}]}`, and that a count is a `metric` with `aggregation: "COUNT"` before `datasetID`. The chart instruction says its actions put a visual in the chat answer, not on Home. The view guide says a view has no button and no size setting.
- **A view edit takes what the model writes** ([SpaceEditing.swift](../../../Sources/SevraCore/SpaceEditing.swift), [Spaces.swift](../../../Sources/SevraCore/Spaces.swift)). An insertion that names no position goes last. A move still has to say where. A count needs no `y`, since it counts rows. A replacement with no `componentID` targets the component's own ID. An empty `text` or `title` on an edit that does not use it is ignored. A field that is refused comes back with the order to write an edit's fields in.
- **A refused save points at the edit** ([Tools.swift](../../../Sources/SevraCore/Tools.swift)). Saving a view whose title exists answers with the `view.edit` call to make, with that view's ID and version. Once the view is edited, the refused save no longer counts as an unfinished task in the reply.
- **Errors name the fault** ([VisualDefinition.swift](../../../Sources/SevraCore/VisualDefinition.swift), [DescriptorDecoding.swift](../../../Sources/SevraCore/DescriptorDecoding.swift)). An aggregate has one message for each thing that can be wrong, a chart lists every missing field, an unknown field is named, and a decoding failure says which field. `definitionID` may be left out of a chart written in chat and then means the table as it is now.
- **The activity says what happened** ([RequestActivity.swift](../../../Sources/SevraCore/RequestActivity.swift)). A step is titled by what it did: "Create table “Tasks”", "Change tables", "Make a visual". A read is "Done", not "Result saved". A run that could not finish says "Couldn’t finish".
- **A model job for this request:** `defaults.home_counter` in [check_chat_jobs.py](../../../scripts/check_chat_jobs.py), on an empty workbook. It passes when Home has a counter that counts rows, nothing was asked and no rows were made up.
- **A view has a button, and a metric or a button has a size** ([ViewButtons.swift](../../../Sources/SevraCore/ViewButtons.swift), [Spaces.swift](../../../Sources/SevraCore/Spaces.swift), [ContentViews.swift](../../../Sources/SevraApp/ContentViews.swift)), at the owner's word ([[sources/notes/2026/11/view-button-and-size]]). A `button` component names a table, and each press adds one empty row to it through the recorded write path, so a count of that table goes up by one. Undo appears beside the button after a press and takes that press back. `size` is small, medium or large on a `metric` or a `button`, and medium when absent. A button cannot be frozen in a snapshot. The model's schema, the view description and the view guide carry both, in the grammar's field order. The UI Catalog has a button story and a Home story with a large count and its button (`home.counter`). Superseded the same day: the button now runs a saved tool and size applies more widely; see Made general.
- **A saved or changed view keeps the model's summary** ([WorkbookAgent.swift](../../../Sources/SevraAI/WorkbookAgent.swift), [ActionConfirmations.swift](../../../Sources/SevraAI/ActionConfirmations.swift)), at the owner's word ([[sources/notes/2026/11/summary-above-confirmation]]). When a request saved or edited a view and nothing failed, the reply is the model's summary and then the host's line, such as "Updated space “Home”." Only the summary says what was chosen. A failure, a change waiting for approval, a cancelled action, a draft, reusable behavior and a native app are still told by the host alone. The summary passes the same checks as any other answer. After two refused summaries the host's line stands alone, so a request that saved cannot fail on its summary. Widened the same day to every save; see Made general.

The prepared header is 4,215 tokens, from 3,809: the instructions are 899, from 702, and `save`, which holds the view description, is 1,083, from 875. The button and the size added the last 70. Counted with `sevra-agent-checks --header-parts`, which loads only the tokenizer.

One rule changed that a core check had pinned: "layout positions are explicit" refused an insertion with no position. That check now expects the insertion to go last and still refuses a move with no position.
## Checks
Without the model, on a debug build of the changed source:

- **The failed run's calls, replayed through the command line** on a new workbook. The style fault, the missing category, the table id given as a definition and the chart with no `x` or `y` each return a message naming that fault. The same aggregate and chart with `definitionID` left out succeed. Home takes a `metric` over an empty table in one `view.edit`.
- **`sevra-agent-checks --progress-stop-checks`, new:** a repeated error brings help and then closes the request with an answer; a closed request whose writes failed ends in the model's account and one host line; a closing request may only finish; three differing failures leave the request open; a request that only reads is closed at the backstop, not failed.
- **`--space-action-checks`:** an edit written component first, with an empty `text` and no position, is taken and goes last; a count with no `y` reads 0 over an empty table; a move with no position, a total with no `y` and a `text` that carries something on an insertion are refused.
- **`--action-confirmation-checks`:** a refused save is settled by a later edit of that view, and the brief list names an unfinished task once. A changed view keeps the model's summary above the host's line, and a summary refused twice is dropped for the host's line alone. A view saved together with a draft stays host-only, as before.
- **`--space-action-checks`, the button:** two presses raise a count from 0 to 2 and taking one back leaves 1; a press works on a table written with a key and a default, as the model wrote one; only a button can be pressed; a button with no table, a size outside the three and a size on a text component are refused; a view with a button cannot be pinned. These checks were rewritten for the general button; see Made general.
- **The button, pressed in the UI Catalog** with a real click on `home.counter`: the count went from 6 to 7, the status read "Row added." and Undo appeared; Undo returned it to 6 with "Row removed." The first try showed the general "Operation ended" line after a press, which led to the two short status lines.
- **`sevra-checks`** passes 660 groups with the button and the size, and the default agent suite passes 60 groups before the stale tool schema fixture, whose size is now 32,795 bytes against the stored 32,318 because the schema gained the button and the size.
- **One pinned answer changed with the summary rule.** The calculation-inputs check expected a host-only reply after a comparison and a saved view. It now expects the summary, the comparison's inputs and then the host's line. The default agent suite passes 59 groups and stops at the stale tool schema fixture, as before.
- **`--conversation-surfaces`** expects a skipped question to continue with the full scope and the new message. **`--prompt-header-checks`** and **`--chat-checks`** pass.
- **`sevra-checks`:** 660 groups pass, with the layout check changed as described above.
- **Stored tool schemas: failing before this change.** `workbook-tools.json` is behind the current `propose_record`, whose `meaning` became a fixed set in commit `704f3d8` without the fixture. Regenerating it also regenerates the grammar reference masks, so it is left for its own change. The default agent suite stops at that last group.
- **`check_chat_sql.py`, `check_chat_run.py`, `sevra-preview-checks`** passed on the first round of changes and were not run again.
- **The model job harness's self-test** accepts the expected result of `defaults.home_counter` and refuses an untouched workbook.
- **The question form, looked at in the UI Catalog** at 450 points wide: "Skip, you choose" sits between Send answer and Cancel question without wrapping, and the skipped state shows "Skip this question. You choose." as the person's message. The activity titles and the "Couldn’t finish" label compile in the catalog build and were not looked at on screen.

With the model, on a release build of the command line tool, each run once. The first try at making the header refused on memory at 16.4 GB reclaimable against the 17 GB a load needs; nothing was forced, and the runs below came after the owner freed memory.

| Run | Header | Result | What it showed |
| --- | --- | --- | --- |
| `defaults.home_counter` | 4,042 | Failed, 9 steps | It asked nothing and created an empty table. Then one save and four edits of Home failed, and the progress stop closed the request. The reply was five raw error lines. |
| `defaults.home_counter` | 4,090 | Passed, 9 steps | A counter at the top of Home over an empty table. One edit failed for a count with no `y`. |
| Light set and `defaults.home_counter` | 4,108 | 11 of 11 passed; the counter failed, 4 steps | The eleven took 27 steps and 247 s. The counter request asked which table to count. |
| `defaults.home_counter`, `conversation.clarify`, `build.view` | 4,145 | 3 of 3 passed | The counter took 6 steps and 34 s with no failed edit. The clarify request still asked for the supplier, quantity and cost. |
| Light set and `defaults.home_counter`, with the summary rule | 4,145 | 12 of 12 passed | 37 steps and 265 s. The counter took 6 steps and 43 s. Both view requests ended in the model's summary and then the host's line, and no summary was refused. |
| Light set and `defaults.home_counter`, with the button and the size | 4,215 | 12 of 12 passed | 35 steps and 263 s. The counter job now also requires a button over the counted table and something large. It took 5 steps: read the views, create an empty Counters table, insert a large button, insert a large count above it. |

What the failures were, and the change each led to:

- **The grammar fixes the order of an edit's fields:** `operation`, `componentID`, `at`, `beforeID`, `component`, `text`, `title`. The model wrote the component and then reached for `at`, and the only field left to write was `text`. Each edit failed on "Unexpected insert fields: text" or on the missing position. The same order put `aggregation` before `datasetID`, so the first counter had none and would have added a column up. The shapes in the instructions now follow the grammar's order, and the edit takes what the model writes.
- **The closing reply was the host's list of errors,** because any reply with basis `completed_action`, `general` or `unresolved` is replaced by the host's outcome lines. A closed request now keeps the model's account.
- **Two instruction lines disagreed.** "Never create a table for a view" stood against "create it if it does not exist", and "for one missing value, ask in the answer" let the model ask which table. One run created the table and the next asked. The first line now says not to create a table of totals for a chart, and the other two say that a table the workbook lacks is created, not asked for.

The replies of the last run, as shown to the person:

- **The counter request:** "Added a "Total Records" counter button to your Home view. It's now the first item on the page, showing the count of all records. I created a Records table to track this." and then "Updated space “Home”."
- **`build.view`:** "The Purchasing view has been created with a table showing the Supplier Comparison data and a chart displaying total costs by supplier." and then "Saved space “Purchasing”."

The counter summary names the table it created and where the counter sits, which is what the person needs in order to change them. It also calls the counter a "counter button", in the request's own words. A view has no button, so that word is the model's and is wrong. The host's line under it is not affected.

With the button, the counter request's reply was: "I've updated your Home view with a big counter button. It includes a large count display showing "Total Clicks" and a large "Click Counter" button that adds a new row each time you press it. Both are linked to a new "Counters" table." and then "Updated space “Home”." Each claim in it is true of what was saved.

Evidence: `integration/evidence/2026-11-23-defaults-home-counter`, `-home-counter-fixed`, `-light` and `-reworded`, `integration/evidence/2026-11-23-summary-light` for the summary rule and `integration/evidence/2026-11-23-button-light` for the button.
## Not done
- **Not committed.** The build was packaged and installed from the working tree on `6f6aaba`, at the owner's word. The installed app's executable UUID, `9E210196-9A76-35B6-9469-CBAEEDE32E71`, matches the package, its signature verifies, and its prompt header is present at 4,215 tokens. The package reused the header the model runs had made, so the model was not loaded again. The installed app's own window was not opened: the replies were read from the command line tool, and the button was pressed in the UI Catalog.
- **Made general is installed, not committed.** On November 24, at the owner's word, the working tree on `480c7c5` was packaged and installed. The installed executable UUID, `93E75F7C-B777-3C74-ABF1-8A454C8C60C5`, matches the package, the CLI is byte-identical, the signature verifies and the prompt header is present at 4,429 tokens, reused without loading the model. The app's own window was not opened after this install.
- **The counter request did not put a number on Home** in its last two runs. It builds a working counter whose count shows under the button after each press, but not before a press or after reopening.
- **A failed opening in the command line keeps the reply to the host's lines.** `defaults.stock_overview` saved its view and then could not open it with no window, so its reply was that failure and the save line. In the app the view opens.
- **The summary's number check may send back a number the model chose,** such as "a table with 2 columns". It was not seen in these runs.
- **The model's summary is not checked for what a component is called.** Before views had a button, one run's summary called a plain counter a "counter button". The summary is checked for invented currency, unsupported numbers and claims of absence only.
- **A button does one thing.** A press adds an empty row. It cannot fill a column, add to a number or run a saved action, and the row it adds has no values, so a table with a date column gets no date. Done in Made general.
- **The button was not pressed in the installed app's own window,** only in the UI Catalog, which draws it with the same code over a synthetic workbook.
- **The first call often reads the request's own record.** In three of four counter runs the model meant to read the views and first read the saved record of the request itself, as an archive, as a reference list or as an item. Two of those calls failed. It costs one step and is not something this change introduced or fixed. Done in Made general.
- **The stored tool schema fixture** is left stale, as it was before this change.
- **The hint under an answered question** still reads "You can also reply with Answer:" after the question is closed. Done in Made general.

## Made general
At the owner's word ([[sources/notes/2026/11/general-behavior-not-the-example]]), the work above was reworked so that it serves any request, not the counter example. A review of the code found the button, parts of the instructions, the size setting, the field-order fix, the error wording, the summary rule and the tests fitted to that one request.

- **A button runs a saved tool** ([ViewButtons.swift](../../../Sources/SevraCore/ViewButtons.swift), [ToolButtonView.swift](../../../Sources/SevraApp/ToolButtonView.swift)). It binds with `definitionBinding: {tool: name}`. `arguments` sets some of the tool's inputs, and the person fills in the rest in fields beside the button. A press runs through the same path as the chat's `sql tool=` and `run tool=`, with the per-Mac grant, history and Undo. The values the button sets are shown under it, the rows a report tool returns are shown under it, and a press that fails, or a script action that could not run, is reported as a failure. A button saved by the earlier build, bound to a table, stays movable and removable and says it names no tool. The command line has `press`.
- **size** is small, medium or large on a table, chart, metric, text or button, and on a visual only when it is a chart.
- **A count is of every row,** past the 1,000 rows a total loads. A total of no values is 0, a blank cell is not a number yet, and text that is not a number is an error.
- **Every save keeps the model's summary** above the host's lines, unless a write failed, a change waits for approval or an action was cancelled. A later success settles a failure for the host's own lines loosely, by tool and target, so the summary uses a finer match, `intent`: a failed call counts as fixed only when a later call of the same tool did the same thing, the same tables written the same way, the same kinds of component put into the same view or the same tool saved. A refused repeat, whose first save stands, keeps the summary too. A failed edit of Home followed by a different edit of Home still keeps the reply to the host's lines. A summary that claims content was kept perfectly, verbatim or verified is sent back ([FidelityClaim.swift](../../../Sources/SevraAI/FidelityClaim.swift)); after two refusals the host's lines stand alone.
- **The instructions are building blocks.** The counter recipe and the line saying views have no button are gone. Defaults cover tables, tools and views the workbook lacks, and a value the user gives each time a tool or button is used is an input of the tool, not a question now. Rows go into a new table only when the request or a document gives them.
- **The field order shown to the model is the grammar's, everywhere.** `NativeTools.fieldOrder` lists every exact action's and every save kind's fields in the grammar's order; before, it listed required fields alphabetically, so `stock.move` and `view.pin` were shown in an order the grammar does not write. The view description lists a component's fields in order, generated from the schema. `--field-order-checks` compares `fieldOrder` with the grammar's `propertyOrder` on every schema and checks every shape and prose list the model is shown, the host's own refusals included, against the closest schema. It found the rule guide's `template.rule` example out of order.
- **Decode errors name the field** everywhere the tool layer reads a model's object, such as "edits[0].operation is missing."
- **A closed question drops "You can also reply with Answer:"**, and typed "Answer: decline" now cancels the question while "Answer: skip" hands the choice over, as the button does.
- **The host note about the request's own record** said "Use it directly", and in four of six counter runs the model read that record first. It now says the record is the request itself and need not be read.
- **Real requests in the model jobs:** `defaults.log_visit`, `defaults.mark_paid` and `defaults.stock_overview` join `defaults.home_counter`. Each presses the button it finds through the command line and checks the effect, and checks that the reply names what was chosen.
- **A tool keeps nothing itself.** Saving a tool whose statements read and change no table is refused, with what to do instead. The instructions say that what a tool records, such as a count or a log, goes in a table, and that a button shows only what its last press returned, so a metric or a table shows what it keeps. The notice after saving a tool no longer says not to build a view for it; it says a view's button can run it.
- **SQLite's own index is named for its cause.** `AUTOINCREMENT`, `UNIQUE` and a `PRIMARY KEY` on a column that is not INTEGER were refused as "cannot make indexes, views, triggers", which no statement had asked for. Each now says what to remove. The word in a quoted value passes.
- **The prompt header** is 4,429 tokens: instructions 1,028, `save` 1,170.

### Model runs of the real requests
Release builds of the command line tool, each run once, English. Evidence under `integration/evidence/2026-11-23-general-*`.

| Run | Header | Result | What failed, and the change it led to |
| --- | --- | --- | --- |
| `defaults.*` (`general-defaults`) | 4,322 | 1 of 4 | Two runs wrote `size` or `viewID` before `definitionBinding`, could not go back and repeated the call: the view description now shows a button in field order, and the error gives the order. `mark_paid` set `invoice_number: ":number"`, one button per row: a placeholder is refused, and one button serves the view. `AUTOINCREMENT` was refused as an index or a view. |
| `defaults.*` (`general-defaults-fixed`) | 4,357 | 2 of 4 | The counter saved a tool `SELECT 1 AS result` over no table: refused now. The visit log did all the work, but its fixed `CREATE TABLE` blocked the summary and the reply was only "Updated space “Home”.": the `intent` match. |
| `defaults.*` (`general-defaults-intent`) | 4,392 | 3 of 4 | The visit log kept its summary. The counter's `UNIQUE` column was refused as an index, so the model dropped every constraint: named now. The job counted the counter's starting row at 0 as invented: one row whose numbers are all 0 is state, not business data. Home had no number: the button line above. |
| Light set (`general-light`) | 4,429 | 11 of 11 | 34 steps, 225 s. |
| `defaults.home_counter` (`general-counter`) | 4,429 | Failed, 7 steps | Recorded, not run again. A counter table, a tool that adds one and returns the count, and a large button on Home. A press shows the count under the button, but Home shows no number before a press, and the model did not add a metric despite the line. |
