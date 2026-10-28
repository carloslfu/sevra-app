---
type: operational
meta-type: conclusion
id: 01m5rbxzcsjnewm0pwmb9a06cj
created: 2026-10-25T01:48:47.385772+00:00
updated: 2026-10-28T04:42:54.955137+00:00
summary: Ordered work and honest requirement status for the first Sevra release.
title: Implementation and acceptance
---
# Implementation and acceptance

This is a working development build, not a qualified release. Requirements in the
specifications remain the acceptance contract. A source commit does not imply that
every requirement or supported hardware profile has passed.

## Current direction, October 27
This remains a development build. The preserved Slotstream app is the baseline;
the separate native preview uses the Python-free Swift adapter and pinned Splash
C++/Metal. Native adoption and automatic compaction remain gated.

- The app/ask loop now checks a proposed inventory direction in a separate local
  model response using current-request and original-source text. A missing quote,
  uncertain direction or opposite sign asks for clarification without saving the
  movement. Exact duplicate refusal ends that run instead of permitting an ID
  rename/retry. Five revised native cases and the fresh native clarification then
  -2 draft flow passed. The initial reviewer prompt failed and remains recorded.
- The withdrawn-v1 failure remains preserved. Exact historical citations now
  require inspection of their current head before finalization and display a
  host version note. The native historical/current answer correctly reports the
  withdrawal; deterministic tests cover the stale-answer and citation-drop paths.
  Semantic event identity across different IDs/runs remains unresolved. Direction
  review still adds 8.58–16.09 seconds per measured call and sees an initial bounded
  Source excerpt. Neither the full inventory flow nor J11 is qualified.
- The owner selected a 75% context-compaction trigger, using actual configured
  capacity and exact rendered tokens, or earlier when reserves require. Policy
  alignment and deterministic checks pass. The repeated native job still fails
  exact labels, despite all originals appearing in drafting context. Supported
  completed_action confirmations now use factual host receipts; draft contents
  are not thereby verified. An isolated literal reviewer passed small
  probes but falsely refused the full job and was removed from the app path.
  Next design source-bound copying for composed documents. Automatic compaction
  stays gated; none of this explains earlier errors at 8–12K prompt tokens.


- The integrated typed/native supplier journey now has direct evidence for intake,
  correct comparison, native table/chart composition, exact quote navigation,
  what-if thread, edited summary sharing, scoped drafts, explicit movement revision,
  acceptance/Undo and close/reopen. J11 remains unqualified: an ambiguous handover
  was interpreted as +2, including after guidance repair; the replay invented a
  resubmit occurrence after refusal. Both unsupported drafts were withdrawn.
- Fixed a reproduced accounting regression: withdrawing a draft inventory correction
  preserves its prior accepted effect, and Undo of an accepted correction restores
  that effect. The regression first failed (80 passed, 1 failed), then all 81 core
  checks passed. Preview, agent/context-budget and native grammar checks pass.
  An optional supersedes tool field enables explicit revision with the same subject
  and occurrence. Review now says Increase or Decrease. Explicit outgoing native
  clarification produced -2 correctly, with stock 20 -> 18 -> 20.
- Chat pipe tables still render literally, despite correct right-pane native tables.
  That presentation repair is pending after the material inventory reliability issue.


- Compound requests preserve exact same-request evidence and show the completed
  thread-creation result before continuing. Current user text stays intact;
  host storage/progress metadata is separate. Ordinary help uses voice/text
  language. The acceptance-versus-accuracy explanation and its direct contrast
  now pass focused manual review, with the original context budget unchanged.
  Earlier model/context failures remain preserved. Non-blocking example wording
  is logged instead of triggering another broad qualification loop.
- Native proposal badges now follow the current version through acceptance,
  Undo and newer drafts, preserving original messages and links. Exact typed
  receipt associations and conservative legacy fallback keep conversations
  isolated. Unknown associations do not invent current status. Deterministic
  checks and a rebuilt native interaction pass; stock remains 20 -> 18 -> 20.
  Captured request context shows named location/selection, with original bytes
  retained under a disclosure and unknown formats shown verbatim.
- Owner-approved focused verification now governs development. Reuse unchanged
  evidence, check the actual fix and one nearby counterexample, and reserve broad
  reruns for a concrete boundary change or meaningful integration/release point.
  The queued action cohort and package/install/rebuild/full-suite reruns were
  cancelled. One already-running handoff cohort finished safely before its
  orchestration shell was terminated. Remote CI now follows the same policy:
  full checks on main/release and review-ready PR milestones or explicit dispatch,
  not each development push. All 26 steps remain. No skipped check counts as a
  pass. See [[records/specs/distribution]].

- Home and the native space picker now show pinned shortcuts and recent visits.
  Live views and saved snapshots are distinct, and Create a space preserves an
  existing composer draft. Preferences merge in SQLite without business changes;
  focused persistence/rollback/stale-read checks and native close/reopen pass.
  Ordinary pin/unpin/navigation now use separate scoped actions. Three native
  requests pass compound unpin/open, host-context pin-this-space and a no-change
  explanation. Core and agent checks preserve snapshot semantics, refuse ambiguous
  targets/unavailable windows, and keep compound focus ordering. The explanation
  leaks internal tool names; log this wording issue without another broad cohort.
  Current pending-review discovery now passes the focused checks below; broader
  P09a/J11 remain open.
- Home now exposes current drafts independently of recent activity, with a bounded
  review list and scoped local opening action. Explicit withdrawal preserves history
  without applying proposed effects; Undo restores a draft. Native paging, review,
  acceptance/Undo, Back and reopen pass. Schema 4 adds the draft index/generation;
  eighty core checks and focused preview/agent/grammar checks pass. Only synthetic
  workbooks were migrated. App and CLI versions must stay matched.

- Search-grounding repairs pass deterministic regressions and the actual paired
  block-3 replay. Empty searches cannot establish exhaustive absence, and the
  current request cannot substitute for independent evidence being sought.
- Native setup passed fresh download, cancellation/resume, verification and
  explicit reuse on the reference M5 Pro. Focused document, space, intake, media
  and packaged-resource checks pass; complete release journeys remain open.
- W1 completed 260 correct jobs and met timing targets but failed exact token
  parity once. D9 finds variation within the reference on an identical request;
  the native repeats agree with one reference. Native adoption stays unqualified.
- The unchanged full 100k search protocol now passes at warm p95 136.47 ms for
  rows and 172.31 ms for document chunks, with correct paging and cancellation.
  Retain the earlier failed run. Whole-app and wider-device performance are open.
- Under the preceding threshold, the maintained32K context repair passed the
  unchanged eight-report v1 fixture twice: exact associations, four checkpoints, one space/draft, all-source lineage,
  unchanged originals/inventory and portable reopen. The first overlaps dictation;
  the controlled second run does not. The earlier uncompressed64K failure and
  remaining C12/C13 cases remain unresolved; compaction stays disabled.
- Real microphone dictation captured the requested English phrase exactly, then
  stopped without sending. Permissions were approved and manually granted. This
  closes the basic single-phrase path, not every language/device/session case.
- Window refresh, chapter menus and Home intake metadata now load off the UI actor
  in a coherent snapshot. Tests pass for bounded pending reads, cancellation,
  conversation scope and stale results. The rebuilt app shows CLI changes, keeps
  thread/main histories separate, and restores the workbook after close/reopen.
- The text-driven Open a copy flow passed through Save and Open into TextEdit.
  Editing the copy leaves the included asset byte-identical and workbook verified.
  Native 2.15 GB included/linked audio playback, seeking, Stop/Retry, changed-byte
  refusal and close now pass. Media teardown releases retained players, and
  extraction status no longer mislabels linked files as included. App-process peak
  was 99.56 MiB for this audio-only fixture; broader media/inference/memory,
  keyboard/VoiceOver and release journeys remain.
- Native document text/OCR and CSV/TSV/XLSX parsing now run in bounded helper
  processes. Nineteen isolation/fidelity/recovery checks pass in debug and optimized
  release. Both packaged app/CLI layouts read documents and tables with build-tree
  reads denied. Table failures persist independently from a successful text index,
  survive reopen and offer Resume. Source changes, coordinate overflow and expanded
  cell budgets refuse before publishing rows. Archives, file transcription, viewers
  and whole-app memory retain separate qualification requirements.

- Conversation and optional named Threads replace visible tangent terminology.
  Text/menu creation and return, summary review/cancellation, exact provenance and
  scoped history pass. Only selected findings return; commands stay in their
  originating history. Existing package IDs and the CLI tangent alias still work.

- Conversation messages now expose separate accessible groups, exact inline links,
  named assistive actions and native message menus. The Conversation menu follows
  the focused workbook, and Command-L focuses its composer. Exact evidence/origin
  navigation and closed-window isolation pass in the native app. Spoken VoiceOver
  and the complete keyboard-only journey remain unqualified.

- Each Conversation/Thread now owns its unsent draft and reading position.
  Background autosave, normal close/quit, reopen, original-message navigation and
  a burst of 120 new messages preserve the right text and place. Competing edits
  refuse silent overwrite and support Keep both/restore. The final package passed
  those visible paths; drafts never entered messages, evidence search or business
  revisions. Native actions are implemented; ordinary language equivalents remain.

- Immediate thread creation, editable provisional titles and visible return now pass
  native checks, including workspace-focus identity and reopen. Older history has
  bounded earlier/later windows and conversation-scoped search, with exact original
  navigation and preserved drafts. Search paging/retry and stale-scope refusal pass.

At the preceding integration checkpoint, the full local suite passed with 79 core,
19 extraction and 16 document checks,
plus the expanded conversation/preview checks. Both package builds, native
resource/signature checks, packaged extraction and isolated baseline
install/update/uninstall pass. Hosted workflows 40562440542 on e27ae39,
40564561986 on 75511b8, 40568212108 on 03163ed and 40571572539 on 3dcc924 pass.
The following checkpoints also passed hosted CI: 00662f6 (40589578202) and
92b08c3 (40593888059) and e1c9b49 (40597871434). The latter includes successful
installation and the isolated native preview build. The current focused checkpoint
passes preview/agent checks, native app/CLI rebuild, a focused native interaction,
CLI integrity/arithmetic/history audit, and workflow parsing with unchanged steps.
No broad model, both-backend, installation or full-suite rerun was required.
The prior 30af388 hosted result is not claimed here; this development push does
not trigger a full remote run under the new policy.
The owner adopted [[records/specs/references-and-relationships]] on October 27.
Inline references, backlinks and bounded traversal are planned, not implemented.
L01-L14 and LJ01-LJ10 define delivery and verification. Keep the active checkpoint
and engine qualification in place; inferred associations follow measured value.

Next, repair the observed stale-status claim about the withdrawn movement and
complete durable event identity across different IDs/runs. Extend direction review
to relevant later-page evidence and reduce its measured latency without treating
model judgments as proof. Continue J11 and native chat-table presentation,
retaining successful comparison/thread/draft and fresh clarification evidence. Current Home review is
implemented. Keep navigation shortcuts distinct from snapshots and retain the
recorded ordinary-language limitation.
The new action checkpoint does not qualify all language, microphone or accessibility
paths, native adoption, or automatic compaction.
Thread creation/rename still
use the existing generic writer lock; add a bounded writer path before treating
interruption under competing writers as qualified. Continue engine repeatability
review and remaining context, keyboard/VoiceOver, archive/transcription, whole-app
memory and release gates alongside that work.
Do not restart the architecture or weaken adoption gates.
[[records/specs/splash-integration]], [[records/specs/conversation-context]] and
[[records/operations/build-and-run]] retain the contracts and failed evidence.
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
4. Extend fault containment/qualification to structured XLSX/CSV ingestion, archive
   selection and file transcription as appropriate. Native document text/OCR worker
   isolation now passes; this does not qualify every ingestion or viewer path.
   Live single-phrase dictation passes; file transcription hardware remains open.
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

All four checks compiled and passed on c0ac40f in hosted CI 40503178418. Its
checkpoint-process-death artifact is retained as 12734101119, 152,915 bytes, archive
SHA256 1dc8f4bb13bc2299e1313eb134832bf367dffc224d48360efca3073613b3ebf5.
That digest is GitHub artifact metadata; local artifact inspection and replay are
still deferred while W1 runs. The complete hosted workflow subsequently passed.
These checks cover storage and process-death boundaries only, not actual-model
summary quality, repeated mid-job compaction, occupied 32K/64K contexts or the
complete C12/C13/J10 gates.
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
running as 40503178418. Its four checkpoint process-death/cancellation/concurrency
checks and inherited voice checks passed; the whole workflow remains pending.
Both branches remain separate from the frozen primary checkout. No local build, inference or test run overlapped
W1; only lightweight source/docs work and hosted CI were added.

W1 blocks 0 and 1 have complete native/reference workers, successful Ready primes,
48 successful workload jobs and exact paired request/generated-token equality.
The remaining eight pairs are required before the full gate can be assessed.
Frozen source/binary identities still match. This is progress, not a speed or
adoption claim. Preserve live local evidence until the complete report is final.

## Document draft durability
Source review found that document editing saved its input Source and new Record
in two transactions, allowing an orphan input if the second write failed. After
autosave, Accept and the active conversation context still named the original
version. A failed Done could exit editing and lose the unsaved text on reentry;
window/application close did not reliably flush or refuse that failure.

The isolated codex/document-drafts branch prepares one shared atomic edit API,
exact operation retries, a draft coordinator and native close/quit guards. A
conflict retains the text and offers an explicit separate draft. Earlier citations
stay pinned; the displayed current version feeds acceptance, undo, navigation and
agent context. Text or voice can request Save this document or Keep my changes as
a separate draft. The CLI exposes edit-document with an exact version, bounded
UTF-8 file, token, optional expected revision and explicit --separate option.
Original file assets cannot be edited through this path. The harness skill
records those semantics without claiming CLI-supplied text is human-authored.

Fourteen new checks cover atomic lineage, unchanged failure state, idempotency,
concurrent writers, Unicode/bounds, acceptance of the displayed edit, debounce,
retained conflicting text, per-window/application flush and actual AppKit delegate
forwarding/close refusal. A packaged CLI runner checks the same mutation boundary
and file/option refusals. These are prepared, uncompiled and untested at this
checkpoint; hosted CI is next. Formatting, Python syntax, skill validation and
db.md/link checks are lightweight prerequisites, not runtime evidence. Visible
editor/quit/voice journeys and large-text responsiveness remain pending. Local
builds and UI replay stay deferred until the frozen W1 cohort finishes.

## Hosted verification update during document repair
Full hosted workflows passed on 7f93617 / 40502209056 and c0ac40f / 40503178418,
including baseline app/CLI installation and the isolated native preview package.
Run 40503805532 on doc-only 2619062 was cancelled after replacement 210b0ba started;
it is not a pass. Run 40504115794 on 210b0ba remains in progress at this checkpoint.
The earlier targeted-only status above records what was known at those times.

W1 has completed both workers in blocks 0 through 3 with successful closure and
no worker failure. Block 4 is running; frozen source hashes still match. This is
an interim observation, not a completed performance or parity qualification.

## W1 current-request evidence failure
The frozen cohort completed five native/reference pairs, 120 workload jobs and
all ten Ready primes, then one Ready prime and one warmup in the next reference
worker before explicit termination. Block 3, sequence 4 failed the preregistered
missing-evidence assertion identically on both frontends. Both searches returned
zero business/history hits and incomplete=1. The model then read the Source
holding its own current request. The first absence claim was correctly refused;
the revised answer cited that request, said indexing may be incomplete and did
not produce the required host-rendered exact search-gap report. Current-request
text does not independently substantiate the requested contract or renewal price.

The finish path renders the authoritative gap only with an empty citation list.
A citation to the current request bypassed that presentation. Ordinary search
already excludes request-kind Sources by default; this is not a missing FTS
exclusion. The next repair should preserve legitimate request inputs and lineage
while preventing that citation from substituting for missing external evidence.
Do not weaken the frozen test to relabel this cohort as passed.

The owned controller received SIGINT after the failure was confirmed. It exited
130 and reaped its current worker; all recorded descendants were absent afterward.
The measured sources and binaries matched their frozen identities before and
after termination. No local build/test overlapped this attempt. Raw results,
requests/tokens, memory samples and interruption notes remain locally retained.
The incomplete report has workflowGatePassed=false and productionAdoption=false;
partial favorable timings and token agreement do not qualify performance.

Public evidence is integration/evidence/2026-10-27-workflow-current-request-failure.json.gz.
Its 3,146,959 uncompressed bytes have SHA256
 aab3c1eafd9756f318b16c5b3c8f6bd82fed45e1842c3e318c9682d98877e585.
It contains all completed/partial worker records, original failure assertions,
identity, summary, stop/cleanup records and a 641-file raw hash manifest. Public
rows omit generated-token arrays and replace local paths; original local bytes
remain the differential evidence. A corrected candidate needs a new complete run.

## Document verification follow-up
The initial 14 document checks passed on 9bc7ab4 in hosted CI 40507262611, including
the real AppKit close guard and previous-delegate forwarding. Core, voice,
checkpoint, table and search lifecycle steps also passed there; full packaging
is still running. The preceding doc-only 210b0ba passed its full workflow
40504115794. The skill validator initially lacked PyYAML in the system interpreter;
it passed using the existing development reference environment, with no install.

A fifteenth check now injects an SQLite failure on the second document insert in
a disposable fixture, verifying rollback of the already inserted Source, retained
editor text and a single successful retry. Conflict actions also adapt to a narrow
pane. These additions are prepared and have not yet run. Local compilation,
packaged CLI editing and visible draft/close/quit journeys follow now that W1 is
stopped. Generated-document responsiveness for very large text remains unmeasured.
A source review also confirms that item components currently open their stored
exact or logical binding and pinSpace freezes table values only. Complete live
versus pinned document/search component behavior remains part of P11/P16 review;
do not call all saved-space semantics qualified from table checks alone.

## Current-request evidence repair
A deterministic regression reproduced the W1 escape before the repair: an empty
search followed by reading/citing the current-request Source did not show the
known incomplete-source count. The host now refuses evidence-basis answers based
only on that Source, directing supplied inputs to current_request and unavailable
external facts to unresolved. Unresolved finishes after empty searches render the
actual query and indexing-gap receipt even when the model cites its own request.
Those citations are omitted from the displayed answer while exact original finish
arguments remain in its payload. Independent or unknown citations retain normal
validation; they are not silently erased. No model/tool schema, index or engine
pin changed.

All shared-agent deterministic checks pass, including six new cases for the gap,
a self-cited unsupported claim, supplied facts, independent evidence, mixed
citations and unknown-reference recovery. The first revised test fixture tried
to read an independent ID without first discovering it; the existing exact-ID
boundary correctly refused it. The fixture now searches that evidence before
reading it, then performs its empty query. Both that test-fixture failure and the
original failing regression logs remain locally retained. This is not yet a
real-model repair claim.

The fixed block-3 replay is scripts/probe_request_evidence.py. It uses the original
W1 order and seeds 3001 through 3008, Ready primes and the same pinned settings on
both frontends. It retains all outputs, corrections, requests, generated tokens,
source identities and cleanup, and requires exact paired request/token agreement.
It is a functional regression, not a replacement for a fresh ten-block W1 cohort.
The corrected release worker builds and passes its deterministic suite; actual
replay and rebuilt package/UI checks are next.

All 15 document checks now pass locally, including the new forced second-insert
failure, rollback and retry case. Local logs are .build/document-verification/.
The narrow layout change still needs visible replay. The previous freeze is over;
local builds and UI checks may resume, with no performance claim from overlap.

