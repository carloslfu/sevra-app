---
type: spec
meta-type: conclusion
id: 01m7gjt1zc6br61a29kn3pf5nz
created: 2026-11-15T21:46:27.180871+00:00
updated: 2026-11-15T21:50:38.285646+00:00
summary: Staged plan to correct context accounting, upgrade Splash and qualify stable context and memory profiles.
title: Inference, context accounting and memory policy
status: reviewed
---
# Inference, context accounting and memory policy

## Decision and status

Revision 4, after three complete readiness passes: architecture/integration, recovery/user experience, and evaluation/release. Ready for staged implementation under the gates below; implementation and runtime qualification remain pending. Planning is authorized by [[sources/notes/2026/11/inference-context-upgrade-plan]]. This record does not upgrade the engine, change the installed app, run a GPU comparison or select a new production default. It connects [[records/specs/splash-integration]] and [[records/specs/conversation-context]]; implementation must update both contracts together. Research and retained evidence: [[records/research/inference-context-upgrade]]. Readiness review: [[records/reviews/inference-context-plan-readiness]].

Inspected source baseline: `658f06947867de8a3e4676c9e1edfb8fc65ced76`. Earlier CPU and historical model evidence have different frozen identities, recorded in the research. Recheck changed inference/agent surfaces before implementation; another workstream's later Excel acceptance is not automatically evidence for this change.

The intended user experience is dependable completion of increasingly large workbook jobs, with original information preserved, accurate results, understandable progress and responsive cancellation. The user should not choose token counts, diagnose GPU allocation or restart a conversation to recover saved work.

The engineering direction is: correct accounting on the present engine; upgrade Splash at the same 32K context and 12 GiB engine budget; then compare context and memory profiles. A 64K default is a candidate on the inspected 48 GiB Mac, not a predetermined result or a promise for every supported Mac. Keep a stable profile during an ordinary job. Choose any larger qualified profile before a large job, using exact input requirements and safe resource admission. Do not introduce a repeated 32K → 64K → 128K → 256K restart ladder.

## 1. Findings that drive the work

| Finding | Consequence | Required change |
| --- | --- | --- |
| Native measurement constructs the full tool set; actual generation can use a narrower scope. The conversation specification deliberately chose conservative all-tool accounting. | An answer-only request can be refused even when its actual rendered prompt fits. This is a policy revision, not merely changing an estimate. | Measure and dispatch the same prepared request, including exact tool scope and current reference choices. Update the documented policy. |
| General output reserve is 1,800 tokens while authoring can produce 8,192. | At 24,575 prompt tokens in 32K, the allowed authoring output leaves only one token, despite the intended tool-result and recovery reserves. This is a headroom mismatch, not a demonstrated buffer overrun. | Make admission and maintenance mode-aware. Include reasoning inside the total output allowance once. |
| Measurement starts the model session; configuration is immutable for that worker. | Choosing a larger profile after measurement can load a 32K helper only to restart it. | Separate frontend preparation/counting from helper startup; validate the prepared request again against actual engine readiness. |
| Ready carries actual capacity, but budgeting reports configured capacity. | Host assumptions can diverge from engine admission. | Bind allowance, diagnostics and generation to validated session capacity and identity. |
| Context size competes with model caching inside an engine memory budget. | A larger ceiling can slow even short jobs; a smaller ceiling alone may not reduce memory use. | Evaluate context, memory budget and activation/cache policy as a profile. Treat pressure recovery separately from context overflow. |
| Existing 1 MiB/512-message envelope and other structural limits are independent of context capacity. | Raising a token ceiling alone may not allow the intended input or complete the job. | Audit all relevant bounds, retain meaningful protections and change only demonstrated bottlenecks with independent checks. |
| Splash 1.4.1/protocol 11 is pinned; 1.6.1/protocol 13 is the current researched candidate. | This is an adapter, lifecycle and packaging upgrade, not just replacing a version string. | Complete the surface map and qualification gates below. |
| Product wiring uses the native preview, while several pin/status records still describe candidate/Slotstream state. | A successful local preview and a qualified production backend can be confused. | Reconcile source, binary, installed preview and release qualification explicitly. Historical W1 failed exact paired-output parity despite passing timing; D9 found reference repeatability differences. Do not flip status fields or call that cohort qualified. |

Retained controller evidence: a synthetic 280-row answer-only request measured 27,187 tokens with all tools and stopped, but measured 22,558 with the actual scope and reached dispatch. The nearby 320-row scoped request still stopped at 24,717 against the 24,576 maintenance boundary. This tests admission with the real tokenizer/controller and a no-generation fixture, not answer quality. Refresh the regression against the implementation baseline rather than hard-coding obsolete schema token counts.

