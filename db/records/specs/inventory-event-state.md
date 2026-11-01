---
type: spec
id: 01m63qzvdy3wsnm72v7xvtezs7
created: 2026-10-29T11:51:10.526544+00:00
updated: 2026-11-01T08:40:00.000000+00:00
summary: 'Reviewed historical inventory adapter: exact committed cutoff and explicit effective time, retained basis and settled effects, bounded read-only reconciliation, no condition execution.'
title: Inventory state at a retained business batch
status: implemented
---
# Inventory state at a retained business batch

Reviewed next condition foundation over [[records/specs/business-events]]. Provide a read-only exact historical inventory adapter as a baseline/reconciliation oracle, not a per-poll history rescan or condition executor. Persistent consumers, incremental state, occurrence decisions and causal/backpressure controls remain required under [[records/specs/condition-transitions]]. No new schema or authority follows from this adapter.

## Two independent coordinates

Require an exact retained semantic batch ID plus an explicit effective-through business date/time. The batch cutoff determines what the workbook had committed; effective-through determines which of those known facts apply to the requested business period. Do not substitute today's current head or imply physical current stock from future-dated accepted entries. A future effective-through value is an explicit ledger projection. A later live rule must select its clock policy and account for effective-date transitions even without a new business mutation.

## Exact basis and settled effects

Read one consistent bounded snapshot. Resolve the latest captured inventory-basis event at or before the cutoff. Use its retained before/after payload and exact Source ID, not today's bases table. If the retained basis is absent, removed or later than effective-through, report unknown with null quantity and a reason, never invent zero.

Select the final settled movement entry for each logical identity at that cutoff. Later settled versions after the cutoff cannot hide earlier accepted state. Drafts never replace settled state. A rejection removes that logical effect; an estimate, plan, commitment or other scenario never contributes to actual stock. Use exact immutable accepted item IDs and item-indexed inventory effects with the exact requested subject, strictly after the basis and through the explicit date. A movement label or subject hint alone is not an effect. Corrections/reversals remain the same logical occurrence; independent occurrences remain distinct.

Return exact batch/workbook identity, both time coordinates, basis Source and retained basis event, contribution event/item/logical/occurrence IDs, effective times and decimal quantities. Add with checked Decimal arithmetic. Any unsupported precision, malformed retained data, missing event or incomplete bound refuses visibly rather than returning an apparently complete quantity.

## Bounds and intended use

Use the existing cancellation-aware three-second feed read transaction, short SQLite busy wait, indexed scope/position and logical-version lookups, an explicit contribution bound and an 8 MiB result budget. The first adapter accepts at most 10,000 contributing effects; exceeding it refuses with an explicit limit error. No unchecked full committed-payload scan or model call. This oracle may inspect retained subject history within its query deadline; it is not the scalable incremental consumer. Later consumers must persist working state and only process bounded successors, using the oracle for establishment/reconciliation when within bounds.

## Three review passes

1. Meaning: knowledge cutoff versus effective time, absent basis versus zero, accepted actual versus other meanings, drafts, withdrawals, corrections and independent occurrences. An explicit future as-of is not physical-now proof.
2. Historical integrity: immutable exact IDs, latest settled at the selected cutoff, captured basis after later edits/removal, atomic commit observation, inert reconstruction and zero mutation/permission from reading.
3. Scale and adversity: subject/time/position indexes, no latest-head shortcut, exact Decimal cancellation/overflow, bounded output/contributions/time, cancellation under locks and visible refusal rather than truncation. Do not install an O(history) read loop as a live scheduler.

## Acceptance

Require real workbook checks for past cutoffs after later corrections/withdrawals, drafts, multiple versions in one commit, unrelated subjects and fake movement labels, accepted estimates, missing/removed/future basis, explicit future effective dates, exact decimals and bounded refusal. Compare the current-tail result to the existing deterministic balance contract where their explicit scopes agree. Retain exact lineage, demonstrate read-only behavior and inert reconstruction, run installed native CLI cases and appropriate native build/resource/refusal/signature, strict Swift lint, db.md/link/diff checks and exact CI. Keep all failed attempts. This scope does not qualify persistent condition delivery, causality controls, visible OS or release readiness.

