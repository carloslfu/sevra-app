---
type: spec
id: 01m63sd9zxhrxzv360z74w3pyn
created: 2026-10-29T12:15:59.997610+00:00
updated: 2026-10-29T13:12:33.343711+00:00
summary: Schema 23 inventory conditions with saved baselines, pages and clocks, exact observations, inert candidates and backpressure; automatic dispatch remains unqualified.
title: Durable inventory condition consumers
status: implemented
---
# Durable inventory condition consumers

This implements bounded incremental condition tracking over [[records/specs/business-events]], checked against [[records/specs/inventory-event-state]]. It retains observations and candidate requests without executing workflows or granting authority. Complete E4 still requires causality-aware dispatch, physical-file permission integration and native/conversational authoring.

## Baseline, knowledge and time

Creation saves an exact rule, inventory subject, explicit normalized effective-through time, current global feed tail and original intent Source. Replay through that captured tail establishes a baseline; it does not fire past transitions. Already true is a baseline. Later batches remain queued, including those committed while establishment is in progress. An empty workbook establishes unknown rather than zero. First certain information after unknown establishes the first certain baseline without firing.

Each step supplies an explicit effective-through horizon. Horizons and completed effective time never move backwards. This is a deterministic ledger clock, not a promise that wall-clock delivery ran while the app was closed. Before consuming the next known business batch, advance retained time through the earlier of its recorded time and the requested horizon, clamped to completed time. Due effects and an opening basis becoming effective are observed at each distinct effective timestamp, even without another business mutation. Then observe the complete atomic business batch at that time. At equal timestamps clock eligibility precedes committed knowledge; this is a declared ordering convention, not proof of physical ordering. A retrospective correction changes present knowledge without rewriting earlier observations. A future explicit horizon is a ledger projection, never physical stock proof.

## Incremental working state

Consume the global indexed feed, since a generic cross-scope correction can withdraw a previous inventory effect. Resolve exact immutable item/effect IDs. Retain only current accepted actual effects for this subject, including future ones, keyed by logical identity with unique occurrence identity. Drafts, estimates, other scenarios and labels without exact effects do not contribute. Retain the latest captured basis, never today's mutable basis mapping.

One step handles at most 100 event or projection rows. Save an unfinished batch/ordinal or clock group and working quantity in the same canonical captured transaction. Completed cursor and last complete observation remain unchanged until the entire batch/group is retained. No evaluation at page boundaries. Ordinary corrections update the working sum by exact removal/addition; basis changes and first establishment rebuild from the bounded current projection with saved keyset position, not full committed history. Queries use exact indices and a three-second cancellation budget. Precision loss refuses and rolls back the page instead of rounding. Limit the retained projection to 10,000 current effects and encoded responses to 8 MiB; refuse explicitly rather than truncate.

## Observations and candidates

Persist exact knowledge batch, effective time, quantity or unknown reason, rule, basis and previous certain observation. Preserve last certain truth across unknown intervals and label any later false-to-true transition across a gap. A true baseline or repeated true value does not fire. Stable observation and candidate identities derive from consumer identity and exact knowledge/time coordinates. A candidate is an inert durable outbox row, not a business occurrence, permission or executed workflow. Observation, candidate and completed cursor publish atomically.

Retain up to 100 pending candidates per consumer. Backpressure stops before final cursor publication and visibly preserves the unfinished decision. Never coalesce distinct crossings. Explicit dismissal with a reason retains history and frees capacity; dismissal grants no authority or business effect. There is no automatic dispatch in this slice, so no claim of causal loop protection. Later dispatch must preserve origin through automatic proposals and human acceptance, enforce restart-safe depth/fan-out/root budgets and keep existing exact physical grants and live fences.

## Capture, recovery and interfaces

