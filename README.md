# Sevra

A private native Mac workbook for working with documents, tables and business
information through conversation. Local AI, checked calculations, and files you own.

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
Focused requests work best: one request handles about nine documents, and a broad question can
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
