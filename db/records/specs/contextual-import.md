---
type: spec
id: 01m61c4z13j3paexnc7xvyyqhs
created: 2026-10-28T13:45:46.275195+00:00
updated: 2026-10-30T00:57:36.701824+00:00
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

## Managed dataset storage

[[records/specs/managed-datasets]] controls working-table persistence. Requested
structured conversion creates managed native dataset projections with stable
logical row/column identities, canonical immutable versions and source lineage.
Append/replace/merge, schema mappings, Undo/redo and resumable batches use the same
transactional history path. Retain exact parsed values/definitions so reconstruction
never depends on rerunning the original importer or AI.

Reference/analysis-only roles still avoid creating working tables. Sparse sheets,
mixed cells, multiple regions, formulas and layout have their appropriate versioned
representation; file suffixes and worksheet boundaries do not force one table.
Native physical storage does not qualify Excel formula/behavior continuity.
Existing shared-row import receipts remain evidence for their current scope;
schema-12 managed storage and exact-base definition lifecycle have scoped evidence.
Uncommitted intake batches refuse after any definition change, preserving the saved
prefix. Typed query/index and full MJ gates remain pending.

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
A bare Add files, start-from-files or drop includes/indexes the evidence as a
reference and returns focus to the composer. Do not interrupt capture with a
mandatory role questionnaire. This default changes no working table or business
state. Preserve the original, a readable inclusion message and later-use actions.
Ask a short contextual clarification only when a requested operation would change
working data and its target or method is ambiguous. Explicit native File actions >
Use saved file offers conversion or table update without reimporting the original.
Prefer a useful question such as whether to create a new table or update the
selected one. Never ask users to choose storage internals. The October 29 native
journey review is [[records/reviews/native-journey-polish]].

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

IJ04. A bare CSV drop includes/indexes a reference under I04 without interrupting
capture. If an explicitly requested update has an ambiguous target or method, ask
briefly before changing working data; append/replace/merge are not guessed. Clear
requests avoid redundant questions. Duplicate headers/keys, unmatched columns, leading zeros, locale-ambiguous dates/numbers and
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
partial-column updates are not implemented. The incoming original stays
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
reopen and shows a reviewable draft before acceptance. Source/preview/publication
callbacks are fenced, and exact failed publication retries reuse their token. This
focused slice does not qualify general local-model/voice update tools or the FJ
persistence gates in [[records/specs/persistence-readiness]]. Those remain next in
the ordered plan.

Less manual reviewed updates, October 30:

Suggestions. An incoming heading suggests a stored column when it equals that
column's title or ID, ignoring case, character width, spaces, hyphens and
underscores. Accents and words still count. A heading or column with two candidates
stays for a person. A suggestion fills only undecided inputs, so a chosen column or
an explicit Ignore stands. One matched column declared unique is suggested as the
key. Values are never inspected to infer a mapping or key, and a preview still needs
the complete explicit mapping. Offer one action to ignore remaining inputs once every
stored column is mapped, and name what still blocks a preview.

Saved drafts. An in-progress review is saved per original as a presentation draft in
the workbook. It survives leaving the page, relaunch and portable export, changes no
table and grants nothing. Saves run in order, keep the newest choices, and a failed
save is shown without interrupting the review. Reopening restores the choices and
says so, and clears any choice a changed table no longer supports. Creating the
proposal ends the draft in the same transaction. Start over discards it.

Excel saved values. An XLSX original can update a table from one named worksheet. A
multi-sheet file names its worksheets before anything is read. Header and source rows
use real worksheet row numbers, empty rows and empty styled cells are skipped, and a
value outside the headings refuses. The 1,000-row, 10,000-row, 8 MB and 16 MB bounds
are unchanged. Text cells keep leading zeros. A number Excel shows differently, such
as 14 under the format 0000, refuses in a key, a non-decimal column or a column holding
leading zeros, because only the unpadded value is saved. Error cells and formulas with
no saved value refuse and name the cell. Other formula cells use saved values, the
preview counts them, and nothing recalculates. Fractions keep the 15 significant digits
Excel shows, so a cell showing 1.15 is not read as 1.1499999999999999; this also applies
to saved-value import. A cell without a reference follows the previous cell in its row.
Workflow intake stays CSV/TSV.

Ambiguous input. Keys stay exact, so a key that differs from an existing or another
incoming key only by case, surrounding spaces or leading zeros stops the review
instead of becoming a new row. Decimal columns compare amounts, so 1.2 does not change
a saved 1.20 and the earlier spelling stays. A value a column refuses names its source
record.

Bulk table intake, October 30:

