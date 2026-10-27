---
type: operational
meta-type: conclusion
id: 01m5rbxzcsjnewm0pwmb9a06cj
created: 2026-10-25T01:48:47.385772+00:00
updated: 2026-10-27T07:04:06.093397+00:00
summary: Ordered work and honest requirement status for the first Sevra release.
title: Implementation and acceptance
---
# Implementation and acceptance

This is a working development build, not a qualified release. Requirements in the
specifications remain the acceptance contract. A source commit does not imply that
every requirement or supported hardware profile has passed.

## Current direction, October 27
Workbook is Sevra's primary product/homepage, with Websites secondary. The installed app remains the preserved Slotstream baseline. A separate Python-free native Splash preview now uses the shared workbook agent through SevraProduct, with the unchanged pinned C++/Metal helper, native grammar library and Swift setup. It is not yet the production default.

The observed search-coverage failures are corrected at the host boundary. Exact classified-record counts come from SQLite and finish-time revalidation. Missing-evidence finishes after empty searches display actual queries and indexing limits, including when the model tries to substitute an unrelated count. Other answers reject recognized unsupported absence/exhaustiveness wording. This is bounded grounding, not general semantic truth verification. The earlier six-case reasoning-off/bounded512 evidence remains in integration/evidence/2026-10-27-search-coverage-setup.json.

Native setup completed a fresh 21,481,463,614-byte target/draft download, with a deliberate cancellation after 130,690,940 retained weight bytes, safe resume and verified atomic publication. The packaged native CLI then passed all nine workbook checks on those fresh files. The rebuilt baseline passed all nine too. Native Settings reuse and offline reverification pass without duplicating weights. A full download initiated in the UI and UI cancellation were not separately qualified.

The native preview app and CLI pass installed-resource checks with build-folder access denied, nine missing-resource cases, altered Metal refusal, missing-model guidance and strict signing. Both load 1,888 Metal functions; native binaries and a live process-map sample show no Python, Slotstream or MLX inference runtime. SwiftPM still resolves baseline source dependencies for comparison targets. A fresh-checkout native preview build and packaging check are now part of CI; checkpoint 8adaa855 passed the complete hosted workflow, including the isolated preview build/package check (run 40454053852). New commits still need their own CI result.

The final full regression has 59 core checks, 30 native adapter/setup checks, 24 exact prompt fixtures, 80 streaming fixtures, all 248,320 vocabulary entries, 105 base grammar masks and 249 masks across 28 actual-tool grammar cases. Required-first nested property order fixes optional formula omission without weakening schemas. Real workbook tests cover comparisons, hostile documents, missing evidence, proposal acceptance/undo, scoped counts and cancellation/restart. Additional native and baseline table runs prove formula recalculation after an input edit. One actual native UI comparison completed with a generated table/chart, opened its cited source, and returned to the space through Back. See integration/evidence/2026-10-27-native-product.json for failed attempts, final results and commands.

Next: matched reference/native request and workbook performance, total memory/headroom, wider evidence-grounding evaluation, complete native UI/media/voice/accessibility journeys, and remaining search scale/interruption recovery. Production adoption, wider hardware support and release qualification remain open. Automatic compaction remains disabled in both product paths. [[records/specs/splash-integration]] and [[records/specs/conversation-context]] control those gates.


The matched native/reference request harness now has three retained pilots in integration/evidence/2026-10-27-native-performance-pilots.json. Pilot 1 exposed an NFC expectation error, an ambiguous title and mismatched tool prompt ordering. Pilot 2 matched prompts but missed nested property normalization inside wrapped reference grammars. Pilot 3 passed all five workloads with identical prompts and generated tokens, no semantic/sampling failures and no power/thermal exclusions. It is one sample per workload/backend, not a performance qualification.

Swift now probes the pinned template's generation suffix once and reuses exact large envelopes in a bounded four-entry, 8 MiB payload cache. Scalar type identity, signed zero, reasoning flags, changed histories and current context limits are preserved. The full local regression passes 24 exact prompt fixtures, the existing 80 stream/105 base-mask/249 actual-tool-mask checks, core and setup checks, plus benchmark gate failure tests. Native assembly reverification passes. The fixed ten-block cohort is complete: latency and token parity passed, but its overall gate failed on four matching raw-model currency errors in warmups. Four labeled actual-model currency recovery trials now pass in off/bounded512 modes. This does not erase the raw-model failure; complete validated-workflow performance remains open. The installed baseline remains unchanged; see Matched request cohort below. Native table row identity and stale-query fixes now pass programmatic and visible-app checks; see Native table identity and asynchronous refresh below. The active-inference pressure policy now passes synthetic checks and actual native/baseline lifecycle probes; the preserved baseline still fails the unrelated Ready follow-up, so its combined probe remains failed. See Active memory-pressure lifecycle below. Atomic request admission now also passes abandoned-run, lease-refusal and real native process-death recovery checks; see Atomic request admission and crash recovery below.
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
2. Model regression for the latest review receipts and proposal tools, automatic compaction and larger-context qualification under
   [[records/specs/conversation-context]], context overflow recovery, and measured whole-task latency across repeated runs.
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

Two-minute idle release remains. Warning pressure defers release until active work ends; critical pressure cancels visibly, preserves committed work and releases afterward. The shared product service owns this policy for the app and CLI. Ordinary user unload remains idle-only, and failed release blocks reuse. App termination signals cancellation; interrupted turns are recovered as interrupted on the next run.

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
- Native CLI full-weight download, cancellation/resume and atomic publication now pass. Finish UI-initiated full-download cancellation and shutdown/relaunch qualification; native Settings reuse/offline reverification already pass.
- Qualify matched reference/native requests, failures, cold/warm latency, total memory and thermal behavior on intended physical hardware. No speed benefit follows automatically from removing Python.
- The isolated native preview now packages and uses the unchanged helper/grammar without Python, Slotstream or MLX inference runtime. Keep it separate until remaining adoption gates pass, then remove shipped baseline inference dependencies. No model catalog or backend picker.
- Broaden answer-grounding evaluation across paraphrases, languages, mixed questions and finish-basis misclassification. The current count renderer and conservative language guard fix the observed path, not every possible inference error.
- Complete text/tool workflows, resource failures, persisted-job resolution and kill/restart tests without replaying uncertain accepted mutations.
- Finish J01–J10, document/row search scale, native accessibility/voice/media and fresh clean-install qualification.
- Workbook-first marketing implementation belongs to the website repository; distinguish planned direction from deployment.
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
## Autonomous native workbook checkpoint, October 26

The actual WorkbookAgent now runs through a package-internal inference boundary
using app-owned messages and tool calls. SevraNativeAI supplies the candidate
Swift frontend and native Splash helper. Production still uses LocalModel and the
preserved Slotstream dependency; the candidate is linked only by development checks.
The existing baseline bridge preserves JSON types and exact integer history values.

The native actor owns an exclusive run and cross-process lease, while one serial
worker owns blocking pipes, tokenizer and grammar state. It verifies the executable,
both Metal libraries, native grammar library and selected model preparation before
loading. Failure discards the session; cancellation suppresses calls; a retry
initializes a verified helper. Unload and owner disposal reap it before releasing
the lease. Idle release remains two minutes. Native errors retain readable diagnostics.

Three repeat cycles passed all seven synthetic jobs through the actual autonomous
agent, with the model choosing tools and arguments. Each cycle checks table creation
as a draft, separate fixture human acceptance, exact values, lineage and reopen;
a cited deterministic supplier comparison; a saved native table/bar-chart space
with unchanged values and a reopened definition; a hostile document whose injected
mutation is ignored; missing evidence with actual index coverage; cancellation
with no dispatched tool; and successful calculation after cancellation. Each cycle
also verifies that the baseline can acquire the lease after native unload.

The resulting 21 persisted jobs comprise 15 complete answers, three proposals
requiring review, and three deliberate cancellations. They are not 21 distinct
use cases or a general reliability claim. The reference host remains M5 Pro,
48 GiB, macOS 26.6.2, with a 12 GiB native engine budget. The sanitized receipt is
integration/evidence/2026-10-26-native-autonomous.json. It records exact source
hashes, pins, prompts, results and metrics. Development builds may overlap these
correctness runs, so timing fields do not establish performance parity or speed.

