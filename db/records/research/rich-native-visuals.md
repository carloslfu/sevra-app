---
type: research
meta-type: conclusion
id: 01m7fxyzj47qvj40kmq79dcbk1
created: 2026-11-15T15:42:08.452505+00:00
updated: 2026-11-15T16:07:42.798937+00:00
summary: Code audit and primary-source research for shared native charts, richer layouts, boards, timelines, diagrams and media.
title: Rich native visuals research
---
# Rich native visuals: code and technology research

Inspected November 15, 2026 against clean source commit `89c8ed70d8f5b18824cccf13932b035d0d424857`. This is source research and technology documentation review, not a new app launch, rendering benchmark or dependency qualification. The owner asked for a plan and repeated review: [[sources/notes/2026/11/rich-native-visuals-plan]]. The proposed implementation is [[records/plans/rich-native-visuals]].

## Code findings

| Evidence | Observed fact | Implication for the plan |
| --- | --- | --- |
| [Package.swift](../../../Package.swift) | macOS 14 baseline; Core, AppProtocol, AppRuntime and AppUI targets; the sandboxed script runtime uses bundled QuickJS. | Native chart selection is available at the supported OS floor. A web/Node diagram library is not automatically compatible with this runtime. |
| [Spaces.swift](../../../Sources/SevraCore/Spaces.swift), [ContentViews.swift](../../../Sources/SevraApp/ContentViews.swift) | Home chart schema permits bar/line; single x/y fields; Swift Charts implementation is in the app executable. X labels are currently strings. Space composition is limited to 16 components and three levels. | Extract a common native rendering layer and typed encodings; preserve bounded composition rather than blindly expanding limits. |
| [ComponentData.swift](../../../Sources/SevraCore/ComponentData.swift), [AccessiblePresentation.swift](../../../Sources/SevraPreviewUI/AccessiblePresentation.swift) | Data projection reads 1,000 rows; metrics refuse partial totals; charts convert finite Y values to Double and disclose plotted coverage. pinSpace captures frozen values and refuses live app components. | Keep exact values and completeness. Distinguish Add to Home live references from frozen visual snapshots. |
| [DatasetQuery.swift](../../../Sources/SevraCore/DatasetQuery.swift), [DatasetQueryExecution.swift](../../../Sources/SevraCore/DatasetQueryExecution.swift), [DatasetQueryFunctions.swift](../../../Sources/SevraCore/DatasetQueryFunctions.swift) | Typed joins, filters, grouping, Decimal sum/average, snapshot tokens, row/byte/instruction/deadline bounds; grouped outputs lack per-row input identities; no typed date-bucket/bin transform. | Reuse this evaluator. Add typed projections and group lineage; do not sum the visible page or write a second JavaScript aggregation engine. |
| [XLSX.swift](../../../Sources/SevraCore/XLSX.swift), [Tables.swift](../../../Sources/SevraCore/Tables.swift) | Imported worksheet columns are created with the default text type, preserving cell strings, headers and original positions. | Chart inference needs a declared body domain and exact number/date interpretation; a decimal SUM over text columns is not already supported. |
| [NativeAppProtocol.swift](../../../Sources/SevraAppProtocol/NativeAppProtocol.swift), [SDK types](../../../sdk/index.d.ts) | 23 permitted node types; no Chart/Board/Timeline/Diagram nodes. Image exposes only symbol. | Add real component and wire contracts, not aliases pretending that drawing primitives are semantic views. |
| [NativeAppCanvas.swift](../../../Sources/SevraAppUI/NativeAppCanvas.swift), [NativeAppRenderer.swift](../../../Sources/SevraAppUI/NativeAppRenderer.swift) | Canvas draws rect/circle/line/text with a finite semantic palette and named regions. Layout uses native stacks/grids and bounded sizes. | Good native foundation; no general diagram layout, responsive composition or first-class rich visualization system yet. |
| [NativeAppSession.swift](../../../Sources/SevraAppUI/NativeAppSession.swift), [HomeViews.swift](../../../Sources/SevraApp/HomeViews.swift) | Independent view observers, shared table presentation and input revisions; Home binds a whole app. Conversation snapshot lists text, inputs and table state. | Generalize shared state and semantic inspection; add declared subview exports rather than scrape a transient UI node. |
| [NativeAppPackage.swift](../../../Sources/SevraCore/NativeAppPackage.swift), [NativeAppData.swift](../../../Sources/SevraCore/NativeAppData.swift) | Exact-version/digest/physical-workbook access; declared datasets only; query broker maps aliases; no asset grants. Draft presentation state has a bounded metadata store. | Asset access is a new capability. Do not confuse existing drafts with immutable saved-view history or let Home bypass app grants. |
| [NativeAppAuthoring.swift](../../../Sources/SevraCore/NativeAppAuthoring.swift), [GrammarChecks.swift](../../../IntegrationTests/Agent/GrammarChecks.swift) | Authoring prefers native Workspace tables/forms; prompt gates remain 8,448 ordinary and 10,240 authoring tokens. | Make visual recipes discoverable on demand, preserve reliability fallback and keep the current token limits. |
| [NativeAppCheck.swift](../../../Sources/SevraAppProtocol/NativeAppCheck.swift), [NativeAppTools.swift](../../../Sources/SevraAI/NativeAppTools.swift) | Checks cover controls, actions, persisted values and canvas regions. | Extend the same signed check path with typed visual assertions and independent business-data oracles; do not equate screenshot resemblance with correctness. |

