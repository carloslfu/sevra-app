---
type: spec
id: 01m63xbjef018f5q5byn9acp7s
created: 2026-10-29T13:24:57.423588+00:00
updated: 2026-10-29T15:27:12.031435+00:00
summary: Schema 25 retains calendar roots and bounded trusted inherited admissions atomically. Condition cause discovery and dispatch remain required; scoped checks and failures are retained.
title: Durable automatic-run origins and admission
status: implemented
---
# Durable automatic-run origins and admission

This reviewed E4 foundation follows [[records/specs/automatic-ancestry]]. It retains automatic run origins and bounded inherited admissions through the existing captured workbook ledger. It does not itself select the business causes of an inventory transition or enable condition dispatch. Calendar execution keeps its existing live device/session fences and separate business review.

## Meaning and useful behavior

Every dispatched calendar occurrence starts an independent automatic-work root. The next day's explicit schedule occurrence is a new clock cause, not a continuation of yesterday's cascade. A condition responding to an automatic output must inherit that output's admitted roots and prior automation logical identities. Accepting, correcting or manually continuing that output does not silently clear its history. Independent human business events require a separately qualified root rule; this slice cannot infer that independence from an actor label or broad configuration ancestry.

An automatic-run origin is retained history, never permission to execute again. Copy/reconstruction/reopen preserve origin and charges but acquire no device capability. Pause, new generation, cancellation, completion and retry do not refund admitted work or reset its ancestry. Retrying an existing workflow uses the same run admission. New explicitly requested manual work remains governed by its own user decision; it does not rewrite the origin of earlier automatic work.

## Policy and initial bounds

The first versioned policy is automation-causality-v1. A run may inherit at most eight distinct immediate automatic parent runs and eight root identities. Count automatic run depth, starting at one for a calendar root, independently of ordinary lineage-edge depth. Maximum depth is eight. Refuse admission if the target automation logical identity occurs anywhere in its automatic ancestors, including an older exact version of that same automation. This prevents A -> A and A -> B -> A even after editing/re-enabling.

Each automatic parent may admit at most eight direct successor runs. Each root may admit at most 32 automatic runs in total, including its initial calendar run, across merges and branches. A merged run charges each distinct inherited root once, and each immediate parent once. These are initial qualification bounds for draft automation, not hardware-performance claims or user-configurable universal defaults. Changing policy requires an explicit version and separately qualified semantics; never reinterpret saved charges under a new silent limit.

Walk at most 256 retained automatic ancestors with bounded parent/root reads. The policy's eight roots and 32 charges per root bound a valid connected ancestry to 256 distinct runs. Unexpected excess/inconsistent paths refuse rather than treating them as independent. Reject missing parent admissions, unsupported policies, contradictory identities/depth/root membership, cycles, malformed/duplicate roots and attempted manual-run admission. Broad derivation/configuration ancestry is not substituted for the explicit parent-run set.

## Persistence and atomicity

Schema 25 adds four control families to existing complete capture/apply: automatic roots, admitted runs, run/root membership and immediate automatic parents. Root identity hashes the policy and exact calendar occurrence. Root rows retain the exact occurrence and original dispatch Source. Admitted runs bind the exact saved automatic run/definition/logical identity, depth, policy and dispatch Source. Parent/root memberships are indexed in both admission and budget-count directions. Use persisted membership rows as charges rather than process counters. No parallel history ledger.

Plan and retain admission only inside the owning captured write transaction. Recheck target binding, exact invocation origin and the plan before publishing; a stale or altered plan cannot commit. Root creation, run and occurrence binding, invocation, membership charges, parent edges, automation active-run pointer and committed-change outbox publish together, or none does. Stable mutation receipts prevent retries charging twice. No public model tool, arbitrary supplied root ID, ambient timer activation or serializable permission is added.

Production calendar dispatch initializes a fresh root and embeds its exact policy/root/depth/parent context in the workflow invocation's origin. Skipped late slots and future/idle/active deferrals create no root or charge. Internal inherited admission is a trusted core primitive for subsequent condition integration, not a public condition-dispatch endpoint. Its synthetic graph tests qualify the primitive, not automatic business-cause discovery or native event execution.

Read-only inspection returns an exact admitted run, direct parents, roots and current retained root/parent charges, with enabled=false and execution=none. Inspection does not establish a current grant or dispatch eligibility. Core verification must reject missing/contradictory saved origin state. Reconstruction restores rows inertly and must still satisfy those invariants. Preserve/refuse schema-24 development files without migration or resets; recreate selected synthetic fixtures only.

## Integration still required