The integration uncovered and corrected four real problems:

- A fixed 1,800-token reservation could reject a possible short final response.
  The candidate now uses the remaining context allowance, with an explicit minimum
  and refusal of all truncated tool output. Long-job context management is still open.
- Needs-review receipts were missing from model history, making earlier creation
  requests look unfinished. History now includes those receipts and derives current
  status/meaning/dataset from the preserved tool result and the item's current head.
  Draft, accepted and withdrawn states are checked; an accepted forecast stays an estimate.
- A model guessed that indexing might be incomplete when the index reported zero.
  The host now ends three consecutive empty searches with exact queries and coverage.
  Checks cover both zero and one incomplete source, without a fourth model request.
- Repeated runs could save a native space successfully and then fail final-answer
  validation by citing space/table IDs or previous-turn evidence. The native grammar
  now permits only Source/Record versions inspected in this request. No inspected
  evidence means an empty citation array. The host's citation/calculation checks remain.

The full scripts/check.sh suite passes, including lifecycle/coverage checks,
15 exact prompts, 80 streamed-output fixtures, 31 output projections across 3,216
chunk layouts, all 248,320 vocabulary entries, 105 base masks and 217 actual-tool
masks. The release app/CLI build and isolated install/update/uninstall checks pass.
The upgrade skill validator passes. The preceding actual-tool checkpoint c14284a
has complete green public CI.

Still open: native resumable downloads and setup/capability UI; matched upstream
performance; signed native packaging and transitive notices; removal of production
Slotstream/MLX dependencies only after adoption gates; broader authority/long-context
workloads; current proposal-status presentation in the UI; full J01–J09, search
scale, accessibility, voice/media, clean installation and website deployment.
The app and complete specification are not marked finished.
Preserved-backend follow-up: the current Slotstream release binary passed comparison with a native space, hostile-document handling, isolated missing-evidence coverage, table proposal/acceptance, cell proposal/acceptance/undo, and cancellation persistence. The combined conversation failed the missing-evidence turn with model_format; cancellation recovery later failed answer_validation. These are retained failures, not a clean end-to-end baseline pass. The inventory trace exposed a concrete shared-agent gap: balance results return a basis and effect versions, but those versions are not yet admitted to the current inspected-evidence set. Fix and qualify that path next. Opaque IDs in generated prose and longer unconstrained conversations also remain under review. Keep the installed earlier baseline intact; this checkpoint is not a release.
## Inventory evidence follow-up, October 26

The shared agent now admits balance results' exact opening-basis and accepted
effect versions into inspected evidence and recognizes balance as deterministic
calculation. It changes neither inventory effects nor acceptance rules. A scripted
actor regression finishes with both citations in two steps without rereading them;
the real native agent returns 18 bolts with exactly the opening/effect citations,
while the stored balance remains byte-equivalent as a Value. The source-bound
receipt is integration/evidence/2026-10-26-native-inventory.json, based on the
published autonomous checkpoint d35fb51. The release app/CLI rebuild passes.
This resolves the missing evidence-admission bug; it does not erase the retained
unconstrained-model formatting failures or establish the full product acceptance.

Recovery testing then exposed the matching history defect for cancelled/failed
requests: their terminal assistant messages were omitted while their original user
instructions remained. The model could resume a cancelled supplier analysis during
a subsequent inventory question. History now includes those terminal outcomes and
explicitly marks the old request closed. Unit checks cover cancellation and failure.
The complete seven-job native probe passed again after this change, recorded in
integration/evidence/2026-10-26-native-closed-turns.json. The rebuilt packaged
Slotstream CLI also passed cancellation persistence and stock-answer recovery in
three model steps. The earlier combined-conversation model_format failure remains
retained and unresolved; this is not a claim of a completely clean model suite.
The installed earlier app remains intact while native adoption and release work continue.

## Continuing-conversation requirements, October 26

Added C01–C13 in [[records/specs/conversation-context]], linked from product,
intelligence, storage and Splash integration. A related design conversation relayed
the owner's request for automatic compaction, preserved original history and larger
working-context tests. Proposed evaluation order is 32K then practical 64K; neither
is a verified capability or selected product default. The 8K native setting remains
a development reference. A three-pass review covers continuity, action/state
integrity and resource/recovery risks. J10 is a new required long-conversation
acceptance journey. Implementation sequence is explicit: profile/budget metrics,
durable checkpoints and history retrieval, tool-free compaction with host-owned
continuation state, repeated real-model qualification, then app adoption. Automatic
compaction and arbitrary older-history retrieval remain unimplemented.

## Context profile instrumentation and occupied probes, October 26

The candidate now has explicit internal 8K/32K/64K evaluation profiles. Engine
startup and prompt rendering use one configured capacity. Exact rendered tokens
control output allowance; request metrics record capacity, token counts and a
provisional maintenance recommendation. Output/result/recovery reserves are
1,800/2,048/256 tokens. These are instrumentation, not an implemented compactor.
The 8K development default is unchanged. The tool-policy floor can already exceed
its provisional maintenance threshold, so a future controller must detect an
irreducible prompt instead of repeatedly compacting unchanged history.

The first occupied 32K attempt executed balance, then failed on an old shared
96,000-byte guard that was incorrectly presented as a context limit. The fix keeps
a separate 1 MiB UTF-8 preparation envelope, accounts for tool arguments and message
count before each request, and leaves exact token limits to the backend. No message
or tool pair is truncated by this envelope check. Boundary tests include Unicode,
oversized call arguments, exhausted output space and a complete two-step inventory
answer with over 96,000 bytes of context. The original failed attempt is retained.

After that fix, one occupied inventory task passed at each allocation:

- 32K: 24,891 background tokens, actual rendered requests from 29,482 to 30,411
  tokens, four model steps and about 45.81 seconds for the complete job.
- 64K: 59,245 background tokens, actual rendered requests from 63,831 to 64,767
  tokens, four model steps and about 108.91 seconds for the complete job.

Both returned 18 brass bolts with exactly the opening-basis and accepted-movement
citations; stored inventory was unchanged. The synthetic background consists of
closed archive notes. This is an occupancy stress check, not realistic prolonged
conversation memory or a qualified product default. The reference host is M5 Pro
48 GiB; engine budget is 12 GiB. The source-bound sanitized receipt is
integration/evidence/2026-10-26-native-context-profiles.json.

Input processing dominates these observations: the first two prefill phases were
about 13/17 seconds at 32K and 40/50 seconds at 64K. Inspection shows that adding
inspected citation IDs changes the tools embedded at the prompt start; prefix
cache reuse is therefore a specific follow-up hypothesis to measure. Do not claim
that cause or a speedup without a controlled comparison. Full-engine memory,
pressure, SSD and thermal qualification remain open, as do automatic compaction,
durable checkpoints, history retrieval and J10. Neither allocation is promoted.

The complete seven-job autonomous probe also passed at the 32K allocation after
the envelope fix: five complete answers, one proposal requiring review, and one
deliberate cancellation. These shorter prompts check table review/reopen/lineage,
comparison, native space, hostile evidence, missing evidence, cancellation/retry
and lease release. They are distinct from the occupied inventory probes and do
not establish repeated compaction or general long-conversation quality. Their
results are included in the same context-profile evidence file.

Verification for this checkpoint: the full scripts/check.sh suite passes, including
46 core checks, 20 native transport/preparation groups, 15 exact prompts, 80 streamed
decodes, 31 projections/3,216 layouts, all 248,320 vocabulary entries, 105 base and
217 actual-tool masks, shared-agent lifecycle and the new context boundaries.
The upgrade skill validator passes. Full db.md validation has zero errors/warnings
and repository links pass. No production-backend switch or installed-app overwrite
was performed. Next implementation dependency is durable conversation/checkpoint
storage and exact history retrieval, followed by the compaction controller.

## Conversation storage and migration checkpoint, October 26

Added database schema 2 with an additive, transactional schema-1 migration. The
package manifest remains version 1. Validate the exact old schema before enabling
triggers or changing data; advance database version and revision with a recorded
migration. Failed foreign-key validation rolls back all changes. Unknown/future
schemas are refused. The canonical version-1 SQL fixture is preserved in Tests
and requires no earlier installed binary or private repository.

