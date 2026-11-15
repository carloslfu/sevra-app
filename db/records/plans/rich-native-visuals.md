---
type: spec
meta-type: conclusion
id: 01m7fxyzjyxhk7wqfy9044qq7y
created: 2026-11-15T15:42:08.478533+00:00
updated: 2026-11-15T15:51:58.792707+00:00
summary: Proposed shared native visual system for Home and mini apps, with data correctness, chat operations, UX and staged acceptance.
title: Rich native views for Home and mini apps
status: reviewed
---
# Rich native views for Home and mini apps

## Decision and status

Revision 4, after three review-and-revision passes: UX, architecture/data integrity, and delivery/adversarial consistency. Planning only. Research and review do not establish implementation or visual acceptance. Owner request: [[sources/notes/2026/11/rich-native-visuals-plan]]. Code baseline inspected: `89c8ed70d8f5b18824cccf13932b035d0d424857`. Technical evidence and external references: [[records/research/rich-native-visuals]]. Review findings and revisions: [[records/reviews/rich-native-visuals-plan-review]].

Build one native visual component system that ordinary workbook spaces, Home and programmable mini apps can all use. The agent chooses the representation, binds real workbook data and invokes semantic operations. The host owns layout, rendering, interaction feedback, arithmetic and access. A chart in a mini app must be as capable and inspectable as the same chart on Home. Reusing components does not mean every view shares filters or every chart reads the same dataset.

Keep the product centered on completed business work: the conversation changes the work; the visual surface explains its state and supports fast inspection. Direct manipulation remains a useful optional shortcut. A user should never have to drag a card, click a chart or select a hidden tab to make a business operation possible through chat.

The first deliverable is a complete, attractive chart-and-exceptions workflow in both a mini app and Home. The full program also includes boards, timelines/calendar views, relationship/process diagrams, images, richer tables and flexible composition. Finish each usable increment before advancing. Do not treat this document as authorization to replace the active installed app, toggle VoiceOver or change system settings; those existing operating boundaries remain.

## 1. What exists and what is missing

| Area | Inspected implementation | Gap to close |
| --- | --- | --- |
| Home and ordinary spaces | `Component` supports chart, metric, table, comparison, text and live whole-app bindings. `NativeComponent` renders bar/line charts with exact-values disclosure. | Single-series/categorical-X chart model, fixed 220-point plot, limited composition; no reusable mini-app chart or exported subview binding. |
| Mini-app UI | Native AppKit renderer; 23 allowed node types; rows, columns, grids, tabs, forms, tables, progress and SF Symbols. | No chart/board/timeline/diagram/media components; weak responsive contracts and semantic styling. |
| Canvas | Four shape types, named hit regions, drag/keyboard events; 2,048 shapes and 128 regions. | No graph semantics, layout, routed edges, zoom model, chart scales, rich text or dependable element reading order. Drawing coordinates is not a visualization system. |
| Data | Home component data reads at most 1,000 rows; metrics refuse incomplete inputs. The typed query engine already supports joins, grouping, exact Decimal aggregates, snapshot-bound pagination and bounded execution. | Charts bypass much of that query machinery. Dates, numeric bins, group drill-down and visualization coverage need a common contract. Query page limits must not become aggregate population limits. |
| Excel | Worksheet imports preserve original cell strings, formulas, headers and coordinates; imported columns default to text. | Explicit typed projections and record domains are necessary before aggregating numbers, dates or statuses. Header/total rows cannot silently become data. |
| Runtime and chat | One approved app session can feed multiple renderers; named business actions, input revisions and table browsing are shared with chat. | Chart selections, filters, board moves, timeline ranges, visual summaries and named exported views need equivalent semantic discovery and operations. |
| Authoring | SDK discovery, constrained schemas, signed execution checks and separate model review exist. Guidance favors Workspace tables and ActionForms. | The agent needs useful visual recipes, on-demand schemas and independent visual/data assertions. Adding exports alone will not change generated output. |
| Assets | Workbook-owned assets and verified/cancellable preview resolution exist. Mini-app Image means SF Symbol. | A narrowly scoped asset-display capability, thumbnails, captions and unavailable states; no arbitrary path or URL property. |
| Validation | Current checks verify controls, saved rows, actions and canvas regions; existing UI reviews are bounded. | No chart-data, axis/series, visual-state, graph-edge, overlap or rich-component inspection contract. |

Relevant code map is in the research record. Preserve existing good foundations: native controls, exact data, versioned spaces, shared actions, recoverable Home and explicit app grants. Do not rewrite the app in a browser or add another business-data store.

## 2. The intended experience

### Three anchor journeys

