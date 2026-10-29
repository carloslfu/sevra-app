---
type: review
meta-type: conclusion
id: 01m5rbxzcb321z9rweagje7715
created: 2026-10-25T01:48:47.371698+00:00
updated: 2026-10-29T04:06:11.366554+00:00
summary: Three first-principles reviews resolve UX, data integrity, search coverage, installation and scope risks before implementation.
title: Design review passes
---
# Design passes

## Pass 1: user job and interaction

Reviewed the design against importing invoices, correcting stock, finding evidence
and sending the result. Problems: a chat-only UI would make browsing dependent on
inference; every result becoming a tab would create clutter; an unsaved preview
could lose generated work. Resolutions: immediate native viewers, searchable space
picker, permanent main conversation, temporary right-pane stack, autosaved drafts
and independent explicit space saving (P01–P16). Text/voice remains the principal
control but direct table interaction and native menus remain available.

Rejected a separate database setup wizard. The first window creates a workbook
and makes useful actions discoverable. Setup and indexing have honest states;
no simulated AI success while weights are missing. Native controls and keyboard
paths support a user who cannot or does not want to speak.

## Pass 2: data correctness and failure recovery

Adversarial cases: two receipts for one delivery; two identical real deliveries;
accepted forecast mistaken for actual; file copied halfway; live SQLite copied
during a write; linked original changes; model output tries arbitrary SQL. Added
separate occurrence/effect/version identities, independent meaning/acceptance,
immutable assets with stage-before-commit, coherent backup, explicit external
version handling, typed mutation tools and Decimal calculations (S01–S16).

Research surfaced the SQLite WAL reset advisory. Updated S11 from generic WAL
recommendation to serialized rollback journaling until a fixed library is verified.
This favors reproducible correctness over an unmeasured performance assumption.
Archive review adds traversal/symlink/collision/expansion defenses and schema
validation before trusting a portable workbook. No blanket repair on opening.

## Pass 3: agentic search, scale and distribution

Problems: FTS alone misses synonyms; embeddings alone miss identifiers; generic
chunking loses PDF pages; partial extraction can make absence claims misleading;
whole-corpus prompts and in-memory asset copies fail at scale. Resolutions:
lexical+filename+structured indexes, bounded iterative agent tools, exact version
locators, explicit coverage, streaming copies, paged tables and corpus benchmarks
(Q01–Q15). Embeddings are a later measured index, not required to call search agentic.

Native inference review requires matching Metal resources and a pinned complete
build rather than a local sibling package path. CLI/app use the same core and
concurrency rules. A public clone must build without a private brain. Added exact
fresh-install, offline reopen, real-model and failure-path gates (D01–D10).

## Review disposition

Specification revision 1 is ready for implementation, with measured acceptance
pending. Further passes occur after core tests, real-model evaluation and rendered
UI inspection. Failures change the implementation/spec and remain in verification
history; they must not be hidden by reducing the requirements retroactively.

## Implementation review: observed failures and corrections

The first model view task repeatedly omitted a chart dataset binding. Native typed
tools replaced the initial JSON-in-text protocol and the view was created in a real
run. That run then invented currency and used the wrong percentage denominator.
A deterministic comparison tool and finish validation now address those specific
failures. The corrected supplier comparison subsequently passed; its evidence is in
[[records/operations/implementation]]. These checks are not a
proof that arbitrary model statements are correct.

A synthetic 4.3 GB archive round trip initially peaked above 8 GB resident memory.
Streaming alone did not bound Objective-C temporary buffers. Per-chunk autorelease
pools reduced the repeated measured peak below 40 MB. ZIP64 export, reopen and
hash verification passed. This is a synthetic sparse-file fixture, not a media
playback or SSD throughput benchmark.

Further review added coherent pinned values plus exact inputs, unknown/error
handling in charts and metrics, validation before changing existing column types,
formula history, resumable 1,000-row intake batches, checksums for Office parts,
cooperative extraction deadlines, Vision request cancellation, search paging and
facets, and explicit linked-file recovery. Native interaction qualification remains
separate from compilation and core tests.

