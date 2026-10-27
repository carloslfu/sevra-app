---
type: operational
id: 01m5refyq97sez3da1rywz08wf
created: 2026-10-25T02:33:33.673437+00:00
updated: 2026-10-27T13:48:18.927527+00:00
summary: Source installation, local AI setup, independent CLI use, verification and uninstall.
title: Build and run
---
# Build and run

The commands below describe the current Slotstream development baseline. The
adopted Python-free Splash integration is being implemented under
[[records/specs/splash-integration]]; do not claim these commands already use it.


The development app targets Apple Silicon Macs. macOS 14 is the declared minimum;
the current verified host is macOS 26.6.2, 48 GB unified memory, Swift 6.3.3.
Older OS versions and smaller memory profiles are still qualification targets.
The inference engine chooses a hardware plan; a token-per-second claim requires
measurement on that hardware.

## Source installation

Install Apple's command line developer tools if absent. Use a Swift 6.3 toolchain,
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
installation. The benchmark is synthetic and creates temporary workbooks.

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
native request's metrics. The shared agent now performs automatic context maintenance. The 8K adaptive
threshold and larger-profile qualification limits are described in
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
