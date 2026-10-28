---
type: spec
id: 01m609st2pz8zhg7bcpec874g1
created: 2026-10-28T03:45:29.174789+00:00
updated: 2026-10-28T03:57:10.492714+00:00
summary: Reviewed exact-copy design, immutable read provenance, atomic composition and staged qualification.
title: Source-bound document composition
status: reviewed
---
# Source-bound document composition

## Problem and decision

The eight-report native job saved a draft but renamed every requested X-CHECK
label despite receiving all eight originals. Host-rendered completion receipts
now truthfully confirm storage. They do not establish content fidelity. A second
generative reviewer added latency and rejected correct content; its experiment
was removed. Preserve both failures in [[records/operations/implementation]] and
the linked immutable receipts.

Adopt documents composed of new prose and explicit original-text copies. The
host resolves a copy against an immutable completed read receipt and inserts its
text. The model selects passages and writes interpretation; it does not regenerate
passages selected for exact copying. Ordinary summaries and paraphrases remain
allowed and are labelled as new prose in this representation. This is a bounded
document construction facility, not a claim that every requirement was met.

The core foundation is implemented and deterministically checked. Agent/CLI schema, selectable native UI,
conversation-origin copies and the real failed job remain qualification gates.
No current product completion claim may depend on those unimplemented paths.

## Identity and text contract

- Each copy identifies a workbook-local read receipt, an exact JSON field path,
  Unicode scalar start/count and SHA-256 of the selected UTF-8 text. Initial
  allowed paths are `item.text` and `chunks[index].body` from `read` results.
- A completed read records the exact Source or Record version. Resolving a copy
  requires the same run and conversation as that receipt. Failed, prepared,
  non-read, other-run and other-conversation receipts cannot supply a copy.
- Search chunks can be reindexed or replaced. Their row IDs and offsets in a new
  extraction are not permanent references. The original receipt snapshot is the
  authority for this copy, including after a source acquires a newer head.
- Copying preserves the selected string's UTF-8 bytes, including decimal spelling,
  CRLF, combining characters, emoji and embedded NUL. It does not normalize,
  trim, translate, paraphrase or repair the text. JSON transport escapes are not
  content changes. Scalar coordinates are explicit and cannot silently become
  character or byte coordinates.
- This copies extracted/read text, not the original PDF or media file bytes.
  Original assets remain immutable files inside the workbook as specified by
  [[records/specs/storage]]. Extraction quality is a separate concern.
- A copy can be historical. Its visible provenance must identify the version;
  copying an earlier report does not establish current acceptance or current
  business state. Integrity hashes detect inconsistency, not truth or authorship.

## Composition and storage

`DocumentPart` is a strict union at the mutation boundary: exactly one `text`
or `copy` field. `text` is new prose. `copy` is a `DocumentCopyReference`; a
submitted quote cannot replace the host-resolved bytes. The foundation API is
`Workbook.documentCopy` for explicit inspection and `saveComposedDraft` for
atomic construction. These are Swift APIs, not advertised CLI commands yet.

The saved item remains a Record of kind document, status draft and meaning
estimate. Its rendered body concatenates parts in order. Its data contains a
version-1 documentComposition object with originating run/conversation and each
resolved copy's reference, exact text, source version, locator, receipt hash and
output scalar position. Exact copied input versions join explicit inputs in
lineage. Empty-copy compositions still need ordinary evidence inputs.

Neither provenance nor user acceptance upgrades generated prose to an actual.
Human acceptance, withdrawal and Undo retain the copied-text metadata and the
existing immutable version history. Composing a document changes no inventory
effect, opening balance, source head or source acceptance.

All copies resolve again in the same write transaction that creates the draft.
Any stale revision, invalid span, wrong hash, invalid part, missing input,
cancellation or size failure rolls back the entire mutation. Idempotent retries
return the original item without a new revision, including after the run ended;
a new write requires an active request-linked run. A reused token with changed
arguments is refused. Inspection of historical receipts does not resume authority.

Workbook verification checks each stored copied passage against its receipt,
position, expected hash and original version. Accept/withdraw/Undo versions and
portable export/reopen must pass the same checks. No schema migration or asset
BLOB storage is required. Existing workbooks without composition metadata retain
their behavior. The documentComposition key is reserved only on document Records. Business
fields with the same name on Sources, analysis Records or table rows remain
ordinary data; malformed app metadata on a document Record fails verification.

## Bounds and cancellation

The initial implementation caps a composition at 64 parts and 64,000 UTF-8 body
bytes, a source span at 16,000 scalars and 16,000 UTF-8 bytes, and a decoded
receipt at 128,000 UTF-8 bytes. IDs, paths, titles and explicit input lists have
preflight bounds before mutation-request serialization. Negative and overflowing
coordinates refuse without allocating an unbounded substring. No truncation
passes as a complete copy. Larger documents need explicit paged continuation,
not a hidden increase to the model context or tool-step budget.

Resolution and mutation check cancellation. The existing bounded writer-lock
and SQLite budget apply. This does not qualify every generic writer-contention
or interruption case in [[records/specs/distribution]].

## Voice, text and native interaction