1. **Sales and collections.** Drop an invoice workbook into chat; ask, “Show monthly invoicing and overdue balances.” The app opens on a dated trend and a short overdue table, with currency, reporting period and exclusions visible. Selecting a month narrows the detail table. “Show only Acme, then pin this overview to Home” produces the same result without pointer use. Marking an invoice paid invokes the existing validated business action, updates both surfaces and can be undone. Neither chart counts the worksheet header or subtotal as an invoice.
2. **Stock and purchasing.** “Show what needs reordering.” The app prioritizes shortage exceptions, then a stock-versus-reorder-level chart and an optional product-image detail. “Receive 12 bolts” changes the underlying inventory action once. Home displays the compact shortage view, not a second inventory database or a copy of the entire input form.
3. **Jobs and dependencies.** “Show my jobs by stage and what is due next week.” A board and timeline show the same jobs. “Move job J-12 to Doing and move its due date to Friday” uses named actions with normal validation. A dependency view explains why a job is blocked; it does not infer a dependency just because two tasks are nearby. Invalid moves keep the original state visible and explain the refusal.

Each journey must remain useful with the model unloaded after the app is created. Native selection, scrolling, tooltips, filtering and already defined actions cannot require an inference turn.

### Composition and visual language

Use the project's native macOS direction: system typography, semantic light/dark colors, precise alignment and a restrained 4-point spacing scale. Richness comes from useful encodings, clear hierarchy, imagery when relevant and well-composed views. Avoid identical card grids, giant metric walls, ornamental sparklines, oversized form panels and nested boxes.

Provide a small composition grammar: `Stack`, `Inline` with wrapping, `AdaptiveGrid`, `Split`, `Section`, `Tabs` and `Disclosure`. These are proposed capabilities, not renamed shipped APIs. Preserve recognizable existing Row/Column APIs where suitable; share underlying layout policy. Each child can declare semantic role, minimum readable width, bounded preferred height and priority. Grid tracks are chosen from the available container width, not a global screen breakpoint. Content remains in a predictable reading order. A detail inspector becomes an inline disclosure at narrow widths. Minimum adaptive behavior, semantic reading order and typography tokens ship in P1; P2 expands composition rather than repairing an unusable first release. Canvas viewports can pan; ordinary screens must not require horizontal scrolling to reach primary content.

Use semantic typography roles (`title`, `section`, `body`, `caption`, `metric`), spacing/density tokens and finite status/series palettes. Keep low-level bounded size/spacing controls for genuinely custom compositions. Colors distinguish status and series, with labels, symbols or line patterns carrying the same meaning. Assign series colors from stable series identities; filtering or sorting must not recolor the remaining categories. Do not promise arbitrary CSS, gradients, downloaded fonts or per-app themes.

Home remains a calm overview: attention first, a small number of explicitly selected views and a clear way to resume. Compact views preserve units, period, coverage and the key question; they reduce secondary detail rather than shrink text. Open app restores the relevant view and context. No automatic rearrangement of a person's authored Home.

### Controls, states and motion

Keep charts/data prominent and operations secondary: “Show overdue,” “Group by customer,” “Explain this change,” and “Open records” are more useful than a toolbar of unlabeled icons. A compact view menu offers Inspect data, Change view in chat, Add to Home, Expand and, when implemented, Export. Use the existing composer handoff and preserve unsent text.

Every component defines loading, empty, filtered-empty, partial, invalid-data, stale, unavailable-source, permission-disabled and failed states. Zero is a result; missing is unknown; not yet loaded is neither. Keep the last valid display during refresh with visible freshness when relevant; a failed refresh cannot silently relabel old data as current. Retry is scoped and cancellable. Motion preserves object identity and explains a change; respect reduced motion. Hover cannot be the only path to information. Selection/focus survives ordinary data refresh when the entity still exists.

## 3. Component catalog and delivery priority

| Component family | Required useful capability | Priority and limits |
| --- | --- | --- |
| Chart | Bar (vertical/horizontal, grouped/stacked), line, area and scatter; multiple series, categorical/numeric/temporal axes, legends, direct inspection, reference lines, units and exact-values drill-down. | P1 delivers bar/line, multi-series, true dates, thresholds and point/range filtering. P2 adds area/scatter, histogram and heatmap. No 3D or dual-axis default. |
| Metric and comparison | Exact value, unit, reporting period, optional target/baseline, absolute and percent change; meaningful short trend. | P1. Define zero denominator and direction semantics; red/green must not guess whether an increase is good. |
| DataTable | Existing native paging/editing plus typed number/date formatting, status badges, conditional emphasis, in-cell data bars and totals with declared scope. | P1 core formatting/exception rules; P2 bars and grouped summaries. Derived/aggregate rows are inspectable and noneditable. Never sacrifice copying, keyboard editing, original values, row identity or formula protection. |
| RecordList and Detail | Dense labeled summaries, optional thumbnails, source links and readable selected-record inspector. | P1 text detail; P4 assets. Useful alternative to forcing every dataset into a table. |
| Board | Group records by explicit status; counts, ordering, progressive loading, selected-card details; optional move through a registered action. | P3. No implicit writes or invented stages; moving is available in chat and via keyboard. |
| Timeline and Calendar | Date ranges, due dates, overlaps, milestones and grouped lanes; week/month navigation and agenda fallback. | P3 delivers timeline and agenda first, then qualifies the calendar grid before P3 is marked complete. This is not a critical-path scheduler or resource optimizer. |
| Diagram | Directed process/dependency and hierarchy views; real node/edge IDs, labels, stable layout, collapse, fit, pan/zoom, selection and related-record detail. | P4, gated by layout spike. No force-directed motion by default or general drawing-editor promise. |
| AssetImage and Attachment | Workbook image thumbnails/full inspection, alt description, caption, aspect fit; attachment tile opens existing verified preview. | P4, exact asset capability. SF Symbols remain a distinct Icon API. |
| Text and annotations | Paragraphs, lists, emphasized text, callouts and structured record/source links; compact labels on visuals. | P2. Use a bounded rich-text AST and existing Markdown parsing where appropriate; no HTML execution. |
| Custom scene | Shapes, paths, stroke/fill, transforms, clipping, explicit semantic regions and fixed coordinate spaces for specialized 2D views. | P5 optional extension after semantic components. No per-frame JS rendering. Existing Canvas remains usable. |

