---
type: spec
meta-type: conclusion
id: 01m5rbxza39hbjgke18phvzhfd
created: 2026-10-25T01:48:47.299215+00:00
updated: 2026-10-28T18:44:20.330692+00:00
summary: Versioned SQLite records, separate content-addressed assets, event effects, deterministic calculations and coherent portable snapshots.
title: Workbook storage and domain model
status: reviewed
---
# Storage and domain model

## Persistence readiness requirement

The adopted [[records/specs/persistence-readiness]] contract F01-F08 and FJ01-FJ06
requires complete saved changes, causal/version identity, deterministic local
reconstruction, atomic/idempotent application and truthful decision provenance.
This extends S05-S17. Schema 10 implements complete atomic typed changes and inert
local reconstruction. The current write-path inventory, scoped synthetic proof
and remaining qualification are in [[records/operations/persistence-coverage]].
Cloud sync, replica coordination and a new semantic resolver remain out of scope.

## Managed dataset requirement

Adopt [[records/specs/managed-datasets]] M01-M10 and MJ01-MJ08. Reserved system
tables retain immutable Sources/Records, lineage, definitions and receipts;
structured datasets use registered native current-state tables. These are
rebuildable projections over authoritative versions/definitions retained by the
existing committed-change history. One managed transaction owns each edit.
Logical schema changes, trusted schema materialization, indexes and dataset
capture/apply/validation are one storage contract. No second ledger or raw-model DDL.

Schema 11 now uses managed native current-state tables over retained immutable JSON
row versions and versioned definitions. Its capture/materialization/repair foundation
has scoped evidence in [[records/operations/persistence-coverage]]. Full schema
lifecycle and managed query/index qualification remain E0-D prerequisites before
dependent E2/E3 storage.
Flexible sheet/cell data and contextual reference/analysis roles remain distinct.
Existing local replay is not concurrent replication qualification.

## Package and ownership

S01. A workbook is `Name.sevra/{manifest.json,workbook.sqlite,assets/,staging/}`.
The manifest identifies package format/version and UUID; SQLite user_version
identifies the independent database schema. SQLite owns structured
state, extracted text, provenance, conversations and views. Every file asset is
an ordinary file under assets, never a BLOB. Caches are disposable and excluded
from authority. Credentials/model weights are device state outside the package.
S02. Asset bytes are immutable and SHA-256 addressed with directory fanout. Each
import has its own source identity even when bytes deduplicate. Store original
filename, media type, byte count, hash, origin, capture time, inclusion mode,
bookmark and extraction status. User-visible identity is not the hash.
S03. Include by default, including Downloads and large video. Stream copy/hash
with bounded memory, cancellation and disk-space checking. Flush bytes, atomically
rename staging to assets, then commit the catalog reference. Crash before catalog
commit may leave an orphan, never a committed reference to half a file. Never
silently turn a failed copy into a link. Do not delete originals.
S04. Explicit external links use a macOS bookmark and observed hash/version.
Missing or changed targets remain visible. Reading a changed file never silently
replaces the version behind an answer. Relinking validates the expected hash or
creates an explicitly new capture. Include converts by copying the required bytes.


Preview verification snapshots asset metadata under the workbook lock, then
resolves and streams the original outside that lock. Cancellation propagates
between bounded hash chunks and is checked again before publishing a URL or
committing a relink. Full hashes remain mandatory for external reads. Included
files open without hashing the complete asset unless verification is requested.
This does not promise interruption of an operating-system file read that is
already blocked, or instant decode/rendering of every supported file format.

External applications receive copies, never included evidence paths. Copy and
hash in one pass with 1 MiB chunks, outside the workbook lock. Match the recorded
SHA-256 and byte count before atomically publishing with no replacement. Check
free space and reject workbook destinations, including directory aliases; keep
existing files and remove partial staging on cancellation or error. A completed
copy is user-owned and remains after Stop or window closure. Process death may
leave an unreferenced hidden staging file in the selected directory, never a
partly published destination. Reimport is an explicit new source operation.
## Durable entities