CI found noncanonical JSON key ordering in a resumable-import request. The same
column definition could serialize differently and be rejected as a changed retry.
Serialized column/view definitions now use canonical sorted-key JSON. A real
cross-process intake retry test passes, along with 40 core checks. Search reads
now use a coherent read transaction and SQLite progress deadlines/cancellation.

## Acceptance, recovery and packaging pass

Table proposals leave accepted cells unchanged until review. Acceptance applies
all rows in one transaction; stale row versions roll back the entire operation.
The first undo implementation lost its inverse table-change identity. Repeated
undo/redo now retains each inverse and tests cover conflicting edits and retries.

Failed URL retrieval preserves an explicit failed reference with no fabricated
asset or searchable content. Sensitive query fields are redacted in captured and
explicit-link metadata. Cancellation and invalid schemes do not create a source.

The standard sealed app layout rejects resource bundles at its root. Preserve
Contents/Resources, require the Fast pack's explicit tokenizer class, and test
packaged resources independently of the build tree. Do not claim generic upstream
tokenizer fallback support. CI's dbmd download extracts into a versioned directory;
its validation command now uses that actual path.

## October 26 direction and integration review

Owner changes Workbook to primary and Websites to secondary. Replace only the
inference integration, preserving workbook semantics and UI/CLI data boundaries.
Retain Splash's C++/Metal engine; replace needed Python-layer behavior in Swift.
Use its existing native helper first. A static library is feasible but not a
stable Swift SDK, and direct linking adds ownership and crash coupling.

The adapter cannot discard tokenization, model layout checks, stop/tool parsing
or grammar masks merely because the engine generates tokens. Map each surface
and test it against the pinned upstream. Publish no automatic size/speed benefit.
Hardware floor changes to M3+/26.4+ for Splash; old support claims must follow.

New table creation preserves estimate/plan meaning after acceptance. User requests
become Source inputs for proposals without contaminating ordinary evidence search.
Validated proposals terminate a turn as needs_review; the app supplies its receipt
instead of requiring another model sentence after a successful tool. Real-model
requalification of that last change remains pending.

## Conversation continuity review, October 26

Three passes informed [[records/specs/conversation-context]]:

1. User-job pass: last-eight-message trimming can forget a decision even if a
   larger window exists. Adopt proactive compaction plus recoverable original
   history and retrieval. Keep one conversation and no context-size controls.
2. Integrity pass: a summary can falsely resume a cancelled request, claim a draft
   was accepted, or repeat a completed movement. Separate model-written digest
   from host-reconstructed current status and operation identities. Preserve exact
   source references, atomic checkpoints and all original receipts. Never treat
   a digest as permission or as a newly inspected business source.
3. Resource/recovery pass: larger allocations can slow input processing or exceed
   practical memory. Qualify 32K and practical 64K using occupied contexts and full
   jobs, including compaction time. Test repeated maintenance, interruption and
   tangents, not just startup or an isolated summary. Keep 8K as a development
   reference until a larger profile is measured. These are reviewed requirements;
   automatic compaction has not yet been implemented.

## Tool journal and retrieval review, October 26

Pass 1, continuity and meaning: a question about older conversation must retrieve
original messages instead of treating its current question as evidence. Exclude the
current request from history search. A saved result is historical information; only
fresh inspected fields enter the current citation vocabulary. Acceptance still comes
from current records. Automatic summarization and action resumption remain separate.

Pass 2, interruption and atomicity: preserving only a final tool message leaves an
unobservable mutation interval. Save intent first; complete the result and message
in one transaction. Repeated call IDs are refused. A missing receipt means uncertain,
not rejected or undone. Expose exact committed-operation proof, keep draft/estimate
meaning unchanged, and retain ambiguity for partially completed archive intake.
A controlled reopen at this interval is tested; broad process-kill recovery remains.

Pass 3, retrieval and portability: never cut JSON or throw away a large result after
an action succeeds. Save it exactly and return navigable bounded pages. Include raw
JSON segments for unusual keys and Unicode-scalar offsets for text. Atomic receipts
travel in portable snapshots. Append-safe history cursors must survive the agent's
own writes. Read-only CLI/core checks verify identity, precision, scope, tampering and
offline reopening. Projection bounds are not a memory-bound claim for huge structured
results. Scope-safe tangent search, full unresolved-call browsing, memory scale and
repeated compaction remain explicit follow-up gates.


