---
type: spec
meta-type: conclusion
id: 01m5rbxzajb661yc3bj5xatkxj
created: 2026-10-25T01:48:47.314196+00:00
updated: 2026-10-27T10:37:22.180251+00:00
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
Q04. Each chunk points to an immutable item/asset version and locator (page, row
range, text offset, time range). Chunk limits bound per-tool output, not silently
claimed document coverage. Deduplicate results by evidence version, return offsets
or cursors, and expose facets/counts without loading all matching rows.
Q05. Query language is a typed API. Ordinary user text is safely tokenized/quoted;
advanced FTS syntax is explicit. No raw SQL from an LLM. Bound term count, query
length, results, page size, traversal hops and context bytes. Escape highlights
before rendering. Empty/hostile queries must never crash or expose another file.
Q06. Agent search traces list queries, inspected evidence and omissions. A zero
match is different from incomplete indexing. The answer must say when sources
were unsupported, truncated or absent. A summary is derived content and cannot
replace its cited original. Citations are validated against retrieved version IDs.
Q07. Optional semantic retrieval is not a substitute for lexical/structured search.
First version uses agent query expansion and deterministic lexical indexes;
embedding/reranking adds a versioned replaceable index only after a measured
recall/latency improvement. No network embedding service. Model synonyms can
improve recall but must not be presented as exhaustive proof of absence.

## Intake

Q08. Drag/drop, native file picker, CLI import, pasted URL and voice/text instructions
converge on an import job. Include by default; preserve filenames, origin and time.
Multiple items have independent progress/errors. Idempotent job retries cannot
create duplicate business effects. Importing evidence does not automatically
accept extracted financial/business events.
Q09. Plain text/Markdown/CSV/TSV/JSON/HTML, PDF text, image OCR, basic DOCX and XLSX
get explicit extractor paths. PDFKit extracts per page; image/scanned-page OCR
uses Vision locally. CSV quoting, multiline fields, BOM, CRLF, duplicate/empty
headers and locale ambiguity have tests. XLSX is data interchange: cached values
and basic cell types, not claimed macro/formula/chart fidelity. Original remains.
Q10. Audio/video are included or explicitly linked, previewed natively and indexed
by metadata. On-device transcription is capability-gated and its timestamps index
only after successful recognition; no fabricated transcript. Encrypted/unsupported
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
