---
type: operational
meta-type: conclusion
id: 01m5rbxzcsjnewm0pwmb9a06cj
created: 2026-10-25T01:48:47.385772+00:00
updated: 2026-10-26T20:46:27.202426+00:00
summary: Ordered work and honest requirement status for the first Sevra release.
title: Implementation and acceptance
---
# Implementation and acceptance

This is a working development build, not a qualified release. Requirements in the
specifications remain the acceptance contract. A source commit does not imply that
every requirement or supported hardware profile has passed.

## Current direction, October 26

Workbook is now Sevra's primary product/homepage, with Websites secondary.
[[records/specs/splash-integration]] supersedes the Slotstream architecture for the
next version. The installed/published build still uses Slotstream. The isolated Splash adapter now passes protocol, local-preparation and real-engine
smoke checks. Full frontend, performance, packaging and app adoption remain pending.

The expanded baseline `5aef111` has green GitHub CI, 46 passing local core
checks and passing packaged installation checks. Native UI and engine work below
is a subsequent checkpoint; broader qualification remains pending. Installed resource verification
executes an actual MLX kernel and passes through the installed CLI symlink.

Included in that public checkpoint: explicit safe ZIP member intake, short
on-device file transcription, reviewed table creation, request provenance,
native needs-review receipts, PDF navigation/search and SQLite embedded-NUL text
round trips. File transcription is capability-gated, at most 60 seconds, and not
yet verified against microphone/speech permissions. New table proposals passed
real-model creation/acceptance twice (26.23 and 26.71 seconds). A cell proposal was
correct but its closing model response failed; needs-review receipts address that
failure and still require real-model regression.

## Implemented

- Native SwiftUI/AppKit document windows with conversation and workspace panes,
  searchable spaces, Home, recent workbooks, native viewers and model settings.
- Shared Swift core and JSON CLI; SQLite metadata, immutable external asset files
  inside the package, SHA-256 verification, explicit external links and ZIP64 export.
- Sources/Records, immutable revisions and lineage, separate meaning and acceptance,
  unique event effects, deterministic inventory replay, corrections and undo.
- CSV and XLSX saved-value intake, typed edits, reviewed AI cell proposals with atomic acceptance, multi-row paste, undo/redo,
  formulas with decimal arithmetic, lazy IF, ROUND, cell/range references, cycle
  errors, column history, unit labels and coherent snapshot CSV export.
- Resumable 1,000-row structured intake batches with idempotent retry. Original files
  remain intact. Native PDF text, Vision OCR, text/DOCX extraction and explicit
  unsupported/partial states. Checksums and bounded cooperative processing.
- FTS5 chunks, Unicode lexical and trigram filename indexes, metadata filters,
  current/historical search, source deduplication and revision-bound cursors.
  Native paging/facets are implemented but still require interaction qualification.
- Versioned native table, bar/line chart, metric, document, asset, search, text and
  comparison components. Live bindings and pinned copies with exact values/input
  versions. Charts disclose excluded/partial rows. Pinned tables and metrics are
  bounded to 1,000 rows and refuse misleading partial aggregation.
- Main conversation, chapters, saved exchanges, parent-linked tangents, evidence
  locators, draft autosave, optional continued playback and linked-file recovery.
- Native Slotstream Fast integration at the pinned public revision, model setup,
  typed tools, bounded agent turns, persisted traces/run metrics, citation checks
  and idempotent agent mutations. Real comparison, cited answers, generated views,
  hostile-document and missing-evidence checks have passed; broader eval is pending.
- On-device dictation code. Actual microphone recognition remains unqualified.
- App/CLI bundling, verified Metal kernels, dependency notices, ad-hoc signing,
  user-local install/update/uninstall and optional Codex/Claude Code skill installer.

## Verification checkpoint, October 24 local / October 25 UTC, 2026

The October 26 baseline rebuild passes 46 executable core checks. They cover lineage, actual/estimate separation,
acceptance/withdrawal, unique effects, stale revisions, immutable imports, changed
and missing links, cancellation, quoted CSV, atomic editing/undo, spaces,
conversations, XLSX, index recovery, unsafe paths/schema/archives, lazy formulas,
precision, cursors, search cancellation/deadline cleanup, pin retry identity, deterministic percentages, CSV snapshots, live versus pinned
values, type/history checks, resumed intake and real PDF text/image OCR locators.

