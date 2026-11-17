---
type: review
id: 01m7nba1s3psnzbrvdcdm4tzgz
created: 2026-11-17T18:11:34.819878+00:00
updated: 2026-11-17T18:11:34.819878+00:00
summary: 'Implemented native catalog: 176 stories, real workbook/XPC paths, isolated services, ten compositions, native capture and scoped acceptance.'
title: Native UI Catalog implementation review
---
# Native UI Catalog implementation review

Authority: [[sources/notes/2026/11/native-storybook-implementation]]. Acceptance contract: [[records/plans/native-storybook]]. Developer and coding-agent instructions: [[records/operations/native-ui-catalog]]. The [portable acceptance receipt](../../../integration/evidence/2026-11-17-native-ui-catalog.json) records source/binary identity, counts and qualification limits.

## Delivered scope

A distinct native catalog build mounts the real main app, Home/ordinary spaces, programmable mini apps, chat and shared visuals. Its 176 entries include canonical nodes/components/styles/fields, secondary routes, states and ten business compositions. Unsupported product states and OS-owned surfaces have explicit limits. The native browser provides search, surface/level filters, bounded inputs, layout recipes, state selection, Reset, Replay, dedicated windows, configuration copy/load, PNG/metadata capture and evidence inspection.

SQLite workbook operations, validators, drafts/history, signed XPC workers and SDK actions are real. Inference, model setup, speech, file destinations, external opens and scheduler timers are controlled and visibly labeled. Each ordinary story owns disposable storage and preferences; the captured/live comparison intentionally shares one owning workspace. Teardown awaits cancellation, flushes drafts, closes workers and removes only the owned root. Normal builds exclude the Catalog directory. The developer package has no workbook document handler and is never installed over the ordinary app.

## Pass 1: capability and source consistency

Compared registration with canonical protocol/core enums, route inventory, SDK exports and actual renderers. Registered all 22 native nodes, 22 Home/component kinds, twelve chart styles, four work styles, five chat field kinds and six visual families. SDK helper/action inputs have executable examples and declaration checks. A declared image app view remains explicitly unsupported; images use the actual granted Image alias. Fixed invalid chart categories, definition identifiers, form function targets and missing action/ActionForm/viewID declarations. Nested SDK builds now ignore a parent TypeScript configuration; generated production bundles remain byte-identical to the baseline.

## Pass 2: authority and lifecycle

Verified table/Home mutation with stale refusal, actual ActionForm writes/invalid inputs/revocation, typed false and revision-bound draft submissions, exact approvals/duplicate refusal, persistence/reopen and captured-versus-current semantics. Fixed the owning-workbook connection and file-input lookup, pending-worker teardown, an early batch exit caused by the last window closing, and stale reviewed evidence after edits. Runners require an explicit terminal completion count; rendering alone never counts as interaction or manual visual approval.

The fixtures exposed a production Quick Look double close on unmount. SwiftUI now owns closing the preview view (`shouldCloseWithWindow = false`), and the viewer fixture passes teardown. No active installed app, user workbook, model setup/download, real speech permission or product schedule was used.

## Pass 3: native UX and evidence

Reviewed the actual isolated browser and representative production canvases. Corrected disabled replay readiness, configuration validation hidden behind its sheet, configuration restore losing inputs, compact workspace minimums and transparent capture backgrounds. Confirmed requested versus actual native dimensions, long labels, dark appearance and 150% reading size. Native ActionForm negative quantity is refused, a corrected save succeeds, Undo and Redo mutate real data, and subsequent edits invalidate a recorded visual review. Graceful Quit waits for owned sessions. The active user preview remains untouched.

## Verification and reuse

- `bash scripts/check.sh`: passed. Includes the SDK, core, signed native-app, preview/conversation, agent/grammar and repository/store gates. Existing freshness guards explicitly skip stale ordinary packaged UI journeys; these are not reported as executed.
- `SEVRA_NATIVE_CANDIDATE=1 swift build --scratch-path .build/catalog-product-check --product SevraDesktop -j 4`: passed. Symbol inspection confirms catalog browser/session/inference code is absent. No normal app installation or replacement was performed.
- `bash scripts/build_ui_catalog.sh`: passed with a distinct signed package, real workers/resources and verified executable build identity. Deep strict signature verification passes.
- `python3 scripts/check_ui_catalog.py --fixtures`: all 176 defaults passed in an uninterrupted run.
- `python3 scripts/check_ui_catalog.py --interactions`: all twelve interaction paths passed in the final focused run, including pending-worker teardown.
- `python3 scripts/check_ui_catalog.py --interactions --flows`: twelve interactions and all ten compositions passed; flows completed uninterrupted. They exercise first workbook, suppliers, inventory, projects, overview, evidence, Excel installation/comparison, interrupted drafts, workflow attention and captured/live/revoked surfaces.
- Sixteen additional bounded states captured successfully: compact ActionForm; draft record; decimal conflict; completed/failed workflow; ready Excel app; stale automation; grouped dark chart at 150%; cyclic diagram; eight-panel overview; corrupt/portrait images; invalid rich text; model-install presentation; long shell; long compact Home comparison. Invalid grid configuration is refused and a requested 360-point shell records its actual 740-point minimum.
- Native visual/functional review: browser/search/filter, Replay/Reset, configuration failure/restore, worker fail/reset, real form save/refusal/Undo/Redo, coverage and review invalidation, graceful Quit. Representative PNGs cover tables, typed chat inputs, mini-app controls, charts, diagrams, overview, images and constrained Home. A final capture-only opaque-background fix was built and verified on a real isolated table window.
- `swift format lint --strict --recursive Sources/SevraApp/Catalog Sources/SevraApp/AppHost.swift`, repository links, db.md validation and `git diff --check`: passed at finalization.

Unchanged default/flow evidence is reused after browser/evidence-only fixes. The final capture-only background change does not alter fixtures, services, actions or ordinary compilation. The portable receipt distinguishes the latest binary from prior semantic evidence rather than attributing every run to one binary. Hosted Checks is checked on the publication commit; local acceptance does not substitute for a failed hosted gate.

## Limits and maintenance

This is finite capability/state/composition coverage. It does not enumerate every arbitrary layout or visually approve every variant. Separate sheets/popovers, Quick Look/media layers and OS-owned behavior require live review. Actual-model reliability, VoiceOver/OS accessibility, additional hardware, performance under model load and signing/notarization for production distribution are unqualified by this work. There is no new pixel-baseline framework or broad model trial matrix.

AGENTS.md now requires matching registry/fixture changes when UI, schema, protocol, SDK, chat or lifecycle changes. Future agents should verify the changed production path and a nearby refusal, keep rendered/interaction/manual evidence distinct, and keep catalog code/data out of ordinary packaging and the shipped agent's prompt/tools.
