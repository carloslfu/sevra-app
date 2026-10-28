---
type: spec
meta-type: conclusion
id: 01m5rbxz9j15p1fw5fmxw7p9hv
created: 2026-10-25T01:48:47.282868+00:00
updated: 2026-10-28T00:31:58.019485+00:00
summary: Native two-pane local-AI workbook requirements, navigation, conversation, viewers and complete first-version journeys.
title: Product and interaction specification
status: reviewed
---
# Product and interaction

Revision 5, October 27, 2026. Status refers to specification review, not delivery.
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
P07. The default pane is Conversation: one continuing main conversation per
workbook. Optional separate discussions are Threads, with descriptive titles such
as What if we raise prices? Start a thread preserves its parent message and scoped
context without cloning workbook data. Back to conversation returns to the ongoing
main history. Share summary with conversation lets the user choose/edit findings
and copies only that summary, linked to its exact original exchange. This does not
accept records, widen retrieval access or start an AI turn. Text/voice equivalents
include Let's explore this separately and Go back to our main conversation.

Chapters are optional named headings at message boundaries within the same
history, available when useful rather than introduced as an upfront concept.
Saved exchanges remain bookmarks. Older package/API identifiers named tangent are
compatible implementation details; visible copy uses Threads. The decision is in
[[sources/notes/2026/10/conversation-threads-refinement]].
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


Explicit shell controls remain available through the composer while an operation
is active. Stop/cancel stops current work; stop preview targets only an opening
file; retry preview starts a fresh check; find original opens the native picker
for the visible external reference. These controls use the same preview session
as their native equivalents and do not wait for inference. Match complete control
submissions, including terminal dictation punctuation; unrelated or negated text
must not be turned into cancellation. Other model submissions remain disabled
while the active request is running. A retry invalidates old callbacks immediately,
and an older reconnection completion cannot discard a newly chosen original.
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
metadata and an explicit Open a copy action. A preview is not an editor.
The button and exact text/voice commands such as "open this in another app" use
the same native save picker, then open a verified copy in its associated app.
The user chooses a persistent destination outside any workbook, with a new
filename. Explain that external edits do not automatically enter the workbook.
Keep the original evidence intact. Copying is cancellable, reports bounded
progress, and cannot start while another workspace operation owns the window.
Closing or switching workbooks prevents a late completion from opening an app;
a completed copy remains at the chosen destination.
P14. Evidence links navigate to version plus page, text range, row or timestamp when
supported. If no locator is available show the exact item version with that limit.
P15. Media opens paused; explicit play starts it. Voice input pauses playback.
Keep-playing mode retains a compact player while switching spaces. Closing its
workbook stops playback and detaches the media item even if SwiftUI retains its
player. Closing the compact player or an ordinary preview releases its media;
explicit keep-playing navigation preserves it until closed. Retry/relink releases
the prior preview before verifying another file. Dictation pauses every live
workbook player while retaining its position and leaves resumption explicit. A transcript is searchable only when actually extracted;
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
J04 Start a thread → explore scenario → share selected summary or return to conversation → preserve business state.
J05 Link external file → move/miss/change → honest status → relink/include version.
J06 Edit/paste cells → recompute → undo → inspect versions → close and reopen.
J07 Export during concurrent CLI writes → open elsewhere → verify hashes/lineage.
J08 Cancel import/model run → recover → restart → last valid document remains usable.
J09 Fresh checkout → documented install → launch app/CLI → demo → uninstall safely.

J10 Long multi-step conversation → repeated automatic compaction → recover earlier
evidence and latest constraints → thread/return → cancel/restart → correct pending
status and unchanged accepted effects → portable export/reopen with full history.

## Workspace operation ownership

Closing or switching a workbook cancels cooperative work and invalidates its UI
callbacks. A completed mutation remains saved in the workbook and conversation
where it began; a late result must not change another window's progress, errors,
selection or navigation. Stop retains operation ownership until ordinary work
finishes, preventing overlapping actions. A cancelled system permission wait
releases the waiting UI immediately, and its eventual response cannot start work.
Opening another workbook resets search, navigation, selections and table state.
File pickers must still belong to the same active workbook when they return.