S05. Sources and Records are categories of immutable item versions. Each version
has stable version ID, logical ID, version number, category, domain kind, title,
meaning, status, effective time, recorded time, scenario ID, structured JSON,
search text, optional asset and supersedes link. Current heads are indexed.
Sources include human claims/decisions/rules, documents and observations. Derived
Records reference exact input versions and transformation identity/parameters.
S06. Meaning and acceptance are independent. Domain meanings include actual,
estimate, plan, commitment, assumption and rule. Accepted forecasts remain
estimates. Unknowns are null/explicit unknown, never silently zero. Status is
draft/accepted/rejected/superseded. An edit creates evidence and a new version,
not a destructive rewrite. Preserve previous issued results.
A document edit commits the submitted text Source, derived document Record,
lineage, head and operation receipt together. Repeating the same operation token
and arguments returns the same version. A stale base refuses without leaving an
orphan Source. An explicit separate draft creates a new logical document and
preserves the competing head, meaning, scenario and metadata. Submission lineage
does not itself claim human authorship when a CLI harness supplied the text.
S07. Lineage edges distinguish derives-from, supports, contradicts, supersedes.
Reject invalid/missing inputs and derivation cycles. Store tool/formula/model
version and relevant rounding/units. Nondeterministic outputs persist as facts
about a run; replay does not rerun an LLM or repeat external side effects.
S08. Business effects have domain/subject/occurrence/effect identities and a unique
idempotency key. Multiple evidence documents can support one effect. Identical
independent deliveries are distinct occurrences. Only accepted actual effects in
the requested scope/scenario change actual balances. Opening basis has an as-of
time and unknown is not zero. Corrections supersede; later returns add events.
S09. Tables have stable dataset/column/row IDs, exact logical values and immutable row
versions. The managed physical layout and type rules are in
[[records/specs/managed-datasets]]. Text/decimal/boolean/date columns; preserve
original text on import.
Use Decimal arithmetic with explicit precision/rounding for financial results.
Formula engine is a bounded expression evaluator, not eval: arithmetic, referenced
columns/cells, SUM/AVERAGE/MIN/MAX/COUNT and conditional operations. Detect cycles,
division by zero, missing fields and invalid units. No arbitrary code execution.

## Contextual conversion and continuity

The adopted [[records/specs/contextual-import]] requires separate capture, role,
inspection/feature report and requested conversion/update state. Checkpoint
63cd642 implements durable capture/role selection, reference/analysis use and
explicit saved-values conversion. Target/mapping updates and Excel continuity
remain open; the latest evidence is in [[records/operations/implementation]].
Keep source coordinates and original formulas separate from native table headings,
stable row identities, formula/dependency bindings and cached-value state. A saved
formula string is evidence, not a recalculating native expression. Existing bounded
column formulas and single-dataset A1 reads are not Excel continuity qualification.
Preserve each original file outside SQLite under assets and derive native state
with exact lineage, retry identity and revision guards. Reference/analysis-only
intake must not silently create working tables; update intent needs an explicit
target/mapping. The spec defines per-cell/cross-sheet work and support gates.

## Transactions and concurrency

S10. One shared Swift core enforces all mutations for app, local agent and CLI.
Use parameterized statements, foreign keys, transactional schema changes, busy timeout
and a process-safe workbook write lock. SQLite serializes writes; every operation
has an idempotency token and optional expected revision. Reject stale revisions
rather than silently overwriting. UI refreshes from revision changes.
S11. Use rollback journal initially with FULL synchronous durability and serialized
mutations. SQLite's published WAL-reset advisory means system SQLite must not be
assumed patched for multi-connection WAL. Reconsider WAL only against a verified
fixed library/version and concurrency tests. Keep queries and transactions short.
S12. Follow the pre-1.0 compatibility policy in [[records/specs/distribution]].
Before the first notarized production-ready 1.0 release, update the canonical
schema and recreate selected disposable development fixtures instead of requiring
migrations from earlier development schemas. Keep schema versions for validation;
reject unsupported formats without modifying or automatically deleting them.
After that milestone, upgrades from supported production baselines must be
transactional. Opening arbitrary SQLite must not run untrusted triggers: validate
application ID, schema version and the permitted schema contract. No extension
loading or SQL authored by a file/model.
S13. Undo is a compensating version/operation with preserved evidence. Redo creates
another operation. Do not erase accepted history. Non-reversible network effects
are outside the first version; local source/view edits are reversible.

## Versioned layouts

Home and other spaces use the same stable component IDs, exact base-version guard,
atomic saved history and committed-change capture. The declared initial
Home/version 1 projects the six default host sections; a deliberately emptied
later layout is empty after reopening. First edit retains the initial layout as
version 1. Every save/restore creates one retained version and checks the current
layout against its retained version before publishing. Verify checks contiguous
history and exact current/latest agreement. Restore is a new edit, not deletion.

