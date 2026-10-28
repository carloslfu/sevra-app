---
type: spec
id: 01m61c4z13j3paexnc7xvyyqhs
created: 2026-10-28T13:45:46.275195+00:00
updated: 2026-10-28T16:37:51.219693+00:00
summary: One contextual intake for starting and ongoing work, role-aware CSV/data use and truthful Excel continuity gates.
title: Contextual import and Excel continuity
status: reviewed
---
# Contextual import and work continuity

Adopted direction, October 28, 2026. Specification review does not imply delivery.
Owner authority: [[sources/notes/2026/10/contextual-import-and-excel-continuity]].
This extends [[records/specs/product]], [[records/specs/search]] and
[[records/specs/storage]]. It supersedes treating all XLSX intake as the final
cached-value interchange design. That remains the current implementation limit.

## Shared persistence requirement

[[records/specs/persistence-readiness]] applies to capture, selected role,
inspection/extraction and feature reports, exact update targets/base versions,
column/key mappings, generated row/dataset IDs and committed results. Save enough
authoritative content to reconstruct completed intake without reopening a changed
external original, rerunning a parser/model or repeating a business effect.
Use shared atomic/idempotent change capture; keep device access grants local.
This adds persistence coverage to IJ gates, not a sync or conflict-resolver feature.

## One capability, two entry points

I01. Starting and continuing use the same intake pipeline. Welcome and an empty
Home offer a calm, prominent start-from-existing-information action alongside
blank creation. An existing workbook offers a persistent, clearly named add-data
entry independent of the selected space/view and chat history. A plus icon alone
is insufficient discoverability. Copy remains an implementation/design choice.

Voice/text stay central. Native controls, the file picker, drag/drop and appropriate
paste call the same workbook-scoped actions and expose the same results, limits,
progress, cancellation and retry. Starting with PDF, image, CSV or another supported
input is valid. No Excel-first wizard or mandatory format choice. Without model
setup, inclusion, previews and explicit native role choices remain useful.

I02. A start action selects input, chooses a normal workbook destination and enters
the same contextual intake used by an open workbook. Cancelling before creation
creates nothing. Once a workbook or original capture is durably saved, cancellation
reports what remains rather than claiming rollback of completed steps. Retry must
not duplicate completed captures/conversions. A failed conversion keeps its saved
original available and offers an honest next action, with no hidden empty success.
Never overwrite an existing workbook or source file. Closing/switching invalidates
late picker, parsing, model, paste and progress callbacks to another destination.

## Role comes from intent

I03. File type chooses the parser and candidate capabilities, never the business
operation. Storage mode (included/explicitly linked), role and conversion fidelity
are separate decisions. The same CSV or XLSX can be:

- A new native working table or set of working sheets.
- Reference material, searchable/readable without creating working tables.
- Input to an analysis, with only requested outputs saved as derived Records.
- An append, replacement or key-based merge into an explicitly chosen existing
  table, with the corresponding mapping and review.

These roles can coexist or be changed later without reimporting immutable bytes.
Reference-only does not prohibit bounded structured reads. Analysis does not
silently create a permanent working table. Converting a source later preserves
its identity and lineage, with idempotent operation receipts.

I04. Use the current request, selected destination and trusted current intake
state to infer intent. On a blank workbook, an explicit start-working-from-this
request usually supports native conversion; a request to consult a price list
supports reference/analysis. Neither inference is unconditional on a file suffix.
If a bare drop supports materially different uses, include/index the evidence
under the default asset policy and ask one short contextual clarification before
changing working data. Prefer a useful question such as whether to create a new
table or update the selected one. Never ask users to choose storage internals.

I05. Updating needs an exact target, expected revision, explicit operation and
validated column/key mapping. Preview affected row counts, conflicts, duplicates,
missing keys, additions and removals before a consequential change. Ambiguous
keys, target, append versus merge, or replace scope stop publication and request
clarification. Preserve lexical identifiers, leading zeros, nulls, original dates,
units and locale ambiguity. Do not guess that equal-looking rows are duplicates
or that an incoming spreadsheet is an accepted business event. Native working
data editing and acceptance of inventory/financial effects remain distinct.

## Preserve Excel work, not just its last values

I06. Continuity conversion inventories the workbook and produces a persisted
feature report before declaring success. Describe each detected feature as native,
translated with stated differences, retained as saved values/evidence, unsupported,
or not inspected because of bounds/failure. Reports link to exact source/sheet/cell
locations and the transformation version. No blanket compatible/migrated claim.

