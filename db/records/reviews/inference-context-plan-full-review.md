---
type: review
meta-type: conclusion
id: 01m7gksj5wja0ytnp8vkjkx1d2
created: 2026-11-15T22:03:39.580552+00:00
updated: 2026-11-15T22:09:29.066888+00:00
summary: Complete plan re-review resolves 18 integration, accounting, lifecycle and experiment gaps; revision 5 is ready for staged implementation.
title: Complete inference and context plan review
---
# Complete inference and context plan review

## Scope and verdict

The owner requested a full re-review in [[sources/notes/2026/11/inference-context-full-review]]. Every section of revision 4 was rechecked against code, upstream 1.6.1 source, existing acceptance contracts and the original review. The resulting [[records/plans/inference-context-upgrade]] is **revision 5, ready for staged implementation**, with the corrections below. This was one comprehensive self-review, not an independent agent or human approval. [[records/reviews/inference-context-plan-readiness]] remains the historical record of the first three passes.

Baseline: `5b05c5f6127d6956d63c167c7bc2b42812578047`. The checkout was clean, and no product changes occurred during this review. The upstream checkout was clean at `d8af1054aab0f97de21d043e01aa98af3754f10e`. Release API metadata reconfirmed 1.6.1 as the latest stable on November 15, 2026. This review also downloaded and hashed its archive and inspected whitelisted member bytes. It did not execute the candidate, load its Metal libraries, install an app or perform a new GPU/context comparison.

“Ready” means an implementer has concrete behavior, dependencies, test boundaries, failure handling and decision gates. It does not mean the current accounting is fixed, the new engine is qualified, 64K is optimal or a hardware tier beyond the inspected 48 GiB host is supported.

## Findings resolved in revision 5