## Context controller review, October 26

Pass 1, retention: the first actual summary exceeded its output budget. A shorter
schema completed but replaced an old exact user value with routine progress.
Require per-checkpoint retention, not merely a correct final answer recovered from
history. Typed notes preserve exact references; host retention protects earlier
user-backed facts/constraints/decisions. Initial extraction can still be wrong and
large collections need a better retirement/retrieval policy. Never erase originals.

Pass 2, authority: a reopen probe unexpectedly proposed a table despite an explicit
no-change instruction. Keep this failure. Added host-enforced read-only tooling for
recognized explicit current-request restrictions, with every mutating tool tested.
Do not mistake that narrow rule for a complete intent authorization system. A
misleading summary cannot change acceptance or turn an estimate into an actual.
Unfinished previous calls must survive context rebuilding with committed-operation
proof and uncertainty. Reset calculation evidence when its result is omitted.

Pass 3, continuation: current requests and complete latest tool pairs survive
maintenance. Check unchanged history hashes, atomic publication, cancelled/invalid
summaries, checkpoint chains, offline reopen and scoped tangents. Actual-model
results remain distinct from synthetic controller fixtures. Foreground backfill
latency, long instruction collections, process-kill recovery and sustained larger
contexts remain release gates, not waived by successful short native jobs.


Follow-up evidence: the 8K adversarial workflow exhausted context, then its helper
shutdown hung in Foundation waitUntilExit. Replaced the unbounded wait with a
termination notification, bounded TERM/KILL waits and lease retention on failed
reaping; 33 serial-worker shutdowns include a helper ignoring TERM. A 32K attempt
returned a forecast answer without citing the accepted version. Read results now
identify historical/current versions explicitly without granting unseen citations.
A retry exposed loss of an older unstructured checkpoint; preserve its legacy
digest verbatim. Focused native acceptance/cancellation/retry checks subsequently
passed. The opt-in Slotstream comparison searched business documents instead of
conversation and failed recall, so its production compaction capability stays off.
These failures remain in the evidence and constrain product-readiness claims.


A repeated reopen probe recovered the correct messages but kept searching until
the step limit. The completion contract admitted only item-version citations,
while conversation facts may exist only as original messages. Added a distinct
message:ID citation, eligible only after a fresh eligible original-message read.
The current request and later messages cannot qualify as earlier evidence. It
renders a link to the original exchange and cannot become a business-record input.
Clarified conversation versus document search and existing table components versus
new datasets after a generated-space probe omitted its requested table component.

## Search scope review, October 26 local / October 27 UTC

The native continuity failure revealed a routing trap: business search returned
no evidence even though the exact answer existed in original conversation.
Adding another prompt instruction left the model responsible for choosing the
right index before discovery. The shared agent search now offers separately typed
results from both indexes on an unfiltered first page. This is a host retrieval
change; reasoning mode and model weights remain unchanged for the comparison.

Adversarial checks preserve explicit business filters, branch isolation, the
active-request cutoff, distinct cursors, cancellation and incomplete extraction.
A conversation candidate cannot mint a citation until its original is read.
A third search that finds only conversation must not trigger the empty-business
termination path. Deterministic integration checks cover all these cases. Actual
model continuity must be repeated separately; one pass cannot qualify release.

Pagination review found an older integration defect: the nextCursor carried the
whole workbook revision, but persisting a search receipt incremented that revision
before the next tool call. Direct core pagination tests did not exercise that
journal boundary. Added a real shared-agent two-page fixture with twenty evidence
items and a conservative operation-journal anchor. Context checkpoints also keep
unchanged pages valid; an independent writer changing evidence refuses the same
cursor. Unknown mutation types and long journal intervals still invalidate it.

