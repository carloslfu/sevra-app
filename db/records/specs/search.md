---
type: spec
meta-type: conclusion
id: 01m5rbxzajb661yc3bj5xatkxj
created: 2026-10-25T01:48:47.314196+00:00
updated: 2026-10-29T18:54:58.412663+00:00
summary: FTS5, structured and filename indexes, bounded extraction, exact citations, agent query refinement and measured scalability.
title: Ingestion and agentic search
status: reviewed
---
# Intake and search

## Retrieval contract

Q01. Agentic search is an iterative tool workflow over indexes. The model can search,
filter metadata, read a bounded item/page/chunk, follow lineage, refine a query,
and synthesize a cited answer. It must never load the whole workbook into context.
Exact lexical search works before model setup and remains directly usable.
Q02. FTS5 indexes titles, body chunks and captions with Unicode tokenization,
diacritic normalization and prefix search. BM25 ranking weights titles above body;
snippets identify matched passages. Separate filename/alias trigram index supports
partial names; structured B-tree indexes cover kind, meaning, status, scenario,
time, asset hash, logical/version identity, parent/child and dataset row order.
Q03. External-content FTS tables are maintained transactionally by canonical
triggers. Explicit rebuild and integrity checks exist. No stale result claims:
indexing status is queued/running/ready/partial/unsupported/failed, with version
and parser identity. New metadata becomes searchable immediately; content follows.
Extraction status describes content coverage independently of included/linked
asset ownership. It must not claim a file was copied just because extraction ran.
Known legacy native status messages are normalized on read across UI, tools and
intake listings without rewriting stored evidence or operation history.
Q04. Each chunk points to an immutable item/asset version and locator (page, row
range, text offset, time range). Chunk limits bound per-tool output, not silently
claimed document coverage. Deduplicate results by evidence version, return offsets
or cursors, and expose facets/counts without loading all matching rows.
Q05. Query language is a typed API. Ordinary user text is safely tokenized/quoted;
advanced FTS syntax is explicit. No raw SQL from an LLM. Bound term count, query
length, results, page size, traversal hops and context bytes. Escape highlights
before rendering. Empty/hostile queries must never crash or expose another file.
The current lexical API requires all query words to match. Agent-facing guidance
starts with short distinctive names or filename fragments and broadens an empty
query by removing words. Extra generic terms such as document or original can
exclude the very quotation being sought. Before calling a requested supplier term
unknown, inspect related originals instead of treating an imported row as complete.

Q06. Agent search traces list queries, inspected evidence and omissions. A zero
match is different from incomplete indexing. The answer must say when sources
were unsupported, truncated or absent. A summary is derived content and cannot
replace its cited original. Citations are validated against retrieved version IDs.
Q07. Optional semantic retrieval is not a substitute for lexical/structured search.
First version uses agent query expansion and deterministic lexical indexes;
embedding/reranking adds a versioned replaceable index only after a measured
recall/latency improvement. No network embedding service. Model synonyms can
improve recall but must not be presented as exhaustive proof of absence.

## Managed dataset queries and indexes

Adopt [[records/specs/managed-datasets]] M07 and MJ05. Structured table filters,
ranges, sorting, joins and aggregations compile against registered native columns
and stable logical IDs. Managed ordinary/composite/partial indexes serve measured
access paths; query plans must demonstrate use. Ordinary views rely on underlying
table indexes. Bound index count/size, query work, pagination and cancellation.
The agent can request managed operations only when exposed by the core; arbitrary
SQL/DDL and reserved-schema changes remain unavailable.

Semantic constraints are versioned definitions. Pure performance indexes/FTS are
rebuildable local projections, with retained authoritative content and exact version
citations. Search does not become a separate writable source of truth. Record
correctness, latency, memory and storage before claiming improved scale; the current
shared-row implementation is not evidence of delivered native dataset indexing.

## Intake