| ID | Gap or ambiguity in revision 4 | Evidence and resolution |
| --- | --- | --- |
| R01 | Main-loop measurement still could precede final read-only scope and authoring flag selection. | `WorkbookAgent.swift` sets both after measuring. Require all preparation dependencies finalized before counting and shared with generation. |
| R02 | An implementation limited to the main controller would miss direct inference calls. | `ExcelConversionAgent.analyze`, `NativeAppReview` and `WorkflowCoordinator` bypass its maintenance controller. Put admission at the shared inference boundary; add caller-specific exact-request/boundary checks. |
| R03 | “Review output 4096” obscured differing current modes; workflow interpretation requests 4096 but actually clamps to 1800. | `NativeWorkbookModel.generate` distinguishes Excel review and interpretation; core interpretation saves 4096. Add a complete mode table and requested/effective metrics; preserve actual 1800 interpretation behavior for the controlled baseline, test any increase separately. |
| R04 | A universal 2048 tool-result cap could break exact-copy/inspection, and a narrow scope might later expand. | Inventory/tokenize bounds per scope, include framing/retry results and aggregate allowed batches. Reserve or safely re-admit known phase/schema growth; 256 recovery is not a guarantee against a much wider schema. Preserve exact material through receipts/locators/paging. |
| R05 | “Revalidate snapshot” could become a long workbook lock or endless retries from unrelated edits. | Existing core interpretation captures exact input outside inference and fences apply separately. Specify short transactions, relevant-version checks, off-UI CPU preparation and commit-time authority/cancellation. |
| R06 | The bounds list omitted review/interpretation inputs, output JSON and parent claim deadlines. | Core evidence is capped at 65536 bytes; app review at 96000, verdict JSON at 12000, retry diagnostic at 16384; frontend depth 32; workflow parent deadline 180 seconds. Add these and prohibit a new request timeout extending the parent. |
| R07 | “Preflight through the memory planner” implied an allocation-free public API that does not exist. | Native commands expose checks/families/serve, not general dry-run planning. Separate CPU preflight from one-helper admission and preserve upstream's 30-second temporary startup recovery within the host deadline. |
| R08 | Protocol Stop and user Stop shared a name but have different completion semantics. | Upstream `StopFrame` can finish successfully as Done/stop. User Stop must remain Cancel plus host cancellation state and cannot dispatch a partial or raced action. |
| R09 | Runtime identity changes were not connected to saved workflow attempts and prior evidence. | The native adapter requires exact model identity; core persists request/claim/model provenance. Preserve old receipts, create new claimed attempts when required, invalidate only dependent caches and never relabel prior outputs or replay effects. |
| R10 | New engine defaults, temporary cache and Ready metadata could be overinterpreted. | Keep numeric context/budget, verify-rows all, persistent-off and idle policy explicit. Ready bounds vocabulary/masks/context, not model/template hashes. Preserve text-only input, local cache failure handling and verified-weight reuse. |
| R11 | Rebuilding the candidate can destroy the baseline output needed for comparison/rollback. | `package_native.py` removes `output/native`. Archive original preview and, separately, corrected P1/1.4.1 worker before P2; retain matching resources/CLI and manifests. |
| R12 | A corrected current-agent replay could be called an exact replay of historical D9. | Scope/schema corrections change prompts. Separate frozen historical token-prefix diagnosis from fresh current-agent fixtures and keep tracing out of uninstrumented qualification. |
| R13 | “Two finalists” did not guarantee a stable control; requested cells could hide clamped admission. | Retain same-engine 32K/12 GiB control plus at most two candidate finalists; record actual admitted context/budget and failures, never relabel a different admitted profile as the requested cell. |
| R14 | Reusing screening examples and vague “benefit” risked selecting a profile on noise. | Use disjoint formal task variants/placements, preregister oracles and exact cohort/resource/UI gates, and require a newly completed needed task or repeatable full-job improvement. Stop at corrected 32K when no benefit qualifies. |
| R15 | “Hold the lease for each comparison” could cause double acquisition. | The adapter already owns the global flock. The orchestrator serializes workers and detects overlap; it does not take a second outer lock blocking the adapter. |
| R16 | “Every wrong answer fails” was ambiguous about permitted in-run automatic repairs. | Existing workflow contract permits validated correction with latency included. Distinguish raw failures, recovered final success and unrecovered job failure; no manual repairs or rerunning until green. |
| R17 | Per-stage 5% tolerances could compound into a substantially slower final app. | Add final end-to-end comparison to the frozen original preview on common successful ordinary tasks. Newly enabled tasks report baseline failure, never a fabricated speedup. Reuse qualifying evidence where conditions already match. |
| R18 | Release/rollback scope could drift into production distribution, unqualified final settings or incompatible data rollback. | Target source preview; qualify the final selected profile and exact-head local/hosted/installed identity, not just P3's 32K settings. Preserve matching prior app/CLI/resources and current-format data; an unplanned format change requires revising rollback before release. |

Artifact verification additionally closes the previous metadata-only provenance gap. The native member hashes and unchanged Apache license/changed notices are recorded in the artifact receipt. No installed behavior follows from that integrity check.

## Complete section coverage