## Reasoning comparison review
Bounded reasoning is a controlled runtime comparison, not a substitute for
host authority or valid evidence. The first matrix freezes five synthetic workbook
snapshots across three paired repetitions: draft forecast, accepted forecast,
original-message recall, deterministic inventory and missing evidence. Alternate
arm order, reopen each snapshot, keep the same user prompt and verify unchanged
business records. New current-run/request identifiers remain unique, so this is
not byte-identical prompt replay. Inspect answer semantics and citations manually
as well as applying deterministic checks. Startup-inclusive elapsed times are
observations, not a standalone engine speed benchmark. Keep failures from both
arms, including infrastructure or grammar failures.
Manual review of the first matrix also found an accepted-forecast answer exposing eight-character UUID prefixes. The repaired candidate rejects these prefixes for inspected references, in addition to full UUIDs. The follow-up inventory assertion requires the exact opening/effect IDs and a successful current-run balance call, not merely two arbitrary citations. Preserve the original automatic check results and identify these additional review criteria explicitly.

## Second-candidate semantic review
Manual review of the second candidate found an extra narrative error in the first bounded inventory answer: it called 1 January 2026 the opening Source acceptance date. The evidence gives that as the inventory starting date; the Source creation/acceptance happened later and the answer cannot infer an acceptance timestamp from the opening condition. The stock total and exact basis/effect citations passed. Preserve the distinction between automatic task checks and full semantic correctness; do not count a successful numeric/citation check as proof that every added sentence is supported. Keep the frozen comparison unchanged, retain this output, and evaluate a targeted answer-policy correction separately after the cohort finishes.

## Grounding and recovery review
The broader R3 continuity probe exposed repeated uncited finishes after reopen. R4's host-selected inspection scope is enforced both in the adapter and before tool dispatch; it grants no automatic citation or mutation permission. Three subsequent continuity probes passed, but R4's frozen recall repetition zero still invented quantity 120 instead of 0.20 kg by declaring current_request. A model-provided basis is a claim, not a trusted proof.

R5 therefore adds a narrow numeric check against the actual request and successful visible calculation values. Original/history claims require fresh inspected citations. This blocks the observed unsupported-number path while retaining spoken arithmetic through calculate. It does not establish semantic entailment, check units, prove calculation relevance, or prevent every misclassification under general, unresolved or completed_action. Wider paraphrases and adversarial evaluation remain required before promotion. Do not present typed basis or citation membership as a general hallucination solution.

The separate controlled recovery fixture injects only the failed finish, then uses the real model. Its initial four responses retrieved and cited the correct original. The fourth response expressed quantity and unit in separate clauses, which exposed a test-only exact-phrase assumption. Preserve that failed test exit, correct the wording-sensitive assertion, and rerun the fixture without changing runtime behavior. Fault-injection recovery must be reported separately from autonomous completion.

## R5 coverage overclaim
Manual review of accepted-forecast repetition two found a correct core answer followed by an unsupported workbook-wide statement that no inventory movements were recorded. The model had performed two empty lexical searches and listed datasets; those operations do not establish exhaustive record coverage. The synthetic fixture does contain no movements, so this is an evidence-scope overclaim rather than a wrong fixture value. Retain it separately from the automatic task score. Typed finish basis and eligible citations do not establish entailment for every sentence. Wider coverage-aware answer synthesis remains an adoption gate; do not claim general reliability or promote native inference from the small suite.

## Inline reference design review, October 27

Owner-adopted design: [[records/specs/references-and-relationships]]. Fits the
Sources/Records model, SQLite portability, voice/text interaction, native right-pane
preview and bounded search. Keep relationship meaning, resolution and acceptance
independent. A mention enables navigation; a substantive inferred claim is a
derived Record with evidence/status. Stable bindings survive renames/rebuilds;
original bytes remain intact. Mention cycles do not weaken derivation checks and
links never widen conversation scope. Avoid mandatory graph UI, all-pairs inference
and another database. Explicit references precede evaluated suggestions.
These are design conclusions, not measured usability or implementation proof.
LJ01-LJ10 define the failure, recovery, model, accessibility and scale checks.
Existing native Splash and release qualification are unchanged.

## Source-bound document review, October 27

