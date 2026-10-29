---
type: operational
id: 01m61qjtn2a03gwyv3sz9cgm0x
created: 2026-10-28T17:05:34.882631+00:00
updated: 2026-10-29T09:58:20.573002+00:00
summary: Authority and write-path inventory, complete commit capture, inert reconstruction and remaining qualification.
title: Local persistence coverage
---
# Local persistence coverage

October 28, 2026. Shared foundation for
[[records/specs/persistence-readiness]], after the reviewed table-update slice.
This inventories current schema/code, not cloud sync, workflow execution or the
complete app release.

## Agent requests and family read snapshots, October 28

Agent definition/action writes add no canonical family or physical schema. They use
current request-linked authoring/invocation Sources, existing captured definitions
and ordinary operation receipts. Creates derive stable identities from the request
operation token; updates require an exact current base. Preview/template receipts
are valid only after successful completion in the same active run/conversation.
Canonical save/invocation transactions recheck that run before publication.

The former whole-history revision invalidated a query/catalog continuation when
its own tool receipt was saved. Definition and dataset family clocks now live in
ordinary captured meta. Relevant writes set the family value to the same transaction's
commit ID before capture publishes; journal/context/presentation-only writes leave
it stable. Real relevant edits still invalidate cursors. Reconstruction restores
the recorded clocks inertly. There is no second ledger or sync claim. Tests use
actual prepared/completed journal calls, then relevant edits and reconstruction.
See [[records/operations/implementation]] for current qualification and limits.

## Schema14 action/form extension

No new ordinary canonical family is introduced beyond schema13. Action/form content,
heads and retained dependencies use the same captured definition tables. Invocation
Sources, draft movements/effects and operations publish atomically through mutation;
preview remains read-only. Events.insertMovement is the common transactional domain
path for direct movement, forms and CLI registry execution. No duplicate effect path.

`form-draft:` meta is explicitly classified portable presentation. FormDrafts saves
raw incomplete inputs and exact bound definitions with compare-before-save and
optional Keep both. A last receipt must match its actual invocation token, exact
form and submitted arguments. Reconstruction copies the current checkpoint separately
with conversation/navigation state, validates it and executes nothing. No keystroke
history, Source admission or search indexing. FormDraftSession/Scope serializes native
writes and participates in close/quit/workbook-switch flushing and crash reconciliation.

[registered action and form receipt](../../../integration/evidence/2026-10-28-registered-actions-forms.json.gz). Broad core217/shared harnesses, final packaged two-writer race,
publication fault, max50 lines, exact retries/actor/lineage, stale bindings, incomplete
input, concurrent alternatives and inert/portable reopening have scoped proof. The
Mac remains locked for visible native form/VoiceOver qualification. New model tools,
workflow/automation state and full FJ/EJ/release still require separate qualification.

## Current schema13 application definitions

app_definitions retains immutable UUID/logical identity, predecessor/version, kind,
content, searchable parameter labels, exact authoring Source and timestamp.
app_definition_heads selects the latest exact version. app_definition_dependencies
retains live/exact policy plus the exact resolved definition/data schema at save.
All three join ChangeFormat.tables, complete saved changes, schema validation,
authority digest and inert reconstruction. No second journal or executable replay.
Definition authoring Sources retain submitted content/actor as an observed save;
current business approval state stays separate. A changed live dependency is
rechecked at evaluation; saved dependency history remains unchanged.

External-content definition_fts and its shadows are disposable, synchronized by
immutable insert/delete triggers, checked against content and rebuilt after inert
replay or explicit search rebuild. Pure evaluation/search has no receipt or business
revision. Query templates reuse managed columns and their snapshot/coverage guards.

[application definition receipt](../../../integration/evidence/2026-10-28-application-definitions.json.gz). Final core208, two CLI editors, late publication fault,
exact history/actor/source verification, final packaged replay/portable reopen and a
10,001-definition/5,000-dependency synthetic corpus have scoped proof. FJ extension
covers these families; whole FJ/EJ/release qualification remains open. New workflow,
action invocation and form-draft families must extend this inventory independently.

## Read-only queries and disposable performance indexes

