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
and accurate decision provenance. The next deliverable is the owner-directed [fast MVP](db/records/specs/mvp-delivery.md):
run the native supplier CSV/PDF to cited comparison, saved result, edit/recalculate/Undo,
reopen and portable-copy journey first, fix observed blockers, then ship MVP 0.1 test
preview. Finish only a coherent in-flight checkpoint. Further E2-E6, condition/dataset/
background infrastructure and full engine/hardware/release research are deferred.
Existing safeguards, history and current-format integrity remain required. Keep at
most three active blockers in the progress record and reuse unchanged proof.
The owner's October 29 follow-up now authorizes the ordered
[minimum feature increments](db/records/operations/minimum-feature-delivery.md).
This supersedes the blanket follow-up deferral above. Complete a bounded usable
increment, test and polish it, then advance; later rows remain queued. Preserve
the existing integrity and authority boundaries and report qualification limits.
The current checkpoint is documented in the
[agent handoff](db/records/operations/agent-handoff.md). Increments 1 through 9 are
accepted for their scope. Increment 10 still needs its window pass, and an external user is next.
Test enough, as the [owner asked](db/sources/notes/2026/10/ship-with-enough-testing.md): the real
failure and one counterexample, with the suite and install once on the candidate.
Cloud sync, transport, replica coordination and a new resolver are out of scope.
Preserve unrelated changes. Do not change the website business or Slotstream
repository as a side effect. Keep public claims tied to measured acceptance.