Packaged-binary checks also pass:

- Isolated install, update, standalone CLI, demo, verification and uninstall,
  preservation of workbooks and refusal to replace an unrelated CLI.
- Thirty concurrent CLI writers, cross-process structured-intake retry, idempotent retry, stale-write refusal and coherent
  export/reopen with preserved inventory and asset verification.
- Loopback HTTP fixture: capture through redirect, indexed content, refusal of a
  redirect loop, failed captures preserved as explicit references, non-HTTP refusal
  and credential-query redaction for both captures and explicit links.
- A 4,296,015,872-byte synthetic asset: include, remove original, verify, ZIP64
  export, reopen and verify. Archive size 4,296,022,031 bytes; peak process RSS
  39,141,376 bytes after the buffer-lifetime fix. Synthetic sparse bytes are not a
  real-video playback or storage-throughput benchmark.

## Model and scale findings

The pinned Fast model completed a corrected supplier comparison with exact values
24 and 27.5, difference 3.5 and 12.73% cheaper relative to the larger quote. It
created the Purchasing table/chart space and cited the rows. One run took about
34 seconds wall time, with 29.30 seconds in model requests across nine steps and
1,224 generated tokens. Another took 32.8 seconds across twelve steps. These are
whole-task observations, not a 100+ tokens/s decoding claim or statistical latency
qualification. Runtime now records decode/prefill/first-token/memory metrics.

An adversarial document was read without executing its injected space-creation
instruction. A missing-contract query exposed repetitive empty searches; the
bounded agent now requires an evidence-gap answer after three empty searches.
Its corrected four-step answer disclosed incomplete indexing and did not invent
citations. An overly narrow test assertion was corrected to accept that wording.

SIGINT cancellation persisted a cancelled run and left the workbook verified.
A subsequent independent retry passed cancellation followed by a successful stock
answer (23.49 seconds). An earlier lock refusal remains historical evidence. Native UI model interaction still
needs qualification. The newest proposal/comparison-component schema also requires
regression evaluation.
At 100,000 rows, initial broad-query warm p95 was about 589 ms. Derived index
metadata reduced a later run to about 220 ms; the 200 ms target remains unqualified.
Exact identifier lookups were below 1 ms. New-connection numbers are not OS-cold
measurements. Runs overlapping inference are not performance qualification.

## Remaining work

1. Native end-to-end interaction: cell editing/paste/undo, Finder opening, search
   paging/Back/facets, chapters/tangents, draft autosave, pinned/comparison views,
   locators, media, dictation, narrow windows, appearance and keyboard/VoiceOver.
   The Mac is accessible again; the interaction results below are verified.
2. Model regression for the latest review receipts and proposal tools, context
   overflow recovery, and measured whole-task latency across repeated runs.
3. Search scale/recall with many chunks per document; further broad-query optimization and cancellation during actual long-running searches.
4. Remaining extraction crash/isolation tests and hardware qualification of file
   transcription and archive selection. These implementations now exist, but actual
   speech hardware/permissions remain unqualified. Parser deadlines are cooperative.
5. Complete text/voice workflow coverage, review agent tools against user authority,
   and qualify formula/units behavior. Units are labels, not automatic conversion.
6. Updated fresh public clone/build, real user installation, green CI and a properly
   labeled public release package. An earlier public clone at 7b6d8f2 built and passed
   its 40 checks plus install/concurrency/URL scripts. Local current app and CLI
   resource checks pass with build-directory reads denied. The skill installer and
   overwrite refusal pass in an isolated directory.

## Packaging and recovery review

The sealed macOS app keeps resources in Contents/Resources. The upstream generic
SwiftPM tokenizer fallback assumes a flat executable layout; this app deliberately
uses the qualified Fast pack's explicit tokenizer configuration and rejects a
missing tokenizer class before loading. Installed-resource checks use packaged
resources and actual Metal library loading, with reads of the build tree denied.
Both app and CLI resolved 17,319 kernel functions on the reference Mac. This does
not qualify arbitrary tokenizer/model layouts.

Two-minute idle release and memory-pressure handling release an idle model. An
active turn is not silently stopped. Setup/unload status distinguishes a busy
model. App termination signals cancellation; interrupted turns are recovered as
interrupted on the next run.

## Completion rule