The ordinary-continuity target includes sheet identity/order, coordinate mapping,
rows/columns and blanks, sheet names, tables/ranges and headers, supported formulas
and dependencies, scoped named ranges, useful number/date/currency formats and
meaningful layout cues. Retain source coordinates when native headers/row identity
differ. Preserve non-tabular sheets, multiple blocks and sparse areas as sheet
structure or explicitly report an unconverted region. Do not assume first row is
always a header or compact rows and retarget formulas. Empty sheets are structure.

I07. Convert working formulas deterministically through a declared, tested subset,
with explicit dependency bindings and type/error/rounding semantics. Support must
be measured by editing inputs and observing dependent recalculation, not agreement
with one saved total. Preserve original expression and source coordinates alongside
native translation. Formula strings alone are evidence, not executable formulas.

The calculation design must handle per-cell expressions and sheet-qualified
dependencies where qualified. Existing column formulas and single-dataset A1
evaluation do not establish Excel formula compatibility. A1 currently means the
first data cell in stable native ordinal order, excluding display headings; it
cannot be substituted for original Excel coordinates without a mapping. Absolute,
relative and mixed references, ranges, quoted sheet names, scoped names and shared
formula expansion each need explicit tests. Unsupported formulas, absent cached
values, cycles, reference errors and their dependants remain visibly unresolved
or saved-value-only. Never compute a mixed stale/live chain and label it current.

I08. Cached values have separate provenance and calculation state. A stale cached
total must not look recalculated after an input edit. Show the relevant limit near
affected results, and in the import summary and tools; retain errors and missing
values as such. Values-only intake remains a useful explicit option. It must not
be presented as full continuity migration or the unconditional role of Excel.

I09. Publish a feature support matrix, starting with bounded XLSX ordinary sheets.
Inspect and report, rather than silently discard, charts, chart sheets, pivot
tables/caches, conditional formatting, validation, merged/hidden/protected regions,
filters, freeze panes, comments, drawings/embedded assets and print layout. Translate
useful supported behavior into native components; do not promise pixel-identical
Excel rendering. Preserve unconverted features in the immutable original.

VBA/XLM macros, add-ins/UDFs, Power Query, external connections, external-workbook
references, data models, iterative/volatile calculations, array/dynamic-spill and
other advanced formulas require separate explicit support decisions. Never execute
code, refresh connections, fetch linked resources or claim working automation on
import. Legacy XLS, XLSB, XLSM and encrypted workbooks are not qualified by the XLSX
parser; retain unsupported originals and explain options. A read-only original
preview or export does not qualify native behavior. No round-trip fidelity promise.

## Shared implementation and evidence

I10. Separate capture, bounded inspection, intent resolution, conversion/update
proposal and commit. Reuse canonical asset inclusion, the isolated helper, stable
identity, revision checks and durable resumable batches. Copy/index once and derive
new native data only for the requested role. Preserve originals as files inside
the workbook, outside SQLite, unless explicitly linked. SQLite owns job state,
lineage, mappings, support reports, tables and formula/dependency metadata.

An import receipt records exact source versions, selected role, destination,
mapping/feature-report version, applied native changes and incomplete stages. The
same request/token cannot repeat changes, and changed arguments cannot reuse its
receipt. Undo compensates native working changes without erasing original evidence.
Partial/resumed publication must not invent all-or-nothing completion. Enforce
existing size/time/decompression limits and disclose uninspected regions.

I11. App, CLI, harness skill and local agent share these scoped core contracts.
Future agent intake uses authorized file handles/captures, exact target IDs and
current-request authority. Retrieved filenames/paths or instructions inside an
import cannot authorize disk reads or updates. Tool results distinguish included,
indexed, analyzed, new-table-created, update-proposed, update-applied and converted
with limits. Clarification is a valid result, not a failed run to work around.
Successful copy/extraction cannot satisfy a requested merge or formula migration.
New tools/grammar require focused authority, retry, stale-state and truthful-final
checks before exposure. No new intake tool is claimed by this specification.

I12. Paste is contextual. Ordinary text stays text. A spreadsheet cell range can
start a table/reference/analysis or propose an update; selected table paste edits
only the explicit range. Capture the submitted range as Source information and
derive changes with lineage. Label a values-only clipboard payload truthfully;
plain TSV cannot promise retained formulas/styles. Rich clipboard parsing is an
explicit supported path, never an excuse to read arbitrary clipboard content.
Do not redirect a paste intended for the composer or a document into a table.

## Focused acceptance