Part-to-whole charts are optional P2: a small positive-category donut can be useful, but bars remain the comparison default. Histograms require explicit numeric bins; heatmaps require meaningful matrix axes. Image galleries, pivot-table authoring, maps, Sankey, treemap, arbitrary SVG execution, 3D, video/audio editors and a Figma-like canvas are outside this program. Keep extension points without claiming those features.

## 4. Shared contract and implementation architecture

### One declarative specification, two adapters

Add validated Codable/Sendable `VisualDefinition`, `VisualDataRequest`, `VisualResult`, `VisualSelection` and `VisualPresentation` types in SevraCore. These names are proposed. A discriminated component specification describes purpose, bindings, encodings, format, layout and interactions. Nested fields have bounded typed schemas and unknown keys fail closed; an unrestricted JSON props bag would hide mistakes instead of creating flexibility. It is data, never arbitrary Swift, JavaScript, SQL or HTML. Keep source/business logic out of styling fields. Immutable package descriptors and versioned presentation overrides are different layers of this same contract; neither is a second business-rule implementation.

Ordinary `Component` owns a visual specification within the existing versioned SpaceDefinition. NativeAppPackage declares a bounded map of named `views`; a new SDK visual node references one of those names. Both resolve to the same host evaluator and native renderer. New code should not duplicate chart parsing or business totals inside the JS runtime. Generate matching protocol validation, TypeScript declarations, discovery documentation and grammar fixtures from one catalog where practical; runtime validation remains authoritative.

A proposed minimal native-app chart definition is below. It deliberately uses already typed decimal data; Excel text projection is the separate required contract below. Dataset/column names are illustrative and must be discovered, not guessed. The query body uses the existing alias-based app query shape; the outer visual fields are proposed. Ordinary spaces resolve the same logical bindings through their own workbook-owned binding map.

```json
{
  "id": "salesByCustomer",
  "kind": "chart",
  "data": {
    "query": {
      "sources": [{"table": "invoices"}],
      "select": [
        {"id": "customer", "column": {"source": 0, "column": "customer"}},
        {"id": "net", "column": {"source": 0, "column": "net"}, "aggregate": "sum"}
      ],
      "groupBy": [{"source": 0, "column": "customer"}],
      "limit": 1000
    },
    "coverage": "completeGroups"
  },
  "mark": "bar",
  "encoding": {
    "x": {"field": "customer", "type": "category"},
    "y": {"field": "net", "type": "decimal", "unit": "USD"}
  },
  "presentation": {"title": "Net invoicing by customer", "density": "comfortable"},
  "interactions": {"selection": {"kind": "group", "targets": [{"view": "invoiceDetails", "parameter": "customer", "valueField": "customer"}]}}
}
```

The proposed `Sevra.View` SDK node takes a declared view ID and optional presentation-record ID. Both resolve through the host catalog; no arbitrary callback/string in the descriptor becomes executable code. Family-specific factories may produce these typed definitions, but must not create a second wire format. All target IDs must resolve within the same authorized view set. Here invoiceDetails must declare a typed customer parameter. A view with adjustable filters declares bounded `parameters` (type, default, allowed values/range) and fixed slots in its query. The host validates values before substituting literals; parameters cannot supply column names, source identities, raw predicates or SQL. Selection-target mappings name the target parameter and source field explicitly. Clearing a selection is distinct from selecting a group whose value is null. Undeclared parameters, incompatible target types and cyclic filter propagation are refused. Changes carry an origin/event token and publish once, so two linked views cannot create an update loop. `completeGroups` refuses a `hasMore` result; it does not enlarge the query limit or hide omitted customers. The Home binding adds `viewID` and optional `presentationID` to the existing app reference. P0 freezes discriminators, required/allowed keys, stable identity, schema fixtures and clear invalid-field diagnostics before feature implementation.

