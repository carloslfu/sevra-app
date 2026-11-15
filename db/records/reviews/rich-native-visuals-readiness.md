---
type: review
meta-type: conclusion
id: 01m7g94edwdaw8wtc6v8ncmf2y
created: 2026-11-15T18:57:21.852134+00:00
updated: 2026-11-15T22:07:21.697101+00:00
summary: Historical revision 9-12 readiness review; the revision 13 supplement corrects capture access and completes agent integration contracts.
title: Rich native visuals implementation readiness
---
# Rich native visuals: complete implementation-readiness review

Owner request: [[sources/notes/2026/11/rich-visual-plan-readiness]]. Reviewed November 15, 2026. The owning [[records/plans/rich-native-visuals]] is now revision 12. Earlier [[records/reviews/rich-native-visuals-plan-review]] remains the history of the initial visual and chat-extension passes. This review read every section of the integrated revision 8 plan and produced revisions 9, 10, 11 and 12 after four further passes. It is an author self-review, not an independent audit, implementation acceptance or rendered-UI certification.

## Verdict

Ready to begin staged implementation with P0-chat and P0a. The plan now specifies the first concrete contracts and journeys, preserves the existing authority/data behavior, and isolates diagram/performance qualification to the stage that requires it. No unresolved product/architecture decision blocks the first increment. Later dependency and measurement gates remain real work; this verdict does not mean the full proposed catalog has been built or proven feasible at its target workloads.

Specification-level anti-pattern verdict: pass. The intended experience prioritizes the business question, exceptions and drill-down; chat controls appear where they reduce effort and collapse into outcomes. It avoids generic dashboard walls, mandatory follow-up chips and full app toolbars embedded in every message. Native spacing, density, focus and appearance still require actual interface review during implementation.

The strongest foundations remain exact native operations, host-owned access, recoverable drafts/history and shared semantic action discovery. The principal remaining execution risk is scope: implementation must finish the input/control increment and then one chart workflow, rather than build all component families at once.

## Code recheck and limits

Rechecked relevant code at `886edc861f702de85eeac89220677654a00794db`, after the initial plan baseline. The subsequent `f90529ab98dc21db38fb9e325c391019c1a75736` only updates the pinned agent grammar fixtures for Redo; that change was inspected for consistency. No app launch, installation, UI interaction, dependency benchmark or application suite was performed for this documentation review.

- [NativeAppSession.swift](../../../Sources/SevraAppUI/NativeAppSession.swift), [NativeAppData.swift](../../../Sources/SevraCore/NativeAppData.swift), [ChatOperations.swift](../../../Sources/SevraCore/ChatOperations.swift): explicit canUndo/canRedo and one latest reversible transaction. Old receipt buttons cannot safely invoke an unspecified latest reversal.
- [AppOperationContext.swift](../../../Sources/SevraAI/AppOperationContext.swift), [ActionConfirmations.swift](../../../Sources/SevraAI/ActionConfirmations.swift): named-action inputs differ from visual drafts; failed actions can have saved effects; envelope repair is distinct from business refusal.
- [DatasetQueryExecution.swift](../../../Sources/SevraCore/DatasetQueryExecution.swift), [DatasetQueryFunctions.swift](../../../Sources/SevraCore/DatasetQueryFunctions.swift), [ReadSnapshots.swift](../../../Sources/SevraCore/ReadSnapshots.swift): current snapshot-bound cursors, bounded Decimal evaluation and dataset-read clocks. These do not already provide historical group reconstruction.
- [NativeAppPackage.swift](../../../Sources/SevraCore/NativeAppPackage.swift), [Package.swift](../../../Package.swift): package/source/access bounds and existing target dependencies. Shared rendering must remain below adapters and cannot manufacture grants.
- [Types.swift](../../../Sources/SevraCore/Types.swift), [Workbook.swift](../../../Sources/SevraCore/Workbook.swift), [Search.swift](../../../Sources/SevraCore/Search.swift), [ChangeCapture.swift](../../../Sources/SevraCore/ChangeCapture.swift): host-owned technical kinds, recents/search exclusions and captured-read invalidation. New presentation metadata must be registered in these existing seams.
- The prior chat audit of message projections, approval claims, native fields, drafts, run admission and history remains applicable: [[records/research/inline-chat-interactions]]. Primary platform/catalog research is retained in that record and [[records/research/rich-native-visuals]]; no new dependency support claim is inferred here.

## Pass 1: architecture and data, revision 8 to 9