Schema 12 adds no durable family for query evaluation. Canonical immutable inputs,
exact definitions and the committed history snapshot bind results/cursors. No query
publishes a business receipt or revision. Optional native index descriptors are
recovered from validated generated structure, not business metadata or historical
SQL. Index-only writes use the existing package lock/SQLite transaction and leave
committed history unchanged. Growth eviction shares the ordinary row transaction;
a late publication fault rolls back the row and dropped index. A copied runtime
without size accounting may drop optional indexes rather than block business edits.

[managed query/index receipt](../../../integration/evidence/2026-10-28-managed-query-indexes.json.gz). Final core191 and packaged 1k/10k/50k probes cover indexed
edits/repair, concurrent optimizers, exact retained history, inert reconstruction
without indexes and portable reopen. Rebuild now has an explicit cancelable
30-second maintenance budget; interactive queries retain three seconds. New in-app
model tools, native query UI and complete MJ/FJ are not claimed. Fault tests use
isolated TEMP triggers/adapters; see the implementation register for actual timing,
resource scope and the retained first 50k safe rollback.

## Current schema-12 dataset definitions

[dataset definition lifecycle receipt](../../../integration/evidence/2026-10-28-dataset-definition-lifecycle.json.gz). The existing column_versions family now retains complete definitions
with UUID/predecessor, title, logical columns/constraints, archive state, decision
Source and time; datasets points to the current exact definition. Trusted physical
materialization and shared capture/reconstruction remain unchanged in authority.
Core 177, packaged lifecycle/unique merge Undo/redo and visible frozen-base native
editing have scoped proof. Required/unique constraints preserve exact Decimal and
null semantics. Removed values remain in immutable payloads, and active row edits
retain them plus exact definition lineage. Formula evaluation honors the declared
active schema. Partial intake refuses new batches after a definition change.
The query/index checkpoint above supplies stored-scalar paths; full E0-D/MJ
qualification, including Excel continuity, remains open.

## Managed dataset foundation, schema 11

The runtime now classifies registered native dataset tables as rebuildable current
projections. Reserved immutable row versions, heads, column_versions and stable
membership/order remain authoritative. Both classes use the same committed_changes
chain. See [[records/operations/implementation]] for the foundation receipt, measured
results, final native observations and retained failed attempts.

ManagedDatasetSchema validates registry descriptors and generates exact trusted DDL.
ChangeCapture refreshes TEMP triggers when another connection changes the schema;
50-column callback fragments preserve one lossless row image within SQLite's
127-argument limit. ChangeApply materializes a saved logical definition before its
dependent rows. A shape change removes old projection rows, updates the descriptor,
recreates its physical table and inserts the new projection in one transaction.
A typed reset marker permits independent repair without admitting corrupt projection
before-values as authority. It can target only registered projections. Verification
checks schema history, membership, exact canonical heads and every scalar/sidecar.

The earlier core 168, packaged 1k/10k and native table edit/Undo/reopen tests provide scoped
FJ/MJ coverage. Existing shared paths now use the projection, including reviewed
intake updates and their Undo/redo. The later schema-12 lifecycle slice above adds removal/archive/constraints and
exact-base authoring. The query/index checkpoint supplies the stored-scalar subset;
complete MJ qualification remains open.
No new ledger, executable payload SQL, sync or release qualification is claimed.

## Capture and identities

Schema 10 introduced one `committed_changes` chain, retained by schemas 11 and 12. An ordinary commit shares the
existing operation ID. The same SQLite transaction publishes complete typed
before/after values, state and receipt. Infrastructure commits use a separate
UUID. Each change keeps workbook/commit/writer identities, actor, schema, original
timestamp, predecessor commit ID/hash and exact row predecessors. Item supersedes,
annotation predecessors, membership and update fingerprints remain exact edit
bases; lineage remains derivation. Local counters are not distributed ordering.

`Database.transaction` owns capture. Each validated Workbook connection installs
temporary capture triggers and a Swift function using public SQLite APIs. Opening
compares the exact reserved schema and registered generated dataset structures with
the declared classification. New table families must join this inventory. Metadata is infrastructure, not a third business category.

Typed values preserve Int64 strings, IEEE-754 bits, UTF-8 bytes/NULs, empty blobs
and nulls independently of the public JSON Double API. Explicit native review is
human; default core/CLI action is programmatic. Model tools retain their registered
run model and draft-policy identity. Writer UUIDs identify actual connection
instances without inventing people/accounts. Saved rows preserve inputs, effective
times, transformations, output IDs, asset hashes and occurrence/effect identities.