Semantic operations rename, insert, remove, move, title, text and replace preserve
unrelated components. Position is explicit first/last or before a stable sibling ID;
unknown operations, unrelated defined fields and invalid compositions refuse atomically.
Snapshots retain their mode, saved bindings and values. System host sections are
live host views and cannot be frozen as if they were bound business results.
The native editor keeps its opened base version fixed across background refresh;
a stale refusal preserves unsaved input for review. Layout history/reconstruction
never executes tools or changes business acceptance. See
[[records/specs/native-app-engine]] for engine scope and remaining E2-E6 gates.

## Portable copies and recovery

S14. Export uses SQLite backup API to a staging snapshot and copies exactly the
immutable assets referenced by that snapshot. Exclude transient journals, caches,
bookmarks/absolute local paths and credentials. Record unresolved dependencies.
Never copy a changing database file directly. No implicit garbage collection of
historical assets. Check cancellation and free space; final archive publishes
atomically after integrity checks.
S15. ZIP64-compatible `.sevraz` uses lossless compression for text/database and
stores already compressed media. Validate archive entry count, expanded byte
budget and paths; reject symlinks, traversal, absolute paths, duplicate/case-fold
collisions and nested archives posing as workbook structure. Extract into staging,
verify database and all included asset hashes, then rename into the destination.
No overwrite by default. Failure leaves the original untouched.
S16. Recovery checks SQLite integrity/foreign keys, missing bytes, orphan staging,
invalid lineage and stale indexes. Rebuild derived indexes from authoritative rows.
Report external dependencies accurately. No silent destructive repair. A workbook
on a network drive/sync folder is not supported for concurrent multi-host editing.

## Conversation continuity

S17. Preserve original conversation and complete executed tool receipts. Store
versioned derived context checkpoints with exact covered history, hashes, model
and transform identity, evidence references and workbook snapshot revision.
Publish atomically; preserve the prior checkpoint on failure. Checkpoints travel
with the workbook, while their indexes remain rebuildable. Reconstruct acceptance,
meaning and completed operations from authoritative state, never from a summary.
See C06–C11 in [[records/specs/conversation-context]]. Current-format retention,
recovery and portable reopen checks remain required. Earlier-development migration
tests are not required under [[records/specs/distribution]]; supported-production
upgrade checks start with the production 1.0 baseline.

## Current physical context storage

The following paragraphs retain historical implementation/verification facts.
They do not require preserving development schemas under the newer pre-1.0
compatibility policy in [[records/specs/distribution]].

Database schema 5 retains message_fts, message_payloads, run_requests,
context_checkpoints, checkpoint_inputs, tool_calls and the current-draft review
index/generation. It adds the explicit reference snapshots described below.
The package manifest version remains 1. Canonical schema-1 through schema-4
packages migrate transactionally under the workbook write lock.
Validate the exact old schema before enabling its triggers, then build the history
index, advance the database version/revision and record the migration in one
transaction. Unknown/future schemas are refused. Older app builds cannot open the
migrated database; keep app and CLI versions together. No existing installed app
or user workbook was upgraded during development qualification.

Original message text remains unchanged. Optional message payloads retain native
terminal-call arguments and response text; tool receipts retain their run/call IDs.
Older history has no invented receipt metadata. Current runs link to their exact
request message. Message text and tool-message bodies are indexed; attached terminal payloads are
retrieved by exact message ID. History slices contain complete messages and payloads, a snapshot
revision and SHA-256 over canonical JSON including conversation/range identity.
Use bounded keyset paging and an independent FTS index; no recent-message cap limits
retrieval. Message bodies and optional payloads each have a 128,000-byte ceiling.

Checkpoints cover contiguous ranges ending at complete turns or recorded tool results, chain to their previous
checkpoint, and record exact input versions, transformation/model/template identity
and source revision. Expected revision, recomputed history hash, exact-ID checks,
foreign keys and one transaction protect publication. Idempotent retry returns the
same checkpoint. Loading checks the original-history hash; integrity verification
also checks the chain. Summary text cannot mutate Sources, Records or acceptance.
Current input heads, status and meaning are projected afresh when inspected.
These are operational artifacts, not a third category of business information.