Q08. Drag/drop, native file picker, CLI import, pasted URL and voice/text instructions
converge on an import job. Include by default; preserve filenames, origin and time.
Multiple items have independent progress/errors. Idempotent job retries cannot
create duplicate business effects. Importing evidence does not automatically
accept extracted financial/business events.
Q09. Plain text/Markdown/CSV/TSV/JSON/HTML, PDF text, image OCR, basic DOCX and XLSX
get explicit extractor paths. PDFKit extracts per page; image/scanned-page OCR
uses Vision locally. CSV quoting, multiline fields, BOM, CRLF, duplicate/empty
headers and locale ambiguity have tests. Current XLSX intake retains cached values
and basic cell types; it does not execute retained formulas or qualify continuity.
The expanded adopted design in [[records/specs/contextual-import]] separates the
requested role from file format and requires reported translation of supported
Excel structure/behavior. Originals remain immutable; unsupported features stay
visible. CSV is an ongoing working/reference/analysis/update input as well as a
possible start. Checkpoint 63cd642 removes automatic suffix-based table creation;
explicit roles and saved-values conversion are available while broader update and
Excel-continuity work remains open. Under [[records/specs/persistence-readiness]],
retain exact extracted content/locators used as evidence and transformation identity.
Reconstruction rebuilds indexes from that authority without rerunning extraction
or changing historical citations.
Q10. Audio/video are included or explicitly linked, previewed natively and indexed
by metadata. On-device transcription is capability-gated and its timestamps index
only after successful recognition; no fabricated transcript. A recording of up to two
hours is divided into overlapping parts of 58 seconds, each transcribed on this Mac, and
words heard twice in an overlap join once. Timestamps stay those of the original. Nothing
is indexed until every part finishes, so Stop leaves the original as it was and a retry
starts over. A silent part is skipped. Recognition uses the Mac's language. Encrypted/unsupported
files remain browsable and have actionable extraction status. Never recursively
expand arbitrary archives during evidence intake. Explicit ZIP intake can select
members through a bounded reviewed import operation.
Q11. Extraction has resource limits: bounded input/output bytes, page count, decoded
image dimensions, decompression ratio and deadline. Large copies stream; large
structured imports batch with resumable job state. Work is off the UI thread with
one inference queue and bounded extraction concurrency. Cancel leaves original
bytes intact and reports actual processed coverage. Extraction never executes
macros, embedded scripts or linked network resources.
Q12. Evidence URL capture preserves included bytes and safe origin/retrieval time.
Ordinary data URLs stay links. HTTP(S) only, no recursive crawl; redirects checked,
content type/size bounded, cookies/credentials not imported from unrelated apps.
Strip credential-bearing URL fields from portable metadata without inventing an
incorrect origin. Failed/authenticated captures remain explicit references.

## Scale and measurements

Q13. Search uses indexes, keyset pagination and result limits; database readers do
not materialize entire documents or datasets. App uses paged/virtualized views.
Cold start reads manifest and counts, not every asset hash. Integrity verification
is explicit or targeted to accessed/imported content, with lazy status reporting.
Q14. Check representative synthetic corpora at 10k and 100k chunks; publish size,
hardware, ingest time and cold/warm p50/p95 query latency. Target warm indexed
search p95 <200 ms at 100k chunks on the reference Mac, excluding inference.
This is a target until measured. Test 1GB+ assets with bounded resident memory.
Q15. Recall fixtures cover accents, filenames, rare identifiers, mixed languages,
phrase/prefix queries, duplicated evidence, corrections, hidden old versions,
partial OCR and unrelated distractors. Agent evaluation checks multi-step
search/read/cite, no-match honesty and resistance to instructions in documents.

## Shared agent search across evidence and conversation

The agent's unfiltered first search page discovers both current business evidence
and older original messages in its current conversation. Keep them distinct:
top-level hits contain item versions, and conversation.hits contain message IDs.
The latter are candidates only; history_read must expose an eligible original
before a message:ID citation can support a statement about earlier conversation.
A message citation never becomes business lineage or proof of current acceptance.

Business kind, meaning, status or scenario filters deliberately exclude messages.
Business continuation pages also stay in that index. Every result says whether
conversation was searched. Its separate cursor continues through history_search
with the same query, conversation and active-request ceiling. Current-request and
later messages, sibling tangents and unselected parent history are excluded.
Business evidence remains workbook-wide. The two indexes share one read snapshot.

