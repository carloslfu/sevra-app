---
type: spec
meta-type: conclusion
id: 01m789vd0k7cmce2ce4g1y2j00
created: 2026-11-12T16:35:58.611467+00:00
updated: 2026-11-12T17:14:42.301357+00:00
summary: Accessibility code closures are implemented and compiled; AI evidence completeness, Excel expansion, background execution and external qualification remain proposed and paused.
title: Ways to close the remaining preview limits
status: proposed
---
# Ways to close the remaining preview limits

## Scope and current state

Originally requested in [[sources/notes/2026/11/accessibility-review-and-pause]]. The later [[sources/notes/2026/11/accessibility-code-fixes-and-pause]] authorized implementation of the ten accessibility findings only. Those code closures, static review and compiler verification are now recorded in [[records/reviews/accessibility-static-review-2026-11-12]]. Runtime accessibility testing remains skipped and the owner will evaluate the behavior afterwards. Work returns to paused after delivery.

The remaining sections are concrete proposals, not implemented behavior, an active work queue or permission to install a helper. AI evidence coverage, the Excel subset, foreground-only automation and release qualification retain their earlier limits. No more than three slices should become active after an explicit resumption. Background execution and broad Excel fidelity should not become accidental prerequisites for a smaller selected improvement.

## 1. AI answers can omit relevant documents or requested terms

**What exists.** [RequestEvidence.swift](../../../Sources/SevraCore/RequestEvidence.swift) supplements the first original read with excerpts from at most two other originals selected by lexical request terms. It explicitly reports partial coverage and byte/time limits. `DiscoveryBudget` stops repeating searches that find no new candidates. `WorkbookAgent` requires inspected citations, current versions, checked calculations and genuine action receipts. `SearchCoverage` and `CostQualification` are narrow language guards. These mechanisms prevent several false claims but do not establish semantic completeness for an arbitrary question.

**Smallest useful closure.** Add a saved answer checklist with requested dimensions and candidate entities. For a supplier comparison, that can include unit price, quantity, shipping, tax, delivery and payment terms for each named supplier. Every cell has one of: supported with exact source/version/locator, explicitly unknown in inspected evidence, conflicting, or still uninspected/partial. Model-authored decomposition is only a proposal; present the scope and permit correction. A missing checklist dimension must not disappear merely because the model omitted it in its answer.

Use that checklist to direct bounded searches and exact chunk reads, with a ledger of query scope, pagination and extraction completeness. Reserve tool budget for final calculations and explanation. If evidence cannot be covered within the limit, show a partial answer and the remaining dimensions with an explicit continuation route. Three unchanged searches are a stopping condition, not evidence that every supplier term is known. Retain the hostile-content and authority boundaries.

Render structured comparisons from the verified checklist and deterministic calculation receipts. Label included cost components and currency explicitly; absent tax cannot become zero, and lowest known cost cannot become a definitive all-in ranking. Keep `SearchCoverage`/`CostQualification` as secondary safeguards, not the acceptance oracle. Extend `SevraAI` completion structures and `SevraCore` request-evidence receipts rather than creating a second business ledger.

**Future functional qualification, not executed now:** replay the retained broad-question failures and a small held-out set with renamed suppliers, split delivery/tax evidence, irrelevant and hostile files, conflicting versions, partial extraction and no relevant source. Score requested-dimension coverage, correct unresolved states, calculation correctness and time/tool limits separately. Include Spanish and English because the existing pricing guard is English-specific. Do not publish a general accuracy rate from these small cases.

## 2. Excel remains a declared formula subset

**What exists.** [SheetFormula.swift](../../../Sources/SevraCore/SheetFormula.swift) supports numbers, percentages, arithmetic/comparisons, cell/range references with optional sheet names, `SUM`, `AVERAGE`, `MIN`, `MAX`, `COUNT`, `ROUND` and `IF`. [SheetFormulaPlan.swift](../../../Sources/SevraCore/SheetFormulaPlan.swift) already maps sheets to datasets, resolves cross-sheet dependencies, orders calculations and propagates unsupported/circular dependencies. Unsupported or mismatched formulas retain saved values with reasons. The native report warns when changed inputs make those values potentially stale. Cross-sheet support and a dependency graph do not need inventing again.

**Smallest useful closure.** Aggregate the existing per-cell reasons into an import compatibility summary: recalculating, saved-only, missing cache, unsupported dependency, circular and budget-limited. Keep access to the original file and exact formula. Make saved-only status available at the cell and table level through the shared accessible presentation. Do not treat a saved result as recalculated merely because its numeric value still looks plausible.