Reviewed three further passes in [[records/specs/document-composition]]:
identity/time rejects disposable search rows; mutation/durability resolves
originals atomically and retains review/export provenance; product/adversarial
behavior separates exact copies from interpretation and completeness. Retain
the failed generative-review experiment. The core foundation passes focused
invariants; agent selection, conversation values, native interaction and the
actual failed job remain unqualified.

## Native saved-reference review, October 28

Three focused reviews accompany the reader/navigation implementation:

- Authority: render saved bindings, never route raw source URLs; live navigation
  resolves an exact version without creating citation evidence. Explicit choices
  preserve every other occurrence, never promote a mention to a business claim
  and do not grant another workbook's access. General agent traversal stays open.
- Durability: Source and asset bytes remain unchanged; Record corrections create
  ordinary drafts with stale checks and retry identity. Byte-identical binding-only
  composed drafts retain valid copy spans; free-text changes discard them. Late
  reads and failed next-page requests cannot replace useful current state.
- Usability: optional Links/Mentioned in stays in the existing right viewer;
  exact text/dictation shell commands need no inference. Back flushes drafts and
  restores body position/PDF page. Clear unindexed coverage avoids false absence.
  These choices still require visible keyboard, VoiceOver and narrow-layout
  qualification. Bounded offscreen correctness is not evidence of broad usability.

See [[records/specs/references-and-relationships]] and
[[records/operations/implementation]] for implementation scope, failures and gates.


## Review: canonical link authority and private request pointers, October 28

A raw URI in an immutable imported file may disagree with a later explicit saved
binding. Two native probes chose the raw URI and confidently answered from the
wrong document despite policy guidance. Adding canonical metadata alone did not
fix it. Reads now include bounded saved-reference metadata, and raw internal
routes in read/tool_result text no longer independently add lookup choices.
Structural destinations and independent discovery supply those choices; the
original evidence remains byte-identical. Current user links and earlier
conversation keep their own lookup semantics. No fuzzy ID repair is introduced.

Private request Sources also cannot become workbook-wide business evidence merely
because a shared document links them. Agent FTS/references/lineage filter technical
kinds; item reading enforces the current immutable submission ceiling. Scoped
history remains the path to earlier messages. A concurrent private request head
cannot appear in currentVersion or become a forced refresh of this run's request.
Business historical-version checks remain in force. Tests separately force the
lookup-choice and direct-read gates, including a visible plain UUID that cannot
grant conversation access. A changed test initially expected a later refusal after
the earlier route-choice gate had already blocked it; that failed log remains.

The final native corrected pin/current edition answer is accurate, and the
private original stays unavailable without leakage. The former needs six steps
and one opaque-ID correction; the latter takes eight steps. This is still too much
work for a simple negative answer, so no latency or general reliability gate is
closed. Preserve the initial negative step-limit failure and both confident
wrong-route answers. No model mutation, automatic recursive graph traversal,
embedded-format hyperlink extraction, visible accessibility or large-graph
retrieval comparison is qualified by these two observations.


## Review: usable native links and destination focus, October 28

Actual preview checks found two gaps that offscreen core tests did not establish:
the outgoing list had no working keyboard selection, and synthesized inline link
children could be visible in the accessibility tree while native activation did
nothing. Selectable scoped lists with Return handling repair the first. A native
accessibility representation over the same saved occurrences repairs the second;
its ordinary link controls activate in the actual app. Keep visual text selection
and saved binding routing. Avoid changing global keyboard or accessibility settings.

The destination sheet also opened without search focus. SwiftUI task/default-focus
attempts did not repair that real sheet-content transition. A small AppKit field
sets focus on attachment to its own window and releases its delegate on teardown.
Only the explicit selected current-query result can save. Empty Return cannot
choose, and changed queries clear selection. Source annotations preserve original
text/assets and pending business records; source and portable integrity pass.

Minimum-width copied-document layout, exact original navigation, historical/current
edition navigation, incoming scope/paging and keyboard correction now have focused
visible evidence. AX inspection and native activation are not a spoken VoiceOver
or broad accessibility qualification. General voice/text passage authoring remains
planned. The same UI pass revealed technical annotation noise in Recent work and
search; correct normal-view query boundaries without deleting owner evidence.
See [[records/specs/references-and-relationships]] and
[[records/operations/implementation]].