Both searches remain bounded: at most 12 business hits and 8 message candidates
per broad agent search; existing separate history pages and result receipts handle
continuation. Model-visible output remains bounded by the tool projection. No
whole conversation or workbook load, semantic embedding, schema migration or
external service is introduced. Each index retains its existing query deadline.

A match in either domain interrupts the consecutive-empty-search limit. A bounded
no-match response identifies document extraction coverage and whether its queries
also searched conversation. Neither no match nor complete indexing proves that
the requested fact is absent. CLI search and saved search components retain their
business-evidence API; CLI history-search remains the explicit conversation API.

Business search cursors include an operation-journal anchor. A next page can
survive only append-only message, tool-preparation, tool-completion and context
checkpoint writes since that anchor. It validates the anchor identity/revision
and examines at most 4,096 subsequent journal rowids through SQLite's rowid index.
Business changes, unknown mutation kinds, invalid anchors or a longer interval
require a fresh query. Legacy cursors retain their strict revision check. This
prevents the agent's own receipt writes from breaking every multi-page search,
without ignoring evidence changes or introducing a database migration.

## Search completeness and exact counts
A lexical query establishes only matches for its terms and filters. An empty result or table list does not establish that a business event, file or record does not exist. Sources may be unindexed, incompletely extracted, differently worded or not yet interpreted.

The read-only count_records tool counts current heads in SQLite using an explicit Source/Record category and optional exact kind, status, meaning and scenario filters. Every result reports all filters and its workbook revision. It includes classified entries even when their text is not indexed. It does not count facts hidden inside documents, external files, historical versions or real-world events. Accepted estimates remain estimates.

finish.counts can reference up to four visible count receipts from the current run. The host rechecks the count, refuses changed/unknown receipts, renders the exact count and scope itself, and saves the verified result with the answer. Compaction invalidates count eligibility when the corresponding result leaves working context. A count receipt is not a Source/Record citation. When an evidence answer has counts and no inspected citations, the displayed answer consists solely of host-rendered counts. Discard the model prose in that presentation so a valid count cannot authorize unrelated factual claims. The original finish arguments remain in the diagnostic payload, explicitly marked host_counts; they are not the displayed answer.

A conservative final-answer guard rejects recognized English and Spanish absence/exhaustiveness claims after retrieval or under the evidence answer basis. It requests scoped query wording or the host-rendered count instead. This catches the observed inventory overclaim; it is not a universal semantic verifier or a guarantee across all paraphrases and languages. Preserve semantic review alongside deterministic and real-model tests.

Counts answer requested entry-count questions. They do not verify a balance, validate citations or establish general search coverage. The active model schema refuses the retired coverage field; historical receipts retain their original bytes and validated coverageEvidence payload. See [[records/specs/intelligence]].
## Native search result continuity
Q16. The native search view retains loaded pages, filters and the opened-result anchor when returning from a preview with the same workbook revision and query. A changed workbook, query, filter or history setting starts a new result set and invalidates the old cursor. Do not show results from one query as matches for another.

Each asynchronous read has a unique request identity in addition to its typed query. Late successes, errors and cancellation from a superseded read cannot alter the current result set or loading state. Clearing a query clears results, incomplete-index notices and errors without leaving a spinner. More-results requests cannot overlap or append an old page to a new query. A failed next page retains the already loaded evidence and offers retry.

These requirements implement the existing stable preview/Back contract in [[records/specs/product]]. They do not change search matching, index completeness, cursor validation or citation authority.

A Source preserving the current request is available for input provenance, but a
citation to it alone is not independent evidence of requested workbook facts.
An evidence-basis answer using only that Source is refused. Explicit supplied
facts may use current_request; arithmetic still requires checked calculation.
After empty searches, an unresolved answer whose citations contain only the
current-request Source uses the host-rendered query/indexing-gap report, with
no displayed evidence citations. Preserve the original finish arguments in the
diagnostic payload. Unknown or independent citations retain their existing
validation and are not silently discarded by this boundary.

