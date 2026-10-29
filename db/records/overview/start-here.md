---
type: operational
meta-type: conclusion
id: 01m5rbxz8vn3x44zb6n5k97y8q
created: 2026-10-25T01:48:47.259629+00:00
updated: 2026-10-29T22:25:44.274614+00:00
summary: Independent context, goals, specification, architecture and implementation order for the Sevra app.
title: Start here
---
# Sevra app

Sevra rethinks the work people do with spreadsheets: gathering messy information,
checking it, calculating, deciding, and explaining. The first audience hypothesis
is a small-business owner reconciling supplier quotes, purchases and inventory.
Mac-first is an implementation choice, not evidence that all such owners use Macs.
The success measure is a completed, explainable job with user-owned evidence.
Token throughput cannot replace correctness or useful interaction.

The product name is Sevra; Sevra Workbooks is a descriptive offer. This public
repository is `sevra-app` because the separate website business uses `sevra`.
Workbook is the primary product and homepage, with a small Websites navigation link
for the secondary service. Website pricing/support does not apply to this app.
Slotstream remains independent.

## Current preview and delivery order

MVP 0.1 is a native source test preview. The focused supplier journey has actual
native proof: include CSV/PDF, inspect a cited quotation summary, calculate a cost
column, save an existing table/chart, edit/recalculate/Undo, close/reopen and export/
reopen a portable copy. An independent installed-CLI check denies network and reads
of original files while verifying the actual native-exported copy.

Broad supplier questions can still miss a document or exhaust bounded tool steps.
The tested route uses a focused open-document question and a short saved-view
request. This preview does not establish unattended business accuracy, broad
hardware support, full Excel fidelity or production release readiness.

Start with [[records/operations/build-and-run]] for native installation, model setup
and the reproducible synthetic example. [[records/operations/implementation]] owns
current verification, exact source/binary receipts, hosted CI outcomes, active work
and limits. Earlier scoped checkpoints live there and in their owning specs; their
historical statuses must not override the current verification record.

The owner-directed [[records/specs/mvp-delivery]] controls delivery order. Ship the
coherent preview and let an external user attempt the job before choosing further
work. The expanded E2-E6, condition/dataset/background infrastructure and full
engine/hardware/release research remain deferred. The long-term design remains
intact; deferred requirements are not completed requirements.

## First user feedback

The owner began the supplier walkthrough on October 29 and found that the static
Thinking locally label did not communicate ongoing agent work. The implemented
[[records/specs/agent-activity]] replaces it with a shimmering real phase, elapsed
time, Stop and expandable saved searches/reads/results. The owner also requested
polished native content instead of JSON dumps: excerpts, tables, matches and
structured fields now share that presentation. This is observed MVP feedback,
not a reason to resume deferred infrastructure. Exact verification and retained
AI source-selection failures belong in [[records/operations/implementation]].

The follow-up [[records/reviews/native-journey-polish]] inventories the full native
journey and simplifies the existing surfaces: immediate reference capture without
a role modal, one Add files control, secondary workbook actions, direct Home,
contextual review, progressive filters/settings and cleaner empty/history/search
results. Explicit conversion, review and acceptance remain. Instructions in
[[records/operations/build-and-run]] reflect these current controls. Advanced
editors and broad AI source selection remain known limitations.

## Architecture

- The native app uses SwiftUI/AppKit. The Swift core also serves the independent
  CLI and repo-owned harness skill. The preview integrates pinned Splash C++/Metal
  through a Python-free Swift adapter. The prior Slotstream build stays a separate
  baseline until the native engine adoption gates pass.
- A `.sevra` workbook is a SQLite document package. Included original assets are
  ordinary files inside the package and outside SQLite. Explicit external links
  retain their distinct ownership and availability behavior. `.sevraz` is the
  portable copy format. Models remain outside workbooks.
- Sources capture original information, including human observations, decisions,
  rules and assumptions. Records derive from Sources or other Records. Meaning
  such as actual, estimate, plan or commitment is independent of that origin.
  Accepted business events, starting conditions and versioned rules reconstruct
  state; lineage identifies exact inputs and transformations without double counting.
- Deterministic calculations, immutable versions and captured changes preserve
  explainable results. Native Home/spaces are composable views over workbook data.
  One main conversation can have chapters and tangents. Consequential changes use
  explicit review; saved definitions and portable copies confer no device authority.
- Retrieval combines bounded filename/FTS/structured inspection with source reads
  and citations. Coverage and missing evidence remain visible. A model answer is
  not proof that all relevant evidence was examined. No hidden hosted fallback or
  in-app telemetry is used.

## Specification map

Read the product and storage contracts first, then the area you are changing:

- Product and native interaction: [[records/specs/product]],
  [[records/specs/identity]], [[records/specs/native-app-engine]],
  [[records/specs/intelligence]] and [[records/specs/conversation-context]].
- Storage, immutable history and managed data: [[records/specs/storage]],
  [[records/specs/persistence-readiness]], [[records/operations/persistence-coverage]]
  and [[records/specs/managed-datasets]]. Local reconstruction is not replication.
- Intake, evidence and documents: [[records/specs/contextual-import]],
  [[records/specs/search]], [[records/specs/references-and-relationships]] and
  [[records/specs/document-composition]]. Saved-value XLSX import does not establish
  the expanded Excel-continuity contract.
- Reusable computation, actions, forms and workflows:
  [[records/specs/application-definitions]] and [[records/specs/manual-workflows]].
- Existing automation foundations and their limits:
  [[records/specs/automation-schedules]], [[records/specs/automation-definitions]],
  [[records/specs/automation-planning]], [[records/specs/automation-execution]],
  [[records/specs/native-automation-owner]] and [[records/specs/condition-dispatch]].
- Existing event/condition history and causality contracts:
  [[records/specs/business-events]], [[records/specs/inventory-event-state]],
  [[records/specs/inventory-condition-consumers]], [[records/specs/condition-transitions]],
  [[records/specs/condition-transition-inputs]], [[records/specs/automatic-ancestry]],
  [[records/specs/business-provenance]] and [[records/specs/automation-causality]].
  These supporting specs do not change the current delivery order.
- Engine integration and distribution: [[records/specs/splash-integration]],
  [[records/specs/distribution]] and [[records/operations/build-and-run]].
- Research and design review: [[records/research/foundations]] and
  [[records/reviews/design-passes]].

## Development and evidence

All examples and test data are synthetic. No private brain, website repository,
credentials or real business data is required to understand this checkout. This
repo-owned db.md store is the authority for product and engineering knowledge.
The owner adopted the product direction; engineering choices remain open to
measured revision.

Use the focused verification policy in [[records/specs/distribution]]: verify the
actual fix and a relevant counterexample, reuse unchanged evidence, and run the
required broad checks at an integration/release milestone. Preserve failed runs
and exact limitations instead of turning a narrow pass into a general claim.

Development schema/format/API compatibility begins with the first notarized,
production-ready 1.0 release actually distributed for production use. Until then,
update canonical contracts and recreate selected disposable fixtures rather than
adding legacy adapters. Previews do not activate support. Preserve current-format
integrity, originals and user history. Cloud sync, transport, replica coordination
and a new resolver remain outside the current scope.