## Primary external sources and decisions

All links below were consulted November 15, 2026. Statements about Sevra integration are recommendations or open gates, not claims made by these sources.

1. [Apple Swift Charts](https://developer.apple.com/documentation/charts) supplies native marks, axes, scales and legends. [chartXSelection](https://developer.apple.com/documentation/swiftui/view/chartxselection(value:)) and [SectorMark](https://developer.apple.com/documentation/charts/sectormark) are available on macOS 14. Recommend this framework for Sevra's chart renderer; no OS-floor increase is required for those features. Newer framework additions still need individual availability checks.
2. [Apple NSHostingView](https://developer.apple.com/documentation/swiftui/nshostingview) embeds SwiftUI in AppKit. This supports the proposed adapter architecture. It does not establish correct sizing, focus, invalidation or performance inside Sevra; those are explicit spike tests.
3. [Apple chart guidance](https://developer.apple.com/design/human-interface-guidelines/charts) emphasizes context, readable hierarchy, accessible data and optional interaction. [Apple's interactivity session](https://developer.apple.com/videos/play/wwdc2023/10037/) demonstrates selection and scrolling. Apply those principles with native exact-values inspection and stable selection. A supplied SDK API is not proof of every pointer/trackpad/keyboard combination.
4. [AXChartDescriptor](https://developer.apple.com/documentation/accessibility/axchartdescriptor) represents a chart's semantic axes and series. [SwiftUI Canvas](https://developer.apple.com/documentation/swiftui/canvas) explicitly does not supply per-element accessibility or interaction. Therefore diagram rendering must implement semantic elements and alternate navigation; drawing a graph is not accessibility acceptance.
5. [Vega-Lite](https://vega.github.io/vega-lite/) demonstrates concise mark/encoding specifications and composed views; its [selection grammar](https://vega.github.io/vega-lite/docs/selection.html) distinguishes point and interval selection and discusses multi-view resolution. Borrow the design idea of typed visual intent and explicit selection scope. Do not import its whole specification or add a web renderer merely to claim a large chart catalog.
6. [ELK.js](https://github.com/kieler/elkjs) provides automatic graph layout, including directed layered layouts, and a bundled JavaScript form with optional workers. Its [license](https://github.com/kieler/elkjs/blob/master/LICENSE.md) identifies EPL-2.0. Prefer it as the first measured diagram-layout candidate, with pinned source/artifact identity and reviewed distribution notices. Its browser/Node documentation does not establish QuickJS compatibility or fit within Sevra's existing budgets.
7. [Graphviz dot](https://graphviz.org/docs/layouts/dot/) is an alternative directed-graph layout engine with crossing/edge-length heuristics. It merits a bounded embedded-library comparison if ELK cannot fit; do not turn a system-installed command into a product dependency. No Graphviz integration or packaging spike was performed during planning.
8. [Image I/O thumbnail creation](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)) supports native reduced-size image decoding. Use it behind workbook verification and explicit image bounds. This API does not grant access to files or certify untrusted media handling.

## Rejected shortcuts

- Add more Canvas examples and call the system visually rich: leaves labels, coordinates, semantics, accessibility and interaction consistency to every generated app.
- Use Swift Charts only on Home: preserves the current product split and duplicates fixes.
- Replace the native shell with a web dashboard stack: contradicts the accepted direction and introduces another input/accessibility/render/export path.
- Implement arbitrary diagram layout in generated source: unpredictable geometry and latency; no dependable native reading order.
- Copy complete datasets into JavaScript for display: undermines native paging, exact aggregates and existing execution bounds.
- Count formatting controls as quality: usefulness depends on a readable answer to a real business question, independently correct data and appropriate interactions.

## Unresolved by research

ELK/Graphviz runtime choice, native-host performance, minimum supported hardware and actual VoiceOver behavior need implementation evidence. The plan supplies decision gates and proposed targets. No public production claim or model-reliability rate follows from this research. Existing [[records/specs/programmable-native-engine]], [[records/specs/chat-primary-operation]], [[records/plans/home-working-overview]] and [[records/specs/distribution]] remain the implemented contracts until their proposed extensions are accepted.

## Inline-chat extension

The owner later extended this same plan to native controls and visual results in chat. [[records/research/inline-chat-interactions]] audits the message renderer, existing forms/approvals, durable input lifecycle and relevant primary design sources. The updated owning plan now covers Home, mini apps and chat; this initial code audit retains its exact baseline and findings.
