---
type: review
meta-type: conclusion
id: 01m654wp7eny7gt0nr2k6nshnf
created: 2026-10-30T00:55:52.814400+00:00
updated: 2026-10-30T00:57:36.715946+00:00
summary: Current feature coverage, fresh AI and scale failures, deferred design gaps and release qualification for the Sevra source preview.
title: Design-to-code and feature audit
---
# Design-to-code and feature audit

## Conclusion and scope

Sevra has a substantial working native workbook foundation and a focused source
MVP. The complete design is unfinished. Its most important product gap is reliably
turning ordinary business files and a natural request into a complete, useful,
editable result without coaching. More visual passes alone cannot close that gap.

This audit answers [[sources/notes/2026/10/design-feature-audit]]. It compares the
product, intake, storage/search, conversation, native application/workflow,
automation, integration and release contracts with code and current evidence.
[[records/specs/mvp-delivery]] still controls delivery. Missing long-term features
are not automatically MVP blockers. No completion percentage is meaningful across
these differently sized requirements.

Audit source commit: `5f550358d9aaf6f5248c1c5a47d1894b4c3d0b56`. All 297 product/test
sources bound by the latest surface-polish receipt are unchanged. The installed
native CLI matches its receipt, SHA-256
`38af5330a756167b4d0ac1576a9a84ca86278e707f57adfd237ef4824df732bc`.
No product code, engine selection, model weights or device authority changed here.
The older IJ04 wording is aligned with the adopted I04 capture default: include a
reference immediately, and clarify only an ambiguous requested working-data change.

The [immutable audit receipt](../../../integration/evidence/2026-10-29-design-feature-audit.json.gz)
binds source identities, actual synthetic command responses, model answers, fresh
scale results, native accessibility observations and private artifact digests.
SHA-256: `3ce6603823f17172c57641df554842f22d7ab4fde756030a70b72e5f72999bce`.

## Fresh findings that affect the next useful job

### Evidence coverage remains unreliable

Four fresh installed native-model requests ran against included synthetic files.
Three Brio-specific questions correctly cited its PDF, gave delivery as five
business days, retained the fourteen-day validity, and did not invent a tax rate.
The fourth asked to compare Atlas and Brio including goods, shipping, delivery and
taxes. It returned correct goods-plus-shipping totals of USD130 and USD135, but
used only the CSV and omitted the PDF's available delivery and tax terms. It
reported Atlas cheapest without adequately limiting that conclusion to the known
costs. Opening the PDF in the native app confirmed that the omitted evidence was
present and processed, not unavailable.

The answer's host state was complete. Valid citations and checked arithmetic do
not establish complete fulfillment of the user's request. The next reliability
work should check requested dimensions and relevant evidence coverage, distinguish
unknown facts from unread files, and qualify broad questions as well as focused
ones. This is four scoped cases, not a measured accuracy rate. Observed request
latencies of 41–74 seconds under development load are not performance benchmarks
or support for an instant-response or 100–150 token/second product claim.

### Native presentation still leaks storage syntax

The installed app visibly renders the comparison's Markdown pipe table as text.
Its conversation renderer handles inline attributed Markdown, not block tables.
The original CSV likewise opens as raw delimited text. The converted working table
is a separate, proper native table. Tool activity's readable structured results
are already implemented; that does not qualify every generated answer's rendering.

A useful completion should show a readable comparison in the conversation or
right-pane space, with source access, clear missing values and a path to edit/save.
Original CSV inspection should be tabular without silently converting it into
working business data. These are concrete usability gaps in the existing promise.

### Intake scale is not established by search indexes

Fresh checks confirm that reviewed table updates refuse 1,001 incoming rows with
`update_limit`, and refuse XLSX mapping with `update_format`. Current CSV/TSV update
bounds are 1,000 incoming rows, 10,000 target rows, 8 MB mapped values and 16 MB
target content. Explicit mappings are required; mapping every stored target column
is not a partial-column merge experience. The native mapping form also lacks a
persisted in-progress draft. These are limits of reviewed updates, not a maximum
asset size or a universal workbook row limit.