Historical successful Excel fixtures used 4,026–15,132 prompt tokens. That supports fixing completion and accounting before assuming every job needs more context. It does not establish actual customer usage or prove 32K is the best ceiling. Earlier multi-document and occupied-context results justify testing larger jobs, with their recorded failures and unmatched conditions retained.

## 2. Architecture and invariants

### 2.1 One preparation path for measurement and dispatch

Introduce an immutable prepared-request representation at the inference boundary. Its exact name is an implementation choice. It must contain or identify the rendered prompt/token IDs, effective tools and schemas, generation prefix, citation/reference enumeration, current task mode, output/reasoning policy, tokenizer/template/schema versions and relevant workbook snapshot/version identities. Do not introduce a second prompt renderer just for measurement.

The controller determines the next step's tool scope before preparation. Counting, grammar construction and generation consume that same request. A changed tool scope, tool declaration, selected source version, reference enumeration, authoring flag, retry instruction or workbook authority snapshot invalidates preparation. Verify identity immediately before dispatch and repeat preparation after maintenance reconstructs the active request. Snapshot validation must not race a concurrent workbook mutation; use the existing authoritative transaction/version boundaries. Preparation cache keys include these dependencies; no cross-workbook or cross-authority reuse.

Cover ordinary answer-only requests, phase-specific calls, native app creation, Excel interpretation/generation/review/repair, custom schemas, summaries and retries. A narrow scope cannot grant tools that the controller or current user authority disallows. Remove redundant accounting paths rather than retaining a second API as pre-1.0 compatibility. Keep the preserved baseline build compiling through the canonical interface, without changing its inference engine as a side effect.

Preparation must operate without starting a GPU helper. Static tokenizer/model metadata loading can remain cached and bounded. Once a helper is ready, compare the prepared request with its engine/model/tokenizer and capacity metadata before generation. A prepared prompt is not permission to reuse stale workbook authority or execute an action.

### 2.2 Explicit capacity and reservations

For each next request define:

- `C`: validated usable capacity bounded by the selected qualified profile, engine Ready, model configuration and host/wire limits, never a marketing/model maximum. A larger Ready value cannot silently expand the selected policy; a smaller one requires re-admission before dispatch.
- `P`: exact rendered input token count, including schemas, history, generation prefix and dynamic choices.
- `O`: maximum output for this mode, including reasoning and final/tool text together.
- `T`: bounded projection of the next tool result plus any required conversation framing.
- `R`: explicit recovery/transition reserve.
- Maintenance/admission threshold `H = min(floor(0.75 × C), C − O − T − R)`, with safe arithmetic and meaningful handling of an infeasible or nonpositive allowance.

Retain the owner's 75% maintenance policy for the first implementation. Reinterpreting that boundary as an optional warning is a separate proposed policy change, not an escape hatch for a failing benchmark. Continue the existing at-threshold maintenance semantics and test the exact inclusive boundary.

Initial values remain normal output 1,800, authoring output 8,192, tool-result reserve 2,048 and recovery reserve 256 until evidence supports a change. Review output 4,096 and summary output 1,400 have their own prepared policies. Normal reasoning 512 and authoring/review reasoning up to 2,048 are part of `O`, not an extra subtraction. Preserve the minimum useful tool/answer room and bounded-reasoning requirements.

With those starting values, 32K normal `H` is 24,576; 32K authoring `H` is 22,272. A larger context must not silently increase output, reasoning, retry count or timeouts. If maintenance cannot fit the irreducible active request, retain saved work and report the specific input/working-set limit or select an already qualified larger profile at a safe boundary.

`T` must describe a bound the tool projection actually enforces. Store complete tool receipts and source data; send a bounded, truthful projection with stable locators and coverage information. Verify that the single-call policy is enforced before applying an action; if a phase permits multiple calls, reserve the aggregate projected results and framing rather than one result. A write that already committed remains recorded even if its response projection cannot fit; recovery must not repeat it. Do not cut JSON, a tool-call/result pair, an exact source-copy contract or the active instruction. Account again after every result; if a tool cannot offer a bounded useful projection, provide a paged/retrieval alternative or stop safely before claiming capacity is available. Reserve values are hypotheses to validate against representative results, not guarantees created by naming constants.

