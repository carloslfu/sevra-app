---
type: research
meta-type: conclusion
id: 01m7gjt29wpn77rzz5z9z27g91
created: 2026-11-15T21:46:27.516157+00:00
updated: 2026-11-15T21:49:30.423421+00:00
summary: Code findings, retained synthetic probes, historical workload limits and Splash 1.6.1 relevance for context planning.
title: Inference and context upgrade evidence
---
# Inference and context upgrade evidence

## Scope and provenance

Research for [[records/plans/inference-context-upgrade]], inspected at source `658f06947867de8a3e4676c9e1edfb8fc65ced76` on November 15, 2026. This is code/source analysis and retention of earlier synthetic CPU and model evidence. No candidate engine execution, fresh GPU comparison, memory exhaustion, app installation or UI verification occurred in this planning checkpoint.

The [retained audit manifest](../../../integration/evidence/2026-11-15-inference-context-planning/audit.json) records the earlier audit-start commit `f90529ab98dc21db38fb9e325c391019c1a75736`, copied test-binary SHA-256, inspected source hashes, commands' exit outcomes and evidence limits. The copied existing binary passed 53 CPU check groups. Its hash plus contemporaneous source hashes are not proof of a fresh whole-source build. The standalone Swift/C++ probes are retained alongside their raw outputs; they are research fixtures, not installed product changes.

## Reproduced accounting behavior

`NativeWorkbookModel.measureContext` constructs a citation/tool policy without the dispatch scope. `respond` uses the scope. `WorkbookAgent` determines scope but its measurement interface does not carry it. The owning conversation contract explicitly calls the all-tool count conservative, so changing it also changes the policy and corresponding tests.

The [controller probe](../../../integration/evidence/2026-11-15-inference-context-planning/controller-audit.swift) exercises the real tokenizer and controller with a no-generation backend. Its [results](../../../integration/evidence/2026-11-15-inference-context-planning/controller-audit.jsonl) show:

| Synthetic rows | All-tool count/outcome | Answer-scope count/outcome |
| --- | --- | --- |
| 280 | 27,187; context limit | 22,558; dispatch reached |
| 320 | 29,360; context limit | 24,717; context limit |
| 400 | 33,685; context limit | 29,030; context limit |

The threshold is 24,576. `audit_dispatch_reached` deliberately ends the admitted arm; it is not a model success or product exception. All workbook integrity checks passed. Token counts depend on the frozen tool/schema version and must be refreshed for implementation. The separate scope-only probe has different context assembly and thus different counts; do not mix its rows with this controller table.

`ContextBudget.allowance` permits authoring output up to 8,192 tokens while its threshold reserves only normal output 1,800. At prompt count 24,575, 32,768 minus prompt minus authoring output leaves one token. That conflicts with the intended next-tool 2,048 and recovery 256 reservations. Existing post-step checks remain; this evidence does not demonstrate out-of-bounds engine writes. A mode-aware 32K authoring threshold using the current reserves is 22,272. Reasoning is already inside total output and must not be subtracted twice.

Measurement currently passes through the worker/session path and can launch the helper. The helper Ready response already includes actual context, but host measurement uses configured capacity. Both are relevant to useful pre-job profile selection.

## Context, memory and structural bounds

Current native product wiring requests 32,768 context tokens and 12 GiB engine memory. The configuration type exposes 8K/32K/64K, not 128K or 256K. The 1 MiB/512-message envelope, 16,000-byte user prompt and tokenizer structural bounds are independent limits. Token-density probes on roughly 1 MB of text ranged from 226,953 English tokens to 931,023 numeric CSV tokens; a byte cap cannot be converted to one dependable token capacity.

The target attention KV geometry from the pinned 1.4.1 headers is 10 attention layers, two KV heads, head dimension 256, 32 tokens/page and 332,800 bytes/page. [Probe and values](../../../integration/evidence/2026-11-15-inference-context-planning/kv-audit.txt): 32K = 325 MiB, 64K = 650 MiB, 128K = 1,300 MiB and 256K = 2,600 MiB. These are target attention KV bytes only. They omit target/draft weights, draft KV, GDN state, scratch, cache/planner rounding, CPU/frontend/application and OS memory. They do not prove a complete profile will start or remain responsive.

