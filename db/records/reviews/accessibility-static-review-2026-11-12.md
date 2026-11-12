---
type: review
meta-type: conclusion
id: 01m789vd03b9gfr85kgg25p5qm
created: 2026-11-12T16:35:58.595937+00:00
updated: 2026-11-12T17:14:42.209929+00:00
summary: All ten accessibility findings have code closures and static review; native compilation passes, runtime tests are skipped by owner and no conformance is claimed.
title: Adversarial accessibility code review, November 12
---
# Adversarial accessibility code review, November 12

## Code fixes after the owner follow-up, November 12

The owner subsequently authorized all ten fixes in code, while continuing to prohibit UI interaction and accessibility tests: [[sources/notes/2026/11/accessibility-code-fixes-and-pause]]. **A1 through A10 are implemented and statically reviewed; runtime accessibility remains unqualified.** The numbered findings below preserve the original baseline and line references, not current open-code defects.

| Finding | Implemented closure and static counterexample review |
|---|---|
| A1 | `NativeTable` keeps logical row/column focus for mouse, actual editing focus, accessibility focus and keyboard movement. Arrows choose columns, Return edits the active cell, Tab visits editable cells and exits at the boundary. Empty selection starts at the correct edge. Paste uses the same published column and exposes its destination. Refresh preserves logical selection; obsolete field/revision and deferred-selection callbacks cannot redirect an edit. Formula/archived cells retain their restrictions and Undo. |
| A2 | `EvidenceTable` routes snapshots, definition queries and saved dataset results through the same native readonly table. Headers carry units, row identities survive equivalent refreshes, exact scalars remain strings and original-source actions stay attached. Complex values remain available rather than being replaced by an instruction to a missing drawer. Existing pagination and partial-result labels remain. |
| A3 | `FormParameterField` includes required state, unit, constraints, repeated entry/line context and path-matched issues. Preview has an error summary; only that explicit action requests error focus, guarded by the originating route/window. Evidence Open/Clear and saved-alternative actions identify their target. Empty, false and zero retain their existing separate representations. |
| A4 | File readers expose Extracted text for the exact asset. The core reads eight passages per page in a three-second budget, caps unusually large passages at 4,000 characters with an explicit notice, and refuses continuation after a revision change. The view names the asset/extraction identity, locator, status, overlap and incomplete/OCR coverage, and returns to the original. Images have document-specific names and an optional explicit human description, saved separately as versioned annotation evidence. Size bounds, revision/previous-description guards and operation replay are retained; a concurrent description is not silently adopted as an unseen overwrite base. No descriptions are generated. |
| A5 | Charts use dataset column titles and units, state plotted/total row coverage and expose an Exact values and sources table. That table uses original scalar values, not rounded chart doubles; omitted invalid/unknown plot values stay disclosed. |
| A6 | Shared status announcements use low priority, changed terminal messages only, generation checks and the owning active key window. Initial rendering, progress tokens, clocks and background windows do not announce. Persistent text and a Read last status command remain available. Completion, review availability, copy feedback and form/document/automation failures have explicit wiring; generic operation endings do not assert business success. |
| A7 | Conversation/workspace containers and meaningful headings are named. Reading commands choose a pane; evidence opens preserve a return target, including the originating message. Focus requests recheck their identity and own window, wait for an explicitly opened sheet to return, and do not originate in polling refresh. Native sheet dismissal still owns ordinary modal return. Actual keyboard/assistive-technology order is unmeasured. |
| A8 | `ReadingStyle` supplies a persistent, app-only 100–200 percent text setting and Reading menu controls. Owned SwiftUI fonts and native table/long-text bridges use it; rows, headers, readonly column measurement and ellipsis-menu targets adapt. Fixed sheet constraints become minimum/ideal sizes, small sheets scroll, pane headers grow, and full row values have a selectable expansion with the long-text bridge. Native PDF/image zoom remains separate. No macOS preference changes occur. |
| A9 | Linked readonly cells expose direct named source actions and a link press for single destinations. Left/Right and Return provide a keyboard path; multiple sources and full values are available through Read selected row and ordinary buttons. Structured source cells require an explicit double click, Return or action rather than opening on row selection. Obsolete cell/menu actions refuse changed content. Existing message-level source alternatives remain. |
| A10 | PDF search receives Reduce Motion from its SwiftUI environment; selection animation defaults off for other callers. No unconditional animated PDF match remains. Existing motion-aware activity and nonanimated table resizing remain. |