Summary generation needs a separate fitting policy: it is maintenance work, not another ordinary tool step subject to a recursively applied 75% trigger. Its exact prompt plus summary output plus the explicit recovery/framing reserve must fit within `C`. Use no fictitious next-tool reserve for a summary that cannot call tools. Preserve the existing bounded batch selection, protected references and validated digest rules. Test repeated maintenance and an irreducible request that remains too large. Require observable progress toward a fitting request and a finite maintenance/repair limit; stop with saved originals on no progress or repeated failure. Do not recursively summarize forever or silently discard protected state. Reuse existing conversation history, task state, immutable receipts and context digests. Summaries remain derived navigation aids; fresh workbook state, acceptance, permissions, source versions and mutation receipts remain authoritative.

### 2.3 Capacity is not the working-set strategy

Use native calculation/query paths for complete row sets and exact arithmetic. Retrieve relevant document spans with explicit coverage. Preserve original documents and conversation outside the active prompt. A wider window is useful when it retains necessary simultaneous evidence or avoids expensive, lossy maintenance; it does not make irrelevant bulk text helpful. Reuse existing coverage/provenance state to track which requested sources and ranges were actually considered. An instruction to compare all selected sources cannot silently become a comparison of the first few that fit.

Audit the whole path: 16,000-byte user prompt, 1 MiB working envelope, 512 messages, frontend 2 MiB/65,536-node/depth bounds, digest 16,384 bytes, citation choices 256, history/protected-reference pages 128, source-copy/reference limits, output grammar bounds, 12-step ordinary run limit, 180-second generation and 360-second startup deadlines. These limits have different purposes. Do not scale them all by the context multiplier. Document the observable user limitation and its safe alternative for each retained bound. Add 128K/256K evaluation capacities only with parser, integer, framing and lifecycle coverage; keep unsupported capacities impossible to select in production.

### 2.4 Stable profiles and resource admission

A profile identifies context capacity, explicit engine allocation budget, activation precision, cache policy, model/draft identities and relevant engine options. Record requested and admitted values separately. The existing 12 GiB setting is not total application memory. Measure application and helper physical footprint, CPU-resident/model-mapped resources, temporary cache storage, pressure and swap alongside the engine budget.

Use a qualified profile allowlist based on hardware/OS capability and successful admission. Total RAM alone is insufficient; current pressure, other applications and engine recommendations matter. The inspected M5 Pro/48 GiB host can qualify only its tested scope. M3+/macOS 26.4+ eligibility does not establish a safe RAM tier. Unsupported or insufficient-memory cases need a precise local explanation and a known safe path, not a guessed budget or hidden hosted fallback.

At ordinary job start prefer the qualified default. A job whose known required working set exceeds it may select one larger qualified profile before helper startup. Long conversations still use bounded retrieval and maintenance. Freeze the selected profile for the active job. Avoid restarting merely because a transient reading of free RAM changes. When a different profile replaces an already warm idle helper, account for that reload in user-visible latency and use the same stop/reap/lease discipline before the new job begins. Limit pre-dispatch admission fallback to one alternative already qualified profile; then return the specific failure instead of cycling profiles.

Memory-pressure fallback must reduce an actual allocation budget and/or release the helper and cached resources. Reducing context from 64K to 32K while leaving the same engine budget may merely increase cached weights. Do not call that memory relief without measurements.

An exceptional helper replacement is permissible only if evidence shows a necessary user benefit and the lifecycle gate passes: checkpoint durable progress, stop and reap the old child while retaining the global lease, construct the replacement, reprepare from current authority and continue only the next unapplied authorized step. No overlapping helpers, replayed writes or duplicate approvals. The first implementation excludes automatic mid-job capacity expansion. Any later exception requires evidence from P4 plus a separately recorded lifecycle qualification before enabling it; a stable profile and clear saved-progress recovery are the first-release path. Existing safe recovery from a dead helper remains distinct from adding a capacity-growth feature.

## 3. Splash and related dependency upgrade

Candidate frozen for this plan: Splash **1.6.1**, source commit `d8af1054aab0f97de21d043e01aa98af3754f10e`, protocol **13**, status schema **8**. Current pin: 1.4.1 at `1744cfafee415fb463b289449cec59a864e768e9`, protocol 11/status schema 6. The candidate archive's published SHA-256 is `0ed408a781f951a13ff58bed95c9e8c1d1dc67ab9d649fcaf365972b6720ce6c`; published size is 78,670,846 bytes. Source and release metadata were inspected; archive bytes, extracted component hashes and installed behavior have not been verified by this planning task.