The [pinned memory planner](https://github.com/incoai/splash/blob/1744cfafee415fb463b289449cec59a864e768e9/runtime/engine/MemoryPlan.cpp) allocates across context and weights/cache. Increasing requested context within a fixed budget can reduce the expert cache. Reducing context with the same budget may increase cached weights, leaving total allocation high. An old max-context report for a particular 32K plan is not a universal upper limit at that memory budget, because asking for a different context changes the plan. The retained occupied 32K and 64K receipts are not a same-input speed comparison.

The inspected host is an M5 Pro with 48 GiB unified memory. Product hardware eligibility is M3+/macOS 26.4+, but no complete per-RAM-tier context qualification follows from that. The budget is not total physical footprint. No destructive memory-pressure run was performed.

## Historical complete-job evidence

The [Excel analysis](../../../integration/evidence/2026-11-15-inference-context-planning/excel-summary.json) reanalyses `integration/evidence/2026-11-14-fresh-excel-apps/trials-and-checks.json.gz`, frozen at `da3c4720e05033b5aaea620ebb01abde28123d9e`. Two accepted batches cover 20 fresh apps and 83 responses, with prompt counts 4,026–15,132 and median 10,051. None reached 16K or recommended maintenance. Across those responses prefill totals 221.065724 seconds and decode 4,394.298224 seconds; this is not a controlled engine comparison or complete end-to-end job timing. An earlier failed batch's 36 responses were also below 16K; those failures do not demonstrate context exhaustion.

The synthetic workflows include inventory, invoices, timesheets, cashflow, commission, loans, production, lookups, due dates and reference codes. They are useful fixtures, not telemetry about customer task frequency. Future qualification must use the current frozen versions and independent business oracles.

The later 32K eight-document receipt `2026-10-27-document-copy-native-eight-report.json.gz` completed 12 responses and eight summaries/checkpoints in 234.2045 seconds including verification. Normal prompt counts reached 24,435; summary requests took 39.2678 seconds. It preserves exact labels, but the model selected prose rather than the available source-copy operation, so it does not qualify actual source-copy selection. The earlier `2026-10-27-active-context-first-full.json.gz` 64K uncompressed failure remains a failure. Different context occupancy, maintenance settings and source versions prevent treating these receipts as a fresh 32K-versus-64K controlled experiment.

## Existing qualification blocker

The complete W1 ten-block cohort at `0e45190` completed 260 jobs and met timing limits but failed exact native/reference generated-output parity in an inventory warmup. The later D9 preserved-prefix replay found one reference repeat diverging while the two native repeats and another reference repeat matched. This does not prove a Swift defect, universal native determinism or an upstream numerical root cause. The original failed cohort and repeatability evidence remain authoritative; no engine promotion follows from passing timing alone. See [[records/specs/splash-integration]] and `integration/evidence/2026-10-27-prefix-d9-repeatability.json.gz`.

The request-level R1 priority mismatch and later command/cache/tracing confounds also matter. The plan requires actual serialized parameters, symmetric cache/command history, frozen workers and uninstrumented qualification. Same-engine adapter equality and cross-engine business-result equivalence are distinct tests. A bounded candidate replay must precede another full cohort; repeated runs until one passes would not resolve the known issue.

## Candidate release and practical relevance

[Release identity](../../../integration/evidence/2026-11-15-inference-context-planning/engine-release.json) records Splash 1.6.1, published November 11, 2026, source commit `d8af1054aab0f97de21d043e01aa98af3754f10e`, annotated tag object `f3ee53329926d53d42159fd40cad28cdd3080393` and the published archive digest. The GitHub release is not immutable. Implementation must download/hash the archive and pin extracted executable/Metal/license resources; metadata inspection does not perform those checks.

The [commit inventory](../../../integration/evidence/2026-11-15-inference-context-planning/upstream-commits.json) retains 132 commits between 1.4.1 and 1.6.1. The source diff spans 592 files. Relevance is mapped by integration surface in the plan; line volume is not a claim that every upstream feature changes Sevra.

| Change group | Relevance to this app |
| --- | --- |
| Protocol 11 → 13, status 6 → 8 | Adapter work: Stop, richer Ready, structured StartFailed, Warming and status metadata. Compare actual serializers/goldens; comments alone can misrepresent already-existing fields. |
| Expert streaming/compute overlap, router memory, warmup and slow-disk handling | Plausible startup/throughput/footprint improvements. Must measure complete jobs under matched cache/memory conditions. |
| 1.6 context/budget planner fix | Admission and configured-versus-effective capacity regression cases. Not a promise that every large context fits. |
| M5 automatic INT8 activation paths in 1.6.1 | Can affect both performance and outputs. Isolate BF16 version comparison from precision adoption; refresh cache identity. |
| Selected-model format/setup and text/grammar integration | Diff source, exact prompt and token/mask/streaming semantics. Current selected target/draft stay fixed initially. |
| LLGuidance | Upstream remains 1.8.0. Version match does not prove C/Python defaults or full-vocabulary masks match. |
| Python frontend prefix cache | Not inherited by Swift. The existing Swift bounded cache is a separate implementation; optimize only with a measured need and exact parity. |
| KV spill, other models, concurrency, HTTP server and upstream app/PDF/chat | Selected 35B model has no KV SSD spill. Other serving/UI capabilities do not automatically apply to Sevra's selected-model, Swift, single-inference architecture. |

Primary upstream sources: [1.6.1 release](https://github.com/incoai/splash/releases/tag/1.6.1), [1.6.1 changes](https://github.com/incoai/splash/blob/1.6.1/docs/release-notes/1.6.1.md), [1.6.0 changes](https://github.com/incoai/splash/blob/1.6.0/docs/release-notes/1.6.0.md), [1.5.0 release](https://github.com/incoai/splash/releases/tag/1.5.0), [server and memory behavior](https://github.com/incoai/splash/blob/1.6.1/docs/server.md), and [Qwen model declaration](https://huggingface.co/Qwen/Qwen3.6-35B-A3B). The model declares native 262,144 context and approximately 1,010,000 with YaRN. The latter is a separate positional-scaling configuration, excluded from the proposed default experiments.

## Limits and conclusion

There is enough evidence to choose the implementation order and identify concrete fixes. There is not enough matched evidence to name an optimal context/memory pair, promise an engine speedup or support all eligible Mac RAM tiers. The plan makes those choices finite, controlled experiments with explicit success/failure gates. It does not need customer telemetry to fix demonstrable accounting, but synthetic fixtures must not be described as the user's measured workload distribution.
