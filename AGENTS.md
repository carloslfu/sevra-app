# Sevra app

This is the open-source native local-AI workbook app, separate from Sevra's
website service and Slotstream's app/engine. Read db/DB.md and
[Start here](db/records/overview/start-here.md) before changing the project.

Before work, read the [checkout context](db/records/operations/agent-handoff.md#checkout-context)
in the handoff. If this repository is nested in a local workspace and
`../AGENTS.md` exists, read it and its checkout/recovery notes. That context is
optional for standalone clones; this public repository remains self-contained.
Keep machine-specific paths and private recovery evidence out of tracked app files.

## Public product language

The owner’s [November 17 launch-copy direction](db/sources/notes/2026/11/readme-launch-wording.md)
supersedes the older MVP label in current public copy. Call the product Sevra or
Sevra Workbook. Describe the current Mac source preview and its actual setup and
feature limits without implying a production release. Preserve historical labels
in dated evidence and compatibility anchors. Follow the
[README copy review](db/records/reviews/readme-launch-copy.md) for the four product
distinctions, claim boundaries and publication checks.

## Engineering and verification

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
accepted for their scope. The November 11 fixes and November 12 live automation checks
passed their scoped functional verification. Work is now paused. The owner selected an
[adversarial static accessibility review](db/records/reviews/accessibility-static-review-2026-11-12.md)
and then authorized [all ten code fixes](db/sources/notes/2026/11/accessibility-code-fixes-and-pause.md).
Those fixes are implemented, compiled and covered by the later owner-authorized
[headless checkpoint](db/sources/notes/2026/11/accessibility-headless-tests-and-pause.md):
22 behavior groups and 10 static adapter groups pass. UI/OS accessibility remains
unqualified. The handoff preserves results and the
[known-limit closure plan](db/records/plans/known-limit-closure-2026-11-12.md).
Work is paused after commit/push; the narrow headless check does not authorize continued work.
Do not manipulate the UI, launch/install the app, inspect accessibility trees, use VoiceOver or
change system settings unless the owner explicitly changes that decision. A general resume
does not revoke it. The later [native-engine request and explicit installation/UI approval](db/sources/notes/2026/11/programmable-native-engine.md)
supersede the pause and no-app restriction for the [native engine implementation](db/records/plans/programmable-native-engine.md).
Installation and UI tests are authorized for that task; VoiceOver and system-setting
changes remain outside scope. External use, signing and hardware qualification remain open.
The subsequent [local-model mini-app request](db/sources/notes/2026/11/local-model-native-apps.md)
continues that installation/UI authorization for the
[native authoring integration](db/records/plans/local-model-native-apps.md), with the same boundaries.
The November 13 [single Excel import request](db/sources/notes/2026/11/single-excel-import.md)
continues those boundaries for [workflow conversion](db/records/plans/single-excel-import.md),
including native visual testing, business cases and adversarial review. The later
[Excel application reconstruction request](db/sources/notes/2026/11/excel-application-reconstruction.md)
authorizes deeper source understanding, constrained behavior translation and original-result
comparison under its [plan](db/records/plans/excel-application-reconstruction.md). The owner
resumed that work after its temporary stop; the same installation/UI boundaries apply. The current
handoff distinguishes this work from the historical pause and earlier authoring trials.
The owner's subsequent [whole-app adversarial review request](db/sources/notes/2026/11/app-engine-adversarial-review.md)
extends the work through the [app and engine review](db/records/plans/app-engine-adversarial-review.md),
with the same installation/UI authority and preserved VoiceOver/system-setting boundaries.
The owner's November 18 [general chat tools authorization](db/sources/notes/2026/11/general-tools-implementation.md)
authorizes implementing the [general chat tools plan](db/records/plans/general-chat-tools.md)
end to end, phase by phase on its exit criteria, with the real-model runs, development
packaging, installation and interface checks those exits require and the same VoiceOver and
system-setting boundaries. His later [answers](db/sources/notes/2026/11/general-tools-answers.md)
settle four points: model SQL may change a table's shape through the recorded write path,
format changes for this plan need no compatibility work, the header work is paused until the
tools are done, and `sql` keeps 15-digit numbers. Build it with the plan's fast loop. Do not
push or publish a release for it without the owner's word.
Test enough, as the [owner asked](db/sources/notes/2026/10/ship-with-enough-testing.md): the real
failure and one counterexample, with the suite and install once on the candidate.
Work directly on `main`, with no feature branch or pull request. Run `dbmd index rebuild` before
the suite, because its last step validates the records.
Cloud sync, transport, replica coordination and a new resolver are out of scope.
Preserve unrelated changes. Do not change the website business or Slotstream
repository as a side effect. Keep public claims tied to measured acceptance.

## Interface quality

The owner explicitly requires deep visual and functional review of interface work.
Inspect spacing, alignment, density, hierarchy, empty/loading/error states, native
keyboard behavior and constrained-window layouts, not only compilation or saved
data. Fix observed issues and inspect the result. This task has explicit app/UI
authorization; VoiceOver and system-setting changes remain outside scope.

## Native UI Catalog maintenance

The owner's [end-to-end catalog implementation request](db/sources/notes/2026/11/native-storybook-implementation.md)
authorizes the isolated developer app and its focused native visual/functional
verification. Read [Native UI Catalog](db/records/operations/native-ui-catalog.md)
when changing UI, navigation, Home/space components, mini-app protocol/SDK, visuals,
chat interactions or their lifecycle. Update the matching registry/fixture in the
same change; add a bounded state/composition for new capabilities. Exercise the
production path and one nearby refusal. Separate registration, rendering,
interaction evidence and visual review; never count an early-exiting runner as a
pass. Keep fixtures, scripts and controlled services out of normal packaging and
the shipped agent's prompt/tools. Do not open an active user workbook, download a
model, start product schedules or change OS settings for catalog checks.