Keep Qwen3.6-35B-A3B 4-bit and the current DFlash2/model/tokenizer revisions unchanged in the initial comparison. Preserve unchanged upstream C++/Metal engine and LLGuidance behind the native ABI. Python may generate reference fixtures in isolated development tooling; the installed product, setup and runtime stay Python-free.

| Surface and owner | Required work | Evidence required before promotion |
| --- | --- | --- |
| `integration/splash.json`, `scripts/fetch_splash.py`, runtime resources and package scripts | Verify immutable source and archive identity; inventory extracted executable, both Metal libraries, license and notices; refresh changed artifact layout/requirements. Preserve the previous pin and qualified bundle. | Clean fetch/hash rejection checks, exact resource manifest and bundle identity. A movable release tag is insufficient. |
| `Sources/SevraSplash/Wire.swift`, `StreamState.swift`, `NativeProcess.swift` | Protocol 13 framing/Stop, extended Ready metadata, typed StartFailed, Warming and status 8. Update bounded payload parsing and request/engine failure distinctions. Validate supported protocol versions explicitly; update the canonical adapter rather than adding a legacy protocol shim. Compare serialized Done/Error fields, including bounded/retry-after semantics, rather than assuming their comment changes imply new bytes. | Upstream serializer/golden byte parity, malformed/truncated/oversized frames, cancellation at startup and generation, bounded child teardown. |
| `ModelPreparation.swift`, `ModelSetup.swift`, `ModelDownload.swift`, selected-model metadata | Compare changed installation/assembly conventions, file checks, reuse and resumable setup. | Fresh Swift-native setup and existing verified model reuse. A Python-created assembly alone does not qualify installation. |
| `SevraSplashText` frontend/templates/decoder/output | Diff all selected-model template, tokenizer, stopping and streaming semantics. Regenerate exact fixtures when changed. | Exact prompt IDs, generation-prefix counts, Unicode bytes, split markers, both EOS/special/padded tokens and output parse outcomes. |
| `SevraSplashGrammar`, grammar fixtures and tool normalization | Compare candidate LLGuidance requirements and full token vocabulary/masks. Preserve strict workbook dispatch. | Every actual tool schema, required/automatic/named/reasoning masks, speculative rows, dynamic enums and invalid schema cases. Successful terminal plus full schema validation before dispatch. |
| `SevraNativeAI`, `SevraAI`, product coordinator | Prepared-request accounting, admitted capacity, model lease, maintenance and pressure handling. | Deterministic admission/recovery checks and complete autonomous jobs, including cancellation and current authority after reopen. |
| Product progress, metadata and packaging | Surface real initialization state; distinguish active preview from qualified default; update pin/status/spec records together. | Native UI verification, installed resource hashes/Mach-O identity, no Python/MLX runtime processes, complete job/reopen/portable-copy receipt. |

The candidate still uses LLGuidance 1.8.0. Do not bump it just to make versions look newer; verify source/C ABI defaults, build/link toolchain and licenses. Audit Swift-transformers 1.3.5, its resolved transitive dependencies and the Rust build dependency for an upstream-required change. Keep them pinned when parity passes. Any necessary dependency change gets its own diff, reason and focused check, not a blanket SDK upgrade.

Expected opportunities include expert streaming/compute overlap, router memory work, kernel warmup/progress and slow-disk fixes. These are candidates for startup or complete-job improvements, not promises of a particular speedup. The 1.6 memory planner fixes a context/budget interaction and needs admission regression coverage. The selected 35B model does not gain KV spill to SSD. Python frontend prefix caching, upstream chat/PDF UI, HTTP serving, unrelated models and concurrency are not automatically features of Sevra's Swift single-inference path.

On M5, 1.6.1 automatic activation selection can choose INT8 paths. First compare old and new engines using explicit BF16 activation behavior where supported and otherwise record the exact existing precision baseline. Then measure candidate auto/INT8 as a separate quality/performance arm with isolated cache identity. Keep target KV/state precision and any Neural Engine setting explicit and matched; `activations=bf16` alone must not be assumed to control an independently enabled execution path. Do not attribute precision changes to context size or require byte-identical generations across different engines; require exact declared business outcomes and retain differences.

Native model capacity is 262,144 tokens; the model advertises approximately 1,010,000 with YaRN. The latter changes positional behavior and is excluded from this plan's default/profile candidates. Neither model declaration establishes useful recall or a deployable memory profile.

## 4. Staged execution and acceptance

