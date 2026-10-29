---
type: spec
id: 01m63vytee21f2t86w8x1t4h3n
created: 2026-10-29T13:00:31.054263+00:00
updated: 2026-10-29T13:51:24.732446+00:00
summary: Schema 24 indexed workflow source identities and bounded automatic ancestry; synthetic acceptance preserves origin. Exact trigger causes and persisted dispatch admission remain required.
title: Automatic derivation ancestry
status: implemented
---
# Automatic derivation ancestry

This is the next reviewed foundation for condition dispatch, after [[records/specs/inventory-condition-consumers]]. It inspects existing exact derivation links and automatic workflow bindings. It does not grant execution, choose a dispatch root, calculate a minimal causal slice, enforce cascade budgets or complete E4. The inspector must remain read-only and inert.

## Meaning and user behavior

A human accepting an automatic proposal adds a decision Source and a new accepted Record version. It must preserve the proposal's ancestry, including its exact automatic workflow invocation. A later correction or manual workflow that derives from that accepted result keeps those links. A genuinely independent human observation with no such links has separate provenance. An actor label or text claiming automatic origin is not proof of an automatic run.

Inspect exact item versions, never mutable heads. Follow derives-from, supersedes and definition-input, including every parent of shared DAG nodes. Look up every visited version through its authoritative workflow_runs source binding, then validate invocation metadata against that saved run, automation_runs and the exact automation definition. Missing or erased metadata cannot make a registered run appear independent. Schema 24 makes workflow_runs.source_id unique and indexed, reflecting its one-invocation-per-run identity and avoiding a full run scan for each ancestor. Require the retained policy, invocation identity, workflow version and origin coordinates to agree. A forged invocation or a missing/inconsistent automatic binding refuses instead of returning a misleading empty ancestry. Historical paused, superseded or reconstructed bindings remain provenance; they grant no present authority.

## Bounded inspection contract

The shared core API is automaticDerivationAncestry(inputs:cancellation:). The explicit CLI is automation-ancestry WORKBOOK ITEM_ID [ITEM_ID...]. Accept 1 to 16 supplied identities, up to 256 UTF-8 bytes each. Deduplicate and sort exact requested versions. Traverse at most 1,024 distinct versions and 4,096 lineage edges; both relations between the same two versions remain separate retained edges. A revision must retain its supersedes edge. Reject unsupported lineage relations, missing versions and graph cycles. Measure the longest path, including shortcuts and diamonds, and refuse more than 128 edges of depth. A visited set alone is insufficient to prove a graph has no cycle or to measure its longest path.

Use the existing three-second, short-busy-wait, cancellation-aware read snapshot. Invocation data inspection is limited to 1 MiB and output to 8 MiB. Never return a truncated graph as complete ancestry. A successful result contains exact requested versions, counts, depth, retained edges, exact automatic run/invocation/occurrence/authorization/dispatch/version bindings and stable automation logical identities. Label coverage=retained-derivation-graph, minimalCausalSlice=false, dispatchEligibility=not-evaluated, execution=none and enabled=false. Return no live grant or serialized process capability. No model tool, prompt or grammar expansion.

The graph includes configuration and control provenance as well as business derivations. Its nodes and lineage depth are not a minimal business cause set, cascade depth or authorization budget. This distinction prevents a report from falsely claiming that every historical dependency caused a particular threshold crossing. It is useful for inspecting preserved ancestry; dispatch needs the separate exact trigger and admission contract below.

## Next dispatch contract, still required

Before dispatch, retain exact scope-relevant triggering versions/effective-time events across partial batches, clock groups and unknown gaps. Do not substitute every unrelated event in a batch or the whole balance history for the cause set. Preserve automatic ancestry through action, calculation, extraction, interpretation, table intake, acceptance and correction. Keep control provenance distinct from the data/cause inputs used for dispatch admission.

Choose and qualify persisted root identity, self-output rejection, cross-automation depth, fan-out and total root budgets. Charge admission and bind occurrence/workflow atomically, preserving evidence across crashes and restarts. Human acceptance alone cannot reset a root. A deliberate independent business occurrence or explicit manual exception needs its own recorded meaning; no actor label silently clears ancestry. Exact numeric caps remain undecided until the integrated candidate/dispatch design and tests support them.

Bind conditions and workflow intent to the exact current physical workbook and device grant. Saving, importing, inspecting and reconstructing never enable work. One active run and bounded retained successors remain required; calendar coalescing cannot erase business crossings. Native and conversation authoring must expose establishing, backlog, unknown/gap, pressure and blocked causes honestly. Folder/background/resource lifecycle and dataset-query adapters remain separate open work.

## Three review passes

1. Meaning: accepted automatic work retains ancestry; independent evidence stays independent; exact versions and logical automation identities remain distinct. Human attribution, origin text, saved permission history and a provenance graph cannot establish present authority or minimal causation.
2. Recovery and integrity: saved bindings must agree with invocation coordinates; read-only inspection survives inert reconstruction. Corruption and cycles refuse. Shared parents and two relation types must not be mistaken for a cycle. Schema 24 strengthens the existing workflow source identity with a unique index. There is no new table or second ledger. Refuse preserved older development files without migration; recreate selected synthetic fixtures only.
3. Scale and adversity: real 1,024/1,025-node and 4,096/4,097-edge boundaries, longest paths with shortcuts, 128/129-depth boundaries, forged IDs, missing bindings, oversize invocation data, cancellation/locks and no mutation. The condition publication guard must also check cancellation immediately before COMMIT, including cancellation delivered after captured rows have been prepared; a refusal must preserve all previous derived state and the token must remain retryable.