J01–J09 in [[records/specs/product]] require recorded outcomes, not inferred
success. Keep this register current. Do not label the whole app or full
specification complete while required work remains.

## Splash checkpoint, October 26

Completed: public design/progress reconciliation, personal and website ownership
pointers, preserved baseline `5aef111`, repo-owned update-splash skill, immutable
1.4.1 source/runtime pin, verified native-only candidate extraction and license
retention. The skill validator passed in an isolated Python development environment.
The candidate executable's `device-check` succeeds on the reference M5 Pro. Its
`model-check` accepts the installed Qwen3.6 target and matching DFlash2 configuration.
This is configuration/device validation, not a model load or throughput result.

`Sources/SevraSplash` builds independently of MLX/Slotstream. Protocol v11
matches eight upstream client frame fixtures and all 15 engine event fixtures.
Text is supported; image requests remain outside this first adapter. Twenty
checks cover framing, sequencing, recovery, cancellation, bounded diagnostics,
pinned model identity, immutable preparation, damaged/missing files and atomic
selection. Exact upstream fixtures have attribution and a recorded digest.

Swift prepares the original selected target/draft bytes without copying the
weights. Its immutable model.json is byte-identical to the pinned upstream
Python preparation API, verified twice in an isolated reference environment.
Full first preparation hashes approximately 21.5 GB with bounded reads; later
preparation checks metadata and reuses verified digests. Interrupted or invalid
preparation preserves the prior selection. The native model downloader is pending.

Real Splash generation through the Swift-owned native helper passed with 22 GiB
and 12 GiB engine budgets on the M5 Pro / 48 GiB / macOS 26.6.2 reference host.
Both runs completed four requests, cancelled one, recovered after cancellation
and local context-limit refusal, and released weights with healthy Metal status.
The 12 GiB run reported expert streaming. Prompt token IDs came from the pinned
Python reference tokenizer, so this does not establish Swift frontend parity.
These six-token answers establish transport/recovery only, not throughput,
performance parity or physical 16 GiB hardware support. See the sanitized receipt
at integration/evidence/2026-10-26-native-smoke.json and the reproducible reference
procedure in [[records/operations/build-and-run]].

The production app still uses Slotstream. Swift model downloads, output/tool parsing, native tool-grammar construction and
integrated workbook behavior remain pending. Native grammar-mask fixture and
real-engine checks now pass as recorded below. The following checkpoint adds tokenizer/template
fixture parity, independently of production adoption. The release archive is a verified upstream artifact;
this is not a claim of a reproducible source-to-binary build.

## Native UI checkpoint, October 26

The installed app opened a newly saved synthetic workbook from Recent workbooks.
Editing a supplier cost recalculated its formula and chart; Undo restored the
values and preserved correction history. Search opened the delivery evidence and
Back restored the query/results. Tangent creation and return to Main preserved
both conversations; named chapters appeared in the navigation menu. The space
picker and pinned Home copy worked, and a reopen preserved workbook contents.

Polish from these checks: compact tables now fit their row count, selection
context uses readable table/row/column/value labels, search hides internal locator
syntax, dates use localized display, and computed values appear in accessibility
labels. Chapter/tangent menu actions use a focused name sheet instead of a command
prefix that typing could overwrite. Voice/text commands remain available. These
interaction checks do not replace full VoiceOver, dictation, media, PDF, narrow
window and appearance qualification.

## Next work in dependency order

- Implement native resumable downloads and setup integration; local preparation
  and its selected-model reference comparison now pass.
- Wire the autonomous workbook agent to the qualified native frontend components.
  Actual tool-schema construction/validation and a real native dispatcher/proposal
  slice now pass; full actor/history/authority workflows remain unqualified.
- Expand real-model tests to complete text/tool workflows, resource failures and
  restoration after release. Preserve the current baseline during qualification.
- Qualify with identical requests, failure/recovery cases and matched performance.
- Adopt Splash only after gates pass; remove Slotstream/MLX shipped dependencies.
- Finish J01–J09, search scale, native accessibility/voice/media and clean install.
- Workbook-first marketing implementation belongs to the website repository;
  its updated brand decision must distinguish planned direction from deployment.

## Swift text frontend checkpoint, October 26