## Background window refresh
Periodic refresh and explicit catalog refresh run outside the UI actor. Read
revision, spaces, recent-item metadata, datasets, conversation messages, chapter
and bookmark menus, and intake state within one SQLite read transaction. Skip
unchanged poll projections only after a matching view has actually loaded. A new
workbook clears the old projection immediately; changing conversations clears old
messages while loading the new conversation.

Each window permits one active read and at most one pending replacement. Poll
requests do not accumulate behind an active read; repeated explicit requests
coalesce to the latest. Closing or changing workbook/conversation/anchor cancels
obsolete work and refuses its later success or failure. Cancellation and the
three-second read deadline include waiting for the workbook lock. Completed
background mutations retain their existing durability and ownership rules.

The header menus and Home intake sections render the snapshot rather than querying
SQLite during view rendering. This change does not establish that every editor,
viewer or explicit mutation is asynchronous, nor qualify whole-app latency/memory.
The actual visible workbook-switch and interaction journeys remain required.

## Conversation accessibility and link routing

P05a. Each message is a separate accessible group, preserving its speaker, status,
selectable text and links. Message actions expose the same exact destinations as
inline links, plus saving an exchange, starting a thread and explicitly sharing
selected findings. Named assistive actions and native menus complement the text.
The app's Conversation menu follows the focused workbook and provides its twenty
most recent visible exchanges; closing that workbook removes its actions.
Command-L focuses the composer without sending text or starting dictation.

Parsing must preserve Unicode/formatted link labels, exact item-version identifiers,
locators and original-message references. Merge adjacent styling runs belonging to
one link and deduplicate repeated destinations in action menus without changing the
body. Link handling permits the current workbook's item/message routes and ordinary
HTTP(S)/mail links. Malformed workbook routes and arbitrary application/file schemes
remain plain text, with no action. Navigation does not imply evidence acceptance or
widen the agent's retrieval scope. System keyboard preferences still apply to native
controls; keyboard and spoken VoiceOver qualification remain explicit UI gates.

## Coherent conversation and workspace flow

P06a. Preserve a separate unsent composer draft and reading position for each
Conversation/Thread and restore them on navigation and workbook reopen. Switching,
following provenance or returning to main cannot move unsent text into another
conversation. Delayed dictation/refresh callbacks remain bound to their origin.
Expose older messages through bounded paging and scoped history search, with an
explicit return to the latest exchange. Preserve the current reading position when
new messages arrive or older pages load; message retrieval is not action authority.

P07a. Starting a thread is immediate, using a useful editable provisional title
without a mandatory naming sheet. Preserve its parent/context and show the current
thread identity plus a visible Back to conversation control. This supersedes the
initial naming-sheet implementation, not historical thread identifiers or scoped
retrieval. Chapters remain optional. Share summary keeps an editable selection,
original author/role and exact origin links, with no automatic business acceptance.

P08a. Keep active conversation, relevant workspace/selection and scenario clear in
both-pane, workspace-focus and narrow-window modes. A temporary evidence preview
returns to the preceding result; it does not silently create a saved space. Complete
P03's Home/recent/pinned navigation, distinguishing a live view from an immutable
saved snapshot without a sprawling tab strip.

P09a. Native controls and interpreted local voice/text requests use the same scoped
host actions and truthful terminal results. Direct Stop/Back remain responsive
without inference. Ordinary requests to branch, return and share must not require
memorizing command literals. Ask when the requested target or consequential effect
is ambiguous. A thread changes discussion context only; what-if work must visibly
use a scenario or proposal and cannot silently alter accepted actuals.

J11. Exercise one coherent journey: import invoices, compare suppliers, open cited
evidence, return to the result, explore supplier/pricing options in a thread, return
to Conversation, review/share selected findings, explicitly review/apply one change,
undo, close/reopen and resume the right drafts, reading positions and business state.
Exercise voice/text and native equivalents, interruption, keyboard access and narrow
windows. Record exact results and open gaps. Automated or agent-operated checks do
not establish that an uncoached everyday user finds the product intuitive.