Create a `SevraVisualUI` target depending on Core and native Apple frameworks. Dependency direction is Core types/evaluation -> VisualUI -> the ordinary-space and mini-app adapters. VisualUI receives narrow host-owned data/action closures; it cannot manufacture a NativeAppAccess grant or import SevraAppUI. AppKit mounting and session authority stay in SevraAppUI. Both SevraApp and SevraAppUI consume it, avoiding a reverse dependency on the main executable. SwiftUI chart views are hosted with NSHostingView inside the existing AppKit renderer. Preserve mounted identity instead of replacing the hosting view on each patch. Native tables retain NSTableView recycling; shared column presentation lives below both existing table frontends, using Core formatting/rule types and the lower-level table UI target where appropriate. Do not make VisualUI import the mini-app AppTable class or rewrite both transactional editors merely to share formatting. The chart renderer is shared directly; existing table adapters share tested presentation rules while retaining their data/edit adapters. Use AppKit/Core Graphics for dense diagrams with explicit hit-testing/accessibility elements. A SwiftUI Canvas alone does not supply per-element interaction or accessibility.

### Data correctness before drawing

Reuse the typed DatasetQuery compiler, exact Decimal aggregate functions, cancellation and snapshot identity. Preserve its existing bounds: up to three sources, 1,000 output rows per page, 100,000 contributing rows/32 MiB referenced inputs, four million VM instructions and a maximum three-second query deadline. Native-app responses retain their smaller 1 MiB boundary. Return a bounded visual result directly to the native host, not thousands of rows serialized through app JavaScript.

The evaluation order is declared record domain/header exclusions, typed projection, relational filtering/joins, grouping/aggregation, output sorting, then bounded presentation. Never parse a known header into a number before applying its declared exclusion. Reuse existing number/date and Excel date-system implementations where they meet this contract; do not introduce a second formula engine. Add only explicit typed projection operations needed by visuals: parse decimal with declared locale/format, parse date with declared format/date system, time bucket with calendar/time zone, and numeric bin with a specified rule. They run within the same query budget and read transaction. Imported Excel views specify body rows/range and exclusion of known headers/totals using inspected evidence; never globally infer that row 1 is a header or that any row called Total should disappear. Typed projections do not rewrite original cells or formula outputs. Ambiguous dates/numbers require a choice. Parsing failures produce counted, inspectable exclusions or refuse a requested total; never silently become zero.

VisualResult carries query/spec identity, workbook read revision, columns/types/units, rows or aggregates, coverage, excluded/null counts and the parameters that produced it. Cache identity includes authorization scope/epoch and physical workbook, not just query text. Never serve a previously authorized result to a narrower or revoked caller. Distinguish complete population aggregation from a limited list of output groups or plotted marks. `hasMore` must trigger explicit grouping/filtering/paging, not a chart of the first page masquerading as the whole. Never compute a total from a paginated table. P2 may add an explicit ranked-subset display mode: its title and coverage state the rank/limit, and an Other group is legal only when calculated over the complete remainder. A query page cannot invent Other or a denominator. Use Decimal values for all business arithmetic; conversion to finite Double occurs only at plotting coordinates. Exact inspection retains the original normalized decimal.

Joins require an explicit expected cardinality or a pre-aggregation that preserves the intended measure. Fixtures must catch duplicated invoice amounts after joining invoice lines. The engine must report/refuse unexpected fan-out for an asserted many-to-one relationship; syntactically valid SQL is not proof of a meaningful total. Empty datasets yield COUNT 0 and unavailable non-count statistics unless a mathematically defined identity is explicitly part of the measure. Percentage formats declare whether source values are fractions or percentage points. Never attach USD to mixed-currency rows simply because a title asks for dollars.

Time is typed as date-only or instant. A date-only due date must not shift with device time zone. An instant view records its display time zone and calendar; month/week bucketing and period comparisons use that declared policy. Preserve gaps in line charts for unknown/missing observations; no smoothing, interpolation or connecting gaps that invents business observations. Expose units and prohibit stacking incompatible currencies/units. Bar axes start at zero unless an explicit justified configuration is visibly communicated. Mixed actual/estimate/forecast data use explicit scope and distinct encodings.

Aggregate marks refer to group identities, not invented record IDs, and never offer direct cell editing. Source-row edits resolve exact current record IDs through the named action. Group drill-down stores the typed query, group key and read snapshot, then resolves contributing rows through a bounded host query. Current grouped results have no per-row inputs; implement this lineage path rather than invent it from display labels. If the source changed, refresh and label the new result or report the stale snapshot; do not silently open current rows as the historical inputs. Frozen visual export captures values, parameters, coverage and required immutable input identities. Reuse current snapshot/history mechanisms; do not add a parallel ledger.

### State, sharing and persistence

Separate package-owned capabilities, durable presentation, logical view state and per-surface mechanics. Source, declared views, data bindings and business actions belong to the exact reviewed package. Changing those creates a new package version and follows existing review/enable behavior. Ordinary Home placement uses existing versioned space edits.

Presentation-only edits must not recompile or reauthorize the app. Add host-owned `visual_presentation` records using the existing item/version/change-capture machinery, not an independent business-data table or the mutable draft store. These records hold a bounded title/format/layout/filter/annotation override and reference a declared `(appSpaceID, viewID, viewContractHash)`. They cannot introduce a dataset, field, join, action, asset or executable expression outside the reviewed descriptor. Every update has an expected record version, mutation receipt and history/recovery; the metadata never contains copied business rows. These typed presentation records are excluded from business datasets and recent-document projections, carry the configuration request/actor provenance, and never masquerade as customer events or calculated business results. The visual evaluator validates overrides again at read time and applies the app's current grant to every data read. A changed source/view contract that invalidates an override reports an incompatible preset, rather than silently remapping columns. Exact schema/public API changes follow the pre-1.0 policy; selected synthetic fixtures can be recreated, with real workbooks preserved.