The shared core and CLI now provide conversation-scoped FTS, exact message/payload
reads, bounded whole-message keyset paging and revision-bound search cursors.
The recent-message display cap no longer limits explicit history retrieval.
New agent runs link to their user request; native tool/terminal receipts retain
run/call IDs, arguments and response text. Legacy metadata remains absent rather
than fabricated. Source message bodies and attached receipts remain unchanged.

Context checkpoints retain a contiguous original-history hash, exact input version
references, parent checkpoint, source revision, run and model/template/transform
identity. They may end at a completed turn or a complete recorded tool result,
which permits future compaction during a multi-step job without marking it done.
Publication is atomic, revision-checked, scope-checked and idempotent. It validates
the actual stored boundary, not caller-supplied message metadata. Loading verifies
history hashes; integrity checks also verify the chain. Current input heads,
acceptance and meaning are read from workbook state. A test digest falsely saying
an estimate is accepted does not accept it; later genuine acceptance stays estimate.

Verification: 54 core checks pass, including migration preservation/refusal/rollback,
Unicode/NUL and payload paging, scope/cursor/cancellation/index rebuild, stale and
invalid checkpoint rejection, exact references, chains, idempotence, run linkage,
mid-run boundaries, portable reopen and altered-history detection. The full
scripts/check.sh suite passes. Release app/CLI build and isolated installation
checks pass. Packaged CLI qualification opens a schema-1 workbook concurrently in
eight processes, verifies one migration, pages all 700 messages, retrieves older
content, searches with cursors and exports/reopens offline. Thirty writer and
snapshot/retry checks pass. The Sevra CLI skill validator passes.

The native autonomous seven-job regression passes again against these core changes:
five complete answers, one reviewed proposal and one deliberate cancellation, all
linked to exact request messages. This checks proposal/reopen/lineage, comparison,
space creation, hostile evidence, coverage and cancellation/retry/lease release.
Evidence with source hashes is integration/evidence/2026-10-26-conversation-storage.json.
The previous public checkpoints f7ff739 and 3e61b62 have green CI.

Still unfinished: model-driven summaries and automatic compaction scheduling,
agent tools for older history, recovery across the mutation/receipt-write interval,
valid bounded projections and durable retrieval for oversized tool results, and
process-death/repeated-compaction/long-conversation J10 qualification. These are
next dependencies, not waived gates. Native setup/downloads, packaging/adoption,
matched performance, full UI/voice/search scale and website release work remain.
The existing user-installed app and CLI were not overwritten. New schema-2
packages require the newly built app/CLI; older binaries refuse them on opening.

## Tool journal and agent retrieval checkpoint, October 26

Schema 3 adds tool_calls and migrates canonical schema 1 or 2 in one transaction.
The native/shared agent saves a prepared call with host-computed operation identity
before execution. Completion stores the exact structured result/hash and its
conversation receipt atomically. The same run/call identity cannot execute again.
An interrupted prepared call exposes any matching committed operation without
replay; lack of an operation is not proof of no effects for multi-step intake.
Failures preserve receipts and acknowledge possible completed sub-operations.

Large results no longer use a 16,000-character JSON prefix or overflow a 128KB
message after a successful action. Full results remain durable; model-facing pages
fit 16,000 encoded bytes with explicit omissions, exact paths and stable hashes.
Unicode-scalar text pages and raw JSON pages allow exact reconstruction. Only shown
fresh evidence enters this run's citation set. Older receipts grant no authority
and require refreshed evidence. Tool results and file assets remain distinct:
structured journals are SQLite data, file assets stay in the package asset folder.

Added history_search, history_read and tool_result to both native tool policies.
History search is scoped to the selected conversation and excludes the current
request/newer receipts. Descending keyset cursors survive append-only history writes.
Explicit tangent parent excerpts remain unchanged; the new tools cannot search a
sibling or the rest of a parent conversation. Conversation reconstruction reports
recent unresolved calls with operation proof rather than silently repeating them.
The bounded unresolved list is not the future complete recovery/resolution UI.

Verification: 59 core checks, including canonical v1/v2 migration, large result and
Unicode/NUL/decimal preservation, exact paged/raw reads, scope/argument refusals,
idempotent completion, call identity refusal, an injected mutation/receipt gap,
checkpoint/export/reopen and result-tamper detection. The shared-agent checks retrieve
an original beyond 110 recent messages and page an oversized table description.
The full check script passes, including 26 actual-tool grammar scenarios with 217
exact pinned reference masks, plus existing transport/prompt/streaming/grammar gates.
The repo-owned CLI skill validates.

Native qualification passes the existing seven autonomous jobs and a new three-step
history job on the 8K development context: six complete results, one proposal for
review and one deliberate cancellation. The history job retrieves MAPLE-27 from an
old original and does not invent currency. Evidence and source hashes are in
integration/evidence/2026-10-26-tool-journal-and-history.json. These are workflow
qualification runs, not a matched upstream performance comparison or speed claim.

Release app/CLI build, ad-hoc signature checks, isolated install/update/uninstall,
700-message migration/history CLI checks, packaged receipt CLI and 30 concurrent
writers pass. The packaged receipt check consumes an archive produced by the Swift
core and tests exact decimal/Unicode/raw pages, scope and argument failures, and
integrity. CI now includes it; the preceding 77034e7 public checkpoint has green CI.
The real installed app/CLI and user workbooks were not overwritten. New schema-3
packages need matching new binaries; older builds refuse them.

Next: automatic tool-free summary generation and exact-token compaction scheduling,
then long multi-step and repeated-compaction restart/kill qualification. Prepared
journals make outcomes inspectable; they do not yet resume or resolve a lost job.
Large structured results are loaded before projection, so streamed-result memory
qualification remains. Native downloads/setup, matched performance, production
backend packaging/adoption, complete UI/voice/search-scale and Workbook homepage
release work remain required. This checkpoint does not complete the app goal.


## Automatic context maintenance checkpoint, October 26 local / October 27 UTC

Implemented the controller, not the full C01–C13 release contract. The shared agent
uses the candidate adapter's exact rendered prompt count to maintain a working
context over append-only originals. Tool-free, constrained notes preserve exact
message references; the current request and latest complete tool group remain
intact. Host state supplies current item heads, meaning, acceptance, committed
operations and a bounded report of unresolved earlier calls. Checkpoint publication
checks the source range and revision atomically. No database schema change.

Typed durable user notes are retained across compactions; older unstructured
checkpoints remain verbatim as bounded legacy context. Tool-only digest claims
are shown as retrieval references, while operational state comes from the host.
Calculation and currency evidence that leaves working context must be inspected
again. Unknown/conflicting notes and originals remain available; note accumulation
and retirement still need qualification rather than silent forgetting.

Added message:ID citations for earlier conversation. They require an actually
visible original message older than the active request; current-request text,
search snippets and summaries cannot grant them. The existing conversation route
opens the earlier exchange. They cannot be used as business-record inputs. Read
results separately identify exact historical versus current item versions without
granting unseen evidence. Native grammar declarations/fixtures and both skills are
updated. Explicit no-change sentences get a host read-only allowlist, including
reversible drafts/spaces; this narrow rule is not general intent authorization.

Observed failures drove concrete changes. A large digest exceeded its output
budget; a smaller one forgot an exact value; a read-only recall proposed a table;
an 8K adversarial job exhausted context and teardown hung; another run cited an
older forecast version; conversion lost a legacy digest; a view omitted its table
component; and the conversation citation contract could leave a correct retrieval
without a valid completion path. Preserve these failures in
integration/evidence/2026-10-26-context-maintenance.json. Replaced Foundation's
unbounded worker wait with termination notification and bounded TERM/KILL waits;
a failed reap retains the model lease.

