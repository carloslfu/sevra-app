---
type: review
meta-type: conclusion
id: 01m7gkxjxdxqaq3phcvcrw74ey
created: 2026-11-15T22:05:51.405576+00:00
updated: 2026-11-15T22:07:21.218675+00:00
summary: Full revision 13 audit closes agent integration, publication and context gaps and corrects historical capture access.
title: Rich native visuals final whole-plan audit
---
# Rich native visuals: final whole-plan audit

Owner request: [[sources/notes/2026/11/rich-visual-plan-final-audit]]. Reviewed November 15, 2026 against clean source `5b05c5f6127d6956d63c167c7bc2b42812578047`. The owning [[records/plans/rich-native-visuals]] advances from revision 12 to 13. This is a further author self-review, not an independent audit or runtime acceptance. Earlier findings remain in [[records/reviews/rich-native-visuals-readiness]]. No application implementation, launch, installation, GPU run or dependency qualification occurred.

## Verdict

Ready to implement the first bounded increment, P0-chat then P0a, followed by P0-visual/P1. The earlier plan had real agent-integration omissions and one overrestrictive historical-display rule; this audit corrects them rather than treating the prior readiness verdict as proof. The required implementation gates now identify concrete APIs, prompt and scope changes, durable transitions and counterexamples. Readiness does not prove all proposed components or workload targets will pass. The full catalog remains unfinished until its own stage evidence exists.

## Pass 1: trace code to each agent contract

Rechecked [WorkbookAgent.swift](../../../Sources/SevraAI/WorkbookAgent.swift), [WorkbookInference.swift](../../../Sources/SevraAI/WorkbookInference.swift), [NativeTools.swift](../../../Sources/SevraAI/NativeTools.swift), [ToolSerialization.swift](../../../Sources/SevraAI/ToolSerialization.swift), [ChatTools.swift](../../../Sources/SevraAI/ChatTools.swift), [Tools.swift](../../../Sources/SevraCore/Tools.swift), [ChatOperations.swift](../../../Sources/SevraCore/ChatOperations.swift), [NativeCitationPolicy.swift](../../../Sources/SevraNativeAI/NativeCitationPolicy.swift), [ToolPolicy.swift](../../../Sources/SevraSplashGrammar/ToolPolicy.swift) and [NativeGrammar.swift](../../../Sources/SevraSplashGrammar/NativeGrammar.swift).

| Finding | Consequence and revision 13 resolution |
| --- | --- |
| Several prompts explicitly require missing-input questions through finish. Changing the new tool declaration alone would leave contradictory instructions. | Section 5.7 enumerates base, answer-only, terminal, app guidance and operation-description changes, retaining no-guessed-values and supplied-input rules. |
| Tool availability is phase-specific; reference definitions, serialized schemas, grammar and runtime guards are separate seams. | Explicit direct-user host capability plus phase eligibility for request_input; internal review/summary/Excel/workflow subcalls return missing-input information to the outer host. Table-driven parity spans every scope and capability, including injected-adapter refusals. |
| Answer scopes do not expose workspace_action, while the proposed chart path depended on generic semantic operations. | Concrete visual discovery/schema/evaluate/capture/inspect/select/configure/pin/export route through the existing envelope. Answer scopes expose only the read-only subset through narrowed declarations and independent operation guards. No broad allowlist expansion. |
| finish visual references had no explicit producer. | visual.evaluate capture mode returns an immutable, host-issued result receipt; finish validates a current-run reference against ordinary evidence rules. Inline definitions can produce a standalone chart without app generation. |
| Native-app SDK discovery activates authoring context; ordinary questions should not need it. | Visual catalog/schema discovery stays separate through the visual domain and shares catalog versions with app authoring. No whole-catalog prompt expansion. |
| New terminal outcome affects more than a run badge. | AgentResult, Core Runs, activity/history, native result handling, CLI and harness contracts are named. Noninteractive output returns a pending identity and exits; callers without a durable channel close unresolved. |

## Pass 2: lifecycle, authority and usefulness

Rechecked [ContinuationState.swift](../../../Sources/SevraCore/ContinuationState.swift), [ContextMaintenance.swift](../../../Sources/SevraAI/ContextMaintenance.swift), [ContextDigest.swift](../../../Sources/SevraAI/ContextDigest.swift), [Runs.swift](../../../Sources/SevraCore/Runs.swift), [NativeAppPackage.swift](../../../Sources/SevraCore/NativeAppPackage.swift) and [WorkspaceState.swift](../../../Sources/SevraApp/WorkspaceState.swift), alongside the existing draft, exact-approval and receipt contracts.

| Finding | Consequence and revision 13 resolution |
| --- | --- |
| Current finish persists its message and terminal status separately. Copying that sequence for interactive publication can leave an orphan form or unfinished run after a crash. | One captured commit publishes the question, pending identity and needs_input transition, checking cancellation/current run identity. Lease release follows durable commit. Explicit before/after-commit crash tests. |
| Context summaries are bounded derived notes, not exact pending-input authority; continuation projection currently excludes finish but not the new tool. | Host-owned bounded pending state survives compaction and carries original restrictions/completed-operation identities. request_input is neither a business mutation nor completed task. Old choices never renew authority. |
| Revision 12 hid already published values when an app grant disappeared. This conflated new app execution with the owner's saved answer evidence and would make old answers unreadable after normal app updates or portable copies. | Explicit correction: the host can render verified immutable captures without running code or reading current data. Live refresh/actions/promotion still require current scope; no ordinary-query fallback or old-package regrant. Missing/corrupt captures disclose the limitation. This supersedes the revocation-display recommendation in the earlier review, not its live-access protections. |
| Session-owned filter sharing did not name window scope. | Linked Home/app views share within one workspace session; separate windows explore independently. Saved presets/business changes retain ordinary version propagation. Stable owner keys now include the workspace session. |
| Two individually allowed 64 KiB descriptors would exceed the 128,000-byte message limit before receipt overhead. | Whole-payload accounting is explicit; use verified out-of-line captures or refuse, never truncate a descriptor. |
| Optional UI failure and no-model wording could overpromise. | Bounded repair and truthful text/table fallback; a requested chart remains incomplete if it failed. Existing deterministic actions work without inference; new natural-language interpretation can still require it. |

## Pass 3: cross-plan, scope and complete-document consistency

Compared [[records/plans/inference-context-upgrade]] revision 4 with this plan. The 8,448/10,240 checks in [GrammarChecks.swift](../../../IntegrationTests/Agent/GrammarChecks.swift) are fixed-fixture prompt-size caps, not runtime admission thresholds. Revision 13 preserves the regression caps while deferring runtime capacity/maintenance to the canonical context policy. Prepared-request identity must include new schemas, effective operation scopes and dynamic capture references; no widget-specific budget policy or engine upgrade dependency is introduced. Either implementation order has an explicit integration requirement. A concurrent uncommitted revision 5 of that plan appeared during verification; its shared-boundary admission and effective-scope refinements are consistent with this contract. That work and its evidence remain outside this audit's commit.

Re-read the full plan and checked these contracts, including their neighboring refusal cases:

| Sections | Coverage and decision |
| --- | --- |
| Decision, current gaps, journeys | Proposed versus implemented status; current native foundations; chat-first operation; model-free known controls; Excel body/header distinction. No new product scope. |
| Composition, controls and catalog | Native hierarchy and density; responsive reading order; source/coverage states; chart, table, metrics, board, calendar, graph, asset and annotation stage membership. No decorative dashboard requirement. |
| Shared specification and adapters | Three adapters, Core/VisualUI dependency direction, native table retention, strict catalog, package limits, named view declarations. Chart JSON is labeled an excerpt requiring companion bindings/target view, not a runnable package. |
| Data path | Domain exclusions before projection; exact Decimal values, date policy, explicit scopes/currency/cardinality; complete aggregation versus pages; coherent query-set budgets; bounded immutable input manifests. |
| Ownership, state and access | Presentation records versus reviewed package; exact owner identities; state versus result cache keys; independent windows; live revocation versus saved evidence; asset helper and export authority. |
| Chat composition and journeys | Choice versus grouped submit, form limits, plain-text parity, custom answer qualifications, date context, no duplicated missing-input questions and no redundant review. |
| Publication and continuation | Strict immutable surfaces; trusted events; direct known actions versus reasoning continuations; atomic publication, reply identity, exact claims, drafts, stale/duplicate/crash/Stop/decline and portable-copy recovery. |
| Agent integration | Concrete discovery/capture route, phase/capability table, prompt and grammar changes, operation-level policy, citation receipts, context retention, prepared identities and CLI fallback. |
| Rendering/history | Captured versus live values, host-only historical display, focused expansion, content revisions, stable scrolling/focus, keyboard semantics and unsupported-client fallback. |
| Technology and stages | Native Charts/hosting; finite catalog; diagram experiment remains a P4 gate. P0a does not depend on charts; visual-specific scope/receipt tests begin in P0-visual/P1. |
| Acceptance and limits | Independent oracles, paired text/control inputs, real-model cohorts, native review, cache/helper/query budgets, exact publication identity and honest accessibility/runtime limits. No boxes marked implemented. |

No new external-library compatibility claim was needed; the primary-source research remains in the earlier linked records. No browser or active app was controlled. The principal remaining execution risk is breadth: complete the small chat increment and chart workflow before expanding families. The diagram choice, real-model behavior, native focus/sizing and workload targets remain measured implementation gates, not gaps disguised as passed tests.

## Documentation verification

Completed: `dbmd validate --all db --json` reports zero errors and warnings; `python3 scripts/check_links.py` passes; both JSON excerpts parse; all nine main sections, seven chat subsections, stage ordering and selected contract/contradiction checks pass; `git diff --check` passes. These checks validate documentation, not the proposed runtime schema or UI. The commit is isolated from concurrent inference-plan edits; its exact staged store is validated again before commit. No application suite, benchmark or actual-model cohort is claimed.