## Local lifecycle and visible document verification
The full scripts/check.sh suite passes locally on 8d0bb6e, including all 15
document checks, 14 injected voice checks and the four checkpoint publication
process-death/cancellation/concurrency checks. Both app/CLI variants rebuilt;
the native package paths check and both packaged document CLI runners pass.
The complete hosted workflow for 9bc7ab4 also passed as 40507262611; the newer
0ad35e3 and 8d0bb6e runs are still in progress at this checkpoint.

On the unlocked Mac, a synthetic native workbook accepted the just-edited 0.25 kg
text while preserving estimate meaning. A saved exact reference still opened its
original 0.10 kg version with an earlier-version notice; only the explicit newer
version action navigated forward. A fixture SQLite trigger rejected the second
insert after the Source insert: Done retained text, window close refused and the
actual native Quit menu refused. After removing the fixture trigger and writing
0.45 kg through the CLI, Retry reported the competing head without losing the
editor's 0.35 kg text. The conversation command Keep my changes as a separate draft
preserved both. Typing 0.55 kg and immediately closing the window persisted it;
reopening displayed that text and SQLite integrity passed. Native Quit succeeded
once saves were complete. Cmd-Q first returned to the welcome window, so shortcut
termination is not claimed from that observation.

Hosted checkpoint artifact 12734101119 was downloaded and independently matched
its recorded SHA256 1dc8f4bb13bc2299e1313eb134832bf367dffc224d48360efca3073613b3ebf5.
Its result.json confirms all four checks. This supersedes the earlier pending
artifact-inspection/local-replay status without erasing that historical checkpoint.
The public archive integration/evidence/2026-10-27-document-lifecycle-qualification.json.gz
contains 17 retained logs, source/binary identities, synthetic item versions,
visible observations and inspected hosted evidence. Its 173,905 uncompressed
bytes have SHA256 06a857bbe3c01a004778f5b6f29c68127e1ab065c78dac689e69e66b0d74fb00.
These are focused checks, not complete keyboard/VoiceOver, narrow layout, hardware
voice/media, large-text responsiveness, all spaces or release qualification.
The fixed actual-model missing-evidence replay is running separately with frozen
sources and has no final result yet.

## Complete pinned-space bindings prepared
Source review confirmed that pinSpace only captured table-derived values. A logical
document/asset binding could advance after pinning, and search components reran
against current indexes while the space implied a saved result. The separate
codex/space-snapshots branch (3b5eda2) prepares one atomic copy with resolved exact
item versions, nested comparison bindings and the bounded first search page.
Saved query/time/versions/locators, index-gap count and a more-results flag preserve
its scope. Re-pinning keeps original results/time. Live searches move off view
rendering through the existing stale-result-safe session, with explicit errors,
empty results and coverage limits. External file references remain references.

Five new core checks cover changes after capture, exact old references, reopened
and portable workbooks, original empty-search gaps, idempotent re-pinning, bounded
search pages, invalid pinned/live declarations and atomic refusal of an oversized
child. Formatting passes. This branch is prepared but has not compiled or run
locally; no runtime pass is claimed. The fixed current-request replay continues
against untouched primary-checkout sources. Merge and execute this work only after
that replay is terminal, retaining both source identities and failed attempts.

## Current-request real-model replay passed
The fixed original block-3 schedule completed on both frontends using frozen
8d0bb6e sources and the unchanged engine/model/grammar pins. All sixteen workflow
jobs and both Ready primes passed. All 37 paired actual requests and generated
outputs match exactly. Both workers confirmed clean closure, all recorded processes
were absent afterward and every frozen source/binary hash still matched.

The original seed-3005 missing-evidence case still needed one host correction on
each frontend. Its final answer now reports the actual two empty queries, exactly
one incomplete source and that those searches do not establish the requested facts,
with no displayed citation to the current request. Seed 3006 also retains its
currency correction on both frontends. Corrections and their latency are retained;
this is not a claim that every raw model answer was correct or that unrelated
semantic grounding is solved.

Public evidence is integration/evidence/2026-10-27-current-request-replay.json.gz,
including original request/prompt/generated-token data, sampling, exact source
snapshots, summary and post-run verification. Its 5,090,684 uncompressed bytes have
SHA256 cea200bd696e4fd22c8f11f9d046ec7aac9561fb6129f81ca4ce00b1cb915047.
The earlier failed cohort remains unchanged. This focused regression is not the
complete ten-block W1 performance cohort, an occupied-context qualification or
production adoption. Measured-source editing and local builds may resume now.

## Pinned-space runtime verification and media crash
After integration as cbe48ce, all 64 core checks pass, including the five new
pinned-space cases. The pin operation now runs off the UI thread with shared
cancellation through its search/capture steps and atomic refusal. The complete
local suite passes again; both packages build, native installed resources/Metal,
missing and altered-resource refusals, signatures and both document CLI runners
pass on that candidate. An initial command used ./scripts/build_native.sh despite
that script not being executable; its permission-denied log is retained, and the
actual build passed using the documented bash invocation.

Visible native checks confirmed a pinned copy's time, original eight hits and two
incomplete indexes. After ten documents were edited through the CLI and one new
matching Source was added, the live view showed the new match/current document;
the pinned copy retained the old eight hits and original document with an earlier
version notice. The fixture is .build/space-media-ui-20261027/Spaces.sevra.

Opening its synthetic MP4 then crashed the packaged app before playback. The
retained report Sevra-2026-10-27-083408.ips shows SIGABRT during VideoPlayerView
superclass metadata initialization in _AVKit_SwiftUI. The system log reports a
failure to demangle AVPlayerView, and otool lists the SwiftUI overlay but omits
AVKit.framework. This is a real failed native media journey. A direct
NSViewRepresentable/AVPlayerView adapter is now being built for both the primary
viewer and compact retained player, with a packaged-framework regression check.
Playback ownership remains in the existing workbook registry. Actual video/audio
replay is still pending; do not claim media qualification from a successful build.
Apple's AVPlayerView and NSViewRepresentable documentation support this native
bridge; upstream wrapper causation beyond the observed missing dependency is not
claimed. See https://developer.apple.com/documentation/avkit/avplayerview and
https://developer.apple.com/documentation/swiftui/nsviewrepresentable.

The earlier welcome-window observation after Quit was investigated: the prior
process exited and the subsequent CUA observation relaunched a new process.
Quitting without asking the observer to reopen the target left no native app
process. Do not report that tooling observation as a Sevra quit defect.

## Native media repair and minimum-window verification
The direct AVPlayerView bridge passed both packaged builds and actual native
video/audio replay. It explicitly links AVKit without the SwiftUI video overlay;
the native package checker now verifies that dependency. Media opens paused,
explicit Play advances its timeline, Keep playing survives Back in a compact
player, and Close player removes it. Closing a workbook during retained playback
and reopening resets the viewer to paused at 00:00 with Keep playing off. Synthetic
silent fixtures establish lifecycle behavior, not audible-output quality.

Minimum-size native checks showed stacked comparison columns, a visible composer
and all three failed-save recovery actions. A synthetic second-insert failure kept
the draft; removing the trigger and Retry persisted the exact text. System/light
and explicit Dark were readable, then System was restored. Command-Shift-F focused
search. The exact synthetic term returned the newly added evidence and retained
the two incomplete media indexes. A spaced variant correctly returned no lexical
match. Filename search still opened the unsupported-for-extraction MP4.

Final SQLite integrity, exact draft text, original pinned definition and removed
fault trigger were independently verified. Both packaged document CLI checks,
baseline resource checks, isolated baseline install/update/uninstall and native
resource/Metal/missing/altered/signature checks pass after the media repair.
The complete shared suite passed after async pinning; the later media wrapper was
verified through both builds, packaging and actual UI. No native preview or Splash
helper remained after actual Quit. Microphone/speech approval is pending, so no
hardware recognition result is claimed.

Public evidence: integration/evidence/2026-10-27-space-media-qualification.json.gz.
Its 853,218 uncompressed bytes have SHA256
846170630e32a89132eff529111230815e6b9178b1ab6f569d84818861a4d61e.
It includes 18 retained logs, candidate source/binary hashes, source snapshots,
synthetic fixture state and precise UI observations. The initial failed build
invocation and media crash remain findings; only a sanitized relevant crash
excerpt/hash is public. Raw device/session metadata and vendor documentation are
not republished. These focused checks do not complete VoiceOver, all keyboard
paths, full W1, occupied contexts, whole-app memory or release qualification.

## Corrected full W1 cohort started
A fresh complete W1 cohort started from clean commit 0e45190d886ba84889261614820b58ed03035ff1 with
a rebuilt release workflow worker and the unchanged model/engine/protocol pins.
It uses ten paired blocks, alternating frontend order and rotating workflows,
with one warmup and two measured repetitions per workload in each worker.
The native preview was quit, AC power was confirmed and local builds, downloads
and other inference stopped before launch. The first native warmups passed.

Command:

~~~sh
python3 scripts/compare_workflow_performance.py \
  --models-root .build/native-fresh-setup \
  --output .build/workflow-performance/current-cohort2
~~~

The console is .build/workflow-performance/current-cohort2.console.log. Its
identity.json freezes all measured source/binary hashes. Preserve every worker,
request, generated output, memory trace, failure and exclusion. Do not edit the
measured sources or rebuild while it runs. Documentation-only updates do not
change those inputs. This is running evidence, not a passed performance gate.
Inspect the terminal result, all paired conditions and cleanup before adoption.

## Linked-asset preview responsiveness prepared

Code inspection found that assetURL held the workbook recursive lock throughout
external-file hashing. A detached preview task could therefore still block UI
refreshes waiting for database state. Its task cancellation also did not reach
the file reader, and late completion lacked request ownership checks.

The prepared correction snapshots catalog metadata before filesystem work,
streams hash progress with cancellation, keeps changed-byte rejection, and checks
cancellation before committing relinks. Existing intake, extraction, archive,
transcription and CLI cancellation tokens now reach the same asset verification.
The native preview owns a cancellable session, shows opening/checking progress,
keeps external-file recovery available and offers Stop/Retry. Switching or closing
a preview invalidates late success, failure and progress. Successful relink reuses
its verified URL rather than immediately hashing the whole file a second time.

A core regression holds hashing at a chunk callback while an independent workbook
read must finish; it also covers chunk cancellation, relink rollback, successful
reconnection, changed original rejection and regular-file validation. Dedicated
preview checks cover stale results/progress, Stop/Retry, view/task cancellation,
cancellation before entry and changed-file failures. They are included in the
shared check script and CI. Formatting and diff checks pass. Compilation, runtime
checks and native large-file UI qualification remain pending; local builds stay
paused during the frozen full W1 cohort. No multi-gigabyte memory or rendering
performance result is claimed from source inspection.

On 57e9fd1, hosted run 40518997102 passed the core invariant/integration suite,
document lifecycle checks and the new preview cancellation/stale-read executable.
This executes the workbook-read-during-hash regression and cancellation/relink
checks rather than relying on source inspection. A follow-up fixture ensures a
first late progress callback cannot be hidden by the producer's throttle. Voice
lifecycle and checkpoint process-death checks also passed in that run. The full
workflow and app build are still running, so this is focused runtime evidence,
not final packaging or a large-file native interaction result.

The independently frozen W1 cohort has completed its first two native/reference
pairs. All 52 jobs including four Ready primes passed, with exact paired requests
and generated outputs and successful worker closure. This is partial progress
through the fixed ten-block protocol, not a passed performance/adoption gate.

## Active-job continuity comparison prepared
The separate codex/continuity-release checkout prepares --active-context to test
repeated maintenance inside one mutating job, against the same fixture without
maintenance at 64K. It preserves real model choice, original source versions,
normal tool/output/step bounds and actual token measurements. Both functional arms
must succeed, with at least two active checkpoints in the 32K arm; missing coverage
and all failures remain explicit. This is a C12 subset, not a C13 performance claim.

Source formatting passes. Compilation and execution are deliberately deferred
while the frozen full W1 cohort runs in the primary checkout. No product code,
model pin, threshold or frozen source/binary was changed. Documentation now states
explicitly that both packaged product paths disable automatic maintenance; only
dedicated native probes opt in. The previous wording could be mistaken for an
enabled native-preview feature. See [[records/specs/conversation-context]] and
[[records/operations/build-and-run]] for the protocol and command.

The probe compiled and the complete hosted workflow for 6886540 passed in run
40516968758, including baseline and native package builds. Its actual-model arms
remain unexecuted while the frozen W1 cohort runs. The prepared probe, corrected
compaction documentation and linked-asset preview changes are now combined in one
development branch. Both branches' source changes and log entries are preserved;
only generated catalogs were rebuilt after the merge. This does not change the
primary checkout's frozen measured code, production defaults or upstream pins.

## Large linked-file verification check prepared

The combined development branch adds a real 2 GiB-plus linked-file verification
probe to the shared check script and hosted CI. It exercises the production
preview session and streaming hash path, including cancellation after 8 MiB,
complete retry, same-size changed-original refusal and unchanged workbook evidence.
A parent process measures lifetime peak physical footprint before allowing exit,
with a fixed 256 MiB headless-process ceiling. The report records executable and
source identities and retains failures. The sparse input is synthetic data, not
playable media; no rendering or whole-app performance claim follows.

Swift formatting, Python syntax, command help, link and dbmd checks pass.
Compilation and execution of this new large-input probe remain pending hosted
CI; local builds and file-intensive tests remain deferred during the frozen W1
measurement. Earlier passing small core/session regressions do not qualify this
new fixture. Reproduction is in [[records/operations/build-and-run]].


The new probe passed on hosted arm64 macOS 26.6.2 at commit 96b8528, run
40520881612. It verified all 2,148,532,224 original bytes, cancelled at exactly
8,388,608 bytes, then rejected a same-size changed original without changing the
workbook revision or saved asset hash. Darwin lifetime peak physical footprint
was 6,489,600 bytes (about 6.2 MiB), below the preregistered 268,435,456-byte ceiling.
The complete fixture/verification process took 7.74 seconds; that is not a cold
storage or UI latency qualification. Sparse source bytes explain why actual disk
reads are much smaller than the hashed length.

Artifact 12740609605 is 1,324 bytes with SHA256
bbf2cf53282867459c258131201532ea9c4d6290eee5f69eb61467896abb270a.
Its digest was checked before extracting the three expected bounded log files;
all five reported source hashes match the recorded commit. Full result, stdout,
empty stderr, executable identity and explicit limits are preserved in
integration/evidence/2026-10-27-large-linked-preview.json. This is a passing headless
verification result, not native media rendering, complete UI responsiveness,
full-app memory or broad hardware qualification. Later composer-control edits
still require their own checks. The full 96b8528 hosted workflow is still running.
## Conversation controls for file previews prepared

Review found that the composer disabled every submission while work was active,
including Stop. Native preview Stop/Retry/Find original also lacked composer
routes. The prepared correction routes complete shell-control submissions before
model dispatch and keeps those submissions available while busy. Stop/cancel
cancels the active operation and an opening preview; stop preview only cancels an
opening file, leaving an already loaded viewer alone. Retry and Find original
share the viewer's session, preserve hash verification and do not invoke a model.
Find original refuses a stale window/preview selection after its picker returns.
The same input path serves submitted dictation, but hardware voice remains pending.

Preview retry/reconnection now invalidates old work immediately rather than
waiting for SwiftUI's replacement task. A generation identity prevents a previous
success from clearing a newly selected original. Focused checks cover that race,
complete-control admission while busy and refusal to interpret negated or unrelated
submissions as shell controls. Swift formatting/diff and documentation checks pass;
new runtime/compilation and actual native interaction checks remain pending.

Separate inspection finding: several older asynchronous workspace operations lack
uniform late-completion ownership checks, and closing a workbook currently stops
media/dictation/preview without consistently cancelling its general operation.
Review and qualify that lifecycle next, preserving completed mutations and avoiding
old callbacks appearing after a workbook switch. This finding is not a tested fix.

## Workspace operation lifecycle prepared

Code inspection confirmed that imports, export, URL capture, review, transcription
and model callbacks did not share a reliable window ownership boundary. The
prepared change gives each operation a cancellation token and unique owner.
Closing/switching invalidates that owner; late progress, errors and completion
cannot clear a newer operation. Completed mutations and event messages remain in
the original workbook/conversation. Result navigation also checks the original
conversation and navigation identity, preserving a user's intervening exploration.

Stop keeps ordinary operations busy until they finish. Waiting for an OS speech
permission response is different: Stop releases the UI immediately, and a late
response cannot start transcription or stop a newer operation. No microphone or
speech permission was requested during these checks. Import/export pickers reject
a changed workbook on return. Opening another workbook resets its conversation,
route, search and table state; closing invalidates outstanding search callbacks.

The added asynchronous regression uses two real temporary workbooks and a delayed
completion to check durable save isolation, stale progress/focus/completion, Stop
ownership, duplicate completion and a delayed permission callback. The search
suite adds reset-during-read coverage. These are prepared regressions, not proof
of native app lifecycle behavior. Swift formatting and diff checks pass; hosted
compilation/runtime and focused native close/switch checks remain pending. Local
builds and inference remain deferred during the frozen full W1 cohort.

## Native search cancellation propagation prepared

Review found that the main search view created a detached SQLite read without
passing cancellation. It discarded stale results but could leave obsolete work
running until the core query deadline. SearchSession now owns the reader token,
cancels it on replacement/reset/task cancellation and passes it into both native
search views. The existing SQLite progress budget observes this token. Leaving
search stops active work while retaining completed pages, cursor and Back anchor.
Cancellation does not publish an error or imply an empty result.

Delayed-read regressions now check that replacement, clearing, task cancellation
and workbook reset actually signal the reader, not just discard its return value.
An additional next-page cancellation preserves earlier results and retries through
a real workbook search with a fresh token. Existing core checks cover cancelled
and expired search budgets followed by a usable query. These prepared checks do
not establish cancellation latency under a large live SQLite workload; that native
measurement remains pending. Formatting and diff checks pass; hosted compilation
and runtime checks for this change are pending.

Hosted run 40519770358 completed successfully for 9a2f58a, covering the earlier
small linked-asset/session changes and both app packages. The larger-file evidence
remains tied to 96b8528 and its specific passing step; newer composer and workspace
changes require their own completed runs. The frozen W1 cohort is now on block 4;
no complete-cohort performance conclusion has been made.

## Remaining workspace callback paths prepared

Table edits and undo/redo now use the same operation owner as imports and model
work, with cancellation checked before their atomic mutation. Late completion
cannot change the undo stack or error in a different workbook. Delayed native
drag/drop providers retain the original interaction, workbook and conversation;
close/switch invalidates the drop instead of importing into a new destination.
File pickers also compare the interaction generation, covering close/reopen with
the same workbook object. The bounded text-file viewer clears old content on a
new file and refuses a cancelled result or error. These app wiring changes pass
formatting/diff review; native compilation and interaction verification are pending.

The new workspace ownership regression in 9044e5e passed in hosted run
40523815521, alongside core and document checks. That workflow is still running;
this does not qualify the newer search cancellation or callback wiring changes.
The complete combined continuity/asset-preview checkpoint c9251aa passed run
40520155806. The redundant documentation-only run 40522177262 was cancelled to
allow current source checks to start; cancellation is not recorded as a pass.

## Bounded Home catalog prepared

Inspection found that every WorkspaceState refresh loaded up to 100 complete
non-row Items, including their document body and structured data, just to display
up to 20 recent titles. Large generated documents could therefore inflate Home
refresh memory even when none was open. Home now uses a distinct ItemSummary type
and a metadata-only SQLite projection capped at 20 entries by default. Row and
request exclusions occur before the limit. Exact version IDs, Source/Record
category, meaning, acceptance and asset identity are retained. Existing full-item
read APIs and original evidence remain unchanged.

