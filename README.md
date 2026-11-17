# Sevra

**A local AI workbook for your business.**

Put your business files to work. Keep them on your Mac. Compare costs, find
answers in your documents and build small native apps for recurring tasks, with
sources and calculations you can inspect.

[Website](https://www.sevrahq.com) ·
[Try the preview](#try-the-native-mvp-preview) ·
[Example walkthrough](db/records/operations/build-and-run.md#native-mvp-supplier-comparison)

**MVP 0.1 source preview.** Free and open source under the [MIT license](LICENSE).
Built from source for a compatible Mac, with no notarized production installer yet.

![Sevra's native preview with the Willow Workshop sample workbook, a supplier comparison table and a cost chart.](docs/images/native-preview.png)

*Inside the native preview. Sample data shown.*

## Why Sevra

- **Your files and AI stay on your Mac.** Ask questions about business documents
  with local AI. After setup and the model download, inference works offline.
  There is no hosted-model fallback or in-app telemetry.
- **Answers you can inspect.** Follow citations to the original documents and
  check the inputs behind a calculation. Review important results before acting
  on them.
- **Useful work becomes a reusable tool.** Keep tables, charts and small native
  apps in the workbook. Use an app's controls or operate it through conversation.
  Enabled apps can run without the AI model.
- **A workbook you own.** Included originals, business records, results and app
  code travel together in a portable workbook. You review an app's access before
  enabling it, and execution permissions stay on the Mac where you approved them.

For a first job, bring two supplier quotes, compare their totals including
shipping, inspect the evidence and keep the comparison for your next order.

## Try the native MVP preview

### Requirements

- Apple M3 or newer and macOS 26.4 or later.
- Swift 6.3, Git, Python 3 for build tooling, and Rust 1.96.0 through rustup.
- Network access for the initial build, dependencies and model download.
- **21.48 GB for model weights**, plus build and runtime working space.

The current tested host has **48 GB of unified memory**. Other memory profiles
remain unqualified. Installed inference uses the native Splash C++/Metal engine
through Swift, without a Python runtime.

### Install from source

For a fresh checkout:

```sh
git clone https://github.com/carloslfu/sevra-app.git
cd sevra-app
rustup toolchain install 1.96.0 --profile minimal
bash scripts/install.sh --native
open "$HOME/Applications/Sevra Native Preview.app"
```

If you already have a checkout, use that checkout. Quit the running preview
before updating it. The installer builds and installs the native app and its
matching CLI at `~/.local/bin/sevra`. It refuses to replace an unrelated app or
CLI. Source builds are locally ad-hoc signed.

Use `~/.local/bin/sevra version` to check the installed workbook CLI if another
program named `sevra` appears earlier in your shell's PATH. See
[Build and run](db/records/operations/build-and-run.md) for build-only commands,
resource verification, updates and uninstall instructions.

### Set up local AI

In Settings, choose **Download model**, or **Verify model files** when files are
already present. To reuse compatible Qwen3.6 35B A3B 4-bit weights with DFlash 2,
expand **Model files and storage > Use existing model files…**.

Models stay outside your workbooks. Import, search, tables, calculations and
saved results also work without setting up AI.

### Your first workbook

1. Choose **Start from files**, select the [sample CSV and PDF](examples), and
   save a workbook. The files are included and indexed.
2. Open the quotation and ask for a cited summary. Compare goods plus shipping,
   checking the source and inputs. Unknown tax stays unknown.
3. Keep a working table or chart, edit an input and check the recalculated result.
   Try Undo, then close and reopen the workbook.
4. Export and reopen a portable copy to keep the evidence and work together.

Follow the [supplier comparison walkthrough](db/records/operations/build-and-run.md#native-mvp-supplier-comparison)
for the exact steps. Focused questions work best. A broad request can miss a
file, so inspect the original evidence before relying on an answer.

## Build a native mini app

Add an **.xlsx or .xlsm** file and describe how you use it. Sevra preserves the
original and can use its imported tables and supported calculations to build a
small native app. You can also choose **Just use the tables** without a model.
The [Excel flow](db/records/specs/single-excel-import.md) explains the process.

For a new tool, describe its fields, actions and tables. The local model writes
an app, runs isolated synthetic checks and reviews the result before saving it.
Review its data access before enabling it. Each changed version needs approval
again. See the [authoring workflow](db/records/specs/local-model-native-apps.md).

You can also import the [Inventory, Jobs and Visual Planner examples](examples/apps)
with **Workbook > Add Native App…**. The interface uses native AppKit controls.
App JavaScript runs in a sandboxed worker, with access scoped to approved data.

Use the controls or ask in chat: “Add Pencils with quantity 3,” “Change it to 5,”
or “Undo that change.” Apps retain one reversible latest transaction, including
after reopening. A new saved transaction replaces the previous Redo. See the
[chat operation contract and qualification](db/records/specs/chat-primary-operation.md).

**Generated apps need your own testing.** Generation can fail or take minutes.
Excel conversion is not full Excel compatibility, and original macros never
execute. Sevra can translate supported formulas and readable macro logic into
local calculations and actions, then compare results against supplied originals.
Those comparisons cover only the tested inputs. External services, unreadable
sources, exact Excel rendering and automatic formula extension to inserted rows
remain limits. See the [reconstruction contract](db/records/specs/excel-application-reconstruction.md)
and [recorded Excel trials](db/records/plans/fresh-excel-batches.md).

## Status and development

This is a source preview for trying bounded workflows. It does not establish
unattended business accuracy, broad hardware support or production readiness.
The [current handoff](db/records/operations/agent-handoff.md) and
[verification register](db/records/operations/implementation.md) distinguish
accepted checkpoints, ongoing work, failures and remaining limits.

Development formats and interfaces may change before the first notarized,
production-ready 1.0 release. Current-format history and originals remain
protected. See the [compatibility policy](db/records/specs/distribution.md#pre-10-compatibility-policy).

The app uses SwiftUI, AppKit and SQLite, with a shared Swift core and CLI.
A `.sevra` workbook contains its database and ordinary included asset files.
A `.sevraz` file is a portable copy. Cloud sync is outside this preview.

For contributors:

- [Build, run and verification commands](db/records/operations/build-and-run.md)
- [Native app SDK](sdk/README.md) and [architecture](db/records/specs/programmable-native-engine.md)
- [Visuals plan and verification](db/records/plans/rich-native-visuals.md)
- [Inference configuration and qualification](db/records/operations/inference-context-execution.md)
- [Repository instructions](AGENTS.md) and [specification store](db/DB.md)

The native app is developed in this repository. [sevrahq.com](https://www.sevrahq.com)
is its marketing website. Slotstream is a separate app and engine.

Report problems in [GitHub Issues](https://github.com/carloslfu/sevra-app/issues).
Include the app version, reproduction steps and a small synthetic example.

## License

Sevra's source is available under the [MIT license](LICENSE). Third-party
components and model weights have their own licenses.
