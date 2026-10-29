---
type: spec
id: 01m648rwd9na7n0vz8pn1ae2pr
created: 2026-10-29T16:44:27.945228+00:00
updated: 2026-10-29T16:44:27.945228+00:00
summary: 'Reviewed next E4 integration: owned condition consumers, exact live grants, atomic candidate/run/admission binding, backlog semantics and native dispatch acceptance. Not implemented.'
title: Atomic inventory-condition dispatch
status: reviewed
---
# Atomic inventory-condition dispatch

This is the next reviewed E4 implementation contract, not implementation proof. It joins [[records/specs/inventory-condition-consumers]], [[records/specs/business-provenance]], [[records/specs/automation-causality]] and [[records/specs/native-automation-owner]]. Schema29 already qualifies exact input/cause identity and the trusted shared admission primitive. A test bridge through calendar bindings does not qualify actual condition execution. Keep the existing calendar behavior intact while adding a real, distinct condition path. Update canonical development schemas without legacy adapters.

## User meaning and scope

“When stock falls below10, prepare a receiving/reorder report” saves a rule and workflow, then requires explicit Enable on this Mac for the exact version and any local-AI use. Saving, importing, previewing, opening and reconstructing never enable it. Voice/text can express the intent; native controls expose status, review and exact choices. No JSON editor is required in the product flow. Automatic work creates drafts; business acceptance stays separate.

Initial enabling establishes a known current baseline. Already-true stock is shown as already below the threshold, with separate manual Run once available. It does not invent a prior crossing. False-to-true transitions use the existing exact observation identity and retained coverage. Unknown is never false. Incomplete/unknown-gap/overflow cause coverage cannot dispatch just because the numeric result is known.

Pause retains candidates, cursors, runs, completed results and charges. Resuming the same rule retains its ordered queue and catches up through saved business history; it cannot silently discard or coalesce distinct crossings. Show the retained queue count and earliest observation when enabling/resuming. If the user says “only from now,” record that explicit decision, retain prior candidates as skipped/dismissed with reasons and establish a fresh current baseline. Do not repurpose ordinary Resume as an unexplained queue reset. An ambiguous request about a substantial old backlog can be clarified conversationally while all work remains saved. Editing workflow arguments or rule content does not silently expand an older grant.

A separately requested manual Run once is its own attributed operation. It does not enable future triggers, consume/dismiss a queued automatic candidate or erase prior automatic ancestry. Later automatic work derived from its results still follows actual input provenance.

## Definition and consumer ownership

Add an explicit inventory-condition automation policy alongside calendar-drafts-v1. Retain one exact workflow version, normalized typed arguments, exact inventory subject and normalized NativeConditionRule. The immutable definition describes intent; runtime consumer IDs, cursor progress, candidates and device grants are not authored as executable model JSON. Saving validates the supported rule/query scope and existing exact workflow dependency under ordinary definition capture.

Each automation logical identity owns its condition consumer. Several automations using the same subject/rule use separate consumers and share causal roots through their actual inputs. This preserves one candidate queue per owner without globally consuming another automation's transition. The consumer's immutable creating Source records owner logical identity, normalized subject/rule and exact definition control provenance. Runtime state continues to use the existing condition family and ledger. Standalone inert CLI consumers remain standalone and cannot acquire ownership through copied metadata.

An authorization binds the exact saved definition, consumer, activation generation, actor and allowAI decision. Reuse a consumer only when its owner, normalized rule and subject match the explicitly selected scope. Changing rule/scope or choosing “from now” establishes a new baseline consumer and preserves the previous one. History retains the exact old consumer through its authorization and run bindings. A different exact workflow version requires a new authorization even when the condition is unchanged. Device registration still binds both physical filesystem identities and the exact authorization Source, not UUID or portable intent alone.

## One atomic candidate-to-run transaction

The dispatcher accepts a live host-created execution session, not caller-supplied roots, parents, consumer IDs or model-created authority. Under the same bounded captured writer:

1. Recheck current device fence, exact definition/generation/authorization, consumer ownership and local-AI scope. Defer if one nonterminal automatic run already occupies this activation. Saved receipts never reissue a revoked capability.
2. Select the earliest pending candidate for that consumer by its observation's integer insertion order. Do not sort hash IDs as time. Validate its exact candidate/rule/transition/observation coordinates and retained inputs. Dismissed or already bound candidates cannot create another run.
3. Resolve the complete window through the qualified sealed business graph and original declarations. Derive parents and independent inputs internally. Block missing/unclassified/partial coverage and excess bounds; never accept a partial cause set or allow a later candidate to bypass the blocked head silently.
4. Plan shared admission and preserve logical self/cross-loop, depth, parent fan-out and root-total budgets. Record exact observation ID, knowledge batch, effective instant, input-set hash and current workflow-read commit coordinate. They explain why work starts; they do not claim the workflow reads a historical frozen database.
5. Insert the dispatch decision Source, workflow invocation/run/steps/outbox, unique candidate/run binding, automatic root/admission/parent/input relations and all charges. Mark the candidate dispatched with its exact decision Source and reserve the activation's active run. All of this publishes together, or none does.
6. Immediately before COMMIT, recheck cancellation and the live device/execution/AI fence. No model execution, external effect or business acceptance occurs inside this transaction. The existing fenced worker executes the queued run afterward.

