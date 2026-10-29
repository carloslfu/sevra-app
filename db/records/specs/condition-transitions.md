---
type: spec
id: 01m63mskyw17ghqe41k3rhh631
created: 2026-10-29T10:55:20.540673+00:00
updated: 2026-10-29T12:04:34.669040+00:00
summary: Reviewed inert numeric transition preview and remaining committed-business-event/cursor/causality integration; no execution or authority from supplied observations.
title: Condition transitions
status: reviewed
---
# Condition transitions

Status: reviewed staged E4 contract. The first slice is a pure deterministic preview of supplied numeric observations. It creates no workbook state, Source, definition, occurrence, permission or workflow. Real committed-event integration and native authoring remain required. See [[records/specs/native-app-engine]], [[records/specs/native-automation-owner]] and [[records/operations/implementation]].

## User behavior

“When stock falls below 10” means one false-to-true transition. Remaining low does not repeat it. A complete known false observation resets it; a later true observation may fire again. A correction is a new committed business observation, not a rewrite of the prior notification. Enabling establishes the current baseline without inventing an earlier crossing. Already-true baseline is shown clearly; a separately requested Run once remains available.

Unknown, missing, stale or partial values are not false and cannot reset the condition. Preserve the last certain truth across an unknown interval. If the next certain value changes false to true, label it an observed transition across a coverage gap, without claiming the exact crossing time or that every intermediate change was observed. True, unknown, true produces no repeat. A first certain value after only unknown inputs establishes baseline and does not fire. These are observed-state semantics, not proof of historical completeness.

## First pure implementation

NativeConditionRule accepts exactly policy=native-condition-v1, a bounded nonempty scope identity, one of <, <=, >, >=, =, <> and an unambiguous decimal threshold. Use the same 38-significant-digit deterministic Decimal contract as existing calculations, never binary floating point or executable expressions. Canonicalize equivalent decimal spellings losslessly for stable rule identity.

Preview accepts at most 100 supplied observations and 64 KiB of encoded input. Each has a bounded nonempty opaque id and either a decimal string value, or null plus a bounded nonempty reason. Input order is declared by the caller. This helper cannot prove that IDs are real commits or that the supplied list is complete. Label output fixture-observations, businessEvidence=false, execution=inert and enabled=false. No workbook argument, model, implicit file scan or native timer activation.

The same observation ID with equivalent normalized content is duplicate delivery and cannot rewind/reset the current state. Reusing an ID with different content refuses the whole preview. Preserve separate IDs even when their values match. An occurrence candidate hashes the normalized rule/scope and causing observation ID; it is a preview identity, not a domain fulfillment ID. Changed rule/scope changes identity. Return all dispositions, explicit gap flags, final certain state and bounded transition candidates. Cancellation refuses before and during evaluation. No cooldown in this slice; distinct re-crossings are not dropped.

The standalone CLI condition-preview accepts rule JSON and observation-array JSON, each inline or through @FILE. Reads are bounded, regular-file-only and no-follow/nonblocking so a substituted FIFO or symlink cannot stall input. Invalid fields, numeric JSON values, precision/range failures, malformed unknown reasons, changed-ID content and excessive input refuse. No ordinary agent tool is added before real evidence/intent qualification.

## Committed-event integration that remains required

A generic workbook revision is not a business event. Integrate through the existing captured change ledger with an indexed semantic business-event outbox and durable per-automation cursors. Accepted actual changes, proposals, estimates, plans and execution metadata stay distinct. Drafts or run-status churn cannot trigger actual-stock rules. Preserve every distinct accepted event, its exact versions and causal identity; duplicate delivery is not a new business occurrence. Outbox publication must be atomic with its business mutation, not a later best-effort watcher.