The pass also disambiguates a pre-existing compiler warning in `ActionConfirmations` without changing its cases. Review followed the edit/paste consumers, exact-version/source resolution, stale asynchronous callbacks, multi-window ownership, copy/result status, native text bridges, settings and all owned animation call sites. This is a code-path assessment, not a spoken-output, focus-order or contrast measurement.

**Verification:** the native release `SevraDesktop` product compiles; strict Swift formatting/lint covers all 40 changed Swift files. No app was launched/installed, no workbook fixture or system setting was changed, and no accessibility or other product test was executed. The final source hashes and compiler/static-check results are retained in the [code-fix receipt](../../../integration/evidence/2026-11-12-accessibility-code-fixes.json.gz). Record validation and link results are in [[records/operations/implementation]]. CI is deliberately skipped because its standard job runs native UI/accessibility checks. Earlier CI belongs to the earlier code baseline.

The implementation uses Apple's documented [accessibility focus binding](https://developer.apple.com/documentation/swiftui/view/accessibilityfocused(_:)) and [AppKit announcement notification](https://developer.apple.com/documentation/appkit/nsaccessibility-swift.struct/notification/announcementrequested). These APIs explain the code's intent; their existence is not proof of runtime behavior.

**Owner follow-up:** exercise cell focus/paste across sort/refresh, repeated-field errors, the three result-table routes and sources, scanned text/description retention, chart exact values, terminal notices, pane/Back/modal return, text sizes and PDF motion when choosing to test. These are unexecuted suggestions, not scheduled work or authorization for the agent to resume. Production signing, other hardware and the broader product limits remain unchanged. Work returns to paused after commit/push.

## Original result and authority

The implementation has useful native controls and explicit names, but accessibility cannot be marked complete. This pass identifies ten actionable findings: six medium-priority interaction/content gaps and four lower-priority presentation/navigation gaps. Some are direct code defects; others are integration risks whose actual spoken or visual behavior is not established. None was reproduced by running accessibility tests in this pass.

The owner selected code review instead of accessibility testing and required the UI to remain untouched: [[sources/notes/2026/11/accessibility-review-and-pause]]. No VoiceOver, keyboard, screen-reader, contrast, appearance or UI automation test was run for this review. The earlier incomplete VoiceOver attempt is not qualification. These findings supersede any interpretation of the prior label inspection as an accessibility pass. Product code was unchanged in that initial review. The later implementation status above supersedes its open-code status.

Reviewed code is `831b7f3b1181b0fa8218f5d77e08cd992fd17246`. The [static inventory](../../../integration/evidence/2026-11-12-accessibility-static-inventory.json.gz) records hashes for 511 source, resource and tooling files, including all 284 Swift source files and 57,881 Swift source lines. That is an inventory boundary, not a claim that every non-UI algorithm was individually audited. Direct review concentrated on every native presentation surface, AppKit bridge, keyboard/action handler and the state paths they expose. Supporting extraction, references, calculation, AI completion and scheduling paths were traced where they affect the experience. Scripts, CLI, engine adapters and non-UI core received inventory/pattern and boundary review; vendored engine internals and operating-system accessibility implementations were not audited.

## Surface coverage