The prepared core regression includes a 2.1 MB document body and 1 MB payload,
accepted-estimate metadata, a corrected version, an included asset and newer
internal requests/rows. It checks a bounded serialized catalog, exact current IDs,
original readability and unchanged workbook revision/integrity. Formatting and
diff checks pass; the new runtime check and app compilation await hosted CI. This
is not a full-app memory result. Synchronous metadata refresh can still contend
with database work; native responsiveness under active large queries remains an
explicit measurement/follow-up, not a completed claim.

## Search test compilation correction
Hosted run 40524238057 compiled the changed SearchSession but failed compiling its
delayed-read fixture: adding a token assignment made its continuation expression
require an explicit return. The fixture is corrected without changing product
behavior or assertions. The search check now runs before the slower product-model
module build so this inexpensive boundary reports earlier. Preserve that failed
run; no passing search runtime result is claimed until the corrected check runs.

The new recent-item catalog regression and the core/preview suites passed on
af702ee in run 40525067058. Its full workflow remains unqualified and inherits the
same search-fixture compilation error until this correction. Separately, the
complete 96b8528 workflow finished successfully (40520881612), including baseline
and native package builds and installation. That is the older large-file
checkpoint, not proof of the newer workspace/search/catalog app wiring.

## Current focused verification follow-up
The complete composer-control checkpoint 202d513 passed hosted run 40521849734,
including baseline/native package builds and install checks. Later workspace,
search and metadata changes remain tied to their own runs. Run 40524689438 on
e4f7225 failed at the same missing-return search fixture as 40524238057; the exact
compiler finding was inspected and remains retained. The correction is 426dd2d,
with run 40526063413 in progress. Newer runs must not inherit an older full pass.

The first five frozen W1 pairs have now been independently inspected: 130 jobs
including ten Ready primes pass validity checks, request hashes and generated
tokens match in each pair, all ten workers report closed, and no worker failure
is recorded. Block 5 is running. The full ten-block performance/condition gate
remains incomplete. Frozen sources were checked unchanged during this work.

This follow-up changes only documentation. Repository links and full dbmd
validation pass locally; the ongoing 426dd2d code workflow remains the relevant
compilation/runtime check rather than launching another identical app build.

## Corrected search runtime passed
On 426dd2d, hosted run 40526063413 passed the corrected search executable, including
reader-token cancellation for replacement/clear/task/reset, rejection of late
results, preserved earlier pages/anchor and a real next-page retry with a fresh
token. The core catalog regression, document/preview ownership checks, large-file
probe, checkpoint process-death checks and table checks also completed before it.
The full workflow and app package builds are still running. These focused results
do not establish native large-query interruption latency or final visible UI.

The prior af702ee full run 40525067058 failed after its passing core/catalog and
preview steps, before the test-helper correction. Retain that failed checkpoint;
the passing corrected search result belongs to 426dd2d, not to the earlier source.

## Search-scale qualification strengthened, prepared
The old benchmark reported aggregate times and limited recall booleans without
refusing a failed recall result, retained no complete warm sample set and ran the
document corpus only under an environment flag. The prepared v2 default covers
both 10k/100k corpora, preserves every sample and fixture, checks exact IDs and
complete multi-chunk paging, and fails its protocol result on semantic errors or
missed 100k latency/interruption targets. Hardware, actual source/binary hashes and
initial/final identity are recorded. Numeric sorting remains measured.

The cancellation probe reports a fast already-finished call as uncovered, retains
that observation and verifies that subsequent reads still work. It does not claim
to trace SQLite instructions or solve native MainActor responsiveness. The small
200-entry self-check now runs in CI/shared checks and uploads bounded JSON reports,
not large fixture databases. It cannot qualify 100k performance. The nearest-rank
percentile and changed query matrix are versioned rather than silently treated as
the earlier roughly 220 ms observation.

Formatting, shell syntax and diff checks pass. New compilation and small-fixture
runtime remain pending hosted CI; full reference-Mac measurement stays deferred
until the independently frozen W1 cohort ends. No local build, scale corpus or
model workload was started alongside W1. The complete workspace-ownership build
9044e5e has meanwhile passed hosted run 40523815521. The current 426dd2d workflow
has passed its baseline app/install checks and is building the isolated native
preview; its final result remains pending.

## Search-scale self-check artifact inspected
The prepared v2 benchmark compiled and passed its 200-row/200-chunk self-check on
9043fff in hosted run 40530670227. All 42 sampled reads passed their fixture
assertions. The multi-chunk case traversed three pages containing exactly its 20
document versions, without duplicates. Both cancellation calls had already
finished when Stop was requested, so interruptionObserved=false, required=false
and cancellationTargetMet=null are retained. This is explicitly no large-query
interruption evidence.

The 10,066-byte artifact 12745618078 was downloaded and its SHA256 verified as
06eb0384261ce2348deb4ceabc767c7ce4fb39317154e259fc62d81988c517fd.
Only the four expected bounded JSON members were read. All 35 source hashes match
9043fff; initial/final source and binary identities match, and the runner reported
a clean checkout. The runner is VirtualMac2,1 with Apple M1 (Virtual), macOS
26.6.2 and 7 GiB memory. It is not the physical reference Mac. The byte-preserved
result and receipt are in integration/evidence/2026-10-27-search-scale-self-check/.
The full workflow remains running; only this focused step is qualified.

Separately, the complete current application checkpoint 426dd2d passed hosted
run 40526063413, including core/catalog, document/preview/search, process-death,
grammar/model-lifecycle, both packaged apps/CLIs and installation checks. This
closes its automated build/regression gate, not the remaining native interaction,
whole-app memory, W1, occupied-context or scale gates.

## Frozen W1 seven-pair checkpoint
Worker files for blocks 5 and 6 were independently checked after the earlier
five-pair review. Both pairs contain all 26 valid jobs including their Ready
primes, exact request hashes/generated tokens, closed workers and no worker
failure. Cumulatively the first seven paired blocks contain 182 valid jobs.
The measured source hashes still match identity.json. The coordinator was
confirmed live with native block 7 in progress. No full-cohort latency or adoption
conclusion follows before the final three pairs and terminal conditions complete.

## External file copy integrity, October 27
The previous Open in another app action supplied the canonical included file
URL to NSWorkspace, allowing an external editor to overwrite saved evidence.
The replacement uses a persistent user-chosen copy, checks its streamed SHA-256
and byte count, and atomically publishes without overwriting. Native Save and
Open and exact composer commands share the operation. Copy completion is guarded
by workspace identity and cancellation before launching another app. Tests cover
included/linked copies, editing isolation, empty files, interruption and staging
cleanup, same-size corruption, package aliases, existing or competing files and
changed linked originals. These are prepared changes; compilation, execution and
visible native save/open behavior are not yet claimed.

Hosted run 40536758642 on 6c9da08 passed the core copy invariants and the search
self-check, then failed to compile the added preview assertions because their
helper requires an explanatory message. The repair supplies those messages.
The copy action also checks the displayed version before opening its save panel,
and destination ownership compares normalized filesystem paths. The failed CI
run is retained; a new full run is required.


After preserving W1, the primary development checkout fast-forwarded to 21a8cd2.
The complete local scripts/check.sh suite passes, including copy invariants,
preview commands, large-file checks and all existing search/agent/grammar gates;
links and full db.md validation also pass with zero errors and warnings. Native
visual copy/save/open checks remain pending.
## Complete W1 cohort and parity failure, October 27
Frozen 0e45190 completed all ten paired blocks (20 workers, 260 jobs including
20 Ready primes). Independent audit validates all 984 request observations,
485 unique serialized frames and prompt arrays, 93 unchanged source/binary
identities, successful worker shutdown and no surviving recorded processes.
The retained summary recomputes exactly. No paired block was excluded.

One warmup diverges: block 9, inventory_evidence, seed 9002, second request.
Its actual request frame and 7,059-token prompt match exactly. Both report
1,568 deduplicated KV tokens and zero matched prompt tokens. Generated tokens
first differ at zero-based offset 19, producing 230 native versus 234 reference
tokens. Both request the same evidence item; downstream prompt histories then
differ. Both final answers correctly cite 20 minus 2 equals 18. The trace locates
the discrepancy but does not establish its engine/scheduler/numerical cause.

Every workflow's native/reference median and p95 ratios stayed inside the frozen
5%/10% thresholds. Supplier: 1.0151/1.0168; formula: 1.0247/1.0093; inventory:
0.9833/0.9798; missing evidence: 0.9654/1.0043. These are retained observations,
not a passed performance gate: the protocol explicitly requires exact parity
for warmups too. Production adoption remains false. Do not erase this failure,
selectively exclude the warmup, silently relax the gate, or run another full
cohort before a focused diagnosis.

Full public evidence: integration/evidence/2026-10-27-workflow-cohort2-parity-failure.json.gz.
It preserves every JSON/stderr file and original-file SHA, with ordinary local
paths sanitized. Decoded request frames were checked for literal home/temporary
paths; model inputs come from the committed synthetic fixtures. The original
local run and frozen worker binary remain preserved. Compressed SHA-256:
99e7b90d29acbc1cd44f1a5395130c736a384a0985900828254cee5095174052. Uncompressed SHA-256:
f82a88441fbf409c5c0db5ec19698704996df05a73cd023cf1da3bc6b67cfb23.

## Hardware dictation permission checkpoint, October 27
The owner explicitly approved both speech and microphone permission. The native
preview opened the synthetic Spaces workbook and started dictation, but the
computer-use tool refuses access to macOS UserNotificationCenter. The owner was
asked to perform the macOS Allow clicks directly, not to reapprove the request.
No permission bypass or alternate access to the restricted system app was used.
Hardware capture/transcription is not yet established. The previous UI showed
only Stop for every active phase; a follow-up adds visible waiting/starting/
listening state and the same accessible value. The source change still needs
compilation and native visual verification.

The native release target compiles successfully with the phase indicator. Its
compiler also identified two file-action closures reading a main-actor item
property from background work; capture the immutable item ID at the button
action instead. The editor binding uses an explicit closure to retain inferred
isolation. This is a source correction; a rebuilt package and visual pass are
still pending the permission handoff.

On 75cb253, the native release target rebuilt successfully without warnings in
that rebuild, and all 14 synthetic voice lifecycle checks pass. Commands used:
SEVRA_NATIVE_CANDIDATE=1 swift build --scratch-path .build/native-product
--configuration release --product SevraDesktop -j 4; swift build --product
sevra-voice-checks -j 4; .build/debug/sevra-voice-checks. Native packaging and
visible status verification remain pending.

The pending dictation session was explicitly stopped in the native UI; the
button returned to Start dictation and no transcript was entered. A late
permission grant must not automatically begin capture. Leave the existing app
available for the owner to complete the macOS permission step, then start a
fresh session for one spoken phrase. Do not treat approval or a Stop icon as
proof of microphone capture.

Hosted 6bac991 run 40538012306 and latest 75cb253 run 40540174787 remain pending
at this checkpoint. The intervening a58903b run 40539699089 was superseded and
cancelled, not passed.

## D9 prefix diagnosis prepared, October 27
Prepare scripts/probe_workflow_prefix.py and its frozen protocol for the exact
W1 block-9 failing prefix, using the preserved worker and independent controller
identity. The helper now optionally accepts an explicit worker executable;
ordinary W1 callers retain the same default. Meaningful report checks pass for
incomplete/reordered schedules, bad jobs, power/thermal/roles, missing cache
counters, source drift, unexpected interventions and cleanup. Token divergence
remains visible without mislabeling a valid diagnostic as a passing W1 gate.
Actual D9 execution has not occurred at this checkpoint.


The first D9 attempt completed the reference prefix with valid jobs and clean
shutdown. At the same inventory request, its output differs from its own W1
reference baseline after token 19 (and from the W1 native baseline after token
22). This is observed within-reference variation, not evidence of a Swift-only
parsing difference or a proven numerical cause. The native Ready prime then
refused because copying the executable alone omitted its adjacent selected-model
resource. Preserve that incomplete attempt in
integration/evidence/2026-10-27-prefix-d9-missing-resource.json.gz.

The original release worker still has the exact frozen binary hash and complete
resource bundles. Add preflight checks for all three native JSON resources and
verify their bytes against the original Git tree before running any frontend.
The corrected D9 command will use that unchanged original executable and a new
output folder. Resource-missing regression checks pass. No product resource
fallback is added and no failed run is discarded. Full 6bac991 CI (40538012306)
has also passed, including both packages and installation checks.
## Full search-scale-v2 baseline, October 27
Run the release sevra-benchmark from clean 4ac137d on the M5 Pro 48 GiB Mac,
with no overlapping local build or inference. The native app was idle with
dictation stopped. Capture power/thermal/process memory before, during and after;
maximum observed thermal state is nominal. All 36 recorded source/binary inputs
remain unchanged. The new 10k and 100k row and document-chunk fixtures retain
correct recall, exact unique evidence across all 34 document pages, and observed
cancellation with a following successful read and unchanged revision.

The 100k row warm p95 is 203.990 ms; 100k document chunks are 275.292 ms. Both
miss the 200 ms target. Their observed Stop-to-return times are 0.101 ms and
0.061 ms. The 10k row/document warm p95 values are 15.738/24.314 ms. Broad
queries dominate; exact identifiers stay sub-millisecond in these synthetic
fixtures. No UI, cold-cache or general-device qualification follows. Preserve
the failing results before optimizing the query.

Public raw reports and conditions: integration/evidence/2026-10-27-search-scale-v2-first-full.json.gz.
Compressed SHA-256: 06c2ca06553d79930b87cca2a52a0f8018ef10303df5c107223b0883f1048472.

## Complete D9 repeatability result, October 27
The corrected diagnostic on controller 22cca90 used the preserved 0e45190 worker
and original adjacent resources. All twelve jobs in four fresh workers completed
correctly, with no sampling/condition/cleanup failures. Independent audit rehashed
all thirteen frozen inputs, twenty-two observed requests, six unique wire frames
and six unique prompt arrays, recomputed the summary exactly and confirmed every
recorded worker/helper/reference PID closed.

Both native repeats matched each other and the last reference repeat completely.
The first reference repeat diverged from the last reference at inventory request
two, output token 19, despite identical request bytes and preceding history. The
first reference finished in two requests while the others used four; all gave the
correct cited stock balance. This demonstrates reference repeatability failure,
not a proven Swift bug or a root cause in any particular kernel/cache operation.
Timing/adoption qualification stays false. No full W1 rerun or gate weakening
followed this result.

Archive: integration/evidence/2026-10-27-prefix-d9-repeatability.json.gz, 406932
bytes; uncompressed SHA-256
5296c2925f62e95b7975d673122238d21c2900ecda521b1a1e728b2e398a5523.
It contains the full four worker arms, root summary, identities, request/prompt
artifacts, sampling and independent audit, with local paths sanitized. The first
missing-resource attempt is retained separately. Search profiling began only
after all D9 workers had exited.

## Bounded snippet retrieval, October 27
Search keeps the existing lexical/filename ranking, filters, best passage and
revision-bound pagination. It fetches snippets for only the displayed IDs using
one FTS cursor per nearby group. Each group spans fewer than 4096 row IDs; sparse
hits split into separate groups. Unary + on rowid membership prevents SQLite from
restarting the full-text query per hit, while ordinary lower/upper bounds still
seek the index. Membership remains explicit so neighboring evidence never leaks
into the page. Filename-only matches retain their stored excerpt. The existing
read transaction and cancellation/deadline budget cover all groups.

Seventy core checks pass, including a new sparse/dense/filename-only/diacritic
fixture comparing exact snippets, locators and ranks across page sizes. The
full 100k measurement remains pending at this checkpoint. The earlier failed
latency result is preserved.

## Full search-scale repair verification, October 27
The complete unchanged search-scale-v2 protocol passed on clean committed
48b1a30418e61b05983e0db5cb31f81f877735c8. Warm p95 fell from 203.99 to 136.47 ms for
100k rows and from 275.29 to 172.31 ms for 100k document chunks. The 10k results
were 8.38 and 11.75 ms. All sampled recall assertions passed, and document paging
visited exactly 1000 unique documents in 34 pages at both scales.

Stop interrupted the active 100k calls in 0.081 ms (rows) and 0.205 ms (documents),
followed by successful reads at the same workbook revision. These are call-level
measurements, not UI response measurements. The 193 process samples had no errors,
nominal thermal state and an observed peak physical footprint of 144147176 bytes.
The host remained on AC with no overlapping local builds/inference; its idle preview
app and unrelated OS activity were uncontrolled. All 36 source hashes match the
recorded commit and end-of-run identity; the release executable is unchanged.

This completes the synthetic reference-Mac warm latency/recall/cancellation target,
not OS-cold, whole-app, all-corpus or wider-device qualification. Full regression
is running separately after the benchmark. Archive:
integration/evidence/2026-10-27-search-scale-v2-batched-snippets.json.gz (30141 bytes),
SHA-256 dd7ae1f33b09e622859ab07d01a979ff49816ec9102db73093dc3cc1264151c2;
uncompressed SHA-256 8d74730632d3d625eedcbdd84f315e51011ead4582cbc9ab0de1acbb868ef2cb.
The earlier failed full run remains preserved. No repeated benchmark or broader
speed claim follows without a new change or unresolved concern.

## Search repair full regression and native build, October 27
On 48b1a30, scripts/check.sh completed with exit 0, including 70 core checks,
15 document lifecycle checks, 14 voice lifecycle checks, 30 native adapter/setup
checks, the exact tokenizer/stream/grammar fixtures, search/preview/product
lifecycle checks, performance-report refusals, link gate and full dbmd validation.
The native release SevraDesktop build also completed with no warnings. Logs and
commands are retained in integration/evidence/2026-10-27-search-snippets-regression.json.gz.

This compiled build is newer than the packaged preview currently open for the
human macOS-permission handoff. It has not replaced that running bundle and does
not establish hardware dictation or the new visible external-copy journey. Hosted
workflow 40540174787 on 75cb253 passed; the latest 48b1a30 workflow is still running.
The search performance run ended before regression/build work resumed.

## Actual active-job context probe started, October 27
The first invocation on frozen 48b1a30 supplied the resolved assembly instead of
the installation root. Both arms stopped before inference with a model-assembly
lookup refusal and unloaded. Source, binary, engine and grammar identities stayed
unchanged. This is invalid setup, not a context outcome. Full receipts:
integration/evidence/2026-10-27-active-context-wrong-root.json.gz.

The corrected invocation uses the installation root with its selected-pack
symlink, unchanged installed weights, the same debug worker and frozen fixture.
It runs the specified 32K maintenance and 64K reference arms sequentially, with
no overlapping local builds/inference. The 32K job has reached two real active
checkpoints; final correctness and the reference arm are still pending. Original
failures remain retained. This does not enable compaction or satisfy C12/C13 in
full. Final results must replace this in-progress status before assessing success.

## Active-job v1 fails exact facts and uncompressed capacity, October 27
The corrected actual-model run on frozen 48b1a30 is complete. Maintained32K used
twelve responses and three active checkpoints, then reported completion and saved
one draft. Independent inspection finds four swapped label/value associations:
CEDAR 0.35 vs expected 0.31 mm, IRIS 0.34 vs 0.32, WILLOW 0.32 vs 0.34, and BIRCH
0.31 vs 0.35. It also created two Receiving review spaces. The saved draft has
thirteen real lines; this is not a newline-parsing false failure. Its status and
meaning remain draft/estimate. The first assertion failure prevented later
in-probe assertions; the independent audit supplies the additional duplicate and
state findings without claiming the skipped assertions passed.