Schema 23 declares consumer, current-effect, observation and candidate families in the existing committed-change capture. No parallel history, migration or legacy adapter. Reconstruction applies saved rows inertly and never interprets a condition, activates a device grant or executes work. Reads and idle status inspection do not advance state. Mutation tokens bind exact requests and return the original receipt on retries. A resumed explicit step continues the saved page. Saving/copying/importing intent cannot install timers or execute workflows.

Expose shared core plus standalone CLI creation, bounded step, status, observation paging and explicit candidate dismissal. Do not expose ordinary model tools or automatic scheduling until the remaining authority/causality contract is implemented. Native rendering must show establishing/backlog/partial/backpressure separately from the last complete observation.

## Three review passes

1. Business meaning: exact accepted actual effects, independent occurrences, correction across scopes, atomic groups, unknown basis, baseline/no historical fire, two time coordinates, future eligibility and retrospective knowledge.
2. Recovery and authority: page rollback, stable retry, restart mid-batch/rebuild, complete cursor versus working state, atomic observation/outbox, queue pressure without loss, exact lineage, inert copies/reconstruction and no authority from saved intent.
3. Scale and adversity: indexed keyset pages, bounded current projection rather than history rescans, exact precision, cancellation/locks, huge atomic batches, simultaneous effective dates, monotonic horizons, duplicate delivery, malformed input and immutable prior receipts. Full background, automatic dispatch and UI release claims remain separately gated.

## Acceptance

Require real workbook checks for baseline/unknown/gaps, distinct recrossings, multiple batches between polls, large atomic batches with restart, exact corrections including cross-scope removal, basis replacement/removal/future dates, future clock-only transitions, equal-time groups, backward horizon refusal, comparison with the independent historical oracle, exact precision rollback, candidate capacity/dismissal/retry, concurrent independent workers and inert reconstruction. Add installed CLI and actual process-death proof at publication boundaries. Run full core for the schema change, nearby condition/feed/automation checks, native package/resource/refusal/signature checks, strict changed-Swift lint and zero-warning db.md/link/diff gates; commit/push and dispatch exact CI. Preserve failures and do not equate this consumer with completed event automation or a production app.

## Primary references and ordering repair