A fresh full release search benchmark passed its 10,000-row cohort and its 10,000-
and 100,000-document-chunk cohorts. The latter represents 1,000 documents, not
100,000 files. Warm p95 observations were 15.6 ms, 18.3 ms and 189.6 ms respectively
on the reference M5 Pro/48 GB Mac. OS caches were uncontrolled; full performance
qualification remains false.

The 100,000-row cohort failed before search: creating its dataset in one
transaction exceeded the 64 MB saved-change limit. The whole benchmark therefore
exited 1 and its aggregate protocol result is false. Follow-up integrity, table
listing and search confirm a clean refusal with no partial table or indexed rows.
The guard protects integrity. Scalable batched capture/conversion with resumable
progress is the missing path; increasing the guard is not an established fix.
Prior 100,000-row evidence predates material source changes and cannot qualify this
current route. Neither this failure nor the document timings prove how all large
existing workbooks perform.

### Excel values are not a functioning imported spreadsheet

A synthetic XLSX contained quantity 3 and `A2*2` with cached total 6. Saved-value
import retained those values and the original evidence. Editing the imported
quantity to 4 left the imported total at 6. Reopen and portable verification passed.
This confirms the documented values-only limit, rather than a regression in native
Sevra formulas. A native `0.1+0.2` calculation returned exact `0.3`; unsupported
`XLOOKUP(1,2,3)` refused clearly.

Live translation of supported Excel formulas, coordinates, cross-sheet/named-range
references, dependent recalculation and feature-by-feature fidelity reporting
remain the expanded IJ05–IJ07 contract. Existing basic import cannot satisfy that
contract. Pivot/chart/layout/macro/connection fidelity is not delivered, and macros
must not execute on intake. Full Excel parity remains deferred from the MVP.

### A durable conversation is not unlimited working context

The installed native configuration explicitly uses a 32K evaluation profile,
bounded512 reasoning and `contextMaintenanceEnabled: false`. Conversation history,
chapters, tangents, checkpoints and compaction mechanisms exist; scripted tests
exercise them. Sustained actual-model C12/C13/J10 coverage and automatic production
compaction remain unqualified. Do not equate a persistent visible conversation
with indefinitely reliable model memory, or silently enable the existing mechanism
without its missing evidence.

## Requirement coverage

Working means the stated bounded behavior exists, not that all possible cases or
all physical devices are qualified. Partial means useful code/proof exists but the
full acceptance journey is open. Deferred means an adopted later requirement is
not delivered or qualified and does not become active work through this audit.