Work on main in focused checkpoints, preserving unrelated work. Keep at most three active blockers in the progress register. Each phase records source/binary/configuration identities, commands, raw failures, interpretation and remaining limits. No recurring benchmark/update job is created. A failed gate stays failed until repaired or explicitly deferred from the release scope.

### P0. Freeze baseline and qualification contract

Re-read current source, package/resource pins and owning specs. Record the actual source/binary/installed-preview relationship and whether there is a previously qualified native bundle. Preserve the Slotstream baseline separately. Freeze synthetic workloads and independent expected results before seeing candidate outcomes. Reproduce the accounting defects with the current tool declarations. Reuse unchanged prior evidence with explicit identities; refresh only affected boundaries.

Deliver: an upstream-to-Swift change map, baseline manifest, complete bounds inventory, candidate archive/component verification and preregistered comparison protocol. No runtime promotion. Entry to P1 requires a reproducible accounting failure plus a nearby legitimate rejection; entry to P2 requires verified candidate provenance.

### P1. Fix accounting on Splash 1.4.1 at 32K/12 GiB

Implement the common preparation/budget contract and exact tool scope through normal, authoring, review and summary calls. Use actual Ready capacity; separate CPU preparation from startup; enforce useful result projections and mode-aware reservations. Update the conversation specification to describe the intentional shift from full-tool conservative accounting. Keep engine/model and default configuration fixed.

Required checks: actual-scope admission failure/counterexample, scope mutation invalidation, exact threshold −1/equal/+1, authoring output reserve, reasoning included once, infeasible minimum output, summary fitting, bounded oversized results, dynamic references, current authority and preparation without helper startup. Exercise one actual normal workbook job and one authoring job to ensure the new boundary reaches valid generation. Reuse broader unchanged business evidence, without claiming those two smokes replace later qualification.

Exit: no known measurement/dispatch mismatch, no stale-scope authority, reserve invariants hold for all modes, oversized input remains safe and originals/receipts remain complete. Commit this independently so engine and capacity experiments use the same corrected host logic.

### P2. Integrate Splash 1.6.1 at the same 32K/12 GiB

Apply the verified candidate pin and affected Swift/fixture/resource changes. Retain unchanged model/draft weights. Implement the protocol/lifecycle/model-preparation matrix in section 3. Treat the new precision default as an explicit experimental factor. No context expansion in this phase. Freeze the chosen candidate rather than chasing a newer release mid-experiment; if a later fix is necessary, record a new candidate and requalify changed boundaries. Extend the existing checks in `IntegrationTests/Splash`, `IntegrationTests/Text`, `IntegrationTests/Grammar` and `IntegrationTests/Agent`; keep `scripts/check_splash_reference.py`, text/grammar fixture generators and `scripts/check_performance_harness.py` aligned with the new pin. Existing `sevra-agent-checks` arguments and capacity validation must be updated before a 128K/256K harness can claim to exercise those profiles.

Exit: protocol/text/grammar/setup/resource checks pass, startup/generation/stop and failure teardown are bounded, the current engine status is truthful, and the comparison harness verifies equal input tokens and equivalent request parameters. The candidate remains unpromoted while full behavior/performance gates are pending.

### P3. Qualify engine behavior and upgrade effect

Run selected-model real-token and grammar differentials against the pinned 1.6.1 reference. Keep the existing native-versus-reference adoption contract, including the stricter same-engine complete-workflow generated-token equality. Cross-version semantic comparison below does not waive that separate gate.

Before another full cohort, run a bounded replay of the preserved W1/D9 divergence with candidate identities and the same complete preceding request/cache history: reference/native/native/reference. Verify actual request bytes, grammar and mask equivalence, then distinguish within-backend repeatability from adapter mismatch. Repair a demonstrated mismatch and repeat its focused counterexample once. If same-backend numerical variation persists, retain failed parity status and document the evidence; do not loop full cohorts until one happens to pass. A change to the existing parity acceptance contract must be a separate explicit reviewed decision with its rationale and tests, not an implicit relaxation hidden in this upgrade plan. Separately compare corrected-host native 1.4.1 with native 1.6.1 under matched 32K/12 GiB/BF16 settings; this isolates the version change. A native-versus-Python result alone does not establish improvement over Sevra's current native engine.

Run autonomous workbook probes, conversation `--continuity` and `--context-recovery`, tool/permission/citation/calculation validation, startup/generation/summary cancellation, pressure/child-exit recovery and current-format reopen/portable-copy. Include the existing accepted supplier/Excel cases affected by changed engine output, with original input hashes and independent expected values. Preserve generation and validation failures rather than repairing outputs manually and counting them as model successes.