Request and evidence limits: [[sources/notes/2026/10/ux-consistency-review]].


## Conversation drafts and reading state

P06b. A composer draft belongs to one conversation in one workbook. Persist it as
presentation state, outside messages, Sources, Records, search and agent input.
Autosave after 600 ms of inactivity, and await pending saves before switching a
conversation, following an original-message link, closing the workbook or quitting.
A save failure keeps the text visible and prevents losing the editor. Dictation
stops before a switch; delayed results also check the window and conversation.
The last active conversation is a device preference for that workbook. Drafts and
reading positions travel with the workbook, including its current portable export.
A workbook copy is not a redacted publication; a selective sharing mode remains a
separate future contract. A hard process kill can lose edits inside the debounce
interval; successful normal close/quit must not.

Store an exact message identifier and a fractional offset within it, or an explicit
follow-latest state. Restore that position through thread switches, provenance jumps,
layout changes and reopen. Refresh around the reader when new messages arrive;
Return to latest deliberately resumes the newest window without clearing the draft.
The bounded history browser below complements this persisted reading state.

Competing windows compare the saved draft they originally read. A different new
draft refuses silent overwrite and offers Keep both drafts. The current text stays
in the composer; the competing text becomes a saved alternative. Restoring an
alternative preserves the previous composer too. Each draft is limited to 128 KB,
with eight alternatives and a 1.2 MB encoded-state bound. Limit errors preserve
text, and an explicitly removed alternative can make room for another. Reading-only
changes preserve and expose a newer externally saved draft rather than overwriting
it. Native conflict controls exist in this slice; ordinary voice/text equivalents
remain part of P09a qualification.


## Immediate threads and bounded history navigation

P07b. Start a thread from a visible conversation message immediately. Derive a
short plain-text title from that message, disambiguate provisional duplicate titles,
and allow an explicit rename later. Preserve the exact parent identifier and scoped
context without copying messages or accepting business changes. A repeated operation
identifier returns the same thread. Rename compares the title originally opened by
the editor and refuses an intervening rename. Main Conversation cannot be renamed
through this action. Explicit titles are one line, 1 to 120 characters and at most
512 UTF-8 bytes. The visible title, Back to conversation and composer remain available
in workspace-focus mode. Flush the current draft before changing discussion.

P06c. Conversation browsing loads at most 100 visible messages and 2 MiB of message
bodies in one coherent read. Use conversation-local message order, even when sibling
threads and tool receipts interleave. Earlier/later controls load overlapping bounded
windows while retaining the visible reading anchor. A cited or searched original is
included in the returned window. Body bounds must never create hidden gaps between
selected visible messages. Return to latest remains explicit and preserves the draft.
Tool receipts remain accessible to scoped history tools; the normal transcript and
its search show human messages, assistant messages and activity entries.

Search this conversation opens from its menu or Command-Option-F. Use the existing
FTS index, scoped to the active conversation, with 20 snippets per page, next/previous
navigation, a bounded cursor trail and an explicit empty-result scope. Show role and
local date; opening a result returns to its exact original after saving the draft.
A query or conversation change cancels and refuses stale results. Closing also
refuses late publication. Read-lock acquisition and SQL have a three-second budget.
Failed page reads preserve the preceding results and retry the requested page.
This is navigation over original messages, never new evidence or action authority.
Ordinary interpreted voice/text equivalents remain part of P09a and J11.

## Inline references, backlinks and related information

P17. Adopt [[records/specs/references-and-relationships]] L09-L10. Voice/text can
link selected text/items, find mentions and inspect dependencies through the same
core as native UI. Optional wiki-style/at-sign authoring offers suggestions.
Readable links open temporary right-pane previews with state-preserving Back.
Distinguish 'Mentioned in', 'Used to calculate' and later 'Possibly related'.
Resolve necessary ambiguity without blocking unrelated saves or requiring graph
maintenance. Keyboard, VoiceOver, narrow-window and draft-preservation checks
remain required. LJ07 is pending. No extra primary pane or automatic space.

