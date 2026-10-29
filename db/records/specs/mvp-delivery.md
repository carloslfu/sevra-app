---
type: spec
id: 01m64d0z6f9sj5c9pwzx5mr7k4
created: 2026-10-29T17:58:47.247749+00:00
updated: 2026-10-29T17:58:47.247749+00:00
summary: 'Owner-directed fast MVP: one complete native file-to-result journey, focused verification, coherent setup and deferred infrastructure.'
title: Fast MVP delivery
status: reviewed
---
# Fast MVP delivery

## Controlling delivery decision, October 29, 2026

The owner requests a useful MVP very quickly, with enough verification to be good,
then continued development. This decision changes delivery order, not the long-term
product vision. This record controls the next deliverable wherever older plans say
to finish E2-E6, every expanded specification, or all production release gates first.
Those specifications remain the roadmap. Unfinished work is deferred, not completed.
The concrete slice below is the implementation plan derived from that decision.

The promise: bring business files, ask questions, get checked numbers, and keep a
useful result in a private, portable workbook. Optimize time to that complete job.
Do not restart the architecture, engine integration, UI, or working test systems.

## One complete customer journey

Use a small synthetic supplier-quote comparison as the first acceptance scenario:

1. Launch the native app, create a workbook, and include a supplier CSV and a
   searchable quotation PDF. Clearly show when extraction/indexing is ready or fails.
2. Ask what the suppliers offer. Answers cite the included evidence and open the
   relevant content. Missing facts remain missing; retrieved instructions are data.
3. Compare equivalent quantities and costs using deterministic computation. Show
   assumptions such as whether shipping or tax is included. Ask only when ambiguity
   prevents a useful, correct answer. Do not invent equivalence or an all-in price.
4. Save a useful native comparison table/chart or report in a space. Change one
   supported structured input, see the calculated result update, and verify Undo.
5. Close and reopen the workbook. Evidence, conversation, saved result, edits and
   provenance survive. Export a portable copy and open it offline with those same
   files and results. Copied workbooks acquire no execution permissions.

Reuse existing synthetic fixtures, demo data, native components and workflows.
Exercise actual file intake, not only an already populated demo. The existing
inventory example is useful but is not a second mandatory automation project.
Start by running this journey and listing observed failures before adding features.

## Required experience

- Keep the current two panes: one main conversation and composer, plus workbook
  spaces with Home and saved results. Keep the existing Sevra identity and native
  appearance. Make the next useful action obvious; no layout redesign is required.
- Text completes the whole journey. Retain existing voice input and honest on-device
  availability/permission handling; blocked dictation must leave text usable. Verify
  the delivered voice path once where available, without a new speech-engine project.
- Include imported assets inside the workbook and outside SQLite by default.
  Explicit external links stay explicit. Preserve originals and show supported
  extraction/editing limits. CSV and searchable PDF are the required intake formats
  for this slice; do not turn existing XLSX saved-value import into a fidelity claim.
- Use existing bounded filename/FTS/structured retrieval, source reads and citations.
  No new embedding or generalized search infrastructure is required unless an actual
  journey failure demonstrates the need. Unprocessed content is not negative evidence.
- Use the existing Python-free native Splash candidate and qualified model setup.
  Reuse installed compatible weights. Show missing-model, progress, failure and
  cancellation states; deterministic workbook operations work without inference.
  Keep Slotstream independent. No upstream upgrade or port rewrite for this MVP.
- Keep deterministic calculations, saved results, normal edits and reversible review.
  Consequential business changes require the existing explicit review boundary.
  Keep source/record lineage and actual/estimate/plan distinctions in the core.
- Provide one correct build/install/launch route for the native MVP, with matching
  app, CLI, extraction helper and engine resources. The current baseline-only
  installer/native-output mismatch is a delivery gap to resolve. Reuse safe
  installation behavior rather than introducing an installer framework.
- Put exact prerequisites, first launch, model storage/download requirements,
  one example task and honest limitations at the front of the quick start.
  Existing CLI and skill remain available; no new harness adapter is required.

## Deferred from this MVP

Do not add new condition/dataset triggers, background helpers, folder monitoring,
automation graphs, template catalogs, or further causality infrastructure. Preserve
what already works and finish a coherent in-flight checkpoint. Park unfinished work
separately. Do not make those features necessary to complete the first job.

Full Excel formula/layout/pivot/macro continuity, arbitrary generated executable
extensions, specialist decision models, cloud/sync/collaboration, other platforms,
new semantic-index systems, broad hardware certification, upstream engine parity
and 100-150 token/second targets are later work. Existing capabilities may stay,
but their expansion does not block this slice. No unsupported speed/device claim.

## Enough verification

Preserve current-format data integrity, originals, truthful evidence, deterministic
numbers, explicit authority and offline/local behavior. A reproducible data-loss,
incorrect-calculation, invented-evidence, or unintended-execution bug is a blocker.
Do not remove safeguards or weaken assertions to make a preview pass.

For each fix, check the actual failure and one relevant counterexample. Reuse
unchanged evidence. Run the complete journey once on the final native candidate,
including a real local-model interaction and visible UI. Check a missing-evidence
case and a relevant failure/cancellation path without losing saved work. Verify
installation, close/reopen and portable export/reopen using disposable fixtures.
Confirm the main path is usable with keyboard and its actual displayed appearance;
defer a whole-app accessibility/media/device certification program.

Run the existing required integration/release checks, including `scripts/check.sh`,
at the candidate milestone, not after every small edit. Triage a failure as an MVP
blocker, a genuine regression to fix, or an explicitly deferred requirement with an
honest release limit. Never silently skip a failing assertion. Do not invent a new
test framework or repeatedly rerun unchanged engine/resource qualification.
Keep evidence brief: candidate commit/build, commands, observed outcomes and limits.

## Delivery order and stopping rule

1. Run the journey with the current native build. Maintain at most three active
   blockers in the progress record, with other findings in a deferred backlog.
2. Fix those concrete gaps, including coherent native install/setup and a usable
   first-run path. Prefer existing implementations over new abstractions.
3. Freeze the candidate, perform the checks above, and deliver a clearly scoped
   MVP 0.1 test preview with a concise quick start and reproducible example.
4. Let an external user attempt the job. Use actual friction and task completion
   to choose the next work; the next roadmap item is not automatically mandatory.

When the journey, core quality checks and usable installation route pass, ship the
preview. The complete long-term specification is not its acceptance checklist.
Production 1.0 notarization and broad supported-hardware claims remain separate.
Label ad-hoc/source builds accurately and use a documented supported install path;
do not disable Gatekeeper or describe an unverified public installer as ready.
If a distribution credential is unavailable, name that limit and complete all
independent product work instead of beginning unrelated infrastructure.

## Related specifications

[[records/specs/product]]
[[records/specs/storage]]
[[records/specs/search]]
[[records/specs/intelligence]]
[[records/specs/contextual-import]]
[[records/specs/distribution]]
[[records/specs/native-app-engine]]
[[records/operations/implementation]]