SevraSplashText uses pinned swift-transformers 1.3.5 and swift-jinja 2.5.2,
without an MLX inference dependency. The selected model's tokenizer files and
actual chat template are checked by hash. The exact upstream late-system-message
patch is also hash checked. Fourteen upstream-generated fixtures match every
prompt token ID, generation-prefix token count and decoded prompt, covering
Unicode, multi-turn history, reasoning modes, tools/results, literal special
markers, trimming and empty content. Input/context/modality bounds also pass.
JSON object keys are normalized recursively before both reference and native
frontends; this is not a byte-parity claim for arbitrary unsorted JSON inputs.

scripts/check_splash_text.py obtains only the three pinned tokenizer files for
CI, verifies their hashes and runs the Swift fixtures. Clean download and the
complete local scripts/check.sh pass. scripts/generate_splash_text_fixtures.py
rebuilds the reference in an isolated Python development environment. Streaming
decoding was still pending at this checkpoint; the later streaming checkpoint
below supersedes that gap. Complete workbook-agent workflows remain unqualified.
The prior public checkpoint 1e8d47a passed its complete GitHub Actions workflow.

## Observer identity checkpoint, October 26

Carlos explicitly selected the existing Sevra website and historical native-app
identity. The app now includes the exact original Observer ICNS, local source
vectors, deterministic native shapes, a welcome lockup and a small workbook-header
mark. The standard About panel uses the bundle icon. The logo adapts through
native semantic colors; the icon retains its approved cream tile. The installed welcome lockup and workbook header were visually verified in
System/light and Dark, then System was restored. The standard About panel and
Finder Get Info show the original icon. Installer checks verify its exact digest.
The full core/adapter/text suite, knowledge validation, packaged resources with
build-tree reads denied, and isolated install/update/uninstall all pass. See
[[records/specs/identity]].

## Native grammar checkpoint, October 26

SevraSplashGrammar calls the pinned LLGuidance 1.8.0 native C ABI, with Swift-owned
state and an exact tokenization callback. Its source/toolchain/header/lock are
pinned in integration/llguidance.json and built by scripts/build_guidance.py.
No Python participates in native grammar checking or real-engine generation.
Rust remains development tooling for this candidate; the production baseline is
unchanged. Native grammar packaging and transitive license collection remain open.

The differential suite caught and fixed two real API differences: the HF adapter
marks added <...> tokens as special even when tokenizer.json does not, and the
Python matcher's stopped-EOS handling differs from the C API. Swift now matches
all 248,320 byte-vocabulary entries and 105 full mask requests across four grammars.
Checks include Unicode/escaped strings, typed arrays, reasoning, strict tools,
invalid speculative suffixes, cache isolation, both EOS IDs, malformed schemas,
invalid committed tokens, stale prefixes and dimension/size refusals.

The native engine completed four requests and cancelled one with a 12 GiB budget
on the reference 48 GiB M5 Pro. Prompts were prepared in Swift, masks came through
the native grammar and output decoded through Swift. The synthetic jobs covered
exact JSON, Unicode JSON, a find_evidence tool call, immediate cancellation and a
successful subsequent request. Weights released and Metal remained healthy. This
proves the native constrained-generation path, not the full workbook tool parser,
schema builder or matched performance. See the sanitized receipt at
integration/evidence/2026-10-26-native-grammar.json. Development build activity
may overlap these correctness checks, so their timings are not a speed benchmark.

Packaging now builds only the app and CLI products and copies only resources
required by the active backend. Candidate adapter resources and test fixtures
are excluded from the shipped bundle, with an installation check for that list.

The updated full scripts/check.sh suite passes: 46 workbook/core checks, 20 native
transport/setup checks, 14 prompt fixtures and the exact grammar suite. The
current packaged app/CLI build, installed icon/resource whitelist, isolated
install/update/uninstall and actual Metal/resource checks with source-tree reads
denied also pass. Both reference generators reproduce their fixtures without
changes and verify the selected source/tokenizer identities first. The repo-owned
upgrade skill validates, and dbmd/link checks report no findings.

## Native streamed output checkpoint, October 26

SplashTextStream incrementally decodes the exact selected byte vocabulary without
redecoding the whole answer on each token. Its immutable offsets/vocabulary are
shared across requests. Eighty pinned-reference fixtures match every text delta,
final flush and stop match, including raw/random byte sequences, split Unicode,
literal replacement characters, special/padded tokens and overlapping stops.
The reference decoder's trailing replacement-character behavior is preserved.