## Proposal history and current review state
Conversation receipts preserve what happened at the time. A proposal's original
message is not rewritten after acceptance, withdrawal or correction. Its exact
original-version link remains useful evidence.

Current review UI is a separate, version-aware projection in the same bounded
background window snapshot. New proposal messages retain an exact item/receipt
association. For older messages without one, only an immediately preceding
completed proposal-tool receipt in the same conversation qualifies. Prose and
arbitrary links never establish current status. Unresolved associations show the
historical "Review requested" label without implying that review is still pending.

The badge opens the current version and distinguishes "Needs your review",
"Newer draft", "Current version accepted" and "Current version withdrawn".
It follows current heads after acceptance, Undo, corrections and reopen without
suggesting that the original content was approved unchanged. Existing conversation
scope, stale-result refusal, read budget and cancellation still apply. No schema
migration or history rewrite is needed.

Built-in movement details show meaning/status once, from authoritative item
metadata, and use the named User request lineage link instead of a raw request ID.
Captured request details omit internal conversation/message routing identifiers.
Keep those fields in the stored evidence and CLI. Recognized native context shows
"Context when requested", the named Space/Item/Table link, and selected text.
The exact original context, including routing IDs, remains under a collapsed
"Original context" disclosure. Unknown formats remain visible verbatim, and
ID-like lines inside selected user text are preserved rather than stripped.

Focused deterministic checks cover current versions, immutable history, foreign
and unknown associations, reopen, and original/selected context bytes. The native
preview check verified withdrawn -> accepted -> withdrawn badges, current versus
original version navigation, stock 20 -> 18 -> 20, readable Home context, original
context disclosure and Home navigation. This is one reference-Mac interaction
check, not a complete keyboard, VoiceOver or release qualification. Evidence:
[integration/evidence/2026-10-27-proposal-status.json](../../../integration/evidence/2026-10-27-proposal-status.json).

## Home and space navigation
P03a. The searchable native picker groups Home, pinned shortcuts, recent visits
and remaining spaces. Show each space once, using stable IDs even when titles
match. Search is case/accent insensitive, keeps matching groups and supports
Return to open the first visible match. Empty results are explicit. Opening a
space remains immediate and does not require model inference.

Pinning in navigation keeps a shortcut; it neither copies the view nor freezes its
data. The picker and Home show Live view or Snapshot with capture time. The former
Save a pinned copy UI action is now Save a snapshot, with the same existing
version-freezing behavior. The public pin_space tool and pin-space CLI remain
compatible snapshot operations. Ordinary requests now use separate open_space and
set_space_pinned actions. Exact names or host-provided IDs resolve existing spaces;
ambiguous names ask for clarification. A live window must confirm opening before
the assistant reports success. Pinning remains a presentation preference. Compound
requests may continue after opening, without returning to an earlier result view.
See [[records/specs/intelligence]].

Home shows pinned spaces, up to four recent unpinned spaces, tables, intake
attention and bounded recent work. Keep the fuller recent list in the picker.
Do not display empty-workbook onboarding once there is work or another saved
space. Keep Add files and Search available. Creating a space through conversation
focuses the composer, prefilling only an empty draft. Preserve existing unsent
text and do not submit it automatically.

Pin/unpin, recency, search/Return, live/snapshot identity, populated Home and
close/reopen passed the focused native preview check. Deterministic checks cover
merged preferences, duplicate titles, stale reads, invalid transaction rollback,
unchanged business state and portable reopen. Full keyboard/VoiceOver, narrow
windows, complete pending-review discovery and J11 remain separate open gates.
Three focused native requests pass compound unpin/open, pin-this-space and an
explanation-only no-change contrast. The explanation still exposes internal tool
names and calls navigation a sidebar; record this wording limitation without
broad requalification. Typed checks do not add microphone coverage. Evidence:
[space action receipt](../../../integration/evidence/2026-10-27-space-actions.json) and
[space navigation receipt](../../../integration/evidence/2026-10-27-space-navigation.json).