Exit for promotion: all mandatory behavioral outcomes pass and the predeclared parity/performance gates pass. P4 research may proceed on a clearly labeled candidate after behavioral, lifecycle and safe-admission prerequisites pass even if the stricter adoption gate remains open; P7 runtime promotion may not. If automatic M5 precision is chosen, it passes the same semantic and recovery suite as a separate arm. A regression requires investigation or retaining the prior runtime, not loosening the thresholds after inspecting results.

### P4. Compare context and actual memory budgets

On the inspected M5 Pro/48 GiB host, screen **32K, 64K and 128K at 12 and 24 GiB** using the candidate's fixed activation/cache policy after P3's behavioral/safety prerequisites. Keep candidate research distinct from production qualification. These are requested experimental budgets, not promised admissible profiles. Preflight each through the engine's resource planner; do not force an infeasible budget or induce real system exhaustion. Record rejection as a result. If 24 GiB is infeasible, allow an explicitly preregistered 18 GiB follow-up to answer the narrower intermediate-budget question; do not opportunistically search many budgets.

Screen all six cells once with the small/medium/large task bundle and safety checks. Screening chooses at most two finalists; it cannot establish p95 or production adoption. Start with identical evidence and output policies across capacities. Evaluate occupied, useful contexts as well as small prompts at a larger ceiling. Keep retrieval and maintenance rules identical except for the declared capacity-dependent thresholds.

Only add a 256K experimental arm when a realistic task still needs simultaneous evidence beyond the 128K profile after appropriate retrieval and it fits all host/model bounds. Require the same quality and resource gates. Do not spend a release cycle filling 256K with repetitive text simply because the engine accepts it.

Deliver a per-workload table of complete outcome, latency, footprint, pressure, cache/disk behavior, compaction/restarts and coverage, including rejected and failed cells. Exit: the decision in P5 follows the prespecified rules, and remaining untested hardware/capacities are explicitly unsupported or unqualified.

### P5. Implement and verify the selected profile policy

Choose the smallest/least costly qualified configuration that completes the intended task classes with the best measured experience. Correctness, preserved authority and responsiveness are gates, not tradeable scores. Among passing profiles, prefer materially better complete-job time and fewer interruptions; when differences are within noise, prefer lower resource use and simpler stable behavior. An overall mean cannot hide a material regression on a declared ordinary workload.

Adopt 64K as a default only if it provides a demonstrated benefit without violating ordinary-workload performance and resource gates. If 32K performs as well after accounting fixes, retain it. If 128K helps rare large jobs but costs ordinary performance, make it an internal pre-job selection only on qualified hardware. Do not make context tuning a user obligation. More RAM can enable a better model-cache/context balance, but a RAM-to-token lookup table is not a substitute for measured admission.

Implement a deterministic, logged profile selection reason and a bounded failure path. A missing qualified tier must not silently choose a larger one. Keep critical-pressure and explicit-cancellation runs stopped until the user explicitly continues; normal safe internal retry must stay within the still-active authorization. Test cold start, cached reuse, application switching, memory warnings and subsequent independent jobs.

### P6. Verify the actual native experience

Use real Warming/Ready/request progress to explain preparation, reading, processing and verification. Avoid fabricated percentages and low-level token/GPU jargon in the ordinary flow. Show saved progress and the specific next action when a limit prevents completion. Do not promise all files were read when coverage is partial, or show a stale result as a new completed job.

Verify Stop during model setup/warmup, ordinary generation, tool result handling and summarization. It must remain responsive, leave a truthful saved state and not restart work automatically. Verify a subsequent independent request after teardown. Instrument cancellation acknowledgement, helper termination and UI response separately. Preserve or improve existing host bounds: request cancellation shortens its wait to three seconds; helper close attempts termination for one second then kill/reap for up to three more. Tests must verify the total path including queue delay, not claim these component timers guarantee an instantaneous stop. A stuck child keeps the lease held and produces a truthful failure. Check reopened conversation, latest user instruction, accepted/rejected proposals, source edits, source removal and saved calculations. Preserve Undo/Redo and no duplicate mutation effects.

Use the exact current native preview bundle when installation/UI testing is authorized for implementation. Verify executable Mach-O UUID and bundled resources against the packaged output, not names/timestamps. Review actual native progress, interruption and completion states at narrow windows with keyboard operation; do not infer UI acceptance from a headless model probe. VoiceOver and system-setting changes remain separate existing boundaries.

