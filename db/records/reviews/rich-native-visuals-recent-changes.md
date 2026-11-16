---
type: review
meta-type: conclusion
id: 01m7k3ehrd9mpvv0jhtqesk699
created: 2026-11-16T21:15:44.781484+00:00
updated: 2026-11-16T21:16:45.909479+00:00
summary: Revision 16 accounts for all three recent inference commits, 95 changed files, token/receipt and human-answer contracts; 53 CPU agent groups pass.
title: Visual-plan review after inference changes
---
# Visual-plan review after inference changes

Owner request: [[sources/notes/2026/11/visual-plan-recent-changes]]. Reviewed November 16, 2026. The owning [[records/plans/rich-native-visuals]] advances to revision 16 after three passes. The previous plan commit was `383b70f504fea2663822295ca16e662a2560eb43`; the new clean source is `33edcd51dc23b039573562a0d18c207d52ef9530`. The [complete change inventory and check receipt](../../../integration/evidence/2026-11-16-visual-plan-change-audit.json) records every changed path/hash and the evidence used. This review changes documentation, not runtime policy or product features.

## Pass 1: all recent changes and evidence

Three commits affect 95 paths: 21 product source files, 25 integration-test files, 16 scripts, 10 runtime/evidence/protocol files, 22 knowledge files and README. Generated fixture changes were compared structurally; historical/new evidence was read according to its frozen source/configuration and qualification limits. Catalog churn is not counted as implementation.

| Commit | Actual change | Effect on this plan |
| --- | --- | --- |
| `c6a588c` | Exact scoped preparation/counting, complete response reserves, bounded result presentation, CPU preflight and accounting fixtures. | The preparation dependency has landed. New controls/results must join this path and its actual token budgets. |
| `26f2ee7` | Splash 1.6.1/protocol 13/status 8; startup capabilities/shortfalls and ownership; text/grammar/model-assembly fixtures; receipt/history fixes; qualification tools and retained failures. | New terminal states, history metadata and evidence must survive these interfaces. Engine integration is not widget or vision support. |
| `33edcd5` | Owner-directed native preview adoption, measured 64K/32K startup choice, unchanged 12 GiB engine allowance and installed-preview evidence. | Current profile, performance baselines and documentation must reflect the adopted preview while retaining broad qualification limits. |

Coverage by seam:

- **Agent/accounting:** ContextBudget, ContextDigest, ContextMaintenance, WorkbookInference/WorkbookAgent, NativePreparedRequest/NativeWorkbookModel and the preserved baseline measurement adapter. Measurement and generation now use the same native preparation path with actual scope, dynamic schemas/references and complete response/result reserves. Counting can run before helper startup; generation rechecks Ready capacity.
- **Receipts/history:** ToolReceipts adds tokenizer-bounded transient projections while originals remain saved. Evidence admits visible whole fields rather than omitted data. ConversationContext distinguishes an original user statement from a later assistant answer. ItemReferenceCandidates prioritizes explicit originals within bounded lookup choices; annotation, ExcelBuildContext and maintenance now preserve review metadata.
- **Native product/lifecycle:** ProductAI/NativeProductResources select 1.6.1 and 64K at 48 GiB or above, otherwise 32K under existing hardware checks. NativeProcess/Wire validate Ready vocabulary/mask rows/stops, Warming, StartFailed, status schema and owned teardown; successful frontend Stop remains distinct from user Cancel. The source rejects vision-enabled readiness and remains text-only. WorkspaceState's ordinary completion footer now says Response ready.
- **Resources/fixtures:** Selected-model assembly uses root config plus unchanged weights, template/output fixture changes preserve their actual content where only upstream identity changed, and tool fixtures now include the already implemented image declaration. The relevant grammar hashes changed; LLGuidance remains 1.8.0 and package pins are unchanged. Resource/byte fixtures do not qualify future tools.
- **Harnesses/scripts:** Accounting probes, Unicode paging, metadata/history tests, threshold checks and observed/reference wrappers cover the new contracts. Excel conversation probes now use production-default maintenance and distinguish fresh generation from replay. Startup admission, context screening, historical request reconstruction, repeatability and the old/new pilot preserve exact identities and explicit limits. Fixed-input/no-maintenance benchmarks cannot substitute for normal conversational acceptance. The complete inventory includes all 16 changed scripts and their fixture/protocol consumers.
- **Evidence/status:** The accounting receipt is old-engine host proof; startup admission is not useful-task qualification; candidate replay is not fresh authoring. The newer preview comparison is one run per setting on a 48 GiB M5 Pro, not a hardware survey, speedup result or new rich-UI cohort. Its product-configuration SHA matches current source. Earlier authoring, repair and strict repeatability failures remain retained.

No recent source change implements request_input, native rich chat results, standalone Home images, the shared visual catalog or the isolated media path. Revision 15's eight handoff corrections remain applicable.

## Pass 2: implementation consequences