The current implementation refuses over 64 MiB of raw changed values or 250,000
row changes in one transaction. These are metadata limits, not asset-size limits.
History is retained in full; verified compaction is unimplemented. History
inspection reads small saved metadata instead of loading complete payloads.

## Authority and write-path inventory

| Family | Classification and authority | Current paths and coverage |
| --- | --- | --- |
| Package identity/title | Declared manifest, canonical initial schema, workbook ID. No title-edit API. | `Workbook.create/open`; reconstruction copies exact manifest and refuses existing destinations. |
| Sources/Records/lineage | Immutable versions, exact supersedes and derivation edges; captured heads materialization. | `Workbook.insertItem`, `Documents`, `DocumentComposition`, `Events`, `DraftWithdrawal`, table/reference helpers. Shared capture plus current invariant/stale checks. |
| Assets | Included immutable files, identity/hash/name/type/origin and historical references. Linked path/bookmark are device access state. | `Assets.importFile`, `URLCapture.includeLinked/relinkAsset`, archive intake/copy. File and directory flush precede publication. All historical included dependencies retained. Paths/bookmarks excluded from portable history. |
| Extracted evidence | Saved chunks, locators, parser/state/detail/time; immutable file-reference input regions/hashes retain replaced extraction. | `Extractor`, `Search.index`, `FileReferenceWrites`. Saved outputs replay without extraction. Worker attempt claims excluded. |
| Tables/formulas/order | Immutable row versions and complete causal dataset definitions, stable membership/order and registered native projections; the same committed journal includes schema descriptors, projection rows and typed reset markers. | `Tables`, `Intake`, `XLSX`, `TableIntakePublication/Undo`, `TableProposals`. Existing checked apply/Undo/redo. Mapping form drafts remain an open UX gap. |
| Inventory/decisions | Opening basis/source/effective time; occurrence/subject/kind effects; actor, exact accepted/withdrawn/restored outcomes. | `Events`, `DraftWithdrawal`, `Tables`, `TableIntakeUndo`. Explicit native human review; programmatic default; model tools stay draft-limited. |
| Application definitions | Immutable definitions, selected heads, retained exact/live dependency bindings and authoring Sources. FTS is disposable. | `ApplicationDefinitions`, `DefinitionFunctions/Queries/Evaluation/Discovery`; exact-base save/restore, read-only evaluation, typed dependency checks, atomic failure and inert replay. Schema14 action/form execution reuses Events/ActionExecution. Workflow/automation state remains open. |
| Receipts | Complete request/result, ID/kind/time/revision, atomic with changed values. | `Workbook.mutation`. Matching retries add no change; changed arguments or explicit decision actor refuse. |
| Conversation | Bodies/payloads, exact message IDs/order, tangent parents/names, chapters/bookmarks. | `Spaces`, `ConversationNavigation/Actions`, `Runs`, `RequestHandoff`. Physical message row IDs preserve current transcript order. |
| Tools/runs/context | Exact arguments/output/hash/prepared state, model/status/metrics/times; checkpoint summaries/ranges/inputs/parents. | `ToolReceipts`, `Runs`, `RequestHandoff`, `ConversationContext`. Replay never executes prepared calls or resumes/regenerates runs/summaries. |
| Spaces/documents | Versioned definitions, pinned snapshots and exact composition evidence. | `Spaces`, `ComponentData`, `Documents`, `DocumentComposition`. Current and historical versions captured. |
| References | Immutable annotation sets/predecessors/targets/locators/inputs; heads/index/coverage materializations. | `ReferenceWrites/Index`, `FileReferenceWrites`, `Search.index`. Captured exactly, with existing deterministic rebuild/validation. Broader projection-elision optimization is unimplemented. |
| Intake | Selected source/use, reports/outcomes/dataset IDs, failure/cancel details/times. Attempt tokens are worker claims. | `ContextualIntake`, `Intake`, `TableIntakePublication`; progress meta also captured. Attempt field becomes null in portable changes. |
| Presentation | Current portable checkpoint of draft alternatives/reading positions, space pins/recents, incomplete form drafts/bindings/receipts and workflow clarification inputs/alternatives. No business revision or semantic admission. | `ConversationViewState`, `SpaceNavigationState`, `FormDrafts` via `presentationMutation`. Values copied separately; no keystroke journal. |
| Search | Chunks are retained evidence. Four FTS indexes/shadows are disposable. | `Search.rebuildSearch`; reconstruction rebuilds all FTS from saved messages/chunks/definitions, without FTS shadows in changes. |
| Device execution/access | Locks/staging, extraction attempt table, intake attempts, bookmarks/linked paths, model installs, recent-workbook/last-conversation UserDefaults. | `Workbook/Database`, `Extractor`, `Assets/URLCapture`, native/product setup. No copied grants or claims become portable authority. Pending outcome rows stay inert history. |
| Export/copies | Coherent DB snapshot plus all included historical dependencies. | `Archive.export/openArchive`, `AssetCopies`, CSV export, reconstruction. Outward file/CSV exports are outputs, not new canonical mutations. |