Uncompressed64K completed eight responses and reached 60455 observed prompt
tokens, then failed with Prompt exceeds the native context limit. It created one
working space and no memo. The two arms took 226.19 and 254.64 seconds including
verification; these are functional observations, not latency qualification.
Both models unloaded and no native helper remained. Sources, debug binary, engine
and grammar stayed unchanged. Both workbook integrity checks pass. Independent
SQLite inspection confirms all fourteen original items and their heads, plus
inventory effects and starting balances, are unchanged in each arm.

Archive: integration/evidence/2026-10-27-active-context-first-full.json.gz,
161649 bytes, SHA-256 c76f2e3bde683d1a6f5c01cae1a3f62a8d00ee7b3325f3acea817b3dbb6e4c17;
independent findings: integration/evidence/2026-10-27-active-context-first-full-audit.json.
The wrong-root setup attempt is separately retained. No C12/C13 or automatic
compaction pass follows. Next repair is the bounded original-evidence and
completed-artifact projection described in [[records/specs/conversation-context]],
then an explicitly scoped actual-model recheck. The failed 64K reference remains
visible and must not be silently enlarged, dropped or relabeled as a pass.

## Continuation evidence repair prepared, October 27
Implemented bounded exact read evidence and completed-space identities in host
continuation state, with no citation or mutation authority added. The model policy
requires values to stay attached to their versions and titles, reuse of saved
spaces, and explicit retrieval for omitted details. Current core checks pass 73/73;
synthetic agent checks pass, including inspection of retained evidence after
repeated maintenance. Unicode with an embedded NUL and forged-text refusal are
covered. The actual-model repair replay is not yet run. Its preregistered scope
and bounds are in [[records/specs/conversation-context]].

Hosted workflow 40544819323 on 48b1a30 completed successfully. This supersedes its
in-progress status above. No new hardware dictation or visible external-copy
result is claimed; the running native preview bundle is preserved while the
manual macOS permission handoff remains pending.

## Maintained context repair and live dictation, October 27
Two real-model maintained32K repair replays on b1e6e5e pass every unchanged v1
functional assertion: twelve responses, four checkpoints, exact eight-report
associations, one space/draft, original and corrected packing values, all-source
lineage, unchanged original history/inventory, integrity, portable reopen and
successful unload. The first overlapped the approved human dictation test; an
explicit conditions addendum preserves that departure. The second ran after
recording stopped with no concurrent local build/inference. Both retain original
identities and full traces. Independent audit confirms all fourteen fixture items
match failed v1 and remain unchanged with their heads and earlier messages.
Archive: integration/evidence/2026-10-27-active-context-maintained-repair.json.gz,
191120 bytes; uncompressed SHA-256
0516b45e4a9f92171f1ed2af438b9284092db2b4e0585417dd4d5f4155d57165.
The earlier 64K failure and remaining C12/C13 cases remain unresolved.

The owner completed macOS microphone/speech permission prompts. In the packaged
0e45190 preview, real speech produced the exact requested phrase Create a receiving
report in the composer. Explicit Stop restored the Start dictation control. The
message was not sent. The driver requires on-device recognition; no audio artifact
was retained. This passes the single-phrase hardware path, not multilingual,
long-session or noisy-room qualification. Evidence with executable identity:
integration/evidence/2026-10-27-live-dictation.json. No further permission approval
is needed for this already authorized test scope.

## Background refresh and copy UI verification, October 27
The new window snapshot/session passes focused preview checks and the complete
scripts/check.sh suite on runtime sources at 7de4843. The suite retains 73 core
checks, 15 document lifecycle checks, 14 voice lifecycle checks and the native
adapter/tokenizer/grammar/agent/search/performance refusal checks. Removed unused
Bool-result warnings in the preview test harness, then rebuilt and reran that
focused suite. Native release app and CLI builds pass without warnings.

Repackaged only after confirming the prior preview process had closed. Installed
resource checks with build-tree access denied, nine missing resources, altered
Metal refusal, missing-model guidance and strict signature checks pass. Both
products load 1888 Metal functions; no baseline/Python inference symbols are
linked. The preserved baseline app is unchanged.

In the rebuilt preview, a new synthetic workbook loaded Home; the text command
open a copy displayed the native Save and Open panel and opened the chosen copy
in TextEdit. Editing/saving that copy changed its hash, while source and included
asset hashes stayed unchanged and integrity passed. A CLI-created source appeared
on Home through polling. A text-created tangent showed its own messages, returning
to main restored the original history, and close/reopen retained the saved data.
The new microphone control exposes its Local AI idle state; dictation stayed off.

Logs, exact commands, binary hashes and focused UI/audit observations are retained
in integration/evidence/2026-10-27-context-refresh-ui-verification.json.gz. These
checks do not qualify large-file rendering/memory, every synchronous editor action,
VoiceOver, all keyboard journeys or release installation.

## Native large-media qualification and release repair, October 27
The visible app was exercised with a fully written 2,148,532,224-byte, 48 kHz stereo
PCM WAV containing silence, as both an included asset and an external reference.
It is not a sparse file or a padded video. Playback and seeking to 03:03:20 within
03:06:30 passed; linked verification showed progress, Stop/Retry worked, and a
same-size one-byte external change was rejected. The included copy retained its
original hash. This initial pass exposed two failures: the linked source's generic
extraction text said File included, and a paused AVPlayer still held the WAV open
after its workbook closed. The initial result remains failed in the evidence.

PlaybackRegistry now separates pause from release. Closing an owner detaches the
AVPlayerItem even while SwiftUI retains the player. Normal viewer exit, explicit
compact-player close and replacement release media; keep-playing navigation
preserves the intended compact player. Retry/relink releases the prior preview,
and an inactive workbook cannot register a late player. Dictation only pauses,
retaining the item for explicit resumption. A real AVPlayer regression failed
before the fix and passes afterward, including isolation from another owner.

Extraction messages no longer assert inclusion. A narrow compatibility projection
also fixes the two older native unsupported/PDF-limit messages for existing books,
including retained-index failures, without changing their stored history. Other
parser messages remain unchanged. The same projection serves viewer/tool status
and pending intake. The new core check verifies both ownership modes, reopen,
unchanged revision and custom-parser preservation.

The rebuilt preview passed both large-file playback/seek paths, compact playback
while navigating, compact-player close, Stop/Retry, same-size changed-original
refusal, workbook close with keep-playing enabled, and close during active hash
verification. Native lsof checks found no fixture WAV descriptors after those
close actions. The final app process exited, and packaged CLI integrity checks
passed with both original hashes. UI status was corrected without reindexing the
old fixture. No model, build, download or dictation ran during either UI sampling.

The repaired app had 1,247 process-footprint observations and a lifetime peak of
104,399,952 bytes, about 99.56 MiB, below the declared 512 MiB ceiling. This measures
the app process, excluding shared macOS media services. It does not establish
all-codec/video/image behavior, simultaneous inference, cold-storage latency,
remote-volume hard deadlines, every retained window object's release, or wider
hardware. Keep broader J01–J10, context and production-adoption gates open.

The complete scripts/check.sh suite passes, including 74 core and 15 voice/media
checks, document/preview/search/agent/native frontend/grammar/performance evidence
checks. Native release app and CLI builds plus installed resources, missing/altered
resource refusals and signature checks pass. The preparer script also completed a
fresh independent fixture and integrity check. Reproduction is in
[[records/operations/build-and-run]]. Source hashes, both app identities, original
failures, native observations, per-sample memory, byte/handle audits and build/test
logs are preserved in integration/evidence/2026-10-27-large-media-ui-repair.json.gz.
Its uncompressed SHA256 is
9b4a8464281b6f85aaa50599780154d93303e000e6e60ddaf344b61ed9a1d126.
The repaired app executable SHA256 is
cd43caa3a6275ead7e38d3f934ed438c1ab4ae57754b6440a6d9ddec43275312.

## Isolated native extraction checkpoint, October 27

Document text/PDF/OCR/XML extraction now runs in a dedicated Swift helper shared
by desktop and CLI. The parent controls index publication and source validation;
no database or workbook lock descriptors are inherited. Two per-host parser slots,
a parent deadline, a sampled memory guard, bounded streams and an orphan watchdog
contain parser faults and allow cancellation of uncooperative synchronous work.
The helper remains alive through stdout writing so its watchdog also covers a
blocked result pipe. Missing helpers and incomplete/invalid terminal results fail
explicitly. Original bytes and any prior index survive failure and support retry.

Twelve focused checks pass in debug and optimized native release, including a
real helper whose parent dies with stdout blocked. The complete scripts/check.sh
suite passed with the first eleven checks; the twelfth descriptor-inheritance check
was added afterward and then passed in both configurations. No production code
changed after that full regression. Baseline build/install/update/uninstall and
skill/conflict checks pass. Both packaged helper layouts extract text/PDF/DOCX
with build-tree reads denied. Native resource/signature checks pass, including ten
missing-resource cases and altered-resource refusal. No Python/model runtime is
linked into the extractor.

The rebuilt native app included a text file, found MARIGOLD-427 and opened its
original with Text indexed. An intentionally invalid PDF produced Cannot read PDF;
Home retained the original with Intake needs attention, and the previous source
remained usable/searchable. Workbook verification and byte hashes pass; app quit
left no parser process. This UI check does not establish every supported format.

Q11 remains partly open: this is process fault isolation, not a security sandbox;
structured table ingestion, archives, file transcription and native viewers are
separate paths. The memory limit is sampled; source filesystem IO outside parsing
is cooperative. Concurrent maximum extraction plus inference and wider hardware
are not qualified. Native adoption and automatic compaction remain gated.

Evidence: integration/evidence/2026-10-27-isolated-extraction.json.gz, uncompressed
SHA256 e1667c89b8efa36ec8836e37d5609d86d0cba6a7045d14223a2f82ddb75f3b6d.
It retains source/binary identities, sanitized logs, package checks and UI audits.
The previous media commit's hosted CI 40557861669 passed. This extraction checkpoint
has not yet received a hosted CI result.

## Conversation and Threads refinement, October 27

Applied the owner-approved UX refinement recorded in
[[sources/notes/2026/10/conversation-threads-refinement]]. The main pane displays
Conversation. The picker groups optional discussions as Threads with descriptive
titles. Start a thread and Back to conversation have explicit text equivalents;
Let's explore this separately opens naming, while Start a thread called followed
by a title creates it directly. Chapters remain optional menu/message headings.
Persisted conversation IDs and the legacy tangent API/CLI spelling remain compatible.

Share summary with conversation opens an editable selection seeded from a completed
answer. Cancel publishes nothing. A message context menu can choose an exact earlier
exchange; an explicit text summary can also be shared without inference. The host
saves selected text and its original conversation/message reference. Sharing does
not accept records, duplicate workbook business data, expand history retrieval or
enqueue an AI turn. The shared contribution remains historical information under
the existing authority rules. CLI thread and share-summary use the same core.

Two new core checks pass for phrase/negation/title handling and summary provenance,
unchanged accepted inventory, no model run, scoped history, incomplete-message
refusal and reopen. All 76 core checks and the complete regression suite pass.
Native release builds/resources/signatures pass. A separate final packaged CLI
check verifies thread, legacy tangent, selected summary, exact provenance, no
business/model mutation and integrity. An initial test used an internal DB property
and a later app build caught catch-variable shadowing; both were corrected and the
failed build logs are retained with successful reruns.

Visible native testing verified Conversation default, text-driven named thread
creation/return, the Threads picker, summary editing/cancellation, sharing and
clicking the original exchange link. The first pass exposed duplicate command text
in main. The repaired app records those commands in their originating thread and
copies only selected findings to Conversation. A fresh fixture verifies the repair,
direct naming, return, zero inference/business mutations and workbook integrity.
The app was quit and dictation remained off throughout this UI pass. These are
synthetic seeded answers, not fresh model-quality or microphone measurements.

The screenshot review passed for the summary sheet. The accessibility tree grouped
message text and did not expose a separate provenance-link node. Link clicking
works; keyboard/VoiceOver exposure still needs explicit qualification. This does
not close all J01–J10, C12/C13, native engine parity or release gates.

Evidence: integration/evidence/2026-10-27-conversation-threads.json.gz, uncompressed
SHA256 8be5592c3c6dfdd763bf97d55563b5c2d95c54efef5ed59298894852651de16b.
It preserves before/after UI audits, exact source/app/CLI identities, failed and
passing build logs, full regression and package checks. The final CLI addition was
built and smoke-tested after the full suite; it changes no core or UI behavior.
Hosted CI for extraction e27ae39 was still running; no new hosted success is claimed.

## Conversation accessibility checkpoint, October 27

Conversation messages now remain separate accessible groups with speaker/status,
selectable rich text, exact link nodes and named assistive actions. Shared actions
also appear in each message menu and the active workbook's native Conversation
menu. Command-L focuses the composer. Recent exchanges are bounded to the twenty
most recent visible messages. Closing a workbook removes its menu actions; switching
workbooks changes the owning state. Save failures now surface instead of being
silently discarded.

One parser supplies inline and menu links. It preserves formatted Unicode labels,
item versions, locators and original-message identities, merging adjacent styling
runs and deduplicating menu destinations with a set. Unsupported application/file
schemes and malformed or ambiguous workbook routes retain their visible text but
cannot be activated. The navigation layer does not change retrieval authority or
accept business records.

Focused checks cover those invariants and 2,000 unique links. The full regression
suite passed after the message/menu changes, including 76 core, 12 extraction and
15 voice/media checks. The final set-based deduplication refinement was made after
that run, then passed focused checks, native package/resource/signature checks,
baseline build/install/update/uninstall/skill-conflict checks and another visible
native UI pass. Swift formatting checks on the three new files pass.

Synthetic native UI checks opened the exact Receiving.txt evidence and original
exchange through named accessibility and menu actions. Row-menu arrow keys plus
Return activated the original exchange; Command-L focused the composer. Native
Conversation actions followed a second workbook and became unavailable after
close. Original source hashes, messages and provenance payloads remained unchanged;
workbook integrity passed and no model turn or business mutation ran. The app was
quit, and no new microphone recording or external URL activation occurred.

Keyboard-only navigation through the application menu bar remains unqualified:
Control-F2 did not establish focus through the UI tool, which also rejects the fn
modifier. Shift-Tab remained in the text field with the current Mac preferences;
Option-Shift-Tab inserted a tab, cleared without sending. Menu activation through
accessibility worked, but that is not a spoken VoiceOver session. No system setting
was changed. Dark-mode requalification and broader J01-J10 coverage remain open.

Evidence: integration/evidence/2026-10-27-conversation-accessibility.json.gz,
12,049 compressed bytes; uncompressed SHA256
22008086456cc68188f631424c1d017ec69c6d2fd6ad010de2a286c4770ed91c.
It preserves source/binary hashes, sanitized build/check logs and explicit UI
observations and limits, not raw AX transcripts or a screenshot collection. All
recorded source and binary hashes were reverified before the documentation
checkpoint. Hosted extraction CI 40562440542 passed, superseding earlier pending
entries. Threads CI 40564561986 is still running; this checkpoint is not yet pushed.

## Structured intake isolation and persistent recovery, October 27

CSV/TSV and XLSX file parsing now use the same bounded native helper and shared
per-host worker slots as text/PDF/OCR extraction. The generic typed reply keeps
old text extraction compatible. XLSX text indexing calls its parser within the
existing helper, without recursive worker spawning. The host validates complete
structured results, rechecks original hashes and alone publishes datasets, lineage
and resumable batches. Failure keeps originals and existing searchable content.
This is fault isolation, not a security sandbox.

Bounds include 32 MB CSV input, one MB fields, 500 columns, 100,000 rows per sheet,
one million dense cell positions across all sheets and 32 MB of expanded values,
formulas and notes. Repeated shared strings and inserted blanks count. CSV parsing
checks cancellation without constructing a character array; EOF row/column limits
and quoted empty records are corrected. XLSX column arithmetic and supplied row
numbers refuse overflow or invalid ranges instead of trapping or inventing a row.
Existing shared strings, sparse rows, dates and cached formula evidence still pass.

A retained failure demonstrated that successful text indexing followed by refused
table parsing disappeared from pending intake. Structured attempts now persist
running/failed/cancelled/ready state separately. Home and CLI retain the error and
Resume action after reopen. Ready attempt identities prevent a late cancelled
parser from overwriting a newer successful import. Operational status updates are
recorded; a failed parse does not publish table rows or inferred business events.

Nineteen focused checks pass in debug and optimized native release, including
structured crashes, deadline/cancellation, invalid replies, source changes during
parsing, exact CSV boundaries, malformed encoding, dense expansion, reopen/retry
and concurrent status ownership. Shared text-worker checks retain memory, output,
descriptor, two-slot and real orphan termination coverage. The full scripts/check.sh
suite passes with 77 core checks, including XLSX coordinate/shared-string limits.
Both packaged app and CLI helper layouts pass text/PDF/DOCX and CSV/XLSX reads with
the build tree denied, preserving cached formulas. Baseline installation/update,
standalone CLI, skill conflicts and uninstall/workbook preservation pass. Native
resources, ten missing-resource refusals, altered resource refusal and signatures
pass. New production/parser sources pass strict Swift formatting checks.

The first visible package imported the synthetic CSV and XLSX through native
file-list selection. Tables displayed Copper washers, quantity 12, the multiline
note, Brass bolt A442 and saved value 12. An invalid-coordinate XLSX remained as
an original with an explicit error; both good tables stayed usable. Initial Go to
Folder automation repeatedly reset to a slash. Quit/reopen and file-list selection
completed the imports; no root cause is claimed for the path-entry failure.

The final package opens the retained wide-CSV fixture with a persisted table error
and Resume. Retry preserves that error and creates no dataset. Its original opens
with Text indexed. Close/reopen retains the pending issue, and the light-mode
layout was visually checked. Workbook integrity and original hashes pass. No model
or microphone turn ran; the app was quit and no parser process remained.

Earlier build failures are preserved: a -j4 command typo, optional dictionary
access during the status implementation, and a concurrency fixture that still had
its text extraction queued. The corrected fixture indexes its source before racing
two table attempts; the unchanged no-pending-status assertion then passes. The
initial package's missing persistent table-error result remains in the evidence.

Evidence: integration/evidence/2026-10-27-structured-intake-isolation.json.gz,
29,324 compressed bytes; uncompressed SHA256
da480fca877d81b268ab1af8cc806e44c232914f32b502451dd9351366a6f62a.
It retains 50 build/test logs, exact final source and binary identities, initial
failure receipts and native UI/audit observations. Some builds overlapped functional
checks; no speed or whole-app memory qualification is inferred. Host column inference
and row-dictionary materialization remain outside parser isolation. The new running
status marker has no dedicated host-kill test yet. Archives, file transcription,
viewers, full keyboard/VoiceOver, C12/C13 and engine adoption/release gates remain
open. No production native-engine switch or automatic compaction was enabled.

## Coherent UX consistency pass, October 27

A further owner-requested review was relayed from the design discussion and is
preserved in [[sources/notes/2026/10/ux-consistency-review]]. The ephemeral chat's
history API was unavailable; the relay is not a new human usability study. Its
requirements refine the existing plan, with no engine, storage or authority reset.

Rechecked latest code: WorkspaceState still has one shared prompt and clears the
message anchor on conversation change, so per-thread drafts/reading positions are
open. Thread creation still opens naming; Back to conversation is in menus. The
normal message window is bounded to 100 without an older-history browsing control.
The space picker remains a flat searchable list, and thread orchestration is not
exposed in the current model tool definitions. These remain implementation gaps.

The sharing observation is partly superseded: 75511b8 already added editable
selected-summary review/cancellation with exact origin payload/link, no automatic
acceptance and no model turn. 03163ed exposes its links/actions accessibly. Historical
shared messages retain their original representation and authority envelope; verify
clear original attribution in the complete journey rather than rewriting evidence.

