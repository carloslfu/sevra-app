---
type: spec
id: 01m63pbtkqgpmeas26bahejmj0
created: 2026-10-29T11:22:45.751359+00:00
updated: 2026-11-01T08:40:00.000000+00:00
summary: 'Reviewed schema22 semantic outbox over captured history: atomic settled versions, inventory basis and dataset membership/schema events, bounded indexed delivery and no execution authority.'
title: Committed business-event delivery
status: implemented
---
# Committed business-event delivery

Status: reviewed E4 implementation contract. This is the durable semantic feed needed by [[records/specs/condition-transitions]], rather than a polling shortcut over the latest state. It adds no execution permission and does not complete condition dispatch or E4. See [[records/specs/native-app-engine]], [[records/specs/persistence-readiness]] and [[records/operations/implementation]].

## Meaning and atomicity

Keep the existing committed-change ledger as authority. Add a semantic outbox over committed business versions in the same SQLite transaction and captured row stream. Do not create another history ledger, infer business facts from run-status changes or use SQLite journal files as business history. Original business inputs and version lineage remain in immutable items and schema versions.

A batch corresponds to one complete committed change, with that exact ID, actor, recorded time and a contiguous local semantic position represented losslessly. Only commits with semantic entries get a batch. A commit may contain several independent business occurrences. Preserve those distinct entries. Multiple versions of one logical record within the same transaction expose only the final settled version because intermediate writes were not committed observations. Delivery ordinals are pagination order, not an invented temporal order within that atomic transaction. A condition consumer must finish the batch before evaluating its final state.

## Semantic families

- Settled record: a newly accepted business Record or a new settled correction/withdrawal of an earlier accepted/rejected version. Draft edits leave the last settled business interpretation intact. A rejected proposal with no settled predecessor creates no accepted business event. Retain exact previous/final settled item IDs, logical identity, domain kind, meaning, status and scenario. Explicitly preserve estimates/plans/commitments as their declared meaning; an accepted forecast cannot become an actual. Technical kinds are excluded using the existing shared classification.
- Inventory scope: a settled movement uses its exact subject as a scoped lookup key. Its exact immutable item IDs and retained effect rows remain the authority for applying quantities; kind/title alone cannot establish an inventory effect. Add an item-indexed effect lookup. Opening-basis changes retain exact before/after quantity, effective time and Source IDs. Future effective dates remain explicit; a later condition adapter must define time eligibility rather than assume ledger balance means physical stock now.
- Dataset membership: retain the first before and final after mapping of each dataset/row slot changed in the commit. A temporary delete/reinsert with identical final mapping produces no semantic event. Membership data is separate from row values and never resolved using today's head as a historical value. Preserve lossless ordinal strings and logical identities.
- Dataset schema: each final new immutable column version retains its exact prior/final version and Source IDs. Archival/schema changes are observable without treating disposable native projection churn as row business events.

Scope keys and record kinds are stored separately. Inventory subject, logical record and dataset lookups are indexed with batch position and ordinal. A movement's scope key is its subject, so a record-scope read finds a record by logical ID across scopes. No full committed-payload scan per poll. Reading current items cannot be used to fabricate past membership, state or event order.

## Storage and publication

Schema22 adds business_batches and business_events to the existing complete capture/apply family. A batch references its exact committed_changes row using a deferred foreign key. Events have stable IDs from batch/ordinal, composite batch/position integrity, exact item foreign keys when applicable, typed semantic family/scope metadata and retained normalized payload. No live capability or device path is stored here. Existing development files stay preserved and refuse unsupported versions; no migration/reset or compatibility adapter.

Publish after canonical operation writes and before the single captured commit is finalized. Choose the global committed ID and recorded time once and use them in both batch and envelope. The semantic publisher inspects the original captured rows; its own outbox writes cannot trigger recursive publication. A failure, cancellation or process death before commit rolls back business mutation, receipt, semantic rows and history together. A committed retry recovers the same receipt/batch/events. Reconstruction applies retained rows inertly and never re-emits events, interprets evidence, acquires a model or restores authority.

## Read delivery and future consumption

Expose bounded read-only batch listing and per-batch event pages through shared core and CLI. Batches can be read globally or by exact scope using indexed keyset lookup. Cursor IDs must belong to this workbook's retained feed; unknown/foreign cursors refuse. Return workbook identity, exact batch IDs, lossless positions, coverage/tail information, next cursor and explicit hasMore. Page event ordinals within one exact batch and flag its completion. Bound rows, encoded bytes and query time; cancellation never returns an apparently complete partial page. No hidden consumer acknowledgement or activation follows from a read.

