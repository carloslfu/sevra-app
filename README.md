# Sevra

A private native Mac workbook for working with documents, tables and business
information through conversation. Local AI, checked calculations, and files you own. Programmable spaces also run small apps with native controls.

**MVP 0.1 test preview.** Bring supplier files, inspect cited evidence, compare costs,
keep a useful native table/chart, edit inputs, and share a portable workbook.
The [verification register](db/records/operations/implementation.md) tracks current
proof and limitations. This is a source preview for trying the example workflow.

MIT licensed and open source. Development formats and interfaces may change
without backward compatibility until the first notarized production-ready 1.0
release. Current-format history and originals remain protected. See the
[compatibility policy](db/records/specs/distribution.md#pre-10-compatibility-policy).
Sevra Websites and Slotstream remain separate products.

The app uses SwiftUI, AppKit and SQLite, with native Splash C++/Metal inference
through Swift. A workbook contains its database plus ordinary included asset files.
The repo's independent [db.md knowledge store](db/DB.md) owns its specifications
and progress. Cloud/sync and the expanded roadmap are outside this next MVP slice.

## Build a native mini app

For existing Excel work, add or drop an **.xlsx or .xlsm** file. Sevra preserves the original,
uses the local model to describe the likely workflow, and lets you clarify it before
choosing **Build workspace**. The checked native app uses the imported tables and
spreadsheet calculations. It can translate missing formulas and readable macro logic into
saved local calculations and native actions, then compare results against the original.
Add recalculated Excel copies to test more inputs. Review access before enabling it. **Just use
the tables** also works without a model. Reopening or retrying resumes the same
import; updating an existing table remains a separate reviewed action within it.
See the [Excel flow and limits](db/records/specs/single-excel-import.md).
Original macros never execute. Saved-result matches cover only the tested examples;
external services, unreadable sources, exact Excel rendering and automatic formulas
for inserted rows remain limits. See the [reconstruction contract](db/records/specs/excel-application-reconstruction.md).
Automatic conversion is undergoing broader business-case and edge-case qualification.
The [reliability plan](db/records/plans/automatic-excel-reliability.md) records fresh local-model
trials, fixes and retained failures. Test your business workflow before relying on it.

Ask the local model to build a named mini app with the fields, actions and tables you need.
It writes the app, runs synthetic checks in isolation, and reviews the result against your
request before saving. Review its table access and choose **Enable app**. Ask for changes
by the app's name; each new version needs approval again. See the
[authoring workflow and limits](db/records/specs/local-model-native-apps.md).

You can also import [example app packages](examples/apps) using **Workbook > Add Native App…**.
Inventory, Jobs and Visual Planner exercise native forms, tables, live counts and a draggable canvas. JavaScript runs in a
sandboxed worker; the interface is AppKit, with no web view. App code and business records
travel with the workbook, while execution permissions stay on this Mac. Enabled apps run
without the inference model. Generated apps still need your own testing before business use.

The [SDK and architecture](db/records/specs/programmable-native-engine.md) explain
TypeScript/JSX authoring, signals, native components, scoped data access and current limits.
The local model can also compose simpler fixed spaces. This is SDK 1, not full Excel compatibility.

## Try the native MVP preview

Requires Apple M3 or newer, macOS 26.4+, Swift 6.3, Git, Python 3 and Rust 1.96.0.
The current test host has 48 GB unified memory; other memory profiles are unqualified.
Initial build/setup needs network access. Installed inference uses no Python.

~~~sh
git clone https://github.com/carloslfu/sevra-app.git
cd sevra-app
rustup toolchain install 1.96.0 --profile minimal
bash scripts/install.sh --native
open "$HOME/Applications/Sevra Native Preview.app"
~~~

The installer includes the matching `sevra` CLI in `~/.local/bin`. It refuses to
replace another app or an unrelated CLI. This source preview is locally ad-hoc
signed, with no production notarized installer yet.
Use `~/.local/bin/sevra version` to verify the installed workbook CLI if another
program named `sevra` appears earlier in your shell's PATH.

In Settings, choose **Download model**, or **Verify model files** when files are
found. To reuse weights, expand **Model files and storage > Use existing model files…**
for compatible Qwen3.6 35B A3B 4-bit weights with DFlash 2. A fresh download is
21.48 GB plus working space. Models stay outside workbooks. Import, search, tables,
calculations and saved results also work without AI setup. There is no hosted-model
fallback or in-app telemetry.

Start from the two files in [examples](examples), then follow the
[supplier comparison walkthrough](db/records/operations/build-and-run.md#native-mvp-supplier-comparison).
Files are saved and indexed without an extra dialog. Convert the saved CSV into
a working table when needed; the searchable PDF stays an included reference.
Open the quotation and ask for a cited summary, calculate goods plus shipping,
keep a live table/chart in a space, edit an input, Undo, and make a portable copy.
Add a folder compares a folder with what you already added and shows the counts first; it does
not watch the folder. Ask to enable a saved automation by name and Sevra opens its review, where
you decide. Long conversations summarize as they go, and a long request that stops keeps its saved
work, so you can ask it to continue.
File actions > Transcribe on this Mac turns a recording of up to two hours into a searchable
transcript with times, in the Mac's language. Audio stays on the Mac, though the first use of a
language can download its speech model from Apple.
Focused requests work best: one request handled eight documents in testing, and a broad question can
still miss a file.
Check the original evidence before relying on an answer. Unknown tax remains unknown.

While Sevra works, the activity line shows its current phase, elapsed time and Stop.
Expand it to inspect actual tool steps and saved results, including after reopening
the workbook. Documents, rows and structured results use native readable views.
See the [activity design](db/records/specs/agent-activity.md).

See [Build and run](db/records/operations/build-and-run.md) for setup, the exact
walkthrough, CLI, safe uninstall and limits. The
[fast MVP contract](db/records/specs/mvp-delivery.md) defines this preview;
the expanded specifications remain the roadmap.
