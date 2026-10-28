---
type: spec
meta-type: conclusion
id: 01m5zn6ks2pyv72pjs65f90rxj
created: 2026-10-27T21:45:28.610289+00:00
updated: 2026-10-28T13:36:23.737552+00:00
summary: Adopted inline references, backlinks and bounded traversal with stable identities, versioned evidence and separate relationship claims.
title: Inline references and relationships
status: reviewed
---
# Inline references and relationships

## Decision and scope

Adopted October 27, 2026. The explicit-binding foundation, bounded body parser, backlink index and owner-facing CLI are implemented.
Retained extracted-text links, owner CLI inspection and a bounded native reader/navigation slice are implemented. A bounded local-agent traversal/read slice is implemented and has focused synthetic evidence. Focused visible native navigation, keyboard correction and minimum-width checks now pass. Spoken VoiceOver, broader usability, general voice/text authoring, embedded format-specific hyperlinks, retrieval-value comparisons and complete first-slice acceptance remain pending. Authority:
[[sources/notes/2026/10/inline-references-adoption]]. This extends Sources/Records,
SQLite, native previews and agentic search without adding a business category.
At adoption, record bodies retain wiki syntax as text, conversation messages have
exact item links, and lineage is explicit. Body-link resolution, backlink indexes
and a weak-association workflow are not yet implemented.

Connect quotes, orders, invoices, assumptions and explanations without requiring
users to maintain a graph. Implement explicit references, backlinks and bounded
traversal first. Evaluate inferred associations later. No graph database, mandatory
relationship workspace, full graph visualization, automatic ontology construction
or whole-workbook all-pairs model scan is required.

## Meaning and authority

L01. Preserve these distinctions in storage, tools and presentation:

| Connection | Meaning | Permitted use |
| --- | --- | --- |
| Mention | A passage refers to an item | Navigation, backlinks, retrieval |
| Possible association | Matching or AI suggests relevance | Find candidates to inspect |
| Business relationship | A claim such as an invoice belonging to an order | Validated domain queries under meaning/status/scenario |
| Derivation | A result was produced from exact input versions | Provenance, dependencies and reproducibility |

Weak means limited semantic commitment, not unreliable identity. Target resolution,
relationship meaning and claim acceptance are independent. An exactly resolved
mention is not proof of payment, delivery, support, contradiction or derivation.
Acceptance records adoption, not universal truth. Accepted estimates remain
estimates. Navigation and relationship discovery cannot create business effects.

L02. Substantive inferred relationships are derived Records with exact supporting
inputs, transformation/model identity, meaning, status and scenario. Human changes
or adoption introduce Source information under existing rules. Ordinary references
are structural annotations; do not create a business Record for every occurrence.
Relationship indexes project those Records without becoming competing authority.
The existing planned supports/contradicts relationships must represent evidenced
claims, not inferred facts merely because two items are linked.

## Identity, storage and history

L03. Store canonical reference identity/bindings in SQLite: reference ID, origin
item version and body/extraction locator, visible label, target workbook identity,
logical and/or exact version ID, target mode, resolution state and binding
provenance. Concrete table names are implementation choices. Keep mention indexes
separate from derives-from lineage, indexed by source, target, kind and history.

L04. Ordinary navigation can follow a logical item; evidence citations,
derivations and pinned outputs retain exact versions and optional page/row/time/text
locators. Resolve a live link to an exact version before citing inspected evidence.
Preserve saved labels and historical context. Renames, duplicate titles, aliases
and localization cannot redirect a bound link or change an old citation's target.

L05. Support double-bracket wiki authoring and internal Markdown references through
one resolver; an at-sign picker is optional authoring convenience. Names help lookup,
not durable identity. User selection or an explicit stable target establishes the
binding. Missing or ambiguous names remain unresolved without blocking unrelated
text saving or fabricating placeholder items. Later title matches are candidates;
rebinding is explicit and versioned. Ignore escaped literals and code examples;
unsupported syntax remains text. Do not reinterpret old content on index rebuild.

L06. Preserve imported asset bytes and Source text. Extracted mentions and
resolution annotations retain their own versioned bindings and source locators.
Annotating a Source records new annotation state/receipts without rewriting it.
Reference corrections preserve prior bindings. Rebuild indexes from stored text,
parser/extraction identity and durable bindings without a model or fresh name guess.