Choose the next function family from a real blocked workbook, then extend the existing parser, typed evaluator and dependency engine coherently. Likely useful candidates are conditional aggregates and lookup functions, but they remain proposed until an actual need selects them. Freeze blank/text/error/coercion, precision, dates, range and cross-sheet behavior before adding syntax. Preserve the cache-agreement and dependent-staleness rules. Shared/array/structured references, macros, pivots, formatting and faithful Excel round-trip are distinct scopes; accepting one must not imply all of them.

**Future functional qualification, not executed now:** current evidence includes 3,600 LibreOffice-generated formulas, not an Excel-authored workbook. Obtain permission to use a synthetic workbook saved by Excel and compare initial values and changed-input results, including dependent unsupported cells and cross-sheet/cycle cases. Full Excel fidelity is not a promise; close the useful subset gap incrementally and state what remains saved-only.

## 3. Automations run only while Sevra is active

**What exists.** [NativeAutomationHost.swift](../../../Sources/SevraApp/NativeAutomationHost.swift) intentionally defers while the app/window/session is inactive, asleep, busy, under memory/thermal pressure or in Low Power Mode. `NativeAutomationController` and `AutomationDeviceRegistry` already separate exact device grants from portable workbook definitions, bind physical identity/generation, support quiescence and use saved workflow claims. The November 12 due-time checks close the stale result-link defect; they do not establish background capability.

**Near-term closure:** keep the foreground contract visible, show the current deferral and next eligible occurrence, and retain explicit manual continuation. Do not silently remove `NSApp.isActive` as a background implementation.

**Optional expansion:** first specify a distinct opt-in background execution policy per exact workbook/definition/version with an explicit local-AI and resource budget. A background host must share the existing dispatcher/claims and grant validation rather than create an independent scheduler. Stage one can permit work while the app is open but not frontmost. Running after Quit requires a separate installed native helper/service and a deliberate decision about login, lock, sleep, restart and catch-up behavior. Service registration, packaging and current platform API requirements need verification when that work is selected; none was installed or enabled here.

There must be one execution owner, bounded replay of missed occurrences, cancellation before changing grants, durable result notifications and a clear Pause all that revokes both hosts. Copies, restores and imported templates stay inert. Replaced/deleted/moved workbooks must follow the existing physical-identity policy. Business mutations still wait for review and no notification may authorize them. Sleeping/offline hardware cannot be promised exact-time execution.

**Future functional qualification, not executed now:** app/helper contention, crash/lease recovery, pause during a claimed step, changed version/grant, replaced copy, locked/sleeping session, missed occurrences and AI memory pressure. Prove one occurrence produces at most one effect before broadening availability claims.

## 4. Other limits that need their own evidence

| Limit | Concrete closure | Boundary |
|---|---|---|
| Accessibility implementation and runtime confidence | The ten code fixes are implemented and compiled. Owner follow-up remains for actual focus, speech, enlarged layout and source interactions. | No runtime accessibility testing under the current owner decision; no conformance claim. |
| External usefulness | Give one consenting, uncoached user the supplier files and an outcome, observe completion, then fix the actual blocker. | Internal fixtures do not prove adoption or usability for that audience. No outreach sent here. |
| Production signing/notarization | Obtain a valid owner-controlled signing identity, build the exact release artifact, notarize/staple and verify installation/update/uninstall on a clean supported Mac. | No valid identity was found in the prior check. This remains a source preview; no credentials, purchase or release authorized here. |
| Hardware and memory | Qualify the stated minimum and supported memory profiles on actual available Macs using the same complete job and resource bounds. Improve preflight and recoverable memory errors where needed. | The previous 20 GB-model memory blocker is closed on the tested 48 GB Mac. Other profiles are not inferred from that result. |
| Transcript accuracy and availability | Show transcript uncertainty and preserve the original/time links; use a small labeled speech set in the intended languages before accuracy claims. Retain chunking, cancellation and retry. | The long-recording lifecycle passed; recognizer substitutions remain. On-device language availability is a separate prerequisite. |
| Large-workbook storage and latency | Profile immutable-change/provenance bytes on representative row shapes, separate essential evidence from avoidable repeated payloads, and reuse shared immutable payloads where reconstruction permits. | Bulk import completion does not resolve the recorded roughly 10 KB per short-row footprint. Do not delete history or raise transaction limits to hide it. |

Each future change should use the repository's focused verification policy. The later accessibility pass changes source code only. The broader proposals, installed app, model, grants and system settings are unchanged. [[records/operations/agent-handoff]] is the restart point when the owner chooses to resume.