The initial SQL audit found 129 write/transaction matches. Live canonical writes
route through `mutation` or `presentationMutation`. Raw Database writes are initial
creation, schema validation, coherent export sanitization, disposable FTS checks,
or inert reconstruction. Connection-local capture does not prevent an unrelated
SQLite editor from tampering. Reconstruction detects unlogged authoritative edits,
missing changes, hash corruption and inconsistent envelopes.

## Reconstruction

`Workbook.reconstruct(to:)` and `sevra reconstruct` snapshot the source, create the
declared current-format initial state and disable storage triggers on an isolated
connection. Apply requires the right workbook/schema/hash, exact predecessor chain,
before-values, table shape and foreign-key closure. It preserves IDs/times; same
ID/payload is idempotent, changed content refuses. No payload SQL/tool/model/workflow
runs as an instruction. Apply itself refuses a non-inert connection.

A final authoritative digest must equal the source snapshot. Current presentation
is copied separately. Included historical bytes are streamed/hash-checked; missing
linked assets remain unresolved without copied paths/bookmarks. Missing included
bytes fail. FTS rebuilds from retained content, then ordinary core integrity,
reference/document/context/receipt validation runs before publication. Deterministic
validation does not extract new content or choose new targets. Failure/cancellation
preserves the original and leaves no published destination.

This is local, current-schema, single-head reconstruction. No backward migration,
legacy backfill, accounts, enrollment, transport, distributed ordering, resolver
or workflow runner. E19 must reuse this chain, not create another ledger.

## Acceptance and limits

The representative core fixture covers inventory acceptance/Undo/redo/withdrawal,
table edits/reviewed intake updates, assets, replaced extraction/historical locators,
body/file bindings, source-bound reports, messages/payloads, tangent/chapter/bookmark
history, checkpoints, spaces, contextual intake and portable drafts/pins. Targeted
fixtures cover duplicate/changed apply, publication-failure rollback, corrupt/missing/
out-of-order/unknown history, unlogged state, actor/model/policy, exact typed values,
linked grants, export/reopen and missing required bytes.

Fresh native app/CLI packaging, strict ad-hoc signature verification and 150 core
groups pass. The final packaged 10,000-row check preserves 34 exact changes across
12 independent writers, retry, conversation-history coexistence, cancellation
after observing a committed prefix, export/reopen and another reconstruction.
Import took 2.920 s; reconstruction took 3.454 s; SQLite held 35,045,376 bytes on this
Mac/fixture. This is a measurement, not a universal throughput or latency promise.
A separate 30-writer run preserves coherent export, stale guards, retry and stock
18. Four preserved process-death/interruption fixtures reconstruct successfully.

The native synthetic journey explicitly accepted and undid an estimate with human
attribution, saved an unsent composer draft, reconstructed, then reopened the same
transcript, decision history and draft. Existing extraction/package checks are
reused because worker code is unchanged. Final changed Swift formatting, skill
validation, Python compilation and shell syntax pass. Earlier broad checks pass;
the later exact-rule/journal-verification changes have final core/package coverage.

`verify` now checks saved payload hashes, envelope metadata, predecessors and
receipt closure from one coherent read transaction. Reconstruction also checks
all authoritative state. AI decisions require an exact accepted current rule Source
and retain that version as an input. A missing rule, policy label or superseded rule
refuses. Attribution never confers authority or adds automatic acceptance tools.

