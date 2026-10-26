---
type: spec
meta-type: conclusion
id: 01m5rbxza39hbjgke18phvzhfd
created: 2026-10-25T01:48:47.299215+00:00
updated: 2026-10-26T22:54:59.150110+00:00
summary: Versioned SQLite records, separate content-addressed assets, event effects, deterministic calculations and coherent portable snapshots.
title: Workbook storage and domain model
status: reviewed
---
# Storage and domain model

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
S07. Lineage edges distinguish derives-from, supports, contradicts, supersedes.
Reject invalid/missing inputs and derivation cycles. Store tool/formula/model
version and relevant rounding/units. Nondeterministic outputs persist as facts
about a run; replay does not rerun an LLM or repeat external side effects.
S08. Business effects have domain/subject/occurrence/effect identities and a unique
idempotency key. Multiple evidence documents can support one effect. Identical
independent deliveries are distinct occurrences. Only accepted actual effects in
the requested scope/scenario change actual balances. Opening basis has an as-of
time and unknown is not zero. Corrections supersede; later returns add events.
S09. Tables have stable dataset/column/row IDs, typed JSON values and immutable row
versions. Text/decimal/boolean/date columns; preserve original text on import.
Use Decimal arithmetic with explicit precision/rounding for financial results.
Formula engine is a bounded expression evaluator, not eval: arithmetic, referenced
columns/cells, SUM/AVERAGE/MIN/MAX/COUNT and conditional operations. Detect cycles,
division by zero, missing fields and invalid units. No arbitrary code execution.

## Transactions and concurrency

S10. One shared Swift core enforces all mutations for app, local agent and CLI.
Use parameterized statements, foreign keys, transactional migrations, busy timeout
and a process-safe workbook write lock. SQLite serializes writes; every operation
has an idempotency token and optional expected revision. Reject stale revisions
rather than silently overwriting. UI refreshes from revision changes.
S11. Use rollback journal initially with FULL synchronous durability and serialized
mutations. SQLite's published WAL-reset advisory means system SQLite must not be
assumed patched for multi-connection WAL. Reconsider WAL only against a verified
fixed library/version and concurrency tests. Keep queries and transactions short.
S12. Migration is transactional with known schema versions; reject future formats
without modifying them. Opening arbitrary SQLite must not run untrusted triggers
through our mutations: validate application ID, schema version and schema contract.
For untrusted portable workbooks, validate and rebuild into canonical schema before
editing if schema differs. No extension loading or SQL authored by a file/model.
S13. Undo is a compensating version/operation with preserved evidence. Redo creates
another operation. Do not erase accepted history. Non-reversible network effects
are outside the first version; local source/view edits are reversible.

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
See C06–C11 in [[records/specs/conversation-context]]. Migration, retention and
recovery checks are required before this storage change ships.

## Current physical context storage

Database schema 3 includes message_fts, message_payloads, run_requests,
context_checkpoints, checkpoint_inputs and tool_calls. The package manifest version remains 1.
Canonical schema-1 and schema-2 packages migrate transactionally under the workbook write lock.
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
snapshots and portable archives. History indexes are rebuildable. Automatic
summarization, compaction scheduling and general pending-action recovery remain
separate unfinished work under [[records/specs/conversation-context]].

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
