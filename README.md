# Sevra

**A local AI workbook for your business.**

Sevra brings your documents, working tables and local AI into one Mac app.
Compare supplier costs, find answers in your files and build small native apps
for work you do regularly. Your files and the AI stay on your Mac.

[Website](https://www.sevrahq.com) ·
[Get started](#try-sevra-on-your-mac) ·
[Example walkthrough](db/records/operations/build-and-run.md#supplier-comparison-walkthrough)

Free and open source under the [MIT license](LICENSE). The current Mac preview
is built from source. A notarized installer is not yet available.

![Sevra with the Willow Workshop sample workbook, a supplier comparison table and a cost chart.](docs/images/sevra.png)

*Inside Sevra. Sample data shown.*

## Why Sevra

- **Local AI, including offline.** The model runs on your Mac. Your documents
  are not sent to a hosted AI model, and you can work offline after setup and
  the model download. The app has no telemetry.
- **Answers you can inspect.** Follow citations back to the source documents
  and check the inputs behind a calculation. Change an input and see how it
  affects the result.
- **Tools you can keep using.** Save tables, charts and small native apps for
  recurring jobs. Use an app's controls or ask Sevra to run its actions in chat.
  The native controls on enabled apps work without the AI model running.
- **A workbook you own.** Included files, business records, saved results and
  app code stay together in a workbook you can copy or export. Permission to
  run an app is approved on each Mac and does not travel with the copy.

Start with a practical job: bring two supplier quotes, compare the totals
including shipping, inspect the evidence and keep the comparison for your next order.

<a id="try-the-native-mvp-preview"></a>

## Try Sevra on your Mac

### Requirements

- Apple M3 or newer and macOS 26.4 or later.
- Swift 6.3, Git, Python 3 for build tooling, and Rust 1.96.0 through rustup.
- Network access for the initial build, dependencies and model download.
- **21.48 GB for model weights**, plus build and runtime working space.

The current test Mac has **48 GB of unified memory**. Other memory
configurations have not been validated. Python is used for the build, not for
running the installed model.

### Install from source

For a fresh checkout:

```sh
git clone https://github.com/carloslfu/sevra-app.git
cd sevra-app
rustup toolchain install 1.96.0 --profile minimal
bash scripts/install.sh
open "$HOME/Applications/Sevra.app"
```

If you already have a checkout, use it. Quit the running app before updating.
The installer builds the native app and installs its matching CLI at
`~/.local/bin/sevra`. It refuses to replace an unrelated app or CLI. Source
builds are locally ad-hoc signed.

Use `~/.local/bin/sevra version` to check the installed workbook CLI if another
program named `sevra` appears earlier in your shell's PATH. See
[Build and run](db/records/operations/build-and-run.md) for build-only commands,
resource verification, updates and uninstall instructions.

Maintainers can build and test a standalone DMG and Sparkle updates using the
[macOS release runbook](db/records/plans/macos-installer-and-updates.md#rehearse-a-release-locally).

### Set up local AI

In Settings, choose **Download model**, or **Verify model files** when files are
already present. To reuse compatible Qwen3.6 35B A3B 4-bit weights with DFlash 2,
expand **Model files and storage > Use existing model files…**.

Once the model is downloaded, quit Sevra and run the installer once more:

```sh
bash scripts/install.sh
```

This reads the start that every chat shares once, with the model, and seals it in
the app, so chat does not read it again each time the model starts. Chat stays
unavailable until then, and the app says so. Run the installer again after you
update the source.

Models stay outside your workbooks. Import, search, tables, calculations and
saved results also work without setting up AI.

### Your first workbook

1. Choose **Add files** on the start window and select the
   [sample CSV and PDF](examples). Sevra makes the workbook in `~/Sevra Workbooks`.
   The files are included and indexed.
2. Open the quotation and ask for a cited summary. Compare goods plus shipping,
   checking the source and inputs. Keep missing tax information marked as unknown.
3. Keep a working table or chart, edit an input and check the recalculated result.
   Try Undo, then close and reopen the workbook.
4. Export and reopen a portable copy to keep the evidence and work together.

The [supplier comparison walkthrough](db/records/operations/build-and-run.md#supplier-comparison-walkthrough)
has the exact steps. Focused questions work best. AI can miss a document or
misunderstand a request, so check important answers against the original files.

## Build a native mini app

Add an **.xlsx or .xlsm** file and describe how you use it. Sevra keeps the
original and can use its tables and supported calculations to build a small
native app. You can also choose **Just use the tables** without a model.
The [Excel guide](db/records/specs/single-excel-import.md) explains the process.

For a new tool, describe its fields, actions and tables. App generation includes
checks with synthetic inputs and a model review before saving. Review the app's
data access before enabling it. Each changed version needs approval again.
See the [authoring guide](db/records/specs/local-model-native-apps.md).

You can also import the [Inventory, Jobs and Visual Planner examples](examples/apps)
with **Workbook > Add Native App…**. Their interfaces use native controls.
App code runs in a sandboxed worker with access to the data you approve.

Use the controls or ask in chat: “Add Pencils with quantity 3,” “Change it to 5,”
or “Undo that change.” Apps support Undo and Redo for the latest saved change,
including after reopening. A new saved change replaces the previous Redo.
See the [chat operation guide](db/records/specs/chat-primary-operation.md).

**Test generated apps with your own cases before using them for business.**
Generation can fail or take minutes. Automated checks help find problems, but
cannot establish that an app handles every situation you need.

Excel support also has limits. Original macros never execute. Sevra can attempt
to recreate readable macro logic as local calculations and actions, then compare
results with supplied originals. Those comparisons cover only the provided cases.
External services, unreadable sources, exact Excel rendering and automatic formula
extension to inserted rows remain limits. See the
[Excel conversion details](db/records/specs/excel-application-reconstruction.md)
and [recorded trials](db/records/plans/fresh-excel-batches.md).

## Development and current limits

Use copies of your files while evaluating Sevra, keep backups and check important
results. The [current handoff](db/records/operations/agent-handoff.md) and
[verification register](db/records/operations/implementation.md) record what has
been tested, known failures and work still in progress. Production signing,
notarization and broader hardware testing remain unfinished.

Development formats and interfaces may change before the first notarized,
production-ready 1.0 release. Current-format history and originals remain
protected. See the [compatibility policy](db/records/specs/distribution.md#pre-10-compatibility-policy).

The app uses SwiftUI, AppKit and SQLite, with a shared Swift core and CLI.
Local inference runs through the native Splash C++/Metal engine. A `.sevra`
workbook contains its database and ordinary included asset files. A `.sevraz`
file is a portable copy. Cloud sync is not part of the current app.

For contributors:

- [Build, run and verification commands](db/records/operations/build-and-run.md)
- [Native UI Catalog](db/records/operations/native-ui-catalog.md) for components, states and replayable workflows
- [Native app SDK](sdk/README.md) and [architecture](db/records/specs/programmable-native-engine.md)
- [Visuals plan and verification](db/records/plans/rich-native-visuals.md)
- [Inference configuration and qualification](db/records/operations/inference-context-execution.md)
- [Repository instructions](AGENTS.md) and [specification store](db/DB.md)

The native app is developed in this repository. [sevrahq.com](https://www.sevrahq.com)
is its marketing website.

Report problems in [GitHub Issues](https://github.com/carloslfu/sevra-app/issues).
Include the app version, reproduction steps and a small synthetic example.

## License

Sevra's source is available under the [MIT license](LICENSE). Third-party
components and model weights have their own licenses.