### P7. Integrate, record and release only the qualified result

Rebuild the db.md index, run focused changed-boundary checks while iterating and `scripts/check.sh` once at the integration/release checkpoint. Re-run a broader suite only for a new change/failure affecting its evidence. Run the required clean native package/setup/install and affected end-to-end checks against the exact final source and resources. Confirm licenses, executable and Metal-library hashes, dependency pins, no Python runtime/setup requirement and no unrelated model redownload.

Update integration pins, native product configuration, selected-model/resource identity, owning specs and operations records consistently. Keep evidence and limits public and synthetic. Commit/push the focused implementation through the normal repository workflow and record any required hosted checks. Distinguish local preview qualification, other hardware and public release/signing status.

Rollback restores the previous verified engine/configuration/bundle and compatible resources while preserving user workbook originals and durable receipts. Do not downgrade user data or overwrite the preserved Slotstream app to make rollback convenient. If the prior native bundle was never fully qualified, state that limitation; do not invent a qualified fallback from a candidate label.

## 5. Experiment design and decision gates

Use both `integration/performance/protocol.json` and `integration/performance/workflow-protocol.json` as starting contracts. The former is request-level R1; the latter is complete-workflow W1. Preserve the recorded R1 priority confound, W1 failed parity and D9 reference-repeatability findings. They prevent claiming that existing historical latency results already qualify production adoption. The request protocol specifies 10 alternating blocks × 2 repetitions per workload per backend, one warmup per workload/process, fixed seed/temperature, sampled physical footprint, retained failed requests and an observed p95 caveat. Freeze separate versioned protocols for same-engine adapter qualification, cross-version upgrade effect and context/memory selection without rewriting historical receipts. The W1 adapter gate retains exact paired prompt/generated-token sequences; different-engine or different-capacity jobs may follow different valid paths and instead require the frozen independent business oracle. Never label the latter as identical-computation proof. The pilot proves harness operation only. Finalists require the full preregistered cohort; 20 samples give an observed tail, not a population guarantee.

Keep hardware, AC power, thermal/load conditions, model/draft, inputs, schemas, output/reasoning budgets, activation policy and cache mode matched except for the declared variable. Capture actual serialized requests, not just intended settings. Within the same protocol normalize only IDs/deadline timestamps and compare all remaining fields, including foreground priority, cache identity, flags and thinking terminators. Across wire versions compare every mapped semantic field, with new/removed fields explicitly explained. Record initial matched-prefix and later deduplicated-KV counters separately; equal counts do not prove identical cached state. Keep command/status history and cache priming symmetric. Diagnostic grammar/mask tracing, per-request isolated caches or artificial pacing cannot qualify normal-cache performance. Freeze measured source, resource manifests and worker binaries and verify them before each worker and finalization.

Do not overlap model jobs, builds or downloads. Hold the existing inference lease for each comparison. Alternate order and rotate task order; separate process-cold from warm runs. Do not call an uncontrolled OS cache SSD-cold. Retain all attempted blocks and the existing narrow exclusion reasons. Swap growth and bad answers are findings, not reasons to drop samples.

| Task family | Necessary evidence and independent oracle |
| --- | --- |
| Ordinary short work | Simple lookup/update, cited supplier comparison and deterministic calculations. Exact values/citations, no extra actions, first useful result and total time. |
| Excel/application work | Current frozen accepted business cases plus a known repair case. Source formula/value equivalence, behavior tests, usable saved app, repair attempts and time included. No hand-edited model artifacts counted as success. |
| Large useful source work | Multiple documents with named facts/constraints early, middle and late; realistic long records/code where appropriate. Exact source versions, coverage, cross-source conflicts, calculations and an answer oracle. |
| Long conversation | Repeated maintenance, latest instruction overriding older intent, preserved early constraint, current accepted/rejected proposals, source updates and portable reopen. False/stale digests cannot grant authority. |
| Capacity/resource limits | Just-below/at/above effective thresholds, irreducible request, dense CSV/non-English/code inputs, oversized results and safe admission failure. Real memory remains bounded; use fault injection for destructive pressure/OOM paths. |
| Interruption/recovery | Stop and helper death at startup/generation/summary/tool boundaries, first subsequent request, applied versus unapplied mutations and source/version changes. No replayed effects or hidden continuation, including a source change while preparing a replacement and cancellation immediately before committing a tool action. |