A read transaction is internally consistent but cannot recreate every earlier condition between polls. Do not evaluate the latest table once and claim that intermediate false/true transitions were processed. Retain/reconstruct exact event-time state or qualify explicit observed-only coverage. Each occurrence records trigger context and actual workflow read revision. The next implementation review must choose exact feed/snapshot storage and supported condition query scope before changing canonical DDL. Reuse shared capture/apply and inert reconstruction, with no second history ledger or development compatibility adapter.

Consume bounded ordered pages. Atomically publish decisions/occurrences/outbox and advance the exact cursor; a failure cannot skip an unretained event. Under queue pressure, stop and show backlog instead of silently discarding business occurrences. Keep one active run; preserve event successors rather than applying calendar report coalescing indiscriminately. Pause/copy/reconstruction retain intent/history but cannot restore device authority. Existing exact local grants and live publication fences remain mandatory.

Track causal origin across workflow outputs and later review acceptance. Block self-output and bound cross-automation depth, fan-out and total admitted work with persisted evidence. Do not clear ancestry merely because a human accepted an automatically generated proposal. A new independent human business occurrence stays distinct. Exact thresholds/escape UX need focused qualification before dispatch; a process-local counter cannot prove restart-safe loop prevention. Optional cooldown must preserve distinct crossings and state its delayed/coalesced output policy instead of erasing events. Folder intake/helper/resource work remains E5.

## Three review passes

1. Meaning and UX: known false/true/unknown, baseline versus crossing, unchanged low values, corrections and distinct occurrences. Unknown never resets. Gap wording does not overstate evidence. The first preview is expressly inert.
2. Recovery and authority: normalized identity, duplicate versus changed content, bounded input, cancellation, missing/partial data, exact cursor/outbox transactions, copies/reconstruction and no authority from history. Calendar coalescing cannot drop business events.
3. Scale and adversarial behavior: exact Decimal boundaries, extreme precision, encoded-size limits, FIFO/symlink reads, duplicate storms, clock-independent observation order, omitted intermediate states, automatic metadata loops and cross-automation causality. Real feed/hardware/native interaction requires separate evidence.

## Acceptance

Pure checks must cover all six comparisons at exact decimal boundaries, repeated low state, false/unknown/true and true/unknown/true, initial true/unknown baseline, independent recrossings, same-ID duplicate delivery versus changed content, scope/rule occurrence identity, malformed/oversized input, cancellation and exhaustive short truth-state trajectories. Installed CLI tests cover inline and file inputs, malformed arguments, no-follow regular-file and size refusal, stable repeated output and explicit inert labeling. Run nearby calendar/automation regressions, native app/CLI build, strict changed-Swift lint, installed resource/refusal/signature gates, links and complete zero-warning db.md validation. Preserve failed attempts and source hashes. The pure preview does not qualify business-event delivery, persistent cursors, native controls, background lifecycle, real-model behavior or release readiness.

## Primary references

