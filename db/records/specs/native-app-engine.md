---
type: spec
meta-type: conclusion
id: 01m61cxp8qh580q1vhqdktxhw2
created: 2026-10-28T13:59:16.503029+00:00
updated: 2026-10-29T14:25:09.832957+00:00
summary: 'Customizable Home and native engine: forms/actions, reusable computation, durable workflows, local automations, authority, portability and phased acceptance. Implementation remains open.'
title: Customizable native workbook application engine
status: proposed
---
# Customizable native workbook application engine

October 28, 2026. Owner direction is adopted from
[[sources/notes/2026/10/native-app-engine-direction]]. Detailed runtime choices
below are the proposed engineering design. This is a specification, not evidence
that these features work today. Requirement IDs use E; acceptance IDs use EJ.

## Required persistence foundation

[[records/specs/persistence-readiness]] is an adopted implementation requirement.
The shared complete committed-change foundation and E1 layout extension now have
scoped local evidence. Extend that foundation through E0-D in
[[records/specs/managed-datasets]] before dependent E2/E3 dataset/action/workflow
storage expands. The schema-12 native dataset and versioned definition lifecycle have scoped evidence in
[[records/operations/persistence-coverage]]. Stored-scalar typed queries and
disposable index paths now pass core/CLI and packaged 1k/10k/50k probes. Full MJ and
Excel continuity remain open; the implemented foundation supports E2 catalog work. Registered native dataset tables are rebuildable projections;
versioned logical schemas and immutable row authority use the same transaction,
capture and inert reconstruction. E19/E3 reuse this foundation, never a second ledger.
This does not authorize sync transport, cloud services, replica coordination or
a new conflict resolver. Detailed engine proposals below retain their open status.

## Product direction

E01. A workbook can become the user's own working application. They can change
Home, create spaces, collect information through forms, define calculations and
rules, save reusable actions, compose workflows and automate repeated work.
Home is an editable surface over this engine. Customization must extend behavior
as well as presentation, and survive closing the app, reopening and export.

The existing supplier/inventory journey remains the first qualification job.
The engine is intended to support other small-business and personal workflows
without each workflow requiring a new hardcoded app. Broader usefulness than
Excel is a product hypothesis. We must earn it through completed jobs, flexibility,
correctness, understandable maintenance and measured effort, rather than token
speed or the number of generated screens.

E02. Keep the current native shell: main conversation and voice/text input on the
left, spaces on the right, searchable space picker, temporary file previews and
state-preserving Back. The main conversation evolves; threads explore tangents
without forking business data. Users can describe both work and changes to their
application in ordinary language. Optional native controls, keyboard operation
and direct editing make precise work possible without waiting for inference.
Do not turn Home into a second chatbot, an obligatory dashboard setup wizard or
a permanent visual programming canvas.

Related contracts: [[records/specs/product]], [[records/specs/intelligence]],
[[records/specs/storage]], [[records/specs/search]],
[[records/specs/contextual-import]], [[records/specs/references-and-relationships]]
and [[records/specs/distribution]]. This spec expands product scope without
claiming that any earlier first-release or engine qualification gate has passed.

## Current code and the missing engine

Historical inspection baseline: commit `1aa83726df3142bf63a4a9a48ad7be077b14c94f`.
This table preserves the original gap assessment. The E1 checkpoint below updates
the Home/editing rows; later behavior/workflow rows remain open.

| Area | Existing implementation | Required addition |
| --- | --- | --- |
| Saved interfaces | [Spaces.swift](../../../Sources/SevraCore/Spaces.swift) stores versioned compositions and history. Current types are table, chart, metric, comparison, document, asset, search and text, limited to 16 components and depth three. | Editable Home and existing spaces, richer layout/input/action primitives, current-format schema/fixture changes and explicit revision conflicts. Current bounds are qualification limits, not a permanent expressiveness ceiling. |
| Home | [ContentViews.swift](../../../Sources/SevraApp/ContentViews.swift) renders saved components alongside fixed review, intake, table, recent and navigation sections. | Make ordinary sections part of the composition with user control over order, visibility, bindings and actions. Keep pending-work access in the stable shell. |
| AI and CLI authoring | [Tools.swift](../../../Sources/SevraCore/Tools.swift) implements `save_space` with the operation token as the new space ID. The current CLI `space` command also creates a new ID. | Separate create from version-checked update/patch of a selected space, including Home. The existing core method accepting an ID does not itself provide the full user-facing edit contract. |
| Behavior | Native application commands, bounded formulas and one-turn tool execution exist. `Component` has no persisted user action/form/workflow binding. | A shared action registry, user definitions with typed inputs, forms, reusable functions and durable workflow execution. Product prose mentioning action IDs is ahead of code. |
| Durability | [Workbook.swift](../../../Sources/SevraCore/Workbook.swift) provides transactional mutations, operation tokens, expected workbook revisions and process-safe write locking. Intake and agent runs retain specific progress/receipts. | General run/step/trigger state, checkpointing, worker claims, recovery, pending approvals and effect reconciliation. Intake state and an agent's step limit are not a workflow scheduler. |
| Automation | No general workflow/automation definitions, durable trigger queue, FSEvents adapter or SMAppService registration were found in `Sources` at this baseline. | Schedule, data-change and folder triggers; visible status; optional app-closed operation; resource/authority policy. The workflow performance executable is a benchmark, not this runtime. |
| Calculation and search | [Calculations.swift](../../../Sources/SevraCore/Calculations.swift) supplies bounded Decimal expressions; search/index/provenance infrastructure already exists. | Typed reusable functions, broader dependency/invalidation support, discoverable application definitions and explicit partial/stale-data behavior. Existing formula support does not establish full Excel migration. |

## Editable Home and space checkpoint, October 28

The E1 foundation is implemented in the shared core, CLI, native preview and local
agent tools. Home's six ordinary sections are versioned composition primitives:
input, reviews, shortcuts, tables, intake and recent. Their rendered empty states
can be omitted without changing the definition. The stable workspace header keeps
Review drafts available when a custom Home removes its review section. An authored
empty Home remains empty. Only the declared untouched Home/version 1 projects the
default composition; this does not backfill or migrate earlier development data.