Execute as one flow, in this order:
1. Persist scoped composer drafts and reading positions; cover switching, provenance
   jumps, delayed dictation, interruptions and reopen without draft migration.
2. Immediate provisional-title thread creation, visible identity/return, and shared
   scoped host actions for natural voice/text and native controls. Basic controls
   bypass inference; ambiguous/consequential actions retain review and honest failure.
3. Bounded older-history browsing/search and reliable return-to-latest, then complete
   Home/recent/pinned space navigation and context in focus/narrow layouts.
4. Verify scenario/proposal labeling, selected-summary attribution, explicit acceptance,
   correction and undo across the full J11 invoice/supplier journey in
   [[records/specs/product]]. Reuse passed lower-level checks and add meaningful
   ownership/navigation regressions, not a duplicate implementation-only test suite.

Keep actual observations separate from targets. J11, equivalent voice/text paths,
keyboard and narrow-window context remain open. Uncoached everyday-user usability
remains unvalidated until observed. Continue reliability, extraction, native-engine,
context and packaging work without treating the Threads label change as completion.


## Scoped composer and reading-state checkpoint, October 27

Implemented P06b/S16a in the shared core, the native conversation coordinator and
the existing SwiftUI workspace. Each conversation has versioned presentation
metadata, a 128 KB draft, at most eight saved alternatives, and an exact message
plus intra-message fraction or follow-latest state. The envelope is bounded to
1.2 MB before loading and before publication. Normal typing debounces for 600 ms;
switching, provenance navigation, close, quit and portable-copy export await the
pending writes. Neither keystrokes nor scrolling advance business revisions,
append messages or create searchable evidence. Portable snapshots preserve saved
drafts and the native copy dialog states that explicitly.

Small persistence transactions run off the UI actor with bounded process-lock
acquisition and short SQLite busy waits. Writes serialize later keystrokes before
acknowledging a flush. Compare the originally read draft before changing text.
Conflict or storage failure leaves the composer visible and blocks losing it;
Keep both preserves the other text. Restoring an alternative preserves the current
one. A full alternative list refuses another save without losing text; removing
an explicit old alternative permits the pending save. A reading-only update
preserves and exposes a newer external draft. Dictation callbacks also check
window ownership and changing-conversation state.

Native scrolling observes the clip view without replacing its keyboard/scroll
behavior. Thread changes and reopen restore the same message and fraction. Polling
loads around the reader when new messages arrive, and rejects a pending window
that no longer contains the reader's current anchor. Return to latest is explicit.
The last active conversation is a local preference for that workbook, while drafts
and positions remain in the package. Existing preview/document state is separate.

Verification:

- Final scripts/check.sh passes: 77 core, 19 extraction, 16 document checks and the
  expanded preview suite, plus the existing deterministic voice, grammar, workflow,
  search, context and integrity checks. Focused coverage includes concurrent flush
  callers and a later edit, exact Unicode, independent main/thread drafts, reopen,
  external conflict, keep-both/restore, reading-only merge, three-second busy refusal
  and retry, invalid scope/size/fraction rollback, FTS exclusion, portable roundtrip
  and recovery when eight alternatives are already retained.
- Both optimized app/CLI/helper builds and packages pass. Isolated baseline install,
  update, unrelated-file refusal, skill install and uninstall preserve the workbook.
  Native installed resource/signature and document/table extraction checks pass
  with build-tree reads denied. The final export-dialog-only change was rebuilt,
  repackaged, checked for resources and observed in the native app after the full
  suite; it did not change the core or extraction helper.
- The visible native fixture returned to the exact unsent main draft and scrollbar
  0.7472084724300679 after a thread roundtrip. It restored exchange 21 through a
  message action and a real pointer click on the inline link. Return to latest
  reached scrollbar 1 without clearing text. Immediate Command-W and Command-Q
  after edits retained the exact drafts; reopen restored the last thread or main
  and saved reading position. The final build remained on exchange 21 after 120
  new synthetic messages, rather than switching to the latest 100.
- An external synthetic writer and local editor produced different drafts. The
  native close was refused with the local text visible; Keep both retained the
  external text, and Restore to composer preserved the preceding local text as an
  alternative. Final SQLite audit found both drafts, 167 fixture messages exactly
  as inserted by the fixture, and integrity ok. None of the composer text was sent.
  The portable-copy disclosure was visible; Cancel retained the draft, and the app
  quit cleanly. No microphone or model request ran during this checkpoint.

Retained failures and limits: the first new async assertions used the synchronous
require autoclosure and failed compilation; corrected explicit Boolean assertions
pass. An initially malformed synthetic link was ignored, then a separate correctly
formed link was added. An accessibility-tool link click produced no navigation;
native menu and screenshot-based pointer clicks worked. This is not evidence of
spoken VoiceOver or uncoached usability. A hard kill can lose the last debounce
interval; no new forced-kill or physical disk-full test was run. OS writes/fsync
can outlast the lock deadline. Older-history paging/search controls, immediate
thread creation, ordinary-language recovery, complete keyboard/VoiceOver and J11
remain open. Engine parity, compaction, broader memory/hardware and release gates
are unchanged.

Evidence: [conversation-state verification](../../../integration/evidence/2026-10-27-conversation-state.json.gz),
30 retained logs, source/binary identities and synthetic UI/SQLite observations.
Uncompressed SHA-256:
`e55a79c6337995908c2ce0bf76a7866a36f620e11b2f9fefa83354fc6df05eb3`.


## Immediate thread and bounded history checkpoint, October 27

Implemented P07b/P06c in core, native UI and CLI. Starting a thread flushes the
current draft, creates a provisional plain-text title and selects the empty thread
without a naming sheet. The exact parent supplies context. Explicit rename uses a
compare against the title originally shown, refusing a concurrent rename. Start and
rename use mutation tokens for safe retries. Main cannot be renamed. The thread
picker, title and visible Back to conversation remain beside the composer in focus
mode. Legacy CLI aliases retain compatibility; start-thread and rename-thread are
available in both packaged CLIs.

Workspace snapshots now use conversation-local keysets, not a global row-id window.
Each contiguous visible window contains at most 100 messages and 2 MiB of bodies,
including its exact anchor. Sibling messages/tool receipts cannot displace it.
Earlier/later windows overlap so the reading observer preserves the user's place.
Search uses existing FTS, 20 snippets per page, scoped visible roles, a bounded
previous-cursor trail, background reads and a three-second lock/SQL budget. Query,
conversation and close identities reject stale publication. A failed page keeps the
previous results and retry cursor. Opening a match saves the draft and navigates to
the original; it does not send text or grant action authority.

Verification:

- scripts/check.sh passes: 79 core, 19 extraction, 16 document checks, the expanded
  preview suite and the existing voice, search, context, grammar, agent and workflow
  checks. Focused tests cover interleaved sibling/tool messages, complete earlier
  and later traversal, a large-body contiguous window, cancellation, scoped cursor
  refusal, duplicate-title disambiguation, idempotency, stale rename and reopen.
  Async search tests cover late results after query/scope/close, bounded replacement,
  previous-page restoration and failed next-page retry.
- Both optimized app/CLI/helper packages build. Baseline isolated install, update,
  skill installation, unrelated-file refusal and uninstall pass. Native resource,
  signature and installed extraction checks pass with build-tree reads denied.
  The final app-only timestamp display change was rebuilt, packaged and visually
  inspected after the suite; core and helper binaries were unchanged.
- Native UI opened a copied 167-message fixture. Start from exchange 21 opened an
  empty thread immediately, then rename to Delivery dates preserved its unsent
  draft. Focus mode retained title, return and composer. Back restored the exact
  main draft. Command-Option-F supplier search paged from exchange 45 to 25 and
  back. Search for Exchange 03 opened that exact original at the top of the view.
- Later/earlier controls made the adjoining messages available while retaining the
  visible boundary position. Return to latest reached scrollbar 1. Thread search
  excluded all main supplier matches. Quit/reopen restored Delivery dates and its
  draft, then main's saved draft/reading anchor. Final search showed a localized
  date. App quit with dictation off and no text sent.
- Independent SQLite and packaged-CLI audit confirms the original 167 messages
  and item rows are byte-for-byte equivalent at the value level, the new thread's
  parent is exactly exchange 21, both drafts are intact, and integrity passes.
  Both packaged CLI variants create/rename a thread without changing messages.

Retained failure: the first preview test compile inherited MainActor isolation in
an inline fixture helper; moving the stateless helper to file scope fixed it. UI
observations are agent-operated synthetic checks, not spoken VoiceOver or uncoached
usability. Generic mutation locking is still unbounded for thread writes; draft
flush and reads have deadlines. No new model, microphone, engine parity or context
qualification ran. Builds overlapped functional checks, so no speed or whole-app
memory claim follows. Ordinary-language actions, Home/recent/pinned organization,
J11 and the engine/context/distribution gates remain open.

Evidence: [conversation-navigation verification](../../../integration/evidence/2026-10-27-conversation-navigation.json.gz),
19 retained logs, source/binary identities and synthetic UI/SQLite/CLI observations.
Uncompressed SHA-256: `b8e15f5e301b189268d345a179a593870544f69298bee5a2775c2a3c95632e85`.

## Scoped natural-language conversation actions checkpoint, October 27

Implemented A12 across the shared agent, both inference adapters, native window
and CLI result. Ordinary submitted text or dictation can request a new discussion,
rename the current thread, return to main, or prepare findings for review. The
host supplies the live request/conversation and available actions. Dynamic schemas
preserve these capabilities through reference annotation/context reconstruction.
Unavailable targets require clarification; creating a new discussion must not
substitute for renaming another one. This is capability enforcement, not complete
semantic intent verification.

Core source selection keeps an exact completed exchange from the current thread;
siblings, inherited parent messages and later messages are refused. Default branch
selection includes the latest answer. Start/rename use the existing idempotent
operations with three-second lock/SQL budgets and cancellation. Rename checks the
original title and refuses a redundant rename. Successful actions end the turn
with a host-owned result; model-authored success claims are not published. The CLI
returns a typed result without claiming a native window switched.

Native result delivery checks the originating workbook, window, operation,
conversation and navigation generation. Leaving and returning cannot reauthorize
late navigation. Summary lookup has the same generation guard. All summary paths,
including the literal command with supplied text, now open review before sharing.
Default summary selection skips control acknowledgments. Editing or cancelling
review does not publish; explicit share preserves the exact original exchange.

Verification:

- The complete scripts/check.sh passes: 79 core checks, 19 extraction checks,
  16 document lifecycle checks, 15 synthetic voice lifecycle checks, existing
  preview/search/context/workflow checks, and 29 actual-tool grammars with 257
  exact reference masks. Added checks cover terminal action results, scope,
  cancellation, read-only refusal, exact parents, review without publication,
  bounded thread-write locks, and native capability masks with reasoning on/off.
- The unchanged eight-case native 32K/bounded512 cohort passes on replay v3:
  branch, Spanish rename, return, review, hypothetical explanation, negation,
  ambiguous other-thread rename, and an instruction embedded in a document.
  Branch/rename/return/review each use one model step. Negation and ambiguity
  each finish in one; imported-instruction handling takes three. The explanation
  case takes six and includes unrelated datasets and calculate(0) calls, so
  stopping efficiency remains unresolved despite its functional pass.
- Both optimized app/CLI/helper packages build. Preserved-baseline installation,
  update, standalone CLI, skill/conflict handling and uninstall pass. Native
  resources, signature, setup refusals and installed extraction pass with
  build-tree access denied. Engine and grammar pins are unchanged.
- The final native package opens a copied synthetic cohort workbook. A literal
  supplied summary opens editable review; Cancel leaves main unchanged. An ordinary
  review request opens the same sheet with the Friday estimate and no-order
  uncertainty intact. An explicit edited share adds exactly that text to main
  with a link to its original exchange.
- Ordinary language creates/selects Delivery options, Spanish renames it Entregas,
  and a separate unsent draft survives rename and navigation away/back. A natural
  return request selects main without adding a main message. The preview quits
  with dictation off. These are agent-operated synthetic UI checks, not uncoached
  use or new speech-recognition evidence.
- Independent SQLite audit checks all 24 cohort workbooks, identical protocol
  hashes, unchanged original source and exchanges, integrity and foreign keys.
  The UI copy preserves all original messages. Its main has four visible
  messages plus one tool receipt and exactly one explicitly shared summary.

Retained failures: v1 chose an earlier branch parent, attempted a redundant rename
for a stay-put request, and attempted invalid renames for an ambiguous target.
v2 incorrectly created threads for review and ambiguous rename requests. Clearer
action semantics and unavailable-target guidance pass the same v3 cases; no test
assertions were weakened. The first read-only synthetic phrase failure, first
misplaced UI result handler, stale fixture/export command result, and an audit
that initially counted a tool receipt as a visible message are retained as limits
or corrected findings. Final suite and package checks pass after corrections.

Evidence: [conversation-action verification](../../../integration/evidence/2026-10-27-conversation-actions.json.gz),
73,422 compressed bytes, 34 logs, three complete cohort exports, final source/binary
identities and native UI observations. Uncompressed SHA-256:
`ed00fb48d8cdc77d887417d8754632a990b25212cec13110a583b9332449946f`.
Probe executable hashes were not captured before each cohort; final agent-check
binary identity includes added capability-mask tests. Do not use these functional
runs to claim native/reference parity or speed.

Remaining: remove irrelevant calls in explanation-only requests; qualify compound
branch-plus-work behavior and delayed live results after navigation; complete
Home/recent/pinned organization, keyboard/VoiceOver and uncoached J11 journeys.
Native engine parity/adoption, automatic-compaction C12/C13, whole-app memory,
wider hardware and public release gates remain open. The approved human dictation
phrase was already verified unsent in the earlier live-dictation checkpoint; it
was not recorded again during this work.

## Conceptual guidance and distinct conversation tools, October 27

The six-step explanation in the prior checkpoint was caused by a host false
positive, not initially by unnecessary model exploration. The first answer was
already an interface explanation. The broad word match for difference rejected
it three times and demanded a calculation. The model then called datasets and
calculate(0), which satisfied that guard without helping answer the question.

The comparison backstop now distinguishes explicit numeric-difference statements
from the ordinary conceptual word. It retains cost/percentage checks and existing
numeric, citation, input and currency validation. It cannot consume a numbered
Markdown item after a conceptual heading as the difference value. This remains a
narrow language backstop, not complete arithmetic or semantic verification.

The model now receives verified product definitions: separate thread histories
with an explicit parent excerpt, one shared workbook, original Sources and derived
Records, and category independent of meaning/status. Accepted changes through a
thread affect the shared workbook. Tool receipts are not automatically business
Sources; calculations can feed Record transformations with original inputs without
an extra Source for each receipt. Explain-only/leave-unchanged clauses join the
additional denial rules, including semicolon-separated instructions. Read tools
are permitted when needed, not mandatory for conceptual guidance.

A later replay still created a thread for an ambiguous rename through the combined
action enum. Replaced that model-visible interface with four specific functions:
start_thread, rename_current_thread, return_to_main and review_thread_summary.
Each has only its own arguments, is filtered by the host capability set, and uses
the existing scoped core/result path. Named tools cannot override their action.
The old conversation_action host alias and historical receipts remain compatible.
Negative-case assertions now recognize all four names and the alias; no original
request, step bound or behavioral assertion was weakened.

Verification:

- Final guidance cohort v4 passes all five unchanged requests: thread differences,
  Source/Record definitions and shared-data safety each finish in one step with
  no tool receipts or mutations. Supplied-price subtraction takes two steps;
  stored Birch/Cedar quotes take six, reading both originals, calculating 2.40,
  identifying Cedar and citing both versions. Semantic review checks the actual
  answers separately from structural assertions.
- Final conversation replay v5 passes all eight original requests. Branch,
  Spanish rename, return, review, hypothetical explanation, negation and ambiguous
  other-thread rename each take one step. Imported-document instructions remain
  ignored; the correct source label is cited in four steps. The ambiguous case
  has no conversation action attempt and creates no thread.
- Added synthetic checks prove conceptual/list wording finishes without a dummy
  calculation while an uncomputed numeric price difference is refused through
  all four finish candidates. A proposal made through thread tools leaves actual
  stock at 20 until explicit acceptance; then main and thread both read 18.
  A calculated Record uses original input lineage without an extra Source.
- Full scripts/check.sh passes: 79 core, 19 extraction, 16 document and 15
  synthetic voice lifecycle checks, plus agent/context/search/preview/workflow
  checks. The 27-tool schema passes 32 actual grammar cases and 268 exact pinned
  reference masks. Dynamic main/thread/read-only capabilities remain tested.
- Both optimized packages build. Baseline install/update/standalone CLI/skill
  conflict/uninstall checks pass. Native signature, resource-damage/setup refusals
  and extraction checks pass with build-tree access denied. The final test-driver
  usage change was rebuilt and its synthetic checks rerun after the full suite.
- The final packaged native CLI answers the shared-inventory question in one
  step, correctly explaining the common data. Independent SQLite audit finds
  no tool receipts, extra conversation or business item, and integrity passes.
  No new GUI or microphone test ran; native window behavior was checked in the
  previous checkpoint and the result shape remains unchanged.
- Independent audit covers 20 guidance and 16 conversation fixture workbooks:
  original quote/note inputs remain unchanged, integrity/foreign keys pass, and
  each cohort keeps its unchanged preregistered protocol. The separate packaged
  CLI workbook also verifies cleanly.

Retain all failed evidence: guidance v1's structural pass did not qualify its
unsupported sender/tool-output claims. v2 misread a numbered list and created a
thread during an explain-without-changes request. v3's structurally passing
Source/Record answer invented an extra capture step. Conversation replay v4 still
created a thread for an ambiguous rename. Final v4 guidance/v5 conversation pass
without discarding those traces. Some explanations remain longer than requested;
these samples do not prove universal intent accuracy or complete prose validation.

Reproduce the live cohorts after native setup/build with the agent-check executable:
use --interface-guidance or --conversation-actions, followed by MODELS_ROOT,
PINNED_NATIVE_LIBRARY, ENGINE and a new output directory. The driver refuses to
overwrite an existing cohort. Guidance saves binary/engine/grammar identities before
running. The conversation v5 run followed guidance v4 in the same command without
an intervening rebuild. Python is used only to regenerate pinned reference grammar
fixtures; product inference remains native.

Evidence: [interface-guidance verification](../../../integration/evidence/2026-10-27-interface-guidance.json.gz),
92,483 compressed bytes, 25 logs, all six cohort exports, semantic audits and final
package identities. Uncompressed SHA-256:
`193fbc447a82cac13c88575bb07e2056de03680228cb17293ca5aea9a5d10e19`.

Next remains compound branch-plus-work execution and delayed-result navigation
qualification, followed by the remaining workbook Home/spaces and uncoached
journeys. Native/reference parity and production adoption, automatic-compaction
C12/C13, whole-app memory, wider hardware and public release gates remain open.
This checkpoint changes neither the engine pins nor the adoption decision.

## Inline-reference design adoption, October 27

Preserved Carlos's adoption instruction in
[[sources/notes/2026/10/inline-references-adoption]] and added
[[records/specs/references-and-relationships]]. Storage S18, search Q17, product
P17, distribution D11, reading map and design review now reference that contract.
Pending: canonical bindings/resolution, deterministic parsing, indexes/backlinks,
native/voice/text/CLI operations, bounded agent traversal and LJ01-LJ10 checks.
Optional inferred associations require separate evaluation. This checkpoint changes
no runtime code or active engine work. The main agent owns delivery and the pointer
from its concurrently edited intelligence specification.


## Compound thread requests, October 27: qualification in progress

