---
type: review
meta-type: conclusion
id: 01m7gk15e9b0jr0h3jm6zg72h9
created: 2026-11-15T21:50:20.105217+00:00
updated: 2026-11-15T21:51:34.604416+00:00
summary: Three sequential plan reviews close architecture, recovery and evaluation gaps while retaining explicit implementation and qualification gates.
title: Inference and context plan readiness
---
# Inference and context plan readiness

## Scope and verdict

Three sequential self-review passes were completed against [[records/plans/inference-context-upgrade]], its owning contracts, selected implementation paths and retained evidence. These were distinct reviews by the planning agent, not independent agent or human approvals. Revision 4 is ready for staged implementation. No engine, profile, installed app or production acceptance is claimed.

The source baseline is `658f06947867de8a3e4676c9e1edfb8fc65ced76`; upstream candidate is Splash `d8af1054aab0f97de21d043e01aa98af3754f10e` (1.6.1). Supporting research: [[records/research/inference-context-upgrade]]. Each pass revised the plan before the next pass. The resulting implementation gates are deliberately not marked complete.

## Pass 1: architecture and integration

Read the complete draft against `ContextBudget`, `WorkbookInference`, native preparation/generation, `NativeReasoning`, `ContextMaintenance`, upstream protocol 13 and the upgrade skill's surface map.

| Finding in revision 1 | Revision 2 correction |
| --- | --- |
| A universal next-request threshold could accidentally apply ordinary 75% maintenance semantics recursively to summary generation. | Separate summary fitting: exact summary prompt/output/recovery within capacity, bounded batches and no fictitious tool result for a tool-free summary. |
| Ready capacity was authoritative but its relation to the chosen policy was underspecified. | Effective capacity is bounded by selected qualified profile, Ready, model and host/wire limits. Larger Ready does not expand policy; smaller Ready triggers re-admission. |
| Initial scope preparation did not explicitly cover reconstruction after maintenance. | Reprepare after compaction and changes to snapshot/scope/reference/schema identity; validate at existing authoritative transaction/version boundaries. |
| A protocol comment diff could be mistaken for a wire change. | Compare actual serializers/goldens, including Done bounded and Error retry-after semantics; canonical version update with explicit rejection, no legacy shim. |
| BF16 was too easy to treat as controlling every precision path. | Freeze KV/state precision and any independent Neural Engine setting; isolate M5 auto activation comparison and cache identity. |
| New capacity values could exist in the product but not reach the test harness. | Name the existing test owners and require harness argument/capacity updates before claiming 128K/256K execution. |

Result: coherent single prepared-request path, explicit mode-specific reserves, unchanged target/draft model and a complete native surface/fixture map. Actual all-tool measurement and authoring-reserve defects remain implementation work.

## Pass 2: state, recovery and user experience

Read revision 2 against current single-call enforcement, product memory-pressure handling, native cancellation/close timers and conversation authority/coverage rules.

| Finding in revision 2 | Revision 3 correction |
| --- | --- |
| One tool-result reserve could be misapplied to a future multi-call phase. | Prove single-call enforcement before mutation; any allowed batch reserves aggregate results/framing. A committed write survives projection failure and is never replayed. |
| Bounded digest size alone does not prevent no-progress maintenance loops. | Require progress and a finite maintenance/repair bound, with preserved originals and a truthful stop. |
| Retrieval could narrow a user's request without making the omission visible. | Reuse coverage/provenance state and require complete declared source coverage or explicit partial completion. |
| Pre-job selection ignored an already warm idle helper. | Include reload time, stop/reap/lease discipline and at most one already-qualified admission fallback. |
| Exceptional mid-job growth left too much optional scope for the first release. | Exclude automatic mid-job capacity expansion initially. Any later exception requires a separately recorded evidence/lifecycle gate. Dead-helper recovery is distinct. |
| “Responsive Stop” had no measurable relationship to existing timers. | Measure acknowledgement/UI response and full queue/teardown path; preserve current 3-second cancellation wait and 1+3-second termination/reap limits. A stuck child retains the lease. |