| Design area | Current state | Missing feature or remaining qualification |
|---|---|---|
| Workbook package, included assets, explicit external links, portable compression | Working bounded foundation | Broad external-volume/media/OS recovery qualification remains open. Asset inclusion is not constrained by the table-update row limits. |
| Sources/Records, independent meaning and acceptance, versions, lineage, replay, review and duplicate effect protection | Working bounded foundation | Broad model interpretation of business meaning and real-world occurrence identity remains unreliable. Accepted forecasts must stay estimates, which the core already supports. |
| Filename, FTS5 and structured agentic search/read/cite | Implemented; task coverage partial | Consistent source selection, requested-dimension coverage, large intake batching and current broad scale qualification. An embedding index is not the demonstrated missing fix. |
| Reference, analysis, values and reviewed update roles | Implemented bounded paths | Simpler intent/mapping, persisted mapping drafts, partial-column and XLSX updates, resumable larger inputs; full IJ01–IJ10 matrix remains open. |
| Native table editing and clipboard | Implemented bounded paths | Multi-row selection, TSV/tabular/rich copy, atomic range paste and Undo/Redo already work. Startup/reference rich-range intake and all external spreadsheet recipients are not fully qualified. |
| Deterministic calculations and reusable queries/functions/rules | Implemented bounded subset | Expanded Excel formula continuity and full EJ04/EJ05 cross-surface/live dependency journeys remain open. No complete Excel function catalog. |
| Two panes, Home, searchable spaces, main conversation, chapters and tangents | Implemented | Sustained context qualification and all-state accessibility remain open; the shell itself is not missing. |
| Shimmer, elapsed time, Stop, expandable actual tool activity and readable structured results | Implemented | Block-rich model-answer rendering, including native comparison tables, remains incomplete. Activity should report actual progress, not claim exhaustive hidden reasoning. |
| Editable generated native compositions and forms | Implemented bounded component/binding set | Broader proven application expressiveness, reusable template packaging/catalog and EJ13/EJ14. Generated arbitrary Swift/JavaScript/SQL execution is deliberately closed. |
| Reusable business actions | Three trusted primitives exist | Registry currently covers delivery, draft inventory movement and document drafting. This is not a general small-business application/action library. Direct conversation invocation is qualified only for supported paths. |
| Durable manual workflows, reviews, typed clarification, recovery | Substantial partial implementation | Linear 1–16-step workflows support evaluation/action/review/interpretation/extraction/intake. General branching, loops, subworkflows, arbitrary ambiguous matching and full EJ06–EJ08 failure/abuse coverage remain open. Exact catalog lookup/repair and human clarification already exist. |
| Calendar and inventory-condition automation | Implemented bounded foreground subset | Text/voice Enable confirmation, broader dataset-query/business triggers and a full actual-model condition-to-human-review/restart job remain open. Native Enable/Pause already work. |
| Background/folder automation | Deferred E5 | Folder reconciliation, helper ownership/resource broker and actual app-quit/login/sleep/wake/drive lifecycle qualification. Foreground polling must not be presented as always-on automation. |
| Documents, links, backlinks and provenance | Implemented bounded structure/viewing | General natural-language/voice passage-link authoring remains open. Do not call explicit links/backlinks or existing correction/traversal missing. |
| PDF, images, OCR, media playback and file fallback | Implemented per-format bounds | Long audio/video content understanding is incomplete. On-device file transcription is limited to clips up to 60 seconds. Inclusion/playback of a large video is not full searchable comprehension. |
| URL linking versus captured snapshot | Implemented explicit distinction | Authenticated/oversized/unsupported capture remains limited; a saved URL is not proof of an offline copy or full web ingestion. No general authenticated web connector is delivered. |
| Text and local voice input | Text and scoped dictation implemented | Every operation does not have equivalent qualified conversational controls. Locale/capability/hardware and complete voice journey qualification remain open. |
| Native Splash C++/Metal with Swift and no Python inference runtime | Implemented preview integration | Maintained update skill and model setup exist. Full native/reference adoption/performance and physical hardware envelope remain unqualified. Keep Slotstream baseline independent. |
| Main model and setup | Pinned Qwen3.6-35B-A3B 4-bit plus matching DFlash2 | Current upstream availability does not qualify a new model automatically. Downloads, reuse, verified manifests and resumable cancellation are implemented. No model-catalog project is needed. |
| CLI plus harness skill | Implemented | Shared native core supports app-closed operations. A CLI cannot substitute for real native UI, permission or model-quality checks. |
| Production distribution and accessibility | Source-preview installation works; full qualification open | Developer ID/notarization/release lifecycle, declared supported hardware, complete keyboard/VoiceOver/contrast/motion/locale/appearance matrix and uncoached use are not complete. |
| Evidence of superiority to Excel | Not established | Full EJ14 comparison of the same job and a second distinct user workflow, including effort, corrections and recovery. An attractive supplier demo cannot establish general replacement value. |

Contracts: [[records/specs/product]], [[records/specs/contextual-import]],
[[records/specs/search]], [[records/specs/conversation-context]],
[[records/specs/native-app-engine]], [[records/specs/manual-workflows]],
[[records/specs/condition-dispatch]], [[records/specs/references-and-relationships]],
[[records/specs/splash-integration]] and [[records/specs/distribution]].

## Research implications

