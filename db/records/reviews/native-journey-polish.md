---
type: review
meta-type: conclusion
id: 01m64w7mfc74gf1h0cqhykr0p4
created: 2026-10-29T22:24:34.284218+00:00
updated: 2026-10-29T22:24:34.284218+00:00
summary: Full native journey/control review, simpler intake and shell, polished search/history, verification coverage and retained limits.
title: Native journey simplification and polish
---
# Native journey review and simplification

October 29, 2026. Owner request:
[[sources/notes/2026/10/native-journey-simplification]]. This is the existing MVP
surface review, not an expansion into deferred infrastructure. Specifications:
[[records/specs/product]], [[records/specs/contextual-import]],
[[records/specs/agent-activity]] and [[records/specs/mvp-delivery]].

## Assessment

The conversation plus workspace foundation is sound. The roughness came from
asking for decisions too early and presenting secondary tools alongside the
primary job. Consistent padding alone would not solve that. The default journey
is now bring information, ask or inspect, work with a result, review consequential
changes, and keep/share the workbook. Advanced authoring remains available.

The first review mapped controls and destinations across the native views. The
second walked synthetic files through the installed app and tested smaller-window
fit. The third rechecked changes and secondary viewers, catching JSON search
snippets, raw Markdown destinations in history results, and awkward empty Links
panels. Failures were retained locally and fixed before the final build.

## Decisions and control inventory

| Surface | Primary job and controls | Simplification and review |
| --- | --- | --- |
| Welcome | Start from files, Open workbook | Blank/example are secondary links; recents and settings remain. Scrollable content avoids clipping at the minimum window size. |
| File capture | Add files, drop, native picker | One Add files split control replaces a separate plus menu. Include is the default; external linking and range paste are explicit menu alternatives. |
| After adding | Index, inspect, ask | Save/index as reference and focus the composer. No mandatory classification modal, table creation or business acceptance. Progress, cancellation and failures remain. |
| Later file use | File actions > Use saved file | Optional conversion sheet has one clear saved-values action plus Other uses, file details disclosure and Done. CSV first-row and Excel cached-value limits remain explicit. |
| Global shell | Search, Add files, focus switch | Stable workbook title; dynamic focus labels; bounded busy text with full help and Stop. |
| Workspace navigation | Back, Home, Spaces | Direct Home outside Home, retained Back stack and searchable adaptive-height space picker. No permanent tab strip. |
| Secondary workbook tools | Workbook actions menu | Edit layout, snapshot, review queue, Workflow runs, Automations and shareable copy. No persistent layout/snapshot row on every space. |
| Pending review | Contextual Review drafts, queue, Accept | Queue shortcut appears when drafts exist; always available in menu. Accept is visually primary in draft inspection, with evidence and Withdraw retained. No implicit acceptance. |
| Conversation | Composer, mic, Send, message menu | Continuing main conversation stays central. Chapters, threads and history search are optional menu actions; the menu does not become a parallel navigation sidebar. |
| Conversation history | Search, original-message cards, Done | No inactive paging on one page. Link labels replace raw Markdown/internal destinations in result cards. |
| Live agent activity | Expand actual steps, Stop, open result/original | Reuse the completed shimmer/elapsed/receipt implementation. Private model reasoning is not a UI transcript. This pass changes no engine behavior. |
| Spaces | Live components, optional layout/history | Layout and snapshot authoring move to the workbook menu. Real snapshot dates remain visible; layout text can wrap across multiple lines. |
| Tables | Filter, cell editing, table actions, contextual Undo | Small tables show a row count rather than disabled pager buttons. Larger tables retain the same bounded 200-row pages. Copy/paste, schema, Undo/redo and CSV export stay grouped. |
| Table definition | Column titles/types/units/formulas, History, archive | Explicit Save definition and Escape Cancel. Advanced editor remains dense but scrollable, with identity/formula information visible because it affects meaning. |
| Table update | Exact target/method, mapping, Preview, draft | Remains an explicit secondary operation. Do not guess append/replace/merge, keys or business meaning. Review and stale-base safeguards retained. |
| Workbook search | Query, clear, optional filters, matches | Filters collapsed unless active; active count and Clear filters. Coverage and retry remain visible. JSON snippets become bounded readable fields, never a completeness claim. |
| JSON files/results | Fields, tables/lists, optional identifiers | Retain native structured views. Exact number spelling, false, zero, missing and empty remain distinct. Search now uses the same display policy. |
| Documents and evidence | Original viewer, Links, File actions, Open a copy | Consolidated linked-file actions; clarify that Open a copy preserves the original. Draft edit/recovery and lineage remain available. |
| PDF/text/image/Quick Look | Native preview, find/zoom/retry where supported | Preserve immediate previews, bounded extraction, coverage and original navigation. File opening does not require inference. |
| Audio/video | Native player, keep-playing option | Preserve playback ownership and navigation behavior. Media appearance was inspected, not a new full playback/accessibility qualification. |
| ZIP contents | Selected member list, size/count, Include selected, Cancel | Explicit bounded selection, 50 files/1 GB per selection. No automatic archive expansion or hidden extraction. |
| Links and mentions | Scope tabs, originals, optional destination choice | Centered empty-state message instead of blank list plus footer. No inactive destination actions/pager on empty scopes. Coverage caveat retained. |
| Forms | Inputs, Preview, draft, recovery | Show Use current form only when the definition actually differs. Validation and unsent input retention remain; no business mutation from an empty preview. |
| Workflow runs | Filter, inspect, Refresh, appropriate continuation | Rename Activity to Workflow runs to distinguish it from agent activity. Hide one-page navigation, preserve run state, evidence, Stop and explicit clarification/retry. |
| Automations | Find, New, details, Runs, explicit device enable | No one-page pagination. Mandatory workflow chooser opens initially and explains an empty list; collapses after selection. Saving never enables device execution. |
| Local AI settings | Setup status, Download or Verify model files | Model storage/reuse/unload behind disclosure. Model files found means presence, not loaded/qualified. Download size, cancel, failure and local-only behavior remain. |
| Portable copy | Named export, native destination, explicit editable reopen | Existing include/link semantics and no-overwrite behavior preserved. Instructions updated for the current intake/settings labels. |