Verification: 59 core checks; 21 transport/preparation checks including 33 serial
shutdown trials and a TERM-resistant helper; exact tokenizer/streaming/grammar
checks, including all 248,320 vocabulary entries, 105 base masks and 217 masks for
26 actual-tool cases. Deterministic agent checks cover repeated maintenance,
changed acceptance, unfinished calls, invalid/cancelled digests, original history
hashes, complete tool groups, calculation invalidation, legacy retention, chapters,
tangent scope and original-message citation boundaries. The complete check script,
release app/CLI build, isolated install/update/uninstall, exact receipt CLI, 700-message
history/migration and concurrent-writer checks pass. Both repository skills validate.

Actual native results are mixed. Several earlier 32K continuity/recovery and
workflow probes passed, and the latest continuity run passes original recall,
portable reopen, current draft/accepted forecast checks and cancellation preserving
the prior checkpoint. Its explicit retry still searches business documents and
fails exact recall. Returned state complete is not a semantic task pass. Do not
mark C12/J10 or a 32K product default qualified. The earlier opt-in Slotstream
compaction probe also failed recall; its production capability remains off. Native
Splash remains a development candidate. The installed earlier app was preserved;
the new output bundle is still a Slotstream development build.

Commands used: scripts/check.sh, scripts/build.sh, scripts/check_install.py,
scripts/check_receipts.py, scripts/check_history.py, scripts/check_concurrency.py,
sevra-agent-checks --continuity/--context-recovery/--autonomous with the internal
32K profile, and --baseline-continuity for the preserved backend. Tokenizer and
actual-tool reference masks were regenerated with the pinned reference environment.
All workbooks were synthetic; existing model bytes were reused unchanged.

Next: improve reliable completion and retrieval using measured model/tool policies,
including a bounded reasoning comparison if supported by the pinned engine. Use
repeated end-to-end cases and retain every failed attempt; do not merely tune a
single prompt until it passes. Then continue native setup/downloads, matched
performance, packaging/adoption, full UI/voice J01–J10 and wider search/hardware
qualification. Broad process-kill recovery, general persisted-job resumption,
large-result memory/FTS coverage and the website rollout remain open. No universal
speed, full-context, or whole-app release claim.


Final current-source autonomous regression: five completed jobs, one proposal for
review and one deliberate cancellation pass on the 32K development profile. It
covers supplier data/lineage, deterministic comparison, both requested space
components, hostile evidence, missing records and a separate cancellation/retry.
This does not erase the latest continuity probe's failed recall after summary
cancellation. Both outcomes and the exact source hashes are retained in the same
evidence file.

The immediate follow-up is to evaluate unified, scoped search candidates across
business documents/records and original conversation. A model choosing the document
index should not incorrectly conclude that a remembered value is unavailable while
it exists in the same conversation. Keep result kinds, citation eligibility,
current-request exclusions, business filters and incomplete-index coverage explicit.
This is an implementation proposal to test, not a completed capability. Compare
bounded reasoning as a separate measured variable rather than conflating it with
retrieval changes.

## Scoped search follow-up, October 26 local / October 27 UTC
Committed and pushed the context-maintenance checkpoint as fdfc518. This follow-up
implements its proposed retrieval change. Agent search checks current business
evidence plus earlier original conversation by default. Business filters and
pages retain their scope, and conversation candidates require an original read
before citation. The two indexes share one snapshot; no schema change or model
change. The bounded no-match response now identifies the domains actually searched.

New deterministic checks cover two failed queries followed by a conversation-only
hit, message citation eligibility, current-request and later-message exclusions,
tangent isolation, Unicode/diacritics, separate cursor paging and rejection,
explicit business filters, partial extraction and cancellation. Actual-tool
declarations and pinned grammar fixtures were regenerated. The CLI skill states
the distinction between business search and the shared agent search surface.

Three consecutive native continuity trials pass on the unchanged 32K development
profile, with the same model/engine pins and no reasoning-mode change. Each checks
repeated maintenance, exact original code/decimal/unit and citation, offline
reopen, false tool-derived digest versus current draft/accepted forecast,
cancelled summary preserving the prior checkpoint, and explicit retry returning
WILLOW-12 / 0.20 kg. Some retries still took extra searches before reading the
original. Keep all trials, not just the fastest one. This fixes the observed
index-routing trap without claiming general model reliability.

Evidence and final verification: integration/evidence/2026-10-26-scoped-search.json.
The previous failed native attempt remains in the context-maintenance evidence.
Native Splash is still a candidate; no production compaction, 32K default,
performance superiority, broad restart recovery or whole-app release claim.

Follow-up review also fixed receipt-invalidated business cursors. The cursor now
binds a journal anchor and tolerates only audited non-business history operations
within a bounded suffix. The shared-agent twenty-item/two-page test proves that
actual prepare/complete receipts do not break continuation; separate-writer
evidence changes and wrong-domain cursors still refuse. No schema migration.
The earlier full native autonomous regression passes five completed jobs, one
proposal for review and one deliberate cancellation. A packaged preserved-backend
inventory question also passes with the correct balance and both evidence links.
Those probes precede the pagination-only adjustment; final checks and the final
native continuity repeat are identified separately in the evidence.

Final checkpoint result: scripts/check.sh, release app/CLI build, isolated
install/update/uninstall, history/receipt CLI checks, concurrent writers, both
knowledge gates and the CLI skill validation pass. The final native repeat fails
at draft-forecast inspection after successfully recalling originals and reopening
its portable workbook. It read the correct forecast, tried a record ID as a
message ID, and explored until the step limit. Do not promote the candidate or
claim four passing trials. Evidence retains the three earlier passes and this
current-source failure. The previously published fdfc518 checkpoint's CI passed.

Next investigate bounded reasoning as a separate variable using the pinned
upstream's actual semantics and grammar, and repeat the same acceptance cases.
The model must finish from inspected current state; more search steps alone do
not establish correctness. Native setup, matched performance, packaging/adoption,
full UI/voice qualification and broader scale/restart recovery remain open.

## Reasoning comparison plan, October 26 local / October 27 UTC
Owner asks to fix AI reliability first and compare bounded reasoning against the current setup. Freeze the initial comparison at the existing Qwen3.6-35B-A3B 4-bit/DFlash2 and Splash 1.4.1 pins, 32K context, 12 GiB native memory, the same prompt/tool definitions and 1,800 total output tokens per request. Compare reasoning disabled with an engine-enforced 512-token thinking budget. Keep tool-free summary generation unchanged and keep the twelve-step bound. Upstream server/backend.py supplies the budget; runtime/model/Runtime.cpp enforces it. Prompt, grammar and parser must agree on thinking mode, and measured prompt tokens must include it.

First verify budget encoding, exact templates and masks, output separation, cancellation and the forced thinking close. Then run interleaved paired trials over the same frozen synthetic workbook snapshots: current draft/accepted forecast despite a false historical digest, older conversation recall, deterministic inventory and missing evidence. Evaluate semantic answer, exact current citation, unchanged business state, complete terminal result, steps, unnecessary/repeated calls and whole-job latency. Retain every failure and record the exact binaries/source identities. Follow a promising result with complete continuity and autonomous-workbook regressions. This is a comparison plan, not an adopted default or claim that reasoning fixes the failure.

## Reasoning continuity investigation
The frozen first comparison is in progress. Initial failures include correct evidence retrieval followed by continued searching until the step limit; bounded reasoning also omitted a requested movement citation on one correct inventory answer. Do not describe these as solved by faster decoding or extra steps.

Adapter inspection found that parsed reasoning was discarded between tool calls. The pinned Qwen chat template retains reasoning_content after the latest user query, while the official Qwen3.6 model card recommends preserving reasoning context for agents. A separate correction now carries reasoning only in ephemeral current-request messages and includes its bytes/tokens in budget accounting. It does not enter saved conversation, receipts, business evidence or later requests; compaction may replace older intermediate state with the existing bounded evidence digest. The original mode-only comparison remains frozen and running against its original binary. Test the correction afterward on the same archived workbooks, not by changing the running comparison.

Primary reference: https://huggingface.co/Qwen/Qwen3.6-35B-A3B . The pinned local chat_template.jinja is the implementation authority. Published nonzero sampling recommendations are a further variable; this experiment keeps the existing greedy seed/temperature unchanged. No sampling or production-default promotion is inferred from those recommendations.

## Calculation provenance correction
The first mode-only comparison exposed repeated correct inventory totals with an omitted movement citation. The repaired candidate therefore combines ephemeral reasoning continuity with a shared host validation: after balance or compare_rows, finish must cite every inspected contributing input. An incomplete citation set receives an explicit validation error and a bounded chance to correct it; it is not recorded as a completed answer. The existing compaction reset also clears obsolete calculation obligations, while retaining the latest calculation's input set when that result remains visible.

This is an additional repair, not an isolated reasoning-history experiment. Compare its full behavior against the preserved mode-only results and label both changes. A model that reads the right value but does not supply requested provenance has not passed the workbook job.
The last initial bounded recall trial supplied the correct code/quantity from a history-search snippet with no original read or citation. Add a shared retrieval-grounding gate: after evidence candidates have been found, require an inspected citation before finish, except a successful space confirmation. Conversation candidates still need history_read. The existing host no-match report remains separate. Test snippet-only finish rejection and successful original-read recovery. This is included in the repaired candidate, not retroactively applied to the frozen initial scores.

## Frozen mode-only comparison result
The frozen mode-only comparison completed all thirty trials: off passed 12/15 and bounded512 passed 12/15. Off failed two accepted-forecast attempts and one recall at the twelve-step limit. Bounded512 completed every task but omitted a requested inventory effect citation twice and answered one recall from a search snippet without reading/citing the original. All thirty preserved business state, passed integrity checks and released the model. The raw median whole-job times were 26.20 s off and 30.84 s bounded, including fresh helper setup; these are small-suite observations, not a Python/native performance claim. Manual review additionally caught abbreviated UUIDs in one accepted-forecast answer. No mode is qualified by this result alone.

The repaired candidate is now compiled and passes the deterministic agent, privacy, history, compaction, template and grammar checks. It retains ephemeral reasoning, requires complete calculated provenance, refuses uncited answers after evidence retrieval, and rejects inspected UUID display prefixes. Those are explicitly combined repairs. Next run the native cutoff/cancellation boundary probe, then fifteen bounded follow-ups on the exact same archived fixtures, followed by full continuity and autonomous regressions. Keep the initial thirty outcomes unchanged. The published baseline checkpoint 26be0d2 CI passed before these edits.

## Answer basis follow-up
The first repaired follow-up exposed an uncited one-step draft-forecast answer from saved host context, before any retrieval tool ran. A retrieval-only guard cannot cover that path. The second candidate makes finish declare an explicit answer basis: evidence, current_request, completed_action, general or unresolved. Stored workbook and earlier-conversation claims use evidence and must cite inspected versions/originals. Current-request answers can use only the supplied information and checked arithmetic. Completed-action confirmations require an actually successful mutation in this run. General responses and unresolved gaps remain available without forcing irrelevant evidence retrieval.

This replaces the first repair's retrieval-triggered citation heuristic. It preserves full calculated provenance, opaque-reference checks, reasoning continuity and bounded validation feedback. The basis is an internal tool field, not a user setting. Validation failures retain its submitted value in the tool trace; successful answers retain the complete finish arguments in their stored payload, including the basis and citations. It is not an independent truth verifier: misclassification or incorrect interpretation can still fail semantic review. Regenerate all maintained tool/schema/reference-mask fixtures and compare both off and bounded512 again on the frozen workbook set after the first follow-up finishes.

## First repair and engine-boundary results
The first repaired bounded-only follow-up completed 15 trials: 14 passed. Every case preserved business state, passed integrity and unloaded. The one failure was a correct draft/estimate answer from saved context with no citation, before any retrieval tool ran. All inventory and original-history cases passed after host citation correction. Retain this failure; do not promote based on 14/15.

The full native boundary suite passed 12 cases: forced closes at budgets 1–8 and 512, cancellation during generation with no call, output-length truncation with no call, successful next request, and a forced split UTF-8 character. The split-character case needed 3 tokens at a budget of 1, closed cleanly, produced a complete valid call, and left Metal healthy with weights released. An earlier added fixture failed grammar setup because it inserted an unescaped quote into the outer JSON; correct its builder and retain that harness failure separately. The second candidate reserves three potential UTF-8 continuation tokens plus the close before its 256-token output allowance.

The second candidate's typed answer-basis protocol and deterministic tests compile and pass. Its tool/reference fixtures are being regenerated before a new thirty-trial off-vs-512 comparison on the same archives. All source and binary identities and prior results are retained in integration/evidence/2026-10-26-bounded-reasoning.json. No production-native or context-profile promotion yet.

## Answer-basis comparison result and final regressions
The second frozen thirty-trial comparison passed 15/15 automatic task checks with bounded512 and 13/15 with reasoning off. Both off failures were accepted-forecast step limits. All thirty trials preserved business state, passed integrity and unloaded. The startup-inclusive median job durations were 40.52 seconds for bounded512 and 29.76 seconds for off. This supports bounded reasoning for the next native candidate's reliability work; it does not establish a speed advantage, a statistical guarantee or production qualification.

Manual review found one additional semantic defect: bounded inventory repetition zero called the opening date an acceptance date. The stock and citations were correct; the extra date label was unsupported. Keep automatic scores separate from full semantic correctness. A separately identified final candidate adds only an explicit effective/creation/acceptance-date distinction to the model policy. It is now replaying all six inventory trials and the complete continuity, cancellation, boundary and autonomous workbook regressions. Do not combine these follow-ups into the frozen R2 comparison or discard the original defect.

The comparison executable now runs all trials and reports the summary before returning nonzero if any trial failed. Earlier A/R1/R2 results predate that exit-status improvement; their saved per-trial results remain authoritative.

## Reopen citation recovery and probe correction
The final date-policy candidate passed all six inventory replays and twelve engine boundary checks. Its first full continuity run passed; the second failed after portable reopen. It repeatedly submitted a correct quantity with basis=evidence and no citations, relying on an earlier run's read. The host refused success after four invalid finish attempts, and no business action was applied. Preserve this failure; the R2 15/15 small-suite result does not qualify repeated continuity.

R4 now narrows the next response to inspection tools when an evidence-based finish has no fresh inspected citations. Both adapters receive the same host-selected scope; native grammar excludes finish and mutations, and the host verifies the scope again before dispatch. One actual inspection restores the normal tool set. The original final-validation and twelve-step bounds remain. This does not grant citations from old summaries or replay actions. Deterministic tests also attempt a mutation during inspection recovery and require refusal.

The autonomous R3 probe stopped after a numerically correct supplier answer because its test required compare_rows specifically, although calculate is also permitted. The old output lacks the successful arithmetic receipts, so retain it as an incomplete probe, not a retroactive pass. The corrected probe records all arithmetic receipts, requires the exact 0.35 computed result through either permitted tool, and strengthens citation checks to require both actual row versions. Reopen, draft-forecast and cancelled-summary retry checks now explicitly require their original/current citations too. R4 build, grammar and fresh full-model qualification are in progress.

## R4 continuity checkpoint
Three consecutive R4 continuity probes passed with the stronger citation checks. Each completed repeated automatic compaction, exact code/decimal/unit recall, portable reopen, draft versus accepted-estimate authority, cancelled-summary preservation, explicit retry and unload. Intentional cancellation appears in each trace and is an expected assertion, not an unexpected failed task. Durations were approximately 173, 184 and 183 seconds for the entire multi-stage probe, not individual answer latency.

These repetitions have not yet triggered the new inspection-only recovery scope in a real model call. A separate labeled fault-injection probe has been added to exercise exactly that branch with both off and bounded512, after injecting only the observed invalid finish. Its compilation/execution and the autonomous/frozen-case regression results remain pending. Three successful repetitions still do not qualify all C12/J10, hardware or restart cases.

## Numeric grounding follow-up
R4 passed three full continuity repetitions, the autonomous workbook workflow and all twelve engine boundary cases, but passed only 14/15 frozen bounded trials. The remaining recall answer said quantity 120 instead of 0.20 kg, with no citation and basis=current_request. Its exact final payload was recovered from the still-open synthetic workbook before cleanup and preserved in the evidence file. Business state stayed unchanged, but the displayed answer was wrong; this is a genuine semantic failure, not a test-only mismatch.

R5 binds numeric claims under current_request to decimal-normalized values actually present in the current prompt or a successful, fully visible calculate receipt. Unsupported values trigger validation and a read-only recovery step when no fresh evidence is available. Inspected business/history facts must instead use evidence and citations. Calculation values are invalidated with the corresponding working context at compaction. This is a limited numeric guard, not a semantic proof of prose, units, intent, or every answer basis.

The fault-injection probe now injects both an uncited evidence finish and the fabricated current_request quantity, then delegates recovery to the actual native model in off and bounded512 modes. Positive checks preserve calculations from spelled-out user arithmetic. All future frozen-trial outputs retain successful terminal tool payloads so basis misclassification can be inspected directly. R5 deterministic and grammar checks pass; real-model fault injection, fifteen bounded trials, continuity repetitions and autonomous work are underway. Setup/performance/adoption work remains behind this reliability gate.

## R5 recovery fixture correction
The initial controlled recovery probe returned all four correct original quantities with citations and an actual inspection-only first model call. Its final bounded/current_request response said “0.10 and the unit was kg”; the fixture required the contiguous phrase “0.10 kg” and exited nonzero before its remaining integrity/unload assertions. This is a test-only mismatch. Keep the failed exit and raw output, check quantity and unit independently, and repeat all four cases after the current cohort finishes. The runtime remains unchanged during the cohort. Its independent frozen comparison, continuity and autonomous checks are still in progress.

## Preserved-backend request continuity follow-up
The first final packaging pass succeeded through build, isolated installation, resources, history/receipts, concurrent writers and URL capture. Its full Slotstream model regression passed comparison and space creation, then failed the next delivery-terms question: it returned the previous comparison answer after twelve steps. This is a genuine wrong-task response, not a wording mismatch. The original script did not retain successful-response tool receipts before an assertion, so the failure preserves the exact answer and check status but cannot establish the full causal trace. The first nine checks and this failure remain in the evidence.

Inspection found a representation difference: the non-compacting path replayed earlier user requests as live user-role messages, while native context maintenance presents saved conversation as explicitly historical data before the active request. The next candidate uses the same boundary for the non-compacting path without enabling summarization: bounded original IDs, authorship, states, text, truncation flags and current proposal status are carried as historical context. The actual current request remains the user-role message. Original messages and receipts are unchanged. This is a hypothesis-driven repair, not a proven explanation based on the missing old trace.

Deterministic checks pass for the historical envelope, cancellation/failure status, current proposal acceptance/meaning, JSON authorship, original IDs and fresh active-request separation. The model probe now saves every answer and current-run tool receipts before its semantic assertions. Full preserved-backend regression and native non-compacting history/recovery verification are next. R5's compaction-enabled frozen and continuity results remain identified separately; do not relabel them as runs of this later source tree.

## Bounded reasoning verification checkpoint
The final R5 bounded follow-up passed all 15 frozen automatic task checks, two full native continuity probes and the autonomous workbook workflow. Runtime source remained unchanged during those R5 trials. A later non-compacting history correction is verified separately below. They cover exact original code/decimal/unit and citation, portable reopen, draft/accepted-estimate distinction, cancelled summary preservation, explicit retry, deterministic supplier comparison, generated spaces, hostile evidence and missing evidence. All fifteen frozen trials preserved business state, passed workbook integrity and unloaded. Median setup-inclusive job duration was 42.20 seconds. This is a separate follow-up, not the R2 paired comparison or a matched engine speed benchmark.

The final history-projection candidate also passes the native non-compacting history check. The four controlled recovery cases initially stopped on a test-only exact-phrase mismatch. After checking quantity and unit independently, the repeated off/bounded512 and evidence/current_request cases all passed, including actual inspection scope, original citation, business-state preservation, integrity and unload. A deterministic CI fixture also rejects the fabricated current_request quantity and requires original inspection. R4's twelve real-engine reasoning boundary cases remain applicable: its engine, grammar and reasoning implementation are unchanged. Earlier failures remain preserved, including the incorrect quantity, uncited reopen, date mislabel and original control results.

Manual review still finds one broader evidence-scope defect in R5: accepted-forecast repetition two makes an unsupported workbook-wide absence claim after non-exhaustive searches. Its core forecast answer is correct. Keep this separate from the automatic task score. These results repair the observed recall/citation paths and demonstrate recovery; they do not qualify general grounding, all C12/J10, physical low-memory hardware or production adoption.

Final validation passed scripts/check.sh, release app/CLI build, isolated install/update/uninstall and skill installation, packaged resources, history and receipts, concurrent writers, URL capture, and all real-weight preserved-backend checks. The latter cover comparison/generated space, hostile evidence, incomplete search, proposal/accept/undo and cancellation/restart. The missing-evidence test now also recognizes the existing host-authored no-match report while still requiring its explicit evidence-gap statement and incomplete coverage. No runtime change was made for that test correction.

Specifications, design review, fixtures, exact source/binary identities and all failed/successful trials are in this repository. Evidence: integration/evidence/2026-10-26-bounded-reasoning.json. The built package remains Slotstream; the user's installed app was not replaced. Automatic compaction remains disabled in that production backend. Splash and bounded512 remain internal candidate settings.

## Preserved-backend history correction result
After the historical-envelope correction, the complete packaged Slotstream regression passes comparison/space creation, then the distinct delivery-terms request with its citation and no injected mutation, missing evidence, table creation and cell-edit proposal/accept/undo, and cancellation/restart. Every successful ask now saves its response and current-run receipts before assertions, so semantic failures will not lose that evidence again. The original failed second request remains in the public evidence, alongside the missing-trace limitation. Passing this sequence supports the repair but does not prove perfect task selection across arbitrary conversations.

Final full checks, release build, installation and resource/history/receipt/concurrency/URL checks were repeated after the source change. Both modes of controlled native recovery and the native non-compacting old-history probe also pass. Compaction-enabled R5 results precede this isolated projection change and retain their own identities. No automatic compaction, native backend or new installed-app default was enabled.

## Search-coverage correction in progress
The owner prioritized the observed R5 search overclaim before native Splash setup. Added an exact SQLite current-head count, typed finish coverage receipts, finish-time count revalidation and host-rendered scope. A conservative prose guard rejects the observed unsupported absence/exhaustiveness wording even when the model labels it general or unresolved after retrieval. This is a bounded language guard, not general truth verification.

Deterministic checks pass for a real movement missed by lexical search, current versions without double counting, accepted-estimate filters, unindexed Sources, cancellation, invalid filters, malformed/forged receipts, changed counts and recovery from the original overclaim. Tool/reference grammar regeneration and real-model cases are next. Native setup follows; production remains the preserved Slotstream build.

## Search scope and native setup checkpoint, October 27 UTC
The initial focused six-case trial passed one automatic case: two positive counts had the wrong integer display, empty-count prose failed to recover from rejection, and the off forecast exhausted validation. A formatter correction itself first failed a deterministic check. Explicit feedback then passed all six. A further review tightened the host boundary: when counts are the only evidence, display only their verified scope, so a valid receipt cannot authorize unrelated model prose. Final targeted testing passes 6/6; count answers take two tool steps and no zero-count wording retry.

One attempted final cohort collided with the still-running baseline regression. The shared lease refused all six before inference; this was test scheduling error, not six generated-answer failures. Its raw results remain in the evidence, including the older probe's mistakenly included fixture receipts. The probe now filters only runs created by that invocation, and the correctly serialized final cohort passes.

Native setup has 28 adapter/setup checks, including partial/range handling, corruption, cancellation, symlink/hardlink refusal, storage and hardware preflight, atomic preparation and prior-install preservation. The initially failing URLProtocol interruption fixture assumed delivery timing; the final fixture starts with known partial bytes and checks exact retry behavior without that assumption. Live HTTPS target/draft config transfers and resumed transfers pass. The full existing 21,481,463,614-byte pack was verified and reused without downloading duplicate weights or invoking Python. The new assembly passed native model-check and four complete generations, one intentional cancellation, context refusal, healthy Metal state and weight release.

There are now 23 maintained tool declarations, 27 complete tool grammar cases and 228 exact workbook mask comparisons. The original reference engine and model pins remain. See integration/evidence/2026-10-27-search-coverage-setup.json and [[records/operations/build-and-run]] for commands and limits. No native production promotion, whole-machine hardware qualification or Python/native performance claim is made.

## Native product migration in progress, October 27 UTC
The shared workbook inference layer has been separated from Slotstream into an engine-independent module; the baseline implementation lives in SevraBaseline. Baseline compilation and the existing tool grammar fixtures pass after the separation. Installed model opening now checks exact selected source identities and revalidates original files; 29 native adapter/setup checks pass, including changed originals and cancellation.

A real fresh 21.5 GB Swift-only installation is in progress. It was deliberately cancelled after retaining 130,690,940 bytes of the first weight shard, then resumed from those bytes. No model selection was published during the interrupted attempt. This establishes live cancellation/resume behavior, not completion of the full installation. The active transfer continues while independent implementation work proceeds.

The app and CLI are being connected through SevraProduct to an isolated native preview. Packaging, resource failure checks, actual installed-layout workbook jobs and matched performance remain pending in this checkpoint. The existing installed app has not been replaced. Preserve both failed and successful qualification output.

## Native preview findings, October 27 UTC
The isolated native preview compiles and packages successfully. Installed app and CLI resource checks pass with build-folder reads denied; both load 1,888 Metal functions and the pinned grammar dylib. Nine missing-resource cases and altered Metal bytes are refused. The app passes strict deep signature verification while preserving unchanged Splash engine and Metal hashes. Native app and CLI contain no baseline module symbols, and live inference process mapping samples contain no Python, MLX or Slotstream runtime mappings. A single memory sample is not a performance or peak-memory qualification.

Packaging failures are retained: license metadata initially invoked an unintended default Rust toolchain, full workspace metadata requested unbuilt development crates, unsigned Metal files in Helpers failed signing, and the check script initially could not locate swift-demangle. The fixes pin the metadata toolchain, collect the built normal dependency tree offline, keep Metal bytes sealed under Resources with bundle-local links beside the helper, and locate the Swift tool through xcrun.

The first native workbook suite exposed an unnecessary duplicate table proposal. The agent now discovers and reuses existing datasets for views; the subsequent comparison and hostile-document cases pass. The next run exposed an irrelevant total-count answer to a missing-document question. Missing-evidence finishes now display host-owned search queries and indexing limits, including when accompanied by exact counts. The current rerun has passed comparison, hostile-document and missing-evidence cases; remaining cases are still running.

The preview Settings visibly discovers the existing Fast pack, verifies it and reports Model files are ready. A verification-path review found that revisiting setup after reuse could download duplicate weights; native setup now checks the existing pinned installation first. The fresh managed full-weight download continues separately and has reached the fourth target shard. Completion and subsequent jobs on that fresh installation remain pending.

## Native setup and packaged workbook checkpoint, October 27 UTC
The fresh managed download completed and verified all 11 original files from the pinned target and draft revisions. Its files are regular originals inside the new managed snapshots, with no reuse of the earlier weight directory. The interrupted attempt never published a selected model. Resuming reused the retained bytes. The native packaged CLI completed the full workbook suite against this installation.

The four earlier native workflow attempts are preserved. They exposed duplicate dataset proposals, an unrelated count replacing a missing-document answer, a fixed value replacing a requested formula, and a prompt-only formula repair that still failed. Discovering existing datasets and host-owned search-gap reports fixed the first two. LLGuidance nested property ordering caused the formula omission: alphabetical optional formula came before required id and became unavailable after id was emitted. Required-first nested ordering now matches all 249 reference masks and produces the requested formula. Types, required fields, open row data and final validation remain intact.

The native product uses only installed resource locations and verifies helper, Metal and grammar hashes. Portable grammar install names, sealed Metal resources with bundle-local links, pinned build tools and transitive notices now survive strict signing. Native Settings reuse completes visibly; an offline setup recheck verifies the existing assembly without network access or duplicate snapshots. Verification progress no longer displays a meaningless zero-byte transfer. A live process-map sample shows a 333.9 MB Swift footprint and 11.6 GB helper footprint, but does not establish peak total memory or a supported hardware envelope.

All nine fresh-install native workbook checks and all nine rebuilt baseline checks pass. Complete deterministic regressions and the CI-compatible packaging check pass. The missing-model packaging check was accidentally overlapped with the baseline suite and correctly refused the shared inference lease; its serial rerun is retained separately. Earlier compile, license collection, signing, tool-location, compaction-fixture and CI-check failures remain in the new evidence file. Behavioral timings include changing development conditions and are not matched performance evidence.

The separate live-formula runs pass on both backends: accepting the planning table yields 7.5, changing quantity from 3 to 4 recalculates 10, and the supplier edit still supports acceptance and undo. The actual native app completed an eleven-step comparison, displayed 3.5 and 12.73%, opened the Purchasing table/chart, and navigated to the cited original and back. Its persisted run and workbook integrity checks pass. It also appended an unnecessary scoped note count, which remains an answer-focus/polish issue. The preview was closed after inspection and its helper exited.

This checkpoint does not replace the installed baseline, enable automatic compaction, qualify arbitrary Macs, establish a speedup or complete the application. Remaining gates are listed in Current direction above.

## Matched request cohort, October 27

The frozen R1 cohort at f74164048bc8fddff87a4726ff907e55ee826c44 completed ten alternating paired blocks on the M5 Pro / 48 GiB reference Mac. The unchanged Splash helper, selected target/draft bytes, 32K allocation, 12 GiB engine budget, greedy seed 42, cache setting and inputs were shared. There were 300 total requests: 100 warmups and 200 measured requests, twenty measured samples per workload and frontend. The largest rendered prompt had 13254 tokens. This does not qualify a full 32K or 64K occupied conversation.

All 150 paired prompt/prefix/generated-token sequences matched, including warmups. All measured requests passed their declared semantics. Every workload met the fixed latency thresholds. Complete request seconds:

| Workload | Swift median | Reference median | Swift p95 | Reference p95 |
| --- | ---: | ---: | ---: | ---: |
| plain_copy | 1.819 | 1.827 | 1.878 | 1.846 |
| unicode_json | 0.919 | 0.916 | 0.937 | 0.926 |
| occupied_lookup | 0.701 | 0.703 | 0.713 | 0.717 |
| workbook_table | 3.517 | 3.523 | 4.030 | 4.036 |
| workbook_finish_history | 12.575 | 12.550 | 13.767 | 13.705 |

The overall preregistered request gate FAILED. Four warmups, two per frontend, invented a dollar sign in the comparison answer. They occurred in blocks 4 and 9, where the history/finish request came first after startup. Both frontends produced the same invalid answer. Preserve the failure; do not relabel the cohort as a full pass or weaken its success requirement. This is raw-model behavior, not evidence of a Swift parity regression. The workbook host already refuses that unsupported symbol; four separately labeled fault-injection trials now verify actual-model recovery through that guard.

Process-launch-to-ready medians were 4.698 seconds for Swift and 5.683 seconds for the reference. These are process-cold with uncontrolled OS file caches, not SSD-cold loads. Observed request-time sums of frontend/helper physical footprints peaked at 11.896 GiB and 12.179 GiB respectively. Sampling was every 0.2 seconds; startup has individual process lifetime peaks, not a simultaneous sampled total. This is not whole-app memory qualification. Preexisting swap stayed at 411.94 MiB. Thermal state reached fair, never serious/critical; no paired blocks were excluded and no helpers or sampling calls failed.

The cohort exited 1 as required. Full sanitized configuration, identities, prompt arrays, outputs, status, memory traces and environment receipts are in integration/evidence/2026-10-27-native-performance-cohort1.json. Checkpoint f741640 also passed hosted CI run 40455955224. These measurements support matched request latency and token parity on this one profile. They do not establish a general speedup, complete workbook-job performance, broader hardware support, automatic compaction or production adoption.

## Currency recovery after the matched cohort

The replay test now exercises the existing workbook host with the observed invalid comparison answer. It first injects a deterministic compare_rows call and the invalid finish, then delegates correction to the real native model. Two reasoning-off and two bounded512 trials each start a fresh helper against the freshly downloaded native model assembly. All four pass: one recorded validation rejection, no invalid assistant message, a corrected complete answer with both row citations, unchanged original business items, exactly one expected user-request Source, workbook integrity and successful unload.

