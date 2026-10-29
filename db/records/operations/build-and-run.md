---
type: operational
id: 01m5refyq97sez3da1rywz08wf
created: 2026-10-25T02:33:33.673437+00:00
updated: 2026-10-29T15:02:47.731798+00:00
summary: Source installation, local AI setup, independent CLI use, verification and uninstall.
title: Build and run
---
# Build and run

The baseline commands below describe the preserved Slotstream build. Explicit native candidate sections use the pinned Python-free Splash build under [[records/specs/splash-integration]]. Keep product output paths and model requirements distinct. Native candidate scoped proof does not establish production engine adoption.


The development app targets Apple Silicon Macs. macOS 14 is the declared minimum;
the current verified host is macOS 26.6.2, 48 GB unified memory, Swift 6.3.3.
Older OS versions and smaller memory profiles are still qualification targets.
The inference engine chooses a hardware plan; a token-per-second claim requires
measurement on that hardware.

## Source installation

Install Apple's command line developer tools if absent. Use a Swift 6.3 toolchain (6.2 minimum for the pinned Markdown parser),
Git and Python 3. A full Xcode installation was not needed on the verified host.

~~~sh
git clone https://github.com/carloslfu/sevra-app.git
cd sevra-app
./scripts/build.sh
./output/bin/sevra version
./scripts/install.sh --no-build
open "$HOME/Applications/Sevra.app"
~~~

The build resolves the committed package revisions. It downloads verified MLX
Metal kernels through Slotstream's pinned build helper. Build dependencies and
kernels need network access on first setup. The installed app is designed to work
without the source checkout; fresh-checkout resource isolation remains a release gate.
The installer places the app in ~/Applications and the CLI link in ~/.local/bin;
add the latter to your PATH if needed. It refuses to replace an unrelated app or
CLI. Isolated install/update/uninstall and conflict-refusal checks pass. Full installation qualification is tracked in [[records/operations/implementation]].

This is locally ad-hoc signed software, not yet a Developer ID notarized release.
Do not describe it as App Store approved or tell users to disable system security.
Model weights are downloaded separately, with their own license, outside workbooks.

## Example and deterministic features

~~~sh
sevra demo "$HOME/Documents/Willow.sevra"
sevra inspect "$HOME/Documents/Willow.sevra"
sevra search "$HOME/Documents/Willow.sevra" "brass bolts"
sevra balance "$HOME/Documents/Willow.sevra" "brass bolts"
sevra verify "$HOME/Documents/Willow.sevra"
~~~

Use a new path for each create/demo command. Existing workbooks are never replaced.
Open the package using the app's Open command. Included files, search, tables,
formulas and export work without model setup.

## Local AI

Open Settings and choose an existing compatible Slotstream Fast model folder or
use Download / verify model. Setup needs roughly 21.5 GB of model files plus
working space. The pinned model is Qwen3.6 35B A3B 4-bit with the Fast pack's DFlash
draft files. Only that verified pack is qualified by this integration. The default
location is ~/.slotstream/models/qwen36-35b-a3b-4bit.

~~~sh
sevra model-status
sevra model-setup
sevra ask "$HOME/Documents/Willow.sevra" \
  "Why do we have 18 brass bolts? Cite the evidence."
~~~

The first use verifies model files and loads the engine. A capability or memory
failure is visible; there is no hosted model fallback. Sevra processes coordinate
model ownership. Unload the idle model in Settings or close that process before
asking through a second Sevra process. Deterministic CLI operations remain usable
while the app is open.

## Verification and development

Full checks also build the candidate native grammar. Install the pinned Rust
1.96.0 toolchain through rustup once; it is a development dependency, not required
by the installed app or by the current baseline's ordinary build command.

~~~sh
rustup toolchain install 1.96.0 --profile minimal
./scripts/check.sh
swift build -c release --product sevra-benchmark
.build/release/sevra-benchmark
~~~