IJ01. From Welcome and empty Home, start separately from a CSV, an ordinary XLSX
and a PDF/image. Reach a saved workbook, preserved original, useful native view and
truthful status without mandatory AI or an Excel-only starting assumption. Cancel
destination selection and conversion separately; observe exactly what is saved.

IJ02. Add CSV/XLSX through the persistent entry while viewing an existing table,
document and space. File picker, drop and text/voice reach the same intake and
correct workbook. Cancel/switch during picker/worker/model work; no late mutation
or completion may target a different workbook. Keyboard and spoken VoiceOver need
actual native checks; an icon or code-only assertion is not discoverability proof.

IJ03. Use one CSV for four requested roles: new working table, reference-only,
analysis-only and update to an existing table. Assert which native entities change
and which stay unchanged. Repeat each at startup where applicable and during work.
Use XLSX as reference/analysis too, without forced whole-workbook migration.

IJ04. A bare CSV drop onto an ambiguous table asks briefly; append/replace/merge
are not guessed. Explicit clear requests avoid redundant questions. Duplicate
headers/keys, unmatched columns, leading zeros, locale-ambiguous dates/numbers and
multiple plausible destinations preserve source bytes and refuse unsafe changes.

IJ05. Edit an input in a converted workbook with two sheets, a table/header, blanks,
scoped named ranges, absolute/relative references and supported formulas. Dependent
results recalculate correctly across sheets, after sorting/filtering, close/reopen
and portable export. Original coordinates, expressions and mappings remain
inspectable. Sparse/empty sheets and multiple data blocks are not silently lost.

IJ06. Include stale/absent cached totals, unsupported functions, shared/array
formulas, cycles and errors. Report exact functioning, saved-only and unresolved
regions and propagation. A correct extracted value is not counted as recalculation.
Test date epochs, number formats and rounding against the declared subset.

IJ07. Inventory a workbook with chart/pivot, validation/formatting, hidden/merged
regions, named ranges and an external link. Supported features translate; all
others are reported and retained in the original. Macros/connections do not run.
Unsupported legacy/encrypted inputs fail honestly without corrupting saved work.

IJ08. Retry and resume a multi-batch conversion/update, fail an intermediate write,
cancel, concurrently advance the target and undo a completed update. No duplicate
rows/effects, orphan accepted changes or silent overwrite. Preserve assets and
lineage; reopen and verify the portable copy. Bound the real input/output and memory.

IJ09. Exercise plain and rich spreadsheet-range paste only where supported, in
empty Home, reference/analysis, selected cells, composer and document contexts.
Verify target, explicit range, Unicode/newlines, empty cells, bounds and one atomic
Undo. Do not claim formula/style continuity for a plain values-only payload.

IJ10. Local model requests the right role and asks on ambiguous merges, survives
imported instructions and reports the real stage/limits. CLI/skill produce the same
core results. Test a nearby false-completion counterexample, not just happy intake.
Reuse unchanged engine evidence; broaden only for material boundary/release changes.

## Inspection and implementation order

Code inspection on October 28 finds: native Home Add files, a toolbar plus menu,
Workbook Import Files menu, exact composer import commands and file-URL drop exist.
Welcome has Create/Open/example but no direct start-from-file path. Home offers
ongoing import, but the persistent toolbar affordance is only a plus icon. Table
paste edits bounded selected visible cells; there is no general range-intake flow.

Current implementation checkpoint, October 28: the shared core now separates
capture and bounded indexing/inspection from a selected use. Durable intake jobs
preserve exact original identity, reference/analysis/explicit saved-value/update roles,
stage reports, affected dataset identities, cancellation/failure and resumable
receipts. A bare file no longer creates a table from its suffix. Reference and
analysis can reuse one original without creating permanent working tables;
analysis readiness does not mean an analysis was performed. Explicit values
conversion retains the existing CSV first-row and XLSX saved-value limitations.
ZIP member capture and a source with no chosen use now ask for a role; retrying an
already requested table conversion retains that intent. Source/Record acceptance
and duplicate business-effect rules do not change.

Welcome offers Start from files and blank creation. The named Add files action
remains visible in the workbook header. Picker, existing drop path, role sheet,
Home attention entry and saved-file reuse all reach the shared core. A Decide
later choice preserves the source and the unresolved use. The native app has a
bounded explicit values-only TSV clipboard entry, but this checkpoint does not
qualify rich clipboard fidelity or its visible lifecycle. The model and voice do
not yet have general contextual intake-role/update tools.