## Contextual import reconciliation, October 28

Reconciled the owner-confirmed side-conversation direction with actual code rather
than declaring existing import sufficient. Three review angles produce concrete
gates in [[records/specs/contextual-import]]:

- Discoverability: Home already has Add files, but Welcome lacks start-from-file
  and the persistent plus icon does not explain data intake. Both entry points
  must call one scoped capability; native controls complement central voice/text.
- Intent/authority: suffix-based automatic tables are convenient only for some
  requests. Preserve harmless capture while resolving material role/target/mapping
  ambiguity. A selected table and CSV suffix do not authorize append or merge.
- Continuity/truthfulness: cached totals and retained formula strings do not keep
  an Excel workbook functioning after edits. Original coordinates, dependency
  translation, named ranges, useful formatting and feature reports need explicit
  support and counterexamples. Existing table A1 addresses cannot be assumed to
  match Excel source coordinates. Preserve originals and all unchanged evidence.

The spec now aligns product, storage, search and agent boundaries, with ten focused
journeys and ordered phases. This review establishes direction and inspected gaps,
not implemented role planning, native Excel compatibility or a new UI pass.


## Technical discovery and command-state follow-up, October 28

The native qualification's two newly exposed failures are retained: technical
Sources fill ordinary Home/search, and after a new-window Home-to-document change
the Workbook link menu can remain disabled. Filter technical kinds in the core
before both result limits and filename/lexical paging, retaining explicit owner
inspection and stricter agent scope. Observe the focused workspace's actual
Published document state in menu content; focus identity alone does not track
navigation. Two core regressions fail before repair (131 pass/2 fail), then all
133 pass. Actual native replay remains the menu/focus acceptance evidence rather
than an implementation-mirroring UI unit test. Expanded intake implementation
follows these corrections, without weakening existing engine/adoption gates.


## Contextual intake implementation review, October 28

First pass, intent and truthfulness: a parser suffix cannot authorize a new
working table. Register durable use separately from included/linked storage;
reference/analysis create no permanent working data. Keep original identities
when choosing another use. Label XLSX conversion saved values and formula
evidence, with live calculation false and uninspected advanced features explicit.
Analysis input readiness cannot claim an analysis result. Missing or cancelled
work exposes partial/failed state, not a reassuring success.

Second pass, failure and ownership: one request spans capture and job registration;
retry works from a saved original after the input disappears. Changed arguments
cannot reuse the receipt. Recover the narrow capture/registration interruption
before any suffix-based conversion. Fence attempts; do not hold the workbook
lock during parsing/copying. Preserve committed batches and their actual dataset
IDs on failure. Native operation identity owns callbacks. A failed role selection
must refresh from the persisted job before retry, so a second click cannot fail
merely because its earlier role choice already committed. Actual malformed-CSV
native replay verifies the final Continue selected use path and retained original.

Third pass, scope and policy: apply the owner's production-1.0 compatibility
baseline by maintaining one current initial schema and refusing unsupported
workbooks byte-for-byte, with no automatic reset. Preserve historical migration
receipts without maintaining their success cases as current gates. Current-format
history, lineage, Undo, integrity, portability and recovery stay tested. The first
broad run exposed an old CLI result-shape assumption in an extraction check;
update the test to request reference/values explicitly and consume the new result.
A later check run was interrupted by editing its executing shell script; rerun
from the final stable script rather than count that run as passed. A new synthetic
XLSX fixture initially lacked a worksheet relationship Type and was corrected;
retain both failed logs. Final broad checks, packaged isolation, concurrency and
nine CLI intake cases pass. General model/voice intake, mapping/merge, live Excel
continuity, rich clipboard and full release qualification remain open.

## Reviewed table updates, October 28

Pass 1, interpretation: require a target, explicit method and complete mappings;
keep exact lexical keys and do not guess duplicates or business effects. Distinguish
new-row semantics from matched-row semantics and retain original input. Bound both
incoming and target materialization. XLSX and partial-column updates remain open.