Title, compatible mark/axis choices, saved parameter values, density and explicitly saved diagram positions use this presentation route. New fields/grouping not exposed by the descriptor require a reviewed descriptor update. Temporary exploration can change declared query parameters without saving. Data edits still go through existing transactional named actions and Undo. Layout/presentation Undo and business-data Undo must be distinctly named and show the operation they will reverse; adding a Home view must not unexpectedly replace the app's last business-change receipt.

An app's named view has one session-owned logical presentation state for active filters and selected records, usable by chat and every linked rendering. Hover, focus, scrolling and zoom stay local to the particular surface. A separate saved preset creates a distinct presentation-record ID over the same declared view and data, not a new package or new business records. Linked instances of the same preset share logical filter/selection state; independent presets do not. Do not couple unrelated charts merely because they use one dataset. A linked Home view visibly retains its preset/period; “Save a separate view” makes independence explicit. Merely resizing or opening a second window never persists a filter or changes another viewport.

Generalize NativeAppSession's existing table-presentation map and observer registry for visual state. Keys include physical workbook identity, app/version, grant epoch, named view, presentation-record ID/version, query identity and canonical dataset-read snapshot. Reuse the existing distinction between data changes and chat/presentation receipts; appending an inspection receipt must not create an endless refresh loop. Dispose subscriptions when a view leaves; bound subscriptions and coalesce refreshes. Late work from a previous app version, query, filter or authorization epoch cannot update the current display. Reuse the shared input-revision protections. The final accepted data update must refresh all active linked views. Related totals/charts/detail blocks in one overview need a coherent read snapshot: evaluate their bounded query set in one short read transaction or publish only a common accepted revision, never hold a database transaction while waiting for UI or inference. Keep a total budget for the set. Pending parts are explicitly updating; they cannot be presented as one reconciled result while reading different revisions.

Named exports in the app package let Home show a compact subview. This is a reference to a declared view, not a path into a transient mounted tree or a screenshot. Full-app embedding stays available. Disabled, removed, incompatible or failed exports show a recoverable placeholder; no implicit grant or silent replacement. Pin-to-Home stays distinct from the current pinSpace frozen-snapshot operation in both tool names and user copy.

### Authority and inspection

All app data and visual queries resolve through NativeAppAccess, exact saved package digest, current physical workbook and declared dataset bindings. The package's view descriptors participate in that digest. Home cannot widen a mini app's read or write authority. Ordinary workbook-owned visuals use ordinary workbook authority, never a forged mini-app grant. Cached data and images must not survive revocation as active visible content.

AssetImage declares bounded exact workbook asset/item bindings in the package; extend access review and the broker accordingly. A writable cell containing an item ID cannot widen asset access. Start with explicit asset IDs under the package byte/count limits; adding a new asset binding follows normal package review. A future host-managed asset collection needs its own membership authority, not an implicit grant to every image in the workbook. JavaScript receives an asset handle/metadata, never a filesystem path or unrestricted bytes. The native host verifies the selected immutable asset and dispatches PNG/JPEG/HEIC thumbnail decoding to a resource-bounded helper, reusing verified preview infrastructure where it meets the contract. Proposed initial bounds are 32 MiB encoded input, 16 megapixels decoded input and a 2,048-pixel longest thumbnail side; P4 must measure these and test refusal at the boundary. Neither full-resolution pixels nor paths travel through app JavaScript. Late thumbnails respect request identity, cancellation and revocation; cap the aggregate decoded-image cache, not just each image. Explicit external links retain existing verification and unavailable-source handling. No remote fetching from a visual specification. Start with attachments opening the existing document preview before attempting rich inline document editing.

Exports use a host operation with an explicit destination and overwrite refusal, consistent with current chat exports. No generated app writes files directly. Export includes a title, period, units, filters and freshness/coverage; disclose a visual snapshot versus live workbook. Render PNG/PDF from the native host and export exact tabular data where applicable. A returned path is not success until the artifact exists and is verified.

### File-level implementation map

Proposed new filenames below are planning names. Keep dependencies acyclic and avoid replacing unrelated code.

