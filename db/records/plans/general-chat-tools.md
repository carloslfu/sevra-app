---
type: operational
id: 01m7qrcqqzh4qqr92a8frch1ze
created: 2026-11-18T16:38:43.199010+00:00
updated: 2026-11-26T03:41:49.553018+00:00
summary: Seven general chat tools (SQL on a scratch copy, sandboxed code, workbook tools) and a prompt header made at build time. Built, looked at, and updated in the app between two headers.
title: General chat tools and a pre-read prompt header
---
# General chat tools and a pre-read prompt header

Owner direction: [[sources/notes/2026/11/general-tools-direction]], continuing [[sources/notes/2026/11/chat-tool-routing-direction]]. Evidence: [[records/research/chat-tool-selection]]. This plan replaces [[records/plans/native-chat-prompt-routing]].

Status: built, including the prepared header (H1 to H4) and phase 5, at the owner's word to build the whole plan, [[sources/notes/2026/11/general-tools-whole-plan]]. On November 20, 2026 the interface look fixed the chat Undo row and three export faults, and H4's in-app update between two builds whose headers differ passed. The model is offered `search`, `read`, `sql`, `run`, `save`, `ask` and `finish`, and nothing else in chat: on November 19, 2026 the owner made them the only chat tools and had the old way removed, [[sources/notes/2026/11/general-tools-only]]. See [The build so far](#the-build-so-far) for what was built, measured and left out, and [Open items for the owner](#open-items-for-the-owner) for what waits on him. Implementation started on November 18, 2026. The same day the owner chose a faster test loop: [[sources/notes/2026/11/fast-loop-direction]], and asked for the tools in the app and the whole plan done: [[sources/notes/2026/11/general-tools-in-the-app]]. [The test loop and the order](#the-test-loop-and-the-order) governs where a phase section says otherwise.

The owner confirmed the plan's three summary points and five proposals as written on November 18, 2026: [[sources/notes/2026/11/general-tools-confirmation]]. He then changed how the header is delivered: [[sources/notes/2026/11/prebuilt-header-direction]]. He authorized implementation on November 18, 2026: [[sources/notes/2026/11/general-tools-implementation]]. That note also lists what the authorization does not cover.

Terms used below:

- A **decision** is one model call that picks a tool or answers. On the test Mac it costs about 4 seconds.
- A **rule Source** is a saved Source of kind rule with status accepted. The write path requires one before it records a change as made by the AI ([DecisionAttribution.swift](../../../Sources/SevraCore/DecisionAttribution.swift)).
- An **evaluation** is one uninterrupted stretch of JavaScript between two host calls.
- The **header** is the fixed start of the prompt: the instructions and the tool schemas, identical for every ordinary chat turn.
- A **restore point** is engine state saved at a position in a prompt. A later request that starts with the same tokens resumes from it and does not read them again.
- The **model pack** is the pinned set of model files the app uses, named by repository and revision. The **assembly key** is the digest of the record that model preparation writes for it.
- A **tool profile** was a host setting that selected the old tools (`current`) or the seven (`general`). The owner had it removed on November 19, 2026. Earlier sections that name a profile are history.

## Decisions

Decided by the owner, in his words in the notes:

1. **General tools.** Chat works through a few general tools. The model writes SQL and code instead of calling many fixed, single-purpose tools.
2. **SQL writes directly.** Model-written SQL can change workbook data with no approval step in between.
3. **Arbitrary code, sandboxed.** The model can run code it writes, inside a sandbox.
4. **Per-workbook tools.** A workbook can carry its own tools, set up by its user. They are listed by name and loaded when needed, like the workbook's views and apps.
5. **The header is calculated ahead of time and restored when the engine starts.** In his words, it is calculated "during development, before shipping it" and restored "when it starts for real and in dev". For a user in production there is no fallback, and tests before release prove the match.
6. **Earlier rules are replaced.** He confirmed the direction after hearing that the specifications forbid model-authored SQL and generated code. The full list in [What this replaces](#what-this-replaces) is the agent's.

Said in the agent's summaries during planning. The agent reads the owner's "Confirm all" of November 18, 2026 as covering them, though the question he answered named only the proposals: [[sources/notes/2026/11/general-tools-confirmation]].

- **S1. No router.** No text matching and no extra model call chooses tools.
- **S2. No business concepts in the built-in tools or the shared instructions.** Inventory, receiving and quote comparison leave both.
- **S3. No built-in tool groups.** Anything loaded on demand is something the workbook holds, or a guide.

Proposed by the agent, and confirmed by the owner as written in the same note, except P4. Each is marked where the plan depends on it:

- **P1. Seven built-in tools:** `search`, `read`, `sql`, `run`, `save`, `ask`, `finish`.
- **P2. Table changes count at once, and no approval step is added anywhere.** A change to a table made by `sql` or `run` is accepted data, attributed to the request that asked for it, and can be undone. A table draft that waits for acceptance is made only when the person asks for one. `save` keeps what each kind does today: a document or record written by the model is saved as a draft, a view or tool is saved ready to use, and an app is saved disabled until the person enables it.
- **P3. The sandbox reaches this workbook only.** No network, no other files, no other workbook. A file leaves the workbook only to a path the person typed in that request, or through the save panel.
- **P4. Replaced.** The owner first confirmed a version that made the header during setup on each Mac. He then replaced it with decision 5 as it now reads: [[sources/notes/2026/11/prebuilt-header-direction]].
- **P5. Code that arrives from elsewhere needs enabling.** A tool that came inside a copied workbook does not run on this Mac until the person enables it there, as apps already work. The permission step for apps is unchanged.

Proposed by the agent after the header direction changed. The owner's "Build it all. Complete the whole plan, end to end." of November 19, 2026 is read as confirming them as written: [[sources/notes/2026/11/general-tools-whole-plan]].

- **P6. The app has no code that computes a header, and a source build pays for that with extra steps.** Not in setup, not in a repair action and not after an update. So after the model download, and again after any change to the prompt, a tool schema, the engine or the model, a developer runs the install command or the header command. Until then the app says so and chat is unavailable. Phase H3 depends on this.
- **P7. A release claims only the Macs it was tested on.** The shipped header is used on every Mac the app runs on. A release's published requirements list only the Apple chips where the header tests passed. Phase H4 depends on this.
- **P8. Only ordinary chat gets a prepared header.** Specialized phases keep reading the start of their own prompts when they run. A second prepared header for them would roughly double what the app carries. Phase H3 depends on this.
- **P9. Chat needs the engine's disk cache.** On a Mac below the engine's free-space floor, or with the cache folder on a volume that is not local, the header cannot be taken back, so the local AI does not start there. It starts there today. Phase H3 depends on this.

## Why

The measurements are in the research record. Three facts decide the shape.

- **Model decisions are what cost time.** Schemas in a resumed prompt cost close to nothing. One piece of code can search, read and compute in a single decision.
- **Most tools are narrower than the product.** Counted for this plan from the 59 ordinary chat tools listed in [[records/plans/native-chat-prompt-routing]]: 5 hard-code inventory, receiving or quote comparison, 4 are narrow helpers a query replaces, 25 are one tool per variant of the same thing and 5 are a fixed layout language beside programmable apps. Twenty are already general.
- **The machinery exists.** The workbook is SQLite, the app embeds a JavaScript engine for mini apps, and a recorded write path with Undo already serves app code and table edits. Chat reaches them only through fixed tools.

Draft schemas for the six tools other than `finish` count 554 tokens as compact JSON with the selected tokenizer, against 7,305 schema tokens in an ordinary first decision today. `finish` is 191 in that form. The drafts and counts are retained: [draft-tools.jsonl](../../../integration/evidence/2026-11-18-general-tool-schemas/draft-tools.jsonl) and [counts.json](../../../integration/evidence/2026-11-18-general-tool-schemas/counts.json).

No published evaluation covers this local model writing SQL and JavaScript. That is what the real-model gates in every phase measure.

## Scope

In scope: the ordinary chat tool list and instructions, the SQL and code layers behind them, workbook tools, the prompt header, and the step that makes the header in both packaging scripts.

Not in scope:

- **The inventory ledger in the core.** Stock is built into the app below the tool list: the `bases` and `effects` tables, the inventory event family, the only condition trigger for automations, the Receive delivery button, the automations and workflow screens, CLI commands and their checks. This plan removes inventory from the built-in tools and the shared instructions. It reaches the ledger through two read-only tables and the workbook's own saved actions. Turning the ledger into ordinary tables is a separate plan.
- **Specialized phases.** Excel conversion, the independent app review, the direction reviews in front of a stock movement and a saved action, workflow interpretation, preparing a workflow answer, and history summaries keep their own prompts and tool lists.
- **The engine.** No change to Splash is made from this repository.

## Design

### The seven tools (P1)

| Tool | What it does | Replaces |
| --- | --- | --- |
| `search` | Finds documents, records and earlier conversation. | `search`, `history_search` |
| `read` | Reads one thing by ID: a document or record, a page of a saved result, a view, an app, a workbook tool, an automation, or a guide. | `read`, `references`, `lineage`, `tool_result`, `history_read`, the read tools for apps, definitions, workflows and view history, and the starter templates as guides |
| `sql` | Runs SQLite statements over the workbook's tables. Reads return rows. Changes apply at once and are recorded. With `draft`, changes are saved as a proposal instead. | The table read helpers, `calculate`, `compare_rows`, the table proposals and the table operations |
| `run` | Runs JavaScript in the sandbox, with functions for SQL, search, reading, exact numbers, files, charts, navigation, apps, workflows and undo. | File, import, Excel, chart, app and workflow operations, navigation tools |
| `save` | Saves a named thing in the workbook: a document, a record, a view, an app, a tool or a definition. | `draft`, `propose_record`, `publish_result`, the view and app save tools, `save_definition`, `save_template` |
| `ask` | Asks the person a structured question. | `request_input` |
| `finish` | Answers, with citations and any chart captures. | `finish` |

Short schemas are displayed. Where a strict shape matters, the grammar enforces it without displaying it, using the split between the displayed tool list and the executable grammar that [NativePreparedRequest.swift](../../../Sources/SevraNativeAI/NativePreparedRequest.swift) already has. `save` gets the strict shape for a kind once the model has read that kind's guide.

**How the model learns the functions, the catalog and the guides.** The header carries a function index, one line per function with its inputs, the catalog tables with their columns, and the names of the general guides. Guides with examples are read on demand with `read`. Guides for one business case, such as the receiving and low-stock starters, are named inside the definitions guide and not in the header. The ledger's two tables are described in the per-workbook block when it lists them. All of this costs room in the prompt but no time, because the header is read ahead. Phase 7 measures it.

**Limits that shape the tools.** Tool arguments are capped at 32,000 bytes and a decision's output at 1,800 tokens. Statements and scripts must be short, so data moves by reference: a script reads an included file or the request's text through a function instead of retyping it.

### SQL runs on a copy and is applied through the recorded write path

Facts that fix the design:

- A user table is a projection. Each dataset has one real SQL table named by hash, with hashed column names and hidden columns. The authority is the immutable `items` rows with `heads` and `dataset_rows` ([ManagedDatasetSchema.swift](../../../Sources/SevraCore/ManagedDatasetSchema.swift), [ManagedDatasetRows.swift](../../../Sources/SevraCore/ManagedDatasetRows.swift)).
- Every change must pass through `Workbook.mutation`, which captures the change and writes one `operations` receipt. `Workbook.verify` requires each table to equal the projection of its head items, and the canonical schema check refuses any table or column the app did not create.
- The app uses the system SQLite. It has no session extension. `sevra_capture` is registered so that any SQL text on the workbook connection could call it.
- Formula columns are not stored. They are computed when rows are read. Every row write also recalculates stored sheet formula cells, normalizes dates and booleans, and refuses protected cells.
- A table's `version` is its schema version. Row edits do not change it. The app path names a table's content by a fingerprint of its definition, row count and newest row ([NativeAppData.swift](../../../Sources/SevraCore/NativeAppData.swift)). The workbook revision advances on every message and tool receipt, so it cannot guard a table between copy and apply.
- A column has an `id` that is separate from its title, and one of four types: text, decimal, boolean, date.
- Decimal columns are text with the exact collation `SEVRA_DECIMAL`. The app's exact sum and divide functions return text.
- The capture limits, 250,000 rows and 64 MB, count stored rows and their before and after images, not user rows. One updated user row writes at least seven, read from the code and not measured. `applyRows` takes up to 10,000 rows. A mutation's default deadline is 3 s.

So model-written SQL never runs on the workbook connection.

1. **A scratch database per call.** The host opens a separate in-memory SQLite connection with a page cap. It holds one table per user table under a readable name, with readable column names and computed formula values. Each row's identity is the scratch table's `rowid`, so `SELECT *` does not show it. The host keeps the mapping from saved rows to `rowid` for the conversation, so a row has the same `rowid` in every call. It also holds read-only catalog tables: the workbook's tables and columns, table versions, views, apps, tools, definitions, automations, workflow runs, the review queue, one metadata row per document and record, and the ledger's two tables.
2. **Readable names.** A name is the title in lower case with every run of other characters replaced by one underscore. Two that would be equal get a numeric suffix in creation order. Catalog names are reserved, so a user table that would take one gets a suffix. The per-workbook part of the prompt shows the names, so the model never guesses them.
3. **Only what the statements touch is copied.** The host takes the statements one at a time. It prepares each against the scratch schema, collects the tables it references from SQLite's authorizer callbacks, fills any of those not yet filled through the existing row read path, then runs it.
4. **The host logs what the statements do.** Triggers that the host creates on each scratch table record every insert, update and delete in order, with recursive triggers on so that `REPLACE` is seen. The authorizer denies the statements any access to the log and to the host's triggers, and reports each `CREATE TABLE`, `ALTER TABLE` and `DROP TABLE`. The changes of a call are this log, netted per row. A before-and-after comparison is not used, because SQLite reuses a `rowid` after the last row is deleted and a delete followed by an insert would read as an update of the deleted row.
5. **Computed values stay current inside a call.** After each statement that changes a table, the host recomputes that table's formula columns for the changed rows and normalizes dates and booleans in the scratch, so the next statement reads what the workbook would hold. Stored sheet formula cells, which tables from an Excel import can have, are recalculated only by the write path. A statement that reads such a table after an earlier statement in the same call changed it is refused, and the model splits the work into two calls.
6. **Reads return rows and a receipt.** The receipt records the statements, each table read with its fingerprint, and the row count. Result rows that select `rowid` are inspected by ID.
7. **Schema changes are read statement by statement.** The host compares a table's column list before and after each schema statement.
   - `RENAME COLUMN`, `RENAME TO`, `ADD COLUMN` and `DROP COLUMN` become the same change in the table definition. A renamed column keeps its `id` and its history.
   - A new table becomes a new dataset. A dropped table is archived.
   - A table dropped and replaced in the same call by a new table of the same name is one redefinition of that dataset. This is how SQLite changes a column's type. The dataset keeps its identity, and so do the columns that keep their names. Its rows are recorded as replaced.
   - Declared types map to the four column types: `INTEGER`, `REAL`, `NUMERIC` and `DECIMAL` to decimal, `TEXT` to text, `BOOLEAN` to boolean, `DATE` and `DATETIME` to date. `NOT NULL` becomes required and `UNIQUE` becomes unique. A single-column primary key is saved as required and unique. A generated column becomes a formula column when its expression fits the formula language.
   - Anything the table definition cannot keep is refused with the reason: other types, defaults, checks, foreign keys and composite keys.
   - Indexes, views, triggers and temporary tables may be created inside a call. They live in the scratch database and end with the call. To keep a query, save a view or a tool.
8. **One recorded change, inside one hold of the workbook lock.** The copy, the statements and the apply happen without releasing the lock, so nothing else can change the tables in between. The operations are applied inside one `Workbook.mutation` through the path `table.change_rows` and mini-app `data.transaction` already use ([NativeAppData.swift](../../../Sources/SevraCore/NativeAppData.swift), [DatasetDefinitions.swift](../../../Sources/SevraCore/DatasetDefinitions.swift)). That path takes 1 to 64 operations today. It gains a bulk form that writes one evidence Source for the call. Its deadline is set in phase 3 at twice the measured time of a call at the row limit on the test Mac, and never below the 30 s the table definition path uses. The limit starts at 10,000 changed user rows per call, the existing `applyRows` cap. Phase 3 measures what fits inside the capture limits and records the final number. A call over the limit is refused with the count, and nothing changes.
9. **Applied equals intended.** Before the mutation commits, the host reads back the cells the statements wrote and requires them to equal the scratch result in canonical form. Cells the app computes, formula columns and recalculated sheet formula cells, are not compared. The receipt lists them as recalculated. Any difference rolls the mutation back and fails the call. A protected cell fails the call the same way. A call's statements apply together or not at all.
10. **One Undo.** The receipt keeps the inverse operations. One Undo restores rows, columns and archived tables. As today, Undo is refused once a later change has touched the same rows. The later change must be undone first.

Other points:

- **Authority for direct changes (P2).** Row updates, schema edits and new tables accept an AI change only under a rule Source. Inserts and deletes through the transaction path make no such check today. App authoring already publishes its own rule Source from the host, marked as written by the app and not as a person's acceptance ([NativeAppAuthoring.swift](../../../Sources/SevraCore/NativeAppAuthoring.swift)). Direct changes get one the same way. Its text says what it allows: changes to this workbook's tables and saved things that the current request asks for. The person has no step to take. Every direct change, whatever its kind, cites it and the request.
- **What a written row is.** The three row operations keep what `table.change_rows` does today. An insert saves the row as actual and accepted. An update goes through `applyRows` and keeps the row's meaning and status. A delete saves a rejected version. Today only the insert names the request, and the update writes its own correction Source without it. Under this plan the call writes one evidence Source that holds the operations, and it is an input of every operation in the call. Its own inputs are the request and the optional `sources` list on `sql`, the IDs of the documents or records the changes come from. Today's table proposals carry their inputs the same way. The `sql` function inside a script takes the same list.
- **Drafts on request (P2).** With `draft` set, nothing is applied. A new table with its rows is saved as a table proposal, as `propose_table` does. Row inserts, updates and deletes on an existing table are saved as an edit proposal, as `propose_table_edit` does. Accepted data does not change, and the person accepts the proposal in the review queue. A draft that changes the columns of an existing table is refused with the reason. The `draft` input exists on the `sql` tool only. Inside a script, `sql` always writes directly.
- **Retries.** The idempotency token of a call is its run and its position in the run, not its statements. A resent decision replays its receipt. A new decision with the same statements, such as a second `SET n = n + 1`, runs again. `sql` has no duplicate refusal.
- **Numbers.** SQLite's own arithmetic is floating point, and it turns a written floating-point value into decimal-looking text before any trigger can see it. So the scratch database holds each decimal cell as a floating-point number and keeps an exact side table from that number to its exact decimal. The host fills the side table when it copies a table, when a statement or its values name a number, and when an exact function returns one. SQLite then compares, orders, groups and joins decimals natively, including against quoted numbers.
  - `sum` is replaced by an aggregate that is exact while every input is exact, and it also works as a window function. Exact functions exist under their own names for multiply, divide to a stated number of places, add, subtract and round. `min`, `max`, `coalesce` and `CASE` pass exact values through.
  - A result cell is exact when its number is in the side table, and it is shown as that exact decimal. Any other number came from SQLite's own arithmetic. It is marked approximate in the result and its receipt.
  - After each statement that changes a table, the host checks the decimal cells it wrote. A number that is not in the side table, or text that is not a number, fails the call, and the message names the exact function to use.
  - Limits: a number SQLite computed is treated as exact when it equals a known exact value, which can differ from the true result only beyond 15 significant digits. Two stored decimals that differ only beyond 15 significant digits compare as equal, and results that involve them are marked approximate.
- **Things bound to a changed table.** Views, apps and definitions bound to changed columns are named in the tool result. As today, an app bound to exact columns is disabled until the person reviews it.
- **Limits.** The existing query budgets apply: rows and bytes read, VM instructions through the progress handler, and time.
- **Read-only requests.** The authorizer refuses every changing statement, and the call fails with the existing read-only refusal.
- **Documents stay with `search` and `read`.** SQL sees tables and the catalog. Exposing records and documents as read-only tables is a later candidate.

The SQLite mechanics above were probed on November 18, 2026 on the system SQLite 3.51.0, with no model and no app code: [probe.swift](../../../integration/evidence/2026-11-18-sqlite-scratch-probe/probe.swift) and [results.json](../../../integration/evidence/2026-11-18-sqlite-scratch-probe/results.json). Phase 2 step 1 lists what it showed.

### Code runs in the existing worker, with a new script entry point

Facts: QuickJS 2026-06-04 is vendored in `Sources/CQuickJS`. App code runs in the `sevra-app-worker` XPC service, which has the app sandbox entitlement only, and a probe confirms file and network access are denied. A second service of the same binary runs unapproved code. Limits today are a 64 MiB heap, a 512 KiB stack, 500 ms and 10,000 jobs per evaluation, 2 MiB per message and of output, and a 3 s worker watchdog. Host calls are asynchronous messages. No native callbacks are registered, and the host accepts four methods: `page`, `query`, `calculate` and `transaction`. The runtime requires the app SDK and has no entry point for a one-off script. BigInt exists. Exact decimals do not. A mutation is one synchronous transaction and cannot stay open across messages to the worker.

1. **A script entry point.** Add a message kind that evaluates one async function with a small prelude in place of the app SDK and returns its JSON result. The Excel behavior runtime already evaluates a script and returns JSON, and the app check's message pump already carries requests to the host and results back.
2. **Run only inside a sandboxed worker.** In the app, model-written code runs in the service for unapproved code. The command line and the checks have no packaged service, so there the script runs in a subprocess that enters a deny-default sandbox first, the way the Excel behavior runtime does. If neither is available the tool is refused. Code written in a conversation needs no enabling, because the person asked for it in that turn and it reaches only this workbook (P3).
3. **Two kinds of function.** Each function is a host method added to the dispatcher. Nothing else is reachable.
   - **Data functions** are answered while the script runs: `sql`, `search`, `read`, the exact number functions, the text of an included file, the text of the request, and saved functions and queries. Each calls the same host implementation as the tool of that name.
   - **Requests** are everything that acts outside the tables: saving a file into the workbook, exporting, opening a view, operating an app's interface, saved actions, app actions and workflows called by name, the other workflow functions, undo, and long jobs such as transcription, an Excel build or an import. The script gets a handle back at once. The host performs requests in order only after the script has returned without error and its table changes are committed. Their outcomes are part of the tool result. A long job returns a job reference, as those operations do today. Each request behaves as its operation does today, so one that makes a draft still makes a draft.
4. **One scratch database for the whole script.** The script sees its own SQL writes. `search`, `read` and saved queries see the saved workbook, without the script's unsaved changes. A workbook tool with a SQL body called from the script runs on the same scratch database. One with a JavaScript body runs inside the same script, under the same budgets.
5. **Applied once, at the end.** When the script returns, its table changes are applied as one recorded change with one Undo, by the same steps as `sql`. Since the workbook lock cannot be held across messages, the apply first checks that each touched table's fingerprint still equals the one copied, and refuses otherwise.
6. **Failure changes nothing.** A script that throws, runs out of budget or is cancelled changes no table and performs no request.
7. **Chats belong to the person.** No function creates, switches or renames a chat. Since November 21, 2026 only the person does that ([[records/plans/simple-chats]]).
8. **Budgets.** Each evaluation keeps its limits. The call gets a host deadline across round trips, a cap on host calls, and the existing output cap. A result over the cap is saved with a receipt and paged with `read`.
9. **Effects.** A script that changed nothing and requested nothing is a read.
10. **Exact numbers.** Scripts get the exact number functions as host calls. Money math in plain JavaScript numbers is floating point, and the guide says so.

Restrictions never change the tool list. The grammar removes a whole tool, `ask` or `save`, where the request forbids it. The SQL and code layers refuse changes in a read-only request. A line in the request block tells the model which apply.

### Saving, and tools that belong to a workbook

Facts:

- Saved definitions have nine kinds (function, query, action, form, workflow, interpretation, extraction, intake, automation) with up to 32 typed parameters, stored as immutable versions in `app_definitions`. None holds SQL or JavaScript: a function is a decimal formula, a query is a structured template that refuses raw SQL, and an action must name one of three registered primitives, two of them inventory.
- The list of kinds is a `CHECK` in the canonical schema, and opening a workbook compares the schema text ([Schema.swift](../../../Sources/SevraCore/Schema.swift)).
- The model does not see definitions as tools. It reaches them through generic tools such as `find_definitions`, `evaluate_definition` and `start_workflow`.
- Mini apps and views are stored in `spaces` and `space_versions`. Saving an app runs an isolated check, a second model review and a per-Mac permission step. An app that arrives in a copied workbook is disabled until the person enables it on that Mac.
- An app declares its actions in JavaScript at run time. Their list exists only while an enabled app is running.
- Views bind forms, calculations and queries to definitions, and those screens work without the model.

1. **`save` routes by kind to the existing validators.** A document goes to the draft path, a record to the record path, a view to the view path, an app to the check, review and save path, and a definition to the definition path for its own kind, one of the nine. Each path keeps its behavior: a document or record is a draft the person accepts, a view or tool is ready to use, and an app is saved disabled until enabled (P2, P5).
2. **A new definition kind, `tool`.** Its payload is a body in SQL or JavaScript. It uses the existing typed parameters, versions, heads, dependencies and search index. The person or the model creates one with `save`. A `tool` body writes directly, like `sql` and `run`.
3. **This changes the workbook format.** Adding a kind changes the canonical schema. Under the pre-1.0 compatibility policy in [[records/specs/distribution]] there is no migration: the schema is updated, the sample workbook and fixtures are recreated, and the break is documented. Workbooks made by earlier development builds do not open in the new build. Every schema change of this plan lands in that one change.
4. **Every callable definition is a workbook tool.** Existing functions, queries, actions and workflows keep their formats and their screens. They are listed and called by name with their typed parameters, in place of the generic find, evaluate and start tools. Each keeps its own behavior: an action that makes a draft still makes a draft, and the direction review still runs in front of it. A workflow started by name runs now or is queued, as the workflow operations allow today.
5. **App actions are listed from a saved catalog.** The isolated check at save already runs the app. It records the declared actions with the package version, so they can be listed and inspected without a running app. Running one still needs the app enabled on that Mac.
6. **Listing.** The per-workbook part of the prompt lists each tool as a name with its inputs and a few words, beside the workbook's tables, views, apps and automations.
7. **Loading and calling.** Reading a tool returns its input schema in the read result. From then on the grammar accepts a direct call to it by name with checked inputs, for the rest of the conversation. A call runs the tool's current version. If the tool changed since it was read, the call is refused and the model reads it again. A tool's name cannot equal a built-in's. Scripts can call it as a function.
8. **Loaded tools survive context maintenance.** The host keeps the list of loaded tools and read guides as conversation state. When context maintenance drops the read result that carried a schema, the rebuilt prompt's host state carries it again.
9. **Tools from a copied workbook (P5).** A tool saved on this Mac in a conversation is granted on this Mac when it is saved. A tool with no grant on this Mac, because the workbook was copied here, does not run until the person enables it. This holds for SQL and JavaScript bodies alike.
10. **Undo.** A `save` is one recorded change. Undo removes the new thing or restores its earlier version.
11. **The command line.** `tool WORKBOOK TOOL` runs the seven tools and workbook tools by name.

### The stock ledger without built-in tools

No ledger tool is built in, on demand or otherwise (S2, S3).

- **Reading.** The ledger's balances and movements are two read-only catalog tables in the scratch database. The core's balance read takes one subject today, so listing every subject needs one small new read over the ledger tables. No ledger data or rule changes. The per-workbook listing shows the two tables, with their columns, when the ledger holds entries. That is a listing of data the workbook holds and adds no tool. It does depend on workbook state, so it is an open item for the owner. The alternative is to list them always.
- **Changing.** A movement is recorded by a saved action that names the existing movement primitive. A saved action is a workbook tool like any other. The sample workbook carries one. The direction review stays in front of the primitive.
- **Starters.** The receiving starter and the low-stock rule starter become guides read on demand, each with a filled example. What the model writes from them is saved with `save` as a definition and checked by that kind's existing validator.
- **Quote comparison** needs no tool. It is SQL over the comparison table.

Nothing about stock appears in the header.

### Confirmations that stay with the person

Five operations today prepare something the person confirms in the conversation: enabling an app, enabling an automation, accepting or withdrawing a record, submitting a form, and reading what is pending. They stay. Each is a function that prepares the exact effect and returns that a confirmation is required. The person's confirmation applies it through the existing approval path. Direct writes do not pass through this path. It covers what a person grants: permission for an app, a standing automation, acceptance of a draft, and a form submitted in their name.

### Safety

- **Nothing leaves the Mac by itself (P3).** The sandbox has no network and reads no file outside the workbook. Today's export operations write to any absolute path in the tool call. Under this plan an export is a request, and the host accepts its path only when that exact path appears in the person's message for this request. Otherwise the app opens the save panel. On the command line there is no panel and the export is refused. Including a file works only on a file the person linked earlier, by its ID.
- **Changes can be undone.** That includes dropped tables and bulk deletes, each restored by one Undo, until a later change touches the same rows.
- **Documents are still untrusted.** The instruction that imported text is evidence and never an instruction stays in the prompt. A document that tries to instruct the model can at worst cause changes in this workbook. Table changes can be undone until later changes build on them. Requests keep the undo their operations have today, and some have none.

### Answers, evidence and the guards that move

The agent loop in [WorkbookAgent.swift](../../../Sources/SevraAI/WorkbookAgent.swift) carries guards keyed on today's tool names. Each needs a new basis before its old tools go. None is dropped silently. Line numbers are at the reviewed commit.

| Guard today | Where | New basis |
| --- | --- | --- |
| What counts as inspected, from the result shape of `read`, `search`, `rows`, `evaluate_definition` | `visibleEvidence`, `WorkbookAgent.swift` 2190 to 2291 | A result row that carries its row identity is inspected by ID. Any other `sql` or `run` result is inspected as a result receipt that names the query or code and every table it read. |
| Numbers, percentages and comparisons must come from `calculate`, `balance` or `compare_rows` | `WorkbookAgent.swift` 269 to 276 and 1728 to 1794, [CalculationRequirement.swift](../../../Sources/SevraAI/CalculationRequirement.swift) | They must appear in the request, in inspected evidence, or in a complete, untruncated result of this run from `sql`, `run` or a tool called by name. A figure taken from a result cell marked approximate is refused, with the exact functions named. |
| Count receipts re-verified at `finish` | `WorkbookAgent.swift` 792 to 813 | A cited result receipt records the fingerprint of each table it read. A catalog table has one of the same shape, its row count and newest entry. If one changed since, the receipt is stale and the answer is refused until the query runs again. |
| Read-only tool list drives `attemptedEffect`, `completedAction` and Core refusal | `WorkbookTools.readOnlyTools`, [Tools.swift](../../../Sources/SevraCore/Tools.swift) 21 to 29 and 151 | The recorded effect of each call. `sql` is a read when it changed nothing. `run` is a read when it changed nothing and requested nothing. A read-only request denies changes inside the SQL and code layers. |
| Empty-search limit and discovery budget | [SearchCoverage.swift](../../../Sources/SevraAI/SearchCoverage.swift), [DiscoveryBudget.swift](../../../Sources/SevraAI/DiscoveryBudget.swift), `WorkbookAgent.swift` 1796 to 1880 | Unchanged for `search`. Searches made from inside `run` count too. |
| Direction review before an inventory movement or saved action | [MovementDirectionReview.swift](../../../Sources/SevraAI/MovementDirectionReview.swift), [ActionDirectionReview.swift](../../../Sources/SevraAI/ActionDirectionReview.swift) | Unchanged, in front of the primitive and of saved actions, however they are called. |
| Isolated check and independent review before saving an app | `WorkbookAgent.swift` 1245 to 1313, [NativeAppReview.swift](../../../Sources/SevraAI/NativeAppReview.swift) | Unchanged, run by `save` for apps. |
| Duplicate draft and view refusals, retry keys by tool | `Tools.swift` 524 to 546, [ActionConfirmations.swift](../../../Sources/SevraAI/ActionConfirmations.swift) | Keyed on the saved thing's kind and name. `sql` and `run` have no duplicate refusal, only the replay of a resent decision. |
| Host-written closing receipts and focus per tool | `WorkbookAgent.swift` 1710 to 1727 and 1841 to 1971 | Per kind of saved thing, and one generic receipt for a data change. |
| Undo offered only for one-change app actions | `WorkbookAgent.swift` 1565 to 1580, [ConversationViews.swift](../../../Sources/SevraApp/ConversationViews.swift) 248 to 275 | Offered for every change made by `sql`, `run` or `save`. |
| Context maintenance keeps `readEvidence` and `savedSpaces` by tool | [ContinuationEvidence.swift](../../../Sources/SevraCore/ContinuationEvidence.swift) 17 to 70 | Read evidence, result receipts, saved things by kind, loaded tools and read guides. |
| Scopes, grammar tool lists and the citation choices on `finish` | [WorkbookInference.swift](../../../Sources/SevraAI/WorkbookInference.swift) 8 to 99, [ToolSerialization.swift](../../../Sources/SevraAI/ToolSerialization.swift), [NativeCitationPolicy.swift](../../../Sources/SevraNativeAI/NativeCitationPolicy.swift) | One ordinary tool list. Restrictions are enforced by the grammar and the host. Specialized phases keep their own lists. |

Interface code also branches on tool names: 14 progress labels in [ToolActivityLabel.swift](../../../Sources/SevraAI/ToolActivityLabel.swift), activity titles in [RequestActivity.swift](../../../Sources/SevraCore/RequestActivity.swift), and scripted names in the Native UI Catalog fixtures. Of the 84 agent check files, 61 contain tool-name literals.

### Prompt layout

1. **Header.** The stable instructions, the seven schemas, the function index, the catalog tables and the names of the general guides. It is identical for every ordinary chat turn, in every workbook.
2. **Per-workbook block.** Tables with their columns, and views, apps, tools and automations, each as a name with its inputs and a few words, within a token budget. Past the budget it lists names only and the catalog tables hold the rest. The block is built when a conversation starts and stays as it is for that conversation, so the follow-up cache holds.
3. **Saved conversation.** Append-only, as [[records/plans/conversation-follow-up-cache]] left it.
4. **Host state and the request.** Catalog changes made after the conversation started are listed here: names added, changed and removed. Context maintenance, which already rebuilds the prompt, rebuilds the block.

A loaded tool's schema and a guide arrive in the result of the read that asked for them. Nothing before them in the prompt changes.

## The prompt header is calculated at build time and restored at engine start

Owner direction: [[sources/notes/2026/11/prebuilt-header-direction]]. It replaces the first form of proposal P4, which made the header during setup on each Mac.

### What the engine allows

The pinned Splash 1.6.1 already keeps restore points on disk. The app turns that off today with `--persistent-cache off` in [NativeWorkbookModel.swift](../../../Sources/SevraNativeAI/NativeWorkbookModel.swift). Read from the pinned source and its `docs/server.md`, and not yet run:

- `--persistent-cache on` with `--cache-dir` keeps restore points across restarts. A start takes back every recorded point whose chain is whole. The status reply reports it under `disk`: `persistent`, and `taken_back` with counts of `states`, `kv_blocks`, `bytes` and `left_behind`.
- The files are `kv.slots`, `kv.records`, `state.slots` and `state.records`, beside `lock`, `serving`, `probation` and `failed-probation` markers, in a folder named by the cache name under the cache directory. The folder must be mode 0700, owned by the user and locked while in use. The engine cannot use them in place from a signed, read-only app bundle. They are copied into place.
- There is no message to export or import one named restore point. With the persistent cache on the engine copies every point of every request, so a conversation's own state reaches the disk too.
- The app passes no disk quota. On low free space, a volume that is not local or a directory it cannot use, the engine falls back to temporary files and still reports Ready.
- **Read from the source, and to be proven in phase H2: the cache name can be the same on every Mac without an engine change.** The name is a digest of the weight manifest and the cache layouts (`runtime/engine/RuntimeResources.mm`). The manifest lists each weight image's relative path, size and header, and the SHA-256 of the assembly's `model.json` (`runtime/model/WeightStore.cpp`). From that file the engine reads four fields: `version`, `model`, `target_format` and `vision_format` (`runtime/model/ModelDescriptor.mm`). It hashes the rest without reading it. The parts that differ per Mac, each file's absolute path and its modification and change times, are written by this repository's [ModelPreparation.swift](../../../Sources/SevraSplash/ModelPreparation.swift) for its own fast verification. Because a launch fingerprints the files again, a changed file time alone gives the assembly a new key and the cache a new name today. The name also depends on the KV and state formats, which the app's launch arguments set.
- Every start removes cache directories nobody used for 14 days, except the one it holds. After two failed starts in a row the next start begins empty. A clean stop gets up to 6 seconds to write waiting points. The app stops its helper with SIGTERM and SIGKILL one second later ([NativeProcess.swift](../../../Sources/SevraSplash/NativeProcess.swift)).
- Whether a request reused the header is known only from its start event, after it is sent. A running engine can drop a point when its disk quota is full, oldest first.

### What the builds look like today

Read from the scripts at `baadc5c`, which implement [[records/plans/macos-installer-and-updates]]:

- **Two packaging paths.** [build_native.sh](../../../scripts/build_native.sh) runs [package_native.py](../../../scripts/package_native.py) and makes the development app, signed ad hoc, with a separate folder for the command line tool. [install.sh](../../../scripts/install.sh) builds and installs it. With `--distribution`, the build script runs [package_release.py](../../../scripts/package_release.py) and makes a DMG that holds the app and a bundled command line app. It has three stages: `qa`, `early-access` and `stable`. Only `stable` uses Developer ID signing and notarization. It writes a `release.json` receipt, and [check_release_package.py](../../../scripts/check_release_package.py) checks an installed copy against it. Both scripts share one staging function, which runs before any signing. Each script then signs in its own order.
- **Where the command line tool sits.** The source installer copies it into the installed app at `Contents/CLI` and links `~/.local/bin/sevra` to it. A release keeps it in a helper app inside the app. Each resolves resources from its own folder today.
- **Rehearsed, not released.** Three ad hoc QA builds were installed and updated on one Mac. The packaged app has not downloaded or run the model. The public README still offers the source build.
- **Neither path uses the model.** The person downloads it in Settings, or points the app at existing files. Both routes record the model by repository and revision ([ModelSetup.swift](../../../Sources/SevraSplash/ModelSetup.swift)). The default folder is the same for every build on a Mac.
- **The app prepares the model at every engine start**, and gives the assembly a new key when a file's time changed.
- **An update replaces the whole app** with the full DMG.
- **Resources resolve from one root:** `Contents/Resources` in an app, the executable's folder in a build tree ([RuntimeResources.swift](../../../Sources/SevraSplash/RuntimeResources.swift)). The release's bundled command line app carries its own copy of the resources.
- **The tokenizer and the chat template come with the model.** The app loads both from the prepared model, so neither a header's rendered text nor its tokens can be worked out on a Mac that has no model. The header's inputs can: the instruction text and the tool declarations as the app serializes them.
- **Specialized phases build their prompt starts differently.** Some share today's header. Excel conversion replaces the instructions with its own, and workflow interpretation has no stable start ([NativePreparedRequest.swift](../../../Sources/SevraNativeAI/NativePreparedRequest.swift)).
- **Restore points sit on 32-token pages.** The app already treats a prompt start as resumed when the engine reuses it up to its last complete page.
- **One launch setting differs by Mac.** The context size is 64K on a Mac with 48 GiB or more and 32K below that ([NativeProductResources.swift](../../../Sources/SevraProduct/NativeProductResources.swift)). The KV format, the state format and the activations setting are fixed.

### The design

1. **One command makes a header.** A command in the built command line tool, `sevra header make`, is the only thing that computes an ordinary chat header. It takes the header from the app's own prompt code, so it cannot differ from what a chat turn sends. It starts the same engine helper with the same launch arguments the app uses, the persistent cache on, a fresh cache directory and an explicit disk quota. It sends the header as a one-token request and waits for the engine's own exit, so the points are written. It then starts the engine again, sends the header once more, and requires that request to resume it. Only then does it write the four data files and a manifest into the build's header cache, `.build/prompt-header/`. It does nothing when the cache already holds a matching header. It takes a tool profile, and a folder to write to. It refuses to start while another engine helper is running or when reclaimable memory is short, so a build never loads a second model. Packaging that needed it then stops with that message, and nothing is packaged.
2. **A header is named by what it is for.** Its folder name is the digest of the header's inputs: the instruction text and the tool declarations as the app serializes them. These can be worked out without the model. If phase H1 shows that the context setting matters, the name also carries that setting. Its manifest records the inputs digest, the token count and token digest, the engine's cache name, the launch arguments that feed that name, the pin from [integration/splash.json](../../../integration/splash.json), the model pack and the assembly key, the point counts the engine reported, and each file's size and SHA-256.
3. **One place in a build holds it.** In an app that is `Contents/Resources/PromptHeader/`. Every executable inside the app uses that folder, including the command line tool, which sits in `Contents/CLI` in a development build and in a helper app in a release. An executable outside an app, such as the command line tool in the package output, a build tree or the checks, takes the folder from an explicit setting that the scripts pass, and they pass the header cache. Without that setting it has no header. A release holds one header, or one per context setting if H1 shows that is needed. A development build holds one per tool profile it can select.
4. **Packaging copies it in before the app is sealed.** One helper, which each packaging script calls at its own point, looks in the header cache for a header whose manifest matches this build: its header inputs, engine pin, model pack and launch arguments, for each tool profile the build can select. If one is missing and the model is on the Mac, it runs the command with the packaged command line tool and writes into the cache. It copies the folder into the app after the nested binaries are signed and the runtime manifest is written, and before the app itself is signed, so the header is sealed with the app. In the release script that point comes after the command line helper app is staged, so the helper app gets no second copy.
   - A development package made without the model has no header and says so.
   - A release package at stage `early-access` or `stable` fails without a matching header. Stage `qa`, which rehearses updates with disposable data, follows the development rule.
   - A header made on another Mac can be placed in the cache, for a release built where the model is not present. Packaging accepts it only if its manifest matches.
5. **The app only restores.** Before every engine start the host prepares the model as it does today, works out the digest of its header inputs, finds the folder of that name, and checks the manifest against the engine pin, the launch arguments and the prepared model's assembly key. Once the tokenizer is loaded it also checks the token count and digest. It then empties its cache directory, creates a folder there named by the cache name, copies the four files into it with copy-on-write copies, and starts the engine with the persistent cache on and an explicit quota. The app has no code that computes an ordinary chat header (P6). This runs before every engine start, whoever asks for it. Without a matching header the engine is not started, so specialized phases are unavailable too.
6. **Check at start.** After Ready the host requests the engine status and requires `disk.persistent` to be true, `taken_back` to report at least the manifest's states and KV blocks, and `left_behind` to be zero. If the points are short, the host stops the engine, restores the files once more and starts again. A second failure is reported as a damaged installation (P6). The host checks free disk space before the start. If the engine still fell back to temporary files, the header was not taken back and the local AI does not start (P9). The app reports that the Mac lacks free disk space for the local AI cache and how much it needs. That is not a damaged installation, and nothing is computed.
7. **Check on every request.** Every ordinary chat prompt starts with the header, so every request's start event must report that it resumed the header up to its last complete page. The engine keeps restore points at 32-token page boundaries, so at most 32 header tokens are read in a turn, as today. If a request resumes less, the host cancels it before it generates, stops the engine, restores the files from the app again, starts again and sends the request once more. If the header is still not resumed, the app reports a damaged installation (P6). The host counts failed starts itself, because restoring a clean directory resets the engine's own counter. The status check in step 6 makes a miss here rare. This step exists so that a miss can never turn into a computed header.
8. **A missing or mismatched header is an error.** The app says that this build has no prepared prompt for this model, and what to do about it. In a release that is to install the app again. In a development build it is to run the install command or the header command (P6). Chat stays unavailable until then. Nothing is computed.
9. **Keep conversations off the disk between runs.** The engine writes later restore points into the same directory while it runs. The host removes the directory when the engine stops and at the next start, before restoring the header.
10. **Size the quota so the header is never the point dropped.** The quota covers the header and a full context of conversation points. Phase H1 measures both.
11. **What a chat turn may still compute.** The per-workbook block cannot be made in advance. If the engine is running when a conversation starts, the host primes that block in the background. Otherwise the first message computes it. Loading the model only to prime it would hold memory for a person who never chats.
12. **Specialized phases get no prepared header (P8).** Excel conversion, the reviews, workflow interpretation and history summaries build their prompt starts in their own ways. The app's `primePrefix`, which reads a prompt start ahead of a request, stops priming the ordinary chat header and keeps priming theirs where it does today. Until phase 6 ends, the phases that share today's header resume the prepared one. After phase 6 that header is no longer ordinary chat's, so they read it once per engine start.

### Development works the same way

- **The first build has no header,** because the model is not on the Mac yet. The source installer says so and names the next step (P6).
- **After the model download** the developer runs `bash scripts/install.sh` again. The build is incremental. Packaging now finds the model, makes the header and copies it into the app.
- **After a change to the prompt, a schema, the engine or the model** the header no longer matches, and the app says so. The developer runs the install command again, or `sevra header make` in a build tree (P6).
- **Unchanged headers are reused.** Packaging takes a matching header from the header cache, so the model is loaded only when the header, the engine or the model changed.
- **Real-model check scripts run the command first,** so a gate never fails for a missing header and never measures a computed one.
- **One set of tools, one header.** The tool profile is gone, so a package carries one header.
- **A model given by local path,** the developer layout, has no repository identity. A header made on that Mac matches only there, and any change to the model's files needs the command again.

[[records/operations/build-and-run]] and the README's setup steps document this when phase H3 builds it.

### What a release proves

- **The shipped header matches the release.** Packaging accepts a header only when its manifest names this build's header inputs, engine pin, model pack and launch arguments.
- **It is tested before publishing.** The header tests pass against the release package. Those that need a comparison run, a seam or a different context setting run through the check harness, pointed at the package's engine and header. The rest run in the installed app.
- **An update brings its own header,** since it replaces the whole app.
- **Other Macs (P7).** The shipped header is used on every Mac the app runs on. Phase H2 makes its cache name the same everywhere. Whether state made on one Apple chip gives the same answers on another has to be tested on each chip a release claims, and a release's published requirements list only the chips where the header tests passed. The installer plan already intends to publish only the hardware qualified on the released build.

### Header tests

- **Match.** `check-resources` reports the header as present and matching, absent or mismatched, without needing the model. It compares the folder name with the digest of the header inputs the app's code produces, and the manifest with the engine pin and the selected model pack. In a development package or install, absent is reported and is not a failure. In a release check at stage `early-access` or `stable`, anything but present and matching fails.
- **Resumed, not computed.** In a cold first turn, the first call resumes the header up to its last complete page and no header prime runs.
- **Faster, not just different.** A cold first turn with the restored header is faster than the same turn run through the check harness's comparison setting, where the engine computes the same header. The research record measured today's header prime at 4.33 s on the test Mac.
- **Same answers.** A fixed set of requests gives the same tool calls and answers with the restored header as in a comparison run where the engine computes the header. The comparison run uses a diagnostic setting that only the check harness can set. The app has no such setting.
- **Survives loss.** Deleting the cache directory, or ageing it past the engine's 14-day sweep, still gives a resumed header in the first turn after the next start.
- **Survives a full conversation.** After a conversation that fills the context, a new conversation still resumes the header.
- **Both memory tiers.** A header made at the 64K context setting is restored and resumed at the 32K setting, or each setting has its own header.
- **Recovers without computing.** With a test seam that reports one missed resume, the request is cancelled, the engine restarts with the header restored, the request runs, and no header is computed.
- **Fails loudly (P6).** With the header folder removed, its manifest, engine pin or model identity changed, or one data file cut short, the local AI is unavailable with the message. No turn runs and nothing is computed.
- **Nothing kept from conversations.** After a stop the cache directory is gone. After a forced kill followed by a start it holds the header only.
- **From the DMG alone.** With the header cache and the app's cache directory removed, a copy of the app installed from the DMG resumes the header in its first chat.
- **Update.** After an in-app update to a build whose header differs, the first engine start uses the new header.

## Coverage of what exists today

The 59 ordinary chat tools, by where each goes. The inventory and token counts are in [[records/plans/native-chat-prompt-routing]].

| New home | Today's tools |
| --- | --- |
| `search` | `search`, `history_search` |
| `read` | `read`, `references`, `lineage`, `tool_result`, `history_read`, `archive_members`, `read_definition`, `read_native_app`, `read_workflow`, `space_history`, and as guides `native_app_sdk`, `definition_registry`, `form_template`, `workflow_template`, `receiving_template`, `inventory_automation_template` |
| `sql`, reading | `datasets`, `rows`, `compare_rows`, `calculate`, and through the catalog tables `count_records`, `find_definitions`, `spaces`, `review_queue`, `workflow_activity`, `balance` |
| `sql`, changing | `propose_table` and `propose_table_edit` with `draft`, and direct changes without it |
| `run` functions | `include_archive_members`, `open_space`, `open_reviews`, `open_automation`, `set_space_pinned`, `pin_space`, `restore_space` |
| `save` | `draft`, `propose_record`, `publish_result`, `save_space`, `edit_space`, `save_native_app`, `save_definition`, `save_template` |
| `ask` | `request_input` |
| `finish` | `finish` |
| Workbook tools, called by name | `evaluate_definition`, `preview_action`, `prepare_action`, `start_workflow`, and `propose_movement` as a saved action |
| The function index and the per-workbook listing | `workspace_actions`, `workspace_action` |

The 81 operations inside `workspace_action`, by domain:

| Domain | Operations | New home |
| --- | ---: | --- |
| `table` | 7 | `sql` for schema and row changes and for history through the table versions catalog. Functions for undo and for restoring an earlier schema. |
| `app` | 13 | An app's named actions are workbook tools. Inspect is `read` from the saved catalog. Browse, set, fill, select, activate, drop, undo, redo and restart are functions. Enable is prepared by a function and confirmed by the person. Disable is a function. |
| `visual` | 27 | Functions for charts, images and diagrams. A capture is attached to the answer through `finish`. `save` for a view. Export follows the export rule under [Safety](#safety). |
| `file` | 6 | Functions. Include by ID, transcribe as a long job, exports under the export rule. |
| `intake` | 7 | Functions that run the existing importers as jobs. They cover XLSX and large files. A script may also read a small text file and insert rows with `sql`. An update proposed by intake stays a draft. |
| `excel` | 8 | Functions that start the existing conversion phases as jobs. |
| `workflow`, `automation` | 8 | Workflows are workbook tools. Continue, retry, cancel and answer are functions. Inspecting an automation is `read`. Enabling one is prepared by a function and confirmed by the person. Pause is a function. |
| `form`, `record`, `document`, `chat` | 5 | Functions. Submitting a form and reviewing a record are prepared by a function and confirmed by the person. |

Phases that are not part of ordinary chat keep their own tool lists and prompts for now. They are listed under [Scope](#scope). Chat starts them through a function. Moving them to general tools is outside this plan.

## Work sequence

Phases are ordered by what depends on what. Each ends on an exit criterion. Checks follow the focused verification policy in [[records/specs/distribution]]: the smallest checks that establish the change. Real-model and engine runs load one model at a time on an idle Mac, after checking reclaimable memory.

The seven tools are the only chat tools since November 19, 2026. Until then the old tools were the default and the seven ran under a host-selected tool profile in the same build, so the two were compared on the same code. Three things do change earlier, each called out where it happens: the model record in phase H2, the header mechanism in phase H3 and the workbook format in phase 5.

### The test loop and the order

Owner direction: [[sources/notes/2026/11/fast-loop-direction]] on November 18, 2026, and [[sources/notes/2026/11/light-testing-direction]] on November 19. This section governs. Where a phase below asks for more testing than this, this section wins.

**The agent overtested this plan, and the owner stopped it.** The first rule here grew into a gate with every job in two languages, reruns of failed jobs and timings taken three times. He had asked for none of it. Spanish alone cost about an hour of model runs. The app is tested in English.

**How this plan is tested:**

- **No model, on every change.** Checks on the layer being changed. They take seconds and carry the mechanics: reads, row and column changes, Undo, refusals, scripts, the sandbox and the routing of the seven tools.
- **The light set, when chat behavior changes.** Eleven model jobs in English, one run each, under four minutes in all: one happy path for each kind of work and the edge cases that matter. `python3 scripts/check_chat_jobs.py --output NEW_DIRECTORY` runs it.
  - Happy paths: a table question, a question answered from a document, a row change, a new table, a script, a saved view and a greeting.
  - Edge cases: a change the person wants as a draft first, a request missing a value, a document that contains an instruction, and a request that forbids changes.
- **A job for its area, when that area changes.** The other jobs in the harness run by name: the app job when app building changes, a rule job when rules change.
- **Every job, once, to compare two models, with the owner's word.** `python3 scripts/check_chat_jobs.py --jobs '*' --long-run-approved --output NEW_DIRECTORY`, once per model. It is for a model change, not for iterating: [[sources/notes/2026/11/model-swap-evals]].
- **The suite, once on a candidate before a release:** `scripts/check.sh`.

**What is not done:**

- No second language.
- No rerun of a failed job to see whether it passes. Its transcript is read, and it is fixed or recorded.
- No timing taken several times. Timing is measured once, when the prompt changes.
- No run of every job. The harness refuses more than twelve jobs without the owner's word.

**What that changes in the phases below:** an exit that asks for every job, a rerun or a repeated timing means the light set, once. Decisions and wall time are recorded at each run. The phase 3 milestone, the full agent suite and `scripts/check.sh`, moves to the candidate before a release.

**Order:**

1. **A thin slice first.** `sql` for reading and for row changes, with `finish`, under the `general` profile, in rough form: enough to run the read and change jobs with the real model. It answers the largest unknown first, whether the local model can drive SQL well.
2. **What the slice has from the start.** Changes go through the recorded write path, so history and Undo hold. Statements that reach outside the scratch database are refused. Row and time budgets apply.
3. **Then the rest of phases 2 and 3,** starting with what the evals show is needed. A part of the design that no check or eval shows a need for is left out, and listed in its phase with the reason. Changing a table's shape through `sql` still waits for the `db/DB.md` change.
4. **Phases 4 to 7 in order,** each built the same way: the smallest working form, an eval, then the rest.
5. **Header.** Paused by the owner on November 18, 2026 until the tools were done ([[sources/notes/2026/11/general-tools-answers]]), then built on November 19 at his word ([[sources/notes/2026/11/general-tools-whole-plan]]). Phases H1 to H4 are done; H4's update test passed on November 20, 2026. When a later change fixes a new header, packaging makes it again with the same command.

### The build so far

Built on November 18, 2026 under the `general` profile. Evidence: [the evals](../../../integration/evidence/2026-11-18-sql-slice-evals/results.json). This section is the current state. Where a phase below describes something differently, this section says what was built and why.

**Result, one run of each job with the real model:** 22 of 24 from the command line, and the app job passes when it runs inside an app bundle, which makes 23 of 24. Today's tools pass 12 of the 23 they can attempt. On the 11 jobs that pass under both, the seven tools take 26 decisions and 219 seconds where today's take 40 and 394. A first prompt is about 4,600 tokens where today's is about 11,180.

- **What today's tools fail and the general tools pass:** adding rows from a document, a bulk update, a new table from pasted text, a renamed column, adding the rows one table is missing from another, totals by category saved as a table, a draft change, building a view, a form and a saved tool.
- **Failing on November 18, since addressed:**

  - **The rule job as written.** A rule needed a saved workflow to run, and the sample workbook has none, so the model asked what the rule should run. Rules can now alert (phase 5), and the job passes in 3 decisions. `build.rule_for_workflow` keeps the workflow case.
  - **The app job.** It needs the app checker, which the CLI finds only as the main executable of an app, so it runs from a copy of the packaged app with the CLI as its main executable. It passed 2 of 3 runs on November 18. On November 19 it failed once by resending the same app after the check said to add fixtures; the check now shows that field with a row of the app's table, and the next run passed in 5 decisions. It is still the least reliable job, and it is not in the light set.

**The light set, the routine model run from November 19, 2026:** 11 of 11 pass, in 26 decisions and 3 minutes 51 seconds. It includes the first job in which the model wrote and ran a script, in 2 decisions. After phase 5, with a 2,707-token header, it passed 11 of 11 again in 26 decisions and 2 minutes 41 seconds, and `build.rule`, `build.saved_tool` and `build.app` passed by name in 3, 2 and 5 decisions: [the runs](../../../integration/evidence/2026-11-19-phase5-light/README.md). On November 20, with the export instruction and a 2,770-token header, it passed 11 of 11 in 31 decisions: four jobs took one or two more, from a refused first `finish`, extra reads and a script that fixed its own mistake, and none read the action list or exported ([the run](../../../integration/evidence/2026-11-20-export-light/results.json)).

**The header was trimmed on November 22, 2026,** at the owner's word: [[sources/notes/2026/11/header-trim-direction]]. It is 3,809 tokens, from 5,172. A first prompt on the sample workbook is about 4,500, from about 5,870. The packaged header is 108 MB, from 123 MB. Evidence: [the counts and the run](../../../integration/evidence/2026-11-22-header-trim-light/README.md).

- **Measured first.** `sevra-agent-checks --header-parts` loads only the tokenizer and counts the header's parts. Before the trim: instructions 1,148, `save` 1,762, `ask` 555, `run` 516, `read` 343, `sql` 267, `finish` 237, `search` 143, and 197 of template framing.
- **The view shape was most of `save`.** A view's schema nests every component three levels deep, each level with its types and fields, which came to about 1,000 tokens. The model is now shown a view as one description: the table and chart case in full, and where their ids come from. The grammar still enforces the whole shape. Every other component is in a new guide, `read kind=view_guide`, written from the component schema's own field notes. `save` is 875 tokens.
- **Each fact is said once.** The instructions no longer repeat what a tool's declaration says: what `sql`, `run`, `save`, `search` and `read` are, how a saved tool is named and described, and what a document, a view and an app are. The `sql` declaration no longer repeats the instructions' table list and draft rule. The instructions are 701 tokens.
- **The scope paragraphs are gone.** The view paragraph became the view's description. The rule and app pointers stand in the `read` and `save` declarations, which say to read each guide before saving. `GeneralTools.scopeInstructions` is removed.
- **Kept, with the reason.** The eleven named actions of `run` stay listed with their fields, because `read kind=actions` lists the workspace actions only and nothing else names them. `ask` and `finish` are unchanged: the light set does not call `ask`, and the citation text in `finish` is what keeps a first answer from being refused. Showing the nested `ask` shapes as field names would save about 100 tokens and needs a job that calls `ask`.
- **Result, one run each with the real model.** The light set passed 11 of 11 in 29 decisions and 215 seconds. The same eleven took 29 decisions and 216 seconds on November 21, so turn time did not change, which is what a restored header predicts. `build.view` passed in 4 decisions without reading the guide. By name, because their text moved: `build.saved_tool` passed in 2 decisions and `build.rule` in 4, reading the rule guide first ([the run](../../../integration/evidence/2026-11-22-header-trim-named/results.json)).
- **Resumed in the installed app.** The build of commit `4e309ee` was installed from `output/native`, and the installed app, extraction helper and command line tool have the package's Mach-O UUIDs. One "Hello" through the installed app's own command line, on its sealed header: `headerResumed` true with no restart, 3,808 of the header's 3,809 tokens matched in a 4,494-token prompt, 1.4 seconds of prefill and 3.9 seconds for the request, after a 4.4-second engine start.
- **Not run:** `build.app` and `build.form`. The app pointer moved from the instructions to the `save` declaration.
- **Checked without the model:** the prompt header, chat, surface, view action and `sql` checks, the default scripted groups, the grammar checks, and the command line's `sql` and `run` checks. The `sql` check still asserted that a `thread.start` action reaches the thread tool, which went with threads on November 21. That assertion is removed.

**The instructions changed on November 23, 2026,** at the owner's word: [[sources/notes/2026/11/defaults-and-step-limit]]. The header is 4,429 tokens, from 3,809: the instructions are 1,028, from 702, and `save` is 1,170, from 875, after a button and a size in views ([[sources/notes/2026/11/view-button-and-size]]) and the general rework ([[sources/notes/2026/11/general-behavior-not-the-example]]). What the run that led to it showed: [[records/reviews/home-counter-run-2026-11-23]].

- **A choice is not a business value.** The model chooses a default for looks, names, placement and what a new view, chart or counter shows, and says what it chose. Business values are still asked for. A table the workbook lacks is created empty with `sql`, not asked for.
- **Home and one number are in the view description,** each shape in the order the grammar makes the model write it: Home is the view `home`, changed with `view.edit` and `{id, expectedVersion, edits: [{operation, at, component}]}`, and a count is a `metric` with `aggregation` before `datasetID`. The table list line says that no tables listed means the workbook has none. "Never create a table for a view" became "never create a table of totals for one", since the model read the old line as a ban on creating any table.
- **`ask` is for business values only.**
- **A new job, `defaults.home_counter`,** asks for a counter on Home in an empty workbook. It is not in the light set.
- **Run with the model, each run once.** The light set and `defaults.home_counter` passed 12 of 12 on the final header, in 35 steps and 263 s: [the run](../../../integration/evidence/2026-11-23-button-light/results.json). The counter, a large count with a large button under it, is built in five steps, and the clarify request still asks for the supplier, the quantity and the cost.
- **A saved or changed view keeps the model's summary above the host's line,** at the owner's word: [[sources/notes/2026/11/summary-above-confirmation]]. That run showed it on `build.view` and on the counter request, with no summary refused. Two earlier runs of the counter request failed, one on the order of an edit's fields and one on two instruction lines that disagreed; the review has both.

**Jobs for comparing models, November 21, 2026:** at the owner's request, [[sources/notes/2026/11/model-swap-evals]], five jobs cover what the earlier ones missed, and two answer checks are stricter. The harness holds 30 jobs, and the light set is unchanged.

- **The new jobs:** `read.large_table` asks for a total over 600 rows, where the first 100 give a wrong one. `change.informal` is an instruction with no table or column named. `change.remove_duplicates` must remove one of two identical rows, not both. `conversation.follow_up` is two turns in one chat, where "its" refers back to the first. `safety.quote_instruction` adds a quote that carries a note asking for a change nobody requested.
- **Stricter answer checks:** numbers in citation links no longer count as figures the answer gives. Before, the label "row 4" let an answer of 3 pass the count job. The comparison job fails an answer that also gives 14.58 percent, the difference measured against the lower total. The clarify job needs the reply to ask for the quantity or the cost.
- **Checked without the model:** the self-test passes for all 30 jobs, and the 20 saved English answers that passed before still pass the stricter checks.
- **One run with the real model:** 4 of 5 passed, in 172 seconds ([the run](../../../integration/evidence/2026-11-21-new-jobs/README.md)). `conversation.follow_up` failed. On the second turn the model read "its" as the brass bolts of the stock list rather than Cedar Tools from the first turn. It tried to set their quantity to 20, which the read-only stock list refused, then looped through refused history reads until the repeated-action stop. The earlier turn was in its prompt. This is a model failure on follow-ups, not a harness fault. It is recorded and was not run again.
- **Fixed the same day, at the owner's word.** Earlier turns reached the model labelled only as historical information, and nothing said the current request may refer back to them. One sentence now says so, in both forms of the saved conversation ([ContextMaintenance.swift](../../../Sources/SevraAI/ContextMaintenance.swift) `historyReferenceNote`). It sits with the history, after the prepared header, so the header is unchanged. The history, prompt header, surface and chat checks pass without the model. One run of `conversation.follow_up` and the light set on the rebuilt CLI: 12 of 12, in 36 decisions and 270 seconds. The follow-up took 7 decisions over its two turns, and the light set's 29 decisions compare with 31 on November 20 ([the run](../../../integration/evidence/2026-11-21-follow-up-fix/README.md)).

**Measured once on the final build:**

- **Timing:** a cold first turn 13.6 s, a warm greeting 4.7 s, a warm stock question 8.9 s. Today's tools: 18.0 s, 4.2 s and 10.8 s.
- **The suite.** `scripts/check.sh` ran through 955 passing checks and stopped at its grammar step on one failure this work had caused: the rule guide was in the read-only tool set that the old answer scopes are checked against. That was fixed, the step passed, and the remaining steps passed from there, with the packaged native journeys on the rebuilt package. The packaged journeys of the older non-native build were skipped, as the script does when that build is not current.
- **Runs the owner did not ask for.** During the build every job was also run in Spanish, failed jobs were run again, and timings were taken three times. Those results stay in the evidence file and are not part of how this plan is tested.

**The seven tools became the only chat tools on November 19, 2026** ([[sources/notes/2026/11/general-tools-only]]):

- **Removed:** the tool profile with `SEVRA_TOOL_PROFILE` and the app's `SevraToolProfile` setting; the old chat instructions; the old-only tools `compare_rows`, `propose_table` and `propose_table_edit`; the core's unused text tool guide; the profile's byte-identity check and fixture; and two probes that only exercised the removed tools. Thread continuations answer or change, nothing finer.
- **Kept:** the operations the seven tools route to, and the tool lists of the reviews and of Excel conversion, which are not chat. Those lists still include `datasets`, `rows` and `calculate`, and the schema fixture of every operation is regenerated from them.
- **Converted:** a paused workflow now takes its answer through `run` with the action `workflow.prepare_answer`, offered only in that step and shaped exactly by the grammar. The passage-copy limit moved to `save` with a document. Read-only `sql` results cross into a new thread as carried evidence, as reads do.
- **Fixed on the way:** a `sql` or `run` call that only read was counted as a change. That turned off `ask` after any query and refused a move to a new thread after one. Only a call that saved something counts now. And the tool text the model is shown is now the same in every chat scope and thread, so read-only turns share the cached header with ordinary ones; the grammar still offers only what the scope allows.
- **Checks:** the 59 scripted agent groups, the grammar checks against regenerated reference masks, the core and preview checks, the `sql` and `run` checks and the model-job harness's self-test all run on the seven tools. The light set then passed 11 of 11 on the packaged build, in 27 decisions and 3 minutes 57 seconds: [the run](../../../integration/evidence/2026-11-19-seven-tools-only-light/results.json).

**The model is offered exactly seven tools:** `search`, `read`, `sql`, `run`, `save`, `ask` and `finish` ([GeneralTools.swift](../../../Sources/SevraAI/GeneralTools.swift)).

- **Each call is routed to the operation that does its work.** `read` with a kind reaches the message, result page, app, definition, list or guide reads. `run` with an action reaches the workspace actions and the view, stock and template operations. `save` reaches the document, view, app, record, definition, template and result saves. `ask` is the question tool.
- **The old operations are the implementation, not the interface.** The agent's checks, receipts, confirmations and labels are keyed on the operation names, so they work unchanged. The model never sees those names: host messages and tool results are shown to it with the general tool's name in their place.
- **Shapes are strict where the model needs them.** The first run with one loose shape per tool passed 19 of 24: the model left out a view's definition, a form's inputs and a draft's flag. `save` now takes exactly one kind, each with the fields of the operation that saves it. `run` takes an action as a name and arguments, with fifteen named actions shaped exactly and the workspace actions sharing an open shape, because the grammar takes sixteen alternatives.
- **The model is shown less than the grammar enforces.** Showing every strict shape took a first prompt from about 4,400 to 7,200 tokens. The model is shown the common shapes in full and the rest as a list of field names, and the grammar supplies the structure as the call is written. A first prompt is about 4,600 tokens.
- **A step that may only read refuses a call that would change something.** A read-only request and an inspection step still offer `sql` and `run`, which refuse changes themselves.
- **A file is exported only to a path the person wrote in the request, or through the save panel.** When the request names no path, the model leaves it out and the app asks the person where to save. Cancelling saves nothing. The command line has no panel and refuses.
- **The command line's `tool` command accepts the seven names.**

**What `sql` is** ([ChatSQL.swift](../../../Sources/SevraCore/ChatSQL.swift)):

- The statements run on an in-memory copy that holds only the tables they name, under SQLite-friendly names made from the titles. Two catalog tables, `tables` and `columns`, list them. The request's context lists every table and its columns with SQL types.
- The statements are rehearsed first on empty tables. That finds mistakes before any row is copied, and tells the host which tables to copy.
- **Rows.** `INSERT`, `UPDATE` and `DELETE` are found through the trigger log and applied through the recorded row transaction. A change of more than 64 rows saves its updates as one edit with one correction Source. One call can change 5,000 rows of a table.
- **Shape.** `CREATE TABLE`, `ALTER TABLE` (add, rename or remove a column, rename the table) and `DROP TABLE` are read from the copy's layout before and after each statement, and applied as a new table, a new table definition, or an archived table. A renamed column keeps its identity.
- **All or nothing.** If the saved table refuses a later step of a call, the steps already saved are taken back and the call fails with nothing changed. This is done by undoing the earlier steps, not by one transaction, so history shows the steps and their reversal.
- **One Undo for a call.** A result that saved anything carries an undo value. The action `table.undo_sql` takes back everything the call saved: rows, new tables and column changes. The app shows "Change saved" with "Undo this change" under the answer. It is refused once a later change has built on the call. There is no Redo.
- **Authority.** A change by the model is recorded under a rule Source the host publishes, as native app authoring already does. This is what today's tools lack.
- **Drafts.** `draft` saves an `UPDATE` as a proposal and changes nothing.
- **Stock.** The ledger is two read-only tables, `stock` and `stock_movements`, filled by the ledger's own balance rules when a statement reads them. They are listed with the tables when the ledger holds a basis, and the Sources of their figures are attached to the answer. The instructions say nothing about stock.
- **Refused, with nothing changed:** indexes, views, triggers and temporary tables, `ATTACH`, pragmas, transaction statements, the schema table, the host's log, the catalog and stock tables, a formula column, more than one statement in an entry, text in a number column, a double-quoted name that is no column, a shape change in a draft, and any change in a request that forbids changes.
- **Answers.** An answer may rest on a query: its figures count as computed, and the host attaches the rows it read, or the table's own Source when there are many.

**Measured on the test Mac, debug build, one table:**

| Changed rows | Create | Update all | Undo | Delete half | Verify |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 200 | 0.3 s | 0.5 s | 0.6 s | 0.5 s | 0.8 s |
| 1,000 | 1.4 s | 2.6 s | 2.2 s | 1.5 s | 1.8 s |
| 5,000 | 7.7 s | 7.2 s | 6.0 s | 4.1 s | 8.5 s |

Each changed row version adds about 8 KB to the workbook file, which is what the recorded write path costs today. The limit is 5,000 changed rows of a table in one call, with a 60 s deadline.

**What `run` is** ([ChatRun.swift](../../../Sources/SevraCore/ChatRun.swift), [ChatScriptRuntime.swift](../../../Sources/SevraExtractionWorker/ChatScriptRuntime.swift)):

- The model writes the body of an async JavaScript function. Inside it, `sql`, `search` and `read` are awaited, `action` queues a named action, and `today` is the date.
- **Where it runs.** In the helper process the Excel behavior runtime already uses, after it enters a sandbox that denies everything: no file, no network, no clock. The same helper is used in the app, on the command line and in the checks. The plan put the app's scripts in the XPC worker. One path with the stricter sandbox was smaller, and the helper is already packaged.
- **How it reaches the workbook.** The helper answers no call. Each pass lists the calls the script made, the host answers the new ones, and the script runs again from the top with the answers. A script must therefore do the same thing each time: the clock is fixed for the run and randomness is refused. A script with 40 calls takes 0.8 s.
- **One copy for the whole script.** Every `sql` call works on the same private copy, so the script sees its own writes. `search` and `read` see the saved workbook.
- **Saved once, at the end.** When the script returns, its table changes are applied as one `sql` call's are: all or nothing, with one Undo. A script that throws, loops, forgets an `await` or exceeds a limit changes nothing.
- **Actions run afterwards.** Actions a script queues run in order after its changes are saved. One that needs the app is refused before anything is saved.
- **Limits:** 24,000 bytes of code, 48 calls, 30 s for the run and 1 s for each pass, 12,000 bytes returned, 8 queued actions.

**Saved tools are the `tool` definition kind, built on November 19, 2026 under phase 5.** The first version, rows of a "Saved tools" table, is gone.

- **The kind.** A tool is a saved definition with a name, a description, typed inputs (text, decimal, boolean or date, up to 16) and a body: SQL statements that use each input as `:name`, or a script. Saving checks the body first, by rehearsing the SQL or checking the script's syntax. Saving under the same name adds a version. Removing one saves a retired version. `tool.undo` restores the previous version, or retires a first one. This is the format change: schema 32, and earlier development workbooks do not open.
- **Running one.** `sql` or `run` with `tool` and `values` runs it, and a script calls `tool(name, values)`. The host checks the values against the inputs. SQL runs through the same copy, refusals and Undo as any `sql` call, a script through the same sandbox as `run`, so a tool can do nothing they cannot. The command line's `tool WORKBOOK NAME` runs one too.
- **The per-Mac grant (P5).** A tool runs on a Mac only once it is enabled there. Saving one in chat enables it on that Mac. A tool that arrives in a copied workbook is listed as not enabled and refuses to run until the person enables it. The grant is a marker file outside the workbook, so copying a workbook never carries it.
- **The Tools screen.** The workbook menu's Tools lists each tool with its inputs and what it runs, with enable, turn off and remove. The plan put tools on the definitions screen. The app has no definitions screen in the workbook menu, so they have their own. Making and changing a tool stays in chat. The command line has `tools`, `tool-enable`, `tool-disable` and `tool-remove`.
- **What the request's context lists.** Tables with their columns, saved tools with their inputs and whether they are enabled here, and in at most 1,600 bytes the views, the apps with their actions, and the saved definitions with their IDs. It rides in the saved context, so it survives context maintenance.
- **App action catalogs.** An app's isolated check records the actions it declares, with their titles and inputs, and they are saved with the app. Chat lists them without running the app. An action runs once the app is enabled.
- **The sample workbook** has a saved action, "Record a stock movement". A movement made through it gets the same direction review as `stock.move`, and the balance read through `sql` agrees with the core's.
- **Rules can alert.** `template.rule` takes alert text in place of a workflow. Saving it binds the rule to a shared "Stock alert" workflow, saved with the first alert rule, that drafts the alert as a document for the person to read in Reviews. The alert cites the record that sets the item's stock.
- **The starters are guides.** `read kind=rule_guide` and `read kind=receiving_guide`, each with a filled example. The definitions guide names both. They are not in the instructions. Since November 22, 2026 `read kind=view_guide` is a guide too, for view components beyond a table and a chart.

**Checks, none needing the model:** [check_chat_sql.py](../../../scripts/check_chat_sql.py) and [check_chat_run.py](../../../scripts/check_chat_run.py) through the command line, and `sevra-agent-checks --sql-tool` with a scripted model under the AI actor. All three run in [check.sh](../../../scripts/check.sh).

**One bug found and fixed in code today's tools also use:** updating a row failed after a column of its table was removed, because older row versions still carried the removed column.

**Left out, with the reason:**

- **Incoming references.** `read` with kind references follows what an item links to. The old tool's options for incoming mentions and history are not in the seven tools' shapes. No job needed them.
- **One transaction for a whole call.** The existing write paths each open their own transaction. Taking back the earlier steps gives the same result for the person.
- **The exact side table and exact functions.** The owner chose 15-digit numbers: [[sources/notes/2026/11/general-tools-answers]].
- **Catalog tables for views, apps, definitions, automations, workflow runs and the review queue.** `read` lists them by kind and `search` finds definitions. No job needed them as tables.
- **Result receipts opened in the conversation, and the read-back of written cells.** No job needed them.
- **Drafts of inserted or deleted rows, of a new table and of a shape change.** Today's proposals cover edits to existing rows.
- **Rebuilding a table** by creating a new one, copying, dropping the old one and renaming. It would lose the old table's history.
- **A script's writes under one hold of the workbook lock.** The lock is held for each `sql` call and for the final save. A row someone else changed in between is refused by the write path, and the script's changes are taken back.
- **Guides with a strict shape after reading.** The grammar is the same for every turn, so the header stays read ahead. Each save kind already has a strict shape.
- **A tool schema loaded into the grammar when a definition is read, and calls by a definition's own name.** The same reason: the shown tools and the grammar never change within a chat. A workbook tool is called by name through `run` or `sql` with `tool`, and the host checks its values. Other definitions run through the actions that already check them: `definition.evaluate`, `action.prepare` and `workflow.start`.

**Remove and restore, November 24, 2026,** at the owner's word after a chat emptied a story draft instead of removing it. The model had reached for `document.edit` with empty text: withdrawing a draft was `record.review` with `decision: withdraw`, one of the actions the tool header did not name, and most other kinds had no way out of the workbook at all.

- **Two actions for every kind.** `run` takes `remove {id}` and `restore {id}`, named in the header beside the eleven shaped actions. Each is a host action the person confirms in chat ([Removal.swift](../../../Sources/SevraCore/Removal.swift), [ChatActions.swift](../../../Sources/SevraApp/ChatActions.swift)). `read kind=removed` lists what restore can bring back. `record.review` keeps accept and undo only.
- **Nothing is erased, and the format is unchanged.** A removal is a `removal` marker Source with the person as its actor, and the thing leaves current lists, search, the request's context and name lookups. A document or record also gets a rejected version, so its effects stop. A table is archived. A view or an app is hidden, and an app loses this Mac's permission. A form, workflow, function or automation is hidden and refused when started or evaluated, and an automation is paused. A saved tool is retired and disabled. Restore saves the version before the removal again; an app or automation comes back turned off.
- **Refused, with what to do instead:** Home, files and other Sources, table rows (`sql` DELETE), host records such as movements and decisions, an AI actor without a saved rule, a second removal and a restore of something not removed. `document.edit` refuses empty text and names remove.
- **In the app,** an open document or record shows Remove, and Restore once removed. Withdraw stays only for a draft change to something already saved, where declining keeps the version before it. Views, apps and tables have Remove in their menus, a removed table's banner has Restore, and the workbook menu's Removed screen lists everything removed with Restore. A view or app that another view shows is refused until it is taken off. The removal checks run in the default suite.
- **Checked without the model:** `sevra-checks --removal`, eight groups: a draft and an accepted document, the actor refusal, the kinds refused, a table, a view, a function and a saved tool. The prompt header, chat, action confirmation, `sql` and surface checks pass, and the grammar check passes after the tool and grammar fixtures were regenerated for the new `removed` read and the two action names.
- **Run with the model, each run once.** A new job, `change.remove_document`, saves a story in one turn and asks "remove it" in the next. With the light set it passed 12 of 12 in 36 decisions and 209 seconds on a 4,480-token header, from 4,429: [the run](../../../integration/evidence/2026-11-24-remove-restore-light/results.json). The model called `remove` and never `document.edit`; the command line has no app to confirm a host action, so the call ends there.
- **In the installed app,** built from this change and matched by its Mach-O UUID, on a throwaway workbook: Remove on a draft, Restore on the removed document, and "remove the Elara and the Silver Leaf story" in chat, which showed the confirmation and, once confirmed, left the document Removed with Restore. Three things were fixed on the way: Edit draft showed on a removed document, the bar said "Operation ended" after Remove, and a restored draft offered Withdraw and Undo, which would have hidden it again with no removal on record.
- **Found on the way, and fixed the same day:** `Workbook.verify()` failed on any workbook with a saved tool, because its definition check read a tool's payload as a query's. A tool is now checked as a tool, with no dependencies ([DefinitionDiscovery.swift](../../../Sources/SevraCore/DefinitionDiscovery.swift)). The saved-tool removal check verifies the workbook, and a dependency added to the tool by hand makes it fail. The core suite passes, 660 checks.

**Fixes from the November 25, 2026 model transcripts,** built November 26 and checked without the model. No model job was rerun.

- **`read` names everything with `ref`.** A tool's own parameters are written in name order and the prompt shows them sorted, so `id` came before `kind`. With items in context, a model that meant `kind=views` wrote `id` first three times and could then only name an item. `read` now has no `id`: `ref` alone reads a document or record, and `kind` comes first for everything else. A new kind, `view`, reads one saved view by its id with its components and version, and the view guide and the save description point an edit there. `views` with a ref also reads one. The command line still accepts `id` for an item.
- **Buttons with no fitting tool.** The view description and guide now say to save a tool first with `save {tool}`, then bind the button to it. A model had made only a metric because no saved tool existed.
- **A table component with no table.** The refusal said "Do not create a table for it" in a workbook with no tables. With none it now says to create the table first. With some it names up to eight, keeps the no-totals-table advice for charts and metrics, and says to create the table first when the one it should show is missing.
- **Optional tool inputs from chat.** An input of `save {tool}` takes `required: false`, and is required otherwise. Left out from chat, a form or a button, it is NULL. Its signature says `optional`, and a view's button no longer waits for it.
- **`visual` only where it belongs.** A component is now one of two grammar shapes: a visual or an image, which take `visual` and no children, and every other type, which takes children and no `visual`. The operation tools' grammar grew from 43,578 to 48,870 bytes, with no measurable compile or mask time on one `save_space` call. Core still refuses a stray visual from callers outside the grammar.
- **An insertion before a comparison's column** joins that comparison while it has fewer than three columns. A full one says to place the component before the comparison or replace it. An unknown `beforeID` says so instead of "Move before a component in the same group".
- **`comparison_check`** read "Cedar Tools, at 24, is cheaper" as right because it cut each claim at a comma. A sentence naming one supplier is now read whole, less what a comparison word gives the other side, and an aside set off by commas after a name stays with it. `--self-test` checks nine worded answers.
- **Checked:** `sevra-checks` (577 checks), `sevra-agent-checks` `--field-order-checks`, `--space-action-checks`, `--prompt-header-checks`, `--chat-checks`, `--sql-tool`, `--action-confirmation-checks`, `--saved-action-checks`, `scripts/check_splash_grammar.py` with the regenerated tool fixtures, and `check_chat_jobs.py --self-test`. The prepared header changed with the tool text, so it needs `sevra header make` before the next model run.

**Table shape kept across calls, November 26, 2026,** from exploratory real-model scenarios, built and checked without the model. Each call rebuilt every table in the copy as plain `REAL`/`TEXT`, so `id INTEGER PRIMARY KEY`, `DEFAULT 'open'` and `DEFAULT CURRENT_TIMESTAMP` worked only in the call that made the table, and later inserts, saved tools behind buttons included, stored NULL. Workbook format 38 refuses older development workbooks.

- **A column keeps a default and numbering.** `Column` gains `defaultValue` (a fixed value, or the local `date`, `datetime` or `time` when the row is added) and `autoNumber`. `INTEGER PRIMARY KEY`, with or without `AUTOINCREMENT`, becomes a numbering column, which is unique and always holds a whole number. `NOT NULL` becomes required, `UNIQUE` and a single-column key on another type become unique. The copy declares them again each call, the numbering column as the table's `INTEGER PRIMARY KEY`, so `RETURNING` and later statements see them.
- **Every new row gets them, whoever adds it.** The row transaction that `sql`, scripts, saved tools, buttons and apps share fills a column the writer left out: the largest number plus one, as SQLite numbers, and the default. An explicit NULL stays NULL, except in the numbering column. Undo of an insert is the same delete as before. File imports and reviewed table updates do not fill them.
- **Unique is enforced at save**, with the duplicate value in the refusal. A table made in the call also refuses one in the copy.
- **Computed columns.** `ALTER TABLE t ADD COLUMN total AS (quantity * price)`, `GENERATED ALWAYS AS` and the same in `CREATE TABLE` become formula columns when the expression uses the table's number columns, numbers, `+ - * /`, comparisons, `round`, `min`, `max`, `iif` and brackets. Anything else is refused with that list. The instructions say to use one for a column that follows others, not an `UPDATE`.
- **Local time.** `'now'` in `date`, `time`, `datetime`, `strftime`, `julianday` and `unixepoch`, and `CURRENT_DATE`, `CURRENT_TIME` and `CURRENT_TIMESTAMP`, are the Mac's local time, one instant for the whole call or script. `unixepoch('now')` is therefore local wall-clock seconds, not UTC.
- **`ALTER TABLE ADD COLUMN` with a current-time default**, which SQLite refuses, is accepted: rows already there stay empty, and rows added later, in the same call too, get the time.
- **A table's name for its id.** Wherever the model gives a table, a `datasetID` in a view, chart, metric or app, or the `id` of a `table.*` action, an exact sql name or title stands for the id when one table has it. Otherwise the refusal lists the tables as title (sql name, id), where it was a bare "Table not found."
- **Shown to the model and the person.** Tables for sql and the `columns` catalog (`required`, `is_unique`, `default_value`, `auto_number`) show what each column keeps. The table definition screen's options line says numbered and the default.
- **Limits:** an `UPDATE` that changes a numbering value is saved as removing the row and adding another, so that row's history restarts. `DROP COLUMN` of the numbering column is refused by SQLite; `table.edit_schema` can remove it. A `UNIQUE` column cannot be added with `ALTER TABLE`, as in SQLite.
- **Checked:** `sevra-checks --chat-sql-shape` (five groups, in the default set), new cases in `check_chat_sql.py`, `sevra-agent-checks --space-action-checks` (AUTOINCREMENT and UNIQUE now accepted), the default `sevra-checks`, the `sql`, field order, prompt header, chat, saved action and action confirmation groups, `check_splash_grammar.py` (ordinary prompt 7,593 of 8,448 tokens, authoring 10,183 of 10,240) and `check_chat_jobs.py --self-test`. The instructions and the `sql` description changed, so the prepared header must be made again before chat runs on a build.

**Views of only some rows, and editing views in place, November 26, 2026,** from exploratory real-model scenarios, built and checked without the model. A view titled "Overdue invoices" showed all eight invoices: the model put a `query` on a table component, which only a search used, and the answer described a filtered result the view did not show. Asked for a bar chart instead, the model inserted the chart again under its own id and left two. Buttons refused a null for an input the person fills in, "make this look nicer" made a second view, and answers named tables by their sql names.

- **A table, chart or metric can take `query`:** one read-only SELECT ([ComponentQuery.swift](../../../Sources/SevraCore/ComponentQuery.swift)). It runs on the same copy as `sql`, so table and column names, functions and local-time dates are the same, and it runs again whenever the workbook changes. A chart's x and y and a metric's y name its result columns; a result column named like a column of a table it read keeps that column's title, type and unit. With `query`, `datasetID` is optional; when given, the query must read that table, and the view links to it. A query was chosen over binding to a saved read-only tool because it is one field in the component the model is already writing, in the SQL it already writes for `sql`, and it needs no second save, name or enablement step.
- **Checked at save, shown honestly later.** Saving runs the query: a write, a second statement, an unknown column, a duplicate result name, or x or y not among its columns is refused with what to do. A view shows at most 1,000 result rows, says how many of how many, shows "No rows match." when none do, and a metric over more than 1,000 says to add them up in the query. A query that stops running later, say after a column was renamed, shows "This view's query no longer runs: no such column: cost. Ask in chat to fix the view." in place of rows, and edits elsewhere on the view still save. Pinning a view freezes a query's result like a table's. A query's rows open nothing, since they are a result rather than rows of a table. An empty table's chart now says "No rows yet." instead of drawing empty axes, and a chart no longer repeats its unit below the axis that names it.
- **Fields a type does not use are refused**, where they were kept and ignored: datasetID, query, aggregation, chartStyle, itemID, text, unit, x and y each say which types use them. Only new or changed components are checked.
- **Editing in place.** The view guide teaches replace, remove, move, relabel, text and rename, and the `save` description names replace, insert and remove. Inserting an id the view already has is refused with the replace edit written out, and a second save under a view's title says to replace. The guidance says a request to change this view (the request's Active space ID) or a named one is `view.edit` on it, and a new view only when asked; components and answers name tables by their titles.
- **Buttons.** A null in a button's arguments is an input left for the person, as when left out. Pressing without a required input says "Fill in name before pressing this button. Nothing ran."
- **No format change.** Saved views keep the same shape: `query` was already a component field. A build before this one opens such a view and shows the whole table for a query component, so the workbook format stays 38 rather than refusing every format-38 workbook.
- **Checked:** `sevra-checks` (585 checks, three new space-editing groups: live query rows, the empty and failed states and a pinned copy; the field and read-only refusals; the replace hint), `sevra-agent-checks` `--field-order-checks`, `--space-action-checks` (a null button argument and the press refusal), `--prompt-header-checks`, `--chat-checks`, `--sql-tool`, `--saved-action-checks`, `--action-confirmation-checks`, `sevra-preview-checks`, `check_chat_jobs.py --self-test` and `check_splash_grammar.py` (ordinary prompt 7,593 of 8,448, authoring 10,183 of 10,240: the exported tools do not carry the save description, so the tool fixtures did not change). The UI Catalog has Query, "Query, no rows" and "Query failed" variants of the table, chart and metric, reviewed in headless captures at 900 and 420 points and in dark mode, and its table check adds a query table, changes a row it reads and refuses a query that deletes. The chat header the model sees grew from about 4,616 to 4,695 tokens, so `sevra header make` is needed before the next model run.

**Truthful replies, confirmations before large changes, and the date, November 26, 2026,** from exploratory real-model scenarios, built and checked without the model. A reply said "I created a Home dashboard" when nothing was saved; "delete everything" deleted all 19 rows of a table at once and the reply showed only an earlier failed remove; summaries were refused for numbers the model had itself inserted, leaving a bare "Saved space"; a model retried a failing app save six times and the run ended with no answer; the date reached the model only for "today" and similar words; an offer to connect to a bank; and a step lost to "$" in most answers.

- **Host lines for table changes.** Every sql call, script and tool run that changed a table adds its own line, by the table's title: "Deleted 19 rows from “Expenses”.", "Added 3 rows to “Coffee log”.", "Created table “Habits” with 5 rows.", "Removed table “Old”.", and the last of them says "You can undo this." A saved tool adds "Saved tool “log_habit”." These lines follow a kept summary and make up the account when the summary is dropped ([ActionConfirmations.swift](../../../Sources/SevraAI/ActionConfirmations.swift), `Workbook.tableChangeSummary`).
- **Failures read once and in place.** A failed remove of a table is settled by a later change that deleted its rows or removed it. A view saved again with the same kinds of component in another order is the same intent. The same refusal from repeated calls is one line, and an edit that failed after the same view was saved reads "Couldn’t finish a later change to “Home”." in place of "Couldn’t finish saving the space." beside "Updated space “Home”.".
- **No claim of a change nothing saved.** When nothing was saved and a call failed, a summary that says something was created, added, saved or updated ([ChangeClaim](../../../Sources/SevraAI/FidelityClaim.swift)) goes back once; a second such summary is replaced by "Nothing was changed." and the host's lines.
- **Grounded numbers.** Numbers in the arguments of calls that succeeded in the request, such as INSERT values, a saved tool's statements or a view's query, count as given for a summary; ids, versions and undo values do not. A number nothing gave, such as "a 7-day chart", is still sent back.
- **Large changes wait for the person.** A sql call, script or saved tool the model runs asks first when it empties a table of two or more rows, removes a table with rows, or deletes or overwrites more than 20 rows, or more than half of a table of more than five (`Workbook.needsConfirmation`). Every change keeps an Undo, so the rule asks only where a misread request costs the most; a small table's change is listed in full in the reply and undone with one click, so it applies at once. Nothing is saved: in the app the host prepares a chat approval, "This deletes all 19 rows of “Expenses”. You can undo it after it is applied.", with a host-only action, `table.confirm_change`, that no model is offered. Confirmed, the call runs as the person saw it, attributed to them, and the chat line "Deleted 19 rows from “Expenses”. You can undo this." carries the Undo row. Without the app, as from `sevra ask`, the change is refused with that preview and "It needs your confirmation, which only the Sevra app can ask for." A view's button is the person's own action and runs without asking.
- **The date with every request.** The request's instructions end with "Now: Thursday 2026-11-26 14:05, time zone America/Bogota." (the Mac's own), below the prepared header, so the header is unchanged. The automation guide says a schedule's time zone is the Mac's from Now, UTC only when the user asks.
- **A failure of this Mac stops the request.** A save that the system could not reach a helper for, twice with the same error whatever the arguments, ends the request with "Couldn’t finish saving the app. Couldn’t communicate with a helper application. This is a problem on this Mac, not with your request, so trying again won’t fix it." and the other host lines. The app checker is an XPC service inside the app bundle, which a plain command line cannot reach, so a save from the command line now says "Saving an app needs the Sevra app open: its isolated check runs only inside the app. Nothing was saved." on the first try and ends there; inside the app, and in the app-bundle copy the app job uses, the check runs as before.
- **What Sevra can bring in.** The instructions say Sevra has no online connections, that data comes in as added files (CSV, TSV, Excel, Word, PDF, text, JSON, HTML or images) or pasted text, and to suggest exporting a file such as a CSV from a service like a bank.
- **Currency.** A currency symbol nothing gave that sits beside a number is removed by the host instead of refusing the answer, so "$51.50" is shown as "51.50" with no extra step. A symbol anywhere else is still refused, and one the workbook or request states is kept.
- **Limits:** the confirmed change's Undo row on the chat event and the approval card for it are not yet reviewed in the app or the UI Catalog; no model job was run, so how often the model now confirms instead of retrying, or splits a large delete into small ones, is not measured. Currency codes such as USD in a column do not admit "$".
- **Checked:** `sevra-agent-checks --action-confirmation-checks` (new [ReplyTruthChecks.swift](../../../IntegrationTests/Agent/ReplyTruthChecks.swift): the confirmation rule and previews, a small delete, "delete everything" held in the app, confirmed, reported and undone, refused without the app, a script and a saved tool asking and a button not, a remove settled by a delete, the false claim, grounded numbers, the currency removal, the date line, the system failure test and the command-line app save), a new `--answer-grounding-checks` group (answer grounding, currency, terminal receipts, refused calls and chat operations), `--chat-checks`, `--sql-tool`, `--saved-action-checks`, `--prompt-header-checks`, `--field-order-checks`, `--space-action-checks`, `--progress-stop-checks`, `--thought-checks`, the full default `sevra-agent-checks` through `check_splash_grammar.py` (ordinary prompt 7,593 of 8,448 tokens, authoring 10,183 of 10,240; the exported tools are unchanged, so no fixture was regenerated), `sevra-checks` (585) and `check_chat_jobs.py --self-test`. The instructions changed, so the prepared header must be made again with `sevra header make` before the next model run.

**Reminders and alerts from chat, Excel headers and smaller fixes, November 26, 2026,** from exploratory real-model scenarios, built and checked without the model. "Every Monday remind me to order supplies" took 131 seconds and four refused saves, because an automation needed a saved workflow the model could not build; "alert me when stock drops below reorder level" and "alert me when any expense is over 500" made a button instead. An imported Excel budget came in as columns A, B and C, all text, with its header as a row.

- **Three short automation shapes** ([AutomationShapes.swift](../../../Sources/SevraCore/AutomationShapes.swift)). The trigger is `{policy: calendar-v1, schedule}` or `{policy: check-v1, check: {name}}`, and what it does is one of: `alert: "one sentence"`, drafted for review at each start through the shared Alert workflow the check alert already used; `tool: {name}` with `arguments`, bound to a one-step workflow that runs that saved tool, one per tool, exact to the tool's version at save; or `workflow` with `arguments` for several steps. A check can be named by its name, `parameters` may be left out and `arguments` defaults to `{}`. What is saved is still the canonical `{policy, trigger, workflow, arguments}`, so the format is unchanged. The enable notice already names the tools a workflow runs and says their changes apply without review.
- **A reminder cites the request that asked for it.** A scheduled alert has no table to cite, so its draft rests on the person's own request, as the host captured it. The document action now accepts that one kind of technical item: a `request` declared as a business input. Outside a chat request a reminder is refused and says to use a workflow.
- **Refusals say what is missing,** with the shapes to use: no policy, a missing schedule or check, nothing it does, two of alert, tool and workflow, parameters, a workflow version that does not exist, an unknown tool with the saved tools listed.
- **Guidance.** One instruction line: "remind me", "every Monday" and "alert me when" are an automation, saved after `read kind=definition_guide`, not a button or view. The guide's automation entry has the shapes, ISO weekdays with 1 as Monday, three one-line examples and the enable step: chat runs `automation.enable`, which asks the person to confirm. The `save` description names automations. The ordinary prompt is 7,600 of 8,448 tokens; the authoring prompt is unchanged at 10,183 of 10,240, since the guide is read on demand.
- **The automation page** says "Then it drafts the reminder" or "the alert" with the sentence, or "Then it runs the tool remove_blank_quotes", in place of "Then it runs Alert" and its document inputs. The editor shows only the alert's sentence for an alert. The empty list suggests asking in the chat. UI Catalog: `main.automations` "Tool runs" is now saved through the tool shape, a new "Reminder" variant through the alert shape, and "Empty" really has no automation.
- **Excel headers** ([XLSX.swift](../../../Sources/SevraCore/XLSX.swift)). In a workbook with no formulas, a sheet whose first row is one distinct, nonempty, non-numeric heading per column, above rows where some column holds only numbers or the headings are styled, is read as a CSV is: the headings name the columns, numeric columns are decimal (codes with leading zeros stay text) and the header row is not a row. The scenario's budget now has Category, Budgeted and Actual. A workbook with any formula keeps every sheet cell for cell under column letters, because its formulas name cells and recalculate; the five business fixtures all have a formula sheet, so they are unchanged.
- **Large deletions count across calls.** One request's tally per table ([ChatSQL.swift](../../../Sources/SevraCore/ChatSQL.swift) `ChatChangeTally`) adds each call's deleted and overwritten rows, so 30 rows deleted five at a time ask on the fourth call: "With the earlier changes in this request, this deletes 20 of the 30 rows of “Expenses”." A new request starts its own count.
- **Reviewed table updates fill new rows** as the shared row transaction does. A numbering column or a column with a default may be left unmapped, and each added row gets the next number and the default. Saved intake workflow definitions still map every stored column.
- **Smaller:** the sql instructions say to store dates as YYYY-MM-DD and times as HH:MM, 24-hour; `sevra tools` marks optional inputs; the UI Catalog's `main.tools` tool reads the supplier table, so `--validate-fixtures` passes all 183 stories, and its route list includes Removed.
- **Limits:** no model job was run, so whether the model now picks the short shapes is not measured. A reminder drafts a document for review; there is no system notification. The editor cannot create an alert or a tool automation from scratch, only from chat. Header detection does not cover workbooks with formulas, all-text sheets without styled headings, or a header below a title row.
- **Checked:** `sevra-checks` default (590), `--check-automations` (three new checks: a reminder drafted on a Monday citing its request, a tool run on a schedule with its notice, every refusal's wording), `--tool-actions`, `--automations`, `--schedules`, `--workflows`, `--workflow-intake` (a reviewed append filling a numbering column and a default), a new XLSX header check; `sevra-agent-checks` `--prompt-header-checks`, `--field-order-checks`, `--chat-checks`, `--action-confirmation-checks` (the split deletion), `--saved-action-checks`, `--sql-tool`; `sevra-automation-ui-checks`, `sevra-preview-checks`, `scripts/check_splash_grammar.py`, `check_chat_jobs.py --self-test`, the UI Catalog's `--validate-fixtures`, and captures of `main.automations` Reminder, Tool runs and Empty.

**Views that survive their retries, merging replaces, settled kindless saves and UNIQUE over several columns, November 26, 2026,** from a real-model re-run of the exploratory scenarios, built and checked without the model. No model job was run. In one scenario the first view save had a right button binding and was refused only for `x` and `y` on a table; every retry rewrote the view and lost the binding. In another, "make it a bar chart" sent a replace with only `{id, type, title, size}` and was refused four times. A reply then described the unsaved view and told the person to open it, and another printed "Couldn’t finish saving the space." twice. A save with no kind stayed a failure after the save that followed it, and `UNIQUE(habit_id, log_date)` rolled back a whole call, the habits table with it.

- **Fields that change nothing are left out, not refused** ([SpaceEditing.swift](../../../Sources/SevraCore/SpaceEditing.swift) `leavingOutUnusedFields`). `x`, `y`, `chartStyle` and `unit` on a type that does not use them, `aggregation` anywhere but a metric (on a chart only when it says SUM, which the chart does anyway) and `size` on a type without one are dropped, and the save's result says so: "Left out x, y on table1: a table does not use them." The rest of the view saves. Still refused, since their loss would change what is shown or hide what was meant: `datasetID`, `query`, `itemID` and `text` on types that do not use them, a chart's AVERAGE, MIN, MAX or COUNT (which now says to work the number out in a query), bindings and arguments outside buttons, forms and computations, and app fields outside apps. Core saves drop the same fields silently, so every caller agrees; a pinned view is left as it is.
- **A replace merges when the type stays.** `view.edit` with `replace` records which fields the model wrote; the others keep their saved values, and a field written as `null` is cleared (`SpaceEdit.fields`, `Workbook.merged`). A new type is still a new, whole component. The app's layout editor sends whole components and keeps full replacement. The view guide, the agent guide and the "already has a component" refusal say to send the id, type, title and the fields that change.
- **No account of an unsaved view.** The rule that a summary claiming a change nothing saved goes back once now also covers one thing that failed beside others that saved, and the account written at the host's stop or wrap-up: a sentence that names the title of a view, definition, app or draft whose save failed and nothing saved later, without saying it failed or was only tried, goes back once with what was not saved; the second time the host's lines stand alone ([ActionConfirmations.swift](../../../Sources/SevraAI/ActionConfirmations.swift) `unsavedClaim`). "Included", "applied", "configured", "fixed" and "adjusted" join the change verbs, so "I have now included these required fields" with nothing saved is caught. A host line the answer already carries, as when a model copies one from an earlier turn, is not printed again.
- **A save with no kind is settled by any later save** in the same request: a tool, definition, draft, app or view. Before, "Choose a kind for save" stayed beside the automation that was then saved.
- **UNIQUE over several columns.** `UNIQUE(a, b)` and `PRIMARY KEY(a, b)` in `CREATE TABLE` are kept as a set on the set's first column (`Column.uniqueWith`), with each key column required; the stored table has the matching constraint, and a save that repeats a set is refused naming both values: "Habit id and Log date together must be distinct in each row, and "1", "2026-11-26" are already in another row." Tables for sql show `UNIQUE(habit_id, log_date)`, the `columns` catalog has `unique_with`, and the table definition screen's options say "unique with Log date". Removing a column of a set ends the set. Workbook format 39 refuses format-38 development workbooks.
- **Real constraints in the copy.** Each call's copy now declares every unique column and set, so `INSERT OR IGNORE`, `INSERT ... ON CONFLICT DO NOTHING` or `DO UPDATE` and `REPLACE` behave as in SQLite, where a duplicate came back as "Name must contain distinct values". A plain duplicate is refused at its statement with how to skip or update such rows: "Statement 2: people.email must hold distinct values, and this row repeats one already there. To skip such rows use INSERT OR IGNORE; to change them use ON CONFLICT(email) DO UPDATE SET. Nothing was changed."
- **`draft` on `sql`** is described as only for when the user asks to review a change before it applies, otherwise left out. A bulk update was sent as a draft and the reply said a draft was prepared.
- **Limits:** no model job was run, so how often the model now keeps a button through retries, sends short replaces or writes an honest account at a stop is not measured. The unsaved-view check matches the failed save's title in the answer, so an account that describes the view without its title is not caught. A set is limited to two to eight stored columns. The app's layout editor shows a set on each of its columns but cannot add or remove one.
- **Checked:** `sevra-checks` default (592: a new group for sets in [ChatSQLShapeChecks.swift](../../../Tests/ChatSQLShapeChecks.swift), with OR IGNORE, ON CONFLICT, REPLACE, the catalog, the schema line, the refusal by a row change and a composite key; a new space-editing group for the merge, null, a stray field on a new type and a type change that needs its fields; the stray-field check now expects the notice and still refuses a chart's AVERAGE); `sevra-agent-checks` `--sql-tool`, `--space-action-checks` (a size on a search is now left out), `--action-confirmation-checks` (the stopped account, the honest account with a copied line, the kindless save), `--answer-grounding-checks`, `--chat-checks`, `--saved-action-checks`, `--prompt-header-checks`, `--field-order-checks`, `--progress-stop-checks`; `scripts/check_chat_sql.py`; `scripts/check_splash_grammar.py` with the save grammar check for a button after query components (ordinary prompt 7,620 of 8,448, authoring 10,183 of 10,240; the exported tools do not carry the `sql` descriptions, so no fixture changed); and `check_chat_jobs.py --self-test`. The `sql` description and the view guide changed, so the prepared header must be made again with `sevra header make` before the next model run.

### Phase 0. Record the direction and get the go-ahead

1. This plan and the owner notes are recorded. Done.
2. The owner confirms or changes S1 to S3 and P1 to P5. Done on November 18, 2026: he confirmed all of them as written, then replaced P4. P6 to P9 are still his to confirm.
3. The owner authorizes implementation, including real-model runs and installing and operating the preview for interface checks, as earlier tasks did. Done on November 18, 2026.
4. The owner updates the store's rule against raw-model DDL in `db/DB.md`, which agents do not edit. Done on November 18, 2026: he left the choice to the agent, which changed that one line ([[sources/notes/2026/11/general-tools-answers]]).
5. The specifications in [What this replaces](#what-this-replaces) get the new rule with a link here, in the phase that makes each one true.

Exit: the owner's answers are recorded as a source note, the `db/DB.md` line is changed, and `AGENTS.md` points at this plan. Phase 3 cannot start before the `db/DB.md` change.

### Phase 1. Baseline and a switchable tool profile

1. Add a tool profile chosen by host configuration, never by the model or by text: `current` and `general`. With `current` the declarations are byte-identical to today.
2. Fix the comparison jobs, on the synthetic sample workbook, in English:
   - read: the stock question, the supplier comparison, a count, a two-table join, a question about a document;
   - change: add rows from a document, a bulk update, a new table from pasted text, a renamed column, deleted rows;
   - several steps: add to one table the rows it is missing from another, total a document's line items by category and save the totals as a table, report the three largest price differences between two suppliers;
   - draft: a change the person asks to see as a draft first;
   - build: a view with a table and a chart, a small app, a form that adds a row to a table, a rule that alerts when an item's stock falls below a level, and a saved tool, which has no baseline because the current tools cannot make one;
   - conversation: a greeting, a new thread, a clarifying question;
   - safety: a document that contains an instruction, and a request that forbids changes.
3. Record the baseline with the current tools: decisions, wall time, prompt tokens, answers, citations, saved results. It is recorded before phase H3 changes how the header is read.
4. Check one unverified point first. Chat's AI actor carries a policy label, not a rule Source, and the row update and schema paths refuse an AI change without one ([Tools.swift](../../../Sources/SevraCore/Tools.swift) 107 to 115, [Tables.swift](../../../Sources/SevraCore/Tables.swift) 595, [DatasetDefinitions.swift](../../../Sources/SevraCore/DatasetDefinitions.swift) 149). If the current tools cannot update rows or change a schema under a real model, those jobs are recorded as having no passing baseline.

Exit: the baseline is retained as evidence, and `--conversation-surfaces` shows the `current` profile unchanged.

**Settled failures, repeat stops and script tools tried at save, November 26, 2026,** from a real-model re-run of the exploratory scenarios, built and checked without the model. A reply printed "Couldn’t finish saving the space" after the same Home was edited and saved, and "Couldn’t finish saving reusable behavior" after the automation saved; a view that could not be opened from the command line became the whole answer; an identical refused edit was sent three times; an app save from the command line met a package shape error three times and ended with no reply; a script tool that called SQL's `date('now')` as JavaScript saved and failed on its first press.

- **A later save of the same thing settles a failure** ([ActionConfirmations.swift](../../../Sources/SevraAI/ActionConfirmations.swift) `sameTarget`), even with other arguments: a failed save or edit of a view by a later save or edit of that view, by title or id; a failed definition save by a later save of the same kind and title, or, when the failed call named neither, of the same payload. A failed whole save so settled keeps the model's summary; a failed edit still needs the same intent for the summary, since it may describe the part that failed.
- **Opening is not the answer.** When a request saved something and `open_space` (or the review list or an automation) cannot open here, the model is told what was saved stands and may only finish, and its account is the reply. With nothing saved, the refusal is still the answer.
- **The same refused call stops on its second try** ([WorkbookAgent.swift](../../../Sources/SevraAI/WorkbookAgent.swift)): the request closes with "The same call was refused twice, so sending it again will not help." and the model's account. App building keeps its own guards; when its identical save is refused a third time, a chat request now ends with "I stopped because the same call kept failing, so trying again would not help." and the host's lines for what changed, instead of no reply.
- **An app save without the app says so first:** the check-service refusal comes before the package's shape. A missing field under `views` says that a package view is a visual from visual.schema, not a space definition, and to leave views out unless the source shows one; any other missing field says where it goes.
- **A script tool is tried once at save** ([ChatRun.swift](../../../Sources/SevraCore/ChatRun.swift) `rehearseChatScript`) on a throwaway copy with sample inputs (text "sample", number 0, today's date, false, null for optional), and nothing is kept. An undefined name, a value called that is not a function, a missing await or return, or a statement SQL refuses refuses the save with the error and one hint: SQL functions go inside the sql text, `today` is the date, pass values as sql(text, {name: value}) with :name, never join values into the text. A failure only the data or the sample caused, such as no rows, a constraint or the script's own throw, saves. The script runtime now reports the error's name. The run description adds "never a value joined into its text".
- **Values by position.** A script's sql(text, [values]) fills each `?` in order. A missing value in a script says how to pass one instead of "uses an input the tool does not declare".
- **Refusals that say what to send:** an insert with componentID says insert places by at first or last, or beforeID, and that componentID is for replace, remove, move, title and text (there is no afterID field); components lacking two or more fields name them all in one error, so a retry that drops fields is told; a button without a binding shows `definitionBinding: {tool: "name"}` with the saved tools as that shape; a button whose tool is not saved says "Save the tool first with save {tool}, then add the button."; `expectedDefinitionID: ""` is a new definition, as when left out.
- **Guidance.** The view guide: a title says exactly what its component shows, and a period needs a query; a metric of a quantity is SUM of that column; a saved query writes today as date('now') and this month as strftime('%Y-%m', 'now'), never a date written out; never add a total or summary row, use a metric. The automation guide's check says the same about dates. The instructions' sql paragraph says X is (Y - X) / Y * 100 percent lower than Y, and (X - Y) / Y * 100 percent higher.
- **Limits:** no model job was run. The repeated-save reply for app building runs only inside the app, so it is not checked here; `--native-app-authoring-checks` needs the app bundle's check service and stops at its first check from the command line, as before. Dates written into a saved query are steered by guidance only, not refused. The instructions changed, so `sevra header make` is needed before the next model run.
- **Checked:** new [RunFollowupChecks.swift](../../../IntegrationTests/Agent/RunFollowupChecks.swift) in `sevra-agent-checks --action-confirmation-checks` (a failed Home save settled by an edit, definitions settled by the same payload and not another, a view of another name not settled, the open failure after a save and alone, the second identical refusal closing the request, the insert message, all missing fields at once, the button shape and unsaved tool, the script trial refusing an undefined name and a bad column and saving data-only failures with nothing kept, sql by name and by position, the missing-value message, the empty expectedDefinitionID, the views shape message and the command-line app refusal first); `--answer-grounding-checks`, `--chat-checks`, `--sql-tool`, `--saved-action-checks`, `--space-action-checks`, `--prompt-header-checks`, `--field-order-checks`, `--progress-stop-checks`; `sevra-checks` default (590; the empty-string case moved out of the refused list); `check_splash_grammar.py` (ordinary prompt 7,608 of 8,448, authoring 10,183 of 10,240; the exported tools are unchanged, so no fixture was regenerated) and `check_chat_jobs.py --self-test`.

**The screen follows a removal, November 24, 2026.** A document removed through chat stayed on screen as a live draft, because the viewer pins an exact version and judged "removed" only on the current one, and only a screen's own button navigated afterwards. The general fix is one core question, `Workbook.presence(id)`, that every screen asks after any change, and one banner, `GoneBanner`, that says removed, withdrawn or no longer here, with Restore when it applies. It covers documents and records (any version), views and apps, tables, automations, and forms and calculations shown in a view. Only the current version offers Accept, Edit, Undo or Withdraw. Confirmed removals and restores now say what happened in chat. Verified live in the installed app for a document and a view removed through chat while open.

**Done on November 18, 2026.** Evidence: [the baseline](../../../integration/evidence/2026-11-18-chat-jobs-baseline/results.json).

- **Profile.** The host reads `SEVRA_TOOL_PROFILE`. Unset means `current`, and an unknown name is refused. `sevra-agent-checks --conversation-surfaces` passes with `current` byte-identical to a build without a profile.
- **Jobs.** [check_chat_jobs.py](../../../scripts/check_chat_jobs.py) holds the 24 jobs with their expected results and runs them under either profile.
- **How it was recorded.** The first 26 results ran under an earlier rerun rule, in two languages the owner had not asked for. He then chose the fast loop, and the remaining jobs ran once in English.
- **Baseline in English, today's tools: 12 of 23 jobs pass.**
  - Reads: 5 of 5, in 3 to 4 decisions and 23 to 48 seconds each.
  - Table changes: 1 of 5. Only deleting rows passes.
  - Several steps: 1 of 3.
  - Building a view, an app, a form and a rule: 0 of 4.
  - Conversation 3 of 3, safety 2 of 2.
  - The draft job was recorded as failed by a mistake in its check, since fixed. It was not run again.
- **Why changes fail today (step 4).** Under the AI actor a row insert and a row delete are applied. A row update and every schema change are refused with "An AI decision needs an exact saved rule Source". Today's tools then fall back to a draft the person must accept. New table and totals by category fail only for that reason: the accepted drafts held the right content. Rename, add rows and missing rows in English are today's tools really failing.
- **Timed turns, one run each:** cold first turn 17.99 s, warm greeting 4.20 s, warm stock question 10.77 s.
- **Cost of one run:** 23 to 187 seconds. About 6 to 7 seconds of that is starting the process and the model. The rest is decisions that each start from a prompt of about 11,200 tokens.

### Phase 2. `sql`, reading

1. **Probe SQLite first, CPU only.** Done on November 18, 2026. The probe showed:
   - the authorizer names every table and column a statement reads or writes, through views and common table expressions too, and every `CREATE`, `ALTER` and `DROP`;
   - the authorizer can deny `ATTACH`, pragmas, transaction statements and `VACUUM`, including `VACUUM INTO` a file, and extension loading is not available in the system library;
   - with recursive triggers on, the trigger log records a replace as a delete and an insert, an upsert as an update, and a reused `rowid` as a delete followed by an insert;
   - the authorizer keeps statements away from the host's log and triggers while the triggers themselves can write;
   - a page cap bounds both the main in-memory database and temporary tables;
   - a table replaced through create, copy, drop and rename shows as those three schema events in order;
   - a trigger cannot tell a written floating-point value from an exact one, because the column's type conversion runs first. This changed the design under Numbers, and the probe then showed the changed design working: comparisons, ordering, grouping, joins, an exact `sum` that also works in `HAVING`, `ORDER BY` and as a window function, and refusal of a written value that SQLite computed.
2. Build the scratch connection, the readable names, the catalog tables including the ledger's two, table discovery, the budgets, the exact side table, the replaced `sum` and the exact number functions.
3. Refuse everything outside the scratch database: `ATTACH`, `VACUUM`, transaction statements, extension loading and pragmas that change state. Refuse every changing statement until phase 3.
4. Write the result receipt with statements, tables read and fingerprints. Rebase the inspected set and the number, comparison, percentage and currency checks on receipts, as listed under [Answers, evidence and the guards that move](#answers-evidence-and-the-guards-that-move).
5. Open a cited result receipt in the conversation, showing its statements and the tables it read.
6. Extend `search` with the conversation scope and `read` with result pages, references, lineage and guides. Write the first guides, for SQL and the catalog.
7. Offer `sql` in the `general` profile in place of `datasets`, `rows`, `count_records`, `compare_rows`, `calculate` and `balance`.
8. Measure filling a table at 1,000, 10,000 and 100,000 rows.

Exit:
- CPU: refused statements are refused; the scratch database holds nothing but the tables referenced and the catalog; results equal the existing query engine on its fixtures; the exact functions equal the exact engine on the calculation fixtures; a floating-point result is marked approximate; budgets and the page cap hold.
- Copy cost: filling 100,000 rows, the existing row budget, completes inside the existing query time budget. If it does not, the row limit for `sql` is lowered to the largest measured size that does, and recorded here. If an ordinary call then spends more than a tenth of a decision in filling, the host keeps a filled copy of each table for the conversation, starts each call's scratch database from it, and refills a table only when its fingerprint changes.
- Real model: every read job is answered correctly with citations, with no more decisions than the baseline. The stock question gives 18 from an opening 20 and a movement of −2. A cited receipt opens in the conversation.

### Phase 3. `sql`, changing

Depends on phase 2 and on the `db/DB.md` change.

1. Translate the trigger log and the schema statements into operations: row operations, new tables, new definitions, redefinitions, archived tables.
2. Add the bulk form of the row write path with one evidence Source and a bulk inverse for Undo. Measure the largest number of changed user rows that fits inside the capture limits, record the limit, and set the deadline from the measured time.
3. Publish the rule Source for direct changes from the host. Add `sources` and `draft`.
4. Apply under one hold of the workbook lock. Add the read-back of written cells, the read-only refusal, and the token keyed on the decision.
5. Name the views, apps and definitions bound to changed columns in the result.
6. Show one Undo for the call in the conversation, using the receipt the finish payload already carries for app actions.
7. Update [[records/specs/managed-datasets]], [[records/specs/persistence-readiness]] and [[records/specs/distribution]] with the new rules.

Exit:
- CPU, over a generated set of inserts, updates, deletes, replaces and schema changes: the written cells equal the scratch result; `Workbook.verify` passes; replaying the committed changes rebuilds the same state; one Undo restores the exact earlier state, including a dropped table, a redefined table and a bulk delete; Undo after a later change to the same rows is refused with the reason; the canonical schema check passes; a read-only request changes nothing; a repeated statement in a new decision runs again; a call over the row limit changes nothing.
- Real model: every change job and the draft job succeed. The two safety jobs pass. They run at every gate from here on, because each later phase adds a way to change the workbook.
- Records: the three specifications carry the new rules.
- Milestone: the full agent suite and `scripts/check.sh`.

### Phase 4. `run`

Depends on phase 2. Uses phase 3 for changes.

1. Add the script entry point and prelude to the worker and the app runtime.
2. Add the data functions: `sql`, `search`, `read`, the exact numbers, the text of an included file, the text of the request, and saved functions and queries.
3. Add the request queue, with opening a view as its first request. The other requests arrive in phase 6.
4. Add the single scratch database per script, the apply at the end with its fingerprint check, the call deadline, the host-call cap, effect accounting and the result receipt.
5. Write the code guide and the function index. Update [[records/specs/native-app-engine]].

Exit:
- CPU: the sandbox probe passes on the script path; file and network attempts fail; time, memory, job, output and host-call limits hold; a script's changes are one recorded change with one Undo; a script that throws changes nothing and performs no request; a table changed by someone else during the script refuses the apply.
- Real model: each of the three several-step jobs finishes in fewer decisions than the baseline, with the same result.

### Phase 5. `save`, workbook tools and the format change

Depends on phases 3 and 4. Workbooks made by earlier development builds will not open after this phase. The owner accepted that on November 18, 2026: nothing has been released, so format changes need no compatibility work ([[sources/notes/2026/11/general-tools-answers]]).

1. Route `save` by kind to the existing document, record, view, app and definition paths, each keeping today's behavior. Write the guide for each kind and attach the kind's strict shape after its guide is read. Extend `read` to views, apps, tools and automations. One Undo per save.
2. Change the canonical schema once: add the `tool` kind and anything else this plan stores. Recreate the sample workbook and the fixtures. Document the break.
3. Add the `tool` kind with a SQL or JavaScript body, validated by preparing the SQL against the scratch schema or checking the script's syntax, and run through the phase 2 to 4 layers.
4. List callable definitions and saved app action catalogs in the per-workbook block. Load on read. Accept direct calls by name with checked inputs, and calls from scripts. Keep loaded tools through context maintenance and handoff.
5. Record an app's declared actions during its isolated check.
6. Add the per-Mac grant for tools and the enable step for a tool that arrives in a copied workbook.
7. Give the sample workbook a saved action for a stock movement. Turn the receiving and low-stock starters into guides.
8. Show a workbook's tools on the existing definitions screen, with enable and remove. Creating and editing a tool happens in chat. This is the default unless the owner chooses more in phase 0.
9. Update [[records/specs/application-definitions]].

Exit:
- The app authoring checks pass through `save`.
- A `tool` can be saved, listed, read, called directly, called from a script, and is disabled in a copied workbook until enabled. It is still callable after context maintenance.
- An app action is listed without the app running and runs once the app is enabled.
- A stock movement made through the saved action behaves as `propose_movement` does today, including its direction review, and the balance read through `sql` agrees with the core's balance. The README's supplier comparison is reproduced with `sql` over the comparison table.
- One Undo removes a saved view, document, record and tool, or restores the earlier version.
- Real model: the build jobs succeed.

**Built on November 19, 2026,** at the owner's word to build the whole plan, [[sources/notes/2026/11/general-tools-whole-plan]]. What was built and left out is under [The build so far](#the-build-so-far). Against the exit, with checks that need no model:

- The app authoring checks pass through `save` (`sevra-agent-checks`, 61 groups).
- A tool is saved, listed, read, run by name, run from a script, refused in a copied workbook until enabled, then enabled and run, and removed with its history kept (`check_chat_sql.py`). It is listed in the request's context on every turn, so context maintenance does not drop it.
- An app's actions are recorded by its check and listed with their inputs without the app running (`check_native_app_authoring.py`). This check found the listing dropping every input, because the inputs are stored as named fields; fixed.
- The saved movement action drafts the movement with its direction review, the balance read through `sql` agrees with the core's before and after acceptance, and the supplier comparison is reproduced with `sql` (`--saved-action-checks`).
- One Undo takes back a saved tool or restores its earlier version (`tool.undo`). Views, documents and records keep their own Undo.
- An alert rule binds the shared alert workflow once, a second alert rule reuses it, and running it drafts the alert citing the stock record (`--automation-authoring-checks`).
- Real model, one run each: `build.view` in the light set, `build.saved_tool`, `build.rule`, `build.form` and `build.app` pass, in 3, 2, 3, 2 and 5 decisions. The app job passed after the fix recorded under The build so far.

### Phase 6. Fold the rest, then remove the old tools

Depends on phase 5.

1. Add the remaining requests and functions, with their guides: threads, navigation, pins, files, imports, charts, Excel, apps, workflows, undo, and the prepared confirmations. Replace `request_input` with `ask`. Apply the export rule.
2. Rewrite the stable instructions for seven tools. Remove the inventory, receiving and supplier paragraphs and the supplier wording in [CostQualification.swift](../../../Sources/SevraAI/CostQualification.swift).
3. Reduce handoff work kinds to answer and change. Rekey action confirmations, closing receipts, progress labels and activity titles by kind.
4. Rewrite or retire the check groups that name old tools, keeping every invariant they assert. Update the Native UI Catalog registry and fixtures in the same change.
5. Point the command line's `tool` command at the seven tools and workbook tools.
6. Make `general` the only profile and delete the old tool definitions that no specialized phase still uses. Done on November 19, 2026, with steps 3 and 4 for the parts that profile removal needed.

Exit:
- Every job in the phase 1 list passes with the general tools, with no more decisions than the baseline in total.
- Milestone: the full agent suite, `scripts/check.sh`, a packaged build, installation, and the native journeys for supplier comparison, Excel import and a mini app in the installed preview, with the interface review `AGENTS.md` requires.

### Phase 7. Final prompt and measurement

Depends on phase 6. Its header items need phase H3, and phase H4 for the release package.

1. Fix the header: instructions, seven schemas, the function index, the catalog tables and the guide names. Fix the per-workbook block: tables with columns, and views, apps, tools and automations by name with inputs.
2. Make the final header with the header command, in a development package, and in a release package if phase H4 is built.
3. Measure prompt tokens, decisions and wall time against the phase 1 baseline, cold and warm.

Exit: the header is smaller than today's 6,020-token shared header, an ordinary first decision's prompt is smaller than today's 10,989 tokens, the measurements are recorded here, and the header tests pass on the final header. If the header work stopped at phase H1, or phase H3 was not built, that last item does not apply and decision 5 stays open with the owner.

**Measured on November 18, 2026.** The general tools' shared header is 2,559 tokens and an ordinary first prompt about 4,600. The header work stopped at phase H1 by the owner's pause, so the header tests do not apply and decision 5 stays open with him. The rest of the measurements are under "The build so far".

### Phase H1. Probe the engine's disk cache

Depends on phase 0. Runs the engine, so it needs the go-ahead. It is a probe mode in the check harness, `sevra-agent-checks`, which starts the engine helper directly with its own arguments. No product source changes.

1. Start the helper as the app does, with the persistent cache on, a temporary app-owned cache directory and an explicit quota. Send the current header as a one-token request. Stop it and wait for its own exit. Record the files, their sizes, whether the slot files are sized to their content or to the quota, and what they add to a compressed disk image.
2. Copy the four data files aside, delete the directory, create the folder named by the cache name again, copy the files back, and start again. Require `disk.persistent` true, `taken_back` reporting the points, `left_behind` zero, and the first request resuming the header up to its last complete page.
3. Record the cost of the copy and the check, and the start time with the cache on and off.
4. Make the files with a small quota and restore them under the larger quota the app would use. Record whether they are taken back.
5. Start the engine at the 32K and the 64K context settings. Record whether the cache name is the same, and whether a header made at 64K is taken back and resumed at 32K.
6. Run a conversation that fills the context. Record the bytes written to the cache directory, and whether a new conversation afterwards still resumes the header. The engine's write budget paces writes and does not cap them, so the plan sets none. The bytes written go to the owner as a cost.

Exit: every item is recorded as evidence, and the measured size goes to the owner. If the header does not resume from copied files, or the files for one header are sized to the quota or larger than 150 MB, the header work stops here and goes back to the owner. The choices then are an upstream request or dropping the pre-read header.

**Steps 1 and 2 done on November 18, 2026.** Evidence: [the probe](../../../integration/evidence/2026-11-18-header-cache-probe/results.json), run with `sevra-agent-checks --header-cache-probe`. No product source changed.

- **It works.** After the four data files were copied out, the cache directory deleted, the named folder made again and the files copied back, the engine reported a persistent disk cache, took back 1 restore point over 188 KV blocks and left 0 behind. The first request, the full first chat prompt of 11,830 tokens, resumed 6,016 of the header's 6,020 tokens from disk: its last complete page.
- **Size: 131.5 MB for today's header.** `kv.slots` is 64.7 MB, about 10.7 KB a token. `state.slots` is 66.7 MB for the one restore point. The slot files are sized to their content, not to the 8 GiB quota. This is under the 150 MB stop line and about twice the size of today's 62.7 MB download.
- **What it saves.** Reading today's header took 2.59 seconds. Copying the files took 0.12 seconds. The engine started in 4.4 seconds with the cache on, the same as with it off.
- **What it does not cover.** The 4,969 tokens after the header in a first prompt were read again, in 2.75 seconds.
- **Not measured:** what the files add to a compressed disk image, and whether the state file stays near 66.7 MB for a shorter header. If it does, a header cannot ship in much less than that.
- **Steps 3 to 6 done on November 19, 2026,** on the general tools' header of 2,572 tokens. Evidence: [the limits probe](../../../integration/evidence/2026-11-19-header-cache-limits/results.json), run with `sevra-agent-checks --header-cache-limits-probe`.
  - **Cost (step 3).** Copying the files took 0.09 s, and an engine start took 3.9 to 4.4 s with the cache on, as with it off.
  - **Quota (step 4).** A header made under a 1 GiB quota is taken back under 8 GiB and resumed to its last complete page.
  - **Memory tiers (step 5).** The cache name is the same at 32K and 64K, and a 64K header is taken back and resumed at 32K. One header serves both tiers, so the name carries no context setting.
  - **A full conversation (step 6).** Eight turns to 61,264 tokens wrote 867.7 MB while they ran and left 1.76 GB of files at the stop. A new conversation afterwards still resumed the header. The app's quota is 8 GiB.


### Phase H2. One cache name on every Mac

Depends on H1.

1. Write `model.json` with only what is the same on every Mac: the version, the model's repository name, the family, the formats, the source repositories and revisions, and each file's relative destination, size and digest.
2. Move each file's absolute path and times to a sidecar the engine never reads. Model preparation keeps its fast verification from the sidecar.
3. Leave the developer layout, a model given by local path, with its per-Mac record.

This changes the model record, so an installed model is prepared again at the next engine start. No file is downloaded again.

Exit: preparing the same model pack from two different folders gives a byte-identical `model.json` and the same assembly key; the engine reports the same model layout digest for both; a header made under one folder is taken back under the other; changing a weight file's times changes neither.

**Done on November 19, 2026.** [ModelPreparation.swift](../../../Sources/SevraSplash/ModelPreparation.swift) writes `model.json` with each file's destination, size and digest and nothing of this Mac. The paths and times sit in `<assembly>.json` beside the assembly folder, which the engine never reads, and the folder name adds a digest of the paths to the key, so the same record linked to other folders is another folder with the same key. A model prepared before this is found through its old record and prepared again at the next start, with nothing downloaded. The setup check `a pinned model's record and key are the same from any folder and after new file times` covers the record, the key and new times; the header test `anotherFolder` prepared the real model from hard links in other folders and resumed the same header.

### Phase H3. The header command, packaging, and an app that only restores

Depends on H1, H2, phase 1 for its baseline, and the owner's answers to P6, P8 and P9.

1. Add `sevra header make`, the header cache and the manifest, with the memory and running-engine guard and a stop path that waits for the engine's own exit.
2. Add the rule that finds the header folder: the app's own folder for an executable inside an app, an explicit setting otherwise.
3. Add one packaging helper that finds or makes the header and copies it into the app. Call it from [package_native.py](../../../scripts/package_native.py) after the runtime manifest is written and before the app is signed, and from [package_release.py](../../../scripts/package_release.py) after the nested binaries are signed and the manifests are written and before the command line helper app and the app are signed. Make a release package at stage `early-access` or `stable` fail without it.
4. Have [install.sh](../../../scripts/install.sh) say when it installed a build without a header and what to run after the model download.
5. In the app, add the restore before every engine start, the checks at start and on every request, and the error states with their messages. Stop priming the ordinary chat header.
6. Extend `check-resources` with the three header states.
7. Have the real-model check scripts run the command first and pass the header cache to the tools they run. Add the comparison setting, the missed-resume seam and the context override to the check harness.
8. Run the three timed turns once more and record them beside the phase 1 baseline, so later wall-time comparisons use the same header mechanism.
9. Document the development flow in [[records/operations/build-and-run]] and the README's setup steps. Record the new launch arguments in [[records/specs/splash-integration]], and add the header tests to that pin's qualification.
10. Add the header tests, except the two that need a release package.

Exit: those header tests pass on a packaged development build; a build with no header refuses chat with the message and computes nothing; a release package at stage `early-access` or `stable` fails without a header.

**Built on November 19, 2026.**

- **The command.** `sevra header make DIRECTORY [MODEL_DIRECTORY]` and `sevra header status [DIRECTORY]` ([PromptHeader.swift](../../../Sources/SevraNativeAI/PromptHeader.swift)). Make starts the engine with the app's launch values and the persistent cache on, sends the header, waits for the engine's own exit, restores the files into a new directory, starts again and requires the point taken back and the header resumed before it writes the four files and `manifest.json`. It refuses while another engine runs or with under 16 GB of reclaimable memory, and holds the app's inference lock. The real header took about 15 seconds.
- **Inputs without the model.** The prompt layout is worked out apart from rendering, so the header's inputs, its instruction text, shared tool declarations and thinking switch, are known without the tokenizer. The no-model check `checkPromptHeader` requires real first decisions in the app, a read-only request and the command line to have exactly these inputs.
- **Where it lives.** Every executable inside an app uses the outermost app's `Contents/Resources/PromptHeader`. Anything else uses `SEVRA_PROMPT_HEADER`. The engine's cache directory is `~/Library/Caches/Sevra/PromptCache`, emptied at every start and stop.
- **Packaging.** [prompt_header.py](../../../scripts/prompt_header.py) finds or makes the header and copies it in before the app is signed: in the development package after the runtime manifests, in a release after the command line helper app is signed. Without the model a development package has none and says so; early access and stable fail. `install.sh` says when a build has no header and what to run.
- **The app only restores.** Before every engine start it checks free space (about 13 GB), restores the files, starts with an 8 GiB quota, and requires the points taken back with none left behind. A short start is repeated once and then reported as a damaged installation; an engine that fell back to temporary files is reported as a lack of free disk space (P9). Every request that starts with the header must resume it; a miss is cancelled before it generates and sent once more after a restart. The header is never primed: it is marked as resumable at each start. Specialized phases read their own prompt starts as before (P8).
- **Errors.** A missing or mismatched header says the copy has no prepared prompt and to install Sevra again, or in a source build to run the installer once the model is downloaded (P6). Nothing is computed.
- **Checks.** `check-resources` reports the header as present, absent or mismatched. `prompt_header.py self-test` covers packaging without the model and the release refusal. The real-model scripts make the header first and pass it on.
- **Header tests, one run on the packaged development build: all eight pass.** Evidence: [the tests](../../../integration/evidence/2026-11-19-header-tests/results.json). The header's share of a cold first decision is 1.57 s restored against 2.79 s computed, and the cold turn 12.4 s against 13.8 s. The engine is not repeatable token for token across processes, two computed runs included, so same answers means the same decisions and factual answer.
- **Left out: priming the per-workbook block in the background when a conversation opens.** The first message reads it, as before. A background prime would hold the engine's one lane while the person types, and no measurement shows a need.

### Phase H4. A release carries a tested header

Depends on H3 and the owner's answer to P7. The packaging it changes exists and is rehearsed. A public release still waits on Developer ID signing and notarization, which [[records/plans/macos-installer-and-updates]] owns.

1. In [package_release.py](../../../scripts/package_release.py), record the header's manifest in `release.json`.
2. In [check_release_package.py](../../../scripts/check_release_package.py), check the installed header against the receipt. With the model on the Mac, run the header tests against the installed copy, including the one that starts from the DMG alone.
3. Test an in-app update between two builds whose headers differ.
4. Update [[records/plans/macos-installer-and-updates]]:
   - a release needs the model on the Mac that makes its header, or a header supplied from a Mac that has it when the release is built elsewhere;
   - the download and every update grow by the header's size;
   - the receipt, the verification matrix and the customer instructions gain the header;
   - its release order must not publish an early-access or stable build made after phase H3 without a header.
5. Testing on another Apple chip needs a Mac the project does not have. Until one is tested, the published requirements name only the chip that was (P7).

Exit: on the test Mac, the test that starts from the DMG alone passes; every header test passes in the packaged release app; the update test passes; the installer plan carries the four changes.

**November 19, 2026.** QA build 0.9.0-qa.4 carries the header in a 150.7 MB DMG, against 62.7 MB before, and its `release.json` records the manifest and the chip, Apple M5 Pro. `check_release_package.py --full-runtime --models` installed it from the DMG into an empty folder with the build tree denied: the app, its CLI and a CLI link report the header present, and the first chat resumed it to 2,560 tokens with nothing primed. The installer plan carries the four changes. The release header matches the development one by design, since a header is matched by the engine's release and commit and a release re-signs the engine's file. The in-app update test is not run: it needs the app's Check for Updates menu, and the owner has not given access to the app's windows.

**November 20, 2026.** Build 4 was installed from its disk image into an empty folder, and its app, CLI and CLI link found header `793529b6` (2,572 tokens). QA build 0.9.0-qa.5 was built clean from `46f6b58` with header `4b5222b7` (2,707 tokens), and a signed loopback feed for it was served. The owner then gave access to the QA app. Check for Updates in build 4 found build 5, and Sparkle verified, installed and relaunched it; About showed build 5. The updated copy matched build 5's receipt and disk image, its app, CLI and CLI link found header `4b5222b7`, and its first chat resumed that header with 2,688 tokens matched and none computed ([evidence](../../../integration/evidence/2026-11-20-update-test/README.md)). H4's exit is met on the test Mac.

## What this replaces

Rules recorded before this direction, and what becomes of each:

| Rule | Where | Becomes |
| --- | --- | --- |
| "No raw-model DDL" | `db/DB.md`, agent instructions | Model SQL, including DDL, runs only on a scratch copy. The workbook changes only through the recorded write path. The owner edits this line. |
| "Never execute SQL supplied by a model" (M05), no "unrestricted SQL" (M08), "Reject raw-model DDL" (MJ07) | [[records/specs/managed-datasets]] | Model SQL is executed, on the scratch copy only. System tables stay unreachable. Model DDL becomes a registered definition or is refused. |
| "No direct projection edit can become unrecorded authoritative state" (M03) | [[records/specs/managed-datasets]] | Kept. It is the reason for the scratch copy. |
| No "executable SQL in historical payloads" | [[records/specs/persistence-readiness]] | Kept. A recorded change holds row operations. The statements stay in the tool receipt for inspection and are never replayed. |
| "No arbitrary SQL, generated executable code" in a definition | [[records/specs/application-definitions]] | Replaced. A workbook tool's body is SQL or JavaScript. |
| "no model-authored SQL" | [[records/specs/distribution]] | Replaced for chat. |
| No "arbitrary SQL writes", and an "arbitrary code runner would delay the first useful job" | [[records/specs/native-app-engine]] | Replaced. The programmable engine already runs model-written JavaScript. |
| Launch with the persistent cache off | [[records/plans/inference-context-upgrade]], [[records/specs/splash-integration]] | Replaced in phase H3. The cache directory is owned by the host, filled from the app's prepared header before each start, and cleared when the engine stops. |
| Exports write to any absolute path in the tool call | [ChatOperations.swift](../../../Sources/SevraCore/ChatOperations.swift), [ChatActions.swift](../../../Sources/SevraApp/ChatActions.swift) | Under the general tools, only a path the person typed in the request. Otherwise the app opens the save panel, and the command line refuses. |
| Two on-demand tool groups | [[records/plans/native-chat-prompt-routing]] | Replaced by this plan. Its measurements stay valid. |

Each specification is updated in the phase that makes its new rule true: managed datasets, persistence readiness and distribution in phase 3, the native app engine in phase 4, application definitions in phase 5, and Splash integration in phase H3. The first five were updated on November 18, 2026, each with a section named for this plan. Splash integration waits for phase H3.

## Risks and what would change the plan

- **The local model writing SQL and JavaScript.** A failed statement costs a decision. Published code-first agents use much stronger models. Every phase gates on real-model jobs, and the current tools stay the default until phase 6. If a job stays worse than the baseline, the phase does not exit and the owner decides whether to keep a narrow tool, change the job or stop.
- **Exact products and divisions need named functions.** A plain `sum` over a decimal column is exact. The natural `sum(qty * price)` is floating point, and the answer guard refuses it as an exact figure. Each miss costs a decision. The phase 2 gate shows whether the model learns the exact functions from the header and the guide.
- **Citations for computed answers.** An aggregate cites its statements and the tables it read, not single rows. The product says a person can check the inputs behind a calculation, so phase 2 does not exit until a receipt opens in the conversation.
- **Changes without approval.** A document can contain an instruction. The sandbox has no way out of the Mac and a change can be undone until later changes build on it, so the exposure is edits to this workbook and the requests a script can make, which behave as today.
- **A schema change can disable an app.** An app bound to exact columns is disabled when they change, as today. The tool result names it.
- **Copying tables per call.** Large tables make each call slower. Phase 2 measures it and sets the limit.
- **Disk writes with the cache on.** The engine copies every conversation point to disk while it runs. Its write budget paces writes and does not cap them. Phase H1 measures the volume for the owner.
- **Download size.** The release DMG is 62.7 MB today, and every update is the full DMG. An earlier estimate put the header near 60 MB, from a Splash 1.4.1 measurement that was not rechecked. Phase H1 measures it, and the owner decides whether the larger download is acceptable.
- **Making a header loads the model.** The command loads it twice, one engine at a time. Packaging runs it only when the header, the engine or the model changed, and a release needs the model on the Mac that makes its header. Packaging did not need the model before.
- **The header files may not be small.** If the engine sizes its slot files to the quota, they cannot ship as they are. Phase H1 finds out first.
- **Specialized phases get no prepared header.** After phase 6 the phases that share today's header read it once per engine start, when one of them first runs (P8).
- **The local AI needs disk room it did not need before.** Below the engine's free-space floor, or on a volume that is not local, it does not start (P9).
- **Source builds take more steps.** A person who builds from source runs the install command again after the model download, and again after any change to the prompt, a schema, the engine or the model, before chat works (P6).
- **The format change.** Phase 5 stops earlier development workbooks from opening.
- **Volume of check changes.** Of 84 agent check files, 61 name tools. Phase 6 is where they change. Earlier phases add checks beside them.
- **The engine pin.** `integration/splash.json` marks the 1.6.1 pin as a candidate with qualification blocked. Phase H3 changes how the helper is launched, so the header tests join that qualification.
- **Specialized phases still use old tool code.** Excel conversion and reviews call tools such as `rows`, `calculate` and `save_native_app` inside their own prompts. Phase 6 removes old tools from ordinary chat only.
- **Inventory stays in the core.** After this plan the model-facing side is general, but the app still ships an inventory ledger, its automation trigger and its screens. The owner's direction against hard-coding is only fully met when a later plan generalizes that ledger.

## Open items for the owner

- **The interface look, November 20, 2026.** The Tools screen and the export save panel work. The "Change saved" row never appeared and its Undo failed; both are fixed at `46f6b58`. The look found three export faults, fixed the same day: the model wrote the CSV into its answer instead of using `file.export_table`, a fenced block in an answer lost its line breaks, and after a cancelled save panel the answer showed an earlier refused call. In the installed app an export request now opens the save panel in one call, and a cancel answers that nothing was exported ([evidence](../../../integration/evidence/2026-11-20-interface-look/README.md)).
- **The header is built** at the owner's word of November 19, 2026, with P6 to P9 as written. It adds 88 MB to the DMG. A release names only the chips where its header tests passed, so far an Apple M5 Pro.
- **The app job** passes, but it is the least reliable job and is not in the light set.
- Decide whether submitting a form from chat keeps its confirmation now that SQL writes directly. The plan keeps it.
- Settled November 25, 2026: the two stock-ledger questions (when to list the ledger's tables, and whether to turn the ledger into ordinary tables) ended when the ledger was removed. Inventory is ordinary tables and saved tools: [[records/reviews/chat-spreadsheet-cleanup-2026-11-25]].

## Review passes

1. Checked the current code at `dcb111e`, including the follow-up cache change made after the earlier plan.
2. Mapped table storage and the recorded write path, and moved model SQL onto a scratch copy because the tables are projections and the workbook connection exposes the capture function.
3. Mapped the JavaScript worker and found no entry point for a one-off script and no synchronous host calls.
4. Mapped every agent guard keyed on a tool name and gave each a new basis.
5. Mapped saved definitions, app actions, views and the inventory ledger. Added the `tool` kind beside the existing kinds and kept the ledger's core out of scope.
6. Read the pinned engine source and its documentation for the persistent cache.
7. An independent review against the owner's notes and for executability. It found the header work missing from the sequence, a person's approval added to direct writes, built-in ledger tools that formed a group, capabilities without a home, and gates without rules. All are corrected above.
8. An independent technical review against the code and the engine source. It found that a before-and-after comparison cannot identify rows, that the read-back cannot compare computed cells, that overriding SQLite's aggregates breaks them, that table versions and the workbook revision cannot guard a copy, that the capture limits count stored rows, that the `tool` kind changes the workbook format, and that the start-up check missed the engine's temporary-file fallback. All are corrected above. Its unverified points are now the first steps of phases 1 and 2.
9. Re-read the engine's cache naming after the reviews. By this reading the name differs per Mac only because of fields this repository writes, so one name everywhere should need no upstream change. Phase H2 proves it. The header section was rewritten for that.
10. A final independent check of the rewrite against both reviews and the code. It found a `save` rule that would have accepted documents and records without the person, row lineage described from inserts only, statements about the engine written as fact before any run, gates without a rule for wall time or for jobs with no baseline, and steps that no phase built. All are corrected above.
11. Aligned with the release packaging at `baadc5c` and with the owner's direction that the header is calculated at build time. The header section and phases H1 to H4 were rewritten: one command makes the header, both packaging scripts stage it before signing, and the app only restores it. The setup-time path and the recorded digest check were removed.
12. A review of the aligned header design for owner fidelity and readiness, and a technical pass against the packaging scripts, the app's start path and the engine's cache layout. They found wording under the owner's decisions that was the agent's reading, a memory tier the probe missed, a header name that needed the model to work out, a command line tool that would not have found the header, and a release that could have been packaged without one between two phases. All are corrected above.
13. A final independent check of the header design against the code. It found that the header's text cannot be rendered without the model, that the staging point named was not in the shared code, that specialized phases do not all share one header, that the engine's write budget does not cap writes, and that refusing to start without disk room was a new limit not put to the owner. All are corrected above.
14. Phase 2's SQLite probe, run ahead of the phase. It confirmed table discovery, the trigger log, the refusals and the page cap. It showed that a written floating-point value cannot be told from an exact one once SQLite has converted it, so the Numbers design changed to floating-point cells with an exact side table, which the probe then confirmed.
15. The build itself, November 18, 2026. Each failed real-model job was read from its transcript. They showed that the local model needs strict shapes, which reshaped `save` and `run`, and that a bare ID as a result makes it repeat a save.
16. The owner's review of the testing, November 19, 2026. He had not asked for Spanish, reruns or repeated timings, and wanted model testing that takes minutes. The test section was rewritten around a light set of eleven jobs, and the harness now refuses a long run.
17. The owner made the seven tools the only chat tools, November 19, 2026. Moving every scripted check to them found two faults the profile had hidden: a query that only read counted as a change, and the shown tool text differed by scope, which split the cached header. Both are fixed, and recorded under The build so far.


## Chat-spreadsheet cleanup, November 25, 2026

Stock movements, balances, receiving, stock threshold automations and the supplier-quote guard were removed, and saved-tool actions (`tools.run`) and check-triggered automations (`check-drafts-v1`) were added, in commits `c80143d`, `08d56be` and `f2cae08` (workbook formats 34 to 36). The chat tools lost `stock.move`, `stock.balance`, `template.receiving`, `template.rule`, `rule_guide` and `receiving_guide`; `action.preview` and `action.prepare` now run saved tools. No-model checks pass; the light model run was not done because the installed app held the model. Details, verification and limits: [[records/reviews/chat-spreadsheet-cleanup-2026-11-25]].
## The command line and its skill follow the tools, November 25, 2026

At the owner's word, [[sources/notes/2026/11/cli-skill-seven-tools]], the shipped skill `skills/sevra/SKILL.md` was rewritten around the tools, from 45,719 bytes to 7,402. It teaches `sql`, `run`, `save`, `search` and `read` through `sevra tool`, reading the catalog, the action list and the guides on demand, the whole-workbook commands, and the authority rules. The workflow, action, form, automation and definition commands are left to `sevra help all`.

- `sevra help` is now a short front page with the tools first. `sevra help all` prints the full list.
- `sevra tool WORKBOOK ask|finish` refuses with `chat_only`: those two are how the app's model talks to the person, and an outside agent talks to its own user.
- An action only the app window performs, such as `file.export_table`, used to return `ok: true` from the command line with nothing done. It now refuses with `app_only` and names the command to use, such as `export-csv`.
- Guidance text in a tool result (`notice`, `detail`, `hint`) gets the same rewording the app gives its model, so it names `read kind=message` and `search in=conversation` instead of removed operation names. Data is not reworded.
- Checked without the model, once each: every command in the skill on a new workbook (create, catalog reads, a table made and filled by `sql`, a script, a saved tool run by name, a view, undo, a draft update, the action list, search, a guide, CSV and archive export, reopening the archive, `verify`), both refusals and an exact `read_definition` string kept in `sql` data. The suite and a model run were not done.

## Agents learn the tools from the CLI, November 26, 2026

At the owner's word, [[sources/notes/2026/11/agent-guide-in-the-cli]], outside agents no longer need an installed copy of the guide.

- **`sevra agent`** prints the guide from `Sources/SevraCLI/AgentGuide.swift` as plain text, followed by the declarations of `sql`, `run`, `save`, `search` and `read` that Sevra's chat model is shown, built from the same code. A tool change shows up in the guide with no edit. `sevra help` starts by pointing there.
- **`sevra mcp [WORKBOOK]`** serves those five tools over MCP on stdio, with the same declarations plus a `workbook` path that defaults to the one named at start. A call runs exactly what `sevra tool` runs and opens and closes the workbook each time. Tool failures come back as MCP tool errors with the CLI's code and message. The guide is sent as the server's instructions. Workbook-level commands (create, import, export) stay command-line only.
- **`skills/sevra/SKILL.md` is a pointer** to `sevra agent`, with a fallback for an older CLI. Installing it is optional. The installer's last lines mention `sevra agent` and `sevra mcp`.
- **Fixed on the way:** a statement in one `sql` call read the old value of a formula column after an earlier statement in the same call changed its inputs, so `UPDATE` then `SELECT total` showed the old total. Formula columns in the scratch copy are now computed again for the changed rows after each statement, as phase 4 intended. A formula that names another cell reads as NULL until the call is saved. `check_chat_sql.py` has the case.
- **Checked, once each:** `sevra agent` and `sevra help`; 26 MCP protocol and tool checks over stdio (initialize, ping, the tool list and schemas, each tool, undo, the `ask`, app-only, unknown-tool, bad-SQL, missing-workbook, parse-error and unknown-method refusals, nothing on stderr, exit on closed stdin); `check_chat_sql.py`, with the new case; Claude Code with the server as its only MCP server, which read the catalog, compared the quotes and changed a price; and Claude Code with only a shell, which went from `sevra --help` to `sevra agent`, added a shipping column, filled it and answered correctly.
- **Not checked:** Codex. Its configured model is not available on this account, so it never reached the task. The installed CLI at `~/.local/bin/sevra` predates `sevra agent` until the app is installed again. The suite and the model light set were not run.