Edits use stable component IDs and exact base versions, checked inside one captured
transaction. Move/insert requires an explicit first/last/before position; unrelated
fields refuse. The native sheet freezes the version opened with its draft; polling
cannot upgrade that base while keeping old edited values. Conflict keeps the draft
visible. Retained history is bounded when paged; restoring creates a new version.
Retrying an exact token returns its original saved version even after later edits.
Pinned layouts preserve saved values/bindings and mode; dynamic host lists cannot
be labeled a frozen business snapshot. Removing layout never deletes business data.

The core has 156 passing groups, including explicit-position/atomic-refusal,
concurrency, snapshot, fault rollback, exact retry, portable history and inert
reconstruction checks. The native synthetic journey exercised edit, a reproduced
polling/base-version race, the repaired stale refusal, history restore and reopening
the reconstructed workbook with the pending draft retained. CLI competing writers
produce one success and one refusal. Two repaired real-model tasks now put Tables first/remove Recent, then put Tables
last while preserving the other sections. Each completed with one successful edit.
The initial model put Tables last and its next attempted repairs failed safely. The constrained grammar's optional field ordering was found
to exclude placement after component selection; its repaired ordering shares the
pinned reference contract. Do not turn the initial action receipt into task-success
proof. See [[records/operations/implementation]] for exact evidence and limits.

This does not close full EJ01-EJ03: low-stock reusable queries/forms/actions are E2,
and actual VoiceOver, broader light/dark/narrow/media form interactions and run
inspection still require qualification. E0's existing-family persistence is scoped
in [[records/operations/persistence-coverage]]; future engine state must inherit it.

## E2 catalog/function/query checkpoint

The schema13 core/CLI now supports versioned typed pure functions and managed query
templates, exact-base save/restore, parameter defaults/units/bounds, live/exact
bindings, bounded FTS discovery and exact dependency inspection. All canonical
families inherit the same capture/inert replay. Authoring is observed metadata;
business review remains separate. See [[records/specs/application-definitions]],
[application definition receipt](../../../integration/evidence/2026-10-28-application-definitions.json.gz) and [[records/operations/implementation]].
This is a scoped E2 foundation. The registry/draft/native-form foundation now has schema14 scoped automated proof
below. Model authoring/invocation and focused visible native form journeys now have
scoped proof in the [agent application definition receipt](../../../integration/evidence/2026-10-28-agent-application-definitions.json.gz). Native calculation/query views and result publication now have scoped proof in the
[native computation receipt](../../../integration/evidence/2026-10-28-native-computation.json.gz). Full EJ04/EJ05 remain open. The schema17 manual workflow core/CLI, explicit native AI interpretation, native Activity/recoverable forms and conversation authoring/queued starts are tracked in [[records/specs/manual-workflows]]. Actual-model jobs qualify interpretation/workflow authoring and queueing without execution; Included-document preparation now has scoped core/CLI, native coordinator, process-death and actual packaged-model proof. Conversation preparation authoring/queued starts now have scoped actual-model/grammar proof. Structured import/report-creation steps and full E3/EJ06-EJ08 remain open. E4-E6 remain unimplemented.

## Home and spaces

E03. Home is a normal versioned space with a default composition. A new workbook
works immediately with add-input, search, recent work, useful tables and review
access. Users can add, remove, rearrange, rename and configure ordinary sections;
place saved queries, tables, charts, documents, media, forms, named actions and
workflow status; change useful presentation properties; or replace the composition
with a task-focused Home. Apply the same editing model to other spaces. A space
does not own a private copy of canonical business data.

E04. The shell always exposes conversation/composer, navigation, activity,
pending approvals/errors and a way to restore Home. It need not force a large
review section into every custom layout. A removed Home section cannot conceal
unresolved work or remove access to its review queue. Technical request sources,
worker heartbeats and binding annotations belong in inspectable history, not the
default recent-business-work list. Preserve their evidence and search scope.

E05. Use semantic editing operations against stable space/component IDs:
insert, move, remove, change properties and rebind data/actions. Example:
"Put stock below ten at the top of Home, add Receive delivery, and hide recent
files." Resolve the current target, preserve unrelated components and data,
validate dependencies, compare the base version inside the commit transaction,
then save one reversible version. Never apply a guessed full replacement over a
newer edit. Refuse or offer a rebase with a readable difference on conflict.

Clear reversible requests can save immediately with a short receipt and Undo.
Use a preview when changes are broad, have consequential side effects or remain
ambiguous; do not require a confirmation for every harmless layout change. A
history view explains changes, authorship and affected bindings. Restore creates
a new version. Removing an interface never deletes its underlying data, action
or workflow. Explain shared-definition edits that affect several spaces.

E06. Separate authored layout from ephemeral selection, scroll, drafts, playback
and per-device window state. Respect live versus pinned bindings and scenarios.
A pinned result cannot silently become live through layout editing; offer an
explicit live copy when needed. A missing binding shows repair options and keeps
the definition. Unknown future components preserve their payload and display a
placeholder without executing anything or destructively migrating the package.

## Native composition, inputs and data

E07. Evolve the typed native grammar with host-owned implementations for layout
stacks/grids/sections, text and document content, parameter controls, forms,
tables, charts, comparisons, media previews, action launchers, review queues and
workflow activity. Every component declares its version, input/output types,
binding schema, supported presentation properties and accessibility behavior.
Responsive layout, keyboard order and loading/empty/partial/error states belong
to the renderer. Avoid unrestricted coordinates and arbitrary model-produced
styling as the normal composition model. Do not regenerate a screen on every open.

Start with the primitives needed by the qualification jobs and expand through a
versioned registry. Pagination, virtualization, cancellation, off-main-actor
queries and bounded data are mandatory. A large workbook must not materialize
every asset, dataset row or component query to show Home. Batch compatible reads
from coherent revisions and invalidate only affected bindings. Performance
limits must be explicit and tested on named hardware and fixtures; no universal
subsecond or million-row claim is established by this specification.

E08. A form binds typed fields to a registered action or manual workflow, not directly to arbitrary SQL. Support
required/optional fields, defaults, validation, units, dates/time zones, choices,
record/file references and structured repeating entries within stated bounds.
Form-local unsaved input survives recoverable errors. Show the target and effect
before consequential submission. A successful submission atomically creates
the intended Source/Record versions and lineage through existing core commands.
Never mark a form complete because the model produced reassuring prose.