| Priority | Finding and consequence | Resolution in the plan |
| --- | --- | --- |
| P1 | The core architecture still said two adapters after adding inline chat. A separate chat renderer could diverge or create an import cycle. | Three adapters, explicit PreviewUI -> VisualUI dependency and Core-only shared formatting rules. |
| P1 | Saved presentation ownership only referenced an app view. A standalone chat chart could not become Home content without inventing an app or losing authority. | App-view/workbook-component owner variants; chat descriptor ownership; atomic promotion preserving the appropriate binding/grant scope. |
| P1 | State-owner keys included query and dataset revision. Refreshing data or changing a filter could allocate a new state object and lose selection. | Stable logical owner keys separated from result/cache/request-generation keys. |
| P1 | Historical visuals referred to current query snapshots without a concrete capture contract. | Exact displayed values plus bounded immutable contributing-version manifests; current cursors are not historical lineage; capture refusal is explicit. |
| P1 | Each child could consume a full query budget and still be described as one coherent overview. | Shared snapshot, deadline and DatasetQueryControl accounting for the reconciled query set; measure P0 capacity and refuse unsupported scope. |
| P2 | Decimal plotting, source meaning/status and missing time buckets were underspecified. | Finite/range/precision safeguards, declared source scopes and explicit cadence/absence semantics. |
| P2 | Revoked app data and durable answer evidence had inconsistent display policy. | Preserve immutable history while hiding protected app-derived surface values without current authority; no ordinary-query fallback. |

## Pass 2: interaction and lifecycle, revision 9 to 10

| Priority | Finding and consequence | Resolution in the plan |
| --- | --- | --- |
| P1 | Every submitted answer was said to start inference, contradicting direct known-action dispatch. | Only reasoning continuations admit a new run; fully specified known operations dispatch directly. |
| P1 | Historical Undo buttons could reverse the current transaction instead of their own. | Exact expected transaction token/direction; explicit Undo versus Redo; stale receipt refusal and separate presentation Undo. |
| P1 | The plan implied any failed app action left data unchanged. | Atomic drag adapters require a single verified host transaction; general action receipts report partial saved effects and forbid blind retry. |
| P1 | Shared visual form state could overwrite current chat values or manufacture missing input. | New invocation drafts, explicit Continue this draft, revision-aware sharing and the current named-action/visual-input distinction. |
| P2 | Clicking an answer in a grouped question set could prematurely submit other unanswered fields. | One-question buttons submit directly; grouped/multi-select/editable inputs submit the completed draft explicitly. |
| P2 | Decline, cancellation, Stop and failed-attempt retry lacked distinct outcomes. | Explicit branch/run behavior, bounded pending groups, immutable response identity and separate verified execution attempts. |
| P2 | Relative dates and compact-result limits could silently change meaning. | Captured temporal context, displayed resolved dates, currency disambiguation and no truncated chart masquerading as complete. |

## Pass 3: scope and delivery, revision 10 to 11

| Priority | Finding and consequence | Resolution in the plan |
| --- | --- | --- |
| P1 | P0 still bundled early input work with a later diagram decision. | Ordered P0-chat -> P0a, then P0-visual -> P1; diagram spike only gates P4. |
| P1 | P1 depended on responsive layout, text detail and expansion described as P2 work. | Minimum usable composition, capture and inline/expanded continuity belong to P1; P2 expands them. |
| P2 | The concrete chart example attached USD without demonstrating currency/source scope or deterministic ordering. | Example now declares accepted actual scope, USD filtering and stable sorting; stable customer keys are explicit. |
| P2 | Bar/area/histogram/heatmap semantics and stage membership were ambiguous. | P1 grouped bars/lines; P2 stacking/area/scatter/histogram/heatmap with declared bin, missing-value, unit and normalization behavior. |
| P2 | Board counts, timeline clipping and partial graphs could overstate completeness. | Scoped lane counts, ID-based moves, explicit clipped intervals and incomplete graph boundaries. |
| P2 | Export verification did not define cancellation/overwrite publication. | Frozen result, existing destination checks, staged output and atomic no-overwrite publication with invocation-scoped cleanup. |

## Pass 4: adversarial consistency and acceptance, revision 11 to 12