L07. Save authored text and canonical bindings through the shared core transaction,
with expected-version checks and idempotency. Publish edges atomically for an
origin version. Bounded source extraction can run asynchronously with explicit
queued/partial/failed/ready coverage. Failure must not present partial edges as a
complete new index. Old-version edges remain inspectable; current lookup follows
current origin versions. Mention cycles are allowed independently of forbidden
derivation cycles. Undo preserves historical text and bindings.

L08. Coherent workbook snapshots and portable archives include bindings,
relationship Records and unresolved states. Migrations/rebuilds preserve identity,
locators and current/history scope. Missing/withdrawn targets remain explainable.
First scope is one workbook. Foreign-workbook references remain explicit external
or unresolved links, never automatic filesystem/network access, global resolution
or new search authority. Copying a workbook preserves or consistently remaps its
internal workbook identity without changing bindings.

## Native interaction

L09. Voice/text requests such as 'Link this explanation to the supplier quote',
'Where is this mentioned?' and 'What used this assumption?' use the same scoped
core as native controls and CLI. Resolve pronouns from visible context; clarify
consequential ambiguity only. Clear linking intent authorizes the reversible edit
without redundant confirmation. An AI-generated draft may contain exact links to
inspected inputs without accepting a business claim. Users need no wiki syntax or
relationship vocabulary. Existing document-edit authority/version rules still apply.

L10. Readable inline links support keyboard and VoiceOver. Open in the temporary
right-pane viewer with state-preserving Back, retaining drafts, reading position
and prior space. Navigation works without inference and creates no extra space or
conversation. Show unresolved targets with explanation and optional resolution.
Expose 'Mentioned in', 'Used to calculate' and later 'Possibly related' on demand;
keep uncertain suggestions separate from provenance. No mandatory third pane or
graph canvas. Existing URI allowlists apply; unsafe routes remain non-actionable.

## Agent search and scale

L11. Add bounded incoming/outgoing-reference tools and equivalent app/CLI queries
with typed filters, deterministic ordering and keyset pages. Results identify
origin/target versions or logical-target mode, locator, relation, resolution and
index coverage. Combine traversal with FTS/structured queries. Deduplicate evidence
by version and retain discovery reason. References are additional retrieval paths,
not proof of exhaustive search or automatic destination inspection.

L12. Enforce workbook, conversation-access, scenario, status and history boundaries
at each expansion. A link never widens conversation access. Bound hops, fanout,
rows, bytes and time; cancel/page without loading the graph or huge bodies. Read
original destinations before citing and apply existing citation checks. Repeated
mentions are not independent corroboration. Imported instructions remain evidence,
not commands; finding a relationship grants no mutation authority.

L13. Parse changed body versions incrementally. Extract supported imported formats
in bounded background jobs. Avoid graph rescans on keystrokes and all-pairs model
inference. Later suggested associations start with bounded title/alias/identifier
matches and on-demand analysis. Retain ambiguity, provenance and dismissals; never
merge similar names or treat model confidence as truth. Persistent substantive
claims become proposed Records under L02. Measure retrieval value, false matches,
latency and memory before promoting richer suggestions. No separate vector or
graph database is a prerequisite.

## Implementation and acceptance

L14. Deliver in dependency order within the existing plan:
1. Version-safe canonical storage, migrations, resolver and annotation history.
2. Incremental parsing, indexes/backlinks, coverage and rebuild/recovery.
3. Native links, resolution and preview; voice/text and shared-core CLI operations.
4. Bounded agent traversal and complete evidence-inspection journeys.
5. Optional inferred associations after a separate evaluation.

Only document new commands in the installed skill once implemented and verified.
Update the repo-owned skill and CLI documentation during delivery. Design adoption
closes no runtime acceptance gate and does not displace or relax existing Splash,
context or release qualification.

Required first-slice acceptance cases:
- LJ01: link, rename target, introduce duplicate title, reopen and rebuild; retain
  the original binding and label.
- LJ02: retain and later resolve/correct ambiguous or missing targets; preserve
  prior bindings and original bytes without fabricating items.
- LJ03: supersede input; live navigation may show the new head, while old citations,
  pinned results and derivations open their exact historical versions.
- LJ04: edit/undo/retry with competing writers and injected failure; refuse stale
  publication, orphan/partial edges and duplicate operations.
- LJ05: Unicode, aliases, escaped brackets, code examples, malformed routes,
  locators and unsupported inputs retain correct parsing and coverage limits.
- LJ06: page a high-fanout cyclic mention graph; verify direction, deduplication,
  scope, history and cancellation. No repeated link multiplies evidence or effects;
  derivation-cycle checks remain independent.
- LJ07: voice/text, native keyboard/VoiceOver and narrow-window journeys link,
  resolve, preview and go Back without losing draft/space/reading state. Record
  actual hardware/accessibility limits; do not simulate success.
- LJ08: offline portable export/reopen, migration and rebuild preserve historical
  bindings, pinned citations, included assets and unresolved links.
- LJ09: local agent follows bounded hops, reads originals and cites correctly;
  misleading mentions, hidden scopes and suggested relations cannot become accepted
  facts, conversation access or business effects.
- LJ10: compare lexical-only and reference-assisted retrieval with useful/misleading
  links, duplicates and missing indexing; report correctness, coverage, latency and
  peak memory. Preserve failures. Earlier 100k FTS results do not qualify graphs.

## Related specifications and research

[[records/specs/storage]], [[records/specs/search]], [[records/specs/product]],
[[records/specs/intelligence]], [[records/specs/distribution]] and
[[records/operations/implementation]] retain their surrounding contracts.