[SQLite SELECT and ORDER BY](https://www.sqlite.org/lang_select.html#the_order_by_clause) specifies that an output alias can determine an ORDER BY expression. A displayed CAST(position AS TEXT) alias must not replace ordering by the stored integer. The capacity fixture exposed that defect in the first consumer and existing global feed/tail reads; the corrected queries explicitly order by b.position. The new 23-batch pagination/tail regression and 101-crossing queue case exercise this boundary. This is an observed local defect and repair, not a claim that earlier scoped evidence covered it.

[SQLite transactions](https://www.sqlite.org/lang_transaction.html) documents a single simultaneous writer and commit/rollback behavior. Our completed-cursor/observation/candidate transaction and resumable working pages are application-level contracts over that mechanism. The ledger clock ordering, baseline semantics, candidate capacity and 10,000-current-effect qualification bound are our explicit implementation decisions. No SQLite guarantee implies automatic event coverage or execution authority.

## Implemented consumer qualification, October 29

Schema 23 now retains explicit inventory-condition intent, incremental current effects, paged working state, exact observations and inert candidate requests through the existing committed-change family. Creation captures the current business tail and explicit effective time; replay establishes a baseline without firing past crossings. Later accepted actual changes are processed in integer batch order, including generic cross-scope withdrawal/correction. Future facts and bases become eligible through an explicit monotonic ledger clock, with each distinct effective timestamp retained. A requested future horizon remains a ledger projection, not physical current-stock proof.

One step processes at most 100 rows. Unfinished business batches, clock groups and basis rebuilds save keyset positions without exposing partial sums as complete observations or advancing the completed batch cursor. Corrections update exact current effects; establishment and basis replacement rebuild only the bounded current projection. An atomic basis replacement is detected before effect deltas, avoiding arithmetic against its superseded opening quantity. Last certain truth survives unknown gaps. Baseline/already true/unchanged true does not fire; distinct false-to-true recrossings produce distinct stable candidate identities. Unsupported exact Decimal arithmetic refuses instead of rounding.

Observation, candidate and completed cursor publish atomically. At 100 pending candidates, backpressure preserves the unfinished decision until an explicit reasoned dismissal frees capacity. No calendar coalescing erases crossings. Dismissal retains a control Source linked to the original intent. CLI attribution is programmatic; native human gestures may supply human attribution separately. Intent/dismissal are technical controls, excluded from business evidence. Reconstruction preserves complete and partial state inertly, with no device grant, timer, workflow, acceptance or model acquisition.

Final frozen V7 passes 416 full core groups with zero failures, 18 focused consumer groups and a real 10,000-current-effect success/10,001-effect explicit refusal. Final native installed checks pass 94 condition calls, including six independent CLI writers and two actual SIGKILL boundaries before/after commit. Nearby 76 feed calls include six writers and two separate process-death boundaries; 37 historical-inventory calls pass. Native registry/controller 18 groups, synthetic ProductAI lifecycle, strict Swift lint on 13 files, final native app/CLI build, build-tree-denied resources with 1,888 kernels for each executable, 10 missing-resource refusals, altered-resource refusal, missing-model guidance/workbook preservation and ad-hoc signature pass. No actual-model, new hardware/performance or visible OS qualification.

Retained iterations: V1/V2 capacity failure and V3 diagnostics exposed text-alias ordering of numeric batch positions in both this consumer and the existing global feed/tail queries. Qualified ORDER BY b.position now passes 23-batch pagination/tail and 101-crossing capacity regressions. Earlier feed evidence did not cover that boundary. V5's installed script initially failed on Python 3.9's eager union annotation; future annotations repair it. The strict-lint closure finding is repaired with a named publication guard. V6 isolates technical Sources and fixes CLI attribution; V7 adds atomic-basis precision protection. No failed result or prior artifact is rewritten.

Evidence: [durable inventory consumer receipt](../../../integration/evidence/2026-10-29-inventory-condition-consumers.json.gz), 102821 bytes, SHA-256 112266cb15e0e415adab344dcddf90bee6ae5378901f1b7c5267718e3e088e3c. All 142 preceding artifacts remain byte-identical.

The previous 26c4bfe hosted run remains in progress in this immutable receipt; 8634c6c CI passed. This source requires its own exact dispatched CI after commit. Final documentation/link/diff gates are recorded separately after the receipt. The Mac inventory still reports locked, so no fresh visible Activity/answers/voice/accessibility/appearance/media or actual closed-window/background proof exists.

This completes the persistent inventory consumer slice, not condition execution, E4 or the app. Next: retained causal ancestry through automatic proposals and human acceptance, restart-safe self-loop/cascade/depth/fan-out/root admission, trigger-to-workflow binding with current physical-file grants, native/conversational authoring and dataset-query condition adapters. Full background/resource lifecycle, E5/E6, E3 receiving/failure/abuse/richer graphs, contextual/Excel continuity and complete E0/E1/E2 journeys, physical hardware/performance/production engine adoption and signing/notarization/distribution remain required. Goal and release remain unfinished.

## Authoritative ancestry and publication cancellation

The later [[records/specs/automatic-ancestry]] checkpoint advances the development schema to 24 solely to make existing workflow invocation Source identity unique/indexed. Consumer families and semantics remain unchanged. The condition publication guard now checks cancellation immediately before COMMIT, after the qualification barrier; a focused test proves complete derived-state/cursor/receipt rollback and same-token retry. Final 434 full core groups and 94 installed condition calls/two actual SIGKILL boundaries pass. The new inspector retains broad derivation ancestry, including synthetic acceptance, but is not a minimal trigger cause set or dispatch decision. Exact cause capture and persisted causal admission remain required.