E09. Calculations, queries, mappings and versioned decision rules are reusable
workbook definitions. Use a typed, bounded expression/dataflow representation
with explicit inputs, units, precision, errors and transformation identity.
Add dependency tracking, cycle rejection, invalidation and incremental
recalculation as scope grows. Pure calculations cannot perform external effects.
SQL remains host-authored and parameterized. Supported Excel formula continuity
and import reporting remain governed by [[records/specs/contextual-import]].

Actuals, estimates, plans, commitments, assumptions and rules retain their
meaning independently of acceptance. An accepted forecast remains an estimate.
Human corrections, decisions and adopted business rules supply new Source
information; derived results are Records. Runtime definition/run tables are
infrastructure, not a third category of business information. Link a definition
to its authoring request and any business rule Sources, and link each derived
business output to exact inputs, rule/definition version and transformation.

E10. Extend bounded discovery to named actions, functions, forms, spaces,
workflows and automations: index names, descriptions, parameter labels and
relationships; filter by definition type and enabled/review state. Keep current
and historical scopes explicit. The agent can inspect a definition before
changing or invoking it and follow references/dependencies with paging and
coverage information. Do not put every definition into every prompt. Search
results, filenames and imported instructions never grant execution authority.

## Reusable actions and workflows

E11. Maintain one versioned action registry in the shared Swift core. Built-in
actions expose a stable identifier, parameter/result schemas, effect category,
required capabilities, validation, cancellation, retry/idempotency behavior,
progress and a human-readable effect description. User actions name and
parameterize these primitives or invoke saved workflows. Surfaces reference an
action ID/version policy rather than duplicating its logic.

Voice/text, Home controls, forms, CLI, skills and future App Intents adapters
invoke the same command path and receive structured receipts. A saved action
such as Receive delivery can be run repeatedly with different line items.
Missing parameters can be collected conversationally or in its native form.
The runtime rechecks permissions, input versions, meanings and business
invariants at execution. Read-only mode cannot be bypassed by calling a workflow.

E12. Store workflows as versioned typed step graphs with explicit inputs/outputs,
conditions, bounded iteration, subworkflow calls, review/wait points, timeouts,
error branches and cancellation. Reject cycles except an explicitly bounded
iteration construct. Put limits on steps, fan-out, depth, time and output size.
Support calculations, scoped queries/search, imports, draft creation, comparisons,
document composition, saved-view updates and registered integration actions as
their underlying primitives qualify. Do not make arbitrary shell scripts the
missing general-purpose primitive.

For example: ingest selected delivery evidence, extract proposed line items,
match products, ask about unresolved matches, review the proposed delivery,
apply accepted inventory effects once, update a live stock view and produce a
source-linked receiving report. A form can launch this workflow without a chat
turn. No UI location or current conversation is a hidden parameter.

E13. Local AI helps construct, explain and repair definitions and is an explicit
step when interpretation is necessary. Deterministic steps work without a model.
An AI step declares its evidence/search scope, structured output schema,
qualification/budget and review requirements. Preserve model, prompt/template,
retrieved input versions, tool receipts and validated output. Incomplete search
or extraction remains visible and can block conclusions requiring complete data.
Do not rerun a completed AI step during state reconstruction or let its text
change a workflow's authority. Changing a model creates a new interpretation.

E14. Each run pins a definition version, input bindings, applicable rules and
authority policy. Capture the exact versions actually read by each step. A
trigger using live data must state whether it reads the trigger-time snapshot
or latest state; store both trigger context and actual read revision. New
definition versions apply to future runs by explicit policy. Do not silently
upgrade an in-flight run, replay an external effect or reinterpret a completed
calculation against different inputs. Approvals bind the precise proposal,
effect and version; stale approval requires re-evaluation.

## Automations and their user experience

E15. An automation connects a trigger to a workflow version policy, parameters,
scope, enabled state, execution limits and authority. Users can say "Each weekday
morning, prepare the receiving report" or "When a PDF arrives in this folder,
extract it and leave it for review." Show a compact, editable saved description
of when, what data, what it can change and when the Mac can run it. Clarify only
material ambiguity. Explicit scheduling intent can enable a validated automation;
merely generating or importing a definition does not authorize activation.

Native configuration and voice/text support inspect, edit, pause, resume, test,
run now and delete. Editing a schedule must not replay earlier occurrences.
Preview/test uses declared fixtures or a read-only execution plan and explicitly
lists skipped effects; it cannot perform the business action it claims to preview.
On first enable, show the expected next occurrence and any relevant folder or
background access needed. Ordinary repeated executions do not prompt again when
covered by the current, versioned scope. Changed scope needs new authority.

E16. Qualify triggers incrementally:

| Trigger | Required semantics |
| --- | --- |
| Manual | A deliberate invocation with explicit parameters; useful before any scheduler ships. |
| Calendar/interval | Named time zone, calendar versus elapsed-time semantics, next occurrences, missed-run and overlap policy. |
| Workbook event | A specific committed business event/version and durable cursor, rather than each generic workbook revision. |
| Query/condition | Defined false-to-true transition, observed revision, null/stale/partial state and reset/cooldown semantics. No repeated notification merely because stock remains low. |
| Watched folder | User-scoped folder, file eligibility/stability checks, discovery cursor/reconciliation and intake copy/reference policy. A change notification is a reason to scan, not proof of a completed business event. |
| External integration | Future qualified adapter with scoped credentials, input validation, receipt identity and retry rules. No always-on public webhook service is implied. |

E17. Store calendar schedules with an IANA time zone and local wall-clock rule;
intervals are elapsed durations. Default to the workbook/user's resolved zone
and show it. For native schedules, propose shifting a nonexistent local time
forward to the next valid time on that day and running only at the first instance
of an ambiguous local time. Preview DST examples and test these policies.
RFC 5545 export/import must preserve its specified semantics rather than claim
that this native policy is identical. A zone change is an explicit schedule edit.

Choose missed-run behavior by effect: coalesce stale refresh/report requests into
one current run by default, preserve every business occurrence for event-driven
work, and require an explicit catch-up plan for external effects. Bound backlog
and lateness; label skipped occurrences. Default one active run per automation;
queue a successor or coalesce only where semantics permit. Store occurrence
identity durably so clock changes, restart and duplicated notifications cannot
manufacture additional runs for the same occurrence.