| Plan section | Rechecked against | Disposition |
| --- | --- | --- |
| Decision/status | Owner request, native AGENTS/DB/README, source baseline | Planning only; current source-preview scope and four review stages explicit. |
| Findings | Retained controller/token probes, actual measurement/generation order, historical Excel evidence | Findings retained with frozen-source/no-answer-quality limits; direct-call and mode details added. |
| 2.1 Preparation | `WorkbookInference`, `WorkbookAgent`, native worker, Excel and review callers, baseline adapter | Shared admission, exact final scope, CPU preparation and transaction boundaries specified. |
| 2.2 Capacity/reserves | `ContextBudget`, `NativeReasoning`, summary controller, native output limits | Mode map, actual requested/effective limits, per-tool projections and separate summary budget specified. |
| 2.3 Working set/bounds | Frontend structure checks, core interpretation, review/Excel bounds, history/citation contracts | Additional independent byte/JSON/attempt/deadline bounds retained; larger ceiling does not waive them. |
| 2.4 Resources | Product lifecycle/idle unload, native lease, upstream arguments/bootstrap/planner/protocol | CPU preflight versus real admission, startup retries, cache defaults, stable jobs and no mid-job growth reconciled. |
| 2.5 Identity, added | Native identity check, core saved interpretation and claim/apply fences | Historical provenance, new attempts and unchanged workbook-format boundary explicit. |
| 3 Upgrade | Exact release/source/artifact identities; wire, setup, text/grammar and resource owners | Surface map retained; Cancel/Stop distinction, Ready attestation limits and artifact proof added. |
| P0 Baseline | Package overwrite behavior and current pin/preview qualification | Freeze original bundle before builds; do not block accounting on unrelated upstream/parity work. |
| P1 Accounting | All inference entry points and current mode limits | Exact call-site/boundary tests and corrected-old-engine worker preservation added. |
| P2 Adapter | Protocol 13/status 8, text/grammar fixtures, model reuse and strict resource checks | No profile/precision/default drift; no app promotion from compilation alone. |
| P3 Qualification | I10, R1/W1/D9 records, wire/cache/tracing restrictions | Historical replay and current functional fixtures separated; strict adoption gate retained. |
| P4 Matrix | Requested versus admitted memory/context, current 75% policy and harness limits | Control preserved, real admission, held-out variants, actual occupancy/coverage and bounded experiments. |
| P5 Selection | Default/large-job UX, reload cost, unknown future tool results and hardware limits | Concrete win/stop criteria, bounded pre-job decision and optional-feature omission rule. |
| P6 Native UX | Product pressure behavior, close/cancel timers, source-preview installation identity | Real progress, stopped canceled runs, UI versus process timing and current-source evidence required. |
| P7 Integration | Distribution CI policy, package/install and data/rollback boundaries | Source-preview target, exact-head required checks and compatible matching bundle/CLI rollback. |
| 5 Experiments | Request/workflow protocols and existing harness rejection checks | Distinct comparison claims, all failures, automatic repairs, one lease owner and total final regression guard. |
| 6 Failure matrix | Protocol failure classes, atomic effects, current authority, helper teardown and cache errors | Added Cancel/Stop race, identity/attempt and startup/disk failure cases; no mid-job growth contradiction. |
| 7 Ownership/checklist | Existing module ownership and repository scope | No new coordinator/ledger/cloud system; all P0–P7 implementation boxes stay open. |
| Cross-links/evidence | Owning specs, previous review, research, source note and evidence manifests | Historical claims remain scoped; current readiness/provenance supersedes only what was actually rechecked. |

## Verification and limits

The [review receipt](../../../integration/evidence/2026-11-15-inference-plan-review/review-receipt.json) records checked code/source identities, focused checks and limits. The [release artifact receipt](../../../integration/evidence/2026-11-15-inference-plan-review/release-artifacts.json) records the downloaded archive and its five native/license member hashes. Public evidence contains synthetic data and repository-relative paths.

`python3 scripts/check_performance_harness.py` passed its existing CPU rejection tests for pilot/incomplete evidence, incorrect output, parameter mismatch, missing samples, thermal/power failures and latency regression. That validates harness safeguards only; no performance cohort was run. The release archive matches its published digest and size, all whitelisted members are unique regular files within the product resource bound, and packaged notices match the inspected candidate source.

Final documentation checks are recorded after applying the revision. Remaining implementation gates are empirical: selected profile/precision quality and resources, candidate protocol/text/grammar runtime behavior, strict same-engine parity, complete installed jobs and native UX. None is silently converted to a pass by this review. No unresolved contradiction was found in the revised implementation sequence; these open gates have explicit entry conditions, bounded tests and failure outcomes.

## Final review verification
After revision 5 was applied:

- `python3 scripts/check_performance_harness.py`: passed the existing CPU gate-rejection checks.
- Archive SHA-256/size and all five intended native/license member hashes, regular-file uniqueness and resource size bounds: passed. Packaged notices match inspected upstream source.
- `dbmd index rebuild --dir db --json`: completed.
- `python3 scripts/check_links.py`: repository Markdown links passed.
- `dbmd validate --all db --json`: zero errors, warnings or informational findings.
- `git diff --check`: passed.

The final consistency check verifies the retained inspected-source hashes, release receipt and absence of private local paths/credential patterns in this review's new records/evidence. Concurrent unrelated visual-plan documentation is preserved and excluded from this review's commit. No product build/runtime/model/installed settings were changed. Candidate execution, strict parity, hardware/resource/context behavior and UI acceptance remain untested implementation gates.