The first deterministic test attempt incorrectly forbade the host-owned request Source and failed before model inference. That assertion was corrected to require exactly that expected addition while preserving every original item. Both the failed preflight and successful traces remain in integration/evidence/2026-10-27-currency-recovery.json. These are labeled fault-injection/recovery results, not autonomous task or latency qualification. Three trials used three steps; one bounded trial used five. Correction has a real latency cost. The existing symbol guard required no production change, and this evidence does not turn the failed R1 raw-model cohort into a pass.

Read-only review during the cohort identified follow-up cases to reproduce: stale asynchronous table results after rapid sort changes; row selection/edit identity after refresh or reordering; and memory pressure during an active model operation, when idle-only unload currently returns false. These are review findings, not completed fixes. The native app/CLI rebuild, packaged resource/signature/refusal checks and all nine packaged real-workbook checks pass after the prompt-cache change. The comparison job naturally produced the same unsupported currency and opaque IDs; the host refused them and obtained a valid answer before publication. Cancellation preserved integrity and the subsequent stock-balance request completed. Full sanitized traces and binary identities are in integration/evidence/2026-10-27-native-post-cohort-workbooks.json. These are behavioral checks, not matched complete-workflow latency qualification.

## Native table identity and asynchronous refresh, October 27

A direct AppKit reproduction on the previous grid returned false for both stable selection and original edit identity after row order changed. The grid retained row indexes and resolved an editing field against the new row array. The old load completion also checked only filter and offset, allowing an earlier sort to overwrite a newer one.

The grid is now an independently testable native component in SevraTableUI, used by the app without an additional runtime dependency. Selection follows logical row IDs; editing fields retain the exact immutable row, column and snapshot revision. Ordinary edits and multi-cell paste use that revision, so the existing transaction gate refuses concurrent changes. Cancel and duplicate editing-end notifications do not write. Copy uses displayed values. A single SQLite read transaction captures rows, schema, formula values, total and revision off the main actor. Referenced-row changes refresh formula cells even when the visible row version itself is unchanged.

All query inputs participate in SwiftUI task identity. A generation guard and cancellation check discard out-of-order successes and failures. Programmatic AppKit/database checks cover reorder during edit, stable selection through correction, actual concurrent writer refusal with unchanged evidence, filtered-out selection, cancelled/duplicate editing, referenced-row formulas, column identity, same-row paste target selection, old query/error completion and cancelled reads. The new sevra-table-ui-checks runner is part of scripts/check.sh and hosted CI.

The full local regression, final targeted table runner, native app/CLI build and packaged resources/signature/refusal checks pass. The visible app also preserved Oak selection after sorting, edited the correct row with formula recalculation, and refused a pending quantity 13 after a separate CLI writer committed 7. The error was displayed; database history contains only accepted quantities 11 and 7, never 13, and integrity passes. Filtering away the selected row clears conversation context. Evidence and source/binary identities are preserved in integration/evidence/2026-10-27-native-table-safety.json. These tests do not complete general UI/accessibility/media/voice qualification. Active-inference memory-pressure handling remains the next native lifecycle finding to reproduce and resolve.

## Active memory-pressure lifecycle, October 27
The app previously responded to both warning and critical pressure by asking an idle-only unload method to release the model. During an active request that returned false, so the notification did not interrupt or arrange later release. The observer now belongs to ProductAI and covers both app and CLI. Warning pressure allows completion then releases; critical pressure cancels with an explicit low-memory cause, preserves committed workbook changes and releases only after endRun. New operations remain excluded during cleanup, and failed release must succeed before reuse. Ordinary user unload does not interrupt active work. Setup also preserves pending-release state if it cannot stop the previous model.

Synthetic lifecycle checks cover saved work before interruption, cancellation cause, release ordering, warning completion, concurrent-request refusal during held cleanup, failed release/retry, setup-release failure and parent cancellation. The shared cancellation path retains the first cause in the saved assistant diagnostic. The runner is part of local checks and hosted CI.

The actual native model passed injected critical pressure, warning completion with the requested Ready answer, and a fresh cited stock answer after release. Native helper PIDs were gone and the cross-process inference lock was independently acquirable after each release. All nine packaged native workbook checks passed, including formulas, proposal review/undo, scoped counts, hostile documents, missing evidence and cancellation/restart. These actual-model tests precede the final one-line setup-error guard; source/binary identities distinguish that revision from the final synthetic and packaging checks.

The preserved reasoning-off baseline exposed a separate semantic failure: after cancellation, the new request to reply Ready answered the old stock question. Automatic context now carries stopped requests as status plus a reference to the preserved original, including summary input/presentation, instead of repeating the old imperative. Two subsequent baseline trials still answered with an unrelated Home-space summary. Those failures remain failures. The final baseline collector separately proved critical cancellation, warning completion, lock release after each, a subsequent cited stock answer of 18 and explicit unload. Lifecycle passed, request semantics failed, and the overall process exited 1. The preserved baseline build and isolated install/update/uninstall/skill/conflict checks passed. Resource lifecycle and following the current request remain separate gates.

This is policy-event injection, not actual OS memory-pressure delivery or RAM exhaustion. Baseline lock release does not measure its total physical footprint. Whole-app headroom, broader hardware, crash-left running requests, failures before run linkage and general request relevance remain open. The prior matched R1 raw-model currency failures also remain open. Native adoption and automatic compaction remain disabled. Full traces, failed trials and exact build identities are recorded in integration/evidence/2026-10-27-memory-pressure.json.

After the final setup-error guard, the full local regression, native and baseline app/CLI builds, native installed-resource/signature/refusal checks, isolated baseline installation and native synthetic lifecycle runner all passed. Knowledge-store validation and repository links have zero errors. Earlier CI checkpoints 31ea247 and 4795fc7 both completed successfully. New changes require their own hosted result. See [[records/specs/intelligence]], [[records/specs/conversation-context]] and [[records/operations/build-and-run]].

## Atomic request admission and crash recovery, October 27
The previous startup sequence assembled recent history before startAgentRun closed abandoned running requests. A model-lease failure could also leave a user message with no linked terminal outcome. The new synthetic reproduction returned false for both expected protections while confirming another active run was preserved.

The shared agent now acquires the inference lease, atomically persists the request/run/link and closes prior abandoned runs, then builds context strictly before the new request message. A refused lease or pre-acquisition cancellation writes its own original message, linked terminal run and diagnostic atomically without changing another run. Failed admission rolls back and releases only a lease actually acquired. Original history and committed workbook actions remain intact; an uncertain prepared tool receipt is shown with its operation proof and is never automatically replayed.

The expanded synthetic checks pass for interrupted-request projection, lease refusal, cancellation before acquisition, atomic rollback, one-transaction revision advancement, current/later message exclusion, cross-conversation boundary refusal, exact original preservation and a saved draft whose final tool receipt was interrupted. Fixture development initially failed because Message is not Equatable, then because the saved draft omitted its required source lineage. Both failures are retained; a stale runner executed after the first compile failure is explicitly not validation of the expanded tests.

The packaged native process-death probe passed. It killed its spawned CLI during actual inference, observed the native helper exit without forced cleanup, reacquired the model lease, forced a new request to fail under a held lease and verified the earlier run stayed untouched. A subsequent Ready request completed in one model step, changed the abandoned run to interrupted and preserved original messages, business items, spaces and database integrity. This is a real process-death check during inference, not a crash at every filesystem or mutation boundary.

The full local regression, native app/CLI build and native installed-resource/signature/refusal checks passed. The preserved-baseline app/CLI build and isolated install/update/uninstall/skill/conflict checks also passed. Its four targeted checks passed: exact scoped movement and invoice counts, cancelled-run persistence/integrity, and a subsequent cited stock answer. These checks do not retest or resolve its earlier Ready-request failure. Prior baseline Ready failures, matched raw-model currency failures, whole-app memory/headroom, broader context/hardware and native release adoption remain open. Evidence is in integration/evidence/2026-10-27-request-admission.json; reproduction commands are in [[records/operations/build-and-run]].