E18. Home can show upcoming work, recent results and exceptions using engine
components. A dedicated activity view exposes trigger, definition version,
parameters, evidence, steps, timestamps, retry state and results with Stop,
Retry or Review when applicable. Keep routine activity out of the main
conversation unless requested or relevant to an active request. Notifications
default to useful results, meaningful changes, failure or needed user action.
No silent failure, heartbeats as chat messages or invented completion.

## Durable execution and local lifecycle

E19. Reuse the committed-change capture/apply foundation in
[[records/specs/persistence-readiness]]; do not create a parallel history ledger.
Add transactional definition/version, trigger/occurrence, run, step/attempt,
approval and event-outbox/consumer-cursor storage, with foreign keys, uniqueness
and indexed ready-work queries. Exact table names and schema versions belong to
the implementation migration. Save a business mutation and its corresponding
outbox entry atomically, then consume with persisted cursors. Avoid full-history
scans and one permanent timer per automation. Operational queue churn should
not make every live business view recalculate or fire business triggers.

Each worker claim has an owner, fencing generation, deadline and bounded
heartbeat. Acquire/reclaim and commit results under the shared core's database
transaction and process-safe lock. A stale worker cannot publish after its
claim expires. Persist checkpoints before yielding for model access, approval,
sleep or dependencies. Use bounded retries with backoff, explicit retryable
versus permanent failures and a visible needs-attention state. Disk full,
database busy and unavailable package locations must preserve committed work.
Do not hold a database transaction during inference, user review or file copying.

E20. Distinguish delivery retries from business occurrences. A logical step uses
stable run/step/iteration operation identities across attempts. Internal effects
and their receipts commit atomically with deduplication; a second invoice or
image can support the same fulfillment without a second inventory movement.
Identical but independent deliveries remain separate. Trigger/run uniqueness
does not replace domain occurrence/effect uniqueness in S08.

External effects can succeed before their reply is durably recorded. Use adapter
idempotency/reconciliation when available. If outcome is ambiguous, stop for
reconciliation rather than blindly retrying. Describe execution as retryable
delivery with guarded effects, not a universal exactly-once promise. Run history
supports reconstruction; it never sends, imports or invokes an LLM again just
to display history. Cancellation preserves completed effects. Compensation is
an explicit domain operation, not deletion of the audit trail.

E21. Filter trigger changes by business scope, propagate causal/run IDs and bound
cascades. Prevent self-trigger loops, cross-automation ping-pong and fan-out
explosions. Debounce pure view refreshes, not distinct accepted stock movements.
Folder watchers must tolerate coalesced/dropped events, renames, removable drives,
partial downloads and symlinks; reconcile actual scoped contents with bounded
incremental scans. Do not traverse outside the granted root. A pending file
must not become accepted business data just because a watcher detected it.

E22. Run modes must be honest:

| Device/app state | Product contract |
| --- | --- |
| App open | In-process worker executes eligible work off the main actor. The UI observes persisted state. |
| Window closed, app running | Only explicitly enabled automation work continues. Unsaved editor input is flushed through existing close rules. |
| App quit | Qualified optional per-user background helper can run registered workbooks, with visible enable/pause/revoke controls. Without it, resume on next open. |
| Mac asleep or powered off | No promise of computation at the scheduled instant. Evaluate due work after wake/start according to its saved lateness/catch-up policy. |
| Logged out, locked, permissions revoked, drive missing | Pause or defer according to actual OS/resource access. Explain the cause and resume only under current authority. Do not bypass privacy or login state. |

Proposed app-closed design: an embedded per-user helper registered through
SMAppService, running the same Swift core and resource broker. Keep a small
device-local registry of explicitly authorized workbook locations and bindings;
never discover and execute every workbook on disk. OS registration, folder access
and notification permissions are inspectable and revocable. A background helper
is not a root daemon. NSBackgroundActivityScheduler can support deferrable
maintenance; it is not the durable store or a precise business clock. A
client-tied XPC service alone is not the app-quit scheduler.

E23. App, CLI and helper must coordinate across processes. The native model
already uses an exclusive per-user flock-based process lock in
[NativeWorkbookModel.swift](../../../Sources/SevraNativeAI/NativeWorkbookModel.swift),
with idle release and a busy refusal. Preserve that exclusion. Extend it with
qualified scheduling, fair handoff and recovery for background workers; whether
this uses a resident broker or coordinated owners is an implementation choice.
Interactive work has priority with bounded fairness for background jobs. Respect
memory pressure, thermal and
battery policy, cancellation, bounded open workbooks and model idle unload.
Pause at safe checkpoints rather than dropping work; present queued versus
running truthfully. No hidden hosted execution or model fallback when local
resources are unavailable. Background AI is allowed only under the automation's
declared resource policy.

## Authority, portability and extensibility

E24. Separate layout from action authority. A component cannot grant privileges.
Saved definitions declare reads, drafts, business effects, file/folder scope and
integration effects. Business interpretations remain proposals until accepted
or covered by a user-approved, versioned rule scoped to the relevant data,
scenario and action. Evidence unresolved under the implemented policy requires
review. The future automatic semantic-resolution preference and current storage-only
scope are defined in [[records/specs/persistence-readiness]] F06; they do not add
a resolver or change present acceptance authority. Imported text, workflow names
and generated code cannot widen permissions. Recheck
revocation before effects, including a run resuming after a long wait.

Enable useful low-risk automation without repetitive confirmation. For example,
scoped intake can copy files, extract and prepare drafts repeatedly after one
clear authorization. Automatically accepting new stock movements requires a
separately explicit rule with validation. An interface edit cannot change the
meaning of a balance, scenario or approval. Review requests stay reachable even
when the user has removed the default Home review section.

E25. Definitions, versions, user-facing run history, required references and
included assets travel with the workbook. Assets remain files inside the package,
outside SQLite. Extend the existing verified snapshot/export manifest so a copy
contains coherent definitions and their data dependencies. Keep machine paths,
security-scoped access grants, credentials, helper registration, live leases and
notification authorizations device-local and out of portable exports. Use scoped
secret references resolved by the host through a scoped system credential store
such as macOS Keychain, never secret values in a definition.