Microsoft describes [Power Query](https://support.microsoft.com/en-us/excel/about-power-query-in-excel)
as repeatable connection, transformation, combination and refresh. This supports
prioritizing reusable file-to-working-data updates over adding more chat surfaces.
Its [recalculation documentation](https://support.microsoft.com/en-us/excel/change-formula-recalculation-iteration-or-precision-in-excel)
also makes the continuity gap concrete: dependent results normally update when
inputs change. Our current saved-value import does not preserve that behavior.
These are product inferences, not evidence that every Excel user needs every feature.

[SQLite FTS5](https://www.sqlite.org/fts5.html) supplies lexical retrieval, tokenizers,
ranking and index maintenance. It does not ensure an agent reads every relevant
source. Current tests point to coverage and intake limits, not a demonstrated need
to replace working FTS with a new semantic-index system.

Apple's [on-device recognition capability](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)
requires checking availability; local voice is not universal across languages and
hardware. [Notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
is also a separate distribution step. An ad-hoc signature check does not establish
customer distribution readiness.

The official [Splash repository](https://github.com/incoai/splash) continues to evolve.
Its model list and benchmark tables are upstream evidence, not Sevra task latency,
accuracy or parity. Keep the pinned candidate until a specific upgrade qualifies
under the existing integration skill. The historical W1 cohort completed 260 jobs
but failed one exact paired-output comparison; later repeatability diagnostics do
not turn that into passed adoption or a Python-removal speedup claim.

## Verification and limits

Fresh verification completed:

- `bash scripts/check.sh`: exit 0, including 557 core groups/0 failures, native
  document lifecycle 27/0, synthetic speech lifecycle 15/0, Splash checks 31/0,
  65 tool grammar cases and 555 masks. This uses the default baseline build
  configuration for the broad shared suite. It is not native-model accuracy proof.
- Installed-native contextual intake checks: nine groups pass. Packaged extraction
  passes while denying build-tree reads. Native isolated install/update/uninstall,
  standalone CLI, skill conflict handling and workbook preservation pass.
- Four actual local-model questions: three pass their requested scope, one is
  incomplete. Native app observation confirms the Markdown/CSV presentation gaps
  and available omitted PDF evidence. Previous synthetic window restored afterward.
- Saved-value XLSX edit, Decimal/refusal counterexamples and portable integrity
  pass. The initial probe had two incorrect fixture/error expectations; their
  failures are retained and corrected probes inspect actual schema/error behavior.
- Full current release search benchmark: three cohorts pass, 100,000-row ingest
  fails, aggregate exit 1. Post-refusal verification confirms atomic safety.
- Installed app deep strict signature verification passes. No new model download,
  privacy grant, speech recording, automation activation or real business change.

The source-commit hosted CI run was still in progress at receipt capture. The
preceding `58d9d37` and `63bfcd9` runs are green; an earlier `f89f8e1` packaged-CLI
receipt failure remains historical. Local passing checks are not a green claim for
an unfinished exact-head hosted run. No all-state UI, general model accuracy,
full performance or production-release qualification follows from this audit.

## Next work and delivery discipline

Keep the same three active priorities in [[records/operations/implementation]]:

1. Complete the ordinary supplier question across all relevant evidence, with
   explicit limits on missing costs and checked complete-request outcomes.
2. Make intake and results usable: tabular reference/answer presentation, simpler
   reviewed mappings and resumable bounded bulk work. Preserve originals, atomic
   refusal and truthful stage reporting while doing so.
3. Qualify accessibility, physical hardware and distribution before broad release
   claims. Use uncoached user attempts to choose the next product change.

Conversation compaction, Excel continuity, richer workflows, background automation
and templates stay visible as deferred work rather than hidden completion claims.
Do not activate every gap at once. Cloud/sync, realtime collaboration, Windows/Linux,
arbitrary executable plugins and a separate specialist decision model remain
outside this MVP. Shareable PDF/report export could be evaluated as a product
addition, but this audit does not silently turn it into an adopted requirement.
