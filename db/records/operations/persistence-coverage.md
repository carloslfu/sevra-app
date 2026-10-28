---
type: operational
id: 01m61qjtn2a03gwyv3sz9cgm0x
created: 2026-10-28T17:05:34.882631+00:00
updated: 2026-10-28T19:17:12.507481+00:00
summary: Authority and write-path inventory, complete commit capture, inert reconstruction and remaining qualification.
title: Local persistence coverage
---
# Local persistence coverage

October 28, 2026. Shared foundation for
[[records/specs/persistence-readiness]], after the reviewed table-update slice.
This inventories current schema/code, not cloud sync, workflow execution or the
complete app release.

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
Typed query/index policy and full E0-D/MJ qualification remain open.

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
exact-base authoring. Typed query/index policy and complete MJ qualification remain
open.
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
| Receipts | Complete request/result, ID/kind/time/revision, atomic with changed values. | `Workbook.mutation`. Matching retries add no change; changed arguments or explicit decision actor refuse. |
| Conversation | Bodies/payloads, exact message IDs/order, tangent parents/names, chapters/bookmarks. | `Spaces`, `ConversationNavigation/Actions`, `Runs`, `RequestHandoff`. Physical message row IDs preserve current transcript order. |
| Tools/runs/context | Exact arguments/output/hash/prepared state, model/status/metrics/times; checkpoint summaries/ranges/inputs/parents. | `ToolReceipts`, `Runs`, `RequestHandoff`, `ConversationContext`. Replay never executes prepared calls or resumes/regenerates runs/summaries. |
| Spaces/documents | Versioned definitions, pinned snapshots and exact composition evidence. | `Spaces`, `ComponentData`, `Documents`, `DocumentComposition`. Current and historical versions captured. |
| References | Immutable annotation sets/predecessors/targets/locators/inputs; heads/index/coverage materializations. | `ReferenceWrites/Index`, `FileReferenceWrites`, `Search.index`. Captured exactly, with existing deterministic rebuild/validation. Broader projection-elision optimization is unimplemented. |
| Intake | Selected source/use, reports/outcomes/dataset IDs, failure/cancel details/times. Attempt tokens are worker claims. | `ContextualIntake`, `Intake`, `TableIntakePublication`; progress meta also captured. Attempt field becomes null in portable changes. |
| Presentation | Current portable checkpoint of draft alternatives/reading positions and space pins/recents. No business revision or semantic admission. | `ConversationViewState`, `SpaceNavigationState` via `presentationMutation`. Values copied separately; no keystroke journal. |
| Search | Chunks are retained evidence. Three FTS indexes/shadows are disposable. | `Search.rebuildSearch`; reconstruction rebuilds all FTS from saved messages/chunks, without FTS shadows in changes. |
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
