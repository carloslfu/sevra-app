---
type: operational
meta-type: conclusion
id: 01m5rbxzcsjnewm0pwmb9a06cj
created: 2026-10-25T01:48:47.385772+00:00
updated: 2026-10-27T12:24:37.149678+00:00
summary: Ordered work and honest requirement status for the first Sevra release.
title: Implementation and acceptance
---
# Implementation and acceptance

This is a working development build, not a qualified release. Requirements in the
specifications remain the acceptance contract. A source commit does not imply that
every requirement or supported hardware profile has passed.

## Current direction, October 27

This remains a development build. The installed app uses the preserved Slotstream
baseline; the separate native preview uses the Python-free Swift adapter and
unchanged pinned Splash C++/Metal engine. Automatic compaction and native
production adoption remain disabled pending their recorded gates.

- Search overclaims and exact reference selection have host-side safeguards and
  real-model regression evidence. Empty searches report the actual queries and
  incomplete-source count; they do not establish that a document does not exist.
  These are bounded checks, not general semantic truth verification.
- Native setup has completed a fresh 21.48 GB download, cancellation/resume,
  digest verification and atomic publication. Settings cancellation, explicit
  reuse and reverification pass. Both packaged variants and isolated installation
  pass on the recorded Mac; broader hardware remains unqualified.
- The latest corrected W1 pilot passes all sixteen jobs, two Ready primes and
  32 exact paired requests/outputs. The full ten-block cohort is running on frozen
  ed6ffd0. Its first two completed pairs matched all jobs, requests and generated
  tokens. This partial run is not a performance result. Preserve the earlier
  failed W1/I1 and R1 attempts and all correction latency.
- Native table identity/stale edits, paginated search/Back, PDF/OCR/CSV intake,
  inherited citations and long-conversation navigation have focused automated
  and visual evidence. Six native continuity requests pass across three
  checkpoints, including current acceptance/withdrawal and portable recovery.
  That does not complete C12/C13 or the full J01–J10 journeys.
- The isolated codex/voice-lifecycle branch repairs permission/recognition races,
  typed draft replacement and incomplete playback cleanup. The 14-check voice
  step passed on 7f93617 in hosted CI run 40502209056; its remaining checks are
  still running. Run 40501522585 on superseded 04ce5c2 was cancelled before the
  voice step. Local execution, hardware recognition and native visual replay
  remain pending. See Voice and media lifecycle repair below.
- The descendant codex/context-durability branch adds four checkpoint publication
  checks at real transaction/process-death boundaries. Commit c0ac40f is running
  in hosted CI 40503178418. No durability result is claimed yet; see Checkpoint
  publication process-death checks below.

Next, finish and assess the frozen W1 cohort, then locally test and integrate the
voice/media repair. Continue occupied-context and repeated-compaction recovery,
whole-app memory/headroom, search scale/interruption and full native accessibility,
media and installation journeys. Promote the native runtime, remove baseline
product dependencies and qualify a release only after the applicable gates pass.
[[records/specs/splash-integration]], [[records/specs/conversation-context]] and
[[records/operations/build-and-run]] own the contracts and reproduction commands.

## Earlier checkpoint summaries, October 27

The following passages retain earlier development states. Statements about tests
not yet run apply to those checkpoints; the Current direction above is the current
status. Detailed retained failures and later results remain in the sections below.

Latest checkpoint: I2 passes both cache arms, and the corrected normal-cache W1 pilot passes all sixteen jobs plus two Ready primes with 32 exact paired requests. Full regression and both packaged builds/resources/install checks pass. The preregistered ten-block W1 performance cohort is now running on frozen ed6ffd0; no speed or adoption claim follows from the pilot. See Corrected complete-workflow pilot below.

Workbook is Sevra's primary product/homepage, with Websites secondary. The installed app remains the preserved Slotstream baseline. A separate Python-free native Splash preview now uses the shared workbook agent through SevraProduct, with the unchanged pinned C++/Metal helper, native grammar library and Swift setup. It is not yet the production default.

The observed search-coverage failures are corrected at the host boundary. Exact classified-record counts come from SQLite and finish-time revalidation. Missing-evidence finishes after empty searches display actual queries and indexing limits, including when the model tries to substitute an unrelated count. Other answers reject recognized unsupported absence/exhaustiveness wording. This is bounded grounding, not general semantic truth verification. The earlier six-case reasoning-off/bounded512 evidence remains in integration/evidence/2026-10-27-search-coverage-setup.json.

Native setup completed a fresh 21,481,463,614-byte target/draft download, with a deliberate cancellation after 130,690,940 retained weight bytes, safe resume and verified atomic publication. The packaged native CLI then passed all nine workbook checks on those fresh files. The rebuilt baseline passed all nine too. Native Settings reuse and offline reverification pass without duplicating weights. Settings has now started a fresh download, cancelled it, resumed its retained partial file, cancelled again and restored/reverified the earlier installation. A stale downloading label after cancellation was reproduced and fixed; cancellation, ordinary failure and success now have distinct terminal UI states. A complete fresh 21.48 GB download solely through the UI was not separately run.

The native preview app and CLI pass installed-resource checks with build-folder access denied, nine missing-resource cases, altered Metal refusal, missing-model guidance and strict signing. Both load 1,888 Metal functions; native binaries and a live process-map sample show no Python, Slotstream or MLX inference runtime. SwiftPM still resolves baseline source dependencies for comparison targets. A fresh-checkout native preview build and packaging check are now part of CI; checkpoint 8adaa855 passed the complete hosted workflow, including the isolated preview build/package check (run 40454053852). New commits still need their own CI result.

The final full regression has 59 core checks, 30 native adapter/setup checks, 24 exact prompt fixtures, 80 streaming fixtures, all 248,320 vocabulary entries, 105 base grammar masks and 249 masks across 28 actual-tool grammar cases. Required-first nested property order fixes optional formula omission without weakening schemas. Real workbook tests cover comparisons, hostile documents, missing evidence, proposal acceptance/undo, scoped counts and cancellation/restart. Additional native and baseline table runs prove formula recalculation after an input edit. One actual native UI comparison completed with a generated table/chart, opened its cited source, and returned to the space through Back. See integration/evidence/2026-10-27-native-product.json for failed attempts, final results and commands.

Next: matched reference/native request and workbook performance, total memory/headroom, wider evidence-grounding evaluation, complete native UI/media/voice/accessibility journeys, and remaining search scale/interruption recovery. Production adoption, wider hardware support and release qualification remain open. Automatic compaction remains disabled in both product paths. [[records/specs/splash-integration]] and [[records/specs/conversation-context]] control those gates.


The matched native/reference request harness now has three retained pilots in integration/evidence/2026-10-27-native-performance-pilots.json. Pilot 1 exposed an NFC expectation error, an ambiguous title and mismatched tool prompt ordering. Pilot 2 matched prompts but missed nested property normalization inside wrapped reference grammars. Pilot 3 passed all five workloads with identical prompts and generated tokens, no semantic/sampling failures and no power/thermal exclusions. It is one sample per workload/backend, not a performance qualification.

Swift now probes the pinned template's generation suffix once and reuses exact large envelopes in a bounded four-entry, 8 MiB payload cache. Scalar type identity, signed zero, reasoning flags, changed histories and current context limits are preserved. The full local regression passes 24 exact prompt fixtures, the existing 80 stream/105 base-mask/249 actual-tool-mask checks, core and setup checks, plus benchmark gate failure tests. Native assembly reverification passes. The fixed ten-block R1 cohort is complete: recorded latency thresholds and token equality were met, but its overall gate failed on four matching raw-model currency errors in warmups. W1 review subsequently found unmatched foreground/normal request priority, so R1 also does not establish performance under fully identical parameters. Four labeled actual-model currency recovery trials now pass in off/bounded512 modes. This does not erase the raw-model failure; complete validated-workflow performance remains open. The installed baseline remains unchanged; see Matched request cohort below. Native table row identity and stale-query fixes now pass programmatic and visible-app checks; see Native table identity and asynchronous refresh below. The active-inference pressure policy now passes synthetic checks and actual native/baseline lifecycle probes; the preserved baseline still fails the unrelated Ready follow-up, so its combined probe remains failed. See Active memory-pressure lifecycle below. Atomic request admission now also passes abandoned-run, lease-refusal and real native process-death recovery checks; see Atomic request admission and crash recovery below.

The W1 complete-workbook pilot exposed both test-harness errors and a real repeated-ID answer failure. Exact offending-reference feedback and durable final-rejection receipts now pass the full local regression. Formula acceptance/edit/undo has its own no-model preflight. W1 now captures normalized actual request bytes and explicitly matches foreground priority; the revised pilot passed all sixteen jobs and both priming requests, but failed its strict request/generation comparison gate. Four same-wire request pairs produced different tokens. No qualifying W1 cohort has run. Preserve prior token divergences and failed runs. See Complete-workbook qualification below and [[records/specs/splash-integration]].

W1 retains a verified cache-comparison mismatch. I1's fresh workers per workload completed all sixteen jobs and eight primes, but supplier generation still differed at equal initial/later cache counters. Formula, inventory and missing-evidence pairs matched exactly. A qualifying performance cohort is not justified by this failed diagnostic. Shared application recovery is separate: typed balance references remove an opening-source versus conversation-ID confusion, and validated item IDs in plain prose now render as named native citations without another model turn. The subsequent four-job native/reference stock replay passed with no rejected finishes or history/count detours. The earlier packaged-app fresh-UUID failure is preserved. Exact read/lineage selection is now constrained to visible IDs verified in the workbook, separately from citation authority. The fixed R2 cohort completed twelve jobs with correct references and unchanged business state, without wrong-ID calls or rejected finishes. Both seed-6 cases still made unnecessary count queries, so R2 failed its stricter UX gate. The following count-purpose clarification now passes the entire fixed R2 replay, with 2, 5, 4, 4, 5 and 4 steps on each frontend and no count/history detours or rejected finishes. Original failed runs remain preserved. See Count-purpose reliability below. See Fresh-worker comparison and calculation-reference recovery below. Checkpoint a1906b0 completed hosted CI run 40487397938 successfully. New changes need their own hosted result.
Native import/search acceptance now covers a synthetic CSV, two-page PDF, OCR receipt and 35 paginated notes. Back preserves the second page; stale reads cannot replace the current query. PDF text-selection context uses the selected pages rather than the previously visible page. Native setup reverification, final app/CLI packaging, resource refusal and isolated installation pass. See Native search navigation below.

The latest native 32K/bounded512 continuity sequence passes six requests across three checkpoints, current acceptance/withdrawal, corrected original quantities, portable stock recovery, inherited tangent citations and a return to main. A reproduced parent-excerpt retrieval refusal is fixed without expanding branch access. Two opaque-ID finish corrections remain in the passing trace. The native UI now preserves paged search navigation, opens long conversations at the latest message, follows inherited citations to the correct original and shows new messages at the fixed history-window limit. Full regression, packaged search/count checks on both runtimes, final packaging/resources/install and focused visual checks pass. See Native multi-stage continuity plan and Inherited history and conversation navigation below. Automatic compaction and native production adoption remain gated; this is a functional checkpoint, not complete C12/C13 or release qualification. Checkpoint 95a1629 CI passed (40491316063); the new checkpoint requires its own CI.

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

## Complete-workbook qualification, October 27
W1 uses the real shared Swift workbook agent against native and pinned-reference frontends. It checks supplier comparison and a native space, reviewed formula creation/acceptance/edit/undo, stock evidence and missing evidence with indexing limits. The installed app has no reference adapter or Python dependency.

The first harness compile rejected asynchronous computed properties and admission forwarding against synchronous protocol requirements. The wrapper now stores identity/metrics, and the package-internal admission requirement permits async forwarding while the existing synchronous model actors retain their implementations. The full regression passes.

Pilot 1 stopped before inference because the harness included license files in the native executable/Metal identity map. Its cleanup also attempted to signal an already exiting group and raised a permission error. Preserve the failed prime, exception and partial evidence. The map now contains only engine files, and cleanup first reaps an exiting worker.

Pilot 2 completed both sides. The formula test used an edited row ID as an undo change ID; both sides correctly refused. The harness now uses the change receipt, retains partial review proof and independently tests 7.5 to 10 to 7.5 through actual acceptance/edit/undo. A measured supplier job also failed on both frontends after repeatedly leaving source/row UUIDs in answer prose. Currency, calculation and citation checks were preserved. Exact offending-reference feedback now covers parenthesized source IDs and Supporting evidence. The fourth rejected finish is saved before failing the run. Synthetic corrected/exhausted tests and the complete regression pass.

Some pilot-2 reasoning sequences diverged despite identical initial prompt arrays. Inspection found the reference's default normal priority differed from native foreground priority. This is a verified matching flaw, not yet a proven cause of the token differences. W1 now specifies foreground priority and captures full serialized request bytes, normalizing only IDs and deadlines, plus cache matched-token counts. R1's frozen receipts remain intact but its stronger matched-configuration latency claim is withdrawn. A new request comparison is needed.

Pilot 3 completed with sixteen successful workbook jobs, two successful Ready priming jobs, no sample/process failures, successful helper/bridge cleanup, and no power/thermal exclusions. The formula receipts contain the requested Washers row, plan meaning, quantity 3 and unit cost 2.50; acceptance computes 7.5, edit computes 10 and undo restores 7.5 on both frontends. Missing-document replies retain actual queries and indexing limits. The previously failed supplier case completed after one correction on both frontends.

The pilot still exited 1 as required. Each frontend made 42 requests. Of 41 request positions paired within jobs, 34 had identical normalized wire bytes and 30 had identical generated tokens. Four same-wire pairs still produced different tokens; later requests then inherited different reasoning, and one job had a different request count. The first missing-document divergence had the same 4640-token cached prefix on both sides, so a prefix-count difference is not its explanation. Identical priority does not resolve generation parity. The next investigation must distinguish repeatability, grammar masks and engine/cache state without weakening the recorded gate or assuming a cause.

The single measured native stock job needed one correction and took 31.658 seconds, versus 21.981 and no correction for the reference. This is not a stable regression estimate, but it fails the pilot threshold and shows why complete-job correction cost matters. No qualifying W1 cohort has run. R1 non-pilot qualification is now explicitly refused until a replacement protocol verifies actual request bytes. Historical protocols and receipts remain preserved.

The final full regression, release worker/self-check, native and baseline app/CLI builds, native installed-resource/signature/refusal checks and isolated install/update/uninstall/skill/conflict checks passed. A second harness compile failure from an observation added in the wrong scope is retained alongside the first compile and both failed pilots. Hosted CI for earlier checkpoints 96a3950 and 608ae52 is green; this checkpoint requires its own result. All 94 published synthetic prompt arrays were decoded and checked for local user/repository paths.

Full sanitized pilot traces, actual request bytes, prompts, outputs and memory samples are in integration/evidence/2026-10-27-workflow-performance-pilots.json. Commands, source/binary identities, retained build failures and final checks are in integration/evidence/2026-10-27-workflow-qualification.json. Native production adoption, automatic compaction, complete context/hardware/UI qualification and the preserved baseline Ready failure remain open.

## Workflow mask and repeatability diagnostics, October 27
The same native release worker, source, synthetic starting workbooks, priming job and complete pilot schedule were replayed without changes. All eight workbook jobs and the Ready prime passed. All 42 actual request and generated-token sequences matched the original native pilot exactly. Sampling, process cleanup, power and thermal checks passed. This is two observed native runs, not universal determinism proof.

The next paired pilot recorded the actual grammar text and every returned mask row. The observation callbacks are nil in the product. Both frontends completed all sixteen jobs and two primes successfully, with 42 identical request/output sequences. Each side recorded 18,141 mask rows. All 16,130 distinct shared prefixes matched, including masks before all 9,724 generated tokens. There were no malformed traces, conflicting prefix masks or missing observations before generated tokens. Grammar strings are not text-identical; these observed masks agree. The native outputs also equal its earlier uninstrumented run.

That traced success cannot clear the original failure. A controlled reference-only replay used the exact same worker and frontend build, schedule and configuration, changing only diagnosticMasks from true to false. All eight jobs and the prime passed again. Its 42 request/output sequences exactly reproduced the older untraced reference pilot, but four same-wire requests again differed from native. The comparison against the traced baseline correctly exited 1. At the earliest difference, token offset 2, both paths reported the same 4640-token matched cache prefix. Preserve the observed association with tracing; timing, mask-return pacing, observation serialization and command/cache state have not been isolated. No engine defect, grammar defect or fix is established.

The diagnostic analyzer retains every observed mask for a prefix and fails closed on malformed prefixes or missing data. The performance summary refuses traced evidence even when a caller omits its diagnostic flag. Tests cover mismatches, incomplete sampling, failed jobs, missing/conflicting masks, historical comparison and reference process accounting. The first analyzer included a post-terminal prefix among expected next-token masks; 34 such positions required no further generation. Its output/source are retained, and the revised analysis excludes only the post-terminal position of identical completed sequences. All masks before actual generated tokens remain checked.

Development failures are preserved. The initial edit attempt stopped before writing; its subsequent unchanged build was not instrumentation validation. The first real instrumentation compile needed explicit self in a closure, and the next hit a Swift type-check diagnostic on a conditional closure. An explicitly typed optional callback resolved the latter. The final release worker/self-check, full local regression, native preview app/CLI build and installed-resource/refusal/signature checks pass. Both packaged binaries load 1,888 Metal functions; missing/altered resources are refused. The final targeted diagnostic tests also pass. The prior e57492e hosted run is green; this checkpoint needs its own hosted result.

Full sanitized runs, prompts, actual wire requests, grammar texts, mask rows, memory traces, analyses and historical controller sources are in integration/evidence/2026-10-27-workflow-mask-diagnostics.json.gz. Compression is only evidence storage: the gzip payload round-trips exactly to 21,487,859 JSON bytes, with uncompressed SHA256 afe3a260f71e8bd6b09ff677ce9589712f2b5ffdefc3c4dd60ad9fd594f697dd. All fifty unique published prompt arrays were decoded and checked for local user/repository paths. Commands, build identities, failed compilations and checks are in integration/evidence/2026-10-27-workflow-diagnostic-qualification.json.

Next isolate the observation effect without changing the pinned engine or weakening W1. A corrected matched request cohort, uninstrumented workbook performance, whole-app memory/headroom, larger contexts, complete UI/media/voice/accessibility and remaining search-scale recovery gates are still open. Production adoption and automatic compaction remain disabled; the earlier baseline Ready and raw-model currency failures remain failures.

## Observation controls and cache comparison, October 27
The three reference controls each ran the identical Ready prime and four W1 warmups, with no measured repetition. Each used a fresh worker and the same unchanged helper, model bytes, requests, fixture seeds, foreground priority and verify-rows all. The modes were no observation, mask hashing without returning the trace payload, and a 2 ms wait after computing each mask. The delay wrapper returns each upstream-produced buffer unchanged; it does not establish that every live mask across the different runs was identical. All twelve workbook jobs and three primes passed, with successful sampling, cleanup and no power/thermal exclusions.

Both the no-observation and hash-without-payload controls matched the earlier traced/native sequence. The delay control reproduced the earlier untraced reference sequence, including the first different token at offset 2 of the initial missing-evidence request. This counterexample means the earlier tracing-on/off association was not sufficient to identify a cause. A production delay would not be a justified fix. The controls are diagnostics, never performance samples.

Pinned upstream documentation describes an additional matching condition: cached KV may be substituted after prefill starts, even when the initial matched-prefix count is zero. The default recurrent state here is FP32; optional BF16 rounding is not an explanation for these runs. Both native product metrics and the reference harness now preserve Done's deduplicatedKVTokens separately from Start's matchedPromptTokens. See [[records/research/foundations]].

The new full uninstrumented pilot completed all sixteen workbook jobs and both Ready primes. It correctly failed the strict comparison, with three same-wire requests producing different tokens. Every one of those three also had different later KV reuse, despite equal initial matched counts. The first missing-evidence request started at 4640 on both sides, then reused another 832 tokens natively versus 960 in the reference. The measured formula case reused 928 versus 1088; measured missing evidence reused 832 versus 1216. A source-history check found that the longest matching prior prompt/output prefix was 5954 tokens on both sides for each request, shorter than the respective 6176, 6187 and 6178-token prompts. With fresh sequential workers and persistent cache off, this places those reused prior tokens inside the prompt, rather than after the different generated answers. Equal reuse counts would still not establish byte-identical cached state.

This is a concrete confound in the comparison, not a proven engine or Swift defect. The two frontends have not been shown to compute from identical cached data. Earlier W1 reports and failed samples remain unchanged. The one-sample latency figures are descriptive; the missing-evidence measurement also exceeded the pilot median ratio threshold. No speed or adoption claim follows.

I1 is frozen in integration/performance/workflow-isolation-pilot.json before implementation. It will create a fresh worker per workload/backend, preserve the Ready prime and the same real workbook jobs, and compare a warmup and one measured repetition. It keeps exact request and generated-token comparisons, adds explicit cache-counter review and retains mixed-workload W1 as separate robustness evidence. If it passes, a qualifying protocol still needs preregistration and a full cohort. This diagnostic result does not justify disabling product caching, adding a delay or changing the engine.

The full local regression, final observation-control checks, release worker/self-check, native preview build and installed-resource/refusal/signature checks pass. The prior 21ccb27 hosted run is green; this checkpoint needs its own hosted result. The current tests reject invalid observation parameters and prevent delay/observation records from qualifying even if an analyst omits the diagnostic flag. The reference validation helper was extracted and tightened after its measured worker had loaded; exact loaded controller/reference source bytes are retained and match the hashes captured at startup. These pilot runs never qualify performance.

Evidence is in integration/evidence/2026-10-27-workflow-cache-diagnostics.json.gz, with complete prompts, request frames, outputs, controls, memory samples, prior-prefix analysis and loaded-source snapshots. Forty-eight unique published prompt arrays were decoded and checked for local user/repository paths. Commands, final source/binary identities and checks are in integration/evidence/2026-10-27-workflow-cache-qualification.json. Native production adoption, automatic compaction, full UI/media/voice/accessibility, wider context/hardware, whole-app memory and remaining search-scale gates are still open.

## Fresh-worker comparison and calculation-reference recovery, October 27
I1 used eight fresh workers, one per workload/frontend, with Ready followed by warmup seed 1 and measured seed 2. All sixteen workbook jobs and eight primes passed their original application assertions. Native made 47 requests and reference 48. All sources/binaries stayed frozen during the run; sampling, cleanup, power and thermal checks passed. The first controller test exposed an exception on absent cache metrics; the gate now refuses incomplete evidence instead of trying to compare it. Its failed preflight is retained.

The pilot correctly exited 1. Formula, inventory and missing-evidence requests, generated tokens and cache counts matched. Supplier generation first differed in measured step 6 at output-token offset 171 despite identical normalized request bytes, initial matched count 4640 and later reuse count 0. Later prompts and counters followed the changed output. This disproves the proposed fresh-worker-per-workload fix for parity. It does not identify an engine, grammar or Swift defect, establish identical cached numerical state, or qualify speed/adoption. W1 and R1 failures remain preserved.

The matched inventory output exposed a separate application weakness. Both frontends mistook an opening-stock source UUID for a conversation-message ID, repeatedly searched history and tried unnecessary count receipts. Each measured job took twelve steps and three rejected finishes: 119.773 seconds natively and 124.649 in the reference. Correct final stock alone concealed this poor path.

Balance tool results now label their calculation references as item-version and provide evidence.citations. Missing-input feedback states that successful calculations already inspected these workbook inputs. The initial recovery replay removed the history/count detour, but each measured job still needed one formatting correction for raw UUIDs in otherwise valid citations. Its four jobs completed, yet the preregistered zero-correction recovery gate failed and remains failed. Exact loaded source snapshots are retained.

The final shared host renders complete item IDs in plain answer prose as native named links only after they are inspected, cited and all answer checks pass. Unknown IDs, abbreviations, conversation IDs and IDs in model-written links/code remain subject to refusal. Source labels escape Markdown; substitutions use original positions once, preventing recursive replacement inside inserted links. The original finish arguments and renderedReferences map are preserved. No factual claim, calculation or citation authority is silently repaired. Synthetic tests cover Unicode offsets, case variants, repeated IDs, unknown/uncited/uninspected references, hostile labels, actual link parsing, unchanged stock, source navigation, correction exhaustion and durable original arguments.

The final actual-model recovery passed all four stock jobs and both Ready primes with no rejected finishes, history/count detours or sampling/cleanup/power/thermal failures. Each job used balance, two source reads and finish. The seed-2 observations were 26.955 seconds natively and 27.241 in the reference. These small functional replays do not establish a latency distribution, native/reference parity for other tasks or general model reliability. The earlier search-coverage protections remain unchanged and pass regression.

Evidence is in integration/evidence/2026-10-27-workflow-isolation.json.gz and integration/evidence/2026-10-27-balance-evidence-recovery.json.gz. Their verified uncompressed SHA256 values are c35243597a619912da58857026f8017a63af1604673ae2555d3c1fa7e3455991 and 67d1d20145f07ad0fef021eb3421a309247f47ff25590f1a106fa3128a47ded7. Forty-nine unique I1 prompt arrays and ten recovery prompt arrays were decoded and checked for private user/repository paths. The first added balance test failed as intended before implementation; a renderer-test compile failure used Message.payload instead of messagePayload and was corrected. Preserve these failures with the final verification receipt.

The full local regression passed before a final conservative guard expansion for bracketed references, HTML, tilde fences and indented code. The final agent suite, native and baseline builds, native installed-resource/refusal/signature checks, baseline installed-resource checks and isolated install/update/uninstall/skill/conflict checks pass after that expansion. The guard changes presentation eligibility only; they do not relax answer validation.

The final packaged CLI has a new explicit inventory check with fresh UUIDs. Its first application run completed correctly in two steps, with inline named citations. The harness then failed because its records command returns Sources as well as Records, and the saved user request was counted as a business mutation. The corrected assertion preserves every original item and permits only the one new request Source. The initial failed check remains retained.

The next fresh-ID run exposed a real remaining model failure, rather than another test error: it repeatedly copied the wrong suffix of the movement UUID, called read/lineage on that missing ID, and then searched conversation history. The host refused the uncited prose reference and later the missing calculation citation. It eventually returned the correct stock with both required citations after twelve steps and two rejected finishes. The zero-correction test therefore failed and the combined command stopped before its missing-document check. Its after-state assertions were not reached, so do not count that run as a verified business-state preservation result. This counterexample limits the successful fixed-seed recovery result. Do not relabel it as passed or repeatedly generate new UUIDs until a favorable result appears.

The next reliability work is exact model-reference selection: constrain choices to actual returned candidates or use short typed per-run handles resolved by the host to canonical immutable IDs. This is a proposed implementation direction, not yet implemented. Never guess a replacement ID or silently resolve a typo to a nearby record. Qualification must vary identifiers as well as task wording. Keep this shared application work separate from the unresolved supplier generation mismatch. Production adoption and automatic compaction remain disabled. Next work must isolate the remaining generation mismatch separately from shared application quality, then complete occupied-context, total memory, UI/media/voice/accessibility and search-scale acceptance. The preserved baseline Ready-request and R1 raw-model currency failures remain open. Commands and evidence boundaries are in [[records/operations/build-and-run]]; current contracts are in [[records/specs/intelligence]] and [[records/specs/splash-integration]].

The separate final packaged missing-document check passed in three steps (15.984 seconds), retaining the actual empty-query report and incomplete-index disclosure. The final release worker rebuild/self-check also passed. Exact source/app/CLI identities, commands, failed smoke runs, final checks and receipt hashes are in integration/evidence/2026-10-27-workflow-isolation-qualification.json. The frozen-I1 and both recovery archives remain unchanged. The repository adds the I1 fail-closed tests to local checks and hosted CI. This checkpoint does not qualify native production adoption or resolve the fresh-ID failure.

## Exact item reference selection, October 27
The shared agent now derives a bounded read/lineage vocabulary from exact UUID strings visible in the current working conversation and verified against this workbook. Native generation constrains those choices; both backends revalidate before lookup. References are ephemeral host metadata, recomputed after context rebuilding, and do not grant citation authority. Logical-ID lookup remains exact and historical versions remain historical. Unknown IDs are never fuzzy-matched. Actual schema tokens count toward context limits.

Focused synthetic and actual grammar checks pass, including the previously copied wrong suffix, reasoning on/off, logical/current/historical IDs, untrusted-text candidates without citation admission, dropped context, bounded candidate counts, durable refused-call receipts and baseline/native schema agreement. The first test build failed on two incorrect test API assumptions; the initial agent regression then revealed a compaction fixture whose source ID was private to its mock model. The fixture now supplies the source visibly. No product lookup guard was relaxed for the test. A later large-vocabulary test initially hit the frontend default 8K limit before its intended assertion. It now renders at the explicit measurement limit and separately verifies the smaller budget refuses the complete prompt. The corrected full local regression passed. The final Settings-only change was subsequently built and checked in both app/CLI packages and exercised through the native UI.

R2 completed all twelve inventory jobs and both Ready primes. Six deterministic identifier sets and three question wordings used the same native/reference workload schedule. Every job returned stock 18 with the exact opening and movement citations, preserved original items, spaces and balance, and passed workbook integrity. No wrong-ID lookup, failed tool call, rejected finish or history search occurred. Ten jobs used four or five steps. Both seed-6 jobs made three unnecessary count_records calls and appended unrelated scoped totals, requiring seven steps. Therefore the strict no-detour/six-step cohort failed and remains failed. Counts were scoped and truthful, but irrelevant to the request. Exact reference selection and stopping when the answer is already established are separate reliability problems.

The recorded wrong-suffix grammar case is exact; these new fixtures do not recreate the deleted failing workbook byte-for-byte. R2 is a small functional cohort, not a reliability rate, speed or general parity result. Supplier generation mismatch, baseline Ready behavior, raw-model currency errors and other release gates remain open. The immutable archive integration/evidence/2026-10-27-exact-item-references.json.gz preserves full traces, source snapshots, prompts, wire bytes and sampling. Its uncompressed SHA256 is fe265245564add9c3f007fe025b8c5e4863e39832ee28e10805f8282ec3b19d9; all thirty unique prompt arrays were decoded and checked for private paths. The collector regression preserves both recorded failures and rejects malformed/incomplete jobs, refused calls, cleanup and sampling failures. Native Settings download/cancellation checks now pass as described below. Production adoption and automatic compaction remain disabled.


The final native and baseline packages each passed a separate fresh-ID inventory job in four steps without corrections, required both exact calculation citations and preserved business state. The native missing-contract job also passed in four steps with its actual search report and incomplete-index disclosure. These favorable independent cases do not erase R2 seed 6. Final native resource/signature/refusal checks, baseline resources and isolated installation/update/uninstall/skill/conflict checks pass. Hosted CI for the previous 6995a89 checkpoint is green; this checkpoint requires its own result.

## Native Settings cancellation and recovery, October 27
The rebuilt native preview started a fresh official model download through Settings. The first cancellation retained 80,440,940 bytes of the first weight shard; resuming and cancelling again retained 208,857,313 bytes. No selected-model assembly was published in that incomplete root. Controls became usable again. Reverification of the prior reused installation returned Model files are ready without creating a weight copy.

This exposed a real display bug: the old Downloading progress remained beside the cancellation error. Settings now initializes its status for each attempt, ignores progress after that operation finishes or is cancelled, and rejects late updates from an older operation. Cancellation is presented as a normal resumable state. Ordinary errors clear progress; successful setup clears the prior error.

The rebuilt UI resumed the retained partial file, displayed progress above its previous byte count, and cancelled cleanly at 426,336,946 retained bytes. Its only terminal status was Setup cancelled. Downloaded files are kept so you can resume. The incomplete root still had no published model. Deliberately selecting an existing JSON file as the model folder produced a normal error, cleared stale progress and left controls enabled without changing that file. Restoring the original model folder and verifying returned Model files are ready. The original preference was restored. Its managed snapshot directories contain zero regular-file bytes, so verification did not duplicate the reused weights.

The earlier CLI proof covers a complete fresh 21,481,463,614-byte native installation and cancellation/resume. This UI session covers start, partial resume, cancellation, error recovery and existing-installation success; it does not claim another full download was completed solely through Settings. Actual microphone recognition, complete media/accessibility and broader hardware/UI qualification remain open. Commands, retained failures and final identities are in integration/evidence/2026-10-27-exact-reference-qualification.json.

## Count-purpose reliability, October 27
The previous R2 cohort returned correct stock and citations but both seed-6 jobs added unrelated entry counts. The active finish field is now counts, with descriptions separating classified-entry counts from inventory quantities and search completeness. The host explicitly refuses the retired coverage argument, including null or mixed old/new fields, while preserving saved historical payloads. The original R2 failures remain unchanged.

The complete fixed R2 replay passes all twelve inventory jobs and both Ready primes. Each frontend takes 2, 5, 4, 4, 5 and 4 steps. There are no wrong-ID calls, failed tools, rejected finishes or count/history detours. Exact input citations, unchanged original business items/spaces/balance, database integrity, process cleanup, sampling and power/thermal checks pass. Paired prompt tokens, normalized wire hashes and generated tokens match for these six jobs. This does not clear the separate supplier-generation mismatch or establish a speedup or reliability rate.

The packaged native app's movement and invoice count checks pass in two steps each. Its missing-document check passes in three steps and reports the actual three search terms, one incompletely indexed source and the limit on the facts established. The rebuilt baseline passes the same missing-evidence check in three steps, movement count in three and invoice count in two. Do not infer zero format correction from the baseline's final count result.

The shared-agent checks, regenerated actual-tool schema/reference masks, release worker self-check and all executable checks in scripts/check.sh pass. The full script stopped at its final documentation gate because a new wiki-link used an unsupported heading anchor. The exact failure is retained; correcting that link produced zero dbmd errors/warnings and a passing link gate. Final native and baseline app/CLI builds, resource/signature/refusal checks and isolated install/update/uninstall/skill/conflict checks pass.

The replay archive is integration/evidence/2026-10-27-count-purpose-replay.json.gz: 697,867 compressed bytes, 3,878,619 uncompressed bytes, SHA256 a3f7a3b36a40ca46c0ab8619e625273efb21ad8919f62435ffa66b80791e6e34 for the uncompressed JSON. All 25 unique published prompt arrays were decoded and checked for private paths. Final source/binary hashes, 31 retained logs, checks and limits are in integration/evidence/2026-10-27-count-purpose-ui-qualification.json. Production adoption, automatic compaction, occupied-context/hardware and whole-app memory qualification remain open.
## Native search navigation, October 27
The prior native app reproduced a stable-navigation failure with 35 synthetic text assets: search amber, load the second page, open Amber_35.txt, then Back. The query remained but the last five results and opened-item position disappeared. The retained before-observation and prior binary identity are in integration/evidence/2026-10-27-count-purpose-ui-qualification.json.

Search result ownership now belongs to the workbook window. Typed identity covers workbook, revision, text, history and all filters; each asynchronous read also has a unique operation identity. Returning from a preview preserves loaded pages and anchor for an unchanged query. A new query clears old matches and cursor; old successes/errors cannot overwrite it. Clear removes results, errors, incomplete-index notices and loading. Failed next pages preserve current evidence and remain retryable; overlapping continuation requests are refused. Facets also discard cancelled or outdated reads.

The new search-state executable passes controlled overlapping-success/error cases, same-query cancellation and retry, clear during a read, revision invalidation, continuation retry and an old continuation arriving after a new query. It runs in the local and hosted suites. The rebuilt native app visibly passes the original second-page/Back reproduction.

Native picker intake of three synthetic files also passes. The CSV opens as a two-row table with Sierra/20/2.50 and Vega/20/2.75. A search for quartz finds page 2 of the PDF and opens there. Searching fulfillment finds recognized image text; its original image opens and zooms with the OCR accuracy notice. The query nandu finds the accented filename. A Row filter removes that document and then finds the Sierra table row. Clear leaves the empty search state. Recents reopens the saved workbook, preserving all imports and the table. Packaged CLI checks confirm exact PDF/OCR locators, filename matching and database/asset integrity.

That journey exposed another real bug: PDF search selected SIERRA on page 1 while the composer still labeled it Page 2, because the selection notification preceded scrolling. Selection context now uses PDFSelection.pages, including a range for multi-page selections, instead of the old visible page. After rebuilding, the UI shows About: Page 1: SIERRA together with Match on page 1 and 1 / 2.

Final native Settings reverification reports Model files are ready, preserves the selected folder and leaves managed snapshot storage with zero file bytes. Earlier fresh-download/cancel/resume evidence remains; this turn does not claim another full 21.48 GB UI download. The reproducible fixture generator is scripts/make_ui_fixture.swift and the journey is documented in [[records/operations/build-and-run]]. All files are synthetic.

This covers the text/PDF/image/CSV part of J01 and selected preview navigation. It does not complete the full media, voice, VoiceOver, narrow-window, long-context, hardware or production-adoption gates. Continue those journeys and resolve matched full-workflow performance and memory qualification without weakening earlier failed gates.

## Late cancelled-search admission, October 27
Final review added a deterministic case where SwiftUI cancels a search task before its actor entry begins. The new test failed: the already-cancelled task cleared the newer result set and opened-item anchor before reaching the existing cancellation check. SearchSession now checks cancellation before claiming request ownership or touching result state. The same test and complete search-state suite pass after this guard.

Both app/CLI paths were rebuilt again. Native installed-resource/signature/refusal checks, baseline Metal/resource checks and isolated installation/update/uninstall/skill/conflict checks pass. Native and baseline CLI binaries remain byte-identical to those used by this turn's actual-model checks. No model-source change followed those checks.

The Mac locked before the final three-line guard could be replayed visually. Manual unlock was requested; no UI bypass was attempted. The earlier actual UI checks, including second-page Back and corrected PDF selection context, remain valid for their recorded build. The final guard is verified by the failing-then-passing controlled test and final packaging checks; its last visual replay remains pending. Do not describe that visual step as completed.

Supplementary evidence is integration/evidence/2026-10-27-search-entry-qualification.json. It binds the prior UI/AI evidence by SHA256 and retains before-source snapshots, all nine build/check logs, final source/binary identities and the locked-screen limit. Continue with that narrow visual replay when available, then the remaining complete workflow, media/voice/accessibility, occupied-context, memory and native-adoption work.

## Native multi-stage continuity plan, October 27
The first five-stage native pilot passed exact original recall, acceptance and withdrawal injected after summary input capture, corrected quantities and portable stock recovery. The final six-stage run also passes inherited parent-message retrieval in a tangent and a host-controlled return to main. Both runs created three durable checkpoints across 450 synthetic closed messages and 18 chapter markers, preserved original source/history bytes, retained the accepted/withdrawn forecast as an estimate, kept stock 18 with the same single inventory effect, verified integrity and released native resources.

The final run used 32K, bounded512 and a 12 GiB engine budget on the recorded M5 Pro/48 GiB host, with native-installed model files and the unchanged pinned Splash/LLGuidance binaries. Its stages used 4/4/4/6/5/3 model steps and took 40.247/62.715/71.219/68.596/91.291/23.731 seconds respectively. These are functional observed durations, not a matched performance comparison or a responsiveness qualification. Reopen and tangent each needed one rejected finish to remove exposed opaque identifiers. Preserve those corrections; this is not a zero-correction result. No source or binary changed during the six-stage run.

The first launch failed before inference because the new probe used the legacy model layout against native-installed files. It now explicitly uses the app's installed resolver. That failed workbook, all traces, identities and both successful pilots are retained in integration/evidence/2026-10-27-continuity-workflow.json.gz. Its 922,436 uncompressed JSON bytes have SHA256 724f125c1597525179481b0d4f7b4fda9e535c0760ea3b5d421ecdc2542646ec. No prompt-token arrays are published in this archive; it contains exact saved history/receipts, checkpoints, metrics and source/binary identities.

The sequence qualifies a C12 subset only. It does not exercise repeated compaction within one mutating job through actual process death, full tangent compaction/isolation under load, occupied 32K/64K performance, whole-app headroom or broad hardware. Automatic compaction stays disabled in both product builds. Native production adoption and the existing reference/native performance gates remain open.

## Inherited history and conversation navigation, October 27
A focused deterministic test reproduced a history_scope refusal when a tangent tried to retrieve an original already present in its inherited parent excerpt. history_read now admits only those explicit inherited IDs and returns the owning conversation; search, receipt access and checkpoint scope remain local. Earlier/later unshared parent messages, siblings, transitive ancestors and mismatched cutoffs remain refused. The citation renderer links back to the actual owner, including nested tangents. No broader history permission or business authority is granted.

The new deterministic checks pass. The pinned reference regenerated all 249 actual-tool masks unchanged, apart from the expected declaration hash, and the full native grammar comparison passed in scripts/check.sh. The six-stage actual-model workflow retrieves and cites the inherited original. After the user unlocked the Mac, the rebuilt native app opened the synthetic review copy; selecting Packing follow-up and clicking Earlier message switched to main and visibly showed the exact 0.25 kg correction and original 0.10 kg statement.

The late search-entry visual replay is now complete: native search loaded all 35 amber results, opened Amber_35.txt, and Back retained results 31–35 and the bottom position. Replacing the query with quartz showed the PDF's page-2 match; clearing and fast keyboard query replacement left the empty view with no stale hits. A batched accessibility action initially reused an invalid element ID after the first field change; refreshing state and using focused keyboard input completed the intended check. This was automation state, not an app search failure.

Opening the larger synthetic conversation exposed a separate UI issue: the view opened at the oldest loaded message, and a count-based observer could miss new messages when the fixed 100-message window retained the same count. The first repair observed the last visible identity on initial presentation/change, but native testing still found the new message below the viewport because of lazy row-height estimates. Preserve that failed intermediate app/source. The final view measures rows in the bounded history window and observes visible message identity, while preserving explicit older-message anchors. Actual rebuilt-app testing now passes initial latest-message visibility, a new locally submitted chapter message at the unchanged 100-message limit, an older citation anchored at the original correction, and return to the latest exchange through Main conversation.

The complete local regression passed, including all 249 actual-tool masks. Both app variants were rebuilt after the final UI-only repair; native resource/refusal/signature checks, baseline resources and isolated installation passed again. Packaged missing-evidence and movement/invoice count checks passed on native (3/2/2 steps) and baseline (3/3/2). Both CLI binaries stayed byte-identical through the UI-only rebuilds, so these model results apply to the final packaged CLIs. Strict formatting passes. Evidence, all 35 retained logs, source/binary hashes, intermediate UI failures and visual observations are in integration/evidence/2026-10-27-continuity-navigation-qualification.json. Previous checkpoint 95a1629 completed hosted CI run 40491316063 successfully. This checkpoint still needs its own hosted CI result.

## Request-cache isolation diagnostic, October 27
I2 completed four Ready primes and eight supplier jobs on frozen commit 3738a56. Both arms passed exact request, output and cache-counter comparisons: 16 paired requests with normal shared caching, 13 with unique per-request salts. Every actual wire salt was verified; every isolated request reported zero initial and later cache reuse. Sampling, power/thermal conditions, source identity and shutdown checks passed.

The shared warmup/measured jobs used 8/7 steps on both frontends; the isolated jobs used 7/5. Shared measured jobs each needed one host-rejected currency correction before publication. Isolated jobs needed no rejected finishes. These are complete successful workflows, not evidence of zero model errors. The current tool contract produces different prompts from I1, so I2 is not an exact replay of the historical failing build. Because the shared control passed too, I2 does not identify prior KV sharing as the cause or establish that the older mismatch is fixed universally. Production caching is unchanged.

Immutable evidence: integration/evidence/2026-10-27-request-cache-isolation.json.gz, uncompressed SHA256 1a557c6a04cd55e3fe61ebc51c567d3730c80c6bbcfe8b31eac4aeb8db421dab. All 23 unique published prompt arrays were decoded and checked for private paths, and saved request frames were hash-checked and matched to those prompts. Preserve I1 and W1 failures separately. This diagnostic cannot qualify speed or adoption.

Review also found an extra status request after every Python reference workflow call, inherited from the R1 request harness. R1 issues status on both sides outside request timing; the native W1 application does not. Remove that unused reference-only W1 probe before another performance comparison. This is a harness correction, not a proven cause of token divergence. The controller now refuses a cohort when measured sources, manifest or worker binary change, checking before each worker and at finalization. The next step is a new full W1 pilot with normal caching and these corrected conditions.

## I2 validation and W1 pilot preparation
The full local scripts/check.sh regression passed after the request-cache diagnostic addition. After the reference-only status and source-freeze corrections, the performance/diagnostic/isolation evidence tests, Python compilation, release-worker self-check, full dbmd validation (zero errors/warnings), Markdown links and diff checks pass again. No product caching behavior changed. The next W1 pilot uses the already built native worker with the corrected development reference and controller; its own results remain pending.

## Corrected complete-workflow pilot, October 27
The normal-cache W1 pilot on frozen fda029e passed all sixteen workbook jobs and both Ready primes. Native and reference each made 32 requests; exact prompt/prefix/request bytes and generated tokens matched for every pair. Both workers exited zero and confirmed release, with complete sampling and no power/thermal exclusions or source changes. Warmup steps were 8/1/2/3; measured steps were 9/1/4/3, in supplier/formula/inventory/missing order, identical on both frontends. Each measured supplier job had one currency rejection before the successful finish. Formula acceptance/edit/recalculation/undo and missing-evidence limits passed.

One measured observation per workload is not performance qualification. The observed native/reference time ratios were 0.912, 0.947, 0.984 and 1.014, but no speed claim follows from this pilot. The recorded performance gate correctly remains false because pilot=true. The exact cause of earlier mismatches remains unresolved; updated tool prompts and removal of reference-only status telemetry are different conditions, not a controlled causal diagnosis. Historical failures remain intact.

Evidence is integration/evidence/2026-10-27-current-workflow-pilot.json.gz, uncompressed SHA256 98d8a40998bd6dd07b807c50918dff4ae8488512671f1771161cd634824b957a. All 32 unique prompt arrays were decoded and checked for private paths; saved request hashes, embedded prompt tokens and zero cache salts were verified. The existing ten-block, twenty-measured-observation-per-workload/backend W1 cohort can now run on the committed tested harness. Native adoption, automatic compaction, wider hardware/context and remaining app acceptance remain gated.

Hosted CI passed for both prior checkpoints: 48dc398 (40495894340) and 3738a56 (40496781537), including isolated native preview packaging. The fda029e check is still running.

## Current workflow packaging and evidence
Both final local app/CLI builds pass. Native installed-resource checks, nine missing-resource refusals, altered Metal refusal, missing-model guidance and strict signatures pass. Baseline resources and isolated installation/update/uninstall/skill/conflict/workbook preservation pass. Verification logs and final source/binary hashes are retained in integration/evidence/2026-10-27-current-workflow-qualification.json. The tested harness and protocol are ready for the full W1 cohort; all product adoption limits remain.

## W1 qualifying cohort in progress
The full preregistered W1 cohort started on frozen clean commit ed6ffd0, using the tested release worker, ordinary cache identities and corrected reference/controller. Its local evidence directory is .build/workflow-performance/current-cohort1. It runs ten alternating paired blocks, one warmup and two measured jobs per workload/backend/block, plus Ready primes. No result or speed/adoption claim is available yet. Do not overlap local inference, builds or downloads or edit measured sources while it runs. Preserve every attempted result and finalize the report before assessing the gate. Documentation-only progress updates do not change its frozen measured inputs.

## Voice and media lifecycle repair
Source review found that pending permission callbacks could start microphone
capture after Stop/window close; old recognition callbacks could overwrite a
later draft or stop a new capture. Dictation also replaced existing typed text,
and the single retained player reference could miss background playback.
These are source-reviewed defects, not a claim of hardware reproduction.

The codex/voice-lifecycle branch isolates a new shared SevraVoice module and
injected-driver regression runner from the frozen W1 checkout. Capture now has
explicit permission/start/recording phases and session identities. The app
preserves the typed prefix, stops on manual edits/send/conversation changes and
closes capture/playback with the window. A weak registry covers all live players;
window teardown cannot retain a newly continued player after the parent closes.
Specifications A09/P15 record these contracts.

Local builds and hardware/UI checks remain deferred while W1 measures the frozen
ed6ffd0 sources. The new tests cover permission cancellation/denial/retry,
duplicate callbacks, stale recognition, synchronous completion/error, capture
failure, cross-window ownership, draft edits, all-player pausing and release.
They are prepared and untested at this checkpoint. Hosted CI will provide the
first compile/regression result without loading the local benchmark machine.
No voice or media qualification is claimed yet. See
[[records/specs/intelligence]] and [[records/operations/build-and-run]].

## Checkpoint publication process-death checks
An isolated codex/context-durability branch now prepares a model-free process-death
runner over the actual checkpoint publication API. Its package-only observer has
no production caller, public API, environment switch or workbook-controlled entry.
One barrier is after the checkpoint/input inserts but before the real SQLite
transaction commits; the other is after the mutation has committed its revision
and idempotency receipt. This does not modify the pinned inference engine.

The parent process uses a separate read-only SQLite connection to check committed
visibility, sends SIGKILL only to its owned fixture child, then reopens through
Workbook. Assertions preserve original history, prior checkpoints, accepted stock
18 from exactly one effect, input versions and current forecast meaning. Exact
retries must publish only one successor, and portable export/reopen must preserve
the final state. Additional cases cancel after inserts and accept a forecast in
another process before publication, requiring rollback/stale refusal and fresh
accepted-estimate projection. Every attempt, fixture and binary/source identity
is retained by the controller.

These checks are prepared, not yet compiled or run. Local builds remain deferred
while the frozen W1 cohort runs; hosted CI is the next check. They cover storage
and process-death boundaries only, not actual-model summary quality, repeated
mid-job compaction, occupied 32K/64K contexts or the complete C12/C13/J10 gates.
Automatic compaction remains disabled. See [[records/specs/conversation-context]]
and [[records/operations/build-and-run]].

## Hosted verification while W1 runs
The previously frozen primary checkpoints all passed their full hosted workflow,
including packaged baseline installation and native preview resources:
ed6ffd0 / 40499506612, f14eb26 / 40499594284 and e66bca6 / 40499641407.

The 14-check injected voice lifecycle step passed for 7f93617 in run 40502209056.
Its remaining job is still running; no whole-branch pass is claimed. The earlier
04ce5c2 run 40501522585 was cancelled after a replacement source revision started,
not reported as a pass. The descendant checkpoint-durability commit c0ac40f is
running as 40503178418 and awaits its own result. Both branches remain separate
from the frozen primary checkout. No local build, inference or test run overlapped
W1; only lightweight source/docs work and hosted CI were added.

W1 blocks 0 and 1 have complete native/reference workers, successful Ready primes,
48 successful workload jobs and exact paired request/generated-token equality.
The remaining eight pairs are required before the full gate can be assessed.
Frozen source/binary identities still match. This is progress, not a speed or
adoption claim. Preserve live local evidence until the complete report is final.
