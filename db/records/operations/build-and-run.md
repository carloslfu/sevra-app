---
type: operational
id: 01m5refyq97sez3da1rywz08wf
created: 2026-10-25T02:33:33.673437+00:00
updated: 2026-10-26T20:39:53.646273+00:00
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
workbook tools add 23 grammar scenarios and 217 exact mask comparisons, plus
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