The user's intent remains natural: “Make a receiving report and keep the
inspection codes exactly.” No copy tokens, hashes, scalar coordinates or
provenance UUIDs belong in the normal conversation. The agent must receive
bounded selectable source blocks tied to their original receipts. An exact-copy
request should use those blocks, while surrounding explanation uses new prose.
The user can inspect the draft in the right pane and explore a copied passage's
original version/locator. Provenance is inspectable without cluttering the prose.

Future composition tools must expose selected source content before using it.
The full persisted result can contain fields omitted from the model projection;
the new explicit inspection is a read, not evidence that the model previously
saw them. Copy choices restored after compaction likewise need explicit source
inspection and cannot silently restore citation eligibility. Preserve original
request constraints independently of any summary.

Do not ask a user to count characters or manually recreate labels. When a
selection is ambiguous, show the relevant original passages and ask only for
the choice that changes the document. Do not add a second model reviewer as a
substitute for host copying. Do not claim all requirements were preserved just
because one or more copies resolved correctly.

## Reviewed design passes

1. Identity and time: rejected current search-chunk IDs as anchors because
   reindexing changes them. Chose immutable read receipts, exact item versions,
   byte hashes and saved text. New heads and refreshed extraction cannot redirect
   an old copy. Explicitly separate historical source content from current facts.
2. Mutation and durability: rejected a text-plus-unverified-source-pointer
   payload. Resolve inside the write transaction, save both the body and copy
   snapshot, preserve idempotency, verify on reopen/export, and test acceptance,
   withdrawal and Undo. Refuse malformed unions, cross-scope reads and partial
   writes. A successful retry does not create a second draft.
3. Product and adversarial behavior: copying does not validate interpretation,
   extraction or completeness. New prose must remain possible. Model-visible
   omissions need a new bounded read, source instructions remain data, and
   scalar indexes remain implementation details. Keep the existing failed
   native job as the acceptance target instead of relaxing its exact labels or
   adding a flaky generative veto. Conversation-origin values, mixed-language
   prose and large omitted tails are explicit subsequent tests, not implied
   successes of this foundation.

## Implementation and acceptance sequence

1. Core foundation: exact scalar-span resolution from immutable receipts,
   strict typed parts, atomic save, provenance verification and portable proof.
   Test decomposed Unicode, CRLF/NUL/emoji, original-version lineage, mutable
   reindex/new head, invalid/forged references, failed/non-read receipts,
   scope isolation, overflow/size bounds, rollback, cancellation and idempotency.
   Acceptance/withdrawal/Undo retain content and meaning. Tampering fails.
2. Read and continuation integration: bounded selectable block identities from
   completed reads, explicit inspection of omitted result tails, no duplicate
   overlap on paginated chunks, source-origin request constraints and retained
   choice identity across checkpoints. Test a nearby paraphrase case and an
   instruction inside an input. Avoid exposing only a generic CHECK suffix.
3. Tool and native composition: add compatible typed parts to draft tools,
   grounded dynamic selections and native preview/provenance interaction.
   Preserve raw-text compatibility, receipts, truthful host confirmation and
   history. Qualify changed grammar/tool masks before any native inference claim.
4. Actual-model proof: rerun the unchanged eight-report native job with its
   existing context threshold and response budget. All eight requested labels,
   quantities, HOLD/clearance details and exact lineage must survive. Original
   state must remain unchanged and export/reopen/integrity must pass. Retain any
   failure. Run the nearby permitted-paraphrase/mixed-language counterexamples.
5. Complete interaction: voice/text/keyboard and source-navigation checks,
   earlier-conversation values with explicit scope, useful preview/export,
   interruption recovery and measured user latency. This does not clear the
   separate engine adoption, compaction, J11, accessibility or release gates.

Keep implementation status and exact evidence in
[[records/operations/implementation]]. Related boundaries are
[[records/specs/intelligence]], [[records/specs/conversation-context]],
[[records/specs/references-and-relationships]] and [[records/specs/distribution]].

## Foundation verification, October 27

The Swift foundation and workbook verification are implemented. The final core
build passes, and 90 core checks pass with zero failures, including eight new
composition groups. Strict formatting and diff checks pass. An independent
portable-fixture audit confirms five retained review versions with identical
original UTF-8 text, unchanged estimate meaning, one composition operation and
zero inventory effects after reindexing and a new source head. The original
request is complete; historical inspection still works without granting a new
write. Tests cover cancellation, atomic rollback, bounds, wrong scopes and
modified text/provenance. See [[records/operations/implementation]] for the exact
receipt, intermediate test corrections and outstanding product gates.

The app does not yet offer typed copy parts to its agent or CLI. Do not count
this as an actual-model, UI, performance, engine-adoption or release pass.

## Business-field compatibility review

A subsequent adversarial check reproduced an overbroad metadata query: a user
field named documentComposition on a Source, analysis or table row incorrectly
failed verification. Scope the reserved metadata to document Records. The new
regression failed before the fix (89 pass, one fail) and passes after it within
the final 90-pass run. Malformed document-Record metadata still fails. Original
portable proof remains retained. No agent or native interaction gate changes.