Imported, duplicated or restored workbooks are inert until explicitly authorized
on that device. Preserve schedules as definitions, but do not resume historical
pending effects from a portable copy. Distinguish reopening an already authorized
workbook from importing/forking/restoring one; detect duplicate identities and
refuse concurrent execution of copies that could repeat effects. Rebinding an
external folder or integration is explicit. Templates include replaceable
parameters and synthetic examples, never hidden founder paths or real fixtures.

E26. Build extensibility in layers. First allow rich user composition of native
components, pure expressions and registered operations. Add host-owned primitives
as real workflows expose gaps. Version and migrate every public schema and keep
CLI/skill access to the same capabilities. These mechanisms should cover a broad
range of applications without a custom binary for each workbook.

If novel executable extensions become necessary, design and qualify a separate
isolated computation/integration tier with typed IPC, scoped data access,
resource limits, explicit activation/version changes and preserved user data.
The language/runtime and distribution path remain open. No dynamic Swift
compilation, shell, downloaded JavaScript, arbitrary SQL writes or unsigned
in-process native plugins are approved by this spec. P10/A08 remain in force.
The signed native shell, permission enforcement and database invariants cannot
silently self-modify. AI can change the user's application definitions and
workflows; expanding executable authority is a separate explicit design gate.

## Research and design reasoning

Primary references checked October 28, 2026. Statements below describe upstream
capabilities. The Sevra requirements are engineering conclusions drawn from them,
not evidence that another product proves this design will succeed.