FJ01-FJ06 pass within the inventoried current-family, local single-head scope.
New action/workflow state must extend the inventory and demonstrate the same gates.
Evidence: [persistence foundation](../../../integration/evidence/2026-10-28-persistence-foundation.json.gz),
30,925 bytes, SHA-256 `c82f6169bffdc2b60c62ea70918e7fe2edf9740da2b7534c4e89c9cffeb9e4da`.
All 101 earlier evidence files are byte-identical to the parent checkpoint.

Next: E1 editable Home/spaces, then E2 actions/forms/functions and E3 manual durable
workflows. Contextual Excel continuity, local-model intake, context qualification,
accessibility, hardware, engine adoption, installation and release gates remain open.

## Primary technical references

Connection-local triggers and function callbacks use
[SQLite CREATE TRIGGER](https://www.sqlite.org/lang_createtrigger.html) and
[the public function API](https://www.sqlite.org/c3ref/create_function.html).
Replay queries/disables main-schema triggers with
[SQLITE_DBCONFIG_ENABLE_TRIGGER](https://www.sqlite.org/c3ref/c_dbconfig_defensive.html).
The preliminary preupdate-hook prototype was abandoned before product use because
the host Apple SDK omits those declarations. No private SDK declarations or alternate
SQLite runtime were introduced.

[[records/operations/implementation]]

## E1 layout mutation extension, October 28

The editable Home/space slice reuses spaces/space_versions and the existing
committed-change family, with exact-base/history checks. Native and CLI saves,
failed publication, same-token retry, competing handles, portable history and inert
reconstruction pass in the editable-Home receipt linked from
[[records/operations/implementation]]. No new ledger or replay path was introduced.
The 156-group core run includes this extension. Future definition/action/workflow
state still needs its own schema classification and scoped FJ proof.

## Managed dataset extension, adopted October 28

[[records/specs/managed-datasets]] defines the pending E0-D storage target. Existing
schema-10 capture and the E1 extension remain qualified within their recorded scope.
Current datasets/dataset_rows/heads/items JSON storage, the fixed ChangeFormat table
set, positional row values and physical-rowid/single-chain apply do not implement
managed native dataset creation or dynamic schema reconstruction.

Extend this same inventory/capture/apply system with a trusted dataset/schema
registry, authoritative versioned definitions and row versions, registered native
projections and managed indexes. Record logical schema changes and materialize their
trusted physical structures before dependent rows during replay. Prove independent
projection rebuild and schema-plus-data reconstruction under MJ01-MJ08 and FJ01-FJ06.
One transaction preserves receipt/history/lineage/current-state consistency.
Physical rowids remain local implementation details; new semantic references use
stable logical identities. No second history ledger or replication service is added.

This is the next storage prerequisite before dependent E2/E3 dataset/action/workflow
persistence, after any coherent in-flight checkpoint. Update this inventory with
actual paths and scoped evidence as implemented. Existing passing receipts are not
proof of the new target; no new runtime qualification is claimed by this note.


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

## Retained computation and publication, October 28
Schema14 adds no canonical family for this slice. Component arguments/snapshots use captured space history. Published values, exact definitions, scoped candidate row versions and invocation attribution use ordinary immutable Source/Record lineage and the same operations transaction. Publication re-evaluates under the write lock and refuses changed/partial/oversized output; invocation/result publish atomically. Exact retries retain the original result. Acceptance creates a review version without changing meaning/data.

The [native computation receipt](../../../integration/evidence/2026-10-28-native-computation.json.gz) covers fault/cancellation/refusal rollback, current/historical values, complete query candidate population, portable reopen and inert reconstruction. Candidate population is not per-group membership. Saved results cap5,000 input-version entries and512KiB retained result/provenance. No replay executes AI/actions, second ledger, cloud/sync or replica completion. Full persistence/engine journey qualification remains open.

## Manual workflows, schema 15
The shared capture inventory now includes workflow runs, ordered steps, worker attempts, exact proposal approvals and a workflow outbox. Step effects, result/provenance, run state and outbox commit with one ordinary operation receipt. A final lease guard executes after capture and immediately before COMMIT; expiry rolls the entire transaction back. Worker generations remain monotonic across explicit retry-budget renewal.

Process-local execution sessions are deliberately outside the workbook. Replay and portable copies preserve claim history and exact outputs without acquiring execution authority or invoking a calculation/action/LLM. SIGKILL fixtures cover claim, prepared transaction and committed checkpoint boundaries. Broader import/AI/native/background and full portability journeys remain open in [[records/specs/manual-workflows]].

## Workflow-form submission and presentation recovery
A form targets exactly one action or workflow. Workflow submission inserts the queued run, original actor/invocation Source linked to both definitions, typed inputs, steps, outbox and operation receipt in one shared captured transaction. It creates no process-local execution session. The trusted workflow-start body is shared rather than nesting public mutations. Optional origin data retains the exact preview; no new table or schema version is required.

Form presentation keeps its stable submission token. The generic saved form receipt reconciles either registered-action or workflow submission before rendering another submit opportunity. Reconstruct/copy both committed and pre-presentation-save states without worker activation. Actual process death before commit leaves no run/receipt; after commit retains exactly one queued run. Explicit native Start can continue only in its originating workbook/window. [Workflow-form scoped proof](../../../integration/evidence/2026-10-28-workflow-forms.json.gz); broader workflow/trigger/helper and release gates remain open.

## Conversation workflow queue and Activity clock
Agent starts carry the active request run/Source into the same atomic workflow-start operation; captured invocation lineage retains the actual AI actor. Revalidate request scope inside the transaction. Exact retries return the same saved run without worker authority. Reconstruction retains all run state without execution.

The workflow-read-snapshot meta key records the current committed-change identity only when workflow_runs changes. It is captured and reconstructed in the existing ledger. Activity cursors bind this family clock plus workbook/filter/page size, so their own tool-journal receipts and unrelated writes cannot stale their next page. Run changes still refuse stale continuation; the response retains actual workbook revision independently. Core251, focused20 and full shared checks pass; [agent workflow evidence](../../../integration/evidence/2026-10-28-agent-workflows.json.gz).

## Explicit AI workflow capture, schema16
workflow_interpretation_request retains exact normalized arguments, evidence/extraction identities, model/messages/schema/budget and observed revision before inference. workflow_interpretation_response retains the bounded raw envelope as diagnostic history before validation. Neither operation alone creates a business Record. Publishing requires the exact retained envelope; normalized decimal output is independently verified against it during integrity/reconstruction. Validated output/Record/lineage/checkpoint/attempt/receipt/outbox commit together under a fresh final claim/deadline/cancellation fence.

Core256/0, focused25/0 and final product lifecycle checks pass. Nine real process-death boundaries now include interpretation request, raw response, pre-COMMIT and post-COMMIT. Reconstructed copies preserve diagnostics and saved results without inference. Async tests prove other workbook writes proceed while the model waits. These local guarantees do not establish exactly-once model invocation or sync/replica semantics. The [interpretation receipt](../../../integration/evidence/2026-10-28-workflow-interpretation.json.gz) retains scoped proof and failed cases.

## Conversation interpretation authoring capture
Conversation interpretation saves and exact workflow templates reuse schema16 application definition Sources/dependencies, stable retry tokens and the same committed-change ledger. In-app logical identity belongs to the host; edits identify an exact base. The template read is metadata-only, not a mutation or execution grant. Raw failed tool receipts and model finish arguments remain available even when host presentation replaces false success. Fullcore260/0 and the final native-model author/workflow/queue fixture preserve one pending run and no business Records; inert reconstructed copies verify. No schema17, new independent ledger or sync claim is introduced. See [[records/specs/manual-workflows]].

## Native preparation capture, schema17
workflow_extraction_request captures exact included business item/asset/hash, definition/parser, actual worker executable digest, limits, read revision and attempt identity. No DB lock spans helper hashing/parsing. The same captured publication contains index/FTS/status/reference input+snapshot and workflow output/checkpoint/attempt/receipt/outbox, with final worker lease/cancel/extraction-owner fencing. Retry may repeat uncommitted parsing but returns the exact committed receipt. Retained extraction lineage remains independent of later current index changes. Thirteen actual SIGKILL boundaries,268 broad core groups,37 final focused workflow groups, async real-child lock/cancel checks and the final packaged-model receiving flow pass. Inert reconstruction preserves exact output and stock. No parallel ledger or sync semantics are introduced. See [[records/specs/manual-workflows]].

## Conversation preparation and real SQLite failure checks
Extraction authoring/templates use the same immutable application Sources, exact current-request lineage, saved receipts and committed-change ledger. Queueing remains inert. Final actual-model original/reconstructed packages verify with no business Records and unchanged retained file text. Actual SQLITE_FULL from a bounded max_page_count and SQLITE_BUSY from a second writer refuse preparation publication without changing index/reference/revision. Clearing the condition permits exact retained-result retry; no re-parsing or duplicate checkpoint is needed. Whole-volume filesystem exhaustion remains a separate release test. No new ledger or schema change beyond17. See [[records/specs/manual-workflows]].

## Registered document action capture, schema17
Registered records.draftDocument adds no canonical table family or alternate ledger. Existing application definitions, invocation Sources, document Records, lineage, chunks/reference indexes, workflow steps/attempts/approvals/outbox and operation receipts use the same captured mutation and inert reconstruction. Review accepts an unchanged direct successor with preserved meaning/scenario and authentic acceptance decision provenance. Accepted report estimates have no inventory effect.

The [registered document receipt](../../../integration/evidence/2026-10-28-registered-documents.json.gz) preserves 278 passing core groups, 15 process-death boundaries/116 worker calls, native form receipt recovery and a 37-call actual packaged-model receiving/report flow. The final run has six completed steps, separate report/inventory review, report estimate preserved, stock 25 only after stock acceptance and inert original/reconstructed integrity. This is scoped local persistence proof, not cloud sync, all FJ/EJ journeys or production readiness. Structured intake must inherit the capture and retained-plan requirements in [[records/specs/manual-workflows]] before new state is implemented.

## Reviewed workflow intake capture, schema18

Schema18 extends only the existing definition/step kind constraints; no independent ordinary-table family or ledger. Exact intake definitions/dependencies and workflow_intake_request use captured application/operation state. The host retains request identity, actual read revision, original/hash, schema/mapping, parser/helper digest and limits. Complete mapped values and source coordinates live in the existing table-intake-update Record. Its proposal, lineage, small digest/count checkpoint, approval, attempt, receipt and outbox publish together. A final lease/cancellation fence covers capture through COMMIT.

Canonical acceptance atomically records row versions/membership/fingerprint plus its exact operation/decision identity. Workflow review checks the unchanged original plan and authentic acceptance receipt; it cannot accept edited/copied-looking/undone alternatives. Assets remain outside SQLite. Existing schema reconstruction recreates constraints and all retained records/definitions without parsing, model calls or row execution. Full 289 core, 21 SIGKILL boundaries/189 worker calls, real SQLite BUSY/FULL/child-lock cancellation checks and final actual-model original/reconstructed integrity pass. This is scoped local proof, not all FJ/EJ journeys or sync semantics. See [[records/specs/manual-workflows]] and the final intake receipt linked there.

## Conversation intake metadata, October 29

This slice adds no durable family or independent ledger. Intake definitions, exact workflow/template copies, request Sources, model/tool receipts and queued runs use existing captured changes. Two focused tests cover current-request lineage, idempotent saves, forged/stale/read-only refusal and inert reconstruction. The actual model saves only behavior/queue metadata; row versions, business Records, stock and extraction remain unchanged. The prior schema18 parsing/publication/acceptance crash proof is unchanged and reused. Details and evidence: [[records/specs/manual-workflows]].

## Workflow scalar lookup, October 29

No new durable family or schema. Lookup definitions reuse the captured catalog; complete query results retain their exact selected row versions/snapshot/input population in the existing workflow checkpoint. Action invocation Sources include exact query-definition and selected-row lineage through calculations. A publication fault/cancellation leaves saved history/run unchanged; exact retry and inert reconstruction pass. The actual model job repairs an unfinished lookup without rerunning completed extraction/interpretation. Earlier schema18 lease/disk/process-death proof is unchanged and reused. See [[records/specs/manual-workflows]] and its immutable lookup receipt.

## Workflow clarification, October 29

No new canonical family or physical schema. The existing captured mutation atomically publishes submission Source, draft clarification Record, completed step/run state, exact receipt, event and outbox. The original request/model response stays unchanged. Exact token retries, forced rollback/cancellation, inert reconstruction, and two new actual process-death boundaries prove this publication path.101 deterministic calls qualify before/after death recovery; prior shared lease/disk proofs are reused. Typed downstream lineage retains supplied provenance and meaning. Native input drafts and presentation recovery remain unimplemented for this boundary. See [[records/specs/manual-workflows]].

## Clarification presentation checkpoints

WorkflowClarificationDraft stores bounded raw values, explanation, exact historical target/retry identity, a small receipt projection and up to eight alternatives under meta workflow-clarification-draft:RUN_ID. ChangeFormat excludes this prefix from authoritative payloads/digests; presentationMutation uses exact-baseline compare-and-save. Reconstruction copies the checkpoint separately and Assets verification validates targets against retained historical publication receipts. Exact canonical operations recover missing presentation acknowledgement. At128 cached runs only wholly submitted checkpoints may be pruned; every unsent alternative and canonical history is retained. Headless fault/switch/quit, cross-window conflict, stale/reconstructed draft and submission-recovery checks plus302 core groups pass. This is local presentation persistence, not sync or a new ledger. See [[records/specs/manual-workflows]].

## Conversation answer preparation persistence

The existing portable clarification checkpoint now retains optional exact current-request/read-receipt preparation provenance. Shared presentation transactions compare/save it without business revision. Human edits keep original prepared values; captured canonical clarification submission retains final values plus both original model and current request Source lineage. A synthetic outbox trigger fault proves rollback and retry; inert reconstruction validates retained metadata. Scoped65-group/session/agent and30-call actual packaged-model proof is in [[records/specs/manual-workflows]]. This adds no new schema family or ledger.

## Conversation confirmation capture

Native composer confirmation uses the existing workflow_clarification operation/token, supplied Source/Record and captured ledger/outbox. Metadata retains exact human confirmation and host preview message/hash identities. Current transaction checks saved typed inputs/target/current-message adjacency/cancellation; historical integrity checks exact retained messages/hash. Outbox fault and prepared-stage cancellation roll back; receipt recovery and inert reconstruction validate retained confirmation without restoring live authority. Final66 focused workflow groups and native session/package checks pass. This is scoped local persistence, not a new ledger, sync or background execution. Details: [[records/specs/manual-workflows]].

## Schema19 inert automation capture

Automation reuses app_definitions, heads/dependencies, authoring Sources/lineage and the same committed-change ledger. The only physical schema change is the kind constraint. Exact-base/idempotent versioning, nested item evidence, pinned workflow history, publication-fault/cancellation rollback, source/dependency corruption checks and inert reconstruction have new scoped proof within the326-group full core pass.36 installed automation CLI calls plus31 calendar calls and final native package/refusal/signature checks pass. No activation, new ledger, trigger execution or claim of a fresh whole SIGKILL matrix. Details: [[records/specs/automation-definitions]].

## Schema20 activation and occurrence capture

All new automation_activations, automation_occurrences and automation_outbox rows join ChangeFormat.tables and the trusted canonical capture/apply path. Sources retain authorization/pause attribution, original slots, skipped reasons and exact cursor/observed coverage. Tests cover publication rollback, cancellation, stale receipts/session revocation, two-connection authority, concurrent planning, altered evidence and inert reconstruction with no runs/events. Frozen V4 passes343 full core groups; final read-only list addition passes17 focused groups. Final33 installed CLI cases and native resource/refusal/signature proof pass; unchanged36 definition/31 calendar CLI cases are reused from V4. This is not fresh model or whole process-death/release qualification. Contract/evidence: [[records/specs/automation-planning]].

## Schema21 occurrence-to-workflow capture

automation_runs and the new activation active-run pointer, dispatched occurrences/outbox, workflow policy and attempt authorization_source all join the existing capture/apply path. Exact original grant/dispatch/invocation evidence survives manual continuation, generation changes and inert reconstruction/archive. Integrity checks original normalized inputs, exact workflow version, invocation origin/actor, eligible time, one active reservation, Source decisions/lineage and per-attempt authority. Pause releases only its own claims; independently authorized manual work is preserved.

Final359 full core/16 focused groups, synthetic lifecycle,2 actual SIGKILL dispatch boundaries/16 worker calls,44 execution/33 preparation/36 definition/31 calendar installed CLI cases and final native package proof pass. No whole previous manual crash-matrix rerun or broad model/release claim. Metadata isolation and the repository skill are updated; all136 prior evidence artifacts are byte-identical. Device-local persistent authority/timer and full release gates remain open. Contract/evidence: [[records/specs/automation-execution]].