Development schema 9 is the single canonical initial schema. Unsupported formats
are refused without changing their database bytes. There is no legacy development migration
or backward-compatible CLI result adapter. Historical receipts and
fixtures are preserved; fresh synthetic workbooks qualify the current format.
The CLI import result is now {source,intake}; roles, resume/from-source operations,
coverage and limits are documented in the repo skill. No app data was reset.

The contextual-intake checkpoint had 134 passing core groups, including six intake
checks and current-format reopen/refusal invariants. The smaller total replaces
obsolete migration-success checks with byte-preserving unsupported-format
refusals under the owner's pre-1.0 policy; it does not remove current-format
history, integrity or portability checks. Nine CLI intake checks, packaged
extraction with build reads denied, 30 concurrent writers and actual native
CSV/TSV journeys pass. Detailed scope and retained failures are in
[[records/operations/implementation]]. No new actual model cohort, spoken voice,
large-scale intake or broad Excel compatibility is established.

Reviewed table updates, October 28: CSV/TSV inspection supports an explicit header
record and bounded sample values. A native review in the workspace requires a
target, method, every input position mapped or explicitly ignored, merge key(s),
and meaning/scenario for new rows. Append keeps duplicates, replacement replaces
all current rows, and merge rejects empty/duplicate input or target keys. Keys are
lexical; there is no case, whitespace or locale normalization. Current bounds are
1,000 incoming rows, 10,000 target rows, 8 MB mapped input and 16 MB target content.
Every stored target column must be mapped once. Calculated columns stay intact;
partial-column and XLSX updates are not implemented. The incoming original stays
unchanged. A typed preview retains columns, exact target fingerprint/revision,
counts, duplicate disclosure, at most 20 examples and parsed source-record locators.

A proposed update is a draft Record. Creating it atomically completes a selected
update intake with its proposal ID, without changing rows. Acceptance applies the
saved plan after an exact target check, without parsing or reading the original.
Merge preserves existing logical row IDs/meaning/scenario; new rows use the chosen
meaning/scenario. Replacement retains removed rows as rejected historical versions.
Checked Undo/redo compensates row versions and restores stable membership/order.
All row lineage retains the original, proposal, decision and source-record locator.
No inventory/financial effects are posted. Generic record creation cannot forge a
table-update proposal. Retry tokens return prior receipts before checking changed
state or a missing linked original; changed arguments refuse. Stale preview/apply/
Undo and fault/cancellation tests preserve working data.

The CLI supplies table-update-inspect, table-update-preview and
table-update-propose, using the same host core.
The repo skill documents exact options and review authority. The native path starts
from a CSV/TSV role choice or File actions, retains a pending update use across
reopen and shows a reviewable draft before acceptance. Mapping-form edits are not
yet persisted across navigation/relaunch. Source/preview/publication callbacks are
fenced, and exact failed publication retries reuse their token. This focused slice
does not qualify general local-model/voice update tools or the FJ persistence gates
in [[records/specs/persistence-readiness]]. Those remain next in the ordered plan.

Implementation phases:

1. Shared capture/inspection, durable roles/results and truthful current CLI
   contracts: implemented within the stated reference/analysis/saved-values scope.
   Broader update/continuity jobs remain below.
2. Welcome and persistent ongoing entries, native role clarification and CSV/TSV
   roles: focused native journeys pass. Full IJ01-IJ04 coverage, all startup
   cancellation/late callbacks and clipboard journeys remain open. No broad
   native working-Excel continuity claim.
3. Reviewed CSV/TSV update mapping and stale/idempotent/undo publication now have
   shared core, CLI and native review paths within the bounds below. General local
   model/voice update tools and broader mapping usability remain unqualified.
4. Add Excel feature inventory, source-coordinate mapping and bounded native
   per-cell/dependency support, then qualify the declared continuity subset.
5. Connect natural-language/voice and CLI/skill contracts, actual native usability,
   portable recovery and truthful completion. Expand the feature matrix by evidence.

These phases do not close broader app/engine/release gates. The centralized status
and next actions remain [[records/operations/implementation]].

## Primary technical references

Microsoft documents formulas and cached results separately. This supports keeping
saved values distinct from native recalculation, not any Sevra delivery claim:
[Working with formulas](https://learn.microsoft.com/en-us/office/open-xml/spreadsheet/working-with-formulas).
Its workbook-part overview distinguishes sheets, tables, pivots, styles and formula
structure, motivating an inventory beyond cell extraction:
[Structure of a SpreadsheetML document](https://learn.microsoft.com/en-us/office/open-xml/spreadsheet/structure-of-a-spreadsheetml-document).
Both checked October 28, 2026. The architecture and qualification choices above
are Sevra design decisions, not requirements asserted by those documents.
