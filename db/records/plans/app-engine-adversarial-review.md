---
type: operational
id: 01m7bp9xnvfpsa888nq0t5q1rb
created: 2026-11-14T00:11:20.635993+00:00
updated: 2026-11-14T01:12:42.217155+00:00
summary: Multiple-pass review and fixes verified; explicit coverage and unresolved model-generation reliability
title: App and engine adversarial review
status: reviewed
---
# App, engine and mini-app adversarial review

Authority: [[sources/notes/2026/11/app-engine-adversarial-review]]. Continues [[records/plans/excel-application-reconstruction]].

## Method and coverage

Inventory owned Swift/TypeScript/C glue, bundled runtime, extraction, local inference, workbook persistence, native views, CLI and packaging. Track direct source review separately from automated coverage and upstream/vendor qualification. An inventory or passing suite is not a claim that every possible behavior or upstream line is proven correct. No universal security or full Excel equivalence claim.

Pass 1 traces untrusted inputs, execution isolation, resource bounds, native events, dataset access, transaction/Undo authority, copies and source comparison. Pass 2 uses counterexamples for state changes, stale events, invalid records, model errors and failure recovery; repair observed defects. Pass 3 integrates the candidate, runs relevant regressions and the full milestone suite, verifies exact installed identity and native visual behavior, records evidence and commits/pushes main.

## Active findings

- Reproduced: remounting a same-type field at the same path retained its old native edit revision and text. Added mount identity across SDK/wire/native renderer and stale-event fencing. Native regression and six SDK groups pass.
- Reproduced: ordinary multi-worksheet updates calculated intermediate states despite one atomic transaction. Deferred calculations to the final batch and normalize returned/Undo row versions. Focused verification running.
- Model-generated candidates copied a placeholder header guard and mishandled zero quantities/error return shapes. Generic authoring/review guidance and independent tests now cover them. Fresh Loan and Lookup trials pass expanded independent checks; prior failures remain evidence.

## Completion gates

- [x] Boundary and subsystem review, with explicit coverage and remaining limits.
- [x] Reproduced defects repaired and counterexamples passing.
- [x] Native reconstruction UI, examples, actions, Undo, reopen and compact layout verified.
- [ ] Final full suite, packaging/installation identity, records, commit/push and CI result.

## Final review findings, November 14

The [[records/reviews/excel-reconstruction-and-engine-review]] supersedes the initial active-finding progress above. The integrated suite passes 653 core checks and all 17 native groups; final authoring checks pass 36 groups. Native package/install/extraction and actual UI checks pass. New corruption/layout/canvas/reviewer-context/error-message counterexamples are retained with source/log hashes. Original examples now include zero interest, renamed lookup keys and invalid numeric input; reviewed derivatives pass while earlier candidates fail the expanded checks. The review is complete for its stated direct-source and automated coverage, not literally every vendor line. Local-model generation/review reliability remains open. Publication and hosted CI are tracked on the containing revision, separately from the local evidence.