| Priority | Finding and consequence | Resolution in the plan |
| --- | --- | --- |
| P1 | Generic item writes/search/invalidation could treat saved-view metadata as business facts. | Register technical/host-owned kinds; domain-owned writes and projection/invalidation counterexamples, with exact owning files. |
| P2 | Metrics still said to define zero/negative baseline behavior without choosing one. | Positive-baseline percentage default; unavailable percent for zero/negative/missing baseline, explicit comparable-period and neutral direction rules. |
| P2 | Per-component resource bounds did not bound caches or work queues. | Process-wide proposed 32 MiB visual/geometry and 64 MiB image caches; bounded thumbnail queue and reported total memory; measurements remain gates. |
| P2 | Creation cohorts were not explicit enough about text/control pairing, waiting runs and P1 coverage. | Six paired chat scenarios; four P1 scenarios and edits; predetermined human answers allowed, no tool coaching; correct needs_input is not counted as failure. |
| P2 | Completion could be declared without testing newly discovered ownership/state/reversal risks. | Expanded acceptance matrix with positive and refusal cases for promotion, stable state, exact reversals and captured provenance. |
| P2 | “Ready” could be mistaken for performance/dependency qualification. | A gate table names required evidence and exactly which stage it blocks. Earlier stages may ship independently; unsupported later families remain incomplete. |

## Whole-plan coverage

| Plan portion | Review coverage and implementation condition |
| --- | --- |
| Decision/status and gap table | Scope, baseline, three surfaces, current versus proposed capabilities and first deliverable reconciled. |
| Anchor business journeys | Sales/collections, stock/purchasing and jobs/dependencies retain source correctness, named actions and optional direct manipulation. |
| Composition, tokens, states and motion | Native hierarchy/density, compact behavior, empty/partial/stale/error states, focus, keyboard, reduced-motion and no forced layout rearrangement. |
| Entire component catalog | Required versus optional families, P1/P2 chart split, tables, metrics, detail, boards, all calendar forms, diagrams, media, text and bounded custom scenes checked against stages. |
| Shared types and adapters | Strict bounded schemas, source/package limits, three adapters, no target cycle or duplicate calculation engine. |
| Query correctness and provenance | Typed projections, Excel record domains, units, dates, scope, joins, grouping, paging, null/zero, exact arithmetic, coherent snapshots, capture and portable evidence. |
| State and persistence | Owner identity, independent/linked presets, stable selections, transient mechanics, expected-version writes, history, removal, replay, Undo/Redo and metadata exclusion. |
| Authority, assets and export | Exact grants, schema/package changes, revocation, cache identity, scoped media, helper gates, destination boundaries and artifact verification. |
| File implementation map | Core, query, capture/schema, native UI, SDK, agent/grammar, chat/drafts, package and regression seams assigned. |
| Agent authoring | Question-driven recipes, capability discovery, compact context, named operations, truthful outcomes and preserved inference budgets. |
| Chat repertoire and journeys | Choices, grouped questions, missing fields, record selection, review, result/receipt, suggestions and activity, each with explicit expansion/text alternative. |
| Chat publication/dispatch | Typed host identities, immutable revisions, result evidence, trusted native event entry, request_input/finish paths and direct known operations. |
| Chat lifecycle/recovery | Durable publication, released lease, causal answers, restrictions, draft conflicts, late/stale responses, exact claims, retry/cancel/Stop and copies. |
| Historical and live chat views | Captured numbers versus current view, explicit Home promotion, local selection default, readable fallback, cache/row invalidation and no focus stealing. |
| Technology choices | Native Charts/hosting remains justified; external UI protocols are inspiration; diagram runtime/license/resource choice remains a measured P4 gate. |
| Delivery sequence | Concrete starting checkpoints, no future-component dependencies for P0a/P1, bounded accepted increments and explicit queued work. |
| Verification/performance | Independent value oracles, matching nearby refusals, text/control cohorts, native visual evidence, process/worker budgets and truthful accessibility/release limits. |
| Gates/checklist | No feature marked implemented; each remaining uncertainty has required evidence and a named blocking stage. |

## Final planning verification

Completed: `dbmd validate --all db --json` returned zero errors and warnings; `python3 scripts/check_links.py` passed; both proposed JSON examples parsed; section/stage/review-pass and selected contradiction checks passed; `git diff --check` passed. These are document checks only. They do not execute the proposed schema or prove runtime behavior. No product compilation, benchmark, app launch or model cohort is claimed. Unrelated concurrent Excel records are excluded from this documentation commit and their generated catalog entries are preserved separately.

## Later whole-plan audit, revision 13

The subsequent owner-requested [[records/reviews/rich-native-visuals-final-audit]] supersedes this review's current-readiness pointer and its pass-1 recommendation to hide saved app-derived answers after revocation. Verified immutable captures remain readable through the host; new app reads/actions still require current authority. It also closes concrete prompt/scope/grammar, capture-production, compaction, atomic-publication and window-state gaps. The findings above remain the record of revisions 9 through 12, not the current implementation contract.
