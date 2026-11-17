---
type: spec
meta-type: conclusion
id: 01m7mskdhjs58amvzbavb8xqpf
created: 2026-11-17T13:02:07.410203+00:00
updated: 2026-11-17T13:02:07.410203+00:00
summary: 'Reviewed native UI catalog plan: real renderers, isolated fixtures, complete capability inventory, state flows and compositions across app, Home, mini apps and chat.'
title: Native Storybook for Sevra
status: reviewed
---
# Native Storybook for Sevra

## Decision, scope and status

Build **Sevra UI Catalog**, a separate native development application that displays the actual Sevra interface with disposable synthetic workbooks. It should answer: what can this interface express, how does it behave, where is it usable, and what happens when something goes wrong?

Cover four surfaces: the main application, ordinary spaces and Home, programmable mini apps, and chat. Browse components, change their inputs, inspect states, assemble supported compositions, and replay representative interactions. A gallery of screenshots alone does not meet this requirement.

**Planning only. No implementation is authorized by this record.** Source audit baseline: `4414522951ce36cfc19a727c3be8378296c71f16`, November 17, 2026. Working tree was clean when inspected. No app was launched, installed or controlled, and no existing functional test was rerun for this plan. The source inventory is current to that commit, not a claim about uninspected future changes.

Authority: [[sources/notes/2026/11/native-storybook-planning]]. Related contracts: [[records/plans/rich-native-visuals]], [[records/specs/chat-primary-operation]], [[records/specs/programmable-native-engine]], [[records/specs/local-model-native-apps]], [[records/specs/distribution]]. Those records retain their existing qualification limits. A catalog does not qualify model reliability or a production release.

## 1. What exists today

| Existing code | Reusable foundation | Gap |
| --- | --- | --- |
| `Package.swift`; `Sources/SevraApp/SevraApp.swift` | Native SwiftUI application with AppKit integration and separate native build configuration | No catalog executable/build mode, registry, browser or story controls |
| `Sources/SevraApp/WorkbookView.swift`, `WorkspaceState.swift`, `ContentViews.swift`, `HomeViews.swift` | Real application layout, routes, Home and ordinary-space renderers | Most views are internal to the executable; state is coupled to preferences, model and automation singletons |
| `Sources/SevraAppUI/NativeAppRenderer.swift`, `NativeAppSession.swift`, `NativeAppSpaceView.swift`, `NativeAppDeclaredView.swift` | Production AppKit tree renderer, real worker-backed sessions, grants, saved drafts and named views | No interactive inventory of primitive variations or composed apps |
| `Sources/SevraAppProtocol/NativeAppProtocol.swift`; `sdk/index.d.ts`, `sdk/src/runtime.ts` | Canonical native node/property contract, validators, actions and interactions | No mapping from supported capability to explorable example |
| `Sources/SevraVisualUI/` and `Sources/SevraMedia/` | Shared charts, work views, diagrams, overviews, text and image decoding | No visual state gallery or cross-surface comparison |
| `Sources/SevraPreviewUI/` | Production conversation inputs, presentation, preview sessions, draft and navigation helpers | Despite its name, this is not a developer preview browser |
| `Sources/SevraTableUI/`, `SevraDocumentUI/`, `SevraSearchUI/`, `SevraAutomationUI/` | Tables, reading, search and automation controllers | Fixtures/checks are distributed across integration executables |
| `IntegrationTests/Preview/Checks.swift`, `TableSnapshots.swift`, `VisualMediaChecks.swift` | Programmatic behavior checks and a real offscreen `NSHostingView` capture path for Markdown tables, CSV/TSV and formula reports | Capture coverage is narrow; it is not a navigable full-app catalog |
| `IntegrationTests/NativeApps/`, `scripts/check_native_apps.py`, `scripts/check_native_app_authoring.py` | Real native controls, signed isolated XPC packaging, semantic-action and authoring checks | Passing test groups are not component or visual-state coverage |
| `Sources/SevraCore/Demo.swift`, `examples/apps/{inventory,jobs,planner}/`, `IntegrationTests/Agent/ConversationSurfaceChecks.swift` | Synthetic business data, actual mini-app packages and scripted inference through the real agent loop | No shared catalog fixture lifecycle or discoverable composition library |

A source search found no `#Preview`, `PreviewProvider`, Storybook implementation or native UI catalog in the inspected source/test/example directories. Do not describe the old “20 native / 21 preview groups” as two UI libraries: those were verification group counts at a checkpoint.