Batches. A table import commits at most 1,000 rows or about 6 MB of cell values at a
time, and always at least one row. Rows also carry their headings, so a batch can pass
that estimate and still exceed the 64 MiB saved-change limit. The refused batch saves
nothing and a batch half its size starts at the same row. The limit itself stays. A row
over the 16 MB record bound stops the import, is named by its position among the data
rows, and earlier rows stay.

Resuming. Saved rows are a committed prefix in source order. After Stop, a failure or a
killed process, a retry parses the same verified original and continues after the saved
rows, repeating none. An edit made to a saved row in the meantime stays. A table whose
definition or row count changed refuses with import_changed and keeps its rows. A
multi-sheet XLSX import finishes its current sheet and then the sheets not yet started.

Progress. Rows count only once committed. The app status line reads "Saved 12,000 of
99,999 rows", across every sheet of an XLSX import, and a resumed import shows its saved
count first. Stopping reports the saved count, and Continue on Home saves the rest
without asking again. Until the last row commits, Home and the table footer say how many
of the source rows are saved, and table results carry unfinishedImportTotal so a person
or agent reading them can say the table is incomplete. Saved rows stay usable meanwhile.

Excel formula subset, October 30:

Declared subset. Sevra recalculates numbers, percent, + - * /, cell and range references
(absolute, relative and mixed, on the same sheet or a named sheet of the same file), and
SUM, AVERAGE, MIN, MAX, COUNT, ROUND and IF with both results. A comparison is read only as
IF's condition. A shared formula expands to each cell it fills. This is a small declared
calculator, not an Excel engine, and it does not claim to match one.

Acceptance at import. A formula joins only if the subset reads it and its result matches the
value Excel saved, to 15 significant digits. Everything else keeps its saved value and records
why: an unsupported function by name, text operators, whole-column references, defined names,
references to another file, powers, array formulas and data tables, a formula with no saved
value, a circular reference, a sheet that was not imported, and any result that differs from
Excel's. A formula reading one of
these keeps its saved value too, so a chain is never part current and part stale. Comparing with
the saved value also catches what the importer cannot see, such as a date stored as text or text
that looks numeric.

Calculation rules. Blank counts as zero in arithmetic. Aggregates skip text and blanks in cell
references. Comparisons sort numbers before text and ignore case in text, and a blank equals
zero and empty text alike. Text in arithmetic gives #VALUE!, division by zero #DIV/0! and an
out-of-range result #NUM!. The first error carries forward, though COUNT ignores errors and IF reads only its chosen
branch. Arithmetic is exact decimal, and a stored result keeps 15 significant digits. A saved
number may carry an exponent, as spreadsheets write very large and very small values.

Recalculation. Formula cells hold stored values, so filters, sorting, exports, queries and tools
see the same numbers. Any change to a table's rows recalculates the whole file's formulas in that
same transaction, across sheets. A person's edit and the cells it moves on that row form one row
version, so Undo restores both, and other rows get their own versions with lineage to the formula
record. Typing over a recalculating cell refuses. A saved-value cell stays editable and nothing
recalculates from it. An error clears when its input is fixed, and a removed column gives #REF!.
An archived table stays current with its file, because recalculation is not a person's edit.
An edit that would rewrite more than 2,000 rows saves nothing, and so does one whose result a
typed column cannot hold, such as #DIV/0! in a Number column.

Showing it. A recalculating cell reads normally, takes no typing and offers its formula as help.
A saved-value cell reads quieter and says why. The table footer counts both and opens the list of
saved cells with their reasons, and warns once values have changed since import, because saved
cells may then be behind. The intake detail, `table-formulas` and the rows tool report the same.

Bounds. A file recalculates up to 10,000 formulas, 20,000 rows and 200,000 read cells, and one
formula reads up to 10,000 cells. Past a bound every formula in the file keeps its saved value
and says so, so a file is never half recalculated. An array or data table too large to list
does the same, because any formula could be reading a cell it fills. A reviewed update refuses a table whose file
still has recalculating formulas, because it could replace rows those formulas read. Only an
import writes the formula record, and later changes cannot revise it.

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
   per-cell/dependency support, then qualify the declared continuity subset. The
   formula subset above is implemented and matches LibreOffice on the committed
   fixtures. A file written by Excel itself, sparse regions and layout remain open.
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

## Folder comparison, October 30

Add a folder compares one chosen folder with what earlier passes saved from it, by relative path
and content, and shows the counts before anything is added. Nothing watches the folder. Hidden
files, symbolic links and package contents are skipped. A changed file becomes a new Source
beside the earlier one, content already in the workbook is not added again, and a file gone from
the folder stays in the workbook and is reported. Replaying a stopped pass saves nothing twice.

One pass handles at most 200 files and 2 GB; past that it refuses and adds nothing. Two folders
with the same name count as one. Each added file goes through normal intake.
