---
type: spec
id: 01m609st2pz8zhg7bcpec874g1
created: 2026-10-28T03:45:29.174789+00:00
updated: 2026-10-28T13:36:23.760759+00:00
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

The core and agent integration are implemented and deterministically checked.
The unchanged eight-report task now passes. Nearby real-model copy selection and paraphrase now pass. A focused visible native provenance check now opens an exact text original and
returns to the draft, including minimum-width layout. Spoken VoiceOver, wider
source formats/locators, conversation-origin copies and a public CLI composition
command remain qualification gates.
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

At the foundation checkpoint the app did not offer typed agent copy parts. The
following integration checkpoint adds them. Neither checkpoint is an actual-model,
UI, performance, engine-adoption or release pass.

## Business-field compatibility review

A subsequent adversarial check reproduced an overbroad metadata query: a user
field named documentComposition on a Source, analysis or table row incorrectly
failed verification. Scope the reserved metadata to document Records. The new
regression failed before the fix (89 pass, one fail) and passes after it within
the final 90-pass run. Malformed document-Record metadata still fails. Original
portable proof remains retained. No agent or native interaction gate changes.


## Agent choices and continuation integration, October 27

Agent reads publish exact line/fragment passages with opaque receipt-bound IDs.
The host supplies scalar coordinates and hashes. Each read offers at most eight
entries and 2,000 serialized entry bytes; long lines split into adjacent bounded
fragments. copyOffset pages through unique candidates. chunkLimit selects one to
eight chunks (default two). chunkPage marks whether more chunks remain and gives
nextOffset. copyOffset pages within the same chosen chunk page, so callers retain
its offset/limit. Results above 124,000 serialized bytes
publish no choices rather than unusable IDs; the resolver still caps receipts
at 128,000 bytes. Adjacent/overlapping source chunks suppress equal passages at
the same original coordinates, while identical lines at distinct positions remain
distinct. This does not prove arbitrary document assembly across every chunk edge.

The draft tool accepts either ordinary text or up to 64 typed parts, each exactly
one text/copy field. The host requires the copy to have been published in the
original completed read and re-resolves it at atomic save. Raw-text drafts and
paraphrases remain compatible. Host-owned context annotations supply available
IDs; prose, user instructions and summaries cannot invent choices. Both inference
adapters derive declarations from the same schema. Native generation constrains
copy IDs to currently presented choices, and the dispatcher enforces strict part
unions. The existing grammar cannot express that union by itself.

Continuation explicitly re-presents verified original passages, separately from
model-written notes. It shares an 8,192-byte/eight-entry bound across at most eight
source versions, re-presenting one passage from each latest read. Repeated
versions and passages already visible in the retained tool group are excluded. These are scoped retained candidates, not a
claim of complete coverage. Omitted passages need another read. Re-presentation
does not restore citation eligibility, current acceptance or new action authority.

All 94 core checks pass. The agent integration checks and 38 native actual-tool
grammars with 323 exact reference mask comparisons pass, including dynamic copy
choice acceptance/refusal with reasoning on/off. Synthetic copy, paraphrase and
embedded-instruction cases pass. A duplicate-restoration context failure and a
parameter-order mistake in the new grammar test were corrected and retained in
the progress record. No model, engine, context threshold, response allowance or
step budget changed. The unchanged eight-report actual-model replay remains next.


## First native replay and compact projection repair

The unchanged eight-report replay genuinely failed at 24,922 tokens against the
fixed 24,576 threshold after two source reads. It saved its checkpoint, preserved
original state and unloaded. Source/binary/runtime identities stayed unchanged.
No draft was made. The failure exposed redundant original-copy context, rather
than qualifying content fidelity.

Continuation now retains one original passage per source version from its latest
read, instead of filling the projection with extra passages. It does not repeat
choices already visible in the final retained tool group. Omitted originals stay
retrievable and are never asserted to have been copied. All 95 core checks and
the agent checks pass after this change; actual replay remains pending. No
threshold, context size, response allowance, step limit or fixture changed.


## Smaller ordinary source reads

The second native replay passed the earlier refusal, then stopped after five
report reads at 24,854/24,576 tokens. One-passage continuation alone did not make
the latest eight-chunk result fit. Preserve that failure.

Ordinary tool reads now default to two chunks, with explicit chunkPage offset,
count, hasMore and nextOffset. One-to-eight chunk requests remain available, as
do the complete original and receipt. This changes retrieval granularity, not
the fixture, required source labels, complete-document claims, context trigger
or response/step allowances. A page is partial; more chunks need explicit reads.
The new test traverses all five synthetic chunks without gaps and checks an
explicit wide read. All 96 core groups and agent checks pass.


## Native eight-report fidelity checkpoint