A later condition consumer will persist its baseline, exact cursor, working state and occurrence decisions through the same captured path, advancing only after retaining every required event. Query-specific state must reconstruct exact versions or explicitly report an observed-only coverage gap. Queue pressure stops cursor progress with a visible backlog rather than erasing business occurrences. Preserve one active run and event successors. Carry causal ancestry across automatic outputs and later review acceptance; qualify persisted self-loop/cascade/fan-out bounds before automatic event dispatch. Current per-Mac grants and live fences remain mandatory. Those consumers and native/conversational authoring remain required, not implied by this feed.

## Three review passes

1. Business semantics: drafts versus settled versions, accepted estimates versus actuals, correction/withdrawal, independent occurrences versus multiple uncommitted edits, explicit effective time and atomic batch observations.
2. Recovery and integrity: exact commit/actor/time, first-before/final-after maps, source-bound immutable versions, deferred references, stable retry identity, rollback/death, complete capture/reconstruction and copied history without authority.
3. Scale and abuse: scope/position indexes, keyset and within-batch paging, sparse lookup, bounded decoding/query/cancellation, no operational/self-trigger churn, no today's-head historical shortcut and no skipped unretained events. Feed correctness alone does not qualify condition execution or loop prevention.

## Acceptance

Require real workbook tests for accepted versions, meaning preservation, ignored drafts/technical churn, corrections/rejections, distinct occurrences and atomic batches, membership and schema edits, future dates retained, indexed scope/cursors/pages, forced rollback/cancellation, concurrent publishers, inert reconstruction and corrupted/missing outbox rows. Run the full shared core suite for the new canonical family, nearby automation/controller/lifecycle checks, installed native CLI jobs, native package/resource/refusal/signature checks and strict changed-Swift lint. Add actual process-death publication evidence, or identify any exact reused publication-boundary proof and its limits. Keep failed iterations. Require zero-warning db.md validation, links and diff checks, commit/push and exact CI. No model, hardware, visible OS or release claim from these checks.

## Shared core and CLI delivery contract

`Workbook.businessBatches(after:limit:scopeKind:scopeKey:cancellation:)` reads 1 to 50 batches; `Workbook.businessBatch(_:afterOrdinal:limit:cancellation:)` reads 1 to 100 entries from one exact batch. Both use a three-second cancellation-aware read transaction and an 8 MiB encoded result bound. An oversized entry refuses visibly; no cursor or acknowledgement is persisted by a read. The caller must retain the whole atomic batch before evaluating conditions or advancing its durable consumer state. A batch cursor must be an existing semantic batch ID in this workbook, not merely any Source or operation ID. An entry cursor must exist within the selected batch.

~~~sh
sevra business-batches WORKBOOK [AFTER_BATCH_ID|-] [LIMIT] [SCOPE_KIND SCOPE_KEY]
sevra business-batch WORKBOOK BATCH_ID [AFTER_ORDINAL|-] [LIMIT]
~~~

Use `-` for an omitted cursor when supplying later positional arguments. Scope kind and key must be supplied together. Scope filtering selects matching batches; their event pages still return every entry in that atomic commit. The global tail and lossless position strings describe the read snapshot. While hasMore is true, nextCursor is the last returned batch. When hasMore is false, nextCursor is the global snapshot tail, including an empty scoped page. This permits an exact unchanged scope consumer to cover unrelated batches without scanning their payloads. Changing subscriptions requires establishing their own baseline/coverage. Readers do not enable execution.

Exact scope meanings are: record plus logical identity, inventory plus subject, or dataset plus dataset identity for membership/schema changes. Row-value versions are record-scoped. A dataset-only subscription does not claim all row-value changes; a later dataset condition adapter must consume both its membership/schema history and the relevant immutable row versions, or consume the global feed while maintaining that state. It must not resolve past membership from today's mapping. A movement scope is a lookup hint; consumers must read its exact retained effects before applying an inventory quantity. A generic record named movement cannot create an effect.

The global batch position and scoped position/ordinal queries are indexed keyset reads. The exact effects item index supports later inventory adapters. Reconstruction replays retained outbox rows alongside all other canonical families; it does not rerun the publisher or interpret a condition. Ordinary verify now checks batch actor/time/position and every event identity, ordinal, metadata and normalized payload against the original committed inputs, streaming each committed envelope once. It detects missing or modified outbox data independently of checking the saved envelope hash. The current committed ledger remains authority; this is its captured semantic projection.

## Implemented feed qualification, October 29

Schema22 now publishes business_batches and business_events as a semantic projection inside the existing committed transaction and row capture. The deferred batch reference binds the exact global commit, actor and recorded time; positions are contiguous and lossless strings at the public boundary. Stable per-batch ordinals preserve independent settled records while collapsing uncommitted revisions of one logical identity. Drafts, unaccepted rejections, Sources alone and technical activity do not create business batches. Meaning and scenario remain explicit. Exact inventory basis and dataset membership/schema images remain available after later changes.