The checks use a standalone executable so they work with command line tools alone.
dbmd 0.14.7 or later is required for the final knowledge-store validation.
See the official [db.md repository](https://github.com/carloslfu/db.md) for
installation. The benchmark retains synthetic workbooks and JSON evidence in a
new .build/search-scale-<id> directory printed at startup. It runs both row and
multi-chunk document corpora at 10k and 100k by default. Use --rows-only or
--documents-only for an explicitly narrower diagnostic, or --self-check for the
small fixture/regression run included in CI. Neither a small run nor a single
corpus qualifies the complete scale requirement. See [[records/specs/search]].
## Candidate Splash checks

These are development checks for the candidate adapter, not the app's active
engine. Native transport/setup checks use Swift and need no model or Python:

~~~sh
python3 scripts/fetch_splash.py
swift build --product sevra-splash-checks
.build/debug/sevra-splash-checks
~~~

The fetch step is build tooling. It verifies the pinned upstream source/archive
and retains only the native executable, Metal kernels and licenses as candidate
runtime files. Real-engine tests require supported hardware and the exact selected
Qwen target plus matching DFlash2 weights. The original files are only read.

For the differential preparation/reference-token smoke check, use an isolated
Python environment with the pinned upstream dependencies. It is never shipped:

~~~sh
python3 -m venv .build/splash-reference
.build/splash-reference/bin/python -m pip install -r .build/upstream/splash-1.4.1/install/requirements.txt
.build/splash-reference/bin/python scripts/check_splash_reference.py \
  /path/to/qwen36-35b-a3b-4bit /path/to/qwen36-35b-a3b-4bit/dflash \
  --output output/splash-checks/my-run --run-engine --memory-bytes 12884901888
~~~

Use a new output path. Omit --run-engine for preparation/token fixtures only.
The script preserves local evidence and refuses an unexpected source revision.
It compares model.json bytes with upstream, then checks short generation,
cancellation/recovery, context preflight and weight release. It does not compare
whole frontend behavior or performance with the Python server. See
[[records/specs/splash-integration]] for the remaining qualification gates.

## Native tokenizer and grammar checks

~~~sh
swift build --product sevra-splash-text-checks
python3 scripts/check_splash_text.py
python3 scripts/build_guidance.py
swift build --product sevra-splash-grammar-checks
swift build --product sevra-agent-checks
python3 scripts/check_splash_grammar.py
~~~

These download only the three pinned tokenizer resources, not model weights.
The grammar builder verifies its public source commit, Cargo.lock, C header and
JSON-slice resource, then builds only the native llguidance crate with the pinned
Rust toolchain. It records the local library digest in .build/llguidance-receipt.json.
The installed product contains neither that development toolchain nor Python.

The native fixtures compare 24 exact prompts, 80 streaming decodes, 31 output
projections across 3,216 chunk layouts, every byte-vocabulary entry and 105 complete
speculative masks for JSON, Unicode, reasoning and strict tools. The actual 19
workbook tools add 27 grammar scenarios and 228 exact mask comparisons, plus
complete argument validation and open-row-data checks. Lifecycle and
malformed/truncated/cancelled-output refusal checks run in the same text suite.
To regenerate reference fixtures after reviewing an upstream change, use the
isolated reference environment above:

~~~sh
.build/splash-reference/bin/python scripts/generate_splash_text_fixtures.py /path/to/verified/model
.build/splash-reference/bin/python scripts/generate_splash_grammar_fixtures.py /path/to/verified/model
.build/splash-reference/bin/python scripts/generate_splash_output_fixtures.py /path/to/verified/model
.build/splash-reference/bin/python scripts/generate_splash_tool_fixtures.py /path/to/verified/model
~~~

These commands compare without editing by default; --write replaces fixtures for
review. The native grammar probe can also run the real engine using the original
weights and a Swift-prepared assembly:

~~~sh
.build/debug/sevra-splash-checks --prepare \
  /path/to/verified/model /path/to/verified/model/dflash .build/splash-models
.build/debug/sevra-splash-grammar-checks \
  /path/to/verified/model \
  .build/upstream/llguidance-1.8.0/target/release/libllguidance.dylib \
  .build/upstream/splash-native-1.4.1/engine/splash \
  /path/to/the/assembly/printed/by/prepare
~~~

This opt-in probe acquires Sevra's inference lock. It uses Swift prompt preparation,
native grammar masks and the unchanged Splash executable, with no runtime Python.
It checks streamed JSON/Unicode output, a schema-constrained tool call projected
into typed Swift arguments, cancellation/retry and healthy weight release. A tool
projection is not dispatch into a workbook or complete schema validation. Its default 12 GiB engine budget can be changed with
SEVRA_SPLASH_PROBE_MEMORY_BYTES. The host still needs the qualified hardware and
memory headroom; that budget is not a claim of physical 12 GiB device support.
These synthetic checks are not the full workbook agent or a matched speed test.

### Actual workbook tool changes and native probe

When the app's tool declarations change, rebuild sevra-agent-checks, then explicitly
regenerate the normalized declaration fixture before rebuilding reference masks:

~~~sh
SEVRA_SCHEMA_FIXTURE_OUTPUT=IntegrationTests/Agent/workbook-tools.json .build/debug/sevra-agent-checks
.build/splash-reference/bin/python scripts/generate_splash_tool_fixtures.py /path/to/verified/model --write
swift build --product sevra-agent-checks
python3 scripts/check_splash_grammar.py
~~~

Without the export variable, the check compares the fixture with the actual app
schemas and refuses drift. These manual check executables work with Command Line
Tools; XCTest or a separate test framework is not required.

To run the synthetic native workbook slice after the assembly setup above:

~~~sh
.build/debug/sevra-agent-checks \
  /path/to/verified/model \
  .build/upstream/llguidance-1.8.0/target/release/libllguidance.dylib \
  .build/upstream/splash-native-1.4.1/engine/splash \
  /path/to/the/assembly/printed/by/prepare
~~~

The probe owns a temporary workbook and Sevra's inference lock. It asks the real
model for calculation and table-proposal calls, validates them, invokes the actual
workbook dispatcher, checks the proposal before a separate fixture acceptance,
reopens the table, verifies values and lineage, cancels a request and verifies a
successful retry. Only the probe's own temporary workbook is removed. Tools are
explicitly selected to isolate this integration; it does not qualify autonomous
WorkbookAgent behavior or installed UI interactions.

## Harness integration

Use the same CLI from Codex or Claude Code. Install the included skill explicitly:

~~~sh
./scripts/install_skill.sh codex
# Or: ./scripts/install_skill.sh claude
~~~

The installer refuses to overwrite an existing skill. The skill uses the CLI and
never edits workbook SQLite directly. Its installation root can be overridden with
SEVRA_SKILL_ROOT for an isolated test. Remove the installed sevra skill directory
to uninstall it; this does not delete workbooks.

## Uninstall

Quit Sevra, then run ./scripts/uninstall.sh. It moves the owned app to Trash and
removes only its own CLI link. Workbooks, preferences and model files remain.
The installer and uninstaller support SEVRA_APP_INSTALL_DIR and
SEVRA_CLI_INSTALL_DIR for isolated installation tests.

## Known development boundaries

The format is pre-release and has no compatibility promise until its first
version is frozen. Preserve original documents and exported snapshots while
evaluating. XLSX import preserves saved values and evidence, not Excel macros,
external connections or full formula fidelity. Image/PDF OCR can be wrong.
See [[records/operations/implementation]] for the complete pending release gates.

## Autonomous native workbook qualification

The package-internal SevraNativeAI target connects the candidate to the actual
WorkbookAgent. It is linked by development checks, not the production app/CLI.
Run from the repository root after preparing the pinned native engine and grammar.
Use the selected full model folder, containing dflash/, rather than the tokenizer-only
fixture folder. These commands do not download model weights:

~~~sh
swift build --product sevra-agent-checks
.build/debug/sevra-agent-checks
.build/debug/sevra-agent-checks --autonomous \
  /path/to/qwen36-35b-a3b-4bit \
  .build/upstream/llguidance-1.8.0/target/release/libllguidance.dylib \
  .build/upstream/splash-native-1.4.1/engine/splash \
  .build/splash-models
~~~

The first command without arguments checks the actual schemas and workbook actor
lifecycle without loading weights. It covers cancellation before dispatch, terminal
run history, exact baseline history types, proposal draft/acceptance/withdrawal
context, meaning preservation and the deterministic three-search coverage response.
The full grammar script also runs these checks, so they are part of regular CI.

The opt-in autonomous probe uses the shared inference lease and a 12 GiB native
engine budget. Unload any model already held by another Sevra app/CLI process.
It creates and removes only its own temporary synthetic workbooks, checks proposals
before separate fixture acceptance, comparisons and citations, native table/chart
spaces, a hostile document, missing evidence, cancellation/retry and lease release.
Its emitted metrics are correctness diagnostics, not a matched speed benchmark.
The candidate validates runtime/Metal digests and selected model preparation before
launch. Production packaging, full clean-download qualification and wider application acceptance
remain open.

For the focused inventory regression, replace --autonomous with --inventory in
the same command. It checks that a computed stock answer cites exactly the opening
basis and accepted movement versions and leaves inventory unchanged. The actor
fixture also proves that those references are eligible immediately after balance,
without requiring a redundant read of each version.

## Candidate context profiles

Only development checks read SEVRA_NATIVE_CONTEXT_TOKENS. Supported evaluation
values are 8192 (the default), 32768 and 65536. This does not change the installed
app or declare a qualified hardware default. Exact rendered prompt counts,
output allowance and a proactive maintenance recommendation are recorded in each
native request's metrics. Dedicated evaluation probes enable the shared agent's
automatic context maintenance; both packaged app/CLI paths still disable it. The
8K adaptive threshold and larger-profile qualification limits are described in
[[records/specs/conversation-context]].

For an occupied 32K inventory probe, use:

~~~sh
SEVRA_NATIVE_CONTEXT_TOKENS=32768 .build/debug/sevra-agent-checks --occupied \
  /path/to/qwen36-35b-a3b-4bit \
  .build/upstream/llguidance-1.8.0/target/release/libllguidance.dylib \
  .build/upstream/splash-native-1.4.1/engine/splash \
  .build/splash-models
~~~

The fixture includes at least context-size minus 8192 tokens of closed archive
notes, then runs the actual inventory agent and requires exact balance citations
and unchanged inventory. It checks actual per-request occupancy and output bounds.
This synthetic stress case is not a realistic long-conversation or repeated
compaction qualification. Run --autonomous with the same environment setting to
check all seven shorter jobs at that allocation. Memory remains 12 GiB; wider
hardware/memory budgets require separate recorded qualification.

## Conversation history and checkpoint storage

Newly built app/CLI binaries use database schema 3. Opening a canonical schema-1 or schema-2
workbook migrates its database transactionally and builds the history index.
The package manifest remains version 1; older binaries refuse schema 3 on opening.
Use matching app and CLI builds. The installed earlier baseline has not been
replaced as part of this development checkpoint.

~~~sh
sevra history Workbook.sevra main
sevra history Workbook.sevra main AFTER_MESSAGE_ID
sevra history-search Workbook.sevra main 'supplier quote'
sevra history-search Workbook.sevra main 'supplier quote' CURSOR
sevra history-read Workbook.sevra main MESSAGE_ID
sevra checkpoints Workbook.sevra main
sevra checkpoint Workbook.sevra main CHECKPOINT_ID
~~~

History pages preserve whole messages and optional original receipts. Search is
scoped to one conversation and returns newest matches with an append-safe keyset cursor bound to the query and conversation.
Checkpoint inspection projects current input acceptance and meaning from records;
it does not trust the digest's wording. Checkpoint creation is automatic in the candidate agent and inspectable through
this core API and CLI; it is not a user-facing manual maintenance step.

After scripts/build.sh, run python3 scripts/check_history.py. It uses only its own
synthetic schema-1 fixture, pages 700 messages, reads an older exact message, tests
search pagination and verifies a portable copy offline. Core checks additionally
cover rollback/refusal, cancellation, stale checkpoint publication, chains, exact
references, payload preservation and altered-history detection.

## Tool journal and older conversation retrieval

~~~sh
sevra unresolved-calls Workbook.sevra main
sevra tool-receipt Workbook.sevra main RECEIPT_ID
sevra tool-result Workbook.sevra main RECEIPT_ID '["rows","0"]'
sevra tool-result Workbook.sevra main RECEIPT_ID '[]' 0 --raw-json
~~~

Use nextOffset on result pages. A prepared call has no final result; inspect its
committed operation and current workbook state rather than automatically replaying it.
The result's hash is stable across pages. History and tool receipts are operational
history, not permission or proof of current acceptance. Failed calls may retain
completed sub-operations. Original results travel in portable snapshots.

The native --history check uses 110 closed messages and an earlier constraint;
it requires autonomous history search/read and the exact original purchase code.
Use the same arguments as --autonomous. These retrieval checks do not prove
automatic compaction or restart/resume qualification.


## Automatic context maintenance checks

Replace --autonomous with --continuity in the native probe command. It creates
synthetic histories, requires multiple automatic checkpoints and exact identifiers,
decimal spelling and units, exports/reopens the workbook, and checks misleading
digests against current forecast acceptance. Cancellation during summary generation
must retain the previous checkpoint; explicit retry must reacquire the model.
For the focused authority/cancellation part, use --context-recovery. No weights
are downloaded. Probe output and failures must be recorded before a
profile is described as qualified.

The same scenario is available for the preserved Slotstream baseline:

~~~sh
.build/debug/sevra-agent-checks --baseline-continuity /path/to/qwen36-35b-a3b-4bit
~~~

That debug executable needs mlx.metallib beside it, from the existing verified
build preparation. This is development comparison tooling, not a product backend
picker. Run one model probe at a time so the inference lock and memory budget are
meaningful. The production build remains Slotstream until adoption gates pass. Its automatic
compaction capability remains disabled after the opt-in baseline recall probe failed.

The ordinary no-argument checks cover deterministic repeated maintenance, original
history hashes, changed acceptance during summarization, unfinished earlier calls,
invalid/cancelled summaries, complete retained tool groups, omitted-calculation
invalidation, chapters and tangent scope. Their byte-based synthetic counter tests
the controller, not real tokenization or hardware capacity. Native measurement uses
the selected template and tokenizer instead.

## Bounded reasoning qualification
The native comparison keeps the pinned model/engine, 32K context, 12 GiB engine budget, greedy sampling and 1,800 total output tokens fixed. It alternates off and a 512-token reasoning budget over five frozen synthetic workbooks, three repetitions each. The fixtures in integration/fixtures/reasoning contain no private files. They exercise stale forecast summaries, accepted estimates, original conversation recall, stock provenance and incomplete missing-document search.

```
swift build --product sevra-agent-checks -j 4
SEVRA_REASONING_FIXTURES=integration/fixtures/reasoning \
.build/debug/sevra-agent-checks --reasoning-comparison \
  /path/to/verified/model \
  .build/upstream/llguidance-1.8.0/target/release/libllguidance.dylib \
  .build/upstream/splash-native-1.4.1/engine/splash .build/splash-models
```

Each result includes checks, the archive hash, complete answer, exact tool receipts and metrics. Failed tasks remain in the output and do not abort later trials. After printing the complete summary, the current executable returns nonzero if any trial failed. The historical A/R1/R2 runs returned zero even for case failures; inspect their final passed counts and individual checks. Request IDs vary across runs, so these are matched input workbooks, not byte-identical prompt replays. Timings include setup and must not be presented as a matched Python/native speed comparison. Review answer semantics as well as the automatic checks.

To generate another frozen fixture set, omit SEVRA_REASONING_FIXTURES and set SEVRA_REASONING_SAVE_FIXTURES to a new directory. SEVRA_REASONING_BOUNDED_ONLY=1 runs the fifteen bounded trials for a separately labeled follow-up. Current reasoning retains ephemeral state between tools within a request; the initial historical comparison discarded it and its failures must remain identified separately.

Use --reasoning-boundary with the same four paths to test short forced reasoning cutoffs under the actual grammar, cancellation, truncated output and a subsequent complete request. No tool action is dispatched by this engine-boundary fixture. Use SEVRA_NATIVE_REASONING=512 with --continuity and --autonomous for full application-loop regressions. The default remains 0; these are developer checks, not a user settings picker or a production promotion.

## Evidence recovery check
Use --inspection-recovery with the same four paths as --reasoning-comparison. It injects an uncited evidence finish and an invented numeric current_request finish, each with reasoning off and bounded512. Only that first invalid finish is synthetic; the native model must recover through the inspection-only tool scope, read and cite the original, return the exact quantity and unit, preserve business records and unload. This deliberately exercises a recovery branch and is not counted as an autonomous success trial.

The first fixture version required the contiguous phrase 0.10 kg. Its fourth live response correctly separated quantity and unit, so that run retains a nonzero test exit. The corrected assertion checks the exact decimal spelling and unit independently. Engine/runtime source is unchanged by that fixture correction.


## Native setup candidate

Build the separate Python-free setup executable:

```sh
swift build --product sevra-native-setup -j 4
.build/debug/sevra-native-setup /path/to/sevra-native-models
```

This downloads the pinned selected target and draft, checks storage, streams files to disk, verifies size and SHA-256 and publishes the native model assembly. Cancel with Ctrl-C; run the same command again to resume. The command requires Apple M3 or newer and macOS 26.4 or newer. These are the engine's minimum requirements, not a qualified memory/context profile for every device. It installs no Python or inference dependencies and does not switch the installed app's backend. A build still resolves this repository's Swift dependencies.

Reuse a complete existing compatible pack without downloading weights:

```sh
.build/debug/sevra-native-setup /path/to/sevra-native-models \
  --reuse /path/to/verified/model /path/to/verified/model/dflash
```

Reused files are verified and remain in their original location. Do not move or delete them while the assembly uses them. Incomplete or different reused packs fail visibly; omit --reuse to download the selected pack into the candidate's own snapshot storage. Partial downloads live under .snapshots. Failed setup preserves a prior selection. Native helper/grammar packaging and production Settings wiring remain open.

Synthetic transfer/preparation/hardware checks run with sevra-splash-checks in scripts/check.sh. The optional bounded live-network check downloads only the two pinned configuration files, then repeats each transfer from a partial file:

```sh
.build/debug/sevra-splash-checks --setup-network .build/setup-network
```

For search scope qualification, --coverage takes the same four paths as --reasoning-comparison. It runs the frozen accepted-forecast case and exact movement-count cases with reasoning off and bounded512. A hidden movement deliberately lacks the search term in its text, and the zero-count workbook has an unreadable Source. The checks require host-rendered counts with every filter, unchanged business state and clean unload. Save stdout and stderr separately so complete JSON evidence cannot interleave with progress messages.

The preserved-backend real-weight suite now includes explicit positive and zero scoped-count cases. Run python3 scripts/check_model.py coverage for those two cases alone, or omit the argument for the complete suite. It requires host-only rendered counts, all stated filters, unchanged business records and successful completion. These tests use the selected local weights and temporary synthetic workbooks, without hosted inference.

## Isolated native app and CLI preview
Build the separate preview with `bash scripts/build_native.sh`, then run `python3 scripts/check_native_package.py`. This uses the pinned Rust toolchain to build the native grammar library and Python for contributor packaging only. The installed preview, its model setup and CLI use no Python runtime. The unchanged upstream helper and Metal kernels remain hash checked after signing.

The output is `output/native/Sevra Native Preview.app` and `output/native/bin/sevra`. This command does not install the preview or replace `output/Sevra.app`. The preview has separate settings and does not register Finder associations. The package check denies build-folder reads, verifies both Metal libraries and the grammar dylib, checks that baseline modules are absent, and refuses missing or altered packaged resources. It also exercises a missing-model run, so run it when no other Sevra model job is active. CI uses `python3 scripts/check_native_package.py --paths-only` to verify packaging without qualifying its GPU or executing a model run.

Run `output/native/bin/sevra model-setup MODELS_ROOT` to download the pinned target and draft. To reuse the original weights from an existing verified Fast folder, run `output/native/bin/sevra model-setup MODELS_ROOT --reuse EXISTING_FAST_DIRECTORY`; that directory must contain its matching `dflash` folder and must remain available. `MODELS_ROOT` is the parent of the selected assembly, not a legacy raw target folder. The preview Settings offers the same setup and reuse flows.

For actual-model checks without changing any user settings, use `SEVRA_CLI=output/native/bin/sevra SEVRA_MODEL_DIRECTORY=MODELS_ROOT python3 scripts/check_model.py`. Those environment variables select qualification inputs for the test script, not a runtime backend preference. Run only one real model workload at a time. Capture failures and tool receipts. Background downloads/builds make these behavior checks unsuitable for controlled performance claims.

The preview uses a provisional 32K context, bounded512 reasoning and 12 GiB engine budget. Automatic compaction remains disabled. It is a qualification artifact until matched performance, memory, setup, application and hardware gates pass.

## Matched request performance
R1 is retained for historical reproduction only. Its reference used normal priority while Swift used foreground. The current coordinator refuses a non-pilot R1 cohort. The qualifying command below describes the historical procedure and must not be treated as a current release gate. Preregister a replacement request protocol with actual wire-byte verification before rerunning qualification. See [[records/specs/splash-integration]] Request-priority comparison correction.


The request comparison is development tooling. First prepare the pinned reference
environment and native model assembly as described above, and build the worker:

```sh
swift build -c release --product sevra-inference-performance -j 4
python3 scripts/check_performance_harness.py
python3 scripts/compare_splash_performance.py \
  --models-root /path/to/sevra-native-models \
  --output .build/performance/pilot-new --pilot
```

Use a new output folder every time. The pilot records failures but cannot pass a
performance gate. It calls the pinned Python Frontend/NativeBackend directly,
without an HTTP listener. A development-only grammar adapter preserves Sevra's
required-first nested property order without changing the prompt. The native
worker uses production Swift primitives. The installed app still contains no
Python. Both use the same unchanged native helper and model assembly.

After reviewing the pilot, commit the tested harness and frozen protocol. With a
clean checkout, AC power and no other model job, build or download running:

```sh
python3 scripts/compare_splash_performance.py \
  --models-root /path/to/sevra-native-models \
  --output .build/performance/cohort-new
```

The coordinator owns the shared inference lease and runs ten alternating paired
blocks, with two measured repetitions and one warmup per workload/backend/block.
Raw responses, exact prompt arrays, sampled physical-footprint traces, power,
thermal, swap and identity receipts stay in that output directory. The summary
requires all twenty measured samples per workload and backend, matching prompts,
all declared semantics, no request/sampling failures and the fixed median/p95
thresholds. An excluded block cannot qualify this fixed-size cohort. Preserve
failed attempts. Review and sanitize local paths before publishing receipts.
This is a request/frontend comparison; actual workbook jobs, full UI and hardware
qualification remain separate release gates.

## Currency correction recovery

After building sevra-agent-checks and preparing the native assembly, run the labeled
fault-injection probe. Keep stdout and stderr separate so progress cannot split
long JSON evidence lines:

```sh
swift build --product sevra-agent-checks -j 4
.build/debug/sevra-agent-checks --currency-recovery \
  /path/to/sevra-native-models \
  .build/upstream/llguidance-1.8.0/target/release/libllguidance.dylib \
  .build/upstream/splash-native-1.4.1/engine/splash \
  > .build/currency-recovery.log 2> .build/currency-recovery.stderr
```

It injects a comparison and the observed invalid dollar-denominated finish, then
lets the actual native model recover twice in off and twice in bounded512 mode.
It checks refusal before assistant publication, corrected citations, unchanged
business data, the expected request Source, integrity and helper unload. Run it
with no other model process active. The deterministic rejection case also runs in
the ordinary agent checks. This is not an autonomous workflow benchmark.

## Native table reliability checks

Run `swift build --product sevra-table-ui-checks` followed by `.build/debug/sevra-table-ui-checks` on macOS. This uses synthetic temporary workbooks and the actual AppKit table coordinator, requires no model download, and is included in `scripts/check.sh` and hosted CI. It covers sorting while an edit is pending, stable selection, concurrent correction refusal, cancelled/duplicate editing notifications, filtered-out selection, referenced-row formulas, column identity, and deterministically reordered async results/errors. See [[records/specs/product]] P12 and [[records/operations/implementation]].

## Active memory-pressure checks
The shared product service owns memory-pressure handling for app and CLI. Warning pressure defers release until the active operation ends; critical pressure cancels, preserves committed changes and releases after model endRun. New operations cannot reuse an incompletely released model. Ordinary user unload remains idle-only.

The synthetic lifecycle runner is included in scripts/check.sh and CI:

~~~sh
swift build --product sevra-product-checks -j 4
.build/debug/sevra-product-checks
~~~

After building the native preview and installing its selected weights, run the actual-model policy-event probe separately from all other inference:

~~~sh
SEVRA_NATIVE_CANDIDATE=1 swift build --scratch-path .build/native-product --product sevra-product-checks -j 4
.build/native-product/debug/sevra-product-checks --native /path/to/Models output/native/bin
~~~

The preserved baseline uses its existing model layout. Build it first so MLX kernels are available, then copy the fetched development metallib next to the debug test executable:

~~~sh
bash scripts/build.sh
swift build --product sevra-product-checks -j 4
cp .build/metal/mlx.metallib .build/debug/mlx.metallib
.build/debug/sevra-product-checks --baseline /path/to/qwen36-35b-a3b-4bit
~~~

These probes inject the same policy event used by the OS observer without exhausting RAM. They check terminal status, preserved business items, native helper reaping, inference-lock release, a new Ready request and a subsequent cited stock answer. They do not prove actual OS pressure delivery or whole-app physical-memory headroom. The runner keeps request semantics separate from resource lifecycle and exits nonzero if either fails; a baseline follow-up failure must remain a failure even if resources release correctly.

## Native process-death and request recovery
Run this opt-in probe after building the native preview and installing its selected model. No other local model process may be active:

~~~sh
python3 scripts/check_native_recovery.py --models /path/to/Models
~~~

The probe creates a temporary synthetic workbook, starts inference through the packaged native CLI and kills only that spawned CLI after generation starts. It checks that the observed native helper exits and that the model lease becomes available. It then holds the lease to force a second request to fail and verifies that this records its own terminal outcome without interrupting the earlier run. After releasing the lease, a new Ready request must complete, close the abandoned run, preserve original history and leave business items/spaces unchanged. All stages are printed before assertions; retain failures.

This checks process death during inference and a fresh request. It does not cover every filesystem failure or a crash at every mutation boundary. Synthetic request-admission checks in sevra-agent-checks separately cover atomic rollback, cancelled acquisition, history boundaries and a saved draft with an unfinished tool receipt that must not be replayed.

## Complete-workbook performance comparison
Prepare the pinned native helper, grammar library, selected model assembly and reference environment described above. Then build and run the no-model checks:

~~~sh
swift build -c release --product sevra-workflow-performance -j 4
.build/release/sevra-workflow-performance --self-check
python3 scripts/check_workflow_performance.py
~~~

The same fixture and gate checks run in scripts/check.sh and hosted CI without downloading model weights. The self-check verifies identical complete starting state, task inheritance, concurrent fixture isolation and ordinary production IDs/time. Gate checks reject missing warmups, failed priming/jobs, divergent prompts/tokens, incomplete process sampling, thermal/power exclusions, cleanup failures and median/tail latency regressions.

With no other model job, build or download active, run a fresh pilot:

~~~sh
python3 scripts/compare_workflow_performance.py \
  --models-root /path/to/sevra-native-models \
  --output .build/workflow-performance/pilot-new --pilot
~~~

The output directory must not already exist. This runs one paired block, one warmup and one measured job per workflow/backend. Review every error and exact paired prompt before continuing. The installed product never loads the reference adapter or Python.

After reviewing the pilot, commit the tested harness and frozen protocol. Build the matching release executable before starting a clean qualifying cohort. Omit --pilot and use a new output directory:

~~~sh
python3 scripts/compare_workflow_performance.py \
  --models-root /path/to/sevra-native-models \
  --output .build/workflow-performance/cohort-new
~~~

Each actual inference adapter owns the cross-process model lease. The coordinator checks availability but does not hold it over the worker. Jobs use the shared agent and include validation/recovery, persisted completion and scripted formula acceptance/edit/undo. Keep all per-step prompt arrays, tokens, receipts, samples and failures. The native process footprint includes host/helper; the reference adds its Python bridge. Only a full clean cohort can pass the fixed sample-count and latency gate. Automatic compaction and production adoption remain separate gates.

## Workflow divergence diagnostics
Replay a recorded successful native pilot with the exact same worker binary and native source. The command refuses a different build. The baseline must still contain its original identity, configuration and native result files.

```sh
python3 scripts/check_workflow_repeatability.py \
  --baseline .build/workflow-performance/pilot3 \
  --output .build/workflow-performance/native-repeat-new
```

After building the diagnostic-capable release worker, record actual mask hashes and grammar text with a full paired pilot. Use a new output directory, keep inference sequential and do not overlap builds or downloads.

```sh
swift build -c release --product sevra-workflow-performance -j 4
.build/release/sevra-workflow-performance --self-check
python3 scripts/check_workflow_diagnostics.py
python3 scripts/compare_workflow_performance.py \
  --models-root .build/native-fresh-setup \
  --output .build/workflow-performance/masks-new --pilot --diagnostic-masks
python3 scripts/analyze_workflow_masks.py .build/workflow-performance/masks-new \
  --output .build/workflow-performance/masks-new/mask-analysis.json
```

The pilot exits nonzero when prompts or tokens differ. Analyze and retain that failed result; it is the reason for this diagnostic. Never interpret the traced timings as performance qualification. `mask-analysis.json` verifies recorded prefix hashes and reports missing or conflicting observations as well as exact mask differences. Full uninstrumented W1 and a corrected matched request cohort remain independent gates.

## Controlled reference replay
Use the same worker binary and frontend source to replay one side of a recorded pilot. The default is native; --backend reference selects the development reference worker and includes its Python process in sampling. A different build is refused. Optional --disable-mask-tracing requires a traced baseline and changes only that observation setting; it is a controlled diagnostic, not an unchanged-conditions replay. Its report preserves actual request and token differences and cannot qualify performance.

```sh
python3 scripts/check_workflow_repeatability.py \
  --baseline .build/workflow-performance/masks1 \
  --output .build/workflow-performance/reference-untraced-new \
  --backend reference --disable-mask-tracing
```

The result retains the baseline identity, exact build/source/controller identities and the explicit tracing change. A nonzero mismatch outcome is evidence to preserve, not a reason to discard the run.

## Compressed diagnostic evidence
Large diagnostic receipts may use deterministic gzip around their JSON. This keeps the public checkout smaller while preserving complete local evidence. The exporter chooses gzip when the output filename ends in .gz and reports compressed size, uncompressed size and SHA256. Existing .json output remains supported.

```sh
python3 scripts/export_performance_evidence.py \
  --scope 'Diagnostic evidence only, not performance qualification' \
  --output integration/evidence/diagnostic-run.json.gz \
  .build/workflow-performance/masks-new
python3 -c 'import gzip,json; print(json.load(gzip.open("integration/evidence/diagnostic-run.json.gz", "rt"))["scope"])'
```

The inspection command reads the compressed JSON without creating or overwriting files. Do not overwrite existing published evidence. The October 27 diagnostic archive has a verified byte-identical round-trip; its uncompressed checksum is recorded in the progress register.

## Observation and later-cache diagnostics
The observation controls are development-only and do not add a setting to the installed product. They require the exact native worker build/source recorded by their baseline; the reference observation code is the explicit intervention and gets a new source identity. Each fresh reference worker runs Ready and the four warmups only.

```sh
python3 scripts/probe_workflow_observation.py \
  --baseline .build/workflow-performance/masks1 \
  --output .build/workflow-performance/observation-new
python3 scripts/check_workflow_diagnostics.py
```

Modes are none, hash-no-payload and delay-2ms. An optional --modes argument selects a unique subset. All preserve the upstream-produced mask buffer. The default no-observation mode performs no diagnostic hashing or delay. Any intervention result is marked diagnostic and excluded from qualification. The baseline masks1 worker predates the later cache metric; rebuilding that target changes its hash and correctly makes this old-baseline command refuse. Use a newly recorded matching baseline for a later build; never bypass the identity check.

The native and reference request metrics now retain matchedPromptTokens and deduplicatedKVTokens. A normal uninstrumented workflow pilot records both. The October 27 cache1 pilot's raw summary and loaded source are preserved separately from the later parameter-validation refactor. I1 now has a tested runner. Its actual-model outcome is recorded separately in the implementation register.

Inspect a complete cache-counter pilot with the reusable analyzer:

```sh
python3 scripts/analyze_workflow_cache.py .build/workflow-performance/cache1 \
  --output .build/workflow-performance/cache1/cache-review-new.json
```

It verifies prompt-array hashes, refuses missing cache counters and incomplete workers, and compares each prompt/output prefix against every earlier request in that fresh sequential worker. Counts and prefix bounds are not cached-byte identities. The output is diagnostic and cannot qualify adoption.

## Fresh-worker isolation pilot
The frozen I1 protocol gives each of the four workloads a fresh native and reference worker. Each worker runs Ready, one warmup and one measured job. The coordinator alternates frontend order, uses the actual model lease and waits for complete shutdown before the next worker.

```sh
python3 scripts/check_workflow_isolation.py
swift build -c release --product sevra-workflow-performance -j 4
.build/release/sevra-workflow-performance --self-check
python3 scripts/probe_workflow_isolation.py \
  --models-root .build/native-fresh-setup \
  --output .build/workflow-performance/isolation-new
```

Use a new output directory. No other inference, build or download may overlap the run. The coordinator freezes all product sources, workload sources, reference/controller files and the release worker before inference, then checks them before each worker and at completion. Editing a measured file stops further workers and fails the report. It verifies the pinned helper/resources and grammar library; the frontends independently verify their model/source identities.

Every prime, warmup and measured job must succeed. The report compares exact requests, outputs and both cache counters. Missing data, failed jobs, instrumentation, partial process sampling, thermal/power exclusions and failed cleanup cannot pass. Partial evidence is kept. The report and process exit distinguish a successful diagnostic from a failed one, and both performanceQualification and productionAdoption always remain false. Equal cache counts do not prove identical cached state.

The root summary compares all four workloads; raw receipts and prompt/memory traces live in the workload subdirectories. Export the root and each workload directory explicitly because the evidence exporter does not recurse. Keep any failed development checks alongside the final receipt. W1 mixed-workload failures remain separate evidence.

## Balance evidence recovery
The I1 inventory seed-2 job exposed a shared application problem: treating an opening-source reference as a conversation message and repeatedly searching history. A separate functional probe replays the same Ready/warmup/measured schedule on both frontends after changing the calculation evidence contract.

```sh
swift build -c release --product sevra-workflow-performance -j 4
.build/release/sevra-workflow-performance --self-check
python3 scripts/probe_balance_evidence.py \
  --baseline .build/workflow-performance/isolation1/inventory_evidence \
  --output .build/workflow-performance/balance-evidence-new
```

The baseline must have the original I1 source/configuration identity. The probe permits only the declared Tools.swift and WorkbookAgent.swift changes and rebuilt worker, verifies the helper/grammar identities, freezes its measured sources and preserves all failures. Other future source changes require a newly reviewed protocol or baseline, not removal of the identity check. Both frontends run sequentially under the actual inference lease. No overlapping build, inference or download is permitted.

Acceptance requires all original stock/citation/business-state assertions, no rejected finishes or history/count detours, complete process sampling/cleanup and valid power/thermal conditions. Timings are observations, not a performance gate. The first typed-reference-only attempt fixed the history detour but retained one formatting correction on each measured job, so its strict recovery report remains failed. Native citation rendering is evaluated in a separate later attempt. Preserve both versions and their exact loaded sources.

After rebuilding the isolated native preview, check the final installed CLI without the benchmark wrapper:

```sh
SEVRA_CLI=output/native/bin/sevra \
SEVRA_MODEL_DIRECTORY=.build/native-fresh-setup \
  python3 scripts/check_model.py inventory missing
```

The explicit inventory check verifies the complete stock answer, opening/movement citations, no rejected finish or history/count detour, unchanged accepted Records/spaces/balance and workbook integrity. It preserves the actual answer and tool receipts before asserting. The missing check independently verifies actual empty queries and incomplete-index disclosure. These are functional checks, not a latency comparison.

## Exact reference and Settings qualification
The native and preserved baseline share exact read/lineage candidate selection. Citation admission remains separate. The full local check covers dynamic schema validation, the recorded wrong suffix through actual grammar, complete context accounting and refusal receipts. The model-free collector check preserves the failed R2 detours:

```sh
bash scripts/check.sh
python3 scripts/check_item_reference_probe.py
```

After the pinned native and reference environments above are prepared, the optional fixed functional cohort can be reproduced without a prior local benchmark configuration:

```sh
swift build -c release --product sevra-workflow-performance -j 4
python3 scripts/probe_item_references.py --models-root .build/native-fresh-setup --output .build/item-reference-probe
```

Use the actual native setup root if different. The output folder must not exist. The runner freezes its source and binary identities, verifies engine/grammar pins, runs both frontends sequentially, saves every result and exits nonzero on a failed requirement. Do not overlap inference with builds or downloads. This is a functional cohort, not performance qualification. The first R2 completed all answers and state checks but failed on both seed-6 unnecessary count detours; do not omit or relabel those failures.

The final packaged native inventory check passed with fresh identifiers in four steps and no corrections. Native Settings started/cancelled/resumed partial downloads and reverified the existing model. Cancellation now reports resumable data, clears stale progress, and leaves controls usable. A deliberate ordinary setup failure also clears progress; success replaces the error. The model folder preference was restored after testing. A full 21.48 GB fresh download only through the UI remains separately unmeasured, while the underlying native downloader has earlier full-download/cancel/resume verification. Broader UI, voice, context, hardware and performance gates remain open.

The retained R2 archive is integration/evidence/2026-10-27-exact-item-references.json.gz. Commands, final build identities, failed test attempts, setup observations and packaged checks are recorded in integration/evidence/2026-10-27-exact-reference-qualification.json.

## Count purpose and native search verification
The active model finish schema uses counts for exact current-run count receipts. Historical assistant payloads retain coverageEvidence. Supplying the retired coverage argument is refused, including null or mixed old/new fields.

Replay the full fixed R2 schedule, without overlapping builds, downloads or another model job:

```sh
python3 scripts/probe_item_references.py --models-root .build/native-fresh-setup --output .build/count-purpose-replay
```

Use a new output folder. The retained successful run is integration/evidence/2026-10-27-count-purpose-replay.json.gz; the original failed seed-6 runs remain in integration/evidence/2026-10-27-exact-item-references.json.gz. This is a functional check, not a performance qualification. Preserve every failed run and do not reroll identifiers.

After building the native preview, test requested counts and missing evidence separately:

```sh
SEVRA_CLI=output/native/bin/sevra SEVRA_MODEL_DIRECTORY=.build/native-fresh-setup python3 scripts/check_model.py coverage
SEVRA_CLI=output/native/bin/sevra SEVRA_MODEL_DIRECTORY=.build/native-fresh-setup python3 scripts/check_model.py missing
swift build --product sevra-search-ui-checks -j 4
.build/debug/sevra-search-ui-checks
```

The search state check is also in scripts/check.sh and hosted CI. It covers retained pages/anchor on Back, typed workbook/revision/filter identity, stale successes and failures, same-query cancellation/retry, clearing, failed continuation retry and refusal to append an old continuation to a new query.

For native UI verification, generate synthetic files in a new directory:

```sh
swift scripts/make_ui_fixture.swift .build/ui-fixture
```

Create a disposable workbook and include the three imports files through the native picker. The CSV must produce two rows, with Sierra 2.50 and Vega 2.75. Search quartz and open the PDF at page 2. Search Sierra inside the PDF: the view and composer selection must both identify page 1. Search fulfillment to find locally recognized image text, open the original image and exercise zoom. Search nandu to check the accented filename. Original files remain included and verify must report no asset or database issues.

Include the 35 paging notes. Search amber, load more results, open Amber_35.txt, and use Back. The last five results and opened-item position must remain. Changing the query or workbook revision must discard obsolete pages/cursors. Clearing must leave no results, error or loading indicator. Inspect filters and previews without waiting for AI. Native setup reverification should report Model files are ready without changing the selected folder or copying existing weights.

These journeys cover synthetic text/PDF/image/CSV intake and search. They do not qualify all media formats, real microphone dictation, VoiceOver, hardware/context envelopes or production adoption.

## Native multi-stage continuity workflow
Run the fixed 32K/bounded512 workflow against a model installation created by native setup:

~~~sh
.build/debug/sevra-agent-checks --continuity-workflow \
  .build/native-fresh-setup \
  .build/upstream/llguidance-1.8.0/target/release/libllguidance.dylib \
  .build/upstream/splash-native-1.4.1/engine/splash \
  .build/continuity-workflow-output
~~~

The output directory must be new and its parent must exist. This command retains synthetic workbooks, a portable snapshot and result.json on success or failure. It performs no download. It uses the same installed-model resolver as the native app, rather than the legacy local-pack layout used by older probes.

The six requests cover original quantity recall, forecast acceptance and withdrawal during maintenance, a subsequent corrected quantity, export/reopen stock calculation, and explicit inherited evidence in a tangent. The host brings the tangent response back to main with its original link. Three batches of 150 closed assistant notes and 18 chapter markers force repeated checkpoints. Human state edits are injected after summary input capture; the real model chooses its tools and answers. Record source/binary identities and all failed attempts. This synthetic functional sequence is not occupied-context performance, process-death recovery or complete C12/C13 qualification.

## I2 request-cache diagnostic
Build the release worker with `swift build -c release --product sevra-workflow-performance -j 4` and run its `--self-check`. Run `python3 scripts/check_request_cache_isolation.py` for fail-closed evidence checks. Then run `python3 scripts/probe_request_cache_isolation.py --models-root MODEL_ROOT --output NEW_DIRECTORY`, where MODEL_ROOT is the installed native model root and NEW_DIRECTORY does not exist.

The command executes four sequential workers: shared native/reference, isolated reference/native. Each runs Ready plus the supplier warmup and measured job. Do not overlap builds, model jobs or downloads, or change measured sources while it runs. Raw frames, prompts, samples and partial results are preserved. Nonzero exit can mean a matched-output diagnostic failed despite valid business answers. Inspect both arm reports; no I2 outcome qualifies speed or production adoption. The option is unavailable in the installed app and CLI.

## Voice lifecycle regression and native follow-up
Build and run the production dictation coordinator with injected speech drivers
and playback participants:

~~~sh
swift build --product sevra-voice-checks -j 4
.build/debug/sevra-voice-checks
~~~

The runner exercises permission/capture cancellation, callback identities,
duplicate taps, retry, startup failure, cross-window recording ownership, typed
draft preservation, manual editing, playback pausing and owner release. It never
requests speech/microphone access or captures real audio. These checks are part of
scripts/check.sh and hosted CI; they do not establish hardware or recognition
accuracy. During a qualifying model comparison, defer local builds/tests and
use the isolated branch's hosted CI first.

After the comparison ends, use a disposable workbook to test the native permission
flow, start/stop while a permission sheet is pending, append dictation to a typed
draft, manually correct it, send, change conversations and close the window. Check
that no late text appears and recording does not resume after cancellation. Test
unavailable/denied recognition without enabling any server fallback. With a
synthetic playable media file, check explicit play, keep-playing navigation,
pausing all workbook players for dictation and teardown of the owning window.
Record actual hardware/language/permission results and any untested branches.

## Checkpoint transaction crash checks
Build the model-free worker and run the controller on new synthetic workbooks:

~~~sh
swift build --product sevra-context-durability -j 4
python3 scripts/check_context_durability.py
~~~

By default it retains a new .build/context-durability-* directory, including every
fixture and result.json. Supply --output with a new directory for a named run,
or --binary for another built worker. The controller owns every child it kills.
It never opens a user workbook, captures audio or loads a model. The committed
visibility check uses a separate read-only SQLite connection; mutations and reopen
use the production Workbook APIs. Source/binary hashes bind each retained result.

The four cases are SIGKILL inside publication before commit, SIGKILL after commit,
cancellation after checkpoint/input inserts and concurrent acceptance before
publication. Verify exact retry identity, one accepted inventory effect, unchanged
history, current estimate status, integrity and portable reopen. A passing storage
run does not enable automatic compaction or qualify C12/C13 on its own. Defer local
execution while a qualifying model comparison is active.

## Document draft durability and editing
The model-free runner exercises the shared editor, transaction and AppKit close
boundaries. Run it with a GUI-capable macOS login; it creates only offscreen test
windows and disposable synthetic workbooks.

~~~sh
swift build --product sevra-document-checks -j 4
.build/debug/sevra-document-checks
./scripts/build.sh
python3 scripts/check_document_cli.py
~~~

For an authorized revision through a harness, use an exact document version and a
UTF-8 file. The command returns the new draft; it does not accept it:

~~~sh
sevra edit-document Workbook.sevra VERSION_ID revised.txt --token UNIQUE_TOKEN
~~~

Reuse the token and exact arguments after an uncertain result. An optional
--revision requires the current workbook revision. A stale version refuses;
inspect it before choosing a fresh edit or an explicit --separate copy. The edit
preserves meaning, scenario and metadata. File assets cannot be changed here.
Text is bounded at 16,000,000 UTF-8 bytes. The command creates the submitted Source
and derived Record in one transaction, with no claim of human authorship merely
because the caller used a CLI.

Native follow-up: edit a generated document, immediately accept it, follow its
older citation, then open the newer version. Type and immediately navigate, close,
quit and reopen; verify exact saved text. Use a second writer to force a conflict;
Done, navigation, export, close and quit must retain the text. Keep a separate
draft using both the visible action and the text/voice command, and verify both
versions. Check real SwiftUI window lifecycle, narrow layout, keyboard focus and
large-text responsiveness. Programmatic checks do not replace this visible replay.
Defer local execution during a qualifying model performance comparison.

## Replay the current-request evidence regression
After rebuilding the release workflow worker, run the retained failed block's
schedule against both frontends in a new output directory:

~~~sh
swift build -c release --product sevra-workflow-performance -j 4
python3 scripts/probe_request_evidence.py --models-root /path/to/native-models \
  --output .build/workflow-performance/request-evidence-replay
~~~

The original failing case is missing_evidence at seed 3005, after four warmups.
The runner preserves that prefix and the first complete measured cycle, verifies
all jobs and exact paired requests/tokens, and retains any failed attempt. It
never marks performanceQualification or productionAdoption true. Keep source and
binary identities unchanged during the replay. A fresh full W1 cohort remains
required for latency qualification.

The packaged document check accepts --cli for the isolated native product:

~~~sh
python3 scripts/check_document_cli.py --cli output/native/bin/sevra
~~~

## Native media packaging and focused UI checks
The primary viewer and compact retained player embed AppKit AVPlayerView through
NSViewRepresentable. This keeps AVKit directly linked in the packaged executable.
A release build using only SwiftUI VideoPlayer aborted while initializing its
AVPlayerView superclass; preserve that failed observation in the implementation
record. The native package check requires AVKit and refuses the former overlay.
Playback ownership remains in the workbook registry rather than view teardown.

After building both variants, run:

~~~sh
python3 scripts/check_native_package.py
python3 scripts/check_install.py
~~~

Use synthetic video/audio for actual UI checks: initial paused state, explicit
play, retained compact playback after Back, explicit close, and workbook close
followed by paused reopen. Resource/signature checks alone do not exercise player
creation. At minimum window size also check stacked comparisons, visible composer,
failed-save recovery controls and Light/Dark text contrast. Restore the previous
appearance after testing. Dictation hardware testing requires separate explicit
microphone/speech permission. See [[records/operations/implementation]] for the
recorded candidate and its remaining limits.

## Active-job context comparison
C12 subset; compilation passes. Record each actual-model result separately. Run only
when no other model or performance cohort owns the host:

~~~sh
swift build --product sevra-agent-checks -j 4
.build/debug/sevra-agent-checks --active-context \
  /path/to/native-models \
  /path/to/libllguidance.dylib \
  /path/to/engine/splash \
  .build/new-active-context-run
~~~

The output directory must not exist; its parent must exist. Run from a prepared
checkout containing integration/splash.json and .build/llguidance-receipt.json.
The probe uses installed native weights, runs the maintained32K and uncompressed64K
arms sequentially, and preserves both failures and successful workbooks. It does
not download models. Inspect result.json and both arm files, exact draft text,
original records, checkpoint boundaries and native helper cleanup. A passing
functional result does not enable product compaction or qualify whole-app memory.
See [[records/specs/conversation-context]] for the frozen job and acceptance scope.

Pass the installation root containing the selected model-name symlink and
.snapshots/.resolved directories. Do not pass the resolved assembly directory
itself: installed-model lookup adds the selected pack name. An initial October 27
probe used the wrong level and correctly stopped before loading either arm. The
failed setup receipts are retained; correcting the command does not change the
model, engine, fixture or context thresholds.
## Large linked-file preview verification

Build sevra-preview-checks, then run:

~~~sh
python3 scripts/check_large_preview.py --binary .build/debug/sevra-preview-checks
~~~

An optional --output NEW_DIRECTORY keeps the result at a chosen new path; existing
directories are refused. The default makes a unique .build/large-preview-* folder.
This creates a 2,148,532,224-byte synthetic sparse original, imports an explicit
link, cancels verification after 8 MiB, retries a complete verification, then
changes bytes without changing length and requires the saved evidence to be
refused. Workbook revision and recorded hash must remain unchanged. It exercises
AssetPreviewSession and the production hash reader, without a native renderer or
model. It is included in scripts/check.sh and the hosted workflow.

The parent measures Darwin process lifetime peak physical footprint while the
worker is still alive after the checks. The fixed ceiling is 256 MiB for this
headless verification process, including fixture setup and imported frameworks.
The bound detects whole-file materialization; it does not qualify full-app memory,
media decoding, filesystem cold performance, remote-volume interruption or UI
responsiveness. Record complete reported bytes, cancellation offset, original
refusal, OS/machine, commit, executable/source hashes, stdout, stderr and failures.
The real native large-file interaction remains a separate check. The existing
scripts/check_large_assets.py covers a different included-asset/ZIP64 round trip.

## Scoped maintained-context repair replay
Use --active-context-maintained with the same four arguments as --active-context
to replay only the maintained32K arm of the unchanged v1 fixture. This is a repair
diagnostic with its own result name. It reports referenceExecuted=false and
completeComparisonPassed=false even if its requested scope passes. Preserve the
original failed two-arm comparison. Use a clean committed source tree, record
source/binary/helper/grammar identities before and after, and run without another
local build or inference process. All existing exact-fact, uniqueness, lineage,
checkpoint, state and portable-copy assertions still apply.

## Window refresh regression
sevra-preview-checks now exercises the window refresh session as well as file
previews and operation ownership. A deliberately blocked background reader must
leave the UI actor responsive; one hundred timer ticks cannot add readers, three
replacements coalesce to the newest conversation, and close/reopen excludes a late
success or failure. Real workspace snapshots check coherent revision, changed versus
unchanged polling, chapter/bookmark contents, conversation anchors, cancellation,
deadline refusal and the subsequent successful read. The native app uses this same
session and core snapshot API. These checks supplement, rather than replace,
visible app and whole-process responsiveness measurements.

## Native large-media playback and teardown
After packaging the candidate, create a new synthetic workbook with:

```sh
python3 scripts/prepare_large_media.py
```

Optional --cli and --output arguments select a packaged CLI and a new fixture
folder. Existing output folders are refused. This writes a real 2,148,532,224-byte
silent PCM WAV, imports it as a link and a separate included copy, and verifies the
workbook. It needs about 4.3 GB of disk space. The extra original filename is a
hard link within the disposable fixture; the workbook's included asset is an
independent streamed copy. Fixture preparation is not UI qualification.

Open Large media.sevra in the native preview. Check included and linked playback,
seek near 03:03:20 of the 03:06:30 duration, Stop while linked verification shows
progress, and retry. Keep playing while returning Home, then close the compact
player. Also close the entire workbook during active playback with keep-playing
enabled, and during linked verification. Observe fresh accessible UI state after
each action. Use lsof -p PID -Fn to confirm the fixture WAV is no longer open after
close; paused-but-retained media is a failure, even if the window vanished.

For changed-original refusal, change one byte halfway through the synthetic linked
WAV without changing its length. Retry must reject it and preserve the included
asset. Restore only that synthetic byte, verify both hashes, and reopen. Never use
customer media for this destructive test. Older fixtures must show corrected
extraction wording without reindexing or changing asset mode.

Sample the app's Darwin physical footprint using footprint(pid) from
scripts/compare_splash_performance.py at 100 ms intervals. Record initial and
lifetime peak as well as samples, phase, process identity and final exit. The
reference audio-only test has a 512 MiB app-process ceiling and no simultaneous
inference, dictation, build or download. Shared OS media services are excluded.
Do not extrapolate a pass to all codecs, video/images, cold storage, whole-system
memory or media with an active model. Preserve failed runs and exact app/source
identities; the 2026-10-27 repair evidence retains both sides of this comparison.

## Isolated document extraction

Both build scripts now package the native sevra-extract executable beside the app
and standalone CLI. Python is build/test tooling only; extraction uses Swift and
Apple frameworks. A raw SwiftPM executable that imports files needs its adjacent
helper built first:

~~~sh
swift build --product sevra-extract -j 4
swift build --product sevra-extraction-checks -j 4
.build/debug/sevra-extraction-checks
python3 scripts/check_extraction_package.py --product output
python3 scripts/check_extraction_package.py
~~~

The package checks need their respective baseline/native build output. They deny
build-tree reads, extract synthetic text/PDF/DOCX through both packaged helper
locations and exercise standalone CLI import/read/integrity. scripts/check.sh and
hosted CI include the worker tests; native CI also runs the optimized release checks.

The worker tests cover crashes, uncooperative hangs, cancellation, output floods,
sampled memory refusal, malformed terminal results, stderr pressure, missing
helpers, bounded concurrency, database descriptor exclusion and parent death while
stdout is blocked. Failure preserves originals and prior search results. No helper
is given a workbook mutation API. This process boundary is not a security sandbox.
The precise limits and remaining parsing paths are in [[records/specs/search]].

## Conversation and Threads controls

Conversation is the continuing main history. Use Start a thread in its menu or
submit Start a thread called What if we raise prices? through text or dictation.
Let's explore this separately opens the naming sheet. Go back to our main
conversation returns without merging the histories. Chapters remain optional.

Share summary with conversation opens a review field seeded from a completed
answer; edit it to the selected findings before sharing. A completed exchange's
context menu can select a different original. Alternatively submit Share summary
with conversation: followed by the exact summary; this explicitly shares those
words from the latest completed thread answer. The result links to the original
exchange and does not accept business data or invoke inference.

The CLI advertises thread WORKBOOK TITLE MESSAGE_ID and share-summary WORKBOOK
MESSAGE_ID TEXT. Quote the selected text as one argument. The older tangent spelling
and persisted IDs remain supported. Existing workbooks need no data migration.

## Conversation keyboard and assistive actions

Command-L focuses Message Sevra in the active workbook. Each message has an actions
menu containing its links and available exchange actions. The native Conversation
menu offers the same actions for the twenty most recent visible exchanges, plus
Back to Conversation. Its contents follow the active workbook and clear on close.

Inspect messages with their speaker/status grouping, link roles and named assistive
actions. Test exact evidence locators and original-message navigation, not merely
menu presence. Run sevra-preview-checks for formatted/Unicode labels, deduplication,
2,000 distinct links and unsupported-route refusal. The full local suite includes
these checks. Real UI coverage and remaining VoiceOver/keyboard limits are recorded
in [[records/operations/implementation]].

## Structured CSV/XLSX helper checks

File table parsing shares sevra-extract with text indexing. Keep the helper next
to both the app and CLI executable. The existing extraction check executable now
also covers CSV/TSV fidelity, exact EOF limits, failed structured publication,
source changes during parsing, dense blank expansion and cancellation. Core checks
exercise XLSX saved values, formulas, dates, overflow and shared-string expansion.
Run scripts/check_extraction_package.py for each built product directory to verify
both installed helper layouts and actual CLI table import with build-tree reads
denied. The public CLI does not require Python; this script is development tooling.


## Thread and history navigation, October 27

Start a thread now opens directly from a message with a provisional title. Use its
menu to rename it; Back to conversation restores the main draft and reading state.
The thread identity and return control remain visible in workspace-focus mode.
Command-Option-F searches the active conversation. Next/Previous matches browse
20 snippets at a time; choose a result to open its original. The transcript's earlier
and later controls move through bounded windows, and Return to latest resumes the
newest exchanges. No model setup is required for these native actions.

The app and both packaged CLIs share the core operations:

```sh
sevra start-thread Workbook.sevra MESSAGE_ID
sevra start-thread Workbook.sevra MESSAGE_ID "Delivery dates"
sevra rename-thread Workbook.sevra THREAD_ID "Supplier scenario"
```

The existing `thread WORKBOOK TITLE MESSAGE_ID` command and `tangent` alias remain
compatible. `history-search WORKBOOK CONVERSATION_ID QUERY [CURSOR]` retains its
agent-oriented history behavior, including tool receipts. The native search limits
its own results to visible transcript roles. These controls do not establish the
full ordinary-language or voice journey; see [[records/specs/product]].


## Nearby source-copy model checks

After the actual-tool grammar checks, run the synthetic nearby probe with a new
output directory while no other inference/build owns the host:

~~~sh
.build/debug/sevra-agent-checks --document-composition \
  /path/to/native-models /path/to/libllguidance.dylib /path/to/engine/splash \
  .build/new-composition-probe
~~~

The three requests ask for literal English and Spanish quotation, then a permitted
paraphrase. The model chooses every tool and argument. Literal cases require an
actual saved copy reference and exact decomposed-Unicode/CRLF text; paraphrase
requires no copied identifier or original passage. Embedded source instructions
cannot accept an unrelated draft. Inputs, outputs, errors, saved drafts and
portable reopen evidence are retained. This is a bounded nearby diagnostic, not
general semantic, latency, memory or full-workflow qualification.


## Inspect copied passages

Open a composed document and expand Copied passages in the right pane. Each
excerpt shows its saved locator and Open original passage. The link opens the
exact version used, even after a new head or refreshed extraction. Earlier
Source and Record viewers show Viewing an earlier version plus the explicit
Open newer version control. Back returns through the normal preview history.
No source IDs or copy tokens are required in the user's request.

Free-text editing creates submitted evidence and a new draft. Original-copy
spans remain on the earlier version through Evidence and history, so edited
prose does not claim stale byte positions. Run sevra-document-checks for the
programmatic consistency/history/edit checks. Visible source navigation, Back,
keyboard, VoiceOver and narrow layout are separate qualification, currently
pending manual Mac unlock in [[records/operations/implementation]].

## Body links and backlinks (introduced in schema 6)

New eligible item bodies parse wiki links and Markdown stable routes automatically.
Existing migrated versions remain unindexed until explicit catch-up. File contents
have separate extraction coverage; these commands do not claim complete asset
link discovery. Keep app and CLI builds matched.

~~~sh
sevra reference-snapshot WORKBOOK VERSION_ID
sevra references WORKBOOK VERSION_ID '{"limit":20}'
sevra backlinks WORKBOOK VERSION_ID '{"targetScope":"logical","historicalOrigins":false,"limit":20}'
sevra backlinks WORKBOOK VERSION_ID '{"targetScope":"exact","limit":20}'
sevra reference-history WORKBOOK VERSION_ID '{"limit":20}'
sevra reference-resolve WORKBOOK VERSION_ID REFERENCE_ID
sevra index-reference-bodies WORKBOOK '{"limit":20}'
sevra rebuild-references WORKBOOK
python3 scripts/check_references.py --cli output/native/bin/sevra
~~~

Replace placeholder paths/IDs with exact returned values. `references` and
`backlinks` options are `limit`, `cursor`, `kind`, `meaning`, `status`, `scenario`,
`targetScope`, `historicalOrigins` and `contentScope` (described below). Incoming filters apply to origin metadata;
outgoing filters apply to destination metadata. Incoming current-origin discovery
is the default. Logical scope includes pins to earlier versions of the target;
exact scope includes a live mention only when the anchor is current. Follow
`nextCursor` with the same options. A changed query or evidence invalidates it.
These are metadata-only discovery results. Read exact versions before citing.
`index-reference-bodies` accepts `afterID`/`limit`; follow `nextAfterID`. It commits
complete origins and skips saved coverage. `index-references WORKBOOK VERSION_ID`
catches up one version. Rebuild never reparses or rebinds saved names.

`annotate-references WORKBOOK SOURCE_VERSION_ID JSON` corrects Source choices
without changing original bytes. JSON requires `selections` and
`expectedSnapshotID` (null for no earlier annotation), with an optional `token`.
A selection has `startScalar`, `scalarCount`, optional `lookup`/preserved `id`,
and optional `target` (`mode`, stable `identity`, optional `workbookID`).
Mode is `live` for a logical ID or `pinned` for an exact version. Source correction
retries preserve the original outcome and stale snapshots refuse.

For Record documents, use `edit-document ... --references JSON_FILE` with an
array of those selections; text and bindings commit atomically as a new draft.
`add` JSON also accepts `references`, `scenario` and `supersedes`. Omitting
references uses automatic body parsing; an explicit empty array means a manual
empty, partial annotation. Reference/selection JSON is bounded to 400,000 bytes.
The repo-owned `skills/sevra/SKILL.md` documents these owner CLI capabilities;
scoped local-model traversal and native link interaction remain separate work.
See [[records/specs/references-and-relationships]] for syntax, coverage and limits.

## Retained file references, schema 7

Imports now capture supported links in bounded extracted text. For an older
workbook or an explicit retry, run extraction for the exact returned file version.
These commands inspect technical annotations without rewriting the asset.

~~~sh
sevra extract WORKBOOK VERSION_ID
sevra file-reference-snapshot WORKBOOK VERSION_ID
sevra file-reference-history WORKBOOK VERSION_ID '{"limit":20}'
sevra file-reference-region WORKBOOK VERSION_ID '{"snapshotID":"SNAPSHOT_ID","region":0,"offset":0,"limit":4000}'
sevra file-reference-resolve WORKBOOK VERSION_ID REFERENCE_ID SNAPSHOT_ID
sevra backlinks WORKBOOK VERSION_ID '{"contentScope":"extracted","limit":20}'
sevra references WORKBOOK VERSION_ID '{"contentScope":"all","limit":20}'
python3 scripts/check_extracted_references.py --cli output/native/bin/sevra
~~~

Use actual returned IDs. Region indexes are zero-based and offsets/limits count
Unicode scalars; follow `nextOffsetScalar`. Regions require a snapshot ID so later
extraction cannot silently change the text being inspected. History takes
`beforeVersion`/`limit` and returns `nextBeforeVersion`. Resolve returns navigation
metadata only. Supported syntax and locators in captured text are not a full scan
of embedded file hyperlinks; partial/unsupported/unindexed input can contain more.
Discovery's separate `fileCoverage.latestExtraction` reports a running or failed
retry even while the previous annotation snapshot remains available.

`annotate-file-references WORKBOOK SOURCE_VERSION_ID JSON` requires a nonnull
`expectedSnapshotID`, `selections` and optional retry `token`. Supply the complete
chosen set. Each entry has integer `region` and nested `selection` with the body
selection fields above. Selection coordinates are relative to retained region
text; the original file and Source remain unchanged. Manual coverage is partial.
An identical retry returns the original snapshot, stale choices refuse, and the
same captured extraction preserves explicit choices. A changed extraction keeps
prior snapshots/regions inspectable. `rebuild-references` rebuilds both body and
file projections without parsing, fetching or binding unresolved labels.

`contentScope` is now an additional references/backlinks option: all (default),
body or extracted. Merge/deduplication and filtering precede pages. Keep schema-7
app/CLI builds matched. The repo's check.sh includes both model-free CLI journeys;
packaged product checks still require building the native layout explicitly.

## Native saved links and Back

Open an item in the right viewer. Supported saved body links display their labels;
choose one to open its saved destination in the same viewer. Assistive technology
gets native link controls over those same saved occurrences. An unresolved label
opens Choose destination where supported. Links opens the optional sheet. Switch
to Mentioned in for bounded incoming pages, with explicit earlier-version and
exact-version filters. Choose destination can correct an existing body or retained
file-text binding. Search and select the actual item; Keep this exact version pins
it, otherwise it follows the item's latest version. Source files remain unchanged;
a Record document change creates a draft. Other Record types need their domain
workflow. Embedded file hyperlink objects are not covered.

Type or dictate Show links, Where is this mentioned? or Go back in the normal
composer. These whole-request shell commands work without inference. Spanish
Mostrar enlaces, Dónde se menciona esto and Volver are also accepted. General
phrasing, arbitrary link authoring and span selection remain future work. Back's
keyboard shortcut is Command+[. Command+Shift+L opens saved links; use arrow keys
and Return to open a selected link or incoming mention. Command+Option+E chooses a
new destination for the selected editable link. Destination search takes initial
focus; type, press Down to select a result, then Return to save. Empty Return makes
no choice, and Escape cancels. Document text scrolling and PDF pages are retained
within this workbook window. A new PDF page locator works even when that file is
already open. Copied passages forward their saved locator when opening originals.

Run swift run -j 4 sevra-document-checks and swift run -j 4 sevra-preview-checks for
focused session, real offscreen AppKit/PDFKit, link choice, provenance, keyset,
cancellation and shell-command checks. Build the native layout before packaged
checks. A focused visible synthetic journey now checks native link activation,
keyboard correction/navigation, exact-version incoming pages, copied-text original
navigation and minimum-width layout. Spoken VoiceOver, new spoken shell commands,
all formats/locators and full uncoached usability remain unqualified. Current
evidence and retained initial failures: [[records/operations/implementation]].


## Local-agent references and focused native probe

The model references tool differs from the owner CLI references/backlinks commands:
it has a fixed 12-result page and excludes request/annotation Sources. It accepts
id, direction, targetScope, historicalOrigins, contentScope, kind, meaning, status,
scenario and cursor. Retain options with nextCursor. Read also supplies its first
canonical outgoing page. These are discovery results; read exact destinations
before citing. Earlier conversation uses history_read. Original asset/body bytes
are unchanged. General linking/span creation by the model remains pending.

The optional development probe exercises a corrected extracted pin, its current
edition, a real mention cycle and a private request pointer. It chooses all model
actions freely and preserves exact responses, history, failures and portable
workbooks in a new output directory. Run from the repository root after building
sevra-agent-checks and the pinned engine/grammar resources:

~~~sh
.build/debug/sevra-agent-checks --reference-traversal "$SEVRA_TEST_MODEL_FOLDER" "$SEVRA_TEST_GRAMMAR_LIBRARY" "$SEVRA_TEST_ENGINE" "$SEVRA_TEST_NEW_OUTPUT"
~~~

Set those variables to explicit local paths. MODEL_FOLDER is the verified legacy
selected target directory with its dflash subdirectory, not an installed models
root. The probe creates a local-pack assembly under its output directory, uses
32K context/bounded512 and 12 GiB configured engine memory, and unloads after the
cases or an error. It does not download weights or qualify fresh native setup,
model throughput, graph-scale memory, installation or release. Two initial wrong
raw-route answers and the first private step-limit failure are preserved; the
final two cases pass with limitations in [[records/operations/implementation]].
Use scripts/check_splash_grammar.py for deterministic actual tool/mask checks.


## Current importer limits and adopted contextual intake

Current app/CLI file intake automatically converts CSV/TSV and XLSX into new tables
after inclusion and extraction. XLSX formulas are retained as evidence with saved
values; they do not recalculate. This is useful development behavior, not full
Excel migration or the final contextual role UX. There is no qualified general
CSV merge planner or start-directly-from-file Welcome action. Selected native
table paste edits an existing bounded range only.

The adopted expanded contract, implementation phases and acceptance cases are in
[[records/specs/contextual-import]]. Until those gates pass, do not describe
reference-only/analysis-only role routing, native Excel formulas/structure, general
range intake or contextual update/merge as implemented. Original inclusion/link
ownership and resumable bounded import checks remain valid in their narrower scope.

## Edit Home and existing spaces

These commands apply to matching current-format baseline/native CLI builds. The
Python-free native preview is built separately below; it is not a qualified
production replacement for the preserved baseline.

~~~sh
sevra spaces /path/to/Work.sevra
sevra space-edit /path/to/Work.sevra home 1 '[{"operation":"move","componentID":"tables","at":"first"},{"operation":"remove","componentID":"recent"}]' home-layout-1
sevra space-history /path/to/Work.sevra home
sevra space-restore /path/to/Work.sevra home 1 2 restore-home-1
python3 scripts/check_space_editing.py output/native/bin/sevra
~~~

Read the actual ID/version first; the example assumes untouched Home/version 1.
A stale base refuses. Retry uncertain results with exactly the same token/arguments.
Move/insert requires at:first, at:last or beforeID; omit unrelated fields. Native
Edit layout provides labels, text, root ordering, addition/removal and bounded
history. Existing grouped compositions remain; chat/CLI can edit nested components.
Restore saves another version. Pending review access remains in the workspace
header even if its Home section is removed. Layout removal keeps underlying data.
The repo-owned [[records/specs/native-app-engine]] tracks forms/actions and remaining
accessibility/engine work. The matching harness skill is skills/sevra/SKILL.md.

## Managed native dataset inspection and repair

Structured table operations use the same managed storage in app, CLI and local
agent tools. Assets stay in assets/. `sevra table-schema WORKBOOK DATASET_ID`
returns current logical columns/version. `sevra table-rebuild WORKBOOK DATASET_ID
EXPECTED_REVISION TOKEN` explicitly rebuilds a projection from retained canonical
versions. Reuse the exact token/base after an uncertain result; a changed base or
dataset under that token refuses. Keep the original workbook during recovery.
Missing canonical authority is not repaired through model inference or reimport.
The repair does not add business effects. `verify` detects projection disagreement;
`reconstruct` creates a new inert current-format workbook with exact saved history.

Development check: `python3 scripts/check_managed_datasets.py --cli PATH_TO_SEVRA
--rows 1000`; a 10,000-row run adds scoped scaling evidence. Supported dataset width
is 1...500 logical columns. See [[records/specs/managed-datasets]] for typed query/index contracts
and remaining qualification work. Older development schemas are preserved
but unsupported; recreate selected synthetic fixtures, never delete user workbooks.

## Versioned table definitions

Current schema is 13, retaining the schema12 managed table lifecycle. `table-schema` returns the exact definition UUID, display
version, title, columns and archive state. `table-schema-history WORKBOOK DATASET_ID
[BEFORE_VERSION]` pages 20 complete definitions newest first.

`table-edit-schema WORKBOOK DATASET_ID BASE_VERSION BASE_DEFINITION_ID OPTIONS_JSON
TOKEN` accepts explicit title, columns or archived options. Columns retain stable
IDs and optional stored-value required/unique constraints. Preserve unrelated fields
and use exact tokens/arguments on retries. Stale bases or changed retries refuse.
`table-restore-schema WORKBOOK DATASET_ID SAVED_DEFINITION_ID BASE_VERSION
BASE_DEFINITION_ID TOKEN` restores an exact definition as a new version.
`tables WORKBOOK --archived` discovers retained archived tables. No raw SQL is exposed.

Native Table actions > Table definition provides title, columns/formulas, required/
unique controls, removal, archive and paginated history. Its opened base is frozen.
Writes run off the UI actor; stale/failing saves keep the draft in the sheet.
A schema restoration preserves the latest retained values for the same column IDs;
it is distinct from selecting an exact historical row version. Ordinary row edits
refuse archived tables. Complete history remains available to reconstruction.

Run `python3 scripts/check_dataset_definitions.py --cli PATH_TO_SEVRA` for synthetic
CLI lifecycle, competing writers, replay/portable reopen and unique-merge Undo/redo
coverage. It is part of scripts/check.sh. See [[records/operations/implementation]]
for the lifecycle receipt, visible native observations and exact remaining scope.

## Typed managed queries and optional indexes

`table-query WORKBOOK QUERY_JSON [CURSOR]` runs the typed host compiler.
`table-query-plan WORKBOOK QUERY_JSON` returns its actual plan. Read table-schema
first and use exact dataset/definition UUIDs. See skills/sevra/SKILL.md for a complete
request example. The query may select up to 50 stored fields across up to three
sources, with AND filters, two equality inner/left joins, grouping, count/sum/average/
min/max and output sorting. Source scope can filter meaning/status/scenario; no
provided scope means all current members. Ungrouped inputs retain exact row/version
references and business metadata. Grouped results identify their exact query/snapshot.

Decimal values are strings. Sum refuses precision loss; average uses Decimal plain
rounding. Text comparisons are case-sensitive. Null and empty remain distinct;
original omitted/lexical cells remain inspectable through version IDs. Query pages
return nextCursor; changing the request, workbook commit or schema refuses reuse.
Calculated columns, arbitrary SQL and unknown request fields refuse.

The core bounds contributing rows at 100,000, referenced inputs at 32 MiB, output
at 8 MiB/1,000 rows, VM instructions at four million and the deadline at three seconds.
A refusal returns no seemingly complete partial answer. SQLite working memory is
not a process-wide hard heap cap. Narrow the request after a bounded refusal.

An explicit maintenance request may use table-optimize with the same query JSON.
The core chooses generated keys, checks actual plan use and dbstat sizes, and retains
only indexes within count/key/storage budgets. table-clear-indexes WORKBOOK DATASET_ID
removes optional performance indexes. Neither command publishes business history.
Column shape rebuilds discard indexes; ordinary edits/repair maintain compatible
ones and evict storage overages atomically. A device without optional size accounting
drops those indexes during row edits. Inert reconstruction needs none of their choices.
Explicit table-rebuild keeps its exact-revision/token contract and has a cancellable
30-second maintenance deadline, with unchanged transaction-capture limits.

Run `python3 scripts/check_dataset_queries.py --cli PATH_TO_SEVRA --rows 1000`.
A 10k/50k run measures range/sort/group/join plans, end-to-end CLI latency, index
bytes, indexed edits/repair, history, RSS, inert reconstruction and portable reopen.
Paired native-column/shared-JSON SQL timings use the same Python SQLite/Decimal
adapter and warm cache, separately from Swift CLI timings. They are not a historical
release-binary speed comparison. Failed stress repair is retained with
--measure-rebuild-limit and reports ok:false; it does not pass the repair gate.

## Packaged query/index qualification

Run `python3 scripts/check_dataset_queries.py --cli output/native/bin/sevra --rows 1000 --output .build/query-1000.json` after the native build.
The same synthetic stored-column probe passed at 10,000 and 50,000 rows. It checks
query plans/results, two optimizer processes, edit/repair, inert reconstruction
and portable export. Use the receipt rather than claiming all indexes improve all
queries: 50k grouping slowed from 0.239 to 0.273 s, while filtered/joined CLI queries
fell from about 0.29 to 0.15 s. Initial 50k repair rolled back at the old three-second
budget; final explicit 30-second maintenance repair took 14.794 s. See [managed query/index receipt](../../../integration/evidence/2026-10-28-managed-query-indexes.json.gz)
and [[records/operations/implementation]] for full timings/resources and limits.
No new native query editor or in-app model tool is implied by these CLI commands.

## Saved application functions and queries

Current schema14 workbooks carry the earlier pure-definition support: `definition-save`, `definition-read`,
`definition-history`, `definition-restore`, `definition-dependencies`,
`definition-search` and read-only `definition-evaluate`. Run `sevra help` and read
skills/sevra/SKILL.md for typed examples, parameter/literal mappings and live/exact
semantics. New definitions use a selected UUID logical ID and base `new`; updates
require the exact opened version UUID. All writes use stable request tokens.
Neither authoring nor evaluation accepts business data or schedules execution.

~~~sh
python3 scripts/check_application_definitions.py --cli output/native/bin/sevra --output .build/application-cli.json
swift build --product sevra-benchmark -j 4
.build/debug/sevra-benchmark --definitions --count 10000 --output .build/NEW-definition-corpus
~~~

Use a new corpus directory. The benchmark exercises actual public-core saves,
FTS/head-filter paging, retained dependency lookup, exact evaluation, verification,
inert reconstruction and portable reopen. Its JSON separates core timings from
packaged CLI process/open observations. Current synthetic 10,001-definition corpus
passes; see [application definition receipt](../../../integration/evidence/2026-10-28-application-definitions.json.gz). These commands do not expose a native
form/definition editor or new in-app model tool. Old development workbooks are
preserved unsupported; create selected fresh synthetic fixtures for schema14.


## Registered draft actions and native receiving form

Use current schema14 fixtures. `action-registry` exposes trusted native primitive
versions, typed inputs/results, effect/capability, deadline and retry semantics.
`receiving-template` and `form-template` return ordinary definitions for versioned
saving. See skills/sevra/SKILL.md for exact receiving arguments, preview/invocation,
function bindings and recoverable `form-draft-*` commands. A saved proposal remains
a draft. No stock change until explicit separate review/acceptance.

~~~sh
python3 scripts/check_application_actions.py --cli output/native/bin/sevra --output .build/NEW-action-cli.json --keep .build/NEW-action-fixture
~~~

The keep directory must not exist. The script creates synthetic receiving evidence,
action/form definitions, a native form-bound space, separate-process racing submits,
exact retries, incomplete/conflicting presentation checkpoints, inert reconstruction
and a portable round trip. Existing fixtures are never migrated or overwritten.

In the native preview, open a fresh current-format workbook, choose Edit layout,
Add section, Receive delivery form, then Save layout. The starter definitions are
saved ordinary catalog objects; the chosen component is added only on layout save.
Select evidence, enter the observed delivery/date/line counts, Preview, then Save
draft proposals. Review drafts separately. Add/remove line and Back preserve inputs.
Changed live definitions require explicit refresh; Keep both handles a competing
window. Crash-after-commit recovery finds the exact saved receipt rather than
resubmitting. The automated session proof passes, but the locked Mac prevented the
visible keyboard/VoiceOver/new-form qualification. No such result is claimed.

The broad schema14 check passed with core217 before a final registry result-schema
metadata refinement. Focused final installed CLI/package checks cover that refinement.
See [registered action and form receipt](../../../integration/evidence/2026-10-28-registered-actions-forms.json.gz) and [[records/operations/implementation]].


## Saved application tools, October28

The native agent can discover, inspect, evaluate and author versioned definitions
and prepare registered action drafts with `prepare_action`. The host previews,
independently reviews inventory direction and commits the exact current-run receipt.
Success supplies exact draft links; accepted stock changes only after review.
Read-only requests refuse saves/preparation. See
[[records/specs/application-definitions]] and [agent application definition receipt](../../../integration/evidence/2026-10-28-agent-application-definitions.json.gz).

Focused repeatable commands after a native build:

```sh
.build/debug/sevra-agent-checks
.build/debug/sevra-agent-checks --application-tools \
  .build/native-fresh-setup \
  .build/upstream/llguidance-1.8.0/target/release/libllguidance.dylib \
  .build/upstream/splash-native-1.4.1/engine/splash \
  .build/application-tools-model-fresh
python3 scripts/check_native_package.py --paths-only
python3 scripts/check_application_actions.py --cli output/native/bin/sevra
```

The model output directory must be fresh. Use the native setup instructions above
for the managed local weights and qualified engine artifacts; these are developer
qualification paths, not runtime dependence on a checkout. The product is Python-free.
The broad `bash scripts/check.sh` includes deterministic core/agent/Splash/native
checks. Real-model timings under concurrent builds are functional observations, not
a new engine-performance qualification. First startup permits360seconds for native
component preparation; cancellation still reaps a stubborn helper within5seconds.

Latest visible keyboard checks cover receiving-form evidence/unsent recovery and
review/accept/undo/restore. Actual VoiceOver and full appearance/media/hardware/
fresh-install/notarized release checks remain open.

## Reusable computation checks
The baseline and separate native candidate expose component-evaluate and definition-publish through the same core. See [[records/specs/application-definitions]] for exact binding/typed arguments, snapshots, current-run receipt publication and bounds. Save result is available for a complete first page and preserves explicit meaning separately from acceptance. Partial pinned pages remain frozen.

After the native build, run python3 scripts/check_computation_views.py --cli output/native/bin/sevra for packaged calculation/query, stale/forged/partial refusals, exact retries, portable reopening and inert reconstruction. The native candidate remains separate from the installed Slotstream baseline until adoption gates pass. Current evidence/limits are linked in [[records/operations/implementation]].

## Manual workflow checks
Run the scoped synthetic checks without opening user data:

```sh
swift build --product sevra-checks -j 3
.build/debug/sevra-checks --workflows
swift build --product sevra-workflow-durability -j 3
python3 scripts/check_workflow_durability.py
swift build --product sevra -j 3
python3 scripts/check_workflow_cli.py --cli .build/debug/sevra --worker .build/debug/sevra-workflow-durability
```

The shared check script and CI include the process-death and independent CLI probes. The native fixture worker is a test executable, not a shipped background helper. CLI help lists workflow-start/read/list/advance/claim/finish/heartbeat/retry/cancel/events. Every advance is one explicit bounded step; reaching review returns waiting_review without accepting proposals. Inspect and accept the exact proposals through the ordinary review path, then deliberately advance again.

Definitions use kind workflow and the contract in [[records/specs/manual-workflows]]. Current development schema17 replaces earlier development schemas without a legacy adapter. Preserve old packages and use a matching earlier development build for recovery. Only recreate selected disposable fixtures. No installed user package is reset or upgraded automatically.

## Manual workflow activity
Use workflow-activity WORKBOOK [STATE|- [CURSOR]] for bounded newest-first pages, workflow-inspect WORKBOOK RUN_ID for exact inputs/steps/proposals/attempts, and workflow-continue WORKBOOK RUN_ID for a deliberate continuation to the next review or terminal state. Read/inspect never resumes a run. Native Activity is accessible beside Review drafts; Continue, Retry unfinished work and Stop workflow use the same trusted core commands. A changed workflow-run family clock requires refresh; agent journal and unrelated writes preserve continuation. Full workflow/automation and accessibility gates remain open.

## Workflow form submission
Use form-template WORKBOOK TARGET_ID for an exact inspected current action or workflow. The returned form follows that target live. Its payload has exactly one action/workflow binding, with identical typed parameters. Save it through definition-save and bind it as a normal native form component. Workflow action steps may use only action-backed forms, preventing hidden recursive workflow execution.

form-draft-preview WORKBOOK STATE_JSON is pure. For a workflow form it checks exact opened definitions and parameters and lists steps; it does not execute queries/model/import/effects. form-draft-submit WORKBOOK STATE_JSON PREVIEW_JSON uses the saved draft's invocation token and creates a queued run plus receipt atomically. Repeating exact submission returns that receipt. Save lastReceipt through the compare-and-set form-draft-save command if using the low-level CLI; native sessions reconcile it after crashes automatically. Continue the returned workflowRunID explicitly. Native Start workflow also deliberately continues under its originating workbook/window; Open workflow remains available after submission. No scheduled/background execution is granted.

## Conversation workflow tools and local-model probe
The agent can find/read/save exact workflow definitions, create associated form templates and queue a requested run. start_workflow returns a saved run and ends with the host-owned no-execution receipt. Open Activity through Workbook > Workflow Activity (Command-Shift-Y), then inspect and explicitly Continue. Opening/reconstructing/queuing never starts a worker. Native form Start is a separate deliberate continuation.

Run swift build --product sevra-agent-checks -j3, then .build/debug/sevra-agent-checks for scripted scope/receipt checks. Use --workflow-tools MODEL_ROOT GRAMMAR_LIBRARY ENGINE NEW_OUTPUT for the three actual-model author/form/queue jobs. MODEL_ROOT is the native installed layout. The output must not exist. It retains results/messages and a synthetic workbook. This is functional32K/bounded512 proof, not throughput or full workflow execution. The final shared check script includes paging/recovery/grammar checks; historical and current evidence is in [[records/operations/implementation]].

## Explicit local AI workflow continuation
workflow-continue WORKBOOK RUN_ID [MODEL_DIRECTORY] uses the shared ProductAI owner and installed native Qwen/DFlash2 engine only for an unfinished interpret step. Native Activity Continue and workflow form Start use the same asynchronous coordinator. Deterministic steps and post-review completion do not require a model. The preserved Slotstream baseline intentionally refuses explicit interpretation; it remains separately usable for its existing features. Agent start_workflow still queues without executing.

Save interpretation/workflow JSON with definition-save and the typed contract in [[records/specs/manual-workflows]]. Interpretation output becomes a draft Record and cannot accept inventory. Inspect workflow-inspect/Activity for exact retained evidence, model, issues and any rejected raw response; Retry is deliberate, not automatic model correction.

Run .build/debug/sevra-checks --workflows for focused core checks and .build/debug/sevra-product-checks for async ownership/lifecycle. scripts/check_workflow_durability.py now includes13 real process-death boundaries, including four preparation boundaries. The agent check runner accepts --workflow-interpretation MODEL_ROOT GRAMMAR_LIBRARY ENGINE NEW_OUTPUT for clear/incomplete actual-model fixtures; it runs normal scripted checks first. The output directory must not exist. This proves bounded task behavior, not throughput. The native packaged CLI imported-file/interpret/propose/review/reconstruct job and focused visible UI observations are retained in [[records/operations/implementation]].

## Conversation interpretation authoring checks
Build sevra-agent-checks, then run .build/debug/sevra-agent-checks for scripted authority, truthful outcomes and compaction checks. Its --interpretation-authoring MODEL_ROOT GRAMMAR_LIBRARY ENGINE NEW_OUTPUT mode runs three actual native-model tasks: author interpretation, compose exact one-step workflow, queue without executing. The output must not exist and retains pre-inference source/runner identity, exact requests/messages/results and two inert synthetic packages. Use the installed model layout,32K and bounded512. This is functional evidence, not throughput. The pinned Python reference generator is test tooling only; the app runtime remains Python-free. See [[records/specs/manual-workflows]].

## Explicit native document preparation workflow
Save an extraction definition through definition-save: kind extraction, exactly one required item parameter, payload {parser: native-v1, file: PARAMETER_ID}. Bind an exact workflow extract step to that definition. The file must already be included as a workbook business item; explicitly include linked files first. workflow-continue and native Continue run the bundled bounded helper without loading a model. workflow-advance alone refuses this asynchronous step. Ready/untruncated preparation returns itemID and exact retained extraction identity. Map {step: PREPARE_ID, field: item} into an interpretation item parameter; the model reads that exact snapshot rather than a later current index. Partial/unsupported/truncated parsing pauses for attention. No original file is deleted or inventory accepted. The baseline preserves its interpretation refusal.

Build sevra-checks/sevra-product-checks/sevra-workflow-durability and run their focused workflow/lifecycle/process-death checks. The shared check suite includes these automatically. Final packaged prepare/interpret/propose/review/reconstruct proof is retained in [[records/operations/implementation]]. Conversation extraction authoring and structured-data/report workflow steps remain separate work.

## Conversation preparation authoring checks
The agent can find/read/save extraction definitions, make exact workflow_template starters and queue their workflows. Explicit Continue owns execution. Authoring inputs, when supplied, are exact existing item-version UUIDs; parameter names belong in parameters/payload, and current request lineage is automatic. Native template starters are tools, not saved definitions to search for.

The sevra-agent-checks --preparation-authoring MODEL_ROOT GRAMMAR_LIBRARY ENGINE NEW_OUTPUT mode runs actual native-model author/workflow/queue jobs. The directory must be new. It retains pre-inference source/runner identities, exact frames, messages, results and synthetic original/reconstructed workbooks. It independently checks metadata, queued pending state, no business Records and unchanged retained file text. Use the installed native model layout,32K and bounded512. The same runner keeps --interpretation-authoring. Functional times do not qualify performance. See [[records/specs/manual-workflows]] for retained failures and exact scope.

## Registered document workflow checks

Run swift build --product sevra-checks -j 3 and .build/debug/sevra-checks --document-actions for focused invariants. scripts/check.sh includes scripts/check_document_actions.py --cli .build/debug/sevra and 15 workflow process-death boundaries. Use python3 scripts/check_document_actions.py --cli output/native/bin/sevra --model-root MODELS_ROOT --output NEW_DIRECTORY for the explicit actual native six-step receiving/report job. The output directory must be new; retain prior results. It uses synthetic evidence and explicit synthetic human review, not user data. Without --model-root, the check exercises document form/workflow/review and keeps stock unchanged without inference. GitHub checks run the default job against the baseline and native packaged CLI products.

The actual qualification output is .build/document-actions-native-model-v2, with 37 independent CLI calls; its immutable receipt is linked from [[records/specs/manual-workflows]]. The final frozen-source native build is document-action-v8; final whole shared checks are document-action-v11. Earlier diagnostics remain retained. Native resource tests are paths-only; latest UI/VoiceOver and full engine/performance release qualification remain open.

## Reviewed workflow intake checks

Build sevra-checks and run .build/debug/sevra-checks --workflow-intake for 21 focused direct-table/workflow groups. The shared scripts/check.sh runs the full 289 core groups and scripts/check_workflow_intake.py --cli .build/debug/sevra, plus 21 actual workflow SIGKILL boundaries. Product lifecycle checks exercise a delayed real child parser, independent writer and cancellation without model loading.

After bash scripts/build_native.sh, run python3 scripts/check_workflow_intake.py --cli output/native/bin/sevra --model-root MODELS_ROOT --output NEW_DIRECTORY for the synthetic six-step preparation/interpretation/intake/review/report/review job. MODELS_ROOT is the installed native model layout. Output must not exist. Omit --model-root for the deterministic form/intake/review/reconstruction path with no inference. Explicit synthetic reviews occur only in the synthetic fixture. Do not point qualification scripts at user workbooks. The CLI script contains a full valid metadata example; intake-schema details are in [[records/specs/application-definitions]].

The final actual qualification is .build/workflow-intake-native-model-v2, 38 independent CLI calls, with no expected-quantity example in its instruction. V1 remains preserved. Source and CLI identities are captured before inference. Final shared checks are intake-v8, frozen native release intake-v9 and package paths checks intake-v10. Evidence and remaining release limits are in [[records/specs/manual-workflows]]. Conversation intake authoring now has the separate scoped qualification below; its saving/queueing still cannot execute or accept rows. These are functional/ownership checks, not a speed or full Excel-support claim.

## Conversation intake authoring check

Build sevra-agent-checks and run .build/debug/sevra-agent-checks --intake-authoring MODELS_ROOT PINNED_NATIVE_LIBRARY ENGINE NEW_OUTPUT_DIRECTORY. Use installed native model layout. The four actual-model jobs save exact CSV/TSV mapping, compose its exact mandatory-review workflow, queue an included file without executing it, and clarify missing intent under an explicit ask-before-save restriction. The probe verifies unchanged business rows/stock/extraction, exact definition/mapping/inputs, one pending run and inert reconstruction. It retains before-inference identities, exact messages, metrics and failures. Never use user workbooks for qualification. Do not package output/native while this runner uses that runtime. Final evidence and scoped limits are in [[records/specs/manual-workflows]].

## Workflow lookup qualification

Build sevra-checks and run .build/debug/sevra-checks --workflows for focused workflow checks. Run python3 scripts/check_workflow_lookup.py --cli output/native/bin/sevra --output NEW_DIRECTORY for deterministic exact match/repair/review/reconstruction, after bash scripts/build_native.sh. Add --model-root MODELS_ROOT for the synthetic seven-step actual native preparation/interpretation/match/stock-review/report-review job. The output directory must not exist. It captures source/product/runtime identities before inference. It expects a zero-match refusal, repairs only its synthetic catalog, explicitly retries the same run and resumes with an absent model directory to prove completed AI outputs are reused. Synthetic human acceptance occurs only inside the synthetic fixture. Never use user workbooks. scripts/check.sh and both packaged CI products include the default deterministic job. Do not replace output/native while a probe uses its runtime. Current proof/limits: [[records/specs/manual-workflows]].

## Workflow clarification qualification

After building sevra-workflow-durability, run python3 scripts/check_workflow_clarification.py --cli output/native/bin/sevra --worker .build/debug/sevra-workflow-durability --output NEW_DIRECTORY for the deterministic submission/review/reconstruction job plus two SIGKILL boundaries. The default worker produces a clearly labeled synthetic missing-information response. Add --skip-crashes to reuse unchanged death proof. For actual local inference use --model-root MODELS_ROOT --skip-crashes and omit the worker. The script captures source/product/pin identities before inference. All values, acceptances and files are synthetic; CLI attribution remains programmatic. Native and baseline packaged CI and scripts/check.sh include the deterministic job. workflow-clarification reads the exact target; workflow-clarify supplies target JSON, values JSON, reason and retry token. Never substitute user data or replace output/native during a probe. See [[records/specs/manual-workflows]].

## Native clarification verification

Freeze all Swift sources before builds. Sequentially run swift build --product sevra-preview-checks, .build/debug/sevra-preview-checks, swift build --product sevra-checks, .build/debug/sevra-checks, scripts/build_native.sh, python3 scripts/check_native_package.py --paths-only and swift build --product sevra-workflow-durability. Then run python3 scripts/check_workflow_clarification.py --cli output/native/bin/sevra --worker .build/debug/sevra-workflow-durability --skip-crashes --output NEW_DIRECTORY. The new headless native checks cover incomplete/stale input, original-evidence scope, cross-window alternatives, exact receipt recovery, and failed-save switch/quit gates. Core checks cover bounded receipt/cache retention. V9 frozen proof passes302 core groups and27 deterministic calls; latest visible editor/keyboard/VoiceOver/appearance checks remain open. Reuse unchanged actual-model and process-death evidence only when its code boundary is unchanged. Full details: [[records/specs/manual-workflows]].

## Conversation answer preparation verification

Run the existing focused workflow, agent, native grammar and headless preview harnesses after freezing all changed Swift sources. Build/package sequentially, then run python3 scripts/check_conversation_workflow_answer.py --cli output/native/bin/sevra --worker .build/debug/sevra-workflow-durability --model-root .build/native-fresh-setup --output NEW_DIRECTORY. Model weights must already be installed; the script performs no hidden download. Do not rebuild/replace native products during inference or run simultaneous GPU jobs. It records source/product identities, uses disclosed synthetic paused interpretation fixtures, tests actual current-message preparation plus a read-only counterexample, and verifies unchanged runs/balances and inert copies. It does not confirm, continue or accept inputs. Final V6 passes30 CLI calls/two cases. Voice/text confirmation and latest visible checks remain open. See [[records/specs/manual-workflows]].

## Previewing and confirming answers in conversation

Open a paused workflow with complete saved input values and an explanation. Say or type Preview my answer in the main composer. Check the host-generated values, exact document links, explanation, meaning and scenario. Then send Save my answer or Confirm my answer as its own message. This uses no model. A bare yes does not submit. Edits, another message or leaving the context require a fresh preview. Only the supplied interpretation completes; Continue and business review remain separate. Native Preview answer / Save my answer controls remain optional equivalents.

Final automated checks pass66 workflow groups plus native session/context invalidation, canonical fault/cancellation, exact receipt and inert reconstruction cases. The actual packaged-model preparation/read-only jobs pass30 calls with corrected paused-state wording in those cases; no actual native microphone/window interaction is claimed while UI access is locked. Use existing workflow, agent, preview and native-package commands, freezing sources before builds. The two V3 display/invalidation deltas have final core/preview/native/package proof and reuse V2 model/agent/deterministic evidence. Exact evidence and limits: [[records/specs/manual-workflows]].

## Preview native calendar schedules

Use `output/native/bin/sevra schedule-preview '{"policy":"native-calendar-v1","timeZone":"America/Bogota","hour":9,"minute":0,"recurrence":{"kind":"weekly","weekdays":[1,2,3,4,5]}}' 2026-10-29T12:00:00Z 5` for the next five weekday mornings. The command also accepts @PATH to an explicitly selected regular UTF-8 JSON file up to64 KiB. It does not take a workbook path or require a model. Count is1 through100 and optional horizon is1 through3660 local days. A horizon result can be empty without establishing there are no later occurrences. Local date slot keys still need an exact automation/trigger-version identity before durable dispatch.

Focused checks: `swift build --product sevra-checks -j 4`, `.build/debug/sevra-checks --schedules`, then after a frozen native build `python3 scripts/check_schedule_preview.py --cli output/native/bin/sevra --output NEW_DIRECTORY`. Final13 groups and31 packaged calls pass. Existing package/refusal/signature checks pass; no UI activation or background execution is implemented here. See [[records/specs/automation-schedules]].

## Saving inert automation definitions

Use the existing definition-save command with kind automation, title/description, parameters [] and payload {policy:calendar-drafts-v1,workflow:{mode:exact,versionID},arguments,schedule}. Arguments must satisfy the exact workflow signature; use exact local item versions, not paths or logical item IDs. Schedule uses the native calendar contract. Save is metadata only. Search with definition-search WORKBOOK QUERY followed by options JSON containing kind automation; read, history and restore use existing definition commands.

Use `output/native/bin/sevra automation-preview WORKBOOK EXACT_DEFINITION_ID 2026-10-29T12:00:00Z 5` to inspect pinned normalized inputs and next dates without execution. Enabled fields are rejected. The agent save tool intentionally cannot create this kind yet. Native configuration and activation are still pending.

Focused checks: `.build/debug/sevra-checks --automations` and `python3 scripts/check_automation_definitions.py --cli output/native/bin/sevra --output NEW_DIRECTORY`. The schema19 checkpoint passes all326 core groups,8 focused automation groups,36 installed automation and31 calendar calls, strict10-file lint and native package checks. No existing user workbook is reset; old development formats require their matching build. See [[records/specs/automation-definitions]].

## Inspecting saved calendar preparation

Use `automation-list WORKBOOK [AFTER_ID_OR_-] [LIMIT]` to discover at most50 saved activations per page. Inspect an exact ID with `automation-activation WORKBOOK ACTIVATION_ID`. Armed state is preparation intent only; output explicitly requires a session and does not mean a timer or workflow is running. Use `automation-occurrences WORKBOOK ACTIVATION_ID [AFTER_ID_OR_-] [LIMIT]` for original/decision Sources and skipped reasons. `automation-events WORKBOOK [AFTER_SEQUENCE] [LIMIT]` pages the transactional outbox. All reads are bounded and mutation-free.

`automation-pause WORKBOOK ACTIVATION_ID EXPECTED_GENERATION TOKEN` revokes prior planning permission and skips a pending request. It records the programmatic CLI caller and never guesses a human identity. Repeating an exact current token recovers its receipt; a superseded decision refuses. No Enable/Run CLI control is offered that would imply an operational scheduler. Authorize/prepare currently remain explicit shared-core APIs for the foreground integration that is still required.

Focused checks: `.build/debug/sevra-checks --automation-planning` and `python3 scripts/check_automation_planning.py --cli output/native/bin/sevra --checks .build/debug/sevra-checks --output NEW_DIRECTORY`. Fixtures are synthetic and selected into a new directory. The schema20 slice has343 full core groups at V4,17 final focused groups and33 final installed CLI cases plus final native package proof. See [[records/specs/automation-planning]].

## Explicit foreground automation execution

Use `automation-preview` and inspect exact definitions/arguments first. `automation-run-once WORKBOOK EXACT_DEFINITION_ID EXPECTED_GENERATION START_AFTER OBSERVED_AT TOKEN [--allow-ai [MODEL_DIRECTORY]]` explicitly authorizes one bounded foreground operation. Generation is0 initially; later inspect automation-activation. Times need an explicit zone, observation at/after start, token1...240 UTF-8 bytes. The optional model path requires --allow-ai, and AI interpretations require that explicit allowance. Use actual observation times honestly; synthetic past observations do not prove a real-time scheduler.

The operation prepares at most100 slots/3660 days, then dispatches/continues at most one eligible run, stopping for review/attention/completion. If catchUpRemaining=true it dispatches nothing: inspect progress before another explicit operation with refreshed generation/new token. Every new operation is a new authorization; a future native timer must retain its verified grant rather than using this command for routine polls. Recover with the original exact token/arguments. A superseded authorization refuses. One active waiting/failed run prevents overlap. No timer is installed and permission ends with the process. Business proposal acceptance remains separate.

`workflow-inspect WORKBOOK RUN_ID` exposes original invocation policy/origin and each latest claim's authorization metadata. A business `read` intentionally refuses those technical Sources. Explicit manual Continue creates new manual-operation provenance for that run, preserving original scheduled policy and leaving future automation disabled/paused. Direct Stop creates no execution grant. Saved armed state alone is not proof of a running timer or permission. See [[records/specs/automation-execution]].

Focused qualification: `swift build --product sevra-checks -j 4`, `.build/debug/sevra-checks --automation-execution`, `swift build --product sevra-automation-durability -j 4`, `python3 scripts/check_automation_durability.py --output NEW_DIRECTORY`; after a frozen native build run `python3 scripts/check_automation_execution.py --cli output/native/bin/sevra --checks .build/debug/sevra-checks --worker .build/debug/sevra-automation-durability --output ANOTHER_NEW_DIRECTORY`. The death script kills only its owned synthetic worker at dispatch publication barriers. Neither script uses user workbooks or real model inference. Final16 focused/all359 core,2 death boundaries/16 calls and44 installed execution calls pass. Native timer/device controls and whole release remain open.

## Native Schedules preview

In the native preview, open a workbook, choose Activity, then Schedules. Create a schedule using an existing saved workflow, typed inputs, named time zone and daily/weekly/monthly/yearly recurrence. Preview shows bounded upcoming local/UTC times and DST adjustments. Save retains inert intent. Enable on this Mac separately authorizes the exact saved version and inputs, with local AI off unless explicitly allowed. Edits create a new immutable version and need a new enable. A currently active older version must finish or be stopped before changing its scope.

Registered on this Mac lists workbook and schedule names, status, Open workbook and Pause/removal. Device status is checked against exact current authority, not inferred from an armed row. Reopening the same physical workbook restores its grant without another authorization. Copied, reconstructed, symlinked, replaced or inaccessible packages cannot borrow it. Renames may work through passive bookmark resolution when both physical objects match; the app does not scan disks. Private registration lives under Application Support for the app bundle identifier, in DeviceSchedules, outside workbooks. It is intentionally not portable workbook content.

Pause removes this Mac's grant before attempting the workbook's exact-generation pause. Missing/replaced workbooks may prevent recording that pause while local scheduling is disabled; the message states both outcomes. An unknown registry publication result is reported as unconfirmed and actual state is reloaded. Run once is a separate manual request and does not consume a calendar occurrence or enable future runs. Continue, retry, Stop and business review remain explicit existing controls.

This implementation currently runs automatic work only while Sevra is active with a key window, no interactive operation, normal memory pressure, acceptable thermal state and Low Power Mode off. Focus/sleep/session/resource loss cancels/defer work; app quit stops it. One app-wide owner serializes automatic work and yields to interactive work. Closed-window/background behavior, event/condition triggers, voice/conversation authoring and real native lifecycle/visible accessibility remain unqualified. Do not use this preview for unattended scheduling assumptions.

Focused checks: `swift build --product sevra-automation-ui-checks -j 4` then `.build/debug/sevra-automation-ui-checks`. They create synthetic workbooks and private temporary registries, run six independent registration workers and kill only owned fixture processes at two registry publication barriers. An injected deterministic runner checks controller behavior without loading a model or simulating proof of real OS notifications. The checks also run in scripts/check.sh and CI. Contract/evidence: [[records/specs/native-automation-owner]].

## Inert condition transition preview

`condition-preview RULE_JSON_OR_@FILE OBSERVATIONS_JSON_OR_@FILE` previews supplied numeric observations without opening a workbook or enabling anything. Example:

~~~sh
sevra condition-preview \
  '{"policy":"native-condition-v1","scope":"stock:bolts","operator":"<","threshold":"10"}' \
  '[{"id":"first","value":"20"},{"id":"second","value":"5"},{"id":"third","value":"4"}]'
~~~

This returns one transition candidate. Starting already below the threshold establishes a baseline; staying below does not repeat. A known false observation resets it. Unknown values use null plus a reason, preserve the last certain truth and label a coverage gap. Same ID/equivalent normalized content is duplicate delivery; changed content under the same ID refuses. Operators are <, <=, >, >=, = and <>. Decimal values are strings, never JSON numbers.

At most 100 observations and 64 KiB encoded observation input. IDs/scope are nonempty bounded strings; unknown reasons are bounded. Each inline/file JSON argument is limited to 64 KiB. @FILE reads require a regular file and refuse symlink/FIFO/directory substitutions. Output says fixture-observations, businessEvidence=false, enabled=false and execution=inert. Supplied IDs/order cannot prove that an actual business crossing occurred or that all events were observed.

Focused verification: `.build/debug/sevra-checks --conditions` and `python3 scripts/check_condition_transitions.py --cli output/native/bin/sevra --output NEW_DIRECTORY`. The first passes 13 groups including 243 trajectories; the second passes 31 installed CLI cases. It uses synthetic inputs and no model/workbook. Real trigger delivery, durable cursors and native authoring remain open under [[records/specs/condition-transitions]].

## Committed business-event inspection

`business-batches WORKBOOK [AFTER_BATCH_ID|-] [LIMIT] [SCOPE_KIND SCOPE_KEY]` lists global or exact-scope semantic batches. `business-batch WORKBOOK BATCH_ID [AFTER_ORDINAL|-] [LIMIT]` pages every entry in one atomic batch. Use - for an absent cursor. Batch limits are 1 to 50; entry limits 1 to 100. Finish an entire batch before evaluating conditions or advancing consumer state. Position strings are lossless. Reads create no acknowledgements or authority. Exact scope meanings, tail/cursor coverage, 8 MiB and three-second query bounds and transient busy/cancellation behavior are in [[records/specs/business-events]]. Dataset scopes select membership/schema, while row-value versions are record-scoped.

Run `.build/debug/sevra-checks --business-events` and `python3 scripts/check_business_events.py --cli output/native/bin/sevra --worker .build/debug/sevra-checks --output NEW_JSON_PATH` for synthetic qualification. The installed script uses its own temporary fixtures, six concurrent CLI publishers and two actual process deaths. No model or automatic condition execution. Schema22 development files preserve/refuse unsupported versions without adapters or reset.

## Historical inventory inspection

`inventory-at-batch WORKBOOK BATCH_ID SUBJECT EFFECTIVE_THROUGH` answers using the exact committed batch and mandatory explicit business date/time. Example: `sevra inventory-at-batch Shop.sevra BATCH_ID bolts 2026-10-29`. Obtain an exact batch ID through business-batches. The result retains basis and effect IDs, both coordinates and an inert label. Missing/removed/future bases are unknown with null quantity. Accepted estimates, other scenarios, drafts and fake movement labels do not affect actual stock. Future dates describe an explicit ledger projection.

Run `.build/debug/sevra-checks --inventory-event-state`, `.build/debug/sevra-checks --inventory-event-limit` and `python3 scripts/check_inventory_event_state.py --cli output/native/bin/sevra --output NEW_JSON_PATH`. The separate scale group creates disposable real workbook history and checks all 10,000 effects plus explicit refusal at 10,001. No model or activation. See [[records/specs/inventory-event-state]] for limits, retained query failure/fix and qualification scope. This reconciliation oracle is not a live per-poll scheduler.

## Explicit inventory condition tracking

These commands save and advance an inert condition; they do not enable a schedule, run a workflow or accept business changes:

~~~sh
sevra condition-create Shop.sevra parts '{"policy":"native-condition-v1","scope":"inventory:parts","operator":"<","threshold":"10"}' 2026-10-29 CREATE_TOKEN
sevra condition-step Shop.sevra CONSUMER_ID 2026-10-29 STEP_TOKEN
sevra condition-state Shop.sevra CONSUMER_ID
sevra condition-observations Shop.sevra CONSUMER_ID - 20
sevra condition-dismiss Shop.sevra CANDIDATE_ID 'Reviewed and dismissed' DISMISS_TOKEN
~~~

Creation returns CONSUMER_ID and captures the current business-tail baseline. Repeat bounded steps with fresh tokens while hasMore is true; retain each original token/arguments to recover its original receipt on retry. Inspect condition-state afterward for current coverage. phase exposes unfinished batch/clock/rebuild work; lastCompleteObservation and effectiveThrough describe the last fully published result, while workingEffectiveThrough is explicitly separate. A backwards horizon refuses. A future horizon is an explicit ledger projection, not physical current stock proof.

condition-observations accepts an optional exact observation cursor and a limit of 1 to 50. A request candidate stays inert. At 100 pending candidates, backpressure stops progress without losing the crossing. Explicit dismissal needs a reason and keeps its Source/history. Saving/reconstructing creates no timer, model acquisition or device permission. Current projection is bounded to 10,000 effects; unsupported precision or limits refuse without partial completion. See [[records/specs/inventory-condition-consumers]].

Run `.build/debug/sevra-checks --inventory-conditions`, the separate `--inventory-condition-limit`, and `python3 scripts/check_inventory_conditions.py --cli output/native/bin/sevra --worker .build/debug/sevra-checks --output NEW_JSON_PATH`. The worker adds actual SIGKILL publication checks; all workbooks and inputs are temporary synthetic fixtures. No selected-model inference.

## Inspect automatic derivation ancestry

Use `sevra automation-ancestry Shop.sevra EXACT_ITEM_ID [EXACT_ITEM_ID...]` to inspect up to 16 exact versions. It reports saved automatic workflow/definition/logical/occurrence bindings and the retained graph, including control/configuration dependencies. Acceptance/manual derivation does not clear origin. This is a read-only diagnostic: execution=none, enabled=false, minimalCausalSlice=false and dispatchEligibility=not-evaluated. It cannot enable work or establish a minimal business cause set.

Limits are 1,024 distinct items, 4,096 edges, 128 lineage-edge depth, 1 MiB invocation metadata and 8 MiB output within a short-wait/cancellable three-second read. Cycles, missing/inconsistent/erased bindings and unsupported sizes refuse without partial output. Current schema 24 uniquely indexes workflow source identity. Unsupported older development files remain preserved/refused; do not reset a user's file.

Focused check: `.build/debug/sevra-checks --automatic-ancestry`. Installed check: `python3 scripts/check_automatic_ancestry.py --cli output/native/bin/sevra --worker .build/debug/sevra-checks --output NEW_JSON_PATH`. The worker creates only a temporary synthetic registered action/review fixture, with no model inference. See [[records/specs/automatic-ancestry]].

## Inspect retained automatic charges

Use `sevra automation-causality Shop.sevra EXACT_RUN_ID` to inspect an admitted automatic run, roots, direct automatic parents, depth and current retained charges. This is read-only historical inspection with execution=none, enabled=false and dispatchEligibility=not-evaluated. It grants no device/session authority. Ordinary calendar occurrences each start an independent root. Pause/completion/cancellation/restart/copy do not clear earlier charges.

Schema25 uses policy automation-causality-v1 with at most eight parents/eight roots/depth eight/eight direct successors/32 runs perroot. Exhausted or inconsistent histories refuse. Internal inherited admissions remain a trusted core primitive, not a public condition dispatch command. Unsupported schema24 files are preserved/refused without migration/reset.

Focused checks: `.build/debug/sevra-checks --automation-causality`. Installed check: `python3 scripts/check_automation_causality.py --cli output/native/bin/sevra --checks .build/debug/sevra-checks --output NEW_DIRECTORY`. The latter creates synthetic fixtures and races nine independent trusted test writers for eight slots. It uses no model and does not establish automatic business-cause discovery. Process-death dispatch checks also verify retained admissions. See [[records/specs/automation-causality]].

## Inspect exact condition change inputs

Use `sevra condition-inputs Shop.sevra EXACT_OBSERVATION_ID [AFTER_INPUT_ID|-] [LIMIT]` for a stable read-only page of one to50 exact scope-relevant changed inputs. Read observation IDs through condition-observations. The result includes exact event/before/after/activation coordinates and immediate previous/previous-certain observation links. It reports execution=none, enabled=false, minimalCauseSet=false, automaticParents=not-resolved and dispatchEligibility=not-evaluated.

Coverage is baseline, complete, unknown-gap or limit-exceeded. A complete window lists relevant changes, not every unchanged numeric contributor or a minimal automatic cause. At most10000 entries are retained per window; overflow keeps exact numeric processing but marks the retained prefix incomplete. Unknown/overflow history cannot grant execution or establish independent origin. Schema25 files are preserved/refused with no migration/reset.

Focused checks: `.build/debug/sevra-checks --condition-inputs`; actual boundary: `.build/debug/sevra-checks --condition-input-limit`. Installed check: `python3 scripts/check_condition_inputs.py --cli output/native/bin/sevra --worker .build/debug/sevra-checks --output NEW_RESULT.json`. It creates only synthetic fixtures, pages205members, uses six readers and tests inert copies/corruption refusal. Existing installed condition process-death tests now also verify input atomicity. See [[records/specs/condition-transition-inputs]].

## Inspect named roles and verify complete input capture

`sevra lineage Shop.sevra EXACT_ITEM_ID` and the existing `sevra automation-ancestry Shop.sevra EXACT_ITEM_ID [ITEM_ID...]` now render named data/control/producer/revision arrays. The broad ancestry inspector continues to include control links and does not resolve business causes or dispatch eligibility. `sevra verify Shop.sevra` checks each item's complete role/revision seal. Schema26 development workbooks are preserved/refused; there is no migration/reset command.

Focused core: `.build/debug/sevra-checks --derivation-roles`. Installed check: `python3 scripts/check_derivation_roles.py --cli output/native/bin/sevra --worker .build/debug/sevra-checks --output NEW_RESULT.json`. It creates disposable synthetic fixtures, independently recomputes canonical seals, checks named role output and unchanged commits, reconstructs inertly and refuses damaged copies. scripts/check.sh and both packaged CI paths include it. Role-aware bounded business-origin/condition resolution is still pending. See [[records/specs/business-provenance]].