## Acceptance

Require registered scheduled action output followed by synthetic human-attributed acceptance, manual derived work, independent human input, shared DAG parents, duplicate roots, forged and damaged bindings, cycle detection, exact limits, already-cancelled requests and read-only reconstruction. Add installed native CLI checks for those public surfaces, nearby automation and condition regression checks, strict changed-Swift lint and native app/CLI package/resource/refusal/signature proof. The schema-24 source-identity constraint requires a fresh full core run and supported-file/refused-old-file preservation checks. Reuse unchanged model, prompt, engine and actual-model evidence with its original limits. Retain failed iterations and original source scopes. Update the self-contained log, validate db.md with zero warnings, check links/diff, commit/push and dispatch exact CI.

## Primary references

[SQLite transactions](https://www.sqlite.org/lang_transaction.html) documents stable read snapshots while a read transaction is active. The inspector uses that existing boundary; it does not create a retained causal ledger. [SQLite graph queries and recursive CTEs](https://www.sqlite.org/lang_with.html) describes duplicate suppression and explicit limits for graph traversal. We use bounded indexed parent reads and a separate topological pass to distinguish shared parents from cycles and measure the longest path. Exact bounds, provenance checks and dispatch semantics above are application decisions, not SQLite guarantees.

## Implemented ancestry inspection, October 29

Schema 24 now makes workflow_runs.source_id unique and indexed. The read-only core API and explicit automation-ancestry CLI traverse exact derives-from, supersedes and definition-input edges, validate each visited version against its authoritative workflow source binding, and expose exact historical automatic run/definition/logical/occurrence coordinates. Erased invocation metadata or a changed kind cannot make a registered workflow appear independent. Human-attributed acceptance and a later manual derivation preserve the original automatic ancestry. Independent evidence and untrusted origin text do not invent a run.

Traversal returns the complete retained graph within explicit bounds or refuses. Shared DAG parents and parallel relation types remain valid; cycles, missing/inconsistent bindings, missing supersession, unknown relation types, unsupported metadata and excess graph limits refuse without a partial independent result. Its graph includes control/configuration provenance and explicitly labels minimalCausalSlice=false and dispatchEligibility=not-evaluated. Lineage depth is not causal cascade depth. This slice adds no dispatch, permission, model tool, prompt/grammar change or second ledger.

Final frozen V3 passes 434 full core groups with zero failures and 18 focused ancestry groups. Those include a real registered scheduled receiving action and synthetic human-attributed acceptance, manual derived inputs, read-only inert reconstruction, forged/damaged/erased source bindings, unique indexed lookup, shared DAG/cycle cases, real 1,024/1,025-item and 4,096/4,097-edge boundaries, 128/129-depth shortcuts, oversize metadata, already-cancelled requests and real exclusive SQLite read-lock cancellation. The condition publication guard now checks cancellation after the qualification barrier and immediately before COMMIT; its test proves derived-state/cursor/receipt rollback and same-token retry.

Final installed native checks pass 22 ancestry, 94 condition and 76 event-feed calls against one CLI. Condition and feed each include six independent writers and two actual SIGKILL publication boundaries. Native owner/registry 18 groups, synthetic ProductAI lifecycle, strict Swift lint on six changed files, final native app/CLI build, installed resources with build-tree reads denied, 1,888 kernels per executable, 10 missing-resource refusals, altered-resource refusal, missing-model guidance/workbook preservation and ad-hoc signature pass. All 388 frozen Swift files and all 143 preceding artifacts remain unchanged. The new installed script joins scripts/check.sh and both packaged CI paths. Schema-23 fixture bytes are preserved/refused without migration or user-file reset; only selected synthetic fixtures are recreated.

V1 retains six passes/seven failures: the inspector omitted the real definition-input relation, corruption fixtures bypassed required capture transactions and a retry fixture expected baseline completion after only one page. V2 repairs those assumptions and passes 16 focused groups plus nearby checks/native build. Adversarial code review then strengthens metadata-directed lookup into authoritative indexed source lookup in V3; no V2 exploit experiment is claimed. The first receipt inventory omitted two nested search-scale artifacts; original frozen hashes restored complete verification before publishing the new receipt. No failed qualification is erased.

Evidence: [automatic ancestry receipt](../../../integration/evidence/2026-10-29-automatic-ancestry.json.gz), 90327 bytes, SHA-256 16b57e1a29edc7f032ba999b57739fb4d3c63f74180b93da99b175fa215e6bd0. Its captured previous 6fb5eff CI remains in progress; earlier 26c4bfe and 8634c6c runs are successful. This source needs its own exact dispatched CI. Final db.md/link/diff gates are recorded after the immutable receipt.

No actual selected-model inference, new throughput/hardware proof, production engine adoption or fresh visible/OS lifecycle qualification. The native app inventory still reports locked. Exact triggering input capture across pages/clocks/unknown intervals and persisted self-loop/cross-automation/root/depth/fan-out admission remain next, followed by atomic trigger/workflow binding with physical-file grants, native/conversation authoring and dataset-query adapters. This inspector is a completed foundation, not condition execution, E4, the app or a production release.

## Durable admission follows this inspector

[[records/specs/automation-causality]] adds schema25 persisted calendar roots and trusted inherited run/root/parent admission. Its automatic depth and charges are distinct from this inspector's broad lineage depth/control graph. Final22 installed ancestry calls remain passing. Existing missing-binding corruption fixtures now remove dependent admission rows before targeting the inspector; otherwise foreign-key integrity correctly refuses earlier. Exact trigger-cause discovery remains required and must not treat this graph as a minimal business cause set.
