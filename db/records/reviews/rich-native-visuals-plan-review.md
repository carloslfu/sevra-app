---
type: review
meta-type: conclusion
id: 01m7fygzq5wbggh4frbd6a5e3d
created: 2026-11-15T15:51:58.437559+00:00
updated: 2026-11-15T15:51:58.437559+00:00
summary: Three review-and-revision passes covering UX, data and authority contracts, dependency choices and delivery acceptance for rich native views.
title: Rich native visuals plan review
---
# Rich native visuals plan: three review passes

Reviewed November 15, 2026. The final plan is [[records/plans/rich-native-visuals]], with evidence in [[records/research/rich-native-visuals]] and the owner request in [[sources/notes/2026/11/rich-native-visuals-plan]]. Four successive plan bodies were produced: initial draft, then one revised body after each pass. This is an author self-review, not an independent external review or implementation qualification.

## Anti-pattern verdict and overall impression

The final plan passes the specification-level check for generic dashboard patterns: it prioritizes a real business question, exception handling and drill-down; avoids mandatory walls of metric cards, decorative charts and nested panels; retains native type, color and interaction conventions. No new rendered interface was inspected in this planning task, so rendered visual quality is not graded as passed.

The strongest existing foundations are the native shell, exact query/transaction machinery and shared chat actions. The largest opportunity is to make good visual choices dependable for the agent. More raw drawing freedom alone would produce more layout and interpretation failures.

## Pass 1: UX and product scope, draft 1 to revision 2

| Finding | Why it mattered | Revision made |
| --- | --- | --- |
| Shared components were underspecified as a user experience. | Reusing code does not explain whether filters are linked or why Home changes. | Added linked logical state versus local hover/zoom; separate presets over the same data; Home compact exports and preserved period/coverage. |
| Saving visual changes through the app package would trigger exact-version reauthorization. | A title/filter adjustment could become another source-generation and enable cycle. | Chose host-owned versioned presentation records, restricted to the reviewed descriptor; package/data/action changes still require their ordinary reviewed version. |
| The initial example deferred too much of the public API. | Implementation could split into inconsistent Home and SDK contracts. | Added a concrete proposed bar-chart descriptor and named View reference, explicitly separating shipped query syntax from proposed visual fields. |
| Responsive composition was too late in the sequence. | The first chart release could work technically and still fail in a narrow chat split. | Moved minimum layout tokens and adaptation into P1; P2 expands composition. |
| A rich view could appear to own its business data. | Removing a Home widget or copying a preset could create destructive or duplicated state. | Made reference-only Home bindings and metadata-only presets explicit; distinct presentation/business Undo labels. |

Priority for future UI review: `/arrange` for hierarchy and density, `/adapt` for compact composition. These are design-review tools, not substitutes for native behavior checks.

## Pass 2: architecture and data integrity, revision 2 to revision 3

| Finding | Why it mattered | Revision made |
| --- | --- | --- |
| “Use the query engine” was not enough for imported Excel. | Headers, text numbers, subtotal rows and ambiguous dates could produce incorrect totals. | Declared row-domain -> typed projection -> relational query -> aggregation ordering; preserve originals; reuse native numeric/date logic; explicit exclusions. |
| A valid join can still multiply measures. | Invoice totals may be repeated for every joined line. | Added cardinality/pre-aggregation requirements and independent fan-out fixtures. |
| Selection targets lacked field/parameter mapping. | Linked charts could filter the wrong field, confuse null with clear, or trigger update loops. | Added typed parameter slots, explicit target mappings, distinct null-group selection and event-origin suppression. |
| Independent refreshes can contradict each other. | A KPI and chart can show different business revisions as one overview. | Added coherent snapshot publication and a total query-set budget; no database lock held while waiting for UI/inference. |
| Cached data could outlive its authority. | Removing an app grant might leave visible data or serve a cached result to a different scope. | Added physical workbook, access epoch and caller scope to cache/controller identities and late-result checks. |
| Asset IDs in writable tables could become a grant-expansion path. | An app could write an unrelated item ID and try to read it as an image. | Initial asset access is an explicit reviewed set; a data cell never creates authority. Added bounded helper decoding and aggregate image-cache limits. |
| Diagram layout quality was assumed from library availability. | Browser/Node support says nothing about QuickJS limits or stable native geometry. | Kept ELK as a qualified-spike candidate, Graphviz as a measured fallback; native label metrics, stable IDs, geometry validation and cancellation are required. General diagrams remain incomplete if the gate fails. |
| Model verification had no clear completion criterion. | A few attractive successful examples could hide unsupported families or stopped runs. | Added a frozen ten-request/ten-edit final cohort, explicit pass requirements, repair reporting and a smaller P1-only cohort. No production success-rate inference. |

Priority for implementation review: data/authority regressions first, then `/harden` for failure states and `/audit` for native accessibility and performance. Use the existing focused-verification policy.

## Pass 3: delivery and adversarial consistency, revision 3 to revision 4

| Finding | Why it mattered | Revision made |
| --- | --- | --- |
| Moving every table implementation into VisualUI could create a target cycle or rewrite unrelated editing code. | The mini-app table currently lives in AppUI, while ordinary tables use a separate target. | Specified acyclic target dependencies, narrow host closures and shared lower-level presentation rules while preserving existing edit adapters. |
| Refresh identity could include every chat receipt. | Inspection itself might trigger repeated recomputation. | Explicitly use canonical dataset-read snapshot identity and existing data-versus-presentation distinctions. |
| Saved presentation metadata could pollute business records and Home recents. | A layout edit must not look like a new invoice, observation or document. | Added typed metadata classification, actor/request lineage and exclusion from business datasets/recent-document projections. |
| Loaded-record targets were ambiguous about mounted controls. | Hundreds of cards could exceed native-tree budgets or hurt input responsiveness. | Required native virtualization, an initial mounted-card bound and cross-view budgets; cold startup is measured separately. |
| Delivery seams and refusal checks were scattered. | An implementer could add a renderer but omit grammar, agent, check-worker or package coverage. | Added a file-level map and a positive/counterexample acceptance matrix; every advertised family must be covered before its stage is accepted. |

Final consistency checks: chart choices match the macOS 14 baseline; no browser renderer or hosted dependency is required; proposed APIs are marked proposed; persistent presentation changes and package grants are distinct; plain inspection does not start code; nonvisual chat operations remain possible; incomplete data is never silently complete; dates, units and record/group identity are explicit; Home live pinning differs from frozen snapshots; no stage is marked implemented.

## Remaining decisions and limits

1. P0 must qualify native hosting and the data/schema vertical slice on actual supported hardware. The performance numbers are proposed targets, not measurements.
2. The diagram dependency must pass its explicit compatibility/resource/packaging gate. No dependency was installed or benchmarked during this planning task.
3. Actual rich-component visual and assistive-technology behavior remains future acceptance work. Existing restrictions on VoiceOver/system-setting changes are preserved; passing headless checks cannot close that qualification.

These do not block completing the planning request. They are concrete implementation gates, with a first chart release that can ship independently of the diagram gate. No new product features, installed app changes or application test-suite passes are claimed by this review.
