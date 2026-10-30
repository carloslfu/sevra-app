---
type: operational
meta-type: operational
id: 01m659x4nd2q89tkpzzsssd7yr
created: 2026-10-30T02:23:30.477380+00:00
updated: 2026-10-30T03:04:42.307148+00:00
summary: 'Resumed minimum features: increments 1 through 5 accepted; increment 6 qualified conversation continuation is next.'
title: Paused minimum-feature agent handoff
---
# Paused feature implementation: agent handoff

## State and first action

**Resumed by the owner on October 29:** [[sources/notes/2026/10/minimum-features-resume]].
Increments 1 through 5 are accepted for their bounded scope, with native build 23
installed. Increment 6, qualified bounded conversation continuation, is next. Exact
evidence and limits are in [[records/operations/implementation]], the
[reviewed-update receipt](../../../integration/evidence/2026-10-30-reviewed-updates.json.gz),
the [bulk intake receipt](../../../integration/evidence/2026-10-30-bulk-intake.json.gz) and
the [Excel formula receipt](../../../integration/evidence/2026-10-30-excel-formula-subset.json.gz).

The earlier pause source is [[sources/notes/2026/10/minimum-features-pause]]. The
sections below keep the paused checkpoint detail; where they conflict, this section
and the resume order at the end are current.

The public repository is `carloslfu/sevra-app`. All in-flight code, tests and docs
are preserved on branch `codex/sevra-minimum-features-handoff`, based on `170efa0`.
This is an unfinished checkpoint, not a release. Main remains at the prior audit.
Read `AGENTS.md`, [db/DB.md](../../DB.md), [[records/overview/start-here]], this handoff,
[[records/operations/minimum-feature-delivery]] and
[[records/operations/implementation]] before making changes.

**Start by finishing and verifying increments 1 and 2. Do not jump to increment 3
or restart the project.** Increment 1 has a successful actual CSV/PDF case but a
remaining pricing-language counterexample. Increment 2 compiles and passes native
component checks; its last visual refinements have not been installed or inspected.
Nothing in increments 3 through 10 was implemented during this checkpoint.

## Goal, architecture and boundaries

The owner wants one minimum usable feature at a time, tested and polished before
advancing. The ordered ten-part queue is in
[[records/operations/minimum-feature-delivery]], with the full historical feature
matrix in [[records/reviews/design-feature-audit]]. That direction supersedes the
earlier blanket follow-up deferral in the fast-MVP plan. Keep at most three active
blockers and preserve the successful supplier walkthrough.

Sevra is a native local-AI workbook: Swift/SwiftUI/AppKit, shared Swift core and CLI,
SQLite state/history/lineage, and every file asset outside SQLite inside its workbook
unless explicitly linked. Preserve Sources/Records, meaning separate from acceptance,
immutable versions, deterministic calculations, reviewed mutations, original evidence,
truthful search limits and user-owned portable workbooks. Splash remains the pinned
Python-free Swift/C++/Metal integration with Qwen3.6-35B-A3B and DFlash2. Do not change
the engine, model, Slotstream or website repository as a side effect. No cloud,
telemetry, transport, new resolver or arbitrary generated executable plugins.

## Increment 1: code and remaining issue

Changes are in:

- `Sources/SevraCore/RequestEvidence.swift` and `Tools.swift`: the first current
  original read in a request can surface at most two exact FTS-selected passages
  from other current file originals. Selection uses up to 24 request terms with
  bounded prefix-OR retrieval, a two-second budget, current/ready/partial filtering,
  exact version IDs/locators and explicit partial coverage. Historical, unrelated
  and unprocessed fixtures are excluded. A discovery deadline preserves the requested
  read with a limit notice; parent cancellation still propagates.
- `Sources/SevraAI/WorkbookAgent.swift`: only complete related passages actually
  visible to this run become citeable. Omission descriptors and metadata are not
  evidence. `StructuredValueView.swift` shows the passages as a related-originals
  disclosure with source links, not JSON.
- `Sources/SevraAI/DiscoveryBudget.swift`, `WorkbookInference.swift` and the shared
  agent loop: after three consecutive search/history-search results without a new
  candidate, an explicitly read-only answer with inspected evidence enters
  `boundedAnswer`. Further lexical searches are masked out; reads, calculation and
  finish remain. New candidates reset the counter before it fires. This is a limit,
  not complete coverage or an absence claim. Evidence-recovery scopes retain precedence.
- `RequestRestrictions.swift`: recognizes the exact combined denial “do not change
  or save anything” and its contraction. It does not classify all natural language.
- `IntegrationTests/Agent/RelatedOriginalChecks.swift`: missed-supplier regression,
  exact visible citations, projected omission refusal, historical/unrelated/partial/
  failed extraction, cancellation, unchanged business state and stalled-search
  completion. A new focused `--related-original-checks` flag is registered.

The original request was:

