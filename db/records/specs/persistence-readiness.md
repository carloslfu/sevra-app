---
type: spec
id: 01m61nphrhdhafzcdjn35zka1b
created: 2026-10-28T16:32:39.697180+00:00
updated: 2026-10-28T18:14:38.837664+00:00
summary: Required complete, causal and replayable local persistence for future syncing; cloud, transport, replica coordination and a new conflict resolver remain out of scope.
title: Persistence readiness for future syncing
status: reviewed
---
# Persistence readiness for future syncing

Adopted requirement, October 28, 2026. Owner authority:
[[sources/notes/2026/10/persistence-readiness-requirement]]. This is an implementation
requirement with scoped local acceptance recorded below, not a claim that sync or the full app is ready.
It extends [[records/specs/storage]], [[records/specs/intelligence]] and
[[records/specs/native-app-engine]] without implementing synchronization.

## Scope and current evidence

Audit every durable mutation path and fix missing persistence needed to reconstruct
and later exchange workbook history. Keep SQLite, the shared Swift core, immutable
Sources/Records, ordinary asset files and the .sevra/.sevraz formats. Do not add
cloud accounts/storage, hosted backup, a cloud UI, network transport/protocol,
replication workers, replica enrollment/coordination, distributed execution,
branch-merging UI or a new semantic conflict-resolution service. No database or
cloud provider is selected by this requirement.

At checkpoint 63cd642, the mutation core already commits operation receipts with
state changes and protects retries. Immutable item versions and assets preserve
substantial evidence. The operation journal alone is incomplete: message receipts
save an ID while the body lives in another table, and opening-balance receipts omit
the effective time/source. Version numbers and a single current head describe local
editing. These observations identify audit targets, not a demand for a second
business data model or proof that existing data has been lost.

## Managed dataset extension

[[records/specs/managed-datasets]] is the adopted next storage extension. Keep the
implemented shared committed-change foundation and its existing evidence. Native
dataset tables are projections over authoritative immutable row versions and
versioned definitions. Register their capture/classification, record logical schema
changes, and materialize trusted schemas before applying dependent saved rows.
Reconstruct both schema and values; independently rebuild query projections from
retained authority. A row-only change log with a fixed table whitelist is insufficient
for dynamic datasets. No parallel ledger or executable SQL in historical payloads.

Current FJ passes qualify the inventoried fixed-schema families. The new M/MJ
requirements extend that coverage; they are pending and do not retroactively turn
local physical-rowid/single-chain replay into a multi-device merge contract.
Stable logical identities and causal/schema dependencies are required preparation.
Cloud, transport, branch ingestion and a new resolver remain outside this slice.

## Required persistence contract

F01. Inventory authoritative state and its write paths across UI, CLI and local
agent. Cover Sources/Records and exact lineage; assets and retained extraction used
as evidence; tables, schema/formulas and ordering; opening bases, effects and
decisions; conversation bodies, attachments, tool results and checkpoints; saved
spaces/documents; and intake definitions, outcomes and user-facing run history.
New workflow/action definitions and completed results inherit this contract as
those features are implemented. Identify which fields belong to immutable history,
mutable projections, portable presentation state or device-local execution state.
A summary, hash or operation ID alone is not a replacement for the referenced data.

F02. Persist a versioned committed-change representation, containing or durably
referencing all exact values and immutable objects needed to apply a change.
Retain commit/operation ID, workbook identity, actual actor/writer identity, recorded
and effective times where relevant, exact base/predecessor versions, dependencies,
transformation identity, resulting IDs and required asset hashes. Preserve deletes,
withdrawals and Undo as explicit historical changes. Checkpointing is allowed, but
a complete checkpoint must retain required history/evidence and declare its covered
commits. Do not silently discard history or substitute a prose summary.

Reuse existing Sources/Records and receipts; commit metadata is infrastructure,
not a third user-facing business category. Referencing existing immutable payloads
is sufficient when their retention and dependency closure are guaranteed. One shared
capture/apply contract must cover all durable mutation paths, including changes to
state outside the items table. Current heads, balances, indexes and other declared
projections must be reproducible from preserved authority.

F03. Keep workbook, logical entity, immutable version, operation and business
occurrence/effect identities distinct. Preserve globally unique immutable version
and operation identities and explicit exact predecessor/base-version references.
Semantic derivation links do not replace edit causality. Record actual writer/actor
identity without inventing a person or requiring an account/enrollment service.
Retain original times; replay must not generate replacement identities or timestamps.
Numeric version counters and workbook revisions remain useful local guards/display
values; they are not global identity or an ordering rule for future replicas.
Document single-head/schema assumptions. Implementing concurrent branch ingestion,
winner selection, semantic deduplication or distributed ordering is outside this slice.