| Seam | Proposed change |
| --- | --- |
| `Sources/SevraCore/VisualDefinition.swift`, `VisualData.swift`, `VisualPresentation.swift` (new) | Shared discriminated schemas, typed results/selection, exact formatting rules, bounded override validation and presentation-record history. |
| `DatasetQuery.swift`, `DatasetQueryCompiler.swift`, `DatasetQueryFunctions.swift`, `DatasetQueryExecution.swift`, `DefinitionQueries.swift` | Whitelisted projections/time buckets/bins, cardinality checks, group lineage and coherent-query-set support. Extend saved-definition validation alongside ad hoc query validation. |
| `Spaces.swift`, `SpaceEditing.swift`, `ComponentData.swift` | Canonical visual payloads, view/preset references, versioned placement/recovery and honest snapshot coverage. No legacy-format adapter layer before 1.0. |
| `NativeAppPackage.swift`, `NativeAppData.swift` | Declared view manifests, digest coverage, bound visual-query access; later asset declarations and verified image broker. |
| `Sources/SevraVisualUI/` (new), `Package.swift` | Shared chart/metric/detail/layout views, native hosting adapters, native diagram surface and semantic accessibility. |
| `NativeAppProtocol.swift`, `NativeAppRenderer.swift`, `NativeAppSession.swift` | Typed visual nodes, stable mounts, session-owned view controllers, headless semantic operations and lifecycle/cancellation/observer handling. |
| `NativeAppTable.swift`, `Sources/SevraTableUI/`, `Sources/SevraPreviewUI/AccessiblePresentation.swift` | Shared exact formatting/conditional rules, retained paging/editing semantics, chart descriptors and values/source inspection. |
| `ContentViews.swift`, `HomeViews.swift`, `SpaceLayoutEditor.swift`, `WorkspaceState.swift` | Shared visual renderer, declared compact exports, optional native configuration/inspector controls and existing composer handoff. |
| `sdk/src/runtime.ts`, `sdk/index.d.ts`, `sdk/build.mjs`, bundled SDK resource | Named visual references, typed authoring helpers, subscriptions and event routing; generated/runtime artifacts updated together. |
| `NativeAppAuthoring.swift`, `NativeAppTools.swift`, `NativeTools.swift`, `ChatOperations.swift` | On-demand capability/schema discovery, purpose-driven recipes, semantic browse/selection/configuration/export and honest receipts. |
| `NativeAppCheck.swift`, `IntegrationTests/NativeApps/`, `IntegrationTests/Agent/`, `Tests/`, `sdk/test/` | Shared visual assertions plus independent business-value/coverage/refusal fixtures, protocol/catalog parity, prompt grammar and native interactions. |
| `scripts/build_native.sh`, `scripts/check_native_package.py`, `scripts/check_install.py` | Resource pin/signature verification for any layout/thumbnail helper, packaging/install/uninstall and missing-resource refusal. |

## 5. Chat and agent authoring

Extend existing semantic app/space operations rather than add one tool per chart type. Support inspect-view, inspect-values, browse/filter, select record/group/range, clear selection, change time range, expand/collapse, focus/fit, pin/unpin view, edit visual configuration, save a preset and export. Business moves or edits call a registered named action with typed record IDs and values. Board drops and timeline drag/resizes dispatch that same operation only on completion, with native preview feedback while dragging. On refusal, remove the preview and retain the committed position/date with the actionable error. Preserve duration rules, date-only semantics, stable card ordering and record identity; do not create order columns or change business stage definitions silently. No screen coordinates or synthetic clicks are required.

View inspection reports type, purpose, bindings, period, parameters, coverage, available interactions and exact current selection. Reading a chart should not require decoding thousands of canvas shapes or scraping visible labels. Bounded data drill-down is separate from the concise overview. Observational browse/filter state is not a business write; explicit persisted configuration changes remain writes and obey read-only restrictions. Inspecting a stopped app must not execute saved code. Query or render completion is not proof of a successful business mutation.

Keep discovery compact: expose a capability/version index, then fetch one component family's schema, recipes and examples on demand. Existing ordinary/authoring prompt gates of 8,448 and 10,240 tokens remain unchanged. Do not dump the entire visual catalog into every turn or increase those gates to fit it. Capability discovery distinguishes unavailable, implemented and enabled features.

Authoring should choose by the question: compare categories -> bar; change over time -> dated line; outliers/relationship -> scatter; status -> board; due dates -> timeline/agenda; dependencies -> directed diagram; exact editing -> table. Include a plain-English purpose and the important units/filter/period. Default to a useful overview plus drill-down, with action inputs progressively disclosed. The existing Workspace table/form layout remains a dependable fallback, not the required template for every app. Imported Excel charts are evidence of intended questions, not a promise to reproduce arbitrary Excel rendering.

Provide six small canonical recipes: sales overview, collections exceptions, inventory/reorder, jobs board/timeline, supplier comparison and dependency explanation. Recipes use synthetic data and real binding/action contracts; they never embed customer values as source constants. Preserve named business operations and validate their effects independently of visual output.

## 6. Technology choices and open gates

Use Swift Charts on the existing macOS 14 baseline. Apple documents marks, axes/legends, selection and scrolling; current Home already imports Charts. NSHostingView is the supported bridge to AppKit. Keep newer 3D/vectorized APIs out of baseline requirements. This is a proposed integration, not a claim that embedding is already qualified in Sevra.

Use a finite visualization grammar inspired by declarative systems such as Vega-Lite, without shipping its web renderer or cloning its entire language. Retain the native SDK and sandbox. Browser-hosted Vega/ECharts could increase chart variety quickly but would introduce a second UI/input/accessibility and export stack; that tradeoff is not justified for the accepted native direction.

