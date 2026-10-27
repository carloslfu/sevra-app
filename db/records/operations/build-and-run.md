---
type: operational
id: 01m5refyq97sez3da1rywz08wf
created: 2026-10-25T02:33:33.673437+00:00
updated: 2026-10-27T05:06:04.031394+00:00
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

The native fixtures compare 15 exact prompts, 80 streaming decodes, 31 output
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