SplashOutputParser separates reasoning, text and complete Qwen XML calls. Thirty-one
upstream projections match text, reasoning and typed argument values across 3,216
chunk layouts. These include multiple calls, structured JSON containing tags,
embedded tag strings in parameters, Unicode, union types and framing whitespace.
The differential checks caught two implementation errors: ordinary byte 0xff was
mistaken for a grammar sentinel, and closing-tag whitespace trimming removed a
newline from the next call at certain chunk boundaries. Both are fixed.

Sevra intentionally refuses unknown/duplicate/malformed calls instead of repairing
them. Every truncation/cancellation boundary in the test call returns no candidates;
limits, parser/decoder reuse, invalid tokens, stop cuts and oversized integers are
also refused. The integrated SplashOutputStream returns only terminal candidates;
full schema/authority validation remains the workbook agent's responsibility.
See I15 in [[records/specs/splash-integration]] for bounds and deliberate differences.

The real native probe now passes the same five synthetic requests through Swift
stream decoding and output projection: JSON, Unicode JSON, find_evidence with the
exact query and integer limit, cancellation and successful retry. No Python runs
in this generation path. The previous 12 GiB engine budget and exact pins remain;
this is correctness evidence, not a matched speed result or full agent acceptance.
The sanitized receipt is integration/evidence/2026-10-26-native-output.json.
The full scripts/check.sh suite and default reference regeneration pass; the
preceding grammar checkpoint a6b65e5 passed its complete GitHub Actions workflow,
including the release app/CLI build and installation checks. This output checkpoint
does not replace full release UI and fresh-install acceptance.

Remaining frontend work: construct native grammars from the workbook's actual tool
schemas, validate full arguments, connect dispatch/history and qualify complete
workbook jobs. Native resumable download/setup, packaging/adoption, matched speed
comparisons and the documented product release gates remain open. The production
app still uses the preserved Slotstream baseline.

## Actual workbook tool checkpoint, October 26

SplashToolPolicy now constructs the Qwen native grammar from all 19 actual app
tool declarations. Its normalized schema drives the prompt, parser and complete
argument validator. The preserved Slotstream baseline has no behavior changes;
NativeTools declarations gained package visibility for these independent checks.

The integration identified a consequential strict-schema mismatch: upstream strict
normalization closes unspecified nested objects. Rows, edits, named calculation
values and record data need arbitrary keys, so the native policy preserves their
original JSON Schema semantics by making default-open objects explicit. Root tool
arguments remain closed. The normalized fixture is compared with actual code.

The reference suite covers 23 actual-tool scenarios and 217 full masks for required,
automatic, named and reasoning output. Native output parsing, schema validation and
prompt preparation pass for these cases. Wrong types, missing fields, unsupported
schema keywords, unavailable enum values, extra closed-object fields, wrong version
constants and lossy large integers are refused. The validator distinguishes booleans
from numeric constants. Exact integer limits reflect the workbook's current Double
JSON representation; large IDs and financial decimals travel as strings.

A new tool-history fixture exposed NSNull failing Swift Jinja rendering. The Swift
frontend now bridges nested nulls to boxed nil after input validation. All 15
prompt fixtures match the upstream's exact tokens, including that history case.

The opt-in real-engine workbook probe uses the actual tool declarations and core
dispatcher. It completes decimal calculation, creates a two-row supplier proposal,
checks that no table exists before separate fixture acceptance, verifies prices and
quantities, reopens the saved values, checks source-to-proposal-to-acceptance lineage,
cancels a further proposal with no call dispatched, then calculates successfully
again. Three requests complete and one cancels; weights release and Metal is healthy.
These are explicitly selected tools in a synthetic workbook, not a claim that the
autonomous WorkbookAgent or installed UI has migrated. The sanitized receipt at
integration/evidence/2026-10-26-native-workbook.json records the exact implementation
and limits.

The full scripts/check.sh suite and default reference regeneration pass. The prior
streaming checkpoint c12318a also passed complete public CI. Next: integrate the
native backend with the autonomous actor and its existing evidence/permission/run
history rules, implement resumable setup/downloads, compare matched performance,
then complete packaging/adoption and the remaining J01–J09/UI/search/release gates.
The release app and CLI build also pass for this checkpoint. Isolated installer checks cover install, update, uninstall, standalone CLI, skill installation/conflicts, workbook preservation and unrelated-CLI protection.