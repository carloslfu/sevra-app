---
type: spec
meta-type: conclusion
id: 01m5zn6ks2pyv72pjs65f90rxj
created: 2026-10-27T21:45:28.610289+00:00
updated: 2026-10-27T21:45:28.610289+00:00
summary: Adopted inline references, backlinks and bounded traversal with stable identities, versioned evidence and separate relationship claims.
title: Inline references and relationships
status: reviewed
---
# Inline references and relationships

## Decision and scope

Adopted October 27, 2026; implementation and acceptance remain pending. Authority:
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