F04. Provide a deterministic local reconstruction/apply path for verification and
recovery. Starting from the declared initial state or a verified complete checkpoint,
apply saved results under the shared core's validation and obtain equivalent
authoritative state, exact version references and business effects. Do not rerun
LLM inference, OCR/extraction, external reads or effects to fill missing history.
Rebuild disposable search/index projections from retained authoritative content.
Unknown change schemas, missing dependencies and corrupt payloads fail truthfully
without partially publishing a successful reconstruction. Missing explicitly linked
files stay unresolved; never fabricate their bytes or reinterpret a changed original.
Reconstruction must not activate triggers, resume pending actions, confer grants or
execute historical tool calls. A separate ordinary execution path owns such work.

F05. Commit authoritative changes, causal/actor metadata and the complete receipt
atomically. Prepare and flush immutable included bytes before committing references.
Retain the existing lock, transaction and stale-write guarantees. A retry of the
same operation and payload has one effect and returns its original result; reuse
with different content fails. Interruption leaves a complete committed change or no
published change. Reconstruction/apply must preserve these guarantees. Do not create
an independent replication ledger alongside the proposed workflow event outbox;
E19 should reference/reuse this commit foundation when workflows are implemented.

F06. Persist decisions as evidence with their exact inputs, output, actual actor,
model/transformation identity, and authorizing rule/policy version when applicable.
Distinguish human acceptance, direct programmatic action and AI action under a rule.
Never label an automated decision as a user acceptance. Keep original disagreements,
request context, occurrence/effect references and superseded results inspectable;
record a concise decision explanation without requiring hidden model reasoning.
Reconstruction adopts the saved outcome rather than asking the model again.

The intended future conflict policy prefers automatic semantic resolution, with
user involvement when evidence or validation cannot support an outcome. Preserve
the information needed for that policy now. This requirement neither implements a
resolver nor widens current business acceptance or effect authority. Existing
identity/invariant checks stay enforced; an LLM's confidence is not a substitute
for preserved evidence or a license to invent a new occurrence after refusal.

F07. Retain the dependency closure of required history in coherent snapshots and
portable exports, including historical assets, exact source versions and retained
outputs. Report unresolved external references. Device paths, credentials, local
access grants, locks, leases and worker claims are not portable authority. Durable
user presentation state may use a declared snapshot/checkpoint path rather than
journaling each keystroke or navigation event. Runtime/cache churn need not become
semantic Sources or advance business revisions. Imported/reconstructed history is
inert; existing portable-copy authorization boundaries remain.

F08. Apply the pre-1.0 policy in [[records/specs/distribution]]: change the current
schema/interfaces directly and recreate selected disposable fixtures. Do not add
legacy migration/backfill/compatibility work for unreleased formats. Preserve user
files, original assets and historical test evidence. Specify schema versions and
reject unsupported input without silent deletion. Mark each audited write path and
remaining gap in [[records/operations/implementation]]; claims follow evidence.

## Implementation order and local acceptance

Finish the current coherent table-update slice. Then inventory persistence paths,
implement the shared capture/apply foundation and close the gaps in existing
mutations before expanding durable workflow/automation storage. Integrate the
foundation into E0 and reuse it in E3/E19. This does not require implementing the
workflow engine, a remote backend or two communicating replicas first.

The schema-10 capture/reconstruction implementation and current path inventory are
in [[records/operations/persistence-coverage]]. FJ01-FJ06 pass for the inventoried
current families through core, packaged CLI, real native review/reopen, concurrent
writers, interruption, corruption, cancellation and bounded scaling checks.
Future action/workflow mutations inherit these gates. These are local current-format
checks, not sync or release completion. Follow focused verification in
[[records/specs/distribution]], reuse unchanged evidence, and choose representative
integration fixtures plus targeted checks for uncovered mutation families.

FJ01. Reconstruct a synthetic current-format workbook into fresh local storage from
its declared initial state/checkpoint and committed changes with the model and
external execution adapters unavailable. Compare canonical authoritative state,
original IDs/times, lineage, effects, messages, saved definitions and required
history. SQLite file bytes and rebuildable index row IDs need not match. Every
inventoried durable family must have coverage or an explicit unresolved gap.

FJ02. Retry a committed change, reject a changed payload under the same ID, and
inject interruption around publication. Demonstrate no duplicate effects or
partial authoritative state. Verify committed asset references have complete bytes.

FJ03. Preserve exact edit bases and derivation inputs through successive edits,
acceptance, withdrawal and Undo/redo. Reopening/reconstruction keeps stable IDs,
original values, actual actors and references. Local stale-writer refusal remains.
This is a local storage check, not a multi-replica merge test.

FJ04. Missing/corrupt payloads, wrong hashes, missing causal dependencies and unknown
change schemas cannot yield a false success. Reconstruction runs zero inference,
extraction, network effects or automation triggers, including for saved pending or
ambiguous execution outcomes. Retain truthful inspection/recovery information.

FJ05. Human and automated/programmatic decision fixtures retain distinct attribution,
exact evidence and policy/model identity where applicable. Replay does not relabel
them or change acceptance. Test existing effect invariants without introducing a
new resolver or claiming semantic event-identity qualification.

FJ06. Export/reopen preserves the new history and its included dependencies;
explicitly linked missing assets remain reported. No device grants or runnable
historical effects become enabled by a portable copy or reconstruction. Verify
portable presentation state through its declared checkpoint path.