The native shell uses 20-point outer horizontal and 14-point workspace-header
padding, with most full-page content using 22 to 24 points and secondary sheets
22 to 24 points. Hierarchy uses native typography and semantic colors. Small-window
inspection retained both panes and document actions; long route titles truncate
with full-title help. Focus workspace provides more room while retaining input.
This is visual inspection on one host, not pixel-perfect qualification of all
locales, contrast/motion settings or generated component combinations.

## Verification coverage and honest limits

Actual installed walkthroughs cover welcome/recent open, Home/table/chart, direct
file addition without a role sheet, explicit later conversion, search/filter entry,
JSON search/viewer, PDF/text evidence, ZIP member picker, video preview, Links and
Mentioned in empty states, form inputs/empty preview, pending review/draft inspection,
layout/history, settings, automation list/editor, conversation actions/search, table
definition, working-cell edit and Undo, focus/restore, and a smaller window.
The 201-row boundary, included originals and portable reopen are additionally
checked through the matching installed CLI. A sandbox denies original fixture
folders and network while reading the reopened included source.

The preview-controller suite covers stale successes/errors, request ownership,
Stop/cancel, bounded pages, exact structured values, conversation scope/history,
form retention, workflow clarification and review behavior. Contextual intake
checks cover intent/retry/idempotence, explicit conversion, lexical identifiers,
Excel cached-value limits and portable identities. Native package paths checks
verify isolated resources/signatures and unchanged engine bytes; the existing
full kernel/admission/model receipts remain the engine proof for this UI change.

No real customer workbook is changed. No fresh model download, privacy permission,
live dictation, business acceptance or automation enablement is performed. Click
paths were exercised on representative states, not every possible state/action
combination. VoiceOver, full appearance/contrast/motion, all media transport and
all platform/hardware qualification remain separate gates. The engine and agent
logic are unchanged; broad questions can still miss an included source.

## Remaining priorities

1. AI evidence selection and truthful coverage for broad requests, including the
   retained Brio PDF omission. A better activity UI does not repair the answer.
2. Reduce advanced authoring effort where useful: table schema/mappings and time
   input remain technical. Reference CSV preview/search still shows delimited
   text before explicit table conversion; a read-only grid preview is a possible
   bounded future improvement, not automatically accepted working data.
3. Complete release accessibility/appearance, hardware and distribution gates.
   This pass improves a source test preview, not a notarized production release.

Exact commands, hashes and evidence belong to [[records/operations/implementation]]
and the [immutable journey receipt](../../../integration/evidence/2026-10-29-native-journey.json.gz).