Retain exact scope-relevant changed input versions/effective-time events across condition pages, clock groups and unknown intervals. Distinguish contribution/cause inputs from configuration/control provenance. Qualify parent discovery through every registered action/calculation/extraction/interpretation/intake output, acceptance and correction. A missing or over-bound origin must create an honest blocked decision rather than minting a fresh root. Choose the independent business-event root rule and coverage-gap behavior with the actual consumer/dispatch tests.

Then bind condition candidates atomically to exact authorized workflows, retain blocked/backlogged candidates, preserve one active run and each distinct successor, and keep live physical-file/model publication fences. Native and conversation authoring must show useful intent and explain a blocked chain in simple terms, with explicit manual run/pause choices. No calendar coalescing may erase inventory crossings. Dataset adapters, background/folder/resource lifecycle and complete E4-E6 remain open.

## Three review passes

1. Meaning and UX: separate a new calendar tick from descendants, automatic depth from lineage depth, logical automation identity from exact edited version, and charges from permission. Human review/manual continuation preserve origin. Distinct independent roots remain useful; blocked work is explicit and retained.
2. Recovery and authority: all admission state joins the existing dispatch transaction and captured reconstruction. Root membership is the persisted charge. Duplicate parents/roots do not double-charge; rejected admissions and failed publication leave no charge. Completion/cancellation/pause/restart do not reset budgets. Existing grants/fences remain mandatory.
3. Scale and adversity: real depth-eight/nine, fan-out-eight/nine and root-total-32/33 boundaries; merged roots/parents; shared DAG paths; old-version self-output; missing/corrupt/cyclic histories; simultaneous writers and process death. Indexed bounded counting must not scan unrelated workbook history. Inspection is read-only and cannot convert copied state into authority.

## Acceptance

Require actual calendar dispatch/no-op/late/retry behavior, exact invocation/binding/root atomicity, distinct next-day roots, restart/reconstruction with retained charges, synthetic inherited graph policy at every bound, self/cross loops and logical-version edits, merge/dedup, rollback/cancellation, refused noncaptured or manual admission and corruption verification. Installed CLI must expose truthful inert origin inspection. Re-run the existing two real dispatch SIGKILL boundaries and concurrent dispatch because the commit boundary now includes charges. Run full core for schema 25, nearby condition/ancestry/native-owner/ProductAI checks, installed native CLI/resource/refusal/signature proof, strict changed-Swift lint and zero-warning db.md/link/diff gates. Preserve iterations, immutable evidence and exact source scope. Commit/push and dispatch exact CI. This is not a whole-app or release claim.

## Primary references