1. **Remove the obsolete conditional preparation dependency.** Revision 15 said to consume unified preparation when it lands. It now exists. The plan names NativePreparedRequest, actual next-step scope and WorkbookInference.measureContext(toolScope:), with parity for filtered declarations, operation permissions, host capability and dynamic reference choices. A widget cannot introduce a parallel preparation/budget path.
2. **Separate storage sizes from generation budgets.** A 64 KiB surface is a storage limit, not a feasible ordinary model response. Current ordinary generation allows 1,800 tokens including reasoning; ordinary tool results start at 2,048. Small host-backed questions, descriptor references and complete compact family schemas must fit those measured budgets. Large recipes can be retrieved explicitly; a partial schema cannot masquerade as a full contract. Neither authoring mode nor a larger context is a workaround for oversized UI descriptions. New token fixtures must exercise the real native tokenizer/projection: the scripted inference protocol default returns results unchanged and cannot prove that contract.
3. **Integrate capture and evidence with bounded projections.** A compact verified capture header must remain usable after projection; full descriptors/manifests remain in saved receipts. A host may attach a verified captured image/chart using its inspected identity/coverage summary, while prose facts still need visible supporting values. New capture IDs need trusted metadata and validation, not UUID scraping. If projection fails after a saved effect, recovery preserves the receipt and cannot repeat the operation. Host-rendered review controls use full exact receipts.
4. **Save the real human answer and preserve metadata.** Native answer submission needs a canonical role=user message with supplied values, qualification and exact surface/response identity. An event-only receipt or assistant paraphrase cannot establish what the user supplied through readHistoryEvidence. Typed replies reuse their original message. Pending/capture references must survive every InferenceMessage rebuild and compaction outside the limited generic lookup menu; originals retain conversation scope and do not renew authority.
5. **Make terminal UI behavior explicit.** needs_input is an application outcome after a complete validated response, not an early transport Stop or user Cancel. The new Response ready footer must not overwrite Waiting for your answer or Answer saved, continuation not started. Startup refusal, late completion and cancellation remain separately tested.
6. **Qualify against the actual current preview.** The architecture still works at 32K/64K; larger capacity does not loosen output budgets, image limits or evidence rules. Model-dependent feature cohorts record exact runtime/profile/maintenance and must qualify both advertised configurations. Hardware scope stays explicit. Earlier Excel cohorts and unchanged-app replays cannot clear new widget creation/edit acceptance; known generation failures cannot be omitted.
7. **Reconcile contradictory current-status language.** The inference plan and its canonical conversation/Splash specs still mixed the installed 64K/32K preview with earlier no-install/32K candidate wording. Current summaries/checklist wording now distinguish preview adoption from broad production qualification; the earlier failure findings and immutable receipts are unchanged. This corrects documentation, not runtime behavior.

## Pass 3: whole-plan consistency

| Plan sections | Outcome |
| --- | --- |
| 1. Current implementation | Added the exact new agent/runtime baseline and its qualification limits. Image/chat availability inventory remains accurate. |
| 2–3. UX and catalog | The representation choices, optional controls, calm Home and early images remain useful. New context capacity adds no component capability and does not justify an always-loaded catalog. |
| 4. Architecture | One visual contract, canonical source edits, durable attachment publication, exact historical capture, scoped grants and bounded media remain unchanged. File map includes current preparation/projection/metadata seams. |
| 5. Chat and authoring | Updated preparation, token budgets, capture headers/evidence, human-answer history, metadata preservation and terminal consumers. Existing text/control parity and no-inference known operations remain authoritative. |
| 6–7. Technology and stages | No dependency/library change is required. Start P0-chat; P1-image reuses it, then charts and later families. The already adopted preview is not a pending prerequisite; missing feature acceptance still is. |
| 8–9. Verification and gates | Added token/receipt, original-human and terminal-state counterexamples; bind actual-model acceptance to current 32K/64K profiles with normal maintenance. Image/resource measurements include the loaded model's total footprint. All feature checkboxes remain open. |

This is ready for staged implementation. The remaining uncertainties are measured acceptance work, especially model-authored correctness, native focus/layout and bounded media resources. The plan does not promise that the full catalog or every hardware tier already passes.

## Verification and limits

Fresh checks on clean 33edcd5: `swift build --product sevra-agent-checks -j 4` passes, then `.build/debug/sevra-agent-checks` exits 0 with 53 reported PASS groups. These include scoped budgets/refusal, request/terminal authority, history/reference choices, receipt/evidence handling and repeated compaction. They are CPU/scripted checks, not a new real-model cohort or UI inspection. The inventory receipt retains the log hash and all source identities.

Reused published evidence is explicitly bounded: context-accounting, context-admission, splash-upgrade and splash-native-preview receipts retain their original source/configuration/failure scope. No GPU experiment, installed-app control, package replacement, model download, engine change, new feature code or production claim was made for this review. Broad release reruns are unnecessary for documentation under the focused verification policy. Final dbmd validation reports zero errors/warnings; repository links and git diff --check pass. Both plan JSON examples parse, all nine numbered sections remain and every feature acceptance checkbox is open. The 95-file inventory matches the frozen three-commit range.