## Cancelling native reads
Changing or clearing a query, closing its workbook and cancelling the view task
cancel the same token passed into the SQLite search budget. A generation check
still rejects late results from readers that finish before cancellation takes
effect. Leaving the search view cancels active work while retaining completed
pages, cursor and anchor for Back. Cancelling a continuation preserves its earlier
pages and allows retry with a fresh token. A cooperative cancellation is not a
search failure or a new empty-result claim.

## Search-scale protocol v2
The maintained benchmark runs 10,000 and 100,000 dataset rows and document chunks,
with at most 1,000 multi-chunk documents. Both corpora are required for Q14. A
first pass uses one reopened connection; it is not an OS-cold measurement. Five
warm repetitions retain every query, elapsed time, result identity and failure.
Report pooled first-pass/warm p50 and p95 using the explicit nearest-rank method;
raw samples remain available for per-query inspection. The full 100k warm p95
target remains below 200 ms. Do not compare the revised query matrix and percentile
method as if they were identical to earlier benchmark runs.

Check exact SKU/version matches, accent normalization and expected first-page
shape, partial filenames, empty results and duplicate-free evidence. Traverse all
multi-chunk document pages and compare the exact complete ID set with the fixture.
Retain the earlier numeric-sort measurement and check its maximum fixture value.
These checks do not establish semantic/agent recall across arbitrary wording.

A cancellation probe signals Stop 5 ms after the public search call starts, then
records whether that call had already returned, its outcome and stop-to-return
time. A completed fast call is an uncovered interruption case, never a pass for
interruption. Full 100k cases require an observed cancellation returning in less
than one second, an unchanged workbook revision and a successful following query.
This observes the public call, not the exact SQLite instruction at cancellation.
The 200-entry CI self-check does not enforce or qualify large-workload latency or
interruption. Its skipped cancellation target is null, with explicit required=false.

Keep unique output folders with fixtures, per-corpus reports, raw samples, source
and executable hashes, commit/dirty state, OS, processor and physical memory.
Compare final source/binary hashes with the initial identities. Failures and
missing coverage remain in the result and cause a failed full protocol check.
A source-level self-check cannot qualify physical hardware, native UI, occupied
model contexts or OS-cold performance. Run the full release binary without other
inference/build activity and review power/thermal conditions before declaring Q14
qualified. The output itself does not automatically declare performance adoption.

## Bounded snippet retrieval and measured scale
The ranking query still considers the complete matching set. Snippets are computed
only for displayed hits, grouped into spans of fewer than 4096 row IDs. Within a
group, rowid range constraints seek the FTS index and unary-plus membership filters
reuse its cursor. This avoids restarting MATCH per result while bounding sparse
ranges. The read transaction, cancellation budget, exact locators and filename-only
excerpt fallback remain intact. No recall limit or new database schema is added.

The full search-scale-v2 run on committed 48b1a30 passed on the reference M5 Pro
with 48 GiB RAM. Warm nearest-rank p95 was 136.47 ms for 100k dataset rows and
172.31 ms for 100k document chunks (1000 documents), both below 200 ms. The 10k
runs, all correctness samples and complete 1000-document paging also passed.
Cancellation interrupted active 100k searches and preserved subsequent reads.
The 36 measured source hashes and release binary stayed unchanged, the host
remained on AC with nominal thermal state, and no local build/inference overlapped.

This qualifies the stated synthetic warm-search target on this reference Mac;
first-pass measurements are not an OS-cold cache test. It does not establish
whole-app responsiveness, all corpora, semantic recall or other hardware. Preserve
the earlier failed 204/275 ms baseline and both raw archives in
integration/evidence/2026-10-27-search-scale-v2-first-full.json.gz and
integration/evidence/2026-10-27-search-scale-v2-batched-snippets.json.gz.

## Native extraction process contract

Q11a. Text, PDF/PDFKit, image/Vision OCR and document/XML text extraction run in
an adjacent native sevra-extract helper. The parent alone records extraction state
and publishes validated chunks, after checking source identity. It passes only the
source path, no workbook database or lock descriptors. This is fault isolation,
not an operating-system security sandbox. CSV/TSV and XLSX structured parsing use
the same helper boundary under Q11b below. Archives, file transcription and viewer
rendering remain separate paths with their own qualification requirements.

At most two extraction workers run per host process. A 60-second parent deadline
includes queue time; queued cancellation starts no child. The helper checks parent
liveness and a 70-second lifetime even while writing output. Cancellation or timeout
requests termination, then force-kills; a process still awaiting reap retains its
slot. Do not block the UI indefinitely waiting for kernel IO or release a slot early.

The host samples each worker's physical footprint against 1 GiB, bounds its result
stream at 64 MiB and retains at most 16 KiB of stderr. A sampled guard is not an
absolute peak-memory limit. Successful publication requires normal exit, complete
versioned JSON, exactly one result or error, bounded locators and at most 100,000
chunks / 16,000,000 UTF-8 text bytes. Invalid output, process failure or a missing
helper refuses explicitly, with no in-process fallback. Original bytes and any
previous searchable index survive failure; retry can replace only the derived index.

Before/after source filesystem operations remain cooperatively cancellable. Remote
volume stalls, concurrent inference headroom and wider hardware remain unqualified.
See [[records/operations/implementation]] for failure-injection and packaged UI evidence.

## Structured parsing process contract

Q11b. CSV/TSV and XLSX table parsers run in the same adjacent native helper as text
extraction, sharing its two-worker limit, deadline, memory/output guards, orphan
watchdog and bounded termination. Text indexing of XLSX calls the parser inside
its existing worker; it must not recursively launch another helper. The helper
returns a versioned typed result containing saved cell strings, original row
numbers, worksheet names, formula evidence and interpretation notes. It receives
no workbook database. The host validates the whole result before creating datasets
or committing resumable batches. Recheck original hashes after parsing and before
publication, including included assets. A changed original requires a new source
version. A parser failure cannot publish partial table results.

CSV/TSV accepts UTF-8 with an optional BOM, quoted multiline fields, escaped quotes
and native CRLF/LF/CR records. Preserve quoted empty records. Enforce at most 32 MB
input, 1 MB per field, 500 columns and 100,000 rows at EOF as well as delimiters.
Iterate without materializing a second character array; check cancellation during
parsing. Clipboard text still uses the bounded in-process parser, not file intake.

A complete structured result has at most 100 worksheets, 100,000 rows per worksheet,
500 columns, one million dense cell positions across all sheets and 32 MB of expanded
UTF-8 values, formulas and notes. Blank cells introduced to make rectangular tables
count toward the cell budget; repeated shared strings count at every occurrence.
Retain XLSX's 10,000-entry, 32 MB single-entry and 64 MB expanded-archive limits.
Validate row coordinates within 1...1,048,576 and bound column accumulation before
integer overflow. Missing or malformed helpers, incomplete results and limits fail
explicitly without an in-process fallback or silently truncated tables.

The host still performs typed-column inference and existing 1,000-row transactional
publication. Cancellation after committed batches preserves those batches for retry;
parsing success does not accept inferred business events. Persist running, failed
and cancelled structured-intake status independently from text-index status, expose
it in Home/CLI with Resume, and retain the current attempt identity. An older parser
finishing after a newer successful import cannot replace that newer status. Preserve
ready markers for this race; do not list them as pending. Process interruption leaves
a resumable running entry. Parsing isolation does not by itself qualify whole-app memory, all filesystem IO, archives, transcription
or viewers. Larger-than-budget files remain preserved assets with an actionable
intake error; they are not reported as fully imported tables.

## Reference-assisted retrieval

Q17. Adopt [[records/specs/references-and-relationships]] L11-L13. Incremental parsing
and bounded indexed incoming/outgoing traversal complement FTS. Preserve bindings,
origin locators, semantics, resolution and coverage. Bound hops, fanout, bytes,
time and cancellation; enforce workbook/conversation/scenario/history scope.
Inspect originals before citing. Mentions are not proof or acceptance. Optional
inferred associations require measured value and explicit uncertainty. LJ06/LJ09/LJ10
remain unqualified; prior FTS results do not qualify graph retrieval. No separate
graph or vector database is required.