> Compare Atlas and Brio for 100 brass M6 bolts. Include goods, shipping, delivery and tax terms, and say which quote is cheapest. Cite the included files. Do not change or save anything.

Retain the failed iterations. The first augmented read correctly surfaced Brio's
PDF, but the model kept searching for a separate Atlas quotation and exhausted
12 steps. A retry completed but used insufficiently qualified cheapest wording.
Prompt changes alone repeated the search failure. The host budget and exact
read-only denial recognition were then added.

Final bounded actual-model results, using fresh synthetic workbooks:

- CSV plus PDF: completed in 11 steps, cited both originals, calculated known
  goods-plus-shipping costs of USD 130 and 135, included Brio's 5-business-day
  delivery and excluded tax without a supplied rate. It explicitly says final
  all-in cost/ordering cannot be determined. Business items unchanged; integrity passes.
- CSV without PDF: completed in 9 steps and invented neither delivery nor tax.
  **Still says “Cheapest quote: Atlas at 130.00” and labels both amounts “Total”.**
  Its later missing-terms paragraph says those costs cannot be determined, but the
  equally explicit all-in qualification is absent. Fix/test this counterexample
  before calling increment 1 accepted. Do not weaken grounding, citation or currency
  checks or silently claim a universal semantic validator.

These are two functional probes under concurrent development load, not an accuracy
rate or speed benchmark. The new search budget applies to recognized explicit
read-only requests; ordinary questions without that denial remain unqualified.
The lexical related-original selector is bounded discovery, not guaranteed semantic
retrieval across all languages, short names, files or document sizes.

## Increment 2: native tables and exact remaining checks

Changes are in:

- `ConversationBlocks.swift` and `ConversationPresentation.swift`: parse top-level
  Markdown tables with the existing pinned CommonMark dependency. Preserve original
  prose and destinations. Fenced examples stay text. No saved Records are created.
- `ReadOnlyTableView.swift`: native AppKit grid, read-only cells, multi-row selection,
  Command-C as TSV plus rich HTML/typed cells, context Copy with headings and Copy as
  CSV, row source-link actions, scrolling and bounded inline height. Tests use an
  independent clipboard. `Package.swift` reuses existing Markdown and TableUI products;
  it adds no new package version.
- `DelimitedPreview.swift` and `Viewers.swift`: original CSV/TSV grid without auto-import,
  exact textual values and leading zeros, quoted/multiline cells, first row as headings,
  a 1 MB read and 1,000-data-row display limit, complete-record truncation, cancellation
  and explanatory failures. Original File actions remain available.
- `ConversationViews.swift`: render table blocks, trim display-only block-edge newlines
  and add Copy message. Stored original message text is unchanged.
- `IntegrationTests/Preview/ReadableTableChecks.swift`: parser/literal/fenced/link cases,
  leading zeros, TSV decimal commas, ragged/quoted/multiline/large/malformed data,
  cancellation, actual AppKit selection, TSV/rich copy, CSV/headings context actions,
  source menu items and native cell accessibility.

Actual installed build-4 UI showed a real comparison grid and original CSV grid.
It exposed excessive block-edge whitespace and a 3-column comparison forcing one
supplier offscreen. Latest build 5 adds newline trimming, uniform column sizing,
content-derived inline height and explicit accessible cell roles/values.
**Build 5 has not been installed or visually checked.** Check narrow/wide panes,
all common comparison columns, wrapped values, horizontal/vertical overflow, row
selection, context CSV/cell copy, source navigation and accessible values. Avoid
clipped rows, phantom extra rows, excessive blank space or unrequested extra controls.
The last successful component run still has one harmless redundant-cast warning in
`ReadableTableChecks.swift`; clean it up during the final pass.

## Verification and local artifacts

Completed successfully:

- `.build/debug/sevra-agent-checks`, full scripted agent regression, exit 0;
  `.build/minimum-agent-regression-2.log`.
- `swift run -j 4 sevra-agent-checks --related-original-checks`, exit 0;
  `.build/related-original-checks-bounded-2.log`.
- `swift run -j 4 sevra-preview-checks`, exit 0 after the final table changes;
  `.build/minimum-preview-checks-4.log`.
- Five `bash scripts/build_native.sh` iterations; latest build 5 exits 0;
  `.build/minimum-native-build-5.log`.
- Build-4 `bash scripts/install.sh --native --no-build`, exit 0;
  `.build/minimum-native-install.log`.
- Earlier build-1 package paths-only/refusal/signature checks pass;
  `.build/minimum-native-package.log`. This is not a build-5 package receipt.
- Most recent dbmd full validation and repository link gate pass with zero issues.

**`bash scripts/check.sh` was explicitly stopped on the owner's pause, exit 143.
It is incomplete, not green.** Its last output was in the inventory/condition
checks. Log: `.build/minimum-features/full-check.log`. No test, inference probe,
build or automation subprocess from this task remains running. A previous full
suite passed at audit code head `5f55035`, before these source changes.