Original messages, payloads, run links and checkpoints travel in coherent SQLite
snapshots and portable archives. History indexes are rebuildable. Summarization
and compaction scheduling are implemented for dedicated evaluation probes but
remain disabled in both packaged product paths pending qualification. General
pending-action recovery remains unfinished under [[records/specs/conversation-context]].

Tool calls are journaled before execution with the exact arguments, response text,
run/call identity and the deterministic operation token computed by the host.
A repeated call identity is refused, including a prepared call whose process ended.
Completion stores the full structured JSON result and hash together with its
conversation message in one transaction. Results larger than 16,000 encoded bytes
receive valid JSON projections with explicit omitted fields and receipt IDs; no
character-prefix truncation is used. The original result remains in SQLite as
structured operational data. File assets remain outside SQLite inside the package.
Tool-result reads navigate exact keys/indexes, page containers, or return labeled
Unicode-scalar text segments; raw JSON segments support lossless unusual-key recovery.
Message arguments and assistant text are checked before execution so the bounded
receipt fits its message ceiling. Integrity checks bind the call, result and message.

A prepared call is an uncertain outcome, never a claim of no changes. Inspection
shows a matching committed operation when present and never replays a call.
Multi-operation intake can be partially complete without a single operation token;
absence of that token does not prove absence of effects. Failed calls retain their
receipts and explain this distinction. Automatic recovery/resume and a user-facing
resolution flow are still pending. Exact result retrieval currently loads the
structured result before projecting a bounded response; streaming huge structured
receipts and large-result memory qualification remain work, not bounded-memory proof.

Conversation FTS uses append-safe descending keyset cursors bound to query, scope
and the optional current-request boundary. Appending journal/messages does not
invalidate older pages. Agent history search excludes its current request and
later messages. It searches only the selected conversation; tangents retain their
existing explicit parent excerpt, without a new cross-conversation search privilege.

The history FTS indexes original messages and bounded receipt projections, not every
field of an oversized journal result. Full results remain addressable by receipt ID
and exact path. Full-result content indexing is still a retrieval qualification item.
## Lightweight recent-item catalog
Home reads a bounded catalog of current item metadata without selecting document
bodies or structured payloads. Its entries retain exact version IDs, category,
kind, title, meaning, acceptance and asset identity. Opening an entry reads its
original version explicitly. Exclude internal requests, technical annotations and
dataset rows before applying the recent-item limit, so internal activity cannot
hide all evidence.
Use a distinct summary type rather than representing omitted content as a complete
empty Item. Full item and lineage APIs retain their existing evidence semantics.


## Conversation presentation persistence

S16a. Use versioned JSON in meta under conversation-view:<conversation-id> for the
unsent composer, saved draft alternatives and message/fraction reading position.
Validate the conversation and require any anchor message to belong to it. Read the
encoded byte count before loading the envelope, then validate decoded bounds.
A small transaction under the workbook process lock compares the expected draft,
merges current alternatives and atomically writes the state. These presentation
writes do not increment the business revision or journal each keystroke, and do not
enter FTS, lineage, Sources, Records, conversation history or model context. This
is an explicit exception to S10's business-operation journaling requirement.

The UI coordinator serializes background writes, waits for later edits before a
flush completes, and awaits durability at thread/close/quit boundaries. Process
lock acquisition has a three-second deadline; SQLite busy waits use 100 ms within
this presentation operation. The OS may still delay a filesystem write or fsync.
A failed save preserves the draft in memory and refuses destructive navigation.
Conflicting text requires explicit preservation of both versions. The package's
coherent portable snapshot retains this state; it is not a privacy-redacted export.

## Inline references and relationship bindings

S18. Adopt [[records/specs/references-and-relationships]] L01-L08. Store durable,
version-aware bindings and Source annotations in SQLite; maintain rebuildable
incoming/outgoing indexes separately from derivation lineage. Mentions, possible
associations, business claims and derivations have distinct semantics. Substantive
inferred relations are derived Records with evidence/status, not a third category.
Preserve original bytes, pinned citations, unresolved targets, transactions, undo,
migration and portable identity. Implementation and LJ01-LJ10 remain pending.

## Space navigation presentation state
SpaceNavigationState version 1 lives in SQLite meta under space-navigation.
It contains up to 64 pinned space IDs and the eight most recent distinct visits.
Home always has its own entry and does not consume a pin/recent slot. IDs must
identify existing spaces when edited. Apply each bounded edit batch atomically
under the existing three-second presentation writer budget. Read the latest saved
state before applying intentions, so visits and unrelated pin changes from another
window merge instead of replacing a stale whole document.