Implemented a single live handoff from a compound branch-and-work request into
its new thread. The host preserves the exact submission and original request
Source, records a carried-message payload and linked child run, marks the parent
continued, and retains one lease, cancellation control and twelve-response budget.
The requested additional task must be quoted from the current submission. The
compound action inherits the latest exchange; standalone branching retains its
explicit earlier-message selection. Child capabilities admit read/calculation tools
plus finish and, when selected for requested work, exactly one named write tool.
Attempted earlier changes prevent a handoff. Earlier read-only calls are allowed;
repeating them remains within the total budget. Restart never resumes unfinished
work, and original inputs are not rewritten.

Synthetic checks pass cancellation before/after handoff, exact request and one
Source, idempotent replay without execution, original/child history separation,
invalid task correction, prior-change refusal, repeated-handoff refusal, shared
step limits, unfinished reopen and independent movement-request lineage. Native
fixtures now cover 28 tools, 33 grammars and 283 exact masks. A malformed new XML
fixture omitted required parameter newlines; the corrected fixture passes. One
early history-isolation fixture put its sentinel inside the intentionally inherited
excerpt; it was corrected to put it outside. Neither is product qualification.

Keep every failed actual-model cohort:

- v1: supplied-price continuation repeatedly searched prior history; quote
  comparison proposed an unrequested table; inventory work ended at creation.
- v2: improved continuation prompting fixed stored quote comparison, but supplied
  arithmetic still tried a view/table; inventory branching happened after reads
  and was refused by the initial first-call-only rule; branch-only inferred work.
- v3: exact task quotation and capability limits fixed branch-only and arithmetic.
  The abstract proposal category was still misclassified as answer, and the model
  selected an unintended earlier message. The inventory fixture now explicitly
  says the units left stock for a sale; the earlier handover wording was ambiguous.
- v4: exact named write-tool selection and latest-exchange inheritance completed
  all requested model operations, but the inventory acceptance check caught a real
  core omission: movement lineage kept its observation but omitted the captured
  user request. The movement API now preserves that host request alongside the
  observation, without changing legacy idempotency arguments when no request is
  supplied. It remains draft; no accepted inventory effect occurs.

v5 is running against that lineage fix, followed by the unchanged conversation
and interface-guidance cohorts. Builds, package installation and visible UI checks
will be recorded below before this checkpoint is accepted. Quote cases can consume
the full twelve responses because evidence is read on both sides of the handoff;
this is functional qualification work, not a latency or production-adoption claim.

The adopted reference/backlink requirements from 00662f6 are linked from intelligence
A14 to [[records/specs/references-and-relationships]]. Their implementation remains
pending and does not replace the open Splash, context, accessibility or release gates.


### Compound request checkpoint results

Final v5 passes all five fixed cases: supplied arithmetic 3 responses, stored
quote comparison 12, proposed inventory movement 6, branch-only 1 and hypothetical
question 1. The movement is draft with quantity -2, exact observation and original
request lineage, and accepted stock still 20. Its changed observation wording
was frozen in protocol v2 before v3; the final v4/v5 prompts and fixture are the
same. v4 remains a failed lineage check, not a reported pass. All eight unchanged
conversation cases pass (the first seven in one response; imported instruction
in four). All five unchanged guidance cases pass in 1, 1, 1, 2 and 6 responses.
Answers were reviewed for the Source/Record distinction, shared workbook effects,
price difference, exact citations and no invented currency. Explanations remain
more verbose than desired; structural checks alone do not prove semantic quality.

Independent SQLite audit confirms exact carried request/source bytes, preserved
original heads, no unresolved prepared calls, foreign keys and integrity across
all eighteen successful fixtures. The final debug executable matches the recorded
v5 and guidance executable identities. No engine revision or model changed.

Commands completed successfully:

- ./scripts/check.sh, including 79 core checks, extraction, documents, preview,
  voice lifecycle, history/context, agent and grammar suites, db.md and link gates.
- ./scripts/build.sh and python3 scripts/check_install.py: optimized baseline,
  isolated install/update, standalone CLI, skill conflict and recoverable uninstall.
- Native release builds of SevraDesktop, sevra and sevra-extract with
  SEVRA_NATIVE_CANDIDATE=1, then scripts/package_native.py,
  scripts/check_native_package.py and scripts/check_extraction_package.py.
  Resource/signature, ten missing-resource refusals, altered-resource refusal and
  extraction with build-tree reads denied pass; no Python runtime is introduced.
- Packaged output/native/bin/sevra created a fresh workbook and fulfilled a request
  to start CLI calculation and compute 20 minus 8. It answered 12 in three responses,
  returned its typed created-thread result, stored one request Source and zero
  business Records, and passed verify. The parent is continued; its child complete.

The Mac was locked when the UI tool tried opening the rebuilt preview. The tool
refused before app launch; no preview process was running afterward. An unlock
request is pending. Do not report automatic navigation or away-and-back late-result
behavior as visually qualified by this checkpoint. Dictation was not restarted;
the earlier approved human phrase remains the existing hardware evidence.

Evidence: integration/evidence/2026-10-27-request-handoff.json.gz, 275207 bytes,
uncompressed SHA-256
0da6a352328048cb471464366174d2b5ff5128788a7ad58b63f1e45a2ea68f9a.
It preserves seven cohorts, 38 synthetic workbook exports, the packaged CLI audit,
47 logs and source/executable identities. Diagnostic model reasoning is retained
only for these synthetic tests; product workbooks do not save it. a0ced3a hosted
CI completed successfully; this new checkpoint's hosted CI is not yet qualified.

Next: finish the two native navigation checks after unlock, reduce duplicate
read-only work across the handoff, then continue the outstanding plan. No native
adoption, automatic compaction, 100-150 tokens/s all-device claim, full accessibility
qualification or public-release completion is established here. The new explicit
reference/backlink specification remains adopted work to implement, not a completed
feature.


## Same-request evidence handoff, October 27

The previous fixed stored-quote run used all twelve responses: search both quotes,
read both originals, calculate, create the thread, then repeat all five evidence
steps before finishing. A13 now specifies exact same-request read/calculation
carry with receipt verification, changed-head refusal, eight-entry/32,000-byte
bounds, and no additional history access. Development implementation is under
qualification. The five-case native cohort is running; do not treat this entry
as a passing result. No model, engine, tool schema or production default changed.


### Retained packaged counterexample and targeted correction

The first packaged check used a fresh workbook and explicitly asked to read and
calculate before creating a thread and reporting the answer there. It completed
the reads/calculation, then selected terminal start_thread and discarded the
requested answer. Preserve `.build/handoff-evidence-packaged.sevra` and its trace;
this check failed. The fixed five-case cohort did not cover that ordering.

The next revision clarifies that delivering the requested answer is remaining
work even when calculation is already complete, adds the exact failed prompt to
the fixed cohort, and clarifies that shared workbook data still permits a separate
thread discussion/analysis. Protocol v4 has six cases. The exact packaged prompt
will be checked again on a fresh workbook after the targeted change; no passing
result is claimed here yet.


### Same-request evidence checkpoint results

The final protocol-v4 cohort passes all six cases: supplied arithmetic (3 responses),
stored quotes (7), review-only inventory proposal (4), explicit read/calculate-first
then branch/report (8), branch-only (1), and hypothetical explanation (1). Original
quotes remain unchanged; the movement stays draft with observation/request lineage;
accepted stock remains 20; all workbooks verify. The quote result includes both
originals and the deterministic 2.40 difference. The reporting case requires both
reads and calculation before branching, then requires child proof or exact carried
receipts. The child finishes directly from that proof. The seven-versus-twelve
comparison uses the same prompt/fixture with fresh IDs, not a controlled latency
measurement or universal reliability claim.

All eight unchanged conversation-action and five unchanged interface-guidance
cases pass on the final code. Branch/rename/return/review, negation, hypothetical
intent, ambiguity and imported instructions keep their boundaries. Manual review
confirms that the revised explanation distinguishes separate conversation/analysis
from shared business data. Explanations can still be verbose and expose internal
tool names; language polish remains open. The ambiguity case takes two responses;
most other direct actions take one.

The exact failed packaged request was rerun after the targeted prompt/tool
clarification and added regression. The rebuilt native CLI completes in eight
responses, retains three reads and a calculation, reports Cedar's lower cost with
both original citations, creates no business Record, preserves one request Source
and passes workbook integrity. The failed predecessor and its binary hash remain
in the evidence archive. No success is attributed to that predecessor.

Final verification:

- `./scripts/check.sh`: full local suite passes. New checks cover exact proof reuse,
  history/prose/reasoning exclusion, changed heads, projected/failed reads,
  byte/count limits, replay, reopen and later-history bounds.
- `./scripts/build.sh` and `python3 scripts/check_install.py`: baseline release,
  isolated install/update, standalone CLI, skill conflict and safe uninstall pass.
- Native release app/CLI rebuild, `scripts/package_native.py`,
  `scripts/check_native_package.py`, and `scripts/check_extraction_package.py` pass.
  Signatures/resources, ten missing-resource refusals, altered resources, absence
  of baseline/Python/MLX runtime symbols, and packaged extraction remain checked.
- Handoff/guidance execution hashes match the final debug binary. Conversation
  regression ran between them with the same executable; its existing harness does
  not emit a separate execution-hash file.
- No new GUI or microphone check was performed while the Mac remained locked.
  Keep the existing verified dictation evidence and pending navigation checks.

Evidence: `integration/evidence/2026-10-27-handoff-evidence.json.gz`, 153775 bytes;
uncompressed SHA-256 `be2d2e1b4be2b26f1c6d980d3d867d6e277a0733c3578994a3be3fcf23d0565f`.
It preserves four cohorts, 24 synthetic workbook exports, failed/corrected packaged
cases, 23 logs and source/binary hashes. Earlier archives are unchanged. Product
workbooks do not persist reasoning; only synthetic qualification traces do.

Next: finish normal/away-and-back native navigation checks after the pending unlock;
polish concise user-facing language and unnecessary request-Source reads; continue
references/backlinks and the remaining product, accessibility, context, engine and
release gates. Baseline/native selection, model revision, engine pin and disabled
automatic-compaction default are unchanged.

## Conversation language and unlocked native checks, October 27
The owner unlocked the Mac, resolving the pending navigation check. On the built
e1c9b49 native preview, a request to create UI automatic and calculate 9 minus 2
opened the new thread and answered 7. During a second compound request, switching
to UI automatic and back to Conversation kept Conversation and Home visible after
the late result. UI receiving contained the requested draft movement, with the
original request and Handover note linked; accepted inventory was still 20.
Normal navigation and the away-and-back generation boundary now have native UI
proof. No microphone recording was started in this check.

The next build separates host request metadata from submitted text, clarifies
ordinary voice/text explanations, and removes internal routing fields and
redundant movement meaning/status from the default detail view. The original
request remains exact and is automatically retained in proposal lineage. New
synthetic checks cover ordinary requests and typed child continuations without
rereading the already visible Source. Existing missing-external-evidence checks
still refuse treating that Source as proof of a document being sought.

The first expanded prompt failed the existing synthetic running-compaction check
with context_limit. The fix condensed repeated conversation policy by 977
characters. It did not increase the context budget or relax refusal tests. The
corrected synthetic suite passes, including repeated active compaction.

All ten actual native interface-guidance v2 cases pass: seven explanation cases
in one response each, a draft estimate forecast in one, supplied arithmetic in two,
and cited stored quotes in six. Fixed simple answers are 57-92 words, with no
internal function names, headings or lists. Spanish stays Spanish; the technical
answer distinguishes the two branch tools. The detailed answer keeps an accepted
forecast an estimate. Its phrase "validated estimate" is not an independent
accuracy claim or proof that acceptance validates a forecast. Broader language
and semantic reliability remain open. No case rereads its current request Source.

On the rebuilt app, the same thread-help question answered in three plain sentences
(56 words), one response and zero tool calls, without creating a thread. A normal
pointer click and the named accessible Open action both opened the proposal.
Details showed one authoritative Record/Actual/Draft header, business fields and
named lineage, with no raw request ID. The original User request opened intact
without internal conversation/message IDs. Accept changed stock to 18 and showed
Accepted; Undo restored 20 and showed Rejected. Both exact versions/history and
workbook integrity were preserved, as confirmed independently through the CLI.

Two remaining UI findings are explicit in [[records/specs/product]]: the original
chat proposal retains its historical Needs your review badge, and request context
shows a technical Active space ID line. Do not mark these presentation fixes done.
The complete ordinary-language/keyboard/VoiceOver journeys also remain open.

The six-case compound-request and eight-case conversation-action regressions are
running against the revised prompt. Their final outcome, package/full-suite
checks and immutable evidence archive will be recorded before committing this
checkpoint. Engine pin, model revisions, preserved baseline and disabled automatic
compaction defaults are unchanged.

### Retained continuation-progress failure and correction
The first revised six-case handoff cohort passed five cases but failed the exact
read/calculate-first then branch/report case. The child could see the completed
quote reads and calculation, but saw no completed creation call after them. It
repeated history searches while reasoning that thread creation was still pending,
and exhausted the shared twelve-response budget. Only one thread was created;
the host correctly refused repeated branching. The answer was not delivered.
Preserve the failed workbook, trace, protocol and binary hash. No budget was raised.

The correction carries the exact completed creation call/result as an in-memory
progress pair after the qualified business evidence, with empty assistant prose
and reasoning. It does not execute that action again or give its result business
citation authority. New synthetic assertions verify the real created conversation,
paired call identity, unchanged user request, no additional durable tool receipt,
unchanged scope and later-history exclusion. The full synthetic suite passes.
The exact report-prices case now passes in seven responses: two searches, both
original reads, deterministic calculation, the completed creation, and a cited
finish in its child. The earlier failed run remains retained. The remaining fixed
handoff/conversation/guidance cases and package checks are still running; their
results will be recorded separately.

The second fixed cohort passes the corrected report case, supplied arithmetic,
stored quotes, proposed movement and hypothetical explanation. Branch-only still
fails its one-response UX gate: it attempted a compound call using the whole
branching instruction as its task. The host rejected that before creation, and
the model corrected to one ordinary new thread on response two. No follow-up work
or duplicate thread occurred. The original failure wording overstated this as
continued work; the check now reports an unnecessary extra response separately
without weakening the same conditions. The next prompt restores the explicit
rule that taking a discussion into a named thread supplies no additional task.
The third fixed cohort and unchanged regressions are running. Preserve both
failed cohorts; do not infer whole-model reliability from the corrected examples.

### Manual meaning review caught an overstatement
The third handoff cohort passes all six cases (3, 7, 4, 7, 1 and 1 responses),
and all eight conversation-action cases pass. The ten interface-guidance cases
also pass their automated checks, but manual semantic review refuses overall
qualification of the detailed-meaning answer: it describes acceptance as proving
reliability and rejection as meaning incorrect/invalid. A draft Source was also
portrayed as unavailable for calculations. Those claims exceed the actual model.
The earlier answer's "validated estimate" wording also deserved stronger correction.

The full package/check sequence was deliberately stopped during the local suite
before rebuilding release packages, so it is not a passing final check. Its log
is retained as conversation-language-full-check-interrupted-for-meaning.log.
The prompt now states the workflow/accuracy distinction, draft exploration,
withdrawal/nonselection and independent Record review explicitly. Protocol v3
adds an eleventh direct acceptance-boundaries question, retaining every earlier
prompt and limit. The eleven guidance, six handoff and eight action cases are
running on that revision. Automated output and manual semantic approval remain
separate; no test bounds or model budgets were relaxed.

The first acceptance-policy addition again exceeded the original synthetic
running-compaction budget. No actual-model v4 run had started. Keep the failed
v5 synthetic log. The revised text removes 521 duplicated characters from the
interface-facts and conceptual-help paragraphs, preserving the product facts and
new acceptance distinctions. It does not alter context size, compaction thresholds
or refusal tests. The next synthetic suite and model cohorts use that revision.

## Verification course correction, October 27
Carlos explicitly approved "Okay course correct" after reviewing a proposal to
reduce verification to the minimum checks that demonstrate the changed behavior.
The approved direction was delivered to this active implementation conversation;
this repo owns the durable update. [[records/specs/distribution]] now defines the
focused verification policy, and AGENTS.md points future work to it.

Applied immediately: the shell orchestrating the broad command chain was stopped
without signaling its already-running handoff check. Let that bounded in-flight
check finish its workbook transactions, then terminate only the stopped shell so
it cannot start the queued conversation-action cohort. No new package, install,
baseline/native rebuild, extraction or full-suite run is justified by the final
acceptance wording change. The earlier interrupted full-suite log is preserved.

Focused evidence already obtained: the exact detailed-meaning question now
separates approval from truth, keeps an accepted forecast an estimate, and does
not make it actual inventory. The direct acceptance-boundaries contrast also
allows draft exploration and says rejection need not mean false. Both used one
response with no action. The existing running-compaction/context checks pass at
the original budget. This fixes the observed acceptance-versus-accuracy issue;
it does not establish general model truthfulness.

The detailed answer's illustrative Source/plan versus derived-forecast example
can still be clearer. This non-blocking wording limitation is retained, not a
reason for another prompt/requalification loop. Automated passes and manual
semantic review remain separate. No business data, lineage, acceptance or Undo
assertion was relaxed. Close this focused checkpoint, then implement the concrete
native chat proposal-status and request-context presentation issues, followed by
the remaining product plan. The app goal remains active.

### Focused conversation checkpoint results
The final focused acceptance check uses the exact detailed-meaning prompt that
previously overstated reliability and one direct acceptance-boundaries contrast.
Both finish in one response without actions. Manual review confirms that approval
is not proof of truth, estimates stay estimates, draft exploration remains
available, and rejection need not mean false. The detailed Source/plan example
could be clearer; this is a retained non-blocking wording limit, not a claim of
universal semantic reliability.

The existing deterministic agent suite passes on the final code, including the
original context-budget/running-compaction regression, unchanged current-request
and missing-external-evidence boundaries, exact handoff, lineage and arithmetic
checks. The final guided model cohort had already completed eleven automated
cases before the course correction. Earlier corrected handoff/action cohorts are
retained as reusable evidence; they are not prerequisites to repeat after every
wording adjustment.

At the course correction, the next handoff cohort was already running. Its six
cases finished with 3, 7, 4, 9, 1 and 1 responses, all passing existing checks.
The report case made extra searches, so do not generalize the earlier seven-step
result. The orchestration shell alone was stopped while its child completed,
then terminated after the child exited. No workbook transaction was interrupted.
The intentional shell exit 137 is not an app/model crash. The queued final action
cohort never started. Final package/install, both-backend rebuild, extraction and
full-suite reruns were skipped; the earlier full-suite interruption is retained.
No unperformed gate is marked passed. Release and native-adoption gates remain.

Native observations apply to their recorded executables: e1c9b49 for normal and
away-and-back navigation, and the interim language/viewer build for help, proposal
navigation, acceptance and Undo. No new microphone session occurred. Those GUI
mechanisms were not changed by the final acceptance wording fix. The final source
is committed; release binaries are not claimed to contain that last wording yet.

Evidence: integration/evidence/2026-10-27-conversation-language.json.gz,
320792 bytes; uncompressed SHA-256
7ef9402dba09a2418e046908456e4fe87183276aa4991919173b6bfc9a79930c.
It retains eight cohorts, 63 synthetic workbook exports, two failed handoff runs,
failed/interrupted checks, separate manual review, native UI observations, 27 logs
and source/binary identities. Earlier archives remain unchanged. Product history
does not save model reasoning; these synthetic qualification traces may contain it.

Final small checks: Swift formatting, repository links, full db.md validation and
Git whitespace review. Commit/push this focused checkpoint, then resume the native
proposal-status/context-label slice under the focused policy. The overall app
objective stays active.