Apple supports interactive previews for both SwiftUI and AppKit. They can be a later convenience for individual components, but the recommended delivery here is a standalone native catalog: this repo needs workbook fixtures, XPC workers, state transitions and full-window compositions in one browsable place. See [Apple's preview documentation](https://developer.apple.com/documentation/xcode/adding-previews-to-your-interface-files) and [interactive canvas documentation](https://developer.apple.com/documentation/xcode/interacting-with-previews-in-the-canvas). No third-party Storybook framework or web rendering layer is needed.

## 2. The catalog experience

### Navigation and workspace

Use a native split interface: searchable outline on the left, the selected example in the center, and a collapsible inspector on the right. Main groups are **Main app**, **Home & spaces**, **Mini apps**, **Chat**, **Shared visuals**, and **Compositions**. Components remain listed once, with links to every supported host surface.

Within each group distinguish **Components**, **States**, and **Flows**. Search matches titles, stable story IDs, control names, capabilities and source filenames. Filters show surface, component family, interaction support and coverage gaps. Default to a curated, useful composition, with a short explanation and obvious controls, rather than a giant grid of unrelated widgets.

The preview toolbar provides:

- Scenario/state selector, Reset, and Replay when the story has steps.
- Actual content width and height, light/dark appearance, and Sevra reading size.
- Open in a dedicated catalog window for complete app layouts, focus, sheets and popovers.
- Copy reproducible story configuration; capture PNG and a small metadata receipt.

The inspector has three concise sections: **Inputs** (editable supported properties), **Behavior** (actions and observed outcomes), and **Implementation** (source, capability coverage and limitations). Keep technical details here, outside the rendered product interface. A persistent catalog badge identifies synthetic data and any simulated service. Do not alter the product views with story labels.

At smaller catalog window sizes collapse the inspector and sidebar before squeezing the example. Record the example's actual point size independently from the catalog window size. Full app examples use a real window and its minimum constraints, not a scaled screenshot pretending to be a compact layout.

### Controls and composition

Use native fields, pickers, toggles and bounded steppers for values, labels, option lists, row count, selections, layout and state. Offer useful presets first: empty, ordinary, dense, long text, missing data, failure and recovery. A raw definition view is available for inspection/copy; editing JSON is not the primary workflow.

The composition explorer edits existing production structures:

- Ordinary spaces/Home: `SpaceDefinition`/`Component`, through existing validators and editing commands; reorder, replace, nest a comparison, change headings and bindings.
- Mini apps: curated SDK composition recipes compiled through the existing SDK build path; edit typed recipe parameters, not a second arbitrary-code IDE.
- Shared visuals: `VisualDefinition`, typed queries, presentation presets and real renderer options.
- Chat: defined sequences of messages, typed surfaces, approvals, captures and operations. Do not invent an arbitrary app-tree message type.

An invalid proposal stays in the inspector with the actual validation error and last valid preview. It must not be silently clamped into an apparently valid saved configuration. Keep transient property editing separate from actions performed inside a story; Reset explicitly rebuilds both. Initial scope includes reusable recipes and reproducible configurations, not a new drag-and-drop application builder.

### Cross-surface comparison

Select a supported visual and compare its **captured chat result**, **live Home version** and **mini-app version** with the same synthetic input data. Change a record and see which surfaces update. Keep a visible explanation of captured/current values, permissions and supported interactions.

Use independent fixture clones for ordinary side-by-side variants so editing one does not contaminate another. For the explicit cross-surface flow, share one workbook and the same app session within one workspace, matching production. Distinguish these two modes in the inspector.

## 3. Coverage contract: finite, explicit and useful

“Every possible arrangement” cannot mean enumerating every arbitrary data value or generated JavaScript program. The deliverable is complete registration of supported capabilities, declared state families and composition rules, plus representative interactions and boundary combinations.

Use stable IDs such as `mini.input.decimal.invalid`, `home.attention.customized`, `chat.question.draft-conflict`, and `composition.inventory.chat-home`. Each story declares:

1. Title, surface/level, capabilities and actual renderer/source symbols.
2. Fixture recipe/version and supported editable inputs with valid ranges.
3. Initial state and applicable variants; explicit reasons for inapplicable states.
4. Supported actions, expected transitions, and the real production operation they exercise.
5. Fixture mode: actual workbook/worker, deterministic inference, or simulated external service.
6. Readiness condition, reset/teardown contract and optional capture exclusions.
7. Evidence status, captured configuration and known limits.

Use separate statuses for **registered**, **rendered**, **interaction checked**, and **visually reviewed**. A registered story is not a passing test. Include **missing**, **blocked**, and **not applicable with reason** in the coverage view. Do not roll different forms of proof into one green percentage.

The component inventory also includes shared application chrome: `PaneHeader`, `MoreActionsMenu`, `ObserverMark`/`SevraWordmark`, reading-font and status presentation, `EvidenceTable`, structured values, long-text/readonly-table presentation, reference links, form fields and progress/empty/error patterns. These are production components in `SevraApp`, `SevraPreviewUI` and `SevraTableUI`, not new catalog-only widgets. Show keyboard focus, selection, hover/pressed where meaningful, labels/help and disabled controls. Preview color/contrast/motion or locale variations only where the component accepts a scoped override; list AppKit/OS settings that cannot be faithfully simulated. Use the existing reading scale, currently 1–2, rather than assuming a mobile Dynamic Type control will affect Sevra.

Coverage authorities at the audited commit:

- `NativeAppNode.types`: **22 native node types**; SDK aliases/helpers must also be mapped.
- Ordinary spaces: **14 content component types + 8 host sections**.
- `VisualDefinition.Kind`: **6 visual families**, with surface-specific restrictions.
- `VisualChart.Style`: **12 styles**; grouped bars are a series configuration, not a thirteenth style.
- `WorkVisual.Style`: **4 styles**.
- `ConversationSurface.Field.Kind`: **5 field types**. Surface kind names alone do not establish live UI support.
- `WorkspaceState.Route` and modal/menu entry points: every route and every user-facing secondary surface needs a registry entry or an explicit coverage gap.

For closed Swift enums/sets, compare the registry to the production source of truth using existing constants or a small `CaseIterable` conformance where appropriate. For string-based ordinary-space types, extract the existing allowed set into one canonical constant if needed, preserving validation behavior. For routes with associated values and modal surfaces, maintain an explicit fixture inventory; do not invent reflection that purports to discover all states. A changed route/rendering branch must update its entry during implementation/review.

No Cartesian explosion. Every primitive gets a meaningful default and its relevant disabled/empty/invalid variants. Each semantic boundary gets a targeted counterexample. Dense layout, long labels, narrow width and enlarged text get curated combinations where they interact. Whole-screen combinations are selected for actual tasks.

## 4. Main app coverage

Mount the existing views, including their real command/focus behavior, wherever feasible. Extract private subviews only when necessary to reuse them without duplicating product markup.

| Story family | Required examples and transitions | Production owner |
| --- | --- | --- |
| `main.welcome` | No recents, populated and expanded recents, missing recent file, create/open/example, opening failure | `WelcomeView.swift`, `SevraApp.swift`, `Demo.swift` |
| `main.shell` | Workbook/chat split, workspace focus, title overflow, busy/Stop, error banner, back/Home navigation, current/missing route | `WorkbookView.swift`, `WorkspaceState.swift`, `PaneHeader.swift` |
| `main.navigation` | Space picker search, pinned/recent/all spaces, no matches, pin/unpin/reorder, return to same item/message/scroll position | `SpacePickerView.swift`, `SpaceNavigationSession.swift`, `SpacePickerSections.swift` |
| `main.commands` | File/workbook/conversation/reading menus, keyboard shortcuts, contextual actions, disabled states, focus owner | `SevraApp.swift`, `MoreActionsMenu.swift`, `ReadingSizeCommands.swift`, `ConversationViews.swift` |
| `main.search` | Initial, loading, results, no results, facets/history, pagination, incomplete index, failure/Retry, late result after navigation | `ContentViews.swift`, `SevraSearchUI/` |
| `main.table` | Empty/populated/dense, selection, cell edit, formula result/error, filter/sort/page, column editor, bulk paste validation, copy, archived/read-only, Undo/Redo and conflicting update | `ContentViews.swift`, `SevraTableUI/` |
| `main.document` | Current and historical versions, editable note/draft/save/conflict, source/provenance links, return to citation, missing source | `Viewers.swift`, `SevraDocumentUI/`, `ReferenceViews.swift` |
| `main.file-viewers` | PDF search/zoom/page/match/no-match/failure; text and extracted text; CSV/TSV; included/linked/missing image; audio/video/transcript; Quick Look supported/unavailable; archive contents | `Viewers.swift`, `ExtractedTextView.swift`, `NativeMediaPlayer.swift`, `ArchiveMemberPicker.swift`, `ImageDescriptionView.swift` |
| `main.intake` | Include/link/folder/paste input routes, progress/Stop, role selection where applicable, resumable extraction, partial/failure, table mapping/diff/review, accept/reject | `IntakeView.swift`, `TableUpdateView.swift`, `WorkspaceState.swift`, `SevraTableUI/TableUpdateSession.swift` |
| `main.excel` | Imported original, purpose draft, analyzing, attention/clarification, building, ready, just tables, original evidence/comparison examples, result mismatch, failed/retry/reopen | `ExcelConversionView.swift`, `NativeAppImport.swift` |
| `main.review` | Empty/paged queue, current versus superseded proposal, accept/withdraw/Undo, busy and stale-version refusal | `ReviewQueueView.swift`, `ReviewQueueSession.swift`, `Viewers.swift` |
| `main.definitions` | Calculation/query parameters, complete/empty/unknown/error result, publication, form draft validation, evidence picker, conflict/recovery | `DefinitionComponentView.swift`, `FormComponentView.swift` |
| `main.workflows` | Queued/running/review/needs-attention/completed/cancelled; step receipts, inputs, evidence clarification, retry with retained prior results | `WorkflowActivityView.swift`, `WorkflowClarificationView.swift` |
| `main.automations` | Empty/list/focused/detail, schedule editor and occurrence preview, device grant/disarmed/armed/stale, paused reason, run receipt/failure, repair | `AutomationSchedulesView.swift`, `AutomationScheduleEditor.swift`, `AutomationFocusedView.swift`, `SevraAutomationUI/` |
| `main.settings` | Appearance and reading size; model missing/installing/installed/loading/failure/cancel/retry and unload outcome | `SpeechAndSettings.swift`, `SevraProduct/` |
| `main.voice` | Idle, recording, recognition/transcription pending, partial text, complete, denied/unavailable, Stop, draft preservation | `SpeechAndSettings.swift`, `SevraVoice/`, composer |
| `main.lifecycle` | Flush drafts before close/switch, failure preserving draft, reopen, two isolated workbook windows, second view of same fixture for conflict stories, teardown during active work | `SevraApp.swift`, `WorkspaceState.swift`, document/form/conversation sessions |

File picker, download, microphone, external application and scheduler examples default to controlled service boundaries. Show their real app-owned presentation and result handling. OS-owned dialogs/permissions, real downloads and actual hardware remain separately labeled manual qualification, not simulated proof.

## 5. Home and ordinary spaces

Home is a versioned ordinary `SpaceDefinition` with host-owned sections and special attention fallback. It can embed a whole mini app or a named declared app view; it is not interchangeable with the programmable app root.

Register all content kinds from `Spaces.swift`: `table`, `chart`, `metric`, `comparison`, `document`, `asset`, `search`, `text`, `form`, `calculation`, `query`, `app`, `image`, `visual`. Register all sections from `SpaceEditing.swift`: `input`, `reviews`, `shortcuts`, `tables`, `intake`, `recent`, `attention`, `continue`.

Required Home stories:

- Fresh default: no work yields the actual start prompt. Default layout contains attention/continue/shortcuts; context filters their visibility.
- Returning work: recent space, documents and usable Excel imports; already embedded apps are not repeated as the continue suggestion.
- Attention: pending approval, draft review, workflow input/failure, unfinished Excel import and extraction, individually and together.
- Customized Home without an attention section, with pending work: production fallback keeps that work reachable. Include occupied fallback component IDs.
- Explicitly emptied later Home versus initial unconfigured Home; Reset to defaults; hidden irrelevant sections; independent ordinary empty space.
- Full app embed, named view/preset embed, disabled/revoked app, missing app, changed app version and unavailable declared view.
- Live visuals versus saved snapshots, same data changed after capture, source unavailable, empty query and missing binding.
- Layout editor: rename, reorder, replace/remove, text, image selection/caption/description, history/restore, save conflict retaining draft.
- Comparison at wide and narrow widths, nested components up to supported depth, maximum legal component count and one refused over-limit example.

Composition presets: a focused start page, inventory dashboard, supplier comparison, project board with timeline, and a mixed evidence/report page. Keep the actual 16-component / three-level limits; do not promise arbitrary nesting or dashboard grids not supported by the current renderer.

## 6. Mini apps

### Primitive inventory

| Family | Actual node types | Important variants |
| --- | --- | --- |
| Layout | `column`, `row`, `grid`, `split`, `scroll`, `section`, `spacer` | Alignment, gap/padding, fixed/flexible dimensions, overflow, horizontal/vertical split, nested scrolling, disabled/hidden ancestor |
| Navigation | `tabs`, `disclosure` | Selected/expanded/collapsed, long titles, changing children, restore draft, removal of selected child |
| Text/status | `text`, `progress` | Weight/size/semantic color/selectability, multiline/long text, determinate/indeterminate |
| Inputs | `textField`, `textEditor`, `toggle`, `picker`, `slider`, `date` | Initial/edited/cleared, no selection, extremes, options replacement, labels/help, enabled/disabled/hidden, focus and edit revisions |
| Actions | `button` | Roles, busy/disabled, success/error, repeated invocation, stale/removed handler |
| Data | `table` | Empty/paged/dense, columns/labels, query/search/sort, selection, writable/read-only, update and Undo/Redo |
| Rich content | `canvas`, `image`, `view` | Canvas rect/circle/line/text and regions; symbol versus included asset/caption; every supported declared visual view |

Also cover SDK `Fragment`, `Workspace`, `ActionForm`, keyed `For`, signals/computed/effect/batch updates, `draftSignal`, `liveQuery`, deterministic `calculate` and declared `action` operations as compositions/behaviors. Helpers are not additional primitive widgets. `ActionForm` has its own generated input/result behavior: text, decimal, boolean, number, date and record inputs, optional/required values and supported string choices. Its six action input types are distinct from the five conversation field types.

**Concrete declaration gap found during review:** `sdk/src/runtime.ts` exports `action` and `ActionForm`, but the inspected `sdk/index.d.ts` does not declare them; `NativeProps` also lacks the native `viewID` property. Register against runtime, protocol and declarations together, not declarations alone. Include aligning these existing public declarations in the implementation's capability pass, with a focused type-check of the actual examples. This is an existing authoring-contract mismatch, not authorization to invent more widgets. Internal SDK transport exports do not become catalog/user capabilities.

### Runtime and authority

Use packaged SDK source and the actual signed XPC worker for normal interactive mini-app stories. Reuse `NativeAppSession` and renderer. Existing `defaults:` and `exchange:` seams are useful: isolated defaults for every story; controlled exchanges only for explicit transport/protocol failure stories. Do not replace all worker sessions with in-process fake trees.

Include enable/access review, read-only and writable dataset aliases, start/loading/running, script failure/restart, worker interruption, grant revoked while a read/action is pending, changed app version requiring new approval, malformed frame retaining the last valid tree, resource-limit refusal, and cancellation after leaving the story. Include input drafts restored after remount/reopen and refused stale revisions.

Canvas examples cover click, drag, keyboard activation/movement, removed regions and disabled ancestors. Tables cover semantic operations, not just visible cell edits. Three real examples seed the compositions: Inventory, Jobs and Visual Planner. Extend their fixtures only where useful; do not turn each test into a demo page.

For a representative writable app, submit the same inputs through native controls and through chat's semantic app actions against independent copies. Compare saved data/receipt, validation failure and Undo/Redo. Label free-form language as scripted when the model is replaced. This proves action-path parity, not language-model success.

## 7. Shared visual and media coverage

| Family | Required repertoire | Data/state boundaries |
| --- | --- | --- |
| Charts | `bar`, `horizontalBar`, `stackedBar`, `line`, `area`, `scatter`, `donut`, `histogram`, `heatmap`, `metric`, `table`, `records`; grouped series where supported | Empty/one/many, exact decimals/units, missing versus zero, negative values where valid, multiple series, long labels, thresholds/annotations, selected point, sources and paged contributors |
| Work | `board`, `timeline`, `agenda`, `calendar` | Empty lanes/dates, unknown/unassigned records, range boundaries/overlap, thumbnails, multiple pages with truthful page scope, narrow layout, record navigation, supported move/date edit and Undo |
| Diagrams | Dependencies/relationships with native nodes/edges | Chain, branch, cycle, disconnected nodes, long labels, saved positions, fit/zoom/select, layout worker failure/fallback, bounded dense graph, record navigation |
| Overview | Two through eight panels | Responsive 1/2/3 columns, mixed chart/metric/table panels, same captured snapshot, source drilldown per panel, empty panel and failure |
| Rich text | Paragraph, bullet and callout blocks | Strong text, multiple blocks, long text, source links where supported, empty/refused invalid definitions |
| Images | Included asset, symbol where supported, thumbnail and expanded viewer | Portrait/landscape/transparency, caption/accessibility description, decode/loading/error/Retry, missing/corrupt/unsupported asset, bounded decoding, source navigation and grant revocation |

Each relevant family gets captured and live presentations. Live wrappers must expose initial load, refresh, last valid stale result, failure, Retry and cancellation as actually implemented. Register a visible gap if a renderer currently lacks a state; do not manufacture the desired product UI in the catalog.

Current limits are part of the controls: charts query up to 100 marks, work pages up to 100 records, diagrams up to 100 nodes/200 edges, overviews 2–8 panels. Take other bounds from canonical validators; don't duplicate an obsolete plan's proposed limits. Over-limit examples exercise refusal, not silently incomplete visualization.

Surface differences are intentional:

- A chat result stores captured values; subsequent writes do not change its past answer. Work-view controls in captured chat do not become live record editors.
- Home's owner-bound work view can offer its supported mutations. Declared app work views currently do not receive the owner editing closure; mutations run through app actions.
- App chart links, transient filters/selections and saved presets retain app authority. A pinned view cannot bypass disabled/revoked access or app-version binding.
- App images use declared image aliases/native image nodes and thumbnail aliases. `VisualDefinition` currently refuses an app-owned image definition; do not advertise a declared image `View` simply because images exist in Home/chat.
- Bounded rich text is not arbitrary HTML, and the catalog does not add inline arbitrary mini-app execution to chat.

Include PNG/PDF/CSV chart export where supported, real decoded image pixels, expanded visuals, source navigation and denied/unavailable cases. Use the actual export/decoder helpers, not placeholder images that bypass them.

## 8. Chat components, states and flows

Use `WorkbookView`'s conversation/composer and `ConversationMessageRow`, not a parallel chat transcript renderer. Extract the current conversation/composer into internal production views if needed for isolated mounting; retain their existing focus, scrolling, commands and state ownership.

| Area | Required examples |
| --- | --- |
| Message content | User/assistant/system roles as supported, short/long Markdown, links/citations, inline read-only tables, selectable text, structured activity and source excerpts |
| Composer | Empty/multiline/draft restored, selected context and captured request context, busy/Stop, unavailable model, attachment/paste/drop states, voice status, keyboard submit/focus |
| Activity | Preparing/running phases, elapsed time, expandable steps, prepared without final receipt, complete, needs_input, needs_review, cancelled, failed, continued, interrupted |
| Choices | One/multiple choices, long labels, enter custom answer, choice values exactly matching typed schema, enabled/disabled/busy |
| Fields | Text, boolean with unanswered distinct from false, decimal, date, record picker; required/optional, valid/invalid, duplicate labels with stable record IDs, missing candidate |
| Input lifecycle | Draft edit/save/clear, restoration, concurrent draft conflict/load saved fields, submit exactly once, ordinary request versus explicit `Answer:`, selected question target, multiple pending questions, decline, cancel |
| Continuation | Saved answer awaiting retry, continuation failure/retry, request scope after answer, navigation during submission, duplicate/outdated answer refusal, closed question shown as history |
| Approvals and changes | Exact confirm/cancel, typed confirmation path, outdated approval, no authority from a visual alone, success receipt, Undo/Redo and superseded/conflicting reversal |
| Visuals | All supported captured visual families, image captions/expand/source, expanded chart/diagram/overview, exact values and sources, Add live view to Home, Open current view, unavailable/current version changed |
| History | Earlier/later pages, search/no results, chapters/bookmarks/threads, rename, saved summary, return from source, restored scroll/draft, new activity while reading older messages |

A useful acceptance flow is: request comparison → choose basis or fill typed fields → see cited captured chart → pin live view → edit a record through chat → Home changes while the old chart stays fixed → inspect source → Undo. The second is app input validation → correction → exact approval when required → saved receipt → reopen. The third is two pending questions with independent drafts and an interrupted continuation.

Use the real `ConversationInputDraft`, surface submission and approval machinery. Script only inference replies or externally timed failures. Never insert a fake success bubble in place of an actual workbook mutation. Scope, request lineage and current/historical state must remain inspectable.

## 9. Architecture and fixture isolation

### Development build, not a second implementation

The lowest-risk initial approach is a **compile-time catalog variant of the existing `SevraApp` target**, packaged as `Sevra UI Catalog.app` with its own bundle identifier and output/scratch directories. The target is an executable and its main views are internal; a separate target cannot simply import those views. Moving the entire app into a new public UI library is unnecessary for this feature.

Proposed flag: `SEVRA_UI_CATALOG`, combined with the existing native-candidate configuration. Guard the product `@main` entry and add a catalog `@main` entry in the same module. Compile catalog-only files only in that variant. Normal product builds have one unchanged production entry point, no catalog menus, no synthetic inference selection and no catalog fixtures bundled. Gate flag combinations in `Package.swift` and check both configurations compile.

Use `Sources/SevraApp/Catalog/` for the browser, registry, fixtures and driver. Keep `SevraCore` UI-free; no reverse dependencies from shared UI modules into `SevraApp`. Move only genuinely shared fixture support into a small package target if tests need it; never import an executable test target or make product code depend on test fixtures.

Build with a separate script and package destination, reusing worker packaging rules from `package_app_worker.py` and the isolated test hosts. Do not overwrite `output/native`, install into Applications or register the catalog as a workbook document handler. Include the actual extraction/image/layout resources and signed app worker. The catalog must check its own bundle identity and refuse an unsafe unbundled launch before mounting stories. Native linking may still require existing engine build artifacts even though no weights are downloaded or model loaded at runtime. A model-free runtime is not a promise of a compiler-free or dependency-free build.

### Minimal production seams

`WorkspaceState` currently calls `ProductAI.shared` and `NativeAutomationHost.shared` directly; other views do so too. Add a small explicit service context with production defaults, rather than scattered catalog conditionals throughout business behavior.

| Boundary | Required treatment |
| --- | --- |
| Workbook and navigation | Create real isolated `Workbook` objects through public APIs, open with the real workspace lifecycle, wait for snapshot readiness before replay |
| Inference | Inject a `ProductAI` instance using its existing package `init(qualifying:)` and deterministic `WorkbookInference`; default remains `.shared`. Unscripted requests report unsupported scenario rather than invoking the real model |
| Automation | Inject controller/registry and busy/yield callbacks into workspace and automation views. Catalog registry lives under its session root; no production singleton start, background timers or system schedule activation |
| Preferences/grants | Catalog has its own app preference domain; inject per-story `UserDefaults` for app sessions and workspace preferences. Route SwiftUI `@AppStorage` through that same story store, including reading size. Avoid global process-wide swaps |
| File/external operations | Use a narrow host-actions adapter for open/save selection, external URL/open/reveal, template export and import choices. Synthetic inputs come from the fixture root; exports go to an owned scratch directory |
| Settings and voice | Reuse `SpeechInput`'s existing package `driverFactory`/`DictationDriver` seam and inject the speech instance into workspace. Extract model-settings presentation state/actions only where needed. No microphone, real downloads or inference from a catalog button |
| Async/read failures | Reuse existing load/exchange closures and cancellation gates; add only the missing small seam at the service/controller boundary. Do not weaken core validation to force a state |
| Timers/time | Use fixed fixture business dates and explicit progress gates. Inject display time only where needed for a reproducible elapsed/relative label; deadlines/timeouts keep real monotonic behavior |

Audit all call sites, not only `WorkspaceState`: `SevraApp.swift`, `SpeechAndSettings.swift`, `ExcelConversionView.swift`, `AutomationSchedulesView.swift`, `AutomationScheduleEditor.swift`, `ChatActions.swift`, file/export actions in shared renderers, and app-session construction. `WorkbookView` polling must be owned and stoppable. A separate bundle ID alone does not fence model directories, selected files or these singletons.

Keep ordinary keyboard/selection behavior real. Automated copy/paste stories use a named pasteboard where injectable and never read the user's clipboard as fixture data; explicit manual copy in the catalog can use the normal clipboard. Keep OS interactions that cannot be safely isolated as labeled manual stories.

### Fixture lifecycle

A `CatalogSession` owns a UUID scratch root, workbook(s), defaults suite(s), scripted inference, native sessions, task handles, isolated automation registry and capture output. It owns cleanup, not a view's incidental `onDisappear` alone.

Lifecycle: prepare fixtures → mount → wait for declared readiness → interact/capture → cancel and await work → stop workers/close sessions/flush or deliberately preserve drafts → unmount → remove owned fixtures. Every async result is bound to the current story/session generation. Switching stories or Reset must not let old callbacks update the new preview.

Use current-format synthetic fixtures produced by core APIs. Assets can be checked-in small synthetic files; seed database content at runtime with stable logical aliases mapped to generated IDs. Do not change global ID generation or production transaction timestamps solely for snapshots. Capture metadata retains actual IDs; normalize only irrelevant display metadata in the capture mode where explicitly declared.

Reset rebuilds the fixture from its recipe, including grants and drafts. Reopen stories intentionally preserve the same fixture within a session. Conflict stories open a second connection/view to that fixture. Ordinary stories do not share global mutable seed workbooks.

Create compact reusable data sets: empty workbook; supplier comparison; inventory with images and missing quantities; project/tasks/relationships; synthetic documents/media/archive; workflow/automation evidence; chat questions/approvals/captures. Reuse `Demo` ideas and existing integration fixtures without importing their test runners. Split fixture payloads from assertions only when actual reuse warrants it.

Use gated loaders with explicit Continue/Fail/Cancel controls for loading and race states. The deterministic driver should issue supported operations and wait for real conditions; no fixed sleep as the definition of “ready.” Transient visual states may use controlled presentation inputs, clearly marked; interaction proofs must use the actual state machine.

## 10. Representative compositions

Every composition is a navigable set of component/state stories and an executable fixture recipe, not a large screenshot.

| Composition | What it proves |
| --- | --- |
| First workbook | Welcome → synthetic file input → Home → conversation → cited result; empty/loading/ready transitions |
| Supplier comparison | Question and typed fields → exact table/chart → expanded sources → live Home pin → changed data versus historical answer |
| Inventory workspace | Mini-app inputs/table/metrics/images → validated transaction → chat equivalent → Undo/Redo → reopen |
| Project planning | Board plus calendar/timeline and dependency diagram, selection and record navigation, missing date, narrow layouts |
| Business overview | Mixed chart/metric/table panels using one snapshot, source inspection, long labels and enlarged reading size |
| Evidence review | PDF/text/image + conversation citation + references + pending change review, unavailable original |
| Excel conversion | Original/clarification/build/compare/enable/app/just-tables paths, failure and resumable state using scripted inference |
| Interrupted work | Pending questions with independent drafts, navigation/reopen, stale submission refusal, retry without duplicate change |
| Workflow attention | Scheduled or manual synthetic run → waiting review/needs attention → Home attention → inspect and continue using controlled scheduler |
| Surface semantics | Captured chat, current Home and granted app view together; edit, preset selection, changed app version and grant revoke |

Add a composition index showing which primitives/states each uses. Include meaningful mixed arrangements (form + result, chart + table, image + evidence, master/detail, tabs + scrolling, comparison wrap). Do not generate thousands of random screens to inflate coverage.

## 11. Reproducibility, capture and agent use

A small catalog command surface should support listing stories as JSON, selecting a story/configuration at launch, and capturing a selected story after readiness. Exact option names can follow the existing CLI conventions; they are new catalog commands, not claims about commands available today. Use stable IDs rather than UI coordinates. Avoid adding a network server or general automation protocol.

A capture receipt contains source commit and dirty status, catalog build/binary identity, OS/SDK, story ID and fixture revision, selected props/state, actual point dimensions/backing scale, appearance, reading size, locale/time zone where relevant, service mode and readiness result. PNGs and receipts go under ignored catalog output; do not flood Git with every run.

Reuse the AppKit hosting/capture technique in `TableSnapshots.swift`, but factor only the small reusable part. `NSView` capture may omit separate windows/popovers, Quick Look or media layers: mark unsupported/partial captures and use explicit separate-window/manual review. An empty bitmap or a captured loading placeholder is not a passing story. No whole-desktop screenshot dependency for ordinary catalog captures.

An agent can read the manifest, locate a story, reproduce a state and inspect actual action/receipt events. Export concise SDK/visual recipe examples for supported mini-app authoring. Keep catalog-only drivers and synthetic stories out of the shipped agent's tool scope and runtime prompt; link developer documentation to the catalog. Do not paste a giant component catalog into every model request or imply new model reliability from deterministic stories.

## 12. Verification sized to this work

Follow [[records/specs/distribution]]'s focused verification policy. Catalog coverage is a design/engineering inventory, not a requirement to duplicate all existing core tests.

During implementation:

1. Check registry integrity: unique IDs, source/capability references, legal fixture definitions, closed-set coverage and explicit unsupported combinations.
2. Build the catalog and ordinary product after startup/dependency changes. Confirm normal packaging excludes fixtures/alternate entry point and catalog packaging includes genuine workers/resources.
3. Run one vertical interaction per surface: main table edit/Undo; Home arrange or pin; mini-app action through XPC; chat typed answer/approval. Add the nearby counterexample: stale version, revoked grant, invalid input or duplicate submission.
4. Verify isolation/reset: no product recents/preferences/grants changed; no model/setup/scheduler/hardware service invoked; switch/reset while async work is pending; reopen keeps only intended drafts; old results cannot cross sessions.
5. Review representative narrow/wide and light/dark actual renderings, including long labels and the real app reading-size control. Native tables, AppKit mini-app controls and shared SwiftUI visuals all need representation.
6. Replay the cross-surface capture/live flow and inspect real workbook values/receipts independently of the picture.
7. Reuse existing checks for unchanged core/SDK semantics. At the final integration milestone run required repository checks and the focused catalog checks once, with failures resolved. A code change after a failure needs the relevant rerun, not automatic repetition of every expensive cohort.

Do not introduce a new snapshot-testing dependency, broad per-pixel CI gate, giant model trial matrix or a screenshot baseline for every Cartesian combination. A small capture set supports human visual review; interaction checks prove meaningful behavior. OS accessibility, screen reader behavior, real inference, performance under model load and other hardware are separately qualified. No VoiceOver or system setting changes are part of this implementation proposal.

## 13. Ordered implementation and acceptance

All phases below are planned, not begun. Reconcile the source inventory against the actual implementation-start commit first.

### Phase 1: Registry, isolation and four-surface slice

Add the catalog build/entry point, native browser, registry, disposable session lifecycle and necessary host seams. Mount one real example for main app, Home, mini app and chat. Include one genuine XPC action and one scripted inference continuation through the real loop. Add Reset and explicit readiness. Acceptance: these four stories operate independently, tear down cleanly, and cannot access product preferences or invoke live external services.

### Phase 2: Components and visual families

Register all 22 mini-app nodes, 22 ordinary-space/section kinds, 6 shared visual families with surface restrictions, 12 chart styles, 4 work styles, and 5 chat field kinds. Add props controls, meaningful variants and shared native styling components. Acceptance: coverage output has no unexplained missing supported primitive; all entries mount the production renderer or explicitly identify a current product limitation.

### Phase 3: Main app, Home and chat state machines

Complete the route/modal/menu inventory and required stories in sections 4, 5 and 8. Add settings/voice/scheduler presentation seams where needed, without touching real services. Verify history, drafts, approvals, failed/retry and lifecycle states. Acceptance: every listed surface is explorable, including errors and recovery, with truthful service-mode labels.

### Phase 4: Compositions and semantic parity

Implement the ten composition recipes, bounded composition controls and the cross-surface comparison. Exercise native/control and chat operation equivalence on isolated copies. Acceptance: real receipts/data agree; historical answers remain fixed; Home/current views update; denied access stays denied. Recipes copy/reopen deterministically.

### Phase 5: Capture, coverage and completion review

Add reproducible configuration/manifest output, selected-story capture/receipts and a focused catalog check runner. Publish developer instructions in the repo's knowledge store and link from README. Review completeness against this plan, actual source enums/sets/routes and the current visual/chat plan. Acceptance: a new developer can build, launch, find a component, change state, replay a flow and capture it using one documented route, without model weights or user data at runtime.

Proposed file ownership:

| File area | Planned change |
| --- | --- |
| `Package.swift`, `Sources/SevraApp/SevraApp.swift` | Catalog compile condition/entry separation; preserve ordinary startup |
| New `Sources/SevraApp/Catalog/` | Browser, registry, story definitions, lifecycle, driver, capture; organized by surface |
| New small host-services file in `Sources/SevraApp/` | Production defaults plus catalog-injected boundaries |
| `WorkspaceState.swift` and listed direct-service views | Route model/automation/preferences/host operations through narrow dependencies |
| `WorkbookView.swift`, `ConversationViews.swift`, private view files as needed | Extract reusable internal production subviews only where catalog mounting requires it |
| `Sources/SevraAppUI/`, `SevraVisualUI/`, `SevraPreviewUI/`, `SevraTableUI/` | Minimal injection points for otherwise hardwired operations/preferences; no duplicate rendering |
| `sdk/index.d.ts` and example type checks | Align existing `action`, `ActionForm` and `viewID` declarations with the shipped runtime/protocol |
| `Sources/SevraCore/Spaces.swift` and canonical enums if needed | Reuse/expose capability sets without behavior changes or UI dependency |
| New `examples/catalog/` | Small synthetic assets and mini-app composition sources; no real customer workbooks |
| New `scripts/build_ui_catalog.sh`, packaging/check helpers | Distinct native bundle, isolated scratch/output, focused runner |
| `IntegrationTests/Preview/TableSnapshots.swift` | Reuse the capture approach; factor helper only when warranted |
| `db/records/operations/` and README | Build/use guide, coverage and qualification limits |

## 14. Review passes and final decisions

### Pass 1: Scope and source consistency

Checked the target graph, app startup, routes and views, Home projection/embedding, native protocol/SDK, visual definitions/renderers, chat input/message paths and existing native/preview harnesses. Corrected the premise that existing preview groups were a Storybook. Included file viewers, import/Excel, reviews, workflows, automations, settings, voice, menus and secondary surfaces instead of limiting the plan to new charts.

### Pass 2: Architectural and adversarial review

A standalone target importing `SevraApp` would not provide clean access to its internal executable-owned views. Chose a distinct compile-time app variant to avoid wholesale UI extraction. A distinct bundle alone was also insufficient: traced direct model/automation calls and file/export/voice operations, added explicit host seams, per-story preferences and lifecycle fencing. Kept XPC/decoder/layout workers real; prevented “successful” fake transcript changes from counting as interaction proof.

### Pass 3: UX and coverage honesty

Separated components, states and flows; distinguished inspectable examples from verified evidence. Added ordinary space versus programmable app differences, Home's mandatory attention fallback, captured versus live semantics, image alias restrictions, current app work-view editing limits, independent versus shared fixture comparison, genuine reading-size controls and unsupported capture cases. Replaced infinite-arrangement promises with finite capability registration and curated composition coverage.

### Pass 4: Export/entry-point completeness

Compared the SDK runtime exports with the public declarations and found the missing `action`, `ActionForm` and `viewID` declarations. Added their existing behavior and the small declaration-alignment task. Rechecked app commands and the shared chrome inventory, added genuine reading-scale bounds, and reused the existing dictation-driver seam rather than proposing a second voice state machine. Added bundle-identity refusal to prevent an unbundled catalog process accidentally using the product's preference domain.

### Implementation checklist

- [ ] All four surfaces mount actual production views.
- [ ] Every canonical primitive/type and user-facing route/secondary surface has an explicit coverage entry.
- [ ] Inputs, state variants and actions are explorable with bounded native controls.
- [ ] Supported compositions use production schemas, validation and runtime.
- [ ] Chat controls and semantic actions reach real mutations/receipts in synthetic workbooks.
- [ ] Captured/current and ownership/permission distinctions remain visible and correct.
- [ ] Missing/unsupported product states are reported, not concealed by gallery-only UI.
- [ ] Reset, teardown, drafts, competing edits and late callbacks have focused evidence.
- [ ] Real user files, model loading, device schedules and OS permissions are outside default story execution.
- [ ] Catalog packaging is separate and ordinary production packaging remains unaffected.
- [ ] Captures/configurations are reproducible and labeled with their evidence limits.
- [ ] Documentation and focused final checks pass; remaining qualification gaps are explicitly listed.

The design is ready to implement in this order once implementation is requested. Packaging/injection work is a first-phase acceptance gate, not something claimed to have been prototyped during planning. Exact story count is derived from the registry as coverage is implemented; it must not replace the explicit coverage checklist above.
