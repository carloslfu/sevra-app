---
type: db-md
updated: 2026-11-12T21:20:51.237726+00:00
owner: Carlos Galarza
scope: project
---
# Sevra app knowledge

This public, independent store owns Sevra app specifications, design, research,
decisions, implementation plans and verification. A checkout is sufficient to
understand the project. No private brain, website repository or local absolute
path is required. User workbooks are separate SQLite document packages.

## Agent instructions

Read `dbmd spec` and this document, then [[records/overview/start-here]].
Use dbmd 0.14.7 or later with JSON output for content and catalog maintenance.
Preserve source evidence. Keep current decisions coherent in records and append
verification results with exact commands and limits. Do not label a target as
implemented or tested until its acceptance check passes. Use full store-relative
wiki-links. Never publish credentials, personal data or real customer fixtures.
Code belongs in Sources, tooling in scripts, synthetic examples in examples.
Follow [[records/specs/distribution]] for pre-1.0 compatibility: no old development
schema/API preservation until the first notarized production-ready 1.0 release
actually distributed for production use. Update canonical schemas/interfaces and
recreate selected disposable fixtures. Test deployments/previews/tags do not
activate support. Current-format integrity and history remain required.
Follow [[records/specs/persistence-readiness]] for the new local persistence
foundation: complete saved changes, causal identities, deterministic reconstruction
and accurate decision provenance. Cloud sync, transport, replica coordination and
a new conflict resolver are outside this requirement. The implemented foundation
now extends through [[records/specs/managed-datasets]]: reserved core tables and
registered native dataset projections over shared immutable authority. Record and
reconstruct logical schema changes within the same capture/apply path. The next deliverable follows [[records/specs/mvp-delivery]]: one complete native
supplier-comparison journey and coherent install/setup, then MVP 0.1 test preview.
Finish only a coherent in-flight checkpoint. Further E2-E6 and new automation,
condition/dataset/background infrastructure are deferred; preserve safeguards.
The owner's October 29 follow-up now authorizes the sequential minimum usable
increments in [[records/operations/minimum-feature-delivery]], superseding the
blanket follow-up deferral above. Test and polish one coherent increment before
advancing. Later rows and external qualification gates remain unfinished.
The November 12 code-only instruction was followed by [[sources/notes/2026/11/accessibility-headless-tests-and-pause]],
which authorizes one headless logic/storage test-and-fix checkpoint for all ten accessibility
changes. That checkpoint passes 22 behavioral and 10 static adapter groups, plus native
compilation, and returns to paused. Actual UI/OS accessibility remains unqualified.
Do not open/install the app, manipulate the UI, toggle VoiceOver, inspect accessibility trees
or change system settings. The headless authorization does not create a standing test loop.
That was the earlier accessibility checkpoint. The later explicit native-engine request
and the owner's “Allow app installation and UI testing” answer in
[[sources/notes/2026/11/programmable-native-engine]] authorize implementation,
installation and native UI verification for [[records/plans/programmable-native-engine]].
The earlier no-UI restriction is superseded for this task; VoiceOver and system-setting
changes remain outside its scope. Use [[records/operations/agent-handoff]] for current status.
Model SQL never runs on the workbook file. It runs on a scratch copy, and a table's rows or
shape change only through the recorded write path, with Undo
([[sources/notes/2026/11/general-tools-answers]]). No parallel ledger or claim that local
replay solves replication.
All maintained product/engineering prose belongs here; root documents are brief
entry points. Finish changes with the relevant checks and a commit. Plain copy,
no em dashes, native controls, purposeful visuals and light/dark accessibility.

## Policies

### Blocking warnings
- all

### Validation log kinds
- design
- implementation
- verification

## Schemas

### note
- told_by (required, string)

### spec
- title (required, string)
- status (required, enum: proposed, reviewed, implemented)

### review
- title (required, string)

### research
- title (required, string)

### operational
- title (required, string)