This is portable presentation state, not business evidence. It creates no item,
message, operation receipt, business revision or space version. It does not alter
live/snapshot bindings. Keep it outside evidence search and model history. The
existing meta table carries it without a schema migration.

Background window snapshots read this state coherently with the catalog and
business revision. Polling also compares navigation state, so another window's
preference-only change is not missed. The UI serializes saves and coalesces queued
visits to the last eight. It displays committed preferences; errors keep the last
saved state and report failure. Snapshot callbacks use a generation check to
avoid overwriting newer local activity. Normal close, quit, workbook switch and
portable export await queued saves. A preference failure does not block closing
or discard a user draft; conversation/document drafts retain their separate
save-and-conflict rules.

## Current-draft index and paging
Schema 4 adds the partial ordered items_review_order index over created/id for
draft items excluding row and request kinds. Review reads join heads to retain
only current versions, ordered oldest first with ID as a deterministic tie-break.
The same coherent read transaction obtains a dedicated review-revision generation.
Head insert/update triggers advance it when an eligible draft enters, changes or
leaves the current-head set. Ordinary chat and execution receipts do not advance
that generation and cannot reset a user's review page merely by being written.

A bounded cursor contains format version, normalized workbook-path hash, review
generation and created/id anchor. Reject foreign or malformed cursors; a changed
draft generation asks the caller to refresh. The API returns one to one hundred
metadata items, the agent/native list uses twenty, and Home uses five. Cancellation
and a three-second SQLite read budget cover the query; original bodies remain in
separate exact-version reads. Native paging discards cancelled/late results from
another workbook and retains at most one hundred backward cursor entries.

The exact-query plan uses the partial index and head lookup without a temporary
sort. A synthetic in-memory query-only check with 100,000 historical drafts,
100,000 accepted heads and fifty current drafts returned correct pages with warm
p95 8.91 ms over thirty samples. It omits body/chunk ingestion and is not evidence
of whole-app, disk, import or FTS performance. Existing draft history still costs
index traversal; this is not an O(current-drafts) complexity claim.

Withdrawal appends a decision Source. A first draft becomes a rejected current
version, with its proposed effects preserved but unapplied. For a movement
correction, the latest preceding settled version determines accepted state. If it
was accepted, copy that accepted content/effect into the new head and link both the
declined draft and prior acceptance; withdrawing the correction must not erase the
earlier accepted effect. Undo of this withdrawal restores the declined draft while
retaining accepted inventory. Undo of an accepted correction similarly restores
the earlier accepted effect, or withdraws the occurrence when no accepted effect
preceded it. The lineage transformation distinguishes withdrawal from acceptance.
Retrying the same withdrawal token returns the same result; obsolete and accepted
targets refuse withdrawal. Movement revisions preserve subject and occurrence.
Original inputs and versions remain immutable; this repair needs no schema change.
See [[records/specs/product]] and the
[review queue receipt](../../../integration/evidence/2026-10-27-review-queue.json).

## Citation version snapshots, October 27
A citation is an exact immutable item-version ID. citationVersions reads up to 256
references, deduplicated, in one cancellation-aware read transaction. Each entry
contains cited/current ID, logical ID, title, version, status and meaning, plus an
isCurrentVersion flag. The snapshot includes the workbook revision. Logical IDs
are refused here; citations cannot float to a newer head. Metadata-only joins
avoid decoding document bodies and structured payloads. The method never changes
items, heads, accepted effects or action authority. The agent stores its observed
snapshot alongside the final message and presents historical/current links.
See [[records/specs/intelligence]] and [citation version receipt](../../../integration/evidence/2026-10-27-citation-current-version.json).

## Composed document provenance, October 27

[[records/specs/document-composition]] adds a core document-construction API
without a schema migration. Record data stores versioned documentComposition
metadata: originating run/conversation and each immutable read reference, exact
copied text, Source/Record version, locator, receipt hash and output position.
Source assets stay outside SQLite as before. New prose and copied text form one
bounded saved body; copied input versions join its ordinary lineage.

