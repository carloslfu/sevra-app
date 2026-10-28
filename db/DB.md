---
type: db-md
scope: project
owner: Carlos Galarza
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
reconstruct logical schema changes within the same capture/apply path. Finish a
coherent in-flight checkpoint, then establish E0-D before dependent E2/E3 storage.
No raw-model DDL, parallel ledger or claim that local replay solves replication.
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