## Current proposal status and readable request context, October 27
Closed the two concrete native presentation findings under the focused
verification policy. Current proposal status comes from the coherent background
snapshot, with exact typed receipt metadata for new messages and a conservative
same-conversation legacy fallback. Current badges navigate to current versions;
original receipt text, state and links remain immutable. Captured request context
now names the location and preserves selected text, with an original-context
disclosure and verbatim fallback for unfamiliar formats.

Verification: `swift build --product sevra-preview-checks -j 4` and its runner,
then `swift build --product sevra-agent-checks -j 4` and its runner passed. New
checks exercise acceptance, Undo, newer draft/reopen, actual shared-agent metadata,
foreign/unknown associations and ID-like selected text. Rebuilt native release app
and CLI and packaged the preview for one interaction pass. A copy of the previous
synthetic receiving fixture showed withdrawn version 3 -> accepted version 4 ->
withdrawn version 5. CLI independently confirmed stock 18 then 20 and workbook
integrity. All 26 original messages and 12 original items remained identical;
only the two expected activity messages and four new history/decision items were
added. Home context, original disclosure and Home navigation passed. The app quit
normally. No model inference, baseline rebuild, install rerun or full-suite cycle.

The owner also explicitly forwarded the remaining remote-CI course correction.
Changed only workflow triggers and the draft guard, preserving all 26 existing
steps byte-for-value under parsed YAML. Main/v-tag integration and non-draft PR
opened/reopened/ready events run the full job; manual dispatch handles later
milestones once available on main. Ordinary branch pushes and PR synchronize do
not. No assertion, branch protection or release requirement was weakened, and
no new testing framework was added. The policy records initial dispatch limits,
exact-current-head pre-merge verification and skipped-versus-passed semantics.

Evidence: [proposal status receipt](../../../integration/evidence/2026-10-27-proposal-status.json),
9,109 bytes, SHA256 `cec7e791bbeebdfd812a1a239330ab29e078c9fbf5b1c4e6f61e519d9bf4445c`.
The receipt includes source/executable hashes, focused check output, native UI
observations, independent arithmetic/integrity receipts and CI trigger parsing.
Broader native adoption, compaction, accessibility and release gates stay open.

## Pinned shortcuts and recent spaces, October 27
Implemented the missing P03 native navigation structure. The picker groups Home,
pinned shortcuts, recent visits and remaining spaces, with stable-ID deduplication
and accent-insensitive search. Home shows these useful entry points and removes
empty-workbook onboarding once content exists. Live view versus Snapshot labels
and Save a snapshot distinguish navigation pinning from frozen results. The
existing snapshot CLI/tool behavior is unchanged. The create-through-conversation
entry no longer overwrites an existing unsent draft.

SpaceNavigationState is portable SQLite presentation metadata. Bounded background
writes merge edit intentions under the existing package lock, preserve business
revisions, and do not create Sources/Records or history. Serialized UI writes and
generation checks preserve recency during bursts and reject stale reads. Closing,
quitting, switching workbooks and exporting await queued saves. Failed saves never
show an uncommitted pin as persisted. No schema migration or inference change.

Focused verification passed: build/run sevra-preview-checks, native app/CLI release
builds and preview packaging, one native interaction pass, and independent CLI/SQL
audit. Synthetic checks cover two-connection merging, invalid-batch rollback,
eight-visit bounding, stale callbacks, unpin, failed persistence, duplicate-title
and accent-insensitive matching, unchanged business/composition state and portable
reopen. The native UI passed pin/unpin, visit grouping, filtered Return navigation,
snapshot labels, populated Home, unsent-draft preservation and close/reopen. All
business/composition rows and revision 5 remained unchanged, with zero messages;
only expected presentation preferences and the synthetic unsent draft were saved.
Workbook verification passed, and the app quit normally.

Evidence: [space navigation receipt](../../../integration/evidence/2026-10-27-space-navigation.json),
5,046 bytes, SHA256 `db2d2c8765a6e8f2dff06811268d2af3c42bdfb631ac1e1c2e9af6954432cc3d`.
No broad model cohort, install suite, both-backend rerun or remote CI cycle was
required. Interpreted navigation/pin actions, complete pending-review Home,
keyboard/VoiceOver/narrow-window J11, engine/context and release gates remain open.

## Interpreted space actions, October 27
The native window now confirms an existing-space opening during the shared agent
run. Pin/unpin modifies the same presentation preferences as Home/the picker.
Missing or duplicate names and changed/unavailable windows produce a saved,
truthful explanation. Successful navigation can continue a compound request.
A later explicit opening clears deferred focus from an earlier created view.
Exact local open-name shortcuts also refuse duplicate names. Existing snapshot
APIs and business-state semantics are unchanged.

Verification was focused under the owner-approved policy:

- Rebuilt and ran sevra-agent-checks. Compound pin/open/calculation, create then
  open, unpin, read-only denial, duplicate/partial name, exact ID, direct CLI
  resolution, and absent/changed host callback pass. Existing grounding, request
  history, lineage, correction and context-budget regressions pass.
- The initial policy expansion failed the existing active-compaction test with
  context_limit. Preserve the failure. Redundant prose was shortened without
  enlarging the model/test budget or weakening the fixture. The original-budget
  test passes; product compaction remains disabled.
- Exported actual workbook schemas, regenerated pinned Splash reference grammar
  fixtures, rebuilt the checks and passed 30 tools, 35 grammar cases and 297 exact
  reference masks. Reference Python is development-only, outside the app runtime.
- Native app and CLI release builds and preview packaging pass. Three typed native
  requests on an isolated synthetic copy completed in 3, 2 and 1 model steps:
  unpin Purchasing then open Receipts; pin this live space without a snapshot;
  explain the distinction without changes. The picker showed Receipts pinned and
  current, Purchasing unpinned, and the existing snapshot unchanged.
- The explanation used internal tool names and called navigation a sidebar.
  This is recorded ordinary-language debt, not a clean wording pass. Functional
  no-change behavior passes. No broad model cohort was launched for this wording.
- CLI integrity passes. All original items, operations and space definitions are
  unchanged, with five spaces before and after. Only three request Sources were
  added. History revision advanced for requests/receipts, not business changes.
  Native preview quit normally. Changed-file Swift lint and diff checks pass.

Evidence: [space action receipt](../../../integration/evidence/2026-10-27-space-actions.json),
14,888 bytes, SHA-256
`f7d6c6191b77aac54dee5beeeb98dffce3ecb34c39fff436c033c0a53341ed58`.

Commands include `swift build --product sevra-agent-checks -j 4`,
`.build/debug/sevra-agent-checks`, `python3 scripts/check_splash_grammar.py`,
the existing native release app/CLI builds, `scripts/package_native.py`, and
packaged CLI `verify`/`tool open_space` on synthetic workbooks. The initial schema
export used SEVRA_SCHEMA_FIXTURE_OUTPUT and the existing reference fixture generator.
No install, both-backend, full-suite or remote CI rerun was required for this
checkpoint. Main/release integration and the full acceptance gates remain open.
Next: Home pending-review discovery, then the coherent J11 journey and remaining
engine/context, accessibility and release work. Do not treat this slice as whole-app
completion.

Final review clarified the baseline tool-instruction sentence: only the branch-and-continue
conversation action continues that conversation action with further work. Space
opening retains its separate continuation contract. Native schemas and model policy
are unchanged, so the native interaction evidence is reused. The receipt preserves
the exact tested source/binary hashes; final app/CLI packaging is rebuilt afterward.

## Current draft review and withdrawal, October 27
Implemented P03b: Home previews five oldest current drafts above custom components,
with a twenty-entry paged right-pane list independent of recent work or history
windows. A metadata-only SQLite partial index and dedicated draft generation keep
chat/receipt writes from invalidating pagination. Schema 4 migrates canonical
versions 1, 2 and 3 after exact schema verification. Original history is unchanged;
manifest version stays 1. Only synthetic fixtures were migrated. Matching app/CLI
binaries are required for migrated workbooks.

Added review_queue discovery and open_reviews host-confirmed navigation. The native
callback shares operation/workbook/conversation/navigation/cancellation checks with
open_space. CLI-only resolution never claims a visible opening. Read-only requests
permit discovery and refuse opening; neither action accepts or withdraws proposals.
The repo-owned Sevra skill documents paging, original inspection and CLI withdrawal.

Added explicit withdrawal because an unwanted first draft otherwise had no direct
way to leave pending review. It appends a decision and rejected version without
applying inventory or table changes. Idempotent retries return the same version;
obsolete/accepted targets refuse. Undo restores the draft. Native controls, exact
current-item text commands and withdraw WORKBOOK ID [TOKEN] share this core action.
General model withdrawal language remains unqualified.

Focused checks passed:
- Core suite: 80 passed, zero failed, including literal schema-3 migration, retained
  history/FTS and one migration receipt. Run before adding withdrawal; the preview
  suite separately verifies that addition, so no claim of a later full-core rerun.
- Preview checks: twenty plus five drafts beyond thirty newer accepted notes;
  current-head membership, request/row exclusions, unrelated chat, stale/foreign
  cursors, cancellation/deadline, failed/late reads, reopen, withdrawal/idempotency,
  stale/accepted refusal, Undo and no proposed-table effects. Integrity passes.
- Agent checks: host opening, unavailable-window refusal, read-only boundaries and
  original context budgets. Native grammar: 32 tools, 37 cases, 307 reference masks.
- Native app/CLI release builds, packaging, strict changed-file Swift lint and diff
  checks pass. Packaged CLI withdrawal retry returned the same ID; Undo restored a
  draft. Both synthetic packages pass verify with no asset issues.

Focused check entry points are swift build --product sevra-checks followed by
.build/debug/sevra-checks; the corresponding sevra-preview-checks and
sevra-agent-checks targets/binaries; and python3 scripts/check_splash_grammar.py.
Native builds use SEVRA_NATIVE_CANDIDATE=1, .build/native-product, release
configuration and the SevraDesktop/sevra products, then scripts/package_native.py.
The existing pinned development reference generated masks; shipped runtime remains
Python-free. No broad model cohort, both-backend run, fresh installation suite or
hosted CI rerun was required by this focused change.

Native evidence: a synthetic schema-3 workbook held twenty-five drafts and thirty
newer accepted notes. Home exposed pending work. Show me the drafts waiting for my
review invoked open_reviews and finished in two steps on native Qwen3.6-35B-A3B
4-bit plus DFlash2, reasoning budget 512. Previous/Next traversed twenty plus five.
The inventory proposal followed draft -> withdrawn -> draft -> accepted -> withdrawn,
with balances 20 -> 20 -> 20 -> 18 -> 20. Original rows remain unchanged.

The first UI check found Back traversing intermediate status versions. Preserve
that finding and its build hash. Corrected review actions replace the current route.
After rebuilding/reopening, withdrawing Planning note 05 displayed Withdrawn and one
Back returned directly to the list. Both withdrawn items were absent; twenty-three
current drafts remained. The final layout was visually inspected and app quit.

The exact-query plan uses items_review_order plus the head lookup without temporary
sorting. Thirty warm in-memory query samples over 100,000 historical drafts,
100,000 accepted heads and fifty current drafts gave p95 8.91 ms. This deliberately
narrow query check omits body/chunk ingestion and does not qualify whole-app/disk,
import, FTS or broader-device scaling.

Immutable evidence:
[review queue receipt](../../../integration/evidence/2026-10-27-review-queue.json),
23,957 bytes, SHA-256
`e2d662ee0dcf8232cc42535bcab78be2578f4a0bb6177f6b8dc7f578d251b784`.
It binds changed source hashes, check outputs, first/final build evidence, native
observations, CLI checks, original-row audit and query-only limits. Existing engine
parity, automatic-compaction, references/backlinks, full J11, accessibility and
release gates remain open. Next is the coherent J11 journey, with its failures and
limits recorded rather than treating this slice as whole-app completion.

## Integrated supplier journey and correction repair, October 27
Ran a fresh synthetic workbook through native creation and intake of the existing
make_ui_fixture CSV, PDF and PNG. The ordinary supplier request produced the correct
2.50/2.75 comparison, 0.25 difference and 9.09 percent relative to Vega, with exact
citations and a Purchasing table/chart space. An exact quote row opened through
its message action and Back returned to Purchasing. A direct AX link click did
not activate in this run; do not claim full keyboard/pointer equivalence.

A compound request created Pricing options and answered the hypothetical Vega 2.40
price correctly: 48 versus 50 for twenty, saving two. No quote/inventory mutation
occurred. An ordinary share request opened review; only the manually selected
what-if summary entered main, linked to its original exchange. The unsent main
draft was restored when returning.

The delivery request was ambiguous: the image says two bolts handed over but does
not identify sender/recipient. The model proposed +2. It remained a draft and was
withdrawn. This is a failed interpretation, not an actual inventory mutation.
A tool-description correction clarified sign/direction and asking when ambiguous.
The unchanged request in retained history still proposed +2; after duplicate
refusal it invented a resubmit occurrence. Preserve both failed runs. Neither was
accepted. Prompt-only clarification and semantic event identity are unqualified.

Code review of the exposed correction path found a separate concrete accounting
regression. Rejecting a draft correction also cancelled the earlier accepted
effect. Added a meaningful invariant check, observed 80 passed/1 failed, then
repaired withdrawal and Undo to restore the prior settled inventory effect. New
accepted heads preserve the earlier accepted content and exact lineage; Undo of
withdrawal restores the declined draft without accepting it. Movement corrections
now enforce unchanged subject/occurrence. No schema migration or history rewrite.
The agent tool exposes optional supersedes for an explicitly requested revision.
The native review makes Increase/Decrease explicit and explains retained acceptance
when a correction is withdrawn. The repo-owned skill documents these semantics.

After rebuilding, opened the original withdrawn movement and clarified that the
two units left our stock for the customer. Two model steps read that current version
and proposed -2 with its exact supersedes and original occurrence. Native review
showed Decrease: 2 brass bolts. Stock was 20 before acceptance, 18 after explicit
acceptance and 20 after Undo. The unrelated resubmit draft stayed withdrawn.

Separate main/thread drafts survived switching and close/reopen. The main scrollbar
returned to 0.1207576953433307, with the exact saved message/fraction retained.
All original items/assets/messages/operations/spaces from the initial snapshot,
and every pre-repair item/message/operation, remain byte-for-byte equal at the row
level. Included asset hashes match. Workbook verify passes with no asset issues.
The app quit normally after the interaction.

Verification commands and scope:
- swift build --product sevra-checks, then .build/debug/sevra-checks: 81 pass, zero
  fail after repair. Retain the earlier 80/1 failure. Checks cover prior effect,
  withdrawal retry, Undo/draft restoration, correction acceptance/Undo, stale
  targeting, subject identity, preserved originals, integrity and reopen.
- Built and ran sevra-preview-checks and sevra-agent-checks. Existing context
  budgets and first-draft withdrawal counterexamples pass.
- Updated actual-tool fixtures using the existing pinned development reference;
  python3 scripts/check_splash_grammar.py passes 32 tools, 37 cases, 307 exact masks.
- Native SEVRA_NATIVE_CANDIDATE=1 release SevraDesktop/sevra builds under
  .build/native-product and scripts/package_native.py pass. Strict changed-file
  swift format lint and git diff --check pass. No full installation or broad
  model/both-backend cohort or hosted CI rerun was performed.

The native screenshot also exposes raw pipe-table Markdown in chat; the generated
right-pane table/chart is correct. Native chat-table formatting is pending.
J11 is not passed: ambiguous direction and semantic duplicate prevention failed,
and full voice, interruption, narrow-window, keyboard/VoiceOver and uncoached-user
coverage remain. Engine adoption, automatic compaction, references/backlinks and
release gates remain open. Next work is the material inventory reliability boundary,
then the remaining coherent journey and presentation gaps.

Immutable evidence:
[supplier journey receipt](../../../integration/evidence/2026-10-27-supplier-journey.json),
95,707 bytes, SHA-256
`715552c7277d73fc9d62893482f4c93466dc4f78b186b5cdaf4da14fa8c9da4c`.
It binds source/build hashes, both failures, check outputs, explicit correction,
source/asset/history audit, original model messages and scoped presentation state.

## Inventory direction boundary and retained-history failure, October 27
Added a host-only direction-review scope shared by the native and baseline schema
adapters. The main agent cannot invoke its tool; the reviewer has no workbook
write tools and receives no earlier assistant guesses or proposed numeric sign.
The host checks exact quote origin and direction versus sign, persists review
inputs/results with the prepared tool receipt, and keeps human acceptance separate.
A missing/unclear/conflicting direction ends in a question, with no movement saved.
An exact duplicate_effect refusal now terminates that attempt, preventing the
observed within-run resubmit-ID retry. No database schema or engine change.

Evidence development was not uniformly green. The first probe invocation selected
a nonexistent default model folder and refused before inference. Correcting the
test invocation to the configured existing installation required no download.
The first isolated prompt then FAILED the original handover: it returned incoming
and quoted only Prepare the stock adjustment for that delivery. The revised
explicit-versus-inferred ownership policy passed five native samples: ambiguous,
outgoing, incoming, wrong sign, and Spanish. Recorded review times were 16.09,
10.04, 12.61, 8.66 and 8.58 seconds respectively. These are single samples.

The conversation probe with misleading earlier assistant history asked for direction
and saved no movement. The native app replay using the original retained J11 package
FAILED differently: it called withdrawn v1 ready for review. It invoked read twice
and no movement proposal, so this path bypasses the new review. All original items,
assets, messages and operation rows remained byte-for-byte equal as SQL values.

A separate fresh workbook imported the original synthetic receipt image through
the packaged CLI. In the native UI, the exact ambiguous request asked whether
units entered or left stock and created no movement. The explicit outgoing
follow-up then produced a single Actual/Draft movement of -2 with Decrease: 2 brass
bolts and receipt/User request links. It was not accepted. Both fixture workbooks
passed verification. The app quit after the visible checks.

Validation:
- swift build --product sevra-agent-checks -j 4 and the executable: passed,
  including isolated inputs, fabricated quote, wrong sign, draft-only success,
  terminal duplicate refusal, original history, receipts and integrity.
- python3 scripts/check_splash_grammar.py: passed existing 37 actual-tool grammars
  and 307 reference masks plus reasoning/citation/conversation boundaries. The new
  isolated grammar also executed in the native model probes; the normal 32-tool
  fixture did not change.
- Native release app and CLI builds and scripts/package_native.py: passed.
- Changed-file strict Swift format lint, skill validation and diff check: passed.
  The tool-scope enum explicitly preserves protocol tool names for the naming rule.
- Reused the preceding 81 core checks because no core/storage code changed.
  No broad both-backend cohort, fresh install, hosted CI or release qualification.

The review is probabilistic, has a measurable latency cost, and currently reads an
initial bounded excerpt. Direct CLI calls retain harness evidence responsibility.
General semantic event identity and the stale current-status claim remain open;
this checkpoint does not qualify the whole journey. Earlier probe binaries were
overwritten without exact digests; their observations are retained but not claimed
as byte-bound performance evidence. Final native app/CLI and current source hashes
are recorded in [direction review receipt](../../../integration/evidence/2026-10-27-inventory-direction-review.json) (83,311 bytes; SHA-256
28223e17e4a37dc0461b5b303fb2d640c4484911a34ca9a84a310eb4c8ae3299).
Other engine, context, relationship, accessibility and release gates remain unchanged.

## Historical citations and current-version answer, October 27
The observed withdrawn-v1 answer now has a deterministic current-head inspection
boundary and a host version note. Historical citations remain usable. A retry
cannot escape the refresh by dropping its citation or changing to general basis.
The core lookup reads only exact-version metadata in one transaction. Original
creation data remains unchanged and its read notice explains the status distinction.