- Excel's [LAMBDA](https://support.microsoft.com/en-us/excel/functions/lambda-function)
  supports named reusable workbook functions. Microsoft also distinguishes
  [Power Query and Office Scripts](https://learn.microsoft.com/en-us/office/dev/scripts/resources/power-query-differences)
  for data transformation and scripted workbook control, with Power Automate
  integration. Our inference: a competing engine needs reusable computation,
  intake and behavior, not only AI-generated views. Excel feature/platform and
  licensing differences must be checked for each future comparison.
- Temporal documents [durable event history](https://docs.temporal.io/encyclopedia/event-history)
  and [activity idempotency](https://docs.temporal.io/activity-definition).
  Our inference: preserve run decisions/results and design retry-safe effects.
  Adopt these principles in the native local runtime; no Temporal server,
  hosted dependency or SDK selection is being introduced.
- Apple's [NSBackgroundActivityScheduler](https://developer.apple.com/documentation/foundation/nsbackgroundactivityscheduler)
  gives the system timing discretion for deferrable work.
  [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
  manages bundled helpers; [XPC documentation](https://developer.apple.com/documentation/xpc)
  distinguishes per-user agents from client-tied services. Our inference: saved
  schedule semantics and persistent due-work recovery must be owned by Sevra.
- Apple's [FSEvents guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html)
  requires rescans for coalesced/dropped events. Its
  [sandbox file-access guidance](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
  explains bookmarks and scoped access. Our inference: qualify folder access and
  reconciliation across app/helper lifecycles; a file event is not a ledger entry.
- [App Intents](https://developer.apple.com/documentation/appintents) exposes
  structured actions/entities to system experiences. Our inference: a typed core
  registry can later support a thin Shortcuts adapter. System exposure is
  optional; a saved workbook action does not require an App Intent per definition.
- SQLite's [backup API](https://sqlite.org/backup.html) supports live database
  snapshots. Its [WAL documentation](https://sqlite.org/wal.html) describes one
  writer, concurrency limits and a WAL-reset advisory. Preserve S11's current
  rollback-journal choice and package lock. This design does not enable WAL or
  assume the OS library is patched; use short transactions and qualify changes.
- [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545.html) makes time-zone and
  recurrence semantics explicit. Our inference: preview occurrences and preserve
  DST/missed-run policy; a human phrase such as every morning is insufficient
  storage on its own. Do not claim RFC-compatible recurrence without tests.

## Adversarial design review

Pass 1, product: Making every user build a dashboard would increase work. Keep
the useful default, edit it incrementally and save successful procedures as
reusable behavior. Conversation remains the entry point, while native forms and
direct manipulation avoid making users describe every precise edit repeatedly.
The tests must include a person maintaining an application after its AI author
is no longer in context.

Pass 2, correctness: Pretty views can conceal stale calculations, incomplete
intake or duplicate stock effects. Require exact versions, coverage/status,
shared command validation, human-readable run evidence and domain occurrence
identity. Recovery and querying history cannot repeat a nondeterministic step.

Pass 3, autonomy: A timer inside a view fails when the app quits. A helper without
visible scope creates unwanted autonomy. Persist due work independently of UI
and make background registration, catch-up, permissions, resource limits and
pause/revoke behavior part of the user-facing contract. Shipping in-app/manual
execution first is valid if limits are shown clearly.

Pass 4, scope: A giant plugin marketplace, generic server orchestration system
or arbitrary code runner would delay the first useful job. Build the common
data/action/workflow contracts and prove one app that can be changed, reused,
recovered and shared. The exact component set, isolated extension runtime and
performance envelopes remain implementation/qualification decisions.

## Implementation sequence and acceptance registry

E0 existing-family persistence and the E1 layout foundation now have scoped
implementation evidence. E1 full journey/accessibility gates and E2-E6 remain
open. The historical baseline table alone is not completion of these gates.
Track implementation receipts and changes in [[records/operations/implementation]].
Do not let this design silently displace a currently active fix; use these stages
when scheduling the next coherent product slices.

| Stage | Deliverable and prerequisite | Acceptance |
| --- | --- | --- |
| E0 | Implement the shared persistence foundation and audit existing mutation paths under [[records/specs/persistence-readiness]] before expanding durable engine storage; agree on versioned definition/parameter/binding/action schemas, inventory reusable commands and capabilities, and update current-format schemas/fixtures. | FJ01-FJ06 for existing persistence; validate well-typed definitions, reject unknown executable behavior and preserve history/reopen. New engine mutations inherit these gates as implemented. No legacy-compatibility, sync-service or feature-complete claim from schemas alone. |
| E1 | Version-checked editing of Home/existing spaces through core, AI, CLI and native controls; default sections become composition primitives; inspect/history/undo. | EJ01-EJ03. |
| E0-D | Managed dataset catalog, trusted schema lifecycle, native current-state tables and bounded indexes integrated with the existing persistence foundation. Finish a coherent in-flight checkpoint, then establish this before dependent E2/E3 storage; independent UI work may continue. | M01-M10 and MJ01-MJ08 in [[records/specs/managed-datasets]], extending FJ01-FJ06. Current shared-row and E1 receipts do not qualify this target. |
| E2 | Shared action registry, parameters/forms, reusable queries/functions/rules, definition search and dependencies, using E0-D managed dataset storage for dependent operations. | EJ04-EJ05. |
| E3 | Manual durable workflow executor with explicit AI steps, approvals, cancellation and recovery; atomic outbox and effect receipts. | EJ06-EJ08. |
| E4 | In-app schedule, committed-event and condition triggers; occurrence identity, catch-up, loops/backpressure and activity UX. | EJ09-EJ10. |
| E5 | Folder reconciliation and explicitly enabled per-user helper; cross-process inference/resource broker and install/uninstall behavior. | EJ11-EJ12 on supported signed/packaged builds and real OS lifecycles. |
| E6 | Portable reusable applications/templates and optional qualified native adapters; broaden components from demonstrated jobs. Evaluate isolated executable extensions only if required. | EJ13-EJ14; extension execution stays closed until its own isolation gate passes. |

EJ01. Request a task-focused Home with a low-stock query, delivery form/action,
receiving report and reordered sections. Reopen offline without a model and
retain the composition, bindings, selection and pending-work access. Remove a
section without deleting data. Restore/undo the layout with exact history.

EJ02. Edit Home concurrently from app and CLI. The second stale writer cannot
erase the first writer's components. A failed/unknown component preserves the
previous valid definition and underlying data. Restore creates a new version.

EJ03. Complete layout editing, form input, review and run inspection using keyboard
and VoiceOver, light/dark modes and narrow layouts. Open a bound PDF or video,
return to the prior space and retain input; media does not autoplay or capture
audio because a space was generated.

EJ04. Create Receive delivery once, invoke through voice/text, a Home form and CLI,
and obtain equivalent validated results. Repeat with new parameters without
requiring new model planning. Test missing fields, invalid units, stale inputs,
read-only mode and scoped review rules.

EJ05. Reuse a calculation/query across two spaces and a report. Change a source
and recompute affected live outputs; retain the prior published result. Detect
cycles and errors. Search definitions/dependencies at scale with bounded results;
partial input coverage must not claim a complete finding.

EJ06. Run the receiving workflow and interrupt after import, interpretation,
review and effect commit. Resume after each interruption without losing accepted
work, rerunning completed AI steps or doubling inventory. Repeated evidence for
one fulfillment has one effect; two genuine deliveries have two.

EJ07. Expire a worker lease while a second process resumes. Late publication is
fenced off. Retry after disk-full/database-busy failure preserves consistent
state; waiting for a person or model does not hold a write lock. Cancel midway
and accurately report committed effects and remaining work.

EJ08. Try prompt injection in a PDF, action description and imported template;
revoked folder access; an accepted forecast; a changed proposal awaiting approval;
and an external effect whose response is lost. None gains broader authority,
changes actuals incorrectly, or silently retries an ambiguous external effect.

EJ09. Test calendar/interval schedules, DST skipped/repeated times, zone edits,
manual clock changes, startup/wake, lateness, overlap and bounded backlog. Explain
skipped/coalesced work. One occurrence cannot create duplicate runs/effects.

EJ10. Cross a stock threshold, remain below it, correct a movement and cross again.
Observe the defined notification/reset behavior. A workflow updating its own
output and two workflows referencing each other must not create an infinite
trigger loop. Generic run-status changes must not trigger business rules.

EJ11. Watch a user-selected folder with partial downloads, renamed/replaced files,
duplicate notifications, dropped events, symlinks and a disconnected drive.
Reconcile without losing eligible files or traversing outside scope. Copy/include
according to saved policy and retain original provenance and review state.

EJ12. Exercise app open/window closed/quit, helper disabled/enabled/revoked,
login/logout, actual sleep/wake, moved workbook and unavailable credentials.
Only authorized work runs. App/CLI/helper share model resources and workbook
locks; interactive editing stays responsive. Test install, OS permission steps,
pause and uninstall cleanup. Injected lifecycle tests alone do not qualify this.

EJ13. Export, reopen, duplicate and restore a workbook with forms/actions/workflows,
history and large included assets. Verify coherent data/definition versions and
asset hashes. Copies remain inert, contain no grants/secrets and cannot repeat
pending external effects. Unsupported future definitions survive round-tripping.

EJ14. Compare the same complete supplier/receiving job in Sevra and an appropriate
current Excel configuration, including intake, setup, customization, reuse,
correction and recovery. Record time/effort, interventions, errors, lineage,
resource use and workflow expressiveness. Add another distinct user workflow
before claiming a general application engine. No claim of being more powerful
than Excel is justified by a single attractive demonstration.


## E2 registered inventory actions and receiving forms

Schema14 implements the first shared draft inventory registry, pure preview/exact
submission guard, immutable action/form bindings and recoverable native form sessions.
Home/space editing can add the receiving starter. Native fields select exact evidence,
retain incomplete values and show field errors/preview/submitted proposal status.
All movements use the existing domain validator/executor. Form checkpoints are
classified presentation copied inertly, not a second journal or business evidence.
See [[records/specs/application-definitions]] and [registered action and form receipt](../../../integration/evidence/2026-10-28-registered-actions-forms.json.gz).

Automated core/CLI/native-session, independent writer, crash reconciliation, portable
and reconstruction proof is scoped. The Mac is locked, so visible new-form/keyboard/
VoiceOver/light-dark/narrow qualification remains open. Chat/model invocation,
result publication and query/function composition remain E2 work; E3-E6 is not
implemented by this foundation.


## Final form identity review, October 28

A draft key now hashes the structured space/component ID pair. Delimiter-containing
IDs cannot alias two components, and maximum-length legal IDs remain within the key
budget. Native view ownership also resets with the workbook interaction identity;
the window-owned scope retains the proper draft across Back and refuses to carry
one workbook's session into another. Focused native-session counterexamples pass,
along with the rebuilt native package paths/resources/signature checks, packaged CLI
action/race/portable/reconstruction probe and strict lint of 27 Swift files.

[form identity correction receipt](../../../integration/evidence/2026-10-28-form-draft-identity.json.gz): 11,074 bytes, SHA-256
`bdda49a349db48f6371cc83d077ddfbeee6d5715b71d2f63ffcf0a3c34ad7b3f`.
All 108 preceding receipt files remain byte-identical, including the earlier action/
form foundation receipt. That earlier receipt retains its original source/binary
hashes. Its broad core217/shared checks are reused; the small identity correction
has focused proof rather than a claimed broad rerun. A first lint invocation lacked
swift-format on PATH; the documented xcrun invocation passes. Visible native UI,
agent invocation, complete E2-E6 and release gates remain open.

## Registered document workflow checkpoint, October 28

Registered document drafts now share the existing native action/form/workflow/review path with inventory, with scoped implementation and a six-step actual packaged-model receiving/report proof in [[records/specs/manual-workflows]]. Report acceptance preserves an estimate and stock 20; separately accepting the actual stock proposal changes it to 25. Reconstruction stays inert. This advances E3 but does not close EJ06-EJ08: workflow structured import, product matching/unresolved inputs, richer graphs, broader failure/abuse cases and external effect semantics remain open. E4-E6 remain subsequent work; no release readiness claim.

## Reviewed workflow intake checkpoint, October 29

E3 now has scoped included CSV/TSV intake with exact reusable mappings, real native parsing outside locks, one atomic retained-plan/proposal/checkpoint and explicit exact review through the existing table-update executor. Recoverable forms, native foreground coordinator/Activity summaries, independent CLI, crash recovery and a final six-step actual-model table-update/report job pass. This advances the row-import boundary only. Conversation intake authoring, full Excel continuity, product matching/unresolved inputs, richer graphs, full EJ06-EJ08 and E4-E6 remain open. Current qualification and limits: [[records/specs/manual-workflows]]. Latest visible Activity/review and broader accessibility/appearance remain unverified while the UI tool reports locked.

## Conversation intake checkpoint, October 29

Conversation now saves exact intake mappings, composes a required-review workflow and queues an included file without parsing/applying it. Missing choices are asked for before saving in the explicitly withheld-save case. Existing native/CLI Continue and table review remain separate. Focused core, scripted/grammar, final native/package and four actual-model jobs have scoped proof in [[records/specs/manual-workflows]]. Full receiving/product matching, richer graphs, E4-E6 and release/accessibility gates remain open.

## Exact catalog lookup checkpoint, October 29

E3 now maps one exact complete catalog-query row into typed later steps, preserving selected-row/query lineage and meanings through calculations. Missing or ambiguous matches pause before checkpoint; explicit catalog repair/retry preserves completed AI work. Core/CLI/native coordinator paths share that validation. Final 59 focused groups, grammar/prompt checks, native package and a 39-call actual-model seven-step receiving/repair/review/report job have scoped proof in [[records/specs/manual-workflows]]. Inline human answers, richer graphs, full EJ06-EJ08, E4-E6 and release/accessibility gates remain open.

## Supplied workflow information

E3 core/CLI now supports explicit typed clarification against an exact paused interpretation. Preserve original AI response; add a submission Source and draft clarification Record with honest actor; complete only that step. Native Activity displays provenance, while native persistent input and conversation submission remain next.63 focused groups,101 deterministic calls/two SIGKILL boundaries, packaged27/actual27 plus39-call known-count job and strengthened native state-dependent grammar have scoped proof. Full E3 and release gates stay open. See [[records/specs/manual-workflows]].

## Persistent native workflow answers

Native Activity now adds typed input, exact original-evidence choices, preview and explicit human submission for paused interpretations. Window-owned presentation checkpoints preserve incomplete/stale alternatives, refuse silent conflicts and failed-save abandonment, and recover exact submission receipts. This has scoped headless/core/package proof, not current visible or conversation/voice qualification. See [[records/specs/manual-workflows]] for exact acceptance evidence and limits.

## Contextual conversation workflow answers

After an exact same-request workflow read, a contextual tool can prepare unsent typed inputs from byte-exact quotations in the current submission. It cannot confirm, continue or accept. Native reload preserves local edits; the editor shows original AI preparation separately from final human-confirmed values. Focused core/agent/session/package and actual-model proof is scoped in [[records/specs/manual-workflows]]. Voice/text confirmation, post-reload focus guard and paused-state wording remain follow-ups.

## Local conversation answer confirmation

Preview my answer and Save/Confirm my answer now bypass model loading in the native composer. Host-rendered exact values/document links and a live instance/session/conversation preview gate protect deliberate human submission. Input/context changes and intervening messages invalidate it; reopening never restores authority. Original AI preparation, final values and exact human confirmation provenance stay separate. Post-flush submission and post-reload focus ownership are corrected. Scoped automated/package/model evidence and remaining visible/voice/full-E3 gates are in [[records/specs/manual-workflows]].

## Calendar preview implementation contract

[[records/specs/automation-schedules]] adopts the reviewed first E4 slice: pure bounded native calendar previews, explicit zones and DST behavior, without activation, new persistence or workflow execution. Full trigger/runtime and UI gates remain open.

## Calendar preview qualification, October 29

The shared pure Swift planner and standalone CLI have13 focused groups/0,31 installed CLI cases and final native package/resource/refusal/signature proof. It exposes bounded coverage and exact local/UTC outcomes, and fixes the observed half-hour gap skip through bounded day-local resolution. No activation, new schema, model tool or execution. Full E4 durable state/runtime and native UI remain open. Exact evidence and three-pass contract: [[records/specs/automation-schedules]].

## Inert automation definition qualification, October 29

Schema19 now stores exact workflow/calendar intentions in the existing immutable application-definition family, with typed/nested item lineage, FTS, stale-base/idempotent saves and inert reconstruction. All326 core groups pass, plus36 installed automation/31 calendar CLI calls and native package/refusal/signature checks. Saving, importing, restoring and previewing grant no execution authority. Ordinary agent authoring stays closed. Explicit activation/device-local grants, durable occurrences/catch-up/overlap, foreground dispatch and E5 remain open. Contract and evidence: [[records/specs/automation-definitions]].

## Durable calendar preparation qualification, October 29

[[records/specs/automation-planning]] now implements schema20 authorization/occurrence/outbox storage, exact source-bound cursor/high-water state and revocable current-process planning capabilities. It passes343 full core groups at frozen V4,17 final focused groups,33 final installed CLI cases and final native package/refusal/signature checks; unchanged36 definition/31 calendar cases are reused. State is portable but authority is not reconstructed. Saved scheduling intent, process-local preparation permission and execution remain distinct. No workflow is dispatched. Persistent device grants, useful foreground execution/overlap, native configuration and E4/E5 event/condition/background/resource work remain required. This is not a new decision to make routine users repeatedly reauthorize work. Full app/release gates remain open.

## Foreground execution qualification, October 29

[[records/specs/automation-execution]] implements schema21's distinct explicit current-process execution/AI grant, atomic scheduled workflow dispatch, one active run, honest origin policy, source-specific claim revocation and explicit separately attributed manual control. Sources remain outside business evidence; bounded inspection and native scheduled wording distinguish execution provenance. Final359 full core/16 focused groups, synthetic lifecycle,2 actual SIGKILL boundaries/16 calls,44 execution/33 preparation/36 definition/31 calendar installed CLI cases, strict25 Swift files, skill validation and native package/resource/refusal/signature checks pass. No actual inference, visible UI or release claim.

Native foreground timer/configuration, persistent device-local physical-copy/workbook registration, reopen/wake/privacy/resources and event/condition behavior remain required E4 work. The run-once CLI installs no timer and cannot substitute for that UX. E5/E6, full E3/EJ/richer graphs, contextual/Excel continuity, hardware/performance and production release gates remain open.

## Native schedule owner qualification, October 29

[[records/specs/native-automation-owner]] adds native Activity/Schedules authoring/preview/enable/pause/manual Run once, persistent exact physical-workbook grants and a single active-app driver through the existing schema21 planner/dispatcher and ProductAI coordinator. Reopen restores the same explicit grant without new authorization. Copies/imports/reconstruction remain inactive; live registry/physical/cancellation fences protect claims, model admission and publication. Interactive work yields automatic work before model use.

Final 17 native registry/controller groups, six independent registration workers, two actual registry SIGKILL barriers, 16 execution groups, synthetic product lifecycle, 44 installed native CLI cases, strict 16-file Swift lint and native package/refusal/signature gates pass. The 359-group core run was on V4; final focused regressions cover subsequent same-guard closure naming. Detailed retained failures/evidence are in the owner contract. No actual model or visible UI was tested in this slice. This owner currently requires the active app and a key window; E22 background/closed-window behavior, real OS sleep/wake/privacy/resource interaction, E4 event/condition/conversation authoring and full E5/E6 are still required. The original full acceptance contract is unchanged.

## Condition transition foundation, October 29

[[records/specs/condition-transitions]] defines the reviewed staged business-event integration and implements its first pure numeric preview. It passes 13 focused groups including 243 short truth trajectories, 31 installed native CLI cases and nearby 13 calendar/16 execution groups. Unknown is not false; it cannot reset a condition. Duplicate identity cannot rewind state; changed content refuses. Explicitly inert fixture output grants no authority and proves no real event coverage. Exact committed-event state/cursor/outbox, loop/backpressure and native/conversation authoring remain required E4 work.

This checkpoint also repairs the registry creation race found by fab2a83 hosted CI, preserving the failed receipt. Final 18 registry/controller groups and five fresh starts/30 workers, strict seven-file Swift lint and native package/resource/refusal/signature gates pass. Schema21 and model/engine behavior are unchanged. The corrective head needs fresh CI; full release remains open.

## Committed business-event foundation, October 29

[[records/specs/business-events]] now implements schema22 semantic delivery within shared capture/apply, with exact versions, indexed bounded read pages and inert reconstruction. Final 386 full core groups with zero failures,14 focused groups, 76 installed CLI calls with six actual publishers/two actual SIGKILL boundaries, nearby owner/ProductAI/automation and native resource/refusal/signature checks pass. Persistent condition consumers, historical state, causality/backpressure and native/conversational event authoring remain required E4 work. The app remains a working development build.

## Persistent condition computation checkpoint

[[records/specs/inventory-condition-consumers]] now supplies schema 23 incremental inventory baselines, explicit ledger clocks, saved atomic working pages, exact observations and inert candidate queues.416 full core groups and 94 installed condition calls/two process-death boundaries pass with scoped native/nearby proof. It creates no timer or workflow authority. E4 still requires causality-aware admission/dispatch with exact physical grants, native/conversational authoring, dataset-query adapters and complete lifecycle qualification. Full E3/E5/E6, contextual/Excel and release journeys remain open.

## E4 derivation ancestry inspection

[[records/specs/automatic-ancestry]] now provides the schema-24 uniquely indexed workflow-source invariant and bounded read-only historical automatic ancestry. Synthetic acceptance/manual derivation retain origin; erased metadata cannot hide the registered source. Final 434 full core groups and 22 installed ancestry calls pass with focused native packaging/nearby proof. This includes control lineage, so it is not a minimal trigger cause slice or cascade budget. Exact condition causes, durable causal admission, atomic event dispatch with physical grants, native/conversation authoring and complete E4 remain open.

## E4 durable admission foundation

[[records/specs/automation-causality]] qualifies schema25 calendar roots and the internal trusted inherited admission primitive, including persisted self/cross-loop, depth, fan-out and root-total bounds. Full456 core groups, final nine independent successor writers, installed21 admission/47 execution/22 ancestry/94 condition/76 feed calls and native/durability checks pass with retained iteration scope. The existing foreground/native owner continues through the same dispatcher; no condition input selection, timer expansion or new device permission is added. Exact causal trigger inputs, independent business roots, current-grant candidate binding and native/conversation/dataset authoring remain next. Full E4-E6 and release are unfinished.

## E4 exact condition change-input foundation

Schema26 now captures the exact condition change-input windows specified by [[records/specs/condition-transition-inputs]]. Final470 core groups, installed30 input/97 condition/76 feed/22 ancestry/21 admission calls, owner18, synthetic ProductAI and full native package/resource/refusal/signature checks pass. There is no new model, native trigger-authoring flow, timer expansion or device permission. Actual contribution/control parent discovery, independent business roots and current-grant candidate-to-run dispatch remain next, followed by native/conversation/dataset adapters. Full E4-E6 and the app release remain unfinished.