| Surface | Code reviewed and boundary considered | Result |
|---|---|---|
| Window, welcome, settings and commands | `SevraApp`, `WelcomeView`, `WorkbookView`, `SpeechAndSettings`, `PaneHeader`, `MoreActionsMenu`, `WorkspaceState`; model setup state | Native menu/shortcut routes and named controls retained; no general text zoom or explicit pane/heading structure. |
| Conversation and activity | `ConversationViews`, `ConversationBlocks`, `AgentActivityView`, `CapturedRequestContextView`, history sheet/search, scroll observer, composer and conversation sessions | Stop, plain text, draft preservation and alternate source actions exist; terminal-state discovery and direct table link actions remain weak. |
| Search and navigation | `ContentViews`, `SpacePickerView`, `SearchSession`, space navigation, reference browser/picker and exact-target resolution | Named search and explicit selection paths exist; result navigation lacks an app-wide accessibility focus/return policy. |
| Editable and readonly tables | All six `SevraTableUI` files, `ReadOnlyTableView`, delimited previews, `TableUpdateView` and update/session code | Version-bound edits and row/column names are useful; active-column mismatch and alternate grid semantics are open. |
| Forms and review | `FormComponentView`, `WorkflowClarificationView`, `ReviewQueueView`, intake, definition and workflow views, form/clarification/review sessions | Review remains explicit; repeated fields omit line context, required/unit context and error association. |
| Spaces, computed output and charts | `ContentViews`, `DefinitionComponentView`, `StructuredValueView`, `SpaceLayoutEditor`, component data and comparison outputs | Live tables are stronger than snapshot/query grids; chart axis names are generic. Layout movement has button alternatives. |
| Documents and originals | `Viewers`, `ReferenceViews`, all document UI helpers, long text views, asset previews, archive picker and extraction paths | Native text/PDF/Quick Look and link panels provide alternatives; image/OCR text does not have a direct complete reading route. |
| Audio and dictation | `NativeMediaPlayer`, transcript view, all `SevraVoice` files and transcription boundaries | Typing remains available, playback ownership is explicit, transcript timestamps are buttons. No claim about AVKit caption discovery or spoken controls. |
| Automations | Schedule list/detail/editor/focused view, native host/controller/registry, workflow activity and clarification | Separate Enable/Pause and saved permission checks retained; live refresh is functionally proven separately, not accessibility-qualified. |
| Engine, CLI and other core | Repository-wide control/gesture/focus/accessibility/animation scans plus targeted errors, receipts, evidence, formulas and grants | No additional product GUI discovered outside the mapped surface modules. Their functional correctness is not a substitute for accessibility. |

## Findings and ways to close them

### A1. P2: keyboard and editing focus do not own the table's active column

**Direct code gap.** [NativeTable.swift](../../../Sources/SevraTableUI/NativeTable.swift), lines 8–60, changes `activeColumn` on mouse interaction and uses it for Return-to-edit. `controlTextDidBeginEditing`, lines 235–240, sends the actual column to the parent but does not update the table's own `activeColumn`. Later selection publication, lines 263–281, publishes that older value again. [ContentViews.swift](../../../Sources/SevraApp/ContentViews.swift), lines 628–636 and 787–793, stores that column and uses it as the paste destination. The help explicitly describes the last clicked column.

A user who reaches another field without a mouse has no equivalent explicit column-navigation contract. Selection/refresh can restore a stale column after editing. This is a plausible wrong-column edit/paste path, not a claim that an observed paste corrupted data. Existing exact-row/revision checks protect stale versions, not the intended destination column.

**Closure:** one cell-focus state keyed by logical row and column identity, updated by editing, keyboard movement, native focus and mouse selection. Make Enter and paste consume the same state. Add explicit previous/next editable cell behavior, preserve identity across sort/refresh, and expose the destination before paste. Code review should trace every focus producer and every edit/paste consumer to this state; keep existing revision guards and Undo.

### A2. P2: table semantics disappear in snapshot, query and saved-result views

