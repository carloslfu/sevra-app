---
type: operational
meta-type: operational
id: 01m7jmgpet71503tz8tqy8k3ax
created: 2026-11-16T16:54:46.490015+00:00
updated: 2026-11-24T14:42:24.662749+00:00
summary: 'The Splash 1.6.1 step: 64K on the 48 GiB test Mac with a 12 GiB engine budget. Splash 1.7.1 replaced the engine on November 24.'
title: Inference and context implementation
---
# Inference and context implementation

## Current engine

November 24: the engine is now Splash 1.7.1 under [[records/plans/splash-1-7-1-upgrade]]; the context tiers and the 12 GiB budget are unchanged. The rest of this record describes the 1.6.1 step.

The owner authorized a focused preview upgrade and a practical 32K versus 64K comparison. Splash 1.6.1 was installed in the app. The source chooses 64K on Macs with at least 48 GiB of unified memory and 32K below that tier, with a 12 GiB engine budget and automatic context maintenance in both cases.

On the 48 GiB M5 Pro, both settings passed the cited inventory task and the 14K-token purchasing audit. The 42K-token audit was refused at 32K and answered all three values correctly at 64K in 32.8 seconds. Observed peak host and helper footprint was 12.0 and 11.9 GiB respectively, with unchanged swap. These were single runs with synthetic inputs. See the [preview comparison receipt](../../../integration/evidence/2026-11-16-splash-native-preview.json) for the measurements and installed build identity.

This preview decision supersedes the earlier local hold. The earlier repeatability, authoring and repair failures remain recorded for broader production qualification. [Checks for the integration commit](https://github.com/carloslfu/sevra-app/actions/runs/43943224631) passed all 40 steps. The additional product change selects the context at startup.

The rebuilt native package passes its resource, signature, installation and extraction checks. The installed app matches package UUID `C13AE316-20FD-39BF-BF56-66EB57E48312`. The installed calculator task returns 893 for 47 × 19 and saves the completed receipt with Splash 1.6.1 and 65,536 served tokens. Workbook integrity passes. The model setup verifies and reuses the existing weights. The previous app and assembly remain available for rollback.
## Earlier candidate evaluation
The host accounting and continuity fixes are implemented. P1 is committed/frozen at `c6a588c` on Splash 1.4.1. The current source integrates candidate Splash 1.6.1/protocol 13/status 8 with explicit BF16, int8 KV, fp32 state and ANE on at unchanged 32K/12 GiB. Exact model assembly, CPU adapter checks, real startup/responses/cancel/refusal/recovery, autonomous workbook jobs and corrected multi-compaction/portable continuity pass. The preserved original preview CLI opens and verifies a disposable portable copy from the candidate. Portable receipts are `integration/evidence/2026-11-16-splash-upgrade.json` and `integration/evidence/2026-11-16-context-admission.json`.

Current-agent R/N/N/R passes all twelve jobs with exact requests and tokens. Historical fixed-input R/N/N/R varies within both native and reference; an instrumented diagnostic matches all 2,830 common mask prefixes but cannot clear the uninstrumented failure. The old/new pilot retains formula warmup failures in both versions. Candidate calculator authoring and repair fail independent outcomes. Full performance cohorts, engine promotion and the task-quality matrix remain blocked by the preregistered gates. No speedup is claimed.

The selected invoice business case passes. Stock initially failed its sixth conversational action with maintenance disabled in the harness. The corrected harness uses production defaults; a separate unchanged-program replay passes at 32K after one checkpoint, including the price update, 18 invalid-input cases, growth beyond 200 rows, duplicate protection, Undo/reopen and portable copy. This is replay evidence, not a fresh generated-app cohort.

Startup-only tests admit 32K, 64K and 128K at 12 GiB, with decreasing resident target weights. 32K/24 GiB also admits; two remaining 24 GiB cells were refused by conservative instantaneous headroom and remain untested. All four started helpers release and are reaped. Capacity is not useful-task qualification. Retain 32K/12 GiB; no automatic growth or larger product profile is enabled. Full local checks pass, followed by a fresh package/install/extraction pass and bounded isolated native UI verification. Both Stop controls, recovery to correct calculations and saved conversation reopening pass. A misleading completion footer was fixed and verified in the final build. Exact containing-commit hosted Checks remains a publication gate; no successful build can clear the failed behavior gates. The installed preview and all its preferences remain untouched.
## Execution order

- P0: preserve source/binary/resource identity, current failures and frozen workload contracts.
- P1: exact-scope/common request preparation, mode-aware reserves, CPU preflight and admitted capacity on the existing engine.
- P2/P3: protocol 13/status 8 and 1.6.1 adapter/behavior/parity qualification at matched settings.
- P4/P5: controlled context/memory experiments, held-out confirmation and final policy selection.
- P6/P7: native UX/recovery, complete final checks, package/install identity, commit/push and rollback proof.

## Earlier qualification blockers
1. Historical same-engine repeatability fails within both native and reference workers despite equal input bytes and matching common-prefix masks. Engine promotion and full qualifying cohorts remain blocked. The unchanged upstream numerical engine has not been patched or qualified by instrumented diagnostic passes.
2. Candidate calculator creation and repair fail independent outcomes. The old/new pilot retains a formula failure in each engine. The useful-task context sweep and larger/precision profiles remain gated; retain 32K/12 GiB without claiming a global optimum.
3. Exact containing-commit hosted Checks is required at publication. Local broad checks, final native package/setup/install/extraction and bounded UI recovery pass. The remaining full P6 phase-specific cancellation timings are unqualified, and the installed 1.4.1 preview remains unchanged.
## Evidence

Initial local build artifacts and originals are retained under the ignored `.build/inference-context-20261116` directory. Public synthetic receipts will record portable source, artifact and configuration identities without private local paths. Earlier evidence remains at its original frozen identities and is not relabeled as proof of this implementation.
Final local suite: `bash scripts/check.sh`, exit 0. It ran before the final one-line ordinary-chat completion footer correction; unchanged functional evidence is reused. Its stale preserved-baseline packaged journeys were explicitly skipped. Fresh native build, package/install/extraction checks after the footer correction all pass. Hosted Checks must build and verify both packages on the exact containing commit. The public upgrade receipt records log hashes and changed source hashes, rather than inferring source identity from app names or timestamps.

Isolated native evaluation main UUID `50067097-3466-35AF-B1C3-00D75F9D1BB9` matches the final package. Its separate bundle identity requires re-signing; unsigned executable code, all resources/helpers and installed CLI match. Two cancellations are saved, 17 × 19 = 323 and 23 × 7 = 161 are independently verified through calculator receipts, and all four runs survive reopening. Final UI shows Response ready. Normal/compact layout proof is from the prior same-UI build; only the footer changed. SQLite and CLI integrity pass; synthetic supplier rows remain unchanged. The evaluation app is closed and its helper reaped. Original preview UUID `A4AF21E2-1B9E-3757-B8F2-091C630658FD`, executable bytes and complete preference domain are unchanged. No user workbook, model weights, original app grant or schedule was modified.

The final result is a committed candidate implementation with a documented negative qualification result. P0/P1/P2 are complete; P3/P4 and broader adoption remain open. P5 follows the plan's conservative no-change path, and P6 has bounded UI/lifecycle proof with explicitly untested timing cells. Do not mark the whole plan accepted or install the candidate over the preserved preview merely because CI passes.