# Sevra

A private native Mac workbook for working with documents, tables and business
information through conversation. Local AI, checked calculations, and files you own.

**MVP 0.1 candidate.** Bring supplier files, compare costs with cited evidence,
keep a useful native table/chart, edit inputs, and share a portable workbook.
The [verification register](db/records/operations/implementation.md) tracks current
proof and remaining blockers. This candidate is not yet a qualified release.

MIT licensed and open source. Development formats and interfaces may change
without backward compatibility until the first notarized production-ready 1.0
release. Current-format history and originals remain protected. See the
[compatibility policy](db/records/specs/distribution.md#pre-10-compatibility-policy).
Sevra Websites and Slotstream remain separate products.

The app uses SwiftUI, AppKit and SQLite, with native Splash C++/Metal inference
through Swift. A workbook contains its database plus ordinary included asset files.
The repo's independent [db.md knowledge store](db/DB.md) owns its specifications
and progress. Cloud/sync and the expanded roadmap are outside this next MVP slice.

## Try the native MVP candidate

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

In Settings, choose **Download / verify model**, or **Reuse an existing Fast model**
for compatible Qwen3.6 35B A3B 4-bit weights with DFlash 2. A fresh download is
21.48 GB plus working space. Models stay outside workbooks. Import, search, tables,
calculations and saved results also work without AI setup. There is no hosted-model
fallback or in-app telemetry.

Start from the two files in [examples](examples), then follow the
[supplier comparison walkthrough](db/records/operations/build-and-run.md#native-mvp-supplier-comparison).
The CSV becomes a working table; the searchable PDF stays an included reference.
Ask for a cited cost comparison, keep a live table/chart in a space, edit a price,
Undo, and make a portable copy. Unknown tax remains unknown.

See [Build and run](db/records/operations/build-and-run.md) for setup, the exact
walkthrough, CLI, safe uninstall and limits. The
[fast MVP contract](db/records/specs/mvp-delivery.md) controls this next deliverable;
the expanded specifications remain the roadmap.