For diagrams, prefer a proven layout engine over model-written coordinates or an unbounded homegrown graph-layout project. ELK.js is the first spike candidate: bundle a pinned layout-only build as a host-owned resource in an isolated worker context, then render resulting geometry natively. Its documented browser/Node support is not evidence that it fits Sevra's QuickJS restrictions. Measure compatibility, initialization, memory, time, cancellation, cyclic graphs, stable ordering, resource signing and license/notice delivery. Do not silently relax existing app execution limits to accommodate it. Graphviz dot is the fallback comparison candidate; evaluate embedded library packaging and dependency/resource costs before selecting it. No external dot installation or shell tool is a user prerequisite. For either candidate, the host supplies measured native label sizes, stable sorted IDs, explicit direction and a fixed supported algorithm/seed. Layout results are cached by graph content, text metrics, options and engine version, not by transient screen coordinates. Ordinary data refresh must not reshuffle unchanged nodes; fit/zoom and saved manual positions remain explicit. The worker receives only validated graph data and returns validated finite geometry. It cannot resolve asset paths, open URLs or widen app authority.

If neither candidate clears the gate, keep general diagrams explicitly unavailable and deliver a narrowly specified native hierarchy/process view only if it has its own acceptance. This does not count as completing the diagram milestone. Record a dependency decision with fixture results before P4 implementation.

## 7. Ordered delivery and acceptance

| Stage | Concrete work and owning seams | Exit evidence |
| --- | --- | --- |
| P0 Contract and vertical spike | Core visual types/catalog; Package.swift UI target; NSHostingView sizing/focus spike in NativeAppRenderer; query/Excel projection design; named-view persistence; diagram dependency experiment. Specify schema, stable IDs and bounds before parallel feature growth. | One synthetic chart rendered in both adapters; query identity and access refusal; native resize/focus proof; saved presentation edit without regrant plus unauthorized override refusal; measured diagram candidate decision or explicit blocker. Spike code is disposable evidence, not acceptance of the full feature. |
| P1 First complete workflow | Chart/metric/data-table exception components; typed dates/decimals, query aggregation and coverage; semantic inspection/filtering; shared view state; compact named-view Home binding; agent recipes and check operations. | Sales and collections journey from chat to app to Home, edit/update/Undo, restart/reopen, independent exact totals and partial-data counterexample. Real native wide/narrow UI review. This is the first usable release, not the whole plan. |
| P2 Rich analysis and composition | Responsive layout tokens, detail inspector, richer chart families, conditional table bars/formatting, structured annotations, native visual/data export. | Stock/supplier scenario, distinct correct visual choices, no clipped labels, exported values match the frozen query, missing-data/units/negative-value cases. |
| P3 Work organization | Board, timeline, agenda/calendar; record identity and action adapters; date semantics, overlapping events, accessible alternative interactions. | Jobs scenario completed by chat alone and optional pointer/keyboard, with stale/conflicting/invalid move refusal and Undo. Home and full view agree. |
| P4 Relationships and media | Qualified diagram engine, native graph renderer/accessibility, scoped assets/thumbnails, captions and attachment preview. | Branch/cycle/disconnected graph corpus, readable labels/edges, cancelled/revoked stale-layout refusal; image bounds/permissions/missing source; source-linked dependency journey. |
| P5 Integration and richness review | Optional bounded custom-scene additions only where a concrete recipe cannot be expressed; examples/discovery cleanup, full native quality review and release qualification. | Whole catalog coverage matrix, actual-model cohort, required suite/package checks on the candidate, documented remaining limits. No unsupported family advertised as ready. |

Every stage updates this plan with exact evidence and retains failures. No invented calendar estimates. Keep at most three active blockers; queued stages remain visibly queued. A blocker in diagram layout must not prevent shipping the accepted chart workflow.

## 8. Verification strategy and performance

Reuse existing core, SDK, signed native, agent and package harnesses. Add meaningful assertions for chart series/units/coverage, exact points/aggregates, selected source/group, visible filtered result, board lane membership, timeline intervals, diagram connectivity and asset identity. The same validated resolver drives display and inspection, but an independent oracle checks business values; comparing a renderer to its own serializer is not enough. Add synthetic negative cases for partial pages, stale query/version, invalid action, inaccessible binding, false provenance and missing assets.

Native visual review is required at wide and compact windows, with the chat pane open and closed, light/dark appearance, long labels and large text. Inspect hierarchy, tick/legend collisions, clipping, table density, empty/error/loading states, focus order, keyboard alternatives and reduced-motion behavior. Use synthetic isolated candidates and preserve the active app. Headless accessibility checks cover labels, semantic order and chart descriptors. Actual VoiceOver/system-setting testing is a separately unqualified gate under the existing restriction; do not infer permission from this plan.

Use fixed independent fixtures: invoices with headers/subtotals/blanks, two currencies, negative credits, ambiguous and date-only dates, more than 1,000 source rows, more than 1,000 groups, joins with duplicate keys, null/malformed numbers, conflicting edits, cycles/disconnected nodes and missing/revoked assets. Check current values after Undo/reopen and in portable copies; copies never inherit device grants.