All copies resolve inside the draft write transaction. Wrong scope, stale
revision, changed hash, malformed parts, excessive output and cancellation
refuse the whole mutation. Identical successful retries return the original
item; new writes require an active request-linked run. Verification checks
declared copies against original receipts and saved text. Acceptance, withdrawal,
Undo and portable export/reopen preserve copied bytes and estimate meaning.
Eight composition test groups pass within the 90-check core run. Reserved
metadata validation applies only to document Records; matching business field
names on Sources, analyses and table rows retain their ordinary meaning. Agent/CLI
and native provenance interfaces are still pending.

## Canonical reference storage, schema 5

`reference_sets` stores immutable per-origin annotation versions, exact body
hashes, parser/coverage, prior/inherited snapshot IDs and the choice Source.
`reference_heads` selects the current annotation state for an exact item version.
`reference_bindings` stores bounded scalar label locators, preserved lookup text,
reference identity, live logical or pinned exact targets, workbook identity and
resolution. Target and reference-ID indexes remain separate from derivation
lineage. These tables travel with coherent backups and portable archives.

The database retains the manifest identity in `meta.workbook-id`. Opening checks
that the two identities agree. Migrations retain original items, messages, assets
and unresolved text; they do not guess bindings from titles. Keep the app and CLI
matched because older builds correctly refuse the newer database schema.

Explicit selections publish with authored text in the same transaction. Later
Source annotation changes retain their own prior snapshot and new Source without
rewriting original inputs. Record binding changes require a new item version.
Unchanged text can inherit exact bindings through review and Undo; changed prose
without supplied selections retains its earlier binding history and receives a
bounded new-version parse under schema 6. Migrated untouched bodies remain unindexed. Manual selections are partial coverage.
See [[records/specs/references-and-relationships]] for implemented API bounds,
remaining native interaction/traversal work and acceptance cases.

## Derived reference projection, schema 6

`reference_index` projects the current annotation of each exact origin with its
current-origin flag and saved target metadata. Covering incoming indexes support
current and historical ID-keyset discovery. `reference_coverage` retains the parser,
body hash, state and detail, including an empty completed parse. Canonical binding
snapshots stay authoritative. Rebuild copies them without reparsing or rebinding;
verification compares both directions. New eligible bodies and their bounded
parses commit atomically; original asset bytes remain outside SQLite and unchanged.
Schema 1-5 migration preserves originals and saved choices and does not parse old
bodies automatically. See [[records/specs/references-and-relationships]] for parser
limits, catch-up, metadata-only queries and extraction bounds and remaining product gates.

## Retained file references, schema 7

Original file assets remain outside SQLite inside the workbook. SQLite retains
bounded extraction text as annotation input, not the binary asset. The canonical
`file_reference_inputs` table binds exact regions/locators to origin version,
asset hash and extractor identity. `file_reference_sets` stores versioned binding
arrays and annotation Sources; `file_reference_heads` selects current annotation
state. The separate indexed `file_reference_index` projects saved bindings only.
`extraction_attempts` prevents a superseded worker from replacing a newer result.

File inputs/choices survive FTS replacement, Source version changes with the same
asset, Undo and portable export/reopen. New input remains separate from earlier
snapshots; identical input retains its latest explicit choices. Search publication,
input capture, Sources, bindings, heads and receipt commit atomically. Failure or
cancellation preserves the prior committed input and index. Integrity checks
validate hashes/locators, choice Sources, historical inheritance and projections;
rebuild repairs projection rows without interpreting text or resolving names.
Migration from canonical schemas 1-6 preserves old choices and runs no extraction.
The current schema is 7; keep app and CLI versions matched. See
[[records/specs/references-and-relationships]] for bounds and coverage limits.


## Agent projection of saved links, October 28

Schema 7 is unchanged. A business item read returns the first canonical outgoing
reference page from the same database read transaction as its original content
and current-version metadata. This projection neither rewrites evidence nor adds
citation eligibility for destinations. Owner reference/search APIs retain their
inspection scope; the model uses business-only reference/search/lineage projections
and a separate immutable current-request Source ceiling. Cursor identities include
that scope. A later request head can be outside read scope without being absent;
its metadata remains undisclosed. See [[records/specs/references-and-relationships]]
and [[records/specs/intelligence]].


## Recent catalog technical scope, October 28

Home's metadata-only recentItemSummaries query excludes row, request and annotation
kinds before ORDER/LIMIT. Technical link parsing/choice Sources remain immutable
and inspectable through explicit owner APIs, but cannot crowd normal business
work out of the first page. No schema, item, lineage or asset rewrite is involved.