Result: ordinary users receive a stable profile, truthful progress and saved work. Critical memory pressure and explicit cancellation stay stopped until explicit continuation. Lower context is not represented as memory relief unless actual allocations fall.

## Pass 3: experiments, provenance and release

Read revision 3 against both R1 and W1 protocols, performance-harness rejection logic and the full historical request-priority, command/cache, tracing and D9 repeatability findings in the integration specification.

| Finding in revision 3 | Revision 4 correction |
| --- | --- |
| Referring primarily to request-level R1 obscured the stricter complete-workflow W1 gate. | Name both contracts. Preserve exact same-engine workflow sequence equality separately from semantic cross-version/context comparisons. |
| Existing W1 timing success could be mistaken for completed adoption. | Explicitly retain the failed paired-output gate and D9's reference-repeatability observation. No promotion follows from timing alone. |
| Repeating a full cohort could simply wait for a passing random outcome. | Require a bounded candidate replay of the preserved preceding history before full qualification. Persistent repeatability failure stays open; changing the acceptance contract requires a separate explicit reviewed decision. |
| A strict adoption blocker could unnecessarily prevent useful context research. | Permit clearly labeled P4 candidate research after behavioral/lifecycle/admission prerequisites, but keep P7 promotion gated. |
| Intended request settings and cache-hit counts do not establish identical computation. | Capture actual wire fields, compare mapped semantics across protocols, preserve priority/cache/command symmetry and distinguish initial versus later KV reuse. Freeze sources/resources/workers before every worker and finalization. |
| Traced/cache-isolated probes or tiny sample sets could be promoted as speed evidence. | Separate diagnostics and screening from uninstrumented normal-cache cohorts; 10 × 2 observations per workload, observed-p95 caveat, all failed/priming/warmup outcomes retained. |
| A vague rerun allowance could erase semantic or safety failures. | At most one predeclared timing-uncertainty cohort, reported together. Wrong answers, parity or identity/lifecycle failures require diagnosis and an explicitly revised candidate/protocol. |

Result: the plan can select a better profile without confounding accounting, engine version, precision, context, memory and cache policy. Candidate provenance remains metadata-only until P0 verifies archive/component bytes. Historical fixtures remain synthetic evidence, not customer telemetry or current-source qualification.

## Integrated coverage and remaining decisions

The final pass checks the entire path: source/version authority, actual scope and exact counting, output/reasoning/tool reserves, summary fitting, structural input bounds, context versus memory tradeoffs, model setup/reuse, protocol/text/grammar, lifecycle/lease, visible progress, cancellation/recovery, complete-job oracles, performance statistics, resource pressure, packaging and rollback. P0–P7 have dependencies, outputs and exit conditions. Implementation starts with P0/P1, not a configuration increase.

No unresolved planning contradiction remains from these passes. Empirical decisions deliberately remain: which context/memory/activation profile wins, which hardware tiers qualify, whether the new engine resolves the existing strict parity blocker, and whether any related dependency needs a real change. Each has a finite test or decision gate. They are not claims that the code already works or that 64K is inherently optimal.

Documentation/evidence verification is recorded below after repository checks. Runtime and UI verification belong to implementation; documentation validation cannot substitute for them.

## Documentation and evidence verification
Verified November 15, 2026 after all three review passes:

- `dbmd index rebuild --dir db --json`: full hierarchy rebuilt.
- `python3 scripts/check_links.py`: repository Markdown links passed.
- `dbmd validate --all db --json`: zero errors, warnings or informational findings.
- `git diff --check`: passed.
- Read-only evidence audit: all retained JSON/JSONL parses; 132 upstream commit entries; 53 historical CPU PASS groups; all six controller integrity checks true; admitted and rejected boundary cases match the research; reserve arithmetic verified. New records/evidence contain no private local paths or recognized credential patterns.

These checks validate the plan, links, store and retained evidence consistency. They do not rerun historical model fixtures or qualify current-source inference. No product source, active pin, model weight, runtime configuration or installed bundle was changed. The candidate archive was not downloaded or executed. Full build, real-model comparisons and UI/install qualification remain P0–P7 work.