Canonical run binding must distinguish exactly one calendar occurrence or condition candidate, with one unique run per trigger identity and one unique trigger per run. Do not manufacture calendar occurrences to represent condition events. Condition dispatch has no calendar coalescing or24-hour discard rule. Deferred backlog remains visible. Exact retry returns the same retained decision without another charge; another token also cannot consume the candidate twice. A failed budget/coverage check retains the pending candidate and records no partial run or charge.

Trigger observation and workflow input state are distinct. Later workflow steps retain their actual read/input versions through their existing receipts. UI/history must not claim a delayed workflow's current query is the trigger-time stock. Show the observed value/time and, when materially different, the current state. Business effects stay drafts pending review. Typed trigger-value bindings can be added only with separately validated parameter semantics; no arbitrary string interpolation or hidden snapshot promise.

## Driver, recovery and truthful status

The active-app native owner restores only its existing private physical-file grant. It advances bounded consumer pages, then admits at most one eligible candidate and runs through the existing resource owner. Interactive work keeps priority. Retain the conservative active-app/key-window/focus/pressure/termination gates until E5 qualifies broader lifecycle. No copied workbook, model response or idle timer creates a new grant.

Avoid idle writes. A bounded read-only probe identifies pending consumer work, due effective-time eligibility, queued candidates or an active run before stepping. Respect existing100-candidate backpressure; keep every distinct crossing rather than calendar-style coalescing. Needs review waits without spinning new Sources/claims. Round-robin work yields between bounded pages and targets.

Reopen after prepared-but-uncommitted publication retains the pending candidate and no run/charge. After committed publication, restore the one bound run and its charges without rebinding. Completed step results remain reusable; Stop, permission/focus loss and retry cannot duplicate business occurrences. Copies/archives/reconstruction retain history but stay inactive. These are local captured-writer guarantees, not shared quotas or coordination across independently edited replicas.

Product status uses plain language and exact evidence navigation. Examples: “Waiting for review,” “5 transitions waiting,” “This change has already started32 automatic workflows. Further automatic work needs review,” or “This change has incomplete history. Automatic work is paused for review.” A blocked head has inspect/dismiss/manual options with recorded intent. It is not silently marked complete or re-rooted. Technical IDs and limits belong in optional details.

## Three review passes

1. Meaning and UX: initial true versus crossing, unknown coverage, delayed events, changed current state, pause/resume versus explicitly “from now,” independent manual work and review. Separate saved intent from device permission and draft preparation from accepted business effects. Preserve every distinct transition and make aged backlog understandable.
2. Persistence and authority: exact owned consumer/generation, unique candidate/run binding, shared original roots across targets, exact invocation roles, atomic writer publication, both process-death boundaries, idempotency and live grant removal before COMMIT. No authority from history or copied identity; no calendar placeholders or another ledger.
3. Adversity and scale: queue ordering beyond9, competing dispatchers, blocked-head bypass attempts, missing/changed observations/declarations, huge or partial input windows, automatic-output loops with new human information, permission replacement, late worker callbacks, no idle write storm and bounded effective-time work. Reuse unchanged qualified graph/domain evidence rather than rerunning unrelated model jobs.

## Implementation and acceptance order

- First implement canonical condition definition/consumer ownership, live authorization and the real trigger/run binding with capture/verify/inert reconstruction. Keep native Enable/ordinary agent submission closed until their own interaction gates pass.
- Then implement actual candidate dispatch and exact worker permission, with complete original/cause resolution derived inside the transaction. Qualify initial independent, inherited automatic and mixed roots; self/cross-loop, depth/fan-out/total limits; pending-review overlap; exact retry; competing dispatchers; late cancellation/fence removal; prepared/committed SIGKILL; reconstruction and copied-file refusal. The shared-root race must use actual condition candidates as well as the existing trusted primitive.
- Finally connect native owner polling/status, native/conversational authoring and explicit preview/Enable/resume/from-now decisions. Qualify one real local-model condition workflow through human business review, visible Activity and restart recovery, plus keyboard/appearance/accessibility. Native UI must not enable a trigger whose backend/status cannot fulfill the contract. Dataset-query adapters and broader background/resource lifecycle follow separately.

Before publishing each coherent slice, bind exact frozen sources and package hashes, focused changes plus nearby counterexamples, meaningful schema/integration checks, full zero-warning db.md validation, repository links and commit/push. Do not call the overall app ready while these or the other maintained release gates remain open.
