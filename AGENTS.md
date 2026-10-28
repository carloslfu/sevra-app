# Sevra app

This is the open-source native local-AI workbook app, separate from Sevra's
website service and Slotstream's app/engine. Read db/DB.md and
[Start here](db/records/overview/start-here.md) before changing the project.

Swift/SwiftUI/AppKit; shared Swift core and CLI. Adopt upstream Splash C++/Metal
through a Python-free Swift adapter. The current Slotstream build is a preserved
baseline until the [integration gates](db/records/specs/splash-integration.md) pass.
Use the repo-owned [update-splash skill](skills/update-splash/SKILL.md) for engine
upgrades. Keep the unchanged native engine separate from the Swift frontend.
Every file asset is outside SQLite inside the workbook unless explicitly linked.
Use deterministic calculations, immutable input versions, lineage, bounded
retrieval, and truthful completion. No hidden hosted model or telemetry.

Keep specifications and work records in this repo's db.md store. No private
paths, private repository requirements, credentials, or real business fixtures.
Use meaningful invariant/integration tests. Follow the owner-approved
[focused verification policy](db/records/specs/distribution.md#focused-verification-policy):
verify the actual fix plus a nearby counterexample, reuse unchanged evidence, and
reserve broad reruns for concrete boundary changes or integration/release milestones.
Run scripts/check.sh before release.

Before the first notarized, production-ready 1.0 release actually distributed for
production use, do not maintain backward compatibility for development schemas,
formats or CLI/agent contracts. Update canonical schemas/interfaces and recreate
selected disposable fixtures instead of adding legacy migrations/adapters. Test
deployments/previews/tags do not activate support. Preserve current-format integrity
and user data. The controlling policy is
[pre-1.0 compatibility](db/records/specs/distribution.md#pre-10-compatibility-policy).
The [persistence-readiness requirement](db/records/specs/persistence-readiness.md)
adds complete saved changes, causal identities, deterministic local reconstruction
and accurate decision provenance. Finish the active table-update slice, then build
this shared foundation before expanding durable workflow/automation storage.
Cloud sync, transport, replica coordination and a new resolver are out of scope.
Preserve unrelated changes. Do not change the website business or Slotstream
repository as a side effect. Keep public claims tied to measured acceptance.