[SQLite transactions](https://www.sqlite.org/lang_transaction.html) describes the single-writer and commit boundary used by the existing dispatcher. Root/parent membership counting and publication are our application-level invariants inside that transaction. [SQLite indexing and query planning](https://www.sqlite.org/queryplanner.html) informs the reverse root/parent indexes and bounded key reads. Neither database mechanism chooses business causality or grants automatic authority.

## Qualified foundation, October 29

Schema 25 now retains automatic_roots, automatic_admissions, automatic_root_members and automatic_parents through the existing captured commit ledger. Every production calendar run records its independent exact-occurrence root, exact saved automation/logical identity, policy, depth and dispatch Source. Next-day ticks remain independent even for the same logical automation. The trusted inherited primitive validates exact automatic parents, immutable invocation context and direct parent-invocation lineage, then applies logical self/cross-loop, depth, root, fan-out and total-work bounds under the same writer transaction. No public condition dispatch endpoint or independent business-event root is added.

Root membership is the retained charge. Duplicate parents and shared graph paths do not multiply it. Completion, cancellation, pause, reopening and inert reconstruction keep all charges. An altered or stale plan, missing/manual parent, corrupt/cyclic history or exhausted budget refuses without publishing a run/occurrence/Source/charge. Calendar future/idle/late/active decisions admit no work. Final cancellation is checked immediately before COMMIT, including the shared deadline; the new test proves complete rollback and same-token retry. Parent invocation IDs are read directly through their indexed workflow identity rather than loading parent workflow outputs.

V3 full core passes 456 groups with zero failures, including all 22 new admission groups. These exercise actual calendar roots/no-ops/retries/distinct next-day occurrences; synthetic inherited merge/dedup/shared DAGs; A -> A and A -> B -> A plus exact-version edits; depth eight/nine, fan-out eight/nine and branching root-total 32/33; eight/nine roots/parents; read-only/inert reconstruction; missing/manual/stale/altered/corrupt/cyclic histories; indexed budget reads; exclusive SQLite lock cancellation and final publication cancellation. Nearby condition, ancestry and execution checks are included. The V2 focused run also passes 22 groups. The final V4 edit only namespaces the independent-process fixture's operation keys; all production Swift and ordinary test bodies remain byte-identical to V3. Final 393 Swift hashes are frozen and strict lint passes on 15 changed files.

Installed checks pass 21 admission, 47 calendar execution, 22 ancestry, 94 condition and 76 feed calls against one native CLI. Nine independent trusted synthetic successor writers admit exactly eight and refuse one causal_fanout, with nine total root charges and no extra run; reconstructed inspection is identical and inert. Production installed calendar execution separately proves distinct next-day roots and retained charges after copies. Two actual calendar dispatch SIGKILL boundaries/16 calls include root/admission atomicity before/after commit and unchanged charges after explicit completion. Condition/feed each add six writers and two actual SIGKILL boundaries. Native owner 18 groups, synthetic ProductAI lifecycle, fresh native app/CLI, installed resources with build-tree reads denied, 1,888 kernels per executable, 10 missing-resource refusals, altered-resource refusal, missing-model guidance/workbook preservation and ad-hoc signature pass. All 144 preceding artifacts remain byte-identical.

V1's retained 19 passes/three failures exposed the final cancellation gap and two fixture expectations. V2 fixes those but its full run retains 454 passes/two older missing-binding fixture failures caused by the new foreign key. V3 fixes those isolated corruption setups and passes the full suite. The first independent-process fixture reuses a global request key, correctly producing idempotency refusals instead of a valid limit race. V4 fixes only that synthetic key namespace and passes nine writers. A missing-worker command usage failure and an installed corruption fixture's new foreign-key refusal are retained; the corrected installed ancestry script passes 22 calls. No failed result is replaced by a success claim.

Evidence: [automatic admission receipt](../../../integration/evidence/2026-10-29-automation-causality.json.gz), 135806 bytes, SHA-256 dd26b95f8d980d7cc74a2e91028c1c9b89dab52b5d57ac35bb92d144cac2090b. Previous head09e6ca2 CI was still in progress when this receipt was captured; this source requires its own exact CI. Final db.md/link/diff gates and commit follow the immutable receipt. Implemented status here means the qualified calendar/admission/inspection foundation only.

No selected-model/prompt/grammar/engine change or fresh actual-model/hardware/performance/production-adoption proof. Native app inventory still reports the Mac locked; no fresh visible UI, voice/accessibility/appearance/media, closed-window or background lifecycle proof. Exact business trigger causes across pages/clocks/unknown gaps, independent business-root policy, contribution-versus-control provenance, condition candidate-to-run binding with current physical grants and native/conversation/dataset adapters remain required. E5/E6, complete E3, contextual/Excel/E0-E2 and production distribution remain open. The app and overall goal are unfinished.

## Condition change inputs available, parent discovery still required

The schema26 [[records/specs/condition-transition-inputs]] checkpoint now retains exact scope-relevant business changes and activation instants between complete observations. Linked unknown windows and explicit10000-entry overflow avoid an empty-origin fallback. Final21 installed admission calls still pass against the same new native CLI. These inputs do not identify the minimal contribution slice or establish independent human business roots. Resolve exact contribution/control provenance and inherited automatic parents before connecting candidates to the existing bounded admission primitive. No new condition executor or permission is added.

## Explicit producer roles retained, resolution remains next

Schema27 now retains automatic parent invocation edges as producer roles, workflow/form/authorization/configuration as controls, and typed business arguments as data. Human review/corrections preserve old automatic versions through data/revision links. Shared admission/root policies and live permission boundaries are unchanged. The full484-group core pass and21 installed admission calls pass against the new packaged CLI. Named broad ancestry remains non-minimal and includes controls. Bounded business-origin resolution must validate the exact saved producer/admission binding before condition dispatch. See [[records/specs/business-provenance]].

## Bounded business-origin checkpoint, October 29

Schema27 now has read-only business-origin inspection over complete sealed data/producer/revision links. Control-only configuration is visible separately and excluded from business traversal; registered automatic producer boundaries validate exact workflow/run/automation/admission history. Direct/manual producer arguments, actors and supported policies are checked. Final 499 core/74 focused groups, real item/edge/depth limits, lock cancellation, installed 42 origin/22 ancestry/21 admission calls and fresh native package checks pass. No independent-root policy or permission follows. Evidence, retained failures and exact limits: [[records/specs/business-provenance]]. Condition-window resolution, shared roots and current-grant candidate dispatch remain next; full app/release qualification remains open.