**Direct presentation gap.** [ContentViews.swift](../../../Sources/SevraApp/ContentViews.swift), line 416, [DefinitionComponentView.swift](../../../Sources/SevraApp/DefinitionComponentView.swift), line 129, and [StructuredValueView.swift](../../../Sources/SevraApp/StructuredValueView.swift), line 156, build ordinary `Grid`/`GridRow` children. They do not bind each value to its row and column through an explicit accessibility representation. The ordinary live/readonly table code does provide those names. Pinning or inspecting the same data changes the semantic contract. A framework may expose the text, but that does not prove table navigation or header association.

**Closure:** share a readonly table presentation that carries stable row identity, header, value, unit and source actions for all three routes. Preserve exact scalar values and paging. If a compact grid remains, give each row/value an equivalent structured representation. Review all producers, including saved tool results, rather than fixing only the live table.

### A3. P2: form labels omit required state, units and repeated-line context

**Direct metadata gap.** [FormComponentView.swift](../../../Sources/SevraApp/FormComponentView.swift), lines 171–270, displays a required asterisk and separate unit/help text, but the field's explicit accessibility label contains only `title`. Repeated entries recurse with the same field labels and no line identity. The remove-line button does include its line number, showing that context is available. Validation issues appear separately from the affected control; the field has no issue input.

**Closure:** pass line context, required state, units, constraints and current validation issue into the field presentation. Associate errors with their fields and provide a short error summary on an explicit submission attempt. Repeated Open/Clear/Remove actions should identify their evidence or line. Do not move focus during autosave or while someone is typing. Preserve the distinction between an empty value, false and zero.

### A4. P2: image and scanned-PDF readers lack a direct extracted-text alternative

**Direct route gap, not an OCR accuracy claim.** [Viewers.swift](../../../Sources/SevraApp/Viewers.swift), lines 832–879, renders an `NSImage` without a content description or document-specific accessibility label. The PDF route delegates to PDFKit and already acknowledges that scanned pages may only be searchable through workbook OCR. The extraction footer contains status, not the extracted document text. The links panel exposes link occurrences, and saved tool receipts can contain selected excerpts; neither is a complete document reading route.

**Closure:** add a bounded, selectable Extracted text view for the exact asset/extraction version, with page/image locators, extraction status, partial-coverage notice and a route back to the original. Name the image with its document title; allow an explicit user description for non-text images. Mark OCR as derived and potentially wrong. Do not invent image descriptions or mistake OCR availability for complete reading order. Preserve native tagged-PDF behavior where it exists.

### A5. P2: charts use generic axis names and lack an explicit exact-value alternative

**Direct metadata/route gap.** [ContentViews.swift](../../../Sources/SevraApp/ContentViews.swift), lines 436–444, supplies `Category` and `Value` to every line/point/bar mark, even when the dataset carries meaningful column titles and units. A separate caption does not explicitly associate the unit with each value. Swift Charts has native accessibility behavior, so this is not a claim that charts are invisible to a screen reader.

**Closure:** use real column titles, units and current view scope; add an accessible chart summary and a direct exact-values table with source actions. Preserve decimal strings for the alternative instead of reconstructing them from chart `Double` values. Do not convey a series or qualification only through color.

### A6. P2: completion, failures and review requests have no explicit announcement policy

**Integration risk supported by absent application wiring.** Searches across owned source find no explicit accessibility notification/announcement service or accessibility focus binding. Global errors, copy feedback, form issues and workflow states update text in different parts of the window. Native controls may announce some changes automatically; static code cannot establish which ones are discoverable from the user's current position.

**Closure:** define one deduplicated terminal-event channel for completion, failure, required review and explicit copy confirmation. Keep the visible status and announcement derived from the same event. Preserve a stable action to reach the result/error. Do not announce token streams, elapsed seconds or every autosave; do not steal focus on automatic refresh. This closes an application-design gap, not the unmeasured operating-system behavior.

### A7. P3: visual headings and panes have no consistent semantic navigation model

**Integration risk.** `PaneHeader`, workbook panes, review sections and document/definition headings rely primarily on font and layout. No explicit heading traits were found. Existing search/history fields and the destination picker do manage initial keyboard focus, so focus handling is not wholly absent. Opening evidence or changing the workspace route does not have one shared accessibility destination/return policy.

**Closure:** label conversation/workspace containers, mark meaningful heading levels, and preserve a return target for user-initiated open/close navigation. Keep background refresh out of that policy. Review source-action navigation, modal replacement and Back together so newly added semantics do not duplicate children or trap focus.

### A8. P3: fixed text metrics and fixed sheet dimensions limit adaptation

**Direct sizing constraints with unmeasured impact.** Editable and readonly tables use 13-point fonts; the editable row is 30 points and the readonly row has a bounded line count. Long-text bridges use fixed AppKit font metrics. Several settings/intake/history/editor sheets specify fixed dimensions. There is image zoom, but no shared app text/table zoom control. This review did not measure clipping or contrast on any display or assert that macOS scaling is ineffective.

**Closure:** shared app presentation metrics and a persistent text-size/zoom control, with table row heights and column measurement derived from the chosen font. Make sheets scrollable with bounded minimum/ideal sizes. Keep selection/focus visible and retain full values through a readable expansion. Use semantic system colors and account for increased contrast without changing system settings.

### A9. P3: readonly table links are static-text cells with indirect alternate actions

**Direct semantic gap with an existing workaround.** [ReadOnlyTableView.swift](../../../Sources/SevraPreviewUI/ReadOnlyTableView.swift), lines 74–78 and 385–388, labels linked cells as source links but assigns a static-text role. `openClickedLink` relies on clicked row/column; menu construction uses a mouse event. However, [ConversationViews.swift](../../../Sources/SevraApp/ConversationViews.swift) provides source accessibility actions and message menus, and saved document text has ordinary link buttons in its accessibility representation. Do not report all citations as unreachable.

**Closure:** expose each linked cell's destination actions directly with row, column and source context, and a keyboard open-selected-source route. Retain existing message/document alternatives, especially when one cell contains several links. Do not turn row selection into an accidental open action.

### A10. P3: PDF match navigation requests animation outside the Reduce Motion policy

**Narrow code gap; actual PDFKit behavior unmeasured.** [Viewers.swift](../../../Sources/SevraApp/Viewers.swift), line 606, unconditionally uses `setCurrentSelection(..., animate: true)`. In contrast, `ActivityShimmer` explicitly handles Reduce Motion, increased contrast and scene activity, and readonly table resizing avoids animation. There is no basis for a blanket claim that motion preferences are ignored.

**Closure:** route the PDF selection animation request through the same motion preference policy, retaining an immediate visible selection and status. Review future animations at their call sites; do not change the Mac preference to inspect this.

## Defenses to preserve and qualification boundary

Keep native controls and dialogs, explicit Stop/Command-period, row/column names, semantic system colors, editable-field/version guards, textual error and state wording, motion-aware activity, selectable text, transcript timestamp buttons, saved-link actions and typed alternatives to dictation. Static review found no reason to remove these safeguards. Decorative vector brand geometry is not business evidence; do not add redundant spoken path descriptions.

Prior functional keyboard/window observations remain valid for their exact cases. They do not establish Full Keyboard Access, VoiceOver speech, Switch Control, Voice Control, actual contrast, enlarged text layout, assistive-technology focus order or third-party PDF/Quick Look/AVKit behavior. Those runtime qualifications are deliberately not being pursued under the owner's current decision. Static remediation can be assessed by code inspection, but must not be relabeled as a tested accessibility pass.

[[records/plans/known-limit-closure-2026-11-12]] gives implementation boundaries and future ordering. [[records/operations/agent-handoff]] records the paused checkpoint. All ten findings now have the code closures above. None is labeled runtime-tested.