The third unchanged maintained32K replay at 0d62807 passes all original assertions:
eight exact label/value/unit/HOLD lines, purchase and both packing constraints,
unspecified currency, lineage to all report versions, one draft, one working
space, unchanged original rows/heads/base/effects and included assets, complete
portable export/reopen/integrity, and clean model unload. Twelve responses and
eight checkpoints took 234.204528 seconds. Source/executable/runtime identities
match across a clean committed run. Two earlier context refusals remain retained.

Fifteen copy IDs were actually presented when drafting, but the model chose a
single new-prose part and zero copy references. This run establishes the frozen
task's content fidelity, not real-model selection of original-copy IDs. A new
nearby probe will test literal English and Spanish quotations and permitted
paraphrase, with original draft/source states protected. No full 64K comparison,
production compaction, engine adoption, UI, performance or release gate is cleared.

## Manual revision provenance

A regression reproduced workbook verification failure after free-text editing
a composed draft: inherited scalar positions/text no longer matched the original
read. Manual revisions now remove only the reserved documentComposition metadata
from the new version. The submitted edit becomes a Source as before; lineage
retains the immutable earlier document and its original copy proof. Existing
business metadata, meaning and scenario remain. Even an unchanged separate copy
uses this edit-submission path rather than claiming newly resolved source spans.
Do not silently align repeated text or rewrite old provenance. Tests cover changed
copy text/positions, exact old history, acceptance, separate drafts and portable
reopen. This does not replace the pending native provenance interface.


## Nearby real-model selection and draft-intent failure

English and Spanish literal-quotation cases pass through the real native model.
Each uses one actual copy reference, preserves decomposed Unicode and CRLF bytes,
saves a draft estimate, leaves original/unrelated draft versions unchanged, and
passes portable export/reopen/integrity. The model chooses all tools and arguments.
The permitted-paraphrase case fails: it returns a chat answer containing the
excluded identifier and saves no draft. The completed probe unloads the model;
this is two passing cases and one real failure, not full nearby qualification.

Keep the exact three requests unchanged. Clarify in the existing agent policy
that explicit draft requests require a saved artifact, that a chat summary is
insufficient, and that identifier exclusions apply to paraphrase independently
of preserving factual values. This adds no classifier, reviewer, threshold,
budget or new write authority. Recheck the same nearby cases.


## Nearby qualification and native provenance implementation

The unchanged English/Spanish quote and permitted-paraphrase replay now passes.
Literal cases have actual copy metadata and exact Unicode/CRLF; paraphrase saves
a draft with no copied passages or excluded identifier. This is a bounded native
mechanism/intent observation, not a guarantee of every interpretation or full
product qualification. See the preserved failure and pass receipts in
[[records/operations/implementation]].

The document viewer now has a Copied passages disclosure showing bounded excerpts
and locators. Open original passage navigates to the exact saved source version.
Earlier sources show the existing newer-version notice without retargeting. The
presentation checks local saved span/hash/body consistency and refuses unusable
metadata. Full receipt integrity remains Workbook.verify's responsibility; no
authorship, truth or current acceptance is implied. All 18 document UI/lifecycle
checks pass. Visual, keyboard, narrow-layout and source-return interaction still
need the native preview; compiling a control is not a visible journey pass.

## Binding-only correction exception, October 28

A versioned link choice may change bindings while preserving byte-identical
composed document text. editDocument now retains documentComposition only when
references are explicitly supplied, separate is false and all UTF-8 text bytes
match the original. The new draft still records its human submission and original
version as inputs. Exact-copy spans and receipt identity remain valid and verify.
Free-text edits, changed bytes and explicit separate copies keep the existing
span-removal behavior. The original always remains inspectable. Native source
opening forwards the exact copied locator. Programmatic checks cover this
exception, stale refusal, exact retries and subsequent prose edits; visible
interaction remains pending. See [[records/specs/references-and-relationships]]
and [[records/operations/implementation]].

## One draft with new prose and copies, October 30

`draft` now always takes `text`, which may be empty, and may also take `parts`. A schema field
prompts for new words better than a description does: with `text` removed the model sent only
copies and lost the purchase code and amounts in three of three runs, and with it required that
stopped.

`DocumentPart` stays a strict union at the mutation boundary. The tool layer composes the two:
a copy takes the place of its own exact words in `text`, so a line retyped beside its copy is
saved once, where the prose put it, with its provenance. Other copies follow the prose on their
own line. A text part the prose already says is dropped. Without prose, parts keep their exact
bytes. A retyped line that differs at all stays new prose, so a loose paraphrase beside its copy
appears as two lines, which happened in one real run.

A copy ID sent in `inputs` means its one source version.

A plain request to draft something, in English or Spanish, gets one correction if the model
tries to finish without saving a draft, because the policy sentence alone failed twice. It is
one correction, so a false alarm costs one step.