Proposed initial workload targets, to calibrate in P0 rather than claim as measured: at most 1,000 plotted marks per view, six directly legible series before a filter/facet alternative, eight simultaneously active rich views, 100 graph nodes/200 edges and 500 loaded board/timeline records with paging. Existing wire, query and app budgets remain upper bounds; limit errors must offer a useful next action. Keep native hover/selection feedback under 100 ms p95, settled viewport render under 250 ms p95 at the target workloads, and filtered query refresh under one second p95 within the existing three-second hard query deadline. Report cold initialization separately from warm interactions. Measure idle and local-model-loaded conditions on named hardware; UI tests must not assume an unloaded GPU. More marks require explicit aggregation/filtering in P1. Any later downsampling requires a named, deterministic algorithm, coverage disclosure and independent exact-value inspection; it is not implicitly included in the first release. Preserve the existing 16-component/three-level space bounds and 512-node native-tree bounds unless a separately measured change is justified. Board/timeline components virtualize visible native children: 500 loaded records does not mean 500 SDK nodes or hundreds of permanently mounted cards. Begin with a proposed cap of 128 simultaneously mounted card/event presentations per surface and explicit paging. Offscreen suspension must preserve selection and show current results on resume. Performance bounds are cross-view totals as well as per-view limits.

Actual-model qualification: freeze ten fresh requests across the six recipes before running, then ten specified edits to those accepted views, with no next-tool scripting or manual generated-code repair. Proposed release gate: all ten requests and all ten edits complete correctly within the existing run/step budgets, with automatic recovery permitted and recorded. A failed request or unsupported advertised family blocks claiming this cohort passed. Report first valid artifact versus internally repaired artifact separately; this small cohort is not a statistical production success rate. Report first-attempt completions, automatic recoveries, stopped attempts, wall time and wrong-result/unauthorized-write counts. Every advertised family must appear; combined scenarios may cover several families. For P1, freeze a smaller cohort covering all P1 scope; do not wait for unimplemented P4 media/diagrams. The full ten-plus-ten cohort is the P5 gate. A failed case remains a failed case; repeat only to measure a named fix. Separately replay accepted artifacts deterministically. Publication requires zero known data-corruption/access defects and an explicit coverage statement, not a vague “all visuals work” claim.

At an integration release run `scripts/check.sh`, relevant native UI checks, SDK/protocol/agent grammar checks, strict changed-file formatting, package/install/extraction/resource checks and exact-code hosted CI. During development use the focused policy and nearby counterexamples. This planning change needs only documentation/link/store validation; it does not justify running the entire application suite.


### Required acceptance matrix

| Contract | Positive check | Nearby refusal/recovery |
| --- | --- | --- |
| Visual data | A 10,000-row fixture aggregates to independent exact totals before plotting. | More than 1,000 output groups, malformed values and join fan-out cannot become a misleading complete chart. |
| Chat parity | Select a group/date range, move a job and edit a view entirely by typed operations, with no window mounted. | Read-only requests cannot persist a presentation or business change; inspection does not start stopped code. |
| Shared view state | Home and app share the same preset's filter and latest committed result; independent presets retain their own state. | An old query/thumbnail/layout response after filtering, version change or revocation cannot replace current output. |
| Presentation history | Change title/allowed mark/preset without new code or regrant; undo and reopen reproduce it. | A presentation cannot introduce a table, asset, callback, forbidden column or unregistered action. |
| Business mutation | Pointer, keyboard and chat call the same action; related record edits commit atomically. | Stale/invalid move leaves business data untouched, retains input and avoids duplicate submission. |
| Diagram | Branch, cycle and disconnected fixtures have correct connectivity and nonoverlapping readable labels. | Timeout/cancellation retains the previous valid view and offers table/relationship inspection, not invented geometry. |
| Media/export | Verified asset identity and native export match exact captured values/filter/period. | Missing/revoked/oversize image or failed export yields an honest failure without fallback to arbitrary paths. |
| Native UX | The scenario stays readable at wide and compact sizes, with keyboard focus and explicit details. | Long labels, no data, missing values, dark appearance and reduced motion do not hide critical meaning. |

## 9. Completion checklist

- [ ] Shared typed visual contract and native adapters, with one query/access path.
- [ ] Complete P1 app/Home/chat workflow and independent evidence.
- [ ] P2 analysis/composition/export scope accepted.
- [ ] P3 board/time/calendar scope accepted.
- [ ] P4 diagram/media scope accepted, including dependency decision.
- [ ] Agent discovery, chat operations and assertion coverage for every shipped family.
- [ ] Persistent edits/history, exact values, grant revocation, Undo/reopen and portable-copy integrity.
- [ ] Native visual quality and bounded performance acceptance; accessibility limits explicit.
- [ ] Final source/package/CI identity and honest supported-feature documentation.

The desired outcome is not a larger widget list. It is a small set of dependable native representations that the agent composes into useful, readable business tools and Home views, with their correctness and interaction behavior preserved.