Core/CLI expose bounded inert global/exact-scope batch pages and per-batch entry pages. Global and sparse scope queries use indexed keyset lookup. Dataset scope means membership/schema, with row-value versions separately record-scoped. Movement scope is a hint requiring exact effects, not an asserted inventory change. There is no consumer acknowledgement or activation. Reads use a cancellation-aware three-second query budget, a 100 ms SQLite busy interval, explicit row/output bounds and no hidden partial completion. Ordinary integrity checks stream/decode committed envelopes once and compare semantic metadata/payloads against retained inputs. Reconstruction applies captured rows without publication or authority restoration.

Final V7 full core passes 386 groups with zero failures, including14 new business-event groups. The final V8 build/14 focused groups and 76 independent installed native CLI calls pass; V8 only corrects one test label from covering index to scope index, with production sources unchanged. The installed probe includes six actual concurrent CLI writers, two actual SIGKILL boundaries before/after commit, receipt/version/feed atomicity, read-only pagination over a 103-row imported dataset, exact integer positions beyond 2^53, semantic corruption refusal, retry/reconstruction and byte-preserved unsupported-format refusal. The large-integer seed deliberately alters a disposable sequence; integrity correctly rejects that gap, so it is not presented as valid historical continuity.

Nearby V4 native owner 18 groups, synthetic ProductAI lifecycle and 44 installed automation calls pass. Those use the same canonical publication code; the later V7 delta only bounds business-feed read waits and adds its lock-cancellation test. Final native app/CLI build, build-tree-denied resource reads with 1,888 Metal kernels for each executable, 10 missing-resource refusals, altered-resource refusal, missing-model guidance/workbook preservation, ad-hoc signature and strict 12-file Swift lint pass. No actual model inference or new performance/hardware qualification. New delivery tests join scripts/check.sh and both packaged hosted CI paths. The new source requires its own dispatched CI.

Retained iterations include the V1 throwing-expression compile error, V3 worker trailing-closure lint finding, and V5 test's incorrect manifest storageVersion assumption. The corrected format check reads SQLite user_version. Earlier successful runs and source snapshots remain retained. All public assets and existing workbook files remain untouched; unsupported development versions refuse without migration/reset.

Evidence: [business-event delivery receipt](../../../integration/evidence/2026-10-29-business-event-delivery.json.gz), 102021 bytes, SHA-256 ace21c59cf049e5770858e2f1742793f33dd48688ad2343abe6dba9701bfe61d. All 140 prior artifacts remain byte-identical.

This completes the semantic feed slice, not E4 or the app. Persistent condition baselines/cursors/working state, exact event-time evaluation, atomic occurrences/outbox, causal ancestry and restart-safe self-loop/cascade/fan-out/backpressure bounds remain next. Native/conversation trigger authoring, complete background/closed-window/resource lifecycle, E5/E6, full E3 recovery/abuse/richer-graph journeys, contextual/Excel continuity, complete E0/E1/E2 journeys and release gates remain open. A fresh native app inventory still reports the Mac locked; latest visible controls/voice/accessibility/appearance/media remain unverified. Goal and release are unfinished.

## Historical inventory adapter

[[records/specs/inventory-event-state]] now consumes exact retained batch cutoffs for bounded inventory reconciliation, preserving earlier settled versions after later corrections/withdrawals and keeping effective dates explicit. It passes 11 focused groups, the real 10,000/10,001-effect boundary, 14 feed regressions and 37 installed native CLI calls, with fresh native resource/refusal/signature proof. A scale timeout and its measured query correction are preserved. Feed storage/schema22 is unchanged. This adapter adds no persistent consumer, condition occurrence, live clock policy or execution authority.

## Integer ordering and durable inventory consumption

The schema 23 checkpoint in [[records/specs/inventory-condition-consumers]] exposes a feed-read defect that the original scoped feed tests missed: ORDER BY position could resolve to the displayed CAST(position AS TEXT) alias. Current global pages/tail and the consumer explicitly order by b.position. The new 23-batch pagination/tail regression and 101 distinct crossings pass. Lossless string positions remain the public representation, with numeric ordering by stored integers.

Final 416 full core and 76 installed feed calls, including six writers/two SIGKILL boundaries, pass on the final native CLI. Incremental inventory baseline/clock/cursor/observation/candidate state is now captured and reconstructible. Dataset-only scope limitations remain unchanged. Causality-aware condition dispatch, dataset-query adapters and native authoring remain open. Earlier artifacts are immutable and do not retroactively prove the newly tested ordering boundary.