Collect full end-to-end job time including startup when applicable, frontend/grammar preparation, retrieval, prefill, decode, maintenance, validation and automatic repair. Record time to first useful visible result separately from first token/thought. Capture input/output tokens by mode, output truncation, tool calls, retries, failures, number/duration of maintenance passes, helper restarts and saved-artifact correctness. Record application/helper physical footprint, engine plan/admitted capacity, memory pressure/swap and actual temporary-cache/read/write behavior where observable. Distinguish estimates and unknowns from measurements.

Adoption preserves the existing I10 limits: no greater than 5% median or 10% observed p95 regression on any declared matched workload, 100% required semantic success, and no behavior regression. Report variance and raw samples; predeclare how noisy near-boundary timing results trigger at most one additional bounded cohort and report both cohorts together. This rule cannot clear a wrong answer, parity mismatch, instrumentation/identity failure or unsafe lifecycle by rerunning unchanged code. Such failures require a diagnosis and an explicitly revised candidate/protocol before new qualification. Useful newly enabled large tasks can justify an optional large-job profile, not a regression in the ordinary default. If no candidate meets the gates, retain the prior configuration and publish the specific unresolved cause.

## 6. Failure and recovery acceptance matrix

| Trigger | Required behavior |
| --- | --- |
| Invalid/zero/overflowed Ready capacity, vocabulary/mask mismatch or wrong engine identity | Reject session before dispatch; bounded teardown; preserve evidence and model lease until child is reaped. |
| StartFailed budget/context/model/cache condition | Use structured failure to choose a permitted next action; no arbitrary retry storm or ambiguous generic success. |
| Truncated frame, bad UTF-8, incomplete/duplicate/unknown tool or unsuccessful terminal | No workbook action from partial output. Preserve diagnostic and close/fail the request safely. |
| Real request exceeds threshold or cannot be compacted | Maintain/retrieve within policy, select a qualified larger profile only at a safe boundary, or explain limit with saved progress. No silent source omission. |
| Tool output exceeds its projection reserve | Keep complete receipt, produce an explicitly bounded projection or stop safely; never cut required exact source material while claiming complete coverage. |
| Warning versus critical pressure | Warning respects current safe lifecycle; critical cancels/releases as required. Actual budget/resource relief measured. Critical cancellation does not auto-resume the job. |
| Stop during startup, generation or maintenance | Bounded cancellation, original data intact, no new actions after cancellation, no automatic larger-profile restart. |
| Child death before/after a write | Rebuild from committed receipts/current authority; retry only an unapplied authorized step. A committed change is not executed twice. |
| Changed approval, source version or workbook between preparation and dispatch/recovery | Invalidate prepared request/digest assumptions; reread current state. No stale authority or cross-workbook cache reuse. |
| Teardown timeout or unreaped child | Keep the global lease; fail closed for further inference until ownership is resolved. Never launch a second competing helper. |

## 7. Ownership, deliverables and completion checklist

Implementation ownership follows existing modules: `SevraAI` owns policy/continuity and tool projections; `SevraNativeAI` owns request preparation/native adaptation; `SevraSplash` owns wire/process/setup/resources; text and grammar modules own exact frontend semantics; product/coordinator owns profile admission and user lifecycle; integration scripts/evidence own reproducible qualification. Reuse existing durable state and inference lease rather than creating a parallel coordinator or memory ledger.

- [ ] P0 baseline, candidate provenance, bounds map and protocols frozen.
- [ ] P1 actual-scope accounting, output/results/recovery reservations and CPU-only preparation verified on the existing engine.
- [ ] P2 protocol 13/status 8 and all affected native/text/grammar/setup surfaces verified at unchanged capacity/budget.
- [ ] P3 engine and precision comparisons pass semantic, lifecycle and performance gates.
- [ ] P4 useful-context and memory matrix completed with retained failures and formal finalist evidence.
- [ ] P5 default and any optional large-job profile chosen from evidence, with qualified hardware limits and safe admission.
- [ ] P6 installed native UX, cancellation, continuity and saved-result correctness verified.
- [ ] P7 final checks, exact bundle/resource identity, consistent documentation, commit/push and rollback evidence complete.

Deferred: million-token/YaRN configurations, new model/draft selection, cloud fallback, concurrent inference, upstream HTTP/UI features, blanket dependency upgrades, speculative tokenizer cache rewrites and a general automatic context-growth ladder. Revisit only for a demonstrated product need with a separate measurable acceptance gate. Planning completion means these decisions and implementation gates are ready; it does not mean the upgrades or candidate profiles have passed them.
