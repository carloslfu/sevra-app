---
type: spec
meta-type: conclusion
id: 01m5rbxz9j15p1fw5fmxw7p9hv
created: 2026-10-25T01:48:47.282868+00:00
updated: 2026-10-27T14:09:32.444758+00:00
summary: Native two-pane local-AI workbook requirements, navigation, conversation, viewers and complete first-version journeys.
title: Product and interaction specification
status: reviewed
---
# Product and interaction

Revision 3, October 26, 2026. Status refers to specification review, not delivery.
Normative requirements use IDs so implementation and verification can map back.

Sevra Workbook is the primary product and homepage. A small Websites link in the
top navigation leads to the secondary managed service. Separate offer terms and
explicit data connections remain. This is a direction, not a deployed-page claim.

## Goal and first complete job

A user imports a supplier CSV, an invoice PDF and an image receipt, asks what was
purchased, inspects citations, corrects an interpretation, compares suppliers,
saves a space, records an inventory movement, asks why the balance changed, then
exports a portable workbook and reopens it offline. The CLI performs the same
operations with the app closed and the UI observes its changes when open.

The first version must be useful with deterministic search and tables before AI
setup finishes. Natural-language interpretation requires the selected local model;
never present canned command matching as model intelligence. Show setup state.

## Stable shell

P01. One document window per workbook. Create/open/recent workbooks, document title,
unsaved-operation status, keyboard shortcuts and native open/save panels. `.sevra`
is a directory package; `.sevraz` is its portable ZIP64 archive. Opening an archive
creates an editable package at a user-chosen location without overwriting a file.
P02. Adjustable conversation-left/workspace-right split, initial 34/66 proportion.
Keep a composer visible. Minimum usable window 820x600; at narrow widths allow
focus on one pane and an accessible switch. Never hide pending changes in a pane.
P03. Searchable space picker: Home, pinned/recent, all spaces. No unbounded tab strip.
Home shows useful recent sources, tables and pending work without dashboard setup.
P04. Stable title, selection and scroll state per saved space; temporary viewers
push onto a bounded navigation stack and Back restores the prior space. Opening
a file must not wait for inference or create a space/conversation automatically.
P05. System/light/dark appearance, Dynamic Type where applicable, keyboard focus,
VoiceOver labels and reduced-motion compatibility. Native semantic colors on dense
work surfaces; restrained warm identity. No decorative dashboard metrics.

P17. Reuse the existing Sevra Observer zebra, outlined lowercase wordmark and
original Mac icon. See [[records/specs/identity]] for placement, appearance and
self-contained asset provenance.

## Conversation

P06. One persisted main conversation per workbook, ordered messages with attachments,
run progress, tool results and citations. Persist each completed message and the
terminal state of each turn. A cancelled or failed answer must not say completed.
P07. Named chapters refer to message boundaries. Tangents link to a parent message
and retain scoped context without cloning accepted records. Saved exchanges are
bookmarks. Return to main and bring a selected summary back with provenance.
P08. Active space, selected item and scenario are visible near the composer.
Pronouns resolve only when context is unambiguous. Clarify consequential ambiguity;
do not force users to understand storage or ask on every harmless import.
P09. Text/voice can invoke all core workflows; native menu/toolbar controls offer
convenient equivalents. Include progress and cancellation for inference, downloads,
copying and indexing. Keyboard shortcuts must not conflict with text editing.

P18. Maintain one continuing conversation through automatic context maintenance.
Preserve original history and recover older details without manual token management
or forced new chats. Show progress only when useful; retain cancellation, browsing
and completed work. See [[records/specs/conversation-context]].

## Spaces and native components