## Implemented historical adapter, October 29

The read-only `Workbook.inventoryAtBusinessBatch(_:subject:effectiveThrough:cancellation:)` and `inventory-at-batch WORKBOOK BATCH_ID SUBJECT EFFECTIVE_THROUGH` now implement the bounded historical adapter. The exact retained batch determines committed knowledge; the mandatory explicit date determines effective eligibility. Later corrections, withdrawals or current heads cannot rewrite an earlier cutoff. Retained basis images survive later edits/removal. Missing/removed/not-yet-effective bases produce unknown with null quantity, never zero. Only the cutoff's settled accepted actual inventory effects contribute, strictly after the basis and through the date. A movement label, estimate, other scenario or unrelated subject cannot establish an effect. Exact event/batch/item/logical/occurrence IDs remain inspectable.

Addition requires a no-error Decimal sum; precision loss refuses with `inventory_history_precision`, without a rounded balance. Reads share the cancellation-aware feed snapshot, short busy wait, three-second query and 8 MiB output budget. At most 10,000 contributing effects. Subject events lead fixed exact-item/item-indexed-effect joins; later settled detection uses the logical/version-position index across scopes. This is an establishment/reconciliation oracle, not an O(history) poll loop. Persistent incremental consumers remain required.

Final V4 passes 11 focused groups, a real 10,000-effect success/10,001-effect explicit refusal, 14 nearby feed groups and 37 installed native CLI calls. The installed checks cover past cutoffs after later changes, explicit future dates/unknown basis, read-only history and inert reconstruction with identical inputs. Fresh native app/CLI build, installed resource reads with build-tree access denied, 10 missing-resource and altered-resource refusals, missing-model guidance/workbook preservation, ad-hoc signature and strict five-file Swift lint pass. The new ordinary groups, separate scale group and installed script join local/hosted checks. The prior 386-group full-core proof retains its original source scope under focused verification; no new full-suite or model/hardware/visible OS proof is claimed for this additive read adapter.

Retained failures: V2's real 10,000-effect case reached the query deadline. V3 profiling measured the historical SELECT consuming that budget. V4 forces indexed subject events before exact item/effect joins and passes both boundary cases within the same budget. The fixture's debug SQL profiles are evidence for this query correction, not general application, hardware or inference speed. No schema/canonical family, engine/model/prompt or authority change. Hosted 60d4ee6 CI passed; feed 8634c6c is still running at this receipt. The adapter source needs its own exact CI.

Evidence: [historical inventory receipt](../../../integration/evidence/2026-10-29-inventory-event-state.json.gz), 38331 bytes, SHA-256 c4f9cc2540c91ed557fa1e4027cae9f3a6ebd6572c07a64eaab223ad36de92aa. All 141 preceding artifacts remain byte-identical.

Next remains persistent condition baselines/cursors and incremental working state, exact atomic occurrence decisions/outbox, durable causal ancestry and restart-safe self-loop/cascade/fan-out/backpressure controls, then native/conversational trigger authoring with current physical-file grants. A live effective-time clock policy is not implied by this explicit-date oracle. Dataset-query historical adapters, complete background/resource lifecycle, E5/E6, full E3 and E0/E1/E2/Excel journeys, visible voice/accessibility/appearance/media, physical performance/engine adoption and production notarized distribution remain open. The UI tool's last fresh inventory reports a locked Mac; no bypass or additional unlock request was made. App, goal and release are unfinished.

## Consumer cross-check at schema 23

[[records/specs/inventory-condition-consumers]] now uses this exact historical adapter as a reconciliation oracle in correction, basis and atomic-new-basis tests while retaining bounded incremental current effects between changes. It processes explicit future eligibility without rescanning full history each poll. Final 416 full core and 37 installed historical calls pass with the schema 23 native product. The original10,000-effect historical read bound remains distinct from the consumer's10,000-current-effect bound. No causal dispatch or new live/background authority is implied.
