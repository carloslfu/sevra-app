---
name: update-splash
description: Update Sevra's pinned Splash engine and Swift integration, compare upstream changes, and qualify behavior and performance before adoption. Use for Splash upgrades or adapter maintenance in the Sevra app repository.
---

# Update Splash

Work from the Sevra app repository. Read `db/DB.md`,
[the integration contract](../../db/records/specs/splash-integration.md),
[the progress register](../../db/records/operations/implementation.md) and
`integration/splash.json`. The pin distinguishes a candidate from the engine
actually used by the shipped build. Keep that distinction throughout the work.

Fetch the pinned reference with `python3 scripts/fetch_splash.py`. It verifies
the source commit and release archive hash, and extracts only the native runtime,
kernels and licenses into the integration area. Python here is development
tooling, never a dependency of the installed app or its model setup.

For a newer release, inspect its source and release identity first. Record a
candidate pin with immutable commit and artifact digest. Compare it with the
last qualified version before changing the active runtime. Do not follow a
moving branch at startup or promote a release just because it is newer.

Follow the responsibilities in `integration/splash.json`: native protocol,
selected-model preparation, templates/tokenizer, output and tools, grammar
masks, resource lifecycle, packaging. Map changed upstream files to the Swift
counterpart and its checks. Add a mapping when a newly relevant surface appears.
Keep unsupported features explicit. Reuse Splash C++/Metal unchanged; do not
translate its inference engine, scheduler or memory governor into Swift.

For grammar changes, compare Splash's pinned LLGuidance requirement with
`integration/llguidance.json`. Keep the Rust grammar library unchanged behind its
C ABI. Check every token's byte vocabulary, added/special/padded token semantics,
both EOS tokens and complete speculative masks, not only parsed JSON. The C and
Python binding defaults have differed; a matching library version alone does not
prove behavioral parity. Preserve native build and transitive-license gates.

For output changes, regenerate the pinned streaming/projection fixtures. Compare
every decoded delta, UTF-8 bytes, special/padded-token behavior, stop cuts and all
marker split points. Preserve Sevra's explicit refusal of incomplete/duplicate or
unknown calls; permissive reference parsing must not grant workbook authority.
Require successful native completion and full schema validation before dispatch.

Check all actual workbook tool declarations, not only a small sample. Their
normalized fixture is compared with NativeTools.definitions by sevra-agent-checks.
Keep default-open nested objects explicit before strict normalization, so rows,
edits, named calculation values and record data retain their fields. Compare
required, automatic, named and reasoning grammar masks with the pinned reference.
Unsupported schema keywords must fail setup, never silently weaken validation.

Run the opt-in autonomous WorkbookAgent probe as well as forced-tool fixtures.
Preserve conversation review/acceptance state, citation and calculation checks,
truthful search coverage, native generated spaces and cancellation/lease recovery.
Review the [conversation continuity contract](../../db/records/specs/conversation-context.md)
when context, templates or memory planning changes. Exact rendered tokens must
include tool schemas/history. Keep output and tool-result recovery headroom,
original conversation receipts and current workbook authority through maintenance.
An engine accepting 32K or 64K is not a qualified context profile. Exercise occupied
contexts and complete jobs. Run --continuity for repeated compaction and portable
reopen, and --context-recovery for false digests, current acceptance, summary
cancellation and explicit retry. Preserve failed runs, not only final passes.
Recheck native helper shutdown on the serial worker; teardown must be bounded
and retain the model lease if the child has not been reaped.
The internal candidate boundary must not become a user backend picker. Keep the
production baseline until the packaging, performance and application gates pass.

Implement affected Swift behavior in small steps. Test protocol bytes against
the pinned upstream goldens, then exact prompt token IDs and parsed results.
Reference Python may run in an isolated evaluation environment. A Python-created
model folder is not proof that native Swift installation works.

Run the affected core and adapter checks, the real-model differential suite,
failure/cancellation/recovery cases and a clean installed-app workflow. Use the
matched conditions and adoption thresholds in the integration contract. Measure
first-token and complete-job latency, memory and failures alongside tokens/s.
Retain failed results. Removing Python does not itself establish a speedup.

Update the public db.md progress register and append its verification log with
commands, source/binary identities, evidence and remaining gaps. Promote only
after the declared gates pass. Preserve the previous qualified pin and evidence
so another agent can reproduce the comparison or roll back. No recurring update
job or unrelated service change is implied by this workflow.