Obsidian separates explicit and unlinked mentions and supports aliases/previews.
Notion uses structured relations for rollups. These are interaction precedents,
not evidence of Sevra's usability or performance:
[Obsidian backlinks](https://obsidian.md/help/plugins/backlinks),
[Obsidian links](https://obsidian.md/help/links),
[Obsidian aliases](https://obsidian.md/help/aliases),
[Notion relations](https://www.notion.com/help/relations-and-rollups).

## Explicit-binding foundation, October 28

Schema 5 adds canonical `reference_sets`, `reference_heads` and
`reference_bindings`, separate from derivation lineage. Each annotation snapshot
retains its exact origin version, body hash, selected label/scalar locator, stable
reference identity, target mode/identity, prior snapshot and choice Source.
The package manifest identity is copied into SQLite and checked on open; copying
or exporting a workbook retains both. Canonical schemas 1 through 4 migrate in
one transaction. A mismatch refuses rather than retargeting local references.

Implemented Swift APIs are `referenceSnapshot`, `annotateReferences`,
`resolveReference` and keyset-paged `referenceHistory`. `addItem` and
`editDocument` accept optional explicit reference selections and publish the
body, choices, bindings and receipt atomically. Record bindings are immutable with
the text version: correcting them requires a new document version. Source choices
have their own annotation versions and new annotation Sources without changing
the original text, head, asset or derivation edges. Nil expected snapshot means
none may exist; a competing writer refuses. Idempotent retries return the original
snapshot even after later corrections. No mention creates a business effect.

Selection establishes identity. Live targets require an existing logical ID;
pinned targets require an existing exact version ID. Labels and lookup hints do
not resolve names, even after new or duplicate titles appear. Unselected mentions
stay unresolved. Foreign-workbook identities stay external and do not open files,
network connections or another workbook. Navigation returns bounded target
metadata and an exact version to inspect, not the destination body or citation
eligibility. These APIs are not yet agent traversal tools.

The initial core supports at most 128 explicit occurrences in a body of at most
1,000,000 UTF-8 bytes. Each selected label is at most 1024 scalars and 1024 UTF-8
bytes; lookup hints are at most 1024 bytes. Coordinates are exact Unicode scalars,
ordered and nonoverlapping. Invalid spans, targets, stale choices or write failures
roll back the whole mutation. Ordinary text saving remains available above these
annotation limits. Existing versions are not scanned or rebound on migration.

Identical body bytes carry bindings through status changes, renaming, separate
copies and Undo, retaining the prior annotation snapshot as provenance. Changed
free text without explicit selections now receives its own bounded body parse; old
bindings remain on the original version and are never silently realigned. Migrated
untouched versions remain `not_indexed` until explicitly caught up. Manual
selections report `partial` coverage, including an empty set. They do not claim a
complete mention parse or a complete backlink index. Workbook verification checks
all retained snapshot chains, body/label bytes, selection Sources, inherited
bindings, targets and heads. Search-index rebuild does not reinterpret bindings.

The next section supersedes the foundation-only parser, backlink and CLI status.
The later extracted-text section supersedes the extraction status. Next implement
native/text/voice interaction and bounded scoped agent traversal. LJ01-LJ10 remain the full first-slice contract; the focused core
evidence establishes only the cases recorded in
[[records/operations/implementation]].

## Body parser, index and CLI, October 28

Schema 6 adds rebuildable `reference_index` rows and per-exact-version
`reference_coverage`, separate from canonical snapshots. Canonical schemas 1
through 5 migrate transactionally. Migration copies existing bindings without
parsing old text, inventing new Sources or resolving names. Keep the app and CLI
matched; older builds refuse schema 6.

The shared `InlineReferenceParser` uses pinned official Swift Markdown 0.9.0
and swift-cmark 0.9.0. Swift 6.2 is the minimum build toolchain; the verified host
uses 6.3.3. The native package includes both dependencies' license notices.
Supported body syntax is double-bracket wiki links with an optional pipe-separated
alias, and Markdown links whose destination is one of these strict stable routes:

- `sevra://item/VERSION_ID` pins an exact version.
- `sevra://logical/LOGICAL_ID` follows the current head.
- `sevra://workbook/WORKBOOK_ID/item/VERSION_ID` or `/logical/LOGICAL_ID`
  retains explicit workbook identity; a foreign workbook is not opened.

ASCII identity tokens are bounded and case-preserving. Scheme/route keywords
are case-insensitive. Queries, fragments, percent escapes, path traversal,
userinfo and extra path components are refused as stable routes. Ordinary web
links remain ordinary Markdown; this parser does not fetch or capture them.
Names and paths remain unresolved lookup hints. A stable local route binds only
if the exact target exists at initial publication; a missing target stays
unresolved after later creation, catch-up or rebuild. Explicit correction
creates a new annotation/version rather than changing the historical parse.

Markdown supplies code, image, HTML and link boundaries. Escaped wiki openings,
fenced/indented/inline code, image labels, HTML blocks and inline code/pre/script/
style spans do not produce mentions. Labels retain their exact raw body scalars,
including any Markdown formatting. UTF-8 parser columns map back to original
Unicode scalars, including CRLF, emoji, combining marks and NUL. The original
body is never normalized. Some upstream source locations are ambiguous when
content directly follows a reference definition. Sevra publishes no edges for
that parse and reports `partial`, with guidance to separate the content by a
blank line. Missing locations and the 50,000-node traversal bound also fail
closed. The AST itself is built for the bounded body before that traversal;
this is not a measured whole-app memory guarantee or interruptible cmark call.

The existing 1,000,000-byte body, 128-occurrence and 1024-byte label/lookup bounds
apply. Excess occurrences retain a partial bounded set. Malformed tokens remain
plain text with partial coverage; oversized bodies report `unsupported`. Ordinary
text saving still works. An eligible new or edited body publishes its parse,
coverage, bindings and operation in the same transaction. Internal rows, request
captures and annotation Sources are excluded from automatic body indexing.
Manual selections retain partial coverage. A completed empty parse is `ready`
for supported item-body syntax, not proof that the whole document or workbook
contains no other mentions.

`indexReferences` explicitly catches up one stored exact version and retains
its original result on an idempotent retry. `indexReferenceBodies` processes at
most 50 unindexed eligible versions per ID-keyset page, committing complete
origins independently so interruption can resume. It skips completed coverage;
it does not replace annotations. `rebuildReferenceIndex` recreates lookup rows
from current canonical annotation heads. It never reparses text, resolves a name
or creates new choice Sources. Integrity checks compare canonical bindings and
projection in both directions, current-origin flags, coverage, exact locations
and parse routes. Changing a current head changes the prior origin's index flag
in the same transaction. Historical versions and annotations remain inspectable.

`referenceLinks` is a bounded, metadata-only, one-hop owner API. Incoming results
deduplicate exact origin versions; outgoing results deduplicate exact destination
versions. Each hit has a first occurrence/locator and mention count. Results
contain no destination body or read/citation receipt. Incoming discovery defaults
to current origins and logical target identity, including pins to that logical
item's older versions. `targetScope: exact` includes pinned matches to that exact
version and live matches only when that version is current. Historical origins
are explicit. Kind, meaning, status and scenario filters apply to incoming
origins or outgoing destinations. Unknown option fields or invalid option types refuse.

Pages contain at most 50 hits; outgoing grouping inspects at most 128 stored
occurrences. Incoming queries use covering target/current-origin/ID indexes.
Keyset cursors bind workbook, anchor, direction, scope, filters and revision.
Receipt/message/context-only journal suffixes can continue an unchanged page;
unknown mutations or changed evidence require a fresh query. Cancellation, a
maximum three-second deadline and bounded fields apply. These owner APIs do not
implement a scoped model tool or grant conversation access. Extracted asset text
and unsupported/unindexed versions are explicitly outside complete coverage.

The CLI exposes `references`, `backlinks`, `reference-snapshot`,
`reference-resolve`, `reference-history`, `annotate-references`,
`index-references`, `index-reference-bodies` and `rebuild-references`. `add` accepts
explicit `references`; `edit-document --references JSON_FILE` publishes selected
bindings with the new Record text atomically. Annotating a Source requires an
explicit `expectedSnapshotID` (null for the first set); a Record needs a new text
version. Commands and the repo-owned harness skill document the distinction
between discovery, reading and business authority.

This slice does not qualify L01-L14 or LJ01-LJ10 as a whole. Extracted-input
locators, native link rendering/resolution and Back, voice/text journeys, scoped
agent tools and original-read enforcement, real local-agent retrieval comparisons,
large-graph latency and peak-memory evidence remain open. See
[[records/operations/implementation]] for focused verification and retained failures.

Primary parser contract: [CommonMark links](https://spec.commonmark.org/0.31.2/#links),
[official Swift Markdown](https://github.com/swiftlang/swift-markdown/tree/0.9.0),
and [SQLite multi-column indexes](https://www.sqlite.org/queryplanner.html#multi_column_indices).

## Retained extracted-text annotations, schema 7, October 28

File mentions are canonical technical annotations over retained extraction input,
separate from original asset bytes, Source body and replaceable overlapping FTS
chunks. `file_reference_inputs` retains exact bounded regions/locators, origin
version, asset ID/hash, extractor identity/state/detail, content hash and truncation.
`file_reference_sets` retains versioned parser/coverage, canonical binding JSON,
prior snapshot and annotation Source; `file_reference_heads` selects each exact
origin's current annotation. `file_reference_index` is the rebuildable covering
incoming projection. `extraction_attempts` guards worker publication. No new
business Record is created per occurrence and no file asset is stored as a BLOB.

The shared wiki/stable-route parser operates on each retained region before FTS
splitting. Locations are zero-based Unicode scalar spans within that immutable
region, plus the extractor's page/sheet/row/text locator. PDF page text can thus
retain coordinates across chunk rebuilds without pretending they are PDF glyph
coordinates. Embedded PDF annotations, Office relationship hyperlinks, media
links outside extracted text and other unextracted content are not parsed. Ready
means supported syntax in the captured input was processed, not that every link
in the original file exists in the index. OCR text remains fallible. Parser
limitations described above still apply.

The initial per-origin bounds are 512 retained regions, 1,000,000 total UTF-8 text
bytes, 64,000 total locator bytes, 1024 bytes per locator and 128 occurrences.
Excess input/occurrences report partial coverage. Retained text is cut only at a
Unicode scalar boundary. Unsupported extraction publishes unsupported coverage.
Failure/cancellation preserves the last committed search index and annotations;
the latest extraction attempt is reported separately from the captured snapshot.
There is no claim of whole-app memory qualification or arbitrary-file coverage.

New extraction publishes search chunks/status, retained input, complete bounded
annotation set, Source, projection and receipt in one transaction. Competing
workers carry attempt identities: an older completion or failure cannot replace a
newer's text, bindings or status. Returning to identical captured input preserves
its latest explicit choices, including unresolved choices. Changed input creates
a new snapshot; old regions and annotations remain inspectable. Unchanged assets
carry bindings through exact Source version changes and Undo. Index rebuild
copies canonical bindings without parsing or changing destinations. Canonical
schemas 1-6 migrate without running extraction or guessing file links; migrated
file origins remain unindexed until explicit extraction. Schema 7 requires a
matched app/CLI build.

`fileReferenceSnapshot`, `fileReferenceHistory`, `fileReferenceRegion` and
`resolveFileReference` expose bounded owner inspection. `annotateFileReferences`
requires an exact Source version and the nonnull current snapshot, records a new
partial manual selection set and supports exact idempotent retry. Selections are
region-relative and replace the complete current chosen set. They preserve the
original asset and Source. They do not create read/citation proof for the model.
Verification checks retained hashes and asset identity, bounded original spans,
annotation Sources/chains/inheritance, stable parse targets and both directions
of the derived projection. Corruption refuses rather than silently repairing
canonical input; explicit rebuild repairs only derived lookup rows.

`referenceLinks`, `references` and `backlinks` now merge body and file mentions
before pagination and deduplicate exact versions across both. `contentScope` is
`all` by default, or `body`/`extracted`; it participates in the cursor identity.
Incoming queries use two bounded indexed prefixes and merge before the page.
Outgoing grouping is bounded by at most 256 combined occurrences. Hits report
`discoveryScopes`, total mention count and first locator/snapshot kind. Coverage
metadata describes the requested anchor, not an exhaustive workbook-wide absence
claim. Other files may remain unindexed. Filters and current/history/exact-target
rules continue to apply to both scopes, with no external IO or permission expansion.

CLI inspection uses `file-reference-snapshot`, `file-reference-history`,
`file-reference-region` and `file-reference-resolve`. `annotate-file-references`
provides explicit Source correction; `extract` explicitly retries/catches up one
exact file version. See [[records/operations/build-and-run]] and the repo-owned
skill for argument shapes. The focused core and packaged CLI evidence is recorded
in [[records/operations/implementation]]. Native links/resolution/Back, voice/text
authoring, scoped local-agent traversal/read enforcement and LJ07/LJ09/LJ10 remain
open. This slice does not qualify complete L01-L14 delivery or app release.


## Native reader and navigation slice, October 28

Supported saved body links now render as their readable labels. Display-only token
boundaries hide recognized wiki/Markdown wrappers; destinations still come from
canonical versioned bindings. The reader verifies exact body hashes and scalar
labels. Code examples and external web syntax remain literal here. Its private
native action URLs identify saved occurrences and are intercepted against that
exact rendered set. No raw input route opens a file, website or another workbook.
Rendering changes neither original bytes nor copied-passage evidence.

An optional Links sheet in the existing right viewer shows links in this document
or Mentioned in. Incoming discovery uses bounded 20-result keyset pages, current
origins by default, with explicit earlier-origin and exact-target filters. Failed
next-page reads retain the current page. Scope changes cancel and invalidate old
results. Coverage copy distinguishes missing indexed text from a proven absence;
mentions establish navigation, not payment, derivation or corroboration. A missing
body annotation can be explicitly checked without inference. Embedded hyperlinks
and unextracted content remain outside this captured coverage.

Choose destination searches the workbook and requires an explicit item selection.
By default it follows that item's logical identity; Keep this exact version pins
it. The complete saved occurrence set is retained while only the chosen binding
changes. Source/body and retained file-text choices create versioned annotations
without changing Source or asset bytes. A Record text-document correction creates
a new draft version. Other Record types still require their domain version
workflow. Leave unresolved is explicit; duplicate titles never auto-bind. Stale
snapshots refuse and exact retries preserve the original operation.

Text or dictation of Show links, Where is this mentioned? and Go back invokes
exact whole-request shell commands without loading the model, including while a
model turn is busy. Corresponding Spanish phrases are supported. This is a small
command vocabulary, not general natural-language authoring, pronoun resolution,
new-span selection or complete voice equivalence. Native controls remain optional.

Opening a saved occurrence uses the normal temporary right-pane viewer. Back also
has Command+[ and flushes drafts before leaving. Window-owned exact-item reading
positions restore native body scrolling, proportionally after reflow. PDF page
navigation retains current pages; a new page locator in the same file is applied
without reloading it or resetting manual reading on unrelated updates. Open
original passage now forwards its saved locator as well as the exact version.
Media time/image zoom and durable across-relaunch item reading positions are not
qualified by this slice. A failed draft flush cannot alter the requested locator.

Link reads, resolution and paging run off the main actor with deadlines and
cancellation. Superseded/cancelled requests cannot replace another exact preview;
wrong-origin results refuse. Choosing links uses existing authority, transaction,
stale-version, receipt and retry rules. Binding-only Record document revisions
retain exact-copy metadata only when text bytes are unchanged, references are
explicit and the operation is not a separate copy. Free-text edits still discard
those spans. See [[records/specs/document-composition]].

Focused evidence and preserved failed attempts are in
[[records/operations/implementation]]. Native scroll/PDF tests are programmatic
checks of real AppKit/PDFKit objects. The Mac UI tool remains locked; readable
inline keyboard activation, actual VoiceOver, narrow-window layout, saved-copy
navigation and full LJ01-LJ10 remain unqualified. Scoped agent traversal, reading
destinations before citation and real retrieval-value comparisons are still next.
The official SwiftUI contracts used are Apple's
[AttributedString Text initializer](https://developer.apple.com/documentation/swiftui/text/init%28_%3A%29)
and [OpenURLAction handler](https://developer.apple.com/documentation/swiftui/openurlaction/init%28handler%3A%29?language=_6).


## Scoped agent traversal and canonical reads, October 28

The shared model tool set now includes read-only `references`. Each call is one
hop, with at most 12 metadata results, a three-second query deadline, cancellation
and revision/journal-bound keyset continuation. Options are exact item version,
incoming/outgoing direction, logical/exact target scope, current/earlier origins,
all/body/extracted content and kind/meaning/status/scenario filters. Keep the same
options with the returned cursor. Incoming queries use the existing indexes;
outgoing work is bounded by the 256 combined saved occurrences. Filtering and
version deduplication happen before pagination. The ordinary agent step/context
bounds govern multiple calls; no automatic recursive walk or global visited-node
scheduler is implemented.

A business `read` also includes `references`, the first canonical outgoing page
from that same database read snapshot. This is discovery metadata about saved
bindings, separate from the original body/chunks and exact-copy passages. Follow
its nextCursor through the references tool. A corrected binding can point somewhere
other than the original raw URI. The original bytes remain unchanged and visible.
Raw internal routes found only in read/tool_result text do not add target IDs to
the lookup-choice vocabulary. Structural metadata and independent discovery do;
explicit current-user routes and earlier conversation keep their own lookup
semantics. A separately discovered or explicitly supplied target can still be read
within scope. This is not fuzzy redirection or a prohibition on reading another
business item.

Reference titles, locators, links and nested read.references never establish
inspection of a destination. Both adapters share exact candidate validation;
native decoding constrains the same choices. Finish citations still require
inspected evidence. Historical business citations continue to require inspection
of their current head and retain the historical-version note. Mentions are not
payment, support, derivation, corroboration, acceptance or proof of absence.

Agent reference pages exclude request Sources and technical annotations before
paging, including as anchors. Agent FTS excludes those kinds even under an explicit
kind filter, and agent lineage excludes their edges. Direct item reads allow only
business items and this run's immutable current submission. Earlier conversation
uses scoped history_read, including only an explicitly inherited parent excerpt.
A link or UUID cannot widen it. A later private request head is neither disclosed
by currentVersion nor made a required citation refresh for this run's original
submission. Other business-version refresh rules are unchanged. Owner Workbook
APIs and CLI queries retain their separate inspection capabilities. These focused
rules are not a qualification of every tool or a general side-channel claim.

Agent results omit raw lookup routes, so a foreign-workbook destination cannot
be reinterpreted as a local ID or opened automatically. Names remain discovery
terms. No model binding mutation or general span authoring was added.

Focused evidence: 132 core checks; deterministic actual-agent traversal over a
real cycle, corrected extracted pin, current-head refresh, metadata-only citation
refusal, 25-origin 12/12/1 incoming pages across saved receipts, scope/cursor/option
refusals, private-request bypass attempts and concurrent request-head isolation.
Actual grammar checks cover 33 tools, 39 cases and 329 exact upstream reference
masks, plus dynamic references/read/lineage choices with reasoning on/off.

The native 32K/bounded512 local-pack probe initially answered from the wrong raw
URI twice. The final corrected-binding journey reads both original and revised
editions, answers weekdays versus weekends, preserves all business items, and
passes portable reopen. It takes six model steps with one opaque-ID finish
correction. Its separate private-request journey reveals no hidden title/content,
explains the unavailable original, and completes in eight steps. Both unload the
native model. The first private run hit the step limit; that failure remains.
These two observations do not qualify general reliability, latency, memory,
large graphs, fresh installation, engine adoption or LJ06/LJ09/LJ10 in full.
See [[records/operations/implementation]] and [[records/reviews/design-passes]].


## Visible native navigation and keyboard correction, October 28

The owner-unlocked preview is accessible. Native item text exposes a dedicated
accessibility representation with readable text and ordinary link controls over
saved occurrence identities. Visual inline text remains selectable. This avoids
relying on synthesized attributed-text link children whose press action failed
in the actual preview. These controls never open a raw source URI.

Command+Shift+L opens Links in This Document for the focused workbook's current
item. The Workbook menu also offers Where Is This Mentioned? The menus are disabled
without a viewed item. In the sheet, arrow keys select an outgoing link or incoming
mention and Return opens that exact selected entry. Stale selections absent from
the current result set cannot activate. Command+Option+E opens destination choice
for the selected editable occurrence; named native action controls are also
available. Escape cancels. These are optional access paths to the existing core.

Destination search uses an AppKit field that requests initial focus only when
attached to its own sheet window. Typing starts immediately, Down selects the
first currently visible result and moves to results, and Return saves only an
explicitly selected result. Empty Return does nothing. Query changes discard
selection, and results/cursors from another query are hidden and refused for
selection. A matching title alone still never binds automatically. Search, result
choice and version mode use the same explicit binding workflow as pointer input.

Focused visible observations cover body link activation through accessibility,
a corrected extracted pin opening the historical weekdays edition, explicit
current weekends navigation, Back through those views, incoming 20/6 pages and
20/5 exact-version pages, previous-page recovery, keyboard incoming activation,
and two keyboard-selected Source corrections. CLI inspection proves unchanged
Source bodies/assets, unchanged pending records, correct live destinations and
portable reopen/integrity. The copied-passage disclosure opens the exact text
original and returns to its unchanged draft. That view fits the 820-point minimum
window width with ordinary vertical scrolling. These are agent-operated synthetic
observations, not uncoached usability, a spoken VoiceOver pass or all formats.

The UI also exposes technical annotation Sources in Recent work and destination
search. Hiding that implementation noise from normal business views needs a
separate query-boundary correction, while keeping explicit owner inspection.
No new model tool, schema, engine, acceptance or external access is added here.
See [[records/operations/implementation]] for failures and measured limits.

## Next general text and voice authoring slice, planned

The existing control corrects saved occurrences. Natural requests to link any
passage still need bounded exact-text discovery and mutation tools. Do not ask the
model or user to count Unicode scalars. Plan the following shared-core boundary:

- Find exact text in the active exact item body's or retained extracted regions'
  bounded snapshot. Return a small page of occurrence choices with neighboring
  context, region/locator and immutable selection proof. Preserve combining
  characters, emoji, NUL and line endings without fuzzy normalization. Repeated
  passages remain distinguishable and require clarification when intent is unclear.
- Bind agent choices to a completed current-run/current-conversation discovery
  receipt and the actually visible choice vocabulary. History, source instructions,
  invented IDs, metadata-only traversal and other runs cannot mint edit choices or
  citation eligibility. Read-only request restrictions still deny mutation.
- A save revalidates the exact body or retained input and expected binding snapshot,
  preserves other occurrences and reference identity for an exact-span correction,
  and refuses partial overlap or stale evidence. It cannot silently move to a new
  extraction or head. Keep stable idempotent retries after intervening changes.
- Source text and asset bytes stay immutable. An eligible Record text document
  creates a normal draft with byte-identical prose, preserved valid copy provenance
  and normal lineage. Other Record kinds require their domain edit workflow. A
  destination mention is not a derivation input or a business acceptance.
- Follow the chosen logical destination by default; pin an exact version only when
  requested. Missing/duplicate targets and ambiguous passages need actual choices,
  never automatic title rebinding. Unresolved is distinct from removing an occurrence.
- Qualify Unicode, repeated/overlapping matches, bounded paging/cancellation, stale
  snapshot/query/target behavior, imported instructions, cross-run/conversation and
  read-only refusal, retry/export/reopen, dynamic grammar/host parity, then real
  native-model text requests and dictation. These are planned gates, not passing
  evidence. Broader embedded hyperlinks and LJ10 comparisons stay separate.
