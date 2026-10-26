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