## Bounded ordinary read pages, October 27

Agent read defaults to two text chunks; chunkLimit permits one to eight. The
chunkPage object reports offset/count/hasMore/nextOffset. Follow that nextOffset
for more indexed text. A page is not the whole original, and index/extraction
coverage remains a separate status. Exact-copy candidate pagination uses its own
copyOffset within the unchanged chunk offset/limit. Completed receipts keep exact
page text for immutable copy provenance. This reduces long-context read pressure
without discarding originals or treating unobserved tails as absent. The new
five-chunk regression checks all pages and an explicit eight-chunk request. See
[[records/specs/document-composition]] and [[records/operations/implementation]].

## Owner-facing reference discovery, October 28

Schema 6 body parsing, a rebuildable incoming index and deduplicated one-hop
`referenceLinks` queries now complement FTS in the core and CLI. They return
bounded metadata and mention locators, never read/citation proof. Incoming scope
defaults to current origins; historical origins and exact versus logical target
identity are explicit. Filters and revision-bound keyset cursors preserve scope.
The 260-origin synthetic pagination check is focused correctness evidence, not
a large-graph or real-agent performance result. The later schema-7 section adds captured extracted-text mentions. Scoped
agent traversal and LJ09/LJ10 comparisons remain unqualified. See
[[records/specs/references-and-relationships]] for the implemented bounds.

## Body and retained-file mention discovery, schema 7

The owner-facing reference query now combines body mentions and saved annotations
from bounded extraction text, deduplicating exact versions before keyset pages.
`contentScope` chooses all/body/extracted and participates in the cursor identity.
Incoming prefixes use covering indexes for both projections. Mention counts and
first locators do not load destination bodies or grant read/citation proof.
Coverage metadata describes the anchor only; other origins may be unindexed.

File annotations use immutable retained input rather than overlapping FTS chunk
IDs. Original asset hashes, extraction identity, page/row/text locators and exact
Unicode spans remain available after reindexing. Latest extraction status is
separate from captured coverage. An older worker cannot overwrite a newer result.
This covers supported syntax in captured text, not embedded PDF/Office hyperlinks
or unextracted content. Limits produce partial coverage; empty results cannot
prove absence. The mixed 70-origin core fixture and packaged CLI journey check
scope/dedup/history, not large-graph throughput, whole-app memory or real-agent
retrieval value. Scoped agent tools and LJ09/LJ10 remain open. See
[[records/specs/references-and-relationships]].


## Local-agent reference and technical-evidence scope, October 28

The bounded references model tool and read.references first outgoing page now
complement agent FTS. Each explicit reference query returns at most 12 metadata
results, with scopes/filters, keyset continuation, cancellation and the existing
three-second deadline. Metadata does not inspect destination content. Discovery
and read path handling preserve canonical corrected bindings while leaving raw
original text and copy passages intact. Prior empty/partial coverage caveats and
body/extracted indexes remain unchanged.

Agent lexical/filename queries exclude request and annotation Sources before
paging, even when the model supplies either kind explicitly. Owner search remains
available. Agent reference anchors/destinations and lineage use the same business
boundary; direct reads and original-message history enforce their own request
ceiling. The cursor identity includes the owner/business scope, so cursors cannot
cross it. There is no automatic multihop fanout or external-workbook access.

Focused synthetic traversal and privacy checks plus two local native observations
pass, with preserved wrong-route and step-limit failures. General LJ09, measured
lexical-only versus reference-assisted retrieval value, large-graph latency/memory
and LJ10 remain open. See [[records/specs/references-and-relationships]] and
[[records/operations/implementation]].


## Ordinary owner search and technical evidence, October 28

Default shared search excludes request and annotation kinds before lexical/filename
ranking and page limits. This keeps ordinary native evidence/destination results
free of parser events. An explicit owner kind filter can inspect either kind;
agent businessOnly scope still excludes both even when explicitly requested. No
Source, original bytes or index entry is deleted, and explicit item/history APIs
retain their existing authority checks. Cursor identity and remaining filters are
unchanged. Focused lexical/filename paging checks and native observations are in
[[records/operations/implementation]].