82 core checks and all agent checks pass after final changes. Early fixture failures
were missing Source lineage and missing selected-ID context, both correctly refused.
A new footer initially formatted numeric versions as 2.0/1.0; it now uses integers.
Native release app/CLI builds and packaging pass, as do strict changed-file Swift
format lint and git diff --check. No tool schemas or grammar masks changed.

Two scoped native observations are retained. The original ambiguous handover asked
for direction without creating a movement, taking the direction-review path. The
historical/current question then read the review queue, lineage, both movement
versions and original receipt, and correctly reported withdrawn status. Original
and current links and the host note were visible. The final app quit normally.
Original 13 items, 3 assets, 33 messages, 77 operations and 2 spaces match exactly;
only the two new request Sources and conversation/run receipts were added. Included
asset hashes match, workbook verification passes, and stock remains 20.

The native run did not need forced citation refresh; deterministic tests exercise
that refusal and the citation-drop counterexample. This does not qualify all
freeform status claims, general event identity, J11, engine adoption, automatic
compaction or release. No installation, full-suite, broad model or CI rerun.
Immutable [citation version receipt](../../../integration/evidence/2026-10-27-citation-current-version.json): 91,919 bytes; SHA-256
4bc29db55e50b5b691aef77d03705ebb3431312695af51b30d61bb050a68b736.

## 75% compaction policy alignment and retained native failure, October 27
One threshold function now serves native ContextBudget and both adapters through
ContextMeasurement: 75% of actual configured capacity, or earlier for output,
next-result and recovery reserves. Removed the adaptive floor increase. Oversized
required state, no reclaimable history, ineffective summaries and still-full
checkpoints refuse explicitly with measured tokens; they preserve original work.
The agent also measures before every generation to catch added recovery/handoff
context. Baseline hard admission now includes its full reply allowance. Native
normal-response metrics and new checkpoint metrics expose the selected threshold.
Product compaction flags, model/context choices, reasoning and KV handling stay
unchanged. Automatic compaction remains disabled in both products.

Agent build and all deterministic checks pass, including new boundary/no-gain/floor
and retry checks plus existing repeated compaction, cancellation, state, retrieval,
portable continuation and no-duplicate-write coverage. An old 8K synthetic fixture
was correctly refused at a 4,120-token irreducible floor versus threshold 4,088;
the successful repeated-job fixture now uses an explicitly synthetic 12,288
capacity. Preserve that refusal, not a claimed regression in production inference.
Strict changed-file Swift formatting, repository links and dbmd validation pass.
Core code is unchanged since the preceding 82-pass check. No new tool schemas,
grammar mask changes, installation, full product rebuild or hosted CI rerun.

The actual native eight-report replay FAILED at exact requested identifiers.
Twelve responses stayed below the 24,576 threshold; eight checkpoints completed.
Quantities, units, currency constraint, all eight numeric report results and lineage
survived, but the draft renamed X-CHECK labels to Inspection X. Its final answer
wrongly claimed to preserve those labels. Two identical save_space calls resolved
to one idempotent space. No duplicate artifact or inventory change occurred, but
that is not evidence of no redundant action attempts. Original rows are unchanged;
failed draft/checkpoints survive portable export/reopen, and verification passes.
The model unloaded and recorded measured sources/binary/engine/grammar stayed fixed.
This single sample is not a matched performance comparison or production gate.

Next: inspect the exact drafting context and fix identifier copying plus unsupported
completion assertions. Do not weaken the exact-label check, raise the selected
threshold, assume missing source context, or rerun broad cohorts until this failure
is addressed. Keep the whole failure in [75% policy receipt](../../../integration/evidence/2026-10-27-context-75-policy.json.gz) (95,680 bytes;
SHA-256 67ac05d72b3a51facba84b8075284c696d63203ef771a2adc626e9c4c68d5f87).
Engine numerical-repeatability review, full native journeys, references/backlinks,
accessibility, latency/memory and release gates remain open.

## Saved-artifact truthfulness and rejected reviewer, October 27
Supported completed_action results now render from actual document/space/opening
receipts. A save confirms storage and names its target; it cannot establish that
all requested content was preserved. Original model finish arguments and all
attempt receipts stay inspectable. Identical repeated saves display once; a later
successful retry of the same title resolves its earlier failure in the final presentation. A failed
write without a later success remains explicit. Evidence answers keep their
existing checks. No schemas, core storage or native engine changed in final code.

The unchanged native eight-report replay completed twelve normal responses and
eight checkpoints in 223.190 seconds including verification, but still renamed
every X-CHECK label. The actual pre-render drafting input contained all eight
original labels. Its final visible body correctly confirmed only the saved space
and draft. The draft remains a failed content result. One space/draft exists and
all original items, heads, messages, operations, spaces, bases, effects and assets
are preserved; workbook integrity passes and the model unloaded.

A bounded isolated local-review experiment was developed to catch missing literal
text before writing. The relocated debug executable first refused missing bundled
resources before inference; the same executable in its normal resource layout
ran. Its initial unsupported finding lacked a retained raw response. Added full
review trace capture; the next trace showed a correct missing code attributed to
the wrong input. Host resolution of exact origins addressed that narrow failure.
The missing-code, permitted paraphrase, already-present code and Spanish cases
then passed, including a source instruction. Measured single-call times were
16.766, 5.756, 10.575 and 8.295 seconds, not performance qualification.

The full reviewer job FAILED after 290.280 seconds and nine checkpoints. It
required lineage identifiers in prose, reported only the shared CHECK suffix,
then rejected already corrected labels and clearances. Two draft attempts failed;
no draft was written. Two identical space attempts produced one stored space.
The existing response budget was exhausted; do not hide that as a passed refusal
or successful completion. Both workbooks pass integrity and independent original
state audits. Candidate3/candidate4 measured source/binary/engine/grammar identities
match before and after their runs. Run1 lacks an end-of-run source/binary snapshot
before subsequent edits/rebuild; its before identities and trace remain preserved.
The experiment was removed from the app and adds no shipped model call or latency.

Final focused verification: agent build and checks pass, including saved outcomes,
failed writes, idempotent display, successful retry, opaque/invented discarded
model claims and intact cited evidence answers. Native release app/CLI rebuild
and packaging pass. Strict changed-file Swift format lint and git diff --check
pass. Core is unchanged; reuse the preceding 82 core checks. No broad inference,
installation, full product suite, hosted CI or release run was performed.
The final native visual confirmation-link check awaits the Mac being unlocked.

Next: specify source-bound original spans/blocks for document composition, with
exact version/locator identity, normal prose and paraphrase support, omitted tails
and earlier-conversation values. A second generative reviewer did not solve the
observed problem. Keep the original failed job and nearby counterexamples as the
acceptance target. Automatic compaction, engine numerical-repeatability review,
full J11, references/backlinks, accessibility and release gates remain open.

Evidence: [saved-artifact and rejected-review receipt](../../../integration/evidence/2026-10-27-artifact-fidelity.json.gz), 377,349 bytes compressed; SHA-256 `83f309ea041dd4b939f6c37b16266d03a59c44e399260043440487a7770666fe`. Final native visual verification is pending manual unlock.

## Source-bound composition core, October 27

Specified [[records/specs/document-composition]] with three review passes and
implemented its Swift foundation. DocumentCopyReference anchors scalar spans and
expected UTF-8 hashes to completed read receipts from the same run/conversation.
The host resolves original text, not disposable reindexed chunk rows or a newer
source head. New prose and original copies compose one atomic draft. Saved
metadata retains exact source version, locator, receipt hash and output position.
Copied versions join lineage. Draft/estimate status and inventory state are
preserved. Idempotent retries survive a terminal run, while new writes require an
active request-linked run. Invalid parts, hashes, scopes, bounds, cancellation or
stale revisions leave no partial draft or revision.

Workbook verification checks declared copied passages. Tests preserve decomposed
Unicode, CRLF, NUL and emoji bytes; retain copies through changed extraction, a
new source head, acceptance, withdrawal, Undo and portable export/reopen; and
reject corrupted passage text/position. An independent SQLite/archive audit
confirms five review versions with the same copied text and estimate meaning,
one composition operation and zero inventory effects after the originating run
completed. This tests immutable observation, not extraction truth or requirement
completeness.

Final verification: swift build --product sevra-checks -j 4 passed. The full core
executable passed 89 groups, zero failed, including seven new composition groups.
Strict changed-file swift-format lint and git diff --check passed. The first test
compile exposed use of an internal helper and a missing required tangent parent;
those test calls were corrected. An intermediate run passed 87 groups and failed
one because the test tried to withdraw an already rejected Undo result. Corrected
the journey to follow existing review behavior; no review semantics changed.
Subsequent relevant code-boundary refinements were included in the final 89-pass
run. Intermediate full stdout was overwritten locally; its exact failure and
correction are retained in the evidence receipt.

No agent definition, CLI command, native UI, inference engine or grammar mask
changed in this checkpoint. No actual-model, installer, full product, hosted CI
or release cohort was rerun. The eight-report native content failure is still
unresolved. This foundation does not establish agent fidelity. Next: expose
bounded original-copy choices through reads and continuation, add compatible
typed draft parts, qualify changed grammar, then rerun the unchanged native job
and nearby permitted-paraphrase cases. Conversation-origin copies, references/
backlinks, compaction qualification, engine repeatability review, full J11,
accessibility, latency/memory and release gates remain open.

The owner replied that the Mac was unlocked, but the next CUA getApp observation
still reported it locked with automatic unlock paused by physical input. A new
manual-unlock request remains pending. The previous packaged preview's factual
save confirmation and exact draft-link UI check remain unverified.

Evidence: [composition core receipt](../../../integration/evidence/2026-10-27-document-composition-core.json.gz),
23,255 compressed bytes; SHA-256
`d742062251cf429da2c05dd6c46ba73c6a321a42b4c7c7dd0164739b3ca2e088`.
Includes final test output, code identities, the portable synthetic workbook,
independent audit, intermediate failures and explicit qualification limits.

## Composition metadata field isolation, October 27

Further compatibility review found that the new verifier scanned every item
with a documentComposition data key. That could reject an imported business
field on a Source, analysis Record or table row. Narrowed reserved metadata
verification to document Records. The added regression genuinely failed before
the fix (89 passed, one failed); after the fix all 90 core groups pass, including
the malformed-document-metadata counterexample and original portable/review
checks. The core build, final strict changed-file formatting and diff checks
pass. The formatter wrapped the SQL line after the 90-pass run; no semantic edit
or further test run followed. The receipt retains the tested source and final
hashes. Reuse the independent five-version portable audit from the first core
receipt; it was not separately repeated. Agent/CLI integration, the actual-model
content failure and the pending unlock/UI check remain unchanged.

Evidence: [field-scope regression receipt](../../../integration/evidence/2026-10-27-document-composition-field-scope.json.gz),
7,000 bytes; SHA-256
`d0d96846609d666b0d689c44b2c1b126fd2576c48939677acecc31c2dd4ef7d5`.
The core foundation was committed and pushed as 44540d9; this compatibility
correction follows separately. Next work remains bounded copy selection through
reads/continuation, typed draft integration and the unchanged failed native job.


## Agent source-copy choices and grammar checkpoint, October 27

Connected the exact-copy core to read and draft tools, both inference adapters
and continuation. Read publishes bounded original line/fragment choices; the host
resolves selected IDs, inserts original UTF-8 and retains exact version lineage.
Only complete currently presented passages supply dynamic grammar choices. Native
grammar refuses unknown/unpresented IDs with reasoning on/off. Raw-text drafts and
paraphrases remain compatible; embedded input instructions do not authorize writes.
Continuation shares bounded original passages across read groups and deduplicates
repeated spans. Original request, context threshold and response/step budgets are
unchanged. No extra model reviewer or engine change was added.

Verification: core and agent builds pass; all 94 core groups pass, zero fail. Agent
checks pass, including exact source-copy drafting and permitted paraphrase. Actual
tool schema export and pinned upstream reference regeneration pass (32 tools,
38 cases, 323 masks). Native grammar comparisons and dynamic copy choice grammar
pass. An intermediate synthetic context failure reached 8,199 tokens at the fixed
8,184 threshold because repeated reads restored duplicate passages; deduplicating
original version/locator/range/hash fixed it without changing the test or limits.
A new grammar test initially ordered parameters incorrectly; corrected that test
to the existing sorted format. Its failed log is retained. Initial test compile
API/throwing-expression mistakes were corrected; initial full output was not retained.

This checkpoint is provisional for actual inference. Commit before replaying the
unchanged eight-report maintained32K job. No actual-model, native UI, installer,
performance, full-suite, hosted CI or release pass is claimed. Earlier-conversation
copies, provenance UI, references/backlinks and all separate compaction/engine/J11
gates remain open. The UI tool still reports the Mac locked after the owner said
unlocked; the existing unlock question and factual saved-draft link check remain
pending.

Evidence: [agent-copy deterministic checks](../../../integration/evidence/2026-10-27-document-copy-agent-checks.json.gz).
Includes final core/agent/grammar stdout, failed grammar stdout, source/binary
identities and exact intermediate failure descriptions.


## Actual copy-integration context refusal and repair candidate

The first unchanged native maintained32K replay at c554640 failed after three
responses, two report reads and one checkpoint: 24,922 tokens exceeded the fixed
24,576 maintenance threshold. It took 43.824589 seconds, made no draft and unloaded
successfully. Independent SQLite and file-hash auditing confirms original rows,
heads, bases, effects and included assets unchanged. Source, executable, engine,
Metal and grammar identities match before/after; both trees were clean. This is
a retained failed attempt, not native qualification.

The compact projection had repeated passages from the latest read and several
passages per earlier source. Limit it to one original from each retained version
and exclude IDs already visible in the final tool group. Additional originals
require explicit reads. The new repeated-read regression, all 95 core groups and
the agent checks pass. Changed grammar definitions are untouched, so reuse the
previous 38-case/323-mask pass. Replay the unchanged native fixture next from this
committed candidate. No context/response/step budget or acceptance change.

Evidence: [first native copy-context refusal](../../../integration/evidence/2026-10-27-document-copy-context-refusal.json.gz).
Contains full native input/output/metrics/history, before/after identities,
independent original-state audit and candidate deterministic stdout.


## Second native refusal and smaller ordinary source pages

At clean commit 3725712 the unchanged maintained32K eight-report replay reached
five report reads and four checkpoints, then stopped at 24,854 tokens against
the unchanged 24,576 threshold. Elapsed job/verification time was 113.204021
seconds. No draft was made; model unload and independent original-state/asset
audits pass. Before/after source, executable, engine, Metal and grammar identities
match. Reducing optional continuation was useful but insufficient to fit a wide
latest read. Preserve this failed replay; it does not qualify content fidelity.

Ordinary tool read now returns two chunks by default, with explicit page metadata
and nextOffset; callers may still request one to eight chunks. Original assets,
full indexing and completed receipts remain. The source-page/copy-page cursors are
separate. Added a meaningful regression that traverses all five chunks and verifies
a wide request, invalid bounds and explicit terminal page. All 96 core groups
and agent checks pass. Agent checks exposed an older flaky assertion matching
120 inside arbitrary assistant text including random citation UUIDs. It now
matches the actual rejected sentence The quantity was 120.; the bad-claim
assertion remains. Its failed and corrected logs are retained.

The native fixture, required labels/values, context threshold and response/step
limits are unchanged. Regenerate the actual declaration/reference fixture for
the revised tool description, qualify it and replay the native task next.

Evidence: [second copy-context refusal](../../../integration/evidence/2026-10-27-document-copy-context-second-refusal.json.gz),
96,148 bytes; SHA-256 dfe29565efaf1062f0dba44aec7af515ee2041e377bbd560d1eb450b3490fab6.
This includes complete observations, identity checks, state audit and candidate
deterministic logs. No UI, native adoption, full comparison or release pass.


## Eight-report fidelity passes; direct copy qualification next

The third unchanged maintained32K repair replay at clean 0d62807 passes. All eight
original CHECK label/clearance/unit/HOLD pairs survive. Original purchase/sample
and corrected packing values, unspecified currency, all eight report lineage,
one draft, one space, no original data/head/base/effect change, exact included
assets, portable export/reopen/integrity and model unload pass. Independent
SQLite/file auditing confirms the same. Twelve responses and eight checkpoints
took 234.204528 seconds. Identical repeated save_space arguments return the same
space through idempotency. Before/after source/executable/engine/Metal/grammar
hashes match, and both source trees were clean.

The draft used parts.text with zero original-copy references despite fifteen
presented choices. This proves this task's content, not actual-model copy choice.
Added an opt-in nearby English quotation, Spanish quotation and permitted
paraphrase probe; it requires actual copy metadata in literal cases and preserves
original/unrelated draft state. It observes the model freely, with no scripted
next action/reply, extra reviewer or changed original eight-report assertions.
The shared observer visibility changes only to let this diagnostic reuse it.

A separate review found manual editing inherited stale exact-copy metadata. The
new regression reproduces integrity failure A copied passage no longer matches
its original source read. (96 pass, one fail). New edit versions now clear only
reserved copy-span metadata, preserve business data/meaning/scenario, and retain
the prior original document as lineage. The regression covers changed text,
acceptance, an unchanged separate draft, and portable export/reopen. Final core
and agent verification follow before the nearby model run. No UI, production
compaction, full 64K comparison, adoption or release gate is cleared.

Evidence: [eight-report native pass](../../../integration/evidence/2026-10-27-document-copy-native-eight-report.json.gz),
160,942 bytes; SHA-256 91c0d85b89154c28bde21e033538967a34055b0fa0efb1a7dec485d2ae8ba083.
Includes actual contexts, outputs, history, metrics, before/after identities,
independent audit and explicit zero-copy-reference limitation. The two native
context failures and deterministic failures remain in their own receipts.


Manual-edit final verification: both builds pass, 97 core groups pass with zero
failures, and agent checks pass. Changed-file strict formatting, diff whitespace,
dbmd all-store validation (zero errors/warnings) and repository links pass.
[Manual-edit provenance regression](../../../integration/evidence/2026-10-27-document-copy-edit-provenance.json.gz)
retains both failing tests, final stdout and tested code/binary hashes. Native
grammar declarations are unchanged; reuse the prior actual grammar pass.


The first nearby probe attempt stopped during fixture setup before inference:
the unrelated pending Record lacked a required input version. Its source and
stdout/stderr/identities are retained locally. Add the synthetic report as its
explicit input; no product lineage rule, model task or assertion changed. Rebuild
and rerun in a new output directory. This setup failure is not a model result.


## Native literal copies work; permitted paraphrase exposes skipped draft

The corrected nearby setup ran all three original requests at clean 8cc0fb4.
English literal quotation and Spanish literal quotation each saved one real
copy reference, exact decomposed-Unicode/CRLF bytes, draft/estimate classification
and original-version lineage. Unrelated draft and original source heads stayed
unchanged; portable export/reopen/integrity passed. The permitted paraphrase
returned a cited chat answer with the excluded identifier and zero drafts. The
probe therefore fails as a whole. All source/executable/runtime hashes match
before/after and the model unloaded. Exact timings remain in the raw receipt.

The existing policy distinguishes answers from unsolicited proposals but did not
explicitly require delivery of a requested draft summary. Add that requirement,
plus independent respect for excluded identifiers in paraphrase. Keep all three
requests/assertions unchanged, with no new intent classifier, generative reviewer,
response/context/step budget or authority. Agent checks pass after this policy
clarification. Rebuild and rerun the nearby cases from the committed candidate.

Evidence: [first nearby copy/paraphrase results](../../../integration/evidence/2026-10-27-document-copy-nearby-first.json.gz).
Contains setup failure, actual full inputs/outputs/history/metrics, before/after
identities, both passing copy cases, and the failed paraphrase. This is no UI,
whole-product, performance, engine-adoption or release pass.
