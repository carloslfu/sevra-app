---
type: operational
meta-type: conclusion
id: 01m5rbxzcsjnewm0pwmb9a06cj
created: 2026-10-25T01:48:47.385772+00:00
updated: 2026-10-27T00:57:13.007805+00:00
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
smoke checks. Native prompts, streaming, actual tool schemas and autonomous workbook integration now have passing synthetic checks as detailed below. Resumable setup, matched performance, packaging and app adoption remain pending.

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

Latest storage checkpoint: schema 3 adds durable prepared tool calls and exact
results, atomic conversation receipts, valid bounded result pages and operation
proof for uncertain outcomes. The agent can search/read older conversation and
retrieve saved result pages. There are 59 core checks and eight passing native
jobs (six complete, one needs-review, one deliberately cancelled). Release build,
packaged history/receipt CLI, concurrent writers and isolated installation pass.
Automatic compaction now has a working candidate controller and native continuity
checks, but repeated recall is not reliable yet. It stays disabled in production
Slotstream. General restart/resume and long-task qualification remain pending; see the
latest context-maintenance checkpoint and [[records/specs/conversation-context]].

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
- Broaden qualification of the autonomous workbook agent connected to the qualified native frontend components.
  Actual tool schemas and synthetic autonomous proposal, review, evidence, space,
  hostile-document and cancellation jobs now pass. Broader authority and application
  qualification remain open, including current review-state presentation in the UI.
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