Pass 2, publication: a preview cannot publish rows. The draft pins schema, exact
row heads/order and fingerprint; stale preview/apply/Undo refuses. Acceptance uses
saved results rather than a parser, and rollback removes every partial row/head/
lineage/receipt. Reversal preserves rejected history and logical identity. Exact
receipt retry precedes missing originals or changed target state. Refuse generic
record creation for the host-only update proposal kind. Core, process CLI and
native acceptance/Undo/relaunch/stale-refusal evidence support this bounded slice.

Pass 3, ownership and scope: late source/preview/publication results cannot replace
a newer or closed review. A lost draft reply retries the same token. Native states
label original previews, Undo/Redo and source-record numbers clearly; Home uses a
readable label. Retain the pre-1.0 policy and the new persistence-readiness contract.
Do not equate saved apply plans with complete workbook reconstruction or truthful
human/programmatic actor coverage. FJ gates and local-model/voice update tools stay
open; mutation inventory and shared capture/apply are next before automation storage.
Form draft persistence, broader usability and all Excel continuity gates remain.

## Explicit interpretation adversarial review, October 28
Before implementing, separated captured evidence, probabilistic interpretation and accepted business effects. A quotation proves where text came from, not that a derived value is true. Host validation checks shape, types, exact inputs/quotes, meaning/scenario and final worker authority. Missing facts pause with empty values and useful issues. Interpretation has no application tools or automatic approval.

Implementation review found three important edges: retain rejected raw responses for diagnosis; preserve transitive interpretation lineage through scalar calculations so estimates cannot become actual stock; compare final publication to the exact raw response while allowing deterministic decimal normalization during reconstruction. Focused counterexamples and actual malformed-model evidence are retained. An unresolved result may cite the exact text explaining what is absent without inventing that absent value. No generic prompt or successful demonstration can establish broad semantic reliability. Full EJ06-EJ08 and release qualification remain open.

## Conversation interpretation adversarial review, October 28
First pass, usability: raw workflow JSON caused repeated real-model invalid bindings and Boolean fields. A trusted exact workflow_template copies declared parameters, adds required action review and validates closure before save; it grants no execution. Second pass, identity: model-generated logical IDs caused refused saves. Host creation identity and exact inspected edit bases simplify the in-app contract, with stale/foreign/read-only refusal preserved. Third pass, truth: actual V3 falsely said saved after a failed write by relabeling its answer as general. Receipt-owned outcomes prevent this bypass; cited evidence and checked arithmetic remain independently useful. An overbroad first presentation fix bypassed arithmetic verification and failed the compaction counterexample, so the final fix narrows current-request replacement to unresolved failures. All failed probes and budget regressions remain retained. Final actual model passes metadata/run assertions, including two corrected workflow-save failures. This does not establish broad semantic reliability or release readiness.

## Document workflow review and qualification, October 28
Usefulness pass: explicit prepare -> interpret -> propose -> review keeps the original and pins the exact parsed text. Transaction pass: extracting through the public multi-transaction intake API would split the workflow checkpoint; trusted insertIndex now shares the outer captured mutation instead. No workbook lock spans helper parsing. Adversarial pass: linked files require deliberate inclusion, competing index attempts fence old publication, stale/cancelled/expired claims roll back index/checkpoint, incomplete text pauses, later indexing cannot replace a prepared interpretation input, and copies grant no execution. Eight focused groups plus four new actual process-death boundaries and the packaged receiving flow pass. Initial schema17/SQL16 disagreement failed fresh fixtures and is corrected by one canonical interpolated version. Formatting and harness failures remain preserved. Full business journeys/accessibility/automation and production readiness remain open.

## Conversation preparation failure review, October 28
The actual V1 success still required three refused saves. Two treated parameter name evidence as a lineage item ID; explicit UUID validation and actionable authoring guidance preserve request lineage without accepting that mistake. V2 then failed by searching for native workflow starters among saved definitions. Tool descriptions and structured registry guidance distinguish the template call from saved data. Final V3 uses workflow_template and queues exactly one pending run; two malformed first-job saves remain visible in its evidence. Fullcore271, final grammar/reference/native/package/model checks and actual SQLite full/lock rollback pass. These are bounded synthetic functional results, not general reliability or instant interaction claims. Preserve the failed probes and improve from them rather than widen limits.