[SQLite isolation](https://www.sqlite.org/isolation.html) explains consistent connection snapshots. That supports a bounded current read, not application-level historical event coverage. [Transaction control](https://www.sqlite.org/lang_transaction.html) explains commit/rollback boundaries; the proposed business outbox and cursor must join the owning transaction. [WAL](https://www.sqlite.org/wal.html) is database recovery/concurrency machinery, not the application's retained business history. These references inform the design; the proposed semantic feed is our implementation decision.

## Pure preview qualification and registry repair, October 29

The pure NativeConditionRule and standalone condition-preview CLI now implement the supplied-observation slice. Six exact decimal comparisons, normalized rule/observation identity, baseline, no repeat while true, known-false reset, unknown gaps, duplicate delivery and changed-content refusal are implemented. Unknown never resets; a crossing across a gap is explicitly labeled. The preview creates no workbook data or permission and labels fixture-observations, businessEvidence=false, enabled=false and execution=inert. CLI file inputs are bounded, no-follow, nonblocking and regular-file-only.

The new 13 focused groups pass, including all 243 five-observation truth trajectories, large exact decimals beyond binary floating-point precision, all six equality boundaries, independent recrossings, identity normalization, malformed/oversized input and already-cancelled calls. The implementation checks cancellation before and within validation/evaluation; no separate real-time mid-loop cancellation experiment is claimed. Nearby 13 calendar groups and 16 execution groups pass. The installed native CLI passes 31 independent cases covering inline/file inputs, stable repeated output, malformed arguments, symlink/FIFO/directory/missing/non-UTF-8/size refusals and explicit inert labels. Its hash matches the final native CLI, so those calls are not repeated after an app-only registry repair. New tests join the ordinary core suite, scripts/check.sh and both packaged hosted CI paths.

Hosted CI for fab2a83 failed 16/17 native owner groups: one independent writer reported an unsafe registry directory. The prior local run had passed. Foundation directory attributes may be applied after creation, leaving a creation window; the repair creates the parent separately, then uses POSIX mkdir(0700) for atomic private leaf creation. Existing unsafe directories still refuse without permission repair. The older V4 child failure had no diagnostics, so this does not retroactively establish its cause. Final 18 owner groups pass, including a new unsafe-directory preservation counterexample. Five additional fresh concurrent starts pass 30 independent registration workers. The existing two real registry SIGKILL boundaries remain in the 18-group run.

Final V2 native app/CLI build, installed build-tree-denied resource reads, 10 missing-resource refusals, altered-resource refusal, ad-hoc signature and strict seven-file Swift lint pass. All frozen Swift hashes remain unchanged. This is focused proof under the adopted verification policy; the previous full 359-group core/model/crash evidence retains its original scope. No schema bump, canonical table, second ledger, model/prompt/grammar/budget change or actual-model inference. Failed CI and both source snapshots remain retained. The corrective source still needs its own hosted run.

Evidence: [condition and registry repair receipt](../../../integration/evidence/2026-10-29-condition-transitions-registry-repair.json.gz), 61244 bytes, SHA-256 1559bf286dec9681b20ac23d78c4c7e5902fbb1d884eb6933fa74f78634b05f6. All 139 preceding artifacts remain byte-identical.

A fresh native inventory still reports no apps and a locked Mac. Visible controls, keyboard/VoiceOver/dictation/light/dark/narrow/media and actual OS lifecycle remain unverified. Committed business-event outbox/cursor, exact event-time state, real condition delivery, loop/backpressure controls and native/conversational trigger authoring remain next; the pure preview is not a condition scheduler. Full E3/E4/E5/E6, contextual/Excel continuity, complete E0/E1/E2 journeys, hardware/performance, production engine adoption and signing/notarization/distribution remain open. App, release and goal are unfinished.

## Committed feed foundation, October 29

[[records/specs/business-events]] now implements the schema22 semantic outbox and bounded inert delivery over the existing captured ledger. It has386 full core groups with zero failures,14 focused groups and 76 installed CLI calls, including six concurrent publishers and two actual SIGKILL boundaries. Native/nearby regression proof and exact source scope are recorded there. This replaces the need to poll only latest state; it does not yet implement a condition consumer. Persistent baselines/cursors/working state, exact historical inventory/dataset adapters, atomic occurrences/outbox and causal loop/fan-out/backpressure bounds remain required before event execution. Dataset-only feed scopes cover membership/schema rather than claiming all row-value changes. Read-only delivery creates no grant.

## Exact inventory reconciliation foundation

[[records/specs/inventory-event-state]] implements the first historical adapter: exact committed knowledge batch plus explicit effective-through time, retained basis and settled accepted actual effects, without a current-head shortcut. Final 11 focused groups, real 10,000-effect success/10,001-effect refusal, 14 feed regressions and 37 installed native CLI calls plus native packaging pass. It is read-only and creates no consumer state, occurrence or permission. Do not install it as a full-history scan on every poll. Persistent incremental working state/cursors, live effective-time policy, atomic decisions and persisted causality/backpressure remain required before dispatch. Dataset row-value coverage remains separately explicit.