Portable tracked evidence:
[paused checkpoint receipt](../../../integration/evidence/2026-10-30-paused-minimum-features.json.gz),
SHA-256 `7a285eaabaeb2ef82e7f6512a441bdedfa1a7334aaae1ec7f583144bdfc0d3b0`.
It binds source/test hashes, completed check output, the interrupted suite, raw
synthetic actual-model results and failed iterations. Public paths are sanitized.
It is an unfinished checkpoint receipt, not release qualification.

Ignored local fixtures and probes remain under `.build/minimum-features/`:
`probe.py`, `revised-probe.py`, `bounded-probe.py`, `initial-failures.json`,
`bounded/evidence.json`, earlier failed outcomes and separate `.sevra` test packages.
These do not travel in Git; the tracked receipt preserves their important results.
Use new synthetic paths for reruns rather than overwriting failed history.
`examples/supplier-quotes.csv` and `examples/Brio-quotation.pdf` are reproducible inputs.

Installed app is `~/Applications/Sevra Native Preview.app`, build 4.
Latest build artifacts are under `output/native/`, build 5.
Use `output/native/bin/sevra` for the latest packaged CLI or the correctly installed
`~/.local/bin/sevra`. **Bare `sevra` resolves an unrelated retired Cloud CLI.**
Do not modify the real Documents/Supplier test workbook. The current app window
shows the synthetic `.build/design-audit/Comparison.sevra` original CSV. No original
business data, microphone permission or model download was changed in this checkpoint.

## Continuation result, October 29

The missing-terms counterexample is fixed by `Sources/SevraAI/CostQualification.swift`,
called from the finish validation in `WorkbookAgent.swift`. It applies only when the
answer itself says a cost is unknown or missing. `RelatedOriginalChecks.swift` replays
the exact failing answer and the audit answer, checks qualified counterexamples and
runs a scripted correction with unchanged business state. Fresh actual-model probes
under `.build/minimum-features/qualified/` complete both supplier cases with qualified
wording; earlier probe folders stay untouched as failure history.

Offscreen renders exposed table sizing problems, now fixed in `ReadOnlyTableView.swift`:
content-aware widths (hug, whole-word minimum, then scroll for conversation tables;
fill, then natural widths and scroll for original files), measured row heights with
a padded container cell, six-line ellipsis, heading help text and persistent manual
column widths. `ReadableTableChecks.swift` covers these cases. Reproduce the renders
with `.build/debug/sevra-preview-checks --render-tables DIRECTORY`, where DIRECTORY
holds `.md` answers, `.csv`/`.tsv` originals or `.json` Excel formula reports; local
fixtures and PNGs are under
`.build/minimum-features/visual/snapshots/`.

The installed-window pass then ran on build 9 with synthetic workbooks under
`.build/minimum-features/gui/`; results and remaining limits are in
[[records/operations/implementation]]. Do not modify the real Supplier workbook.

## Resume in this order

The original order follows; all six steps are complete. Continue with increment 6 in
[[records/operations/minimum-feature-delivery]].

1. Check the branch/diff and read the contracts above. Preserve this work.
2. Fix the missing-terms pricing counterexample and rerun its focused actual-model
   case plus the full CSV/PDF case. Preserve exact outputs, unchanged-business-state
   checks and integrity. Do not mark a partial answer accepted just to advance.
3. Complete the native table visual pass. On this Mac build 5 is available; after
   any edits rebuild it, close the existing app cleanly and run
   `bash scripts/install.sh --native --no-build`. On a new checkout build first.
   Use the CUA tool for app interaction and scoped synthetic workbooks.
4. Run the focused agent/preview checks, latest package paths-only check and the
   full `bash scripts/check.sh` at the coherent release/integration checkpoint.
   Do not count the paused suite as passed or reuse old binary receipts for changed code.
5. Update this handoff, the progress register and minimum-feature sequence with
   exact acceptance/limits. Run `dbmd validate --all db --json`,
   `python3 scripts/check_links.py` and `git diff --check`. Commit the coherent
   changes and integrate the handoff branch according to the owner's working state.
6. Only then advance to increment 3: unambiguous mapping suggestions, persisted
   reviewed-update draft and bounded saved-value XLSX updates. Relevant entry points
   are `Sources/SevraCore/TableIntake.swift`, `TableIntakePublication.swift`,
   `Sources/SevraTableUI/TableUpdateSession.swift`,
   `Sources/SevraApp/TableUpdateView.swift` and `scripts/check_table_updates.py`.
   Acceptance and Undo remain explicit. Subsequent increments follow the existing queue.

The 100,000-row saved-change limit, saved-only XLSX formulas, disabled installed
context maintenance, longer-audio limit, broader automation/workflow scope and
hardware/signing/notarization gaps remain unresolved. No production-ready claim.