P10. Persist versioned declarative compositions: table, bar/line chart, metric,
markdown/document, asset preview, search results and comparison columns. A bounded
component tree has explicit data bindings and action identifiers. Never execute
model-generated Swift, shell, JavaScript, SQL writes or downloaded code.
P11. A saved space is a view, not a copy of its data. Live bindings recompute when
inputs change. A published result pins input versions and labels its as-of time.
Draft views can be temporary; generated documents autosave independently of views.
Edits target the exact displayed version. Autosave publishes the submitted text and
its derived draft atomically, preserving meaning, scenario and metadata. Accept,
Undo and the conversation context use the newly saved version. Earlier citations
remain pinned to their original version.
A document or asset binding may name a logical item to follow its current version,
or an exact item version to preserve that reference. Pinning resolves every logical
binding, including comparison children, in the same transaction as the saved copy.
A pinned search stores the visible first eight results with exact versions and
locators, its query, capture time, index-gap count and whether more results existed.
It does not rerun later or imply an exhaustive result when only a page was saved.
Empty results retain their search limits. Live searches refresh off the UI thread;
errors and incomplete indexing must not disappear as an unexplained blank view.
The whole copy labels its capture time; pinning an already pinned copy preserves
the earlier results and time. An unpinnable child refuses the complete operation.
External asset links remain references with visible changed/missing-file checks;
pinning metadata does not silently import or freeze externally owned file bytes.
Earlier partially pinned spaces retain their stored data without fabricated
historical search results. New optional snapshot metadata keeps them readable.
P12. Tables support column types, stable row identity, scrolling/virtualization,
selection, sorting, filtering, editing, copy/paste, undo and CSV export. Edits
append source information and new versions. Multi-cell paste is one atomic change.
Formula values must show errors, units and provenance, never silently become zero.
Table selection follows stable logical row and column IDs through sorting and refresh.
An in-progress cell edit keeps the immutable row version and workbook revision the
user saw. A concurrent correction must refuse a stale edit, never retarget it to a
screen position. Copy uses the displayed snapshot; paste is based on its revision.
Rows, schema, calculated values and total count load from one SQLite read snapshot.
Only the latest table query may publish results or errors; query identity includes
workbook, dataset, revision, filter, offset, sort column and direction. Cancelled
reads cannot update a view. Removing a selected row from the view clears selection.

## Viewers

P13. PDFKit page navigation/search/selection; images zoom and pan; AVKit audio/video
playback; Quick Look fallback for supported formats. Unsupported files retain
metadata and an explicit Open in Other App action. A preview is not an editor.
P14. Evidence links navigate to version plus page, text range, row or timestamp when
supported. If no locator is available show the exact item version with that limit.
P15. Media opens paused; explicit play starts it. Voice input pauses playback.
Keep-playing mode retains a compact player while switching spaces. Closing its
workbook stops playback; dictation pauses every live workbook player and leaves
resumption explicit. A transcript is searchable only when actually extracted;
unavailable audio semantics stay visible.
P16. Comparisons compose viewers in the right pane. Draft edits save as new versions.
Closing a viewer does not delete a draft. Pending text flushes before navigation,
export, window close or application quit. A refused save retains the editor and
text, explains the failure and prevents that close. If another writer advanced
the document, the user can keep their text as a separate draft, preserving both;
never silently replace the newer version. Text/voice can request saving or keeping
that separate draft. Original file assets remain immutable previews, separate
from editable generated text. Search/preview must work without a model.


File verification must keep the workbook responsive. Show opening/checking state
and bounded progress while checking an external original, with Stop and Retry.
Leaving a preview cancels its work; a late success, error or progress callback
cannot appear in a different preview. Keep Find original available when a linked
file is missing. Relink checks the recorded bytes before changing the reference.
These controls complement conversation actions and must work without a model.
## Acceptance journeys

J01 Create → import CSV/PDF/image → search text and filenames → open exact evidence.
J02 Ask locally → agent searches/reads → cited answer → chart/table → save space.
J03 Source claim → draft movement → accept → balance 20−2=18 → retry unchanged →
correction gives 19; genuine return is distinct; forecast never changes actuals.
J04 Create tangent → explore scenario → return to main → preserve business state.
J05 Link external file → move/miss/change → honest status → relink/include version.
J06 Edit/paste cells → recompute → undo → inspect versions → close and reopen.
J07 Export during concurrent CLI writes → open elsewhere → verify hashes/lineage.
J08 Cancel import/model run → recover → restart → last valid document remains usable.
J09 Fresh checkout → documented install → launch app/CLI → demo → uninstall safely.

J10 Long multi-step conversation → repeated automatic compaction → recover earlier
evidence and latest constraints → tangent/return → cancel/restart → correct pending
status and unchanged accepted effects → portable export/reopen with full history.
