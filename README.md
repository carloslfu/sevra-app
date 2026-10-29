# Sevra

A native Mac workbook for working with documents, tables and business information
through conversation. Local AI, inspectable calculations, and files you own.

**Development preview.** The native app, shared core, CLI and real local-model
integration are implemented. Release qualification is still in progress; see the
[verification register](db/records/operations/implementation.md) for tested behavior
and pending work.
Development schemas, workbook formats and interfaces may change without backward
compatibility until the first notarized production-ready 1.0 release. Test builds
and deployments do not start that commitment. See the
[compatibility policy](db/records/specs/distribution.md#pre-10-compatibility-policy).
It is MIT licensed from the first commit. It is separate from Sevra Websites.
The adopted [persistence requirement](db/records/specs/persistence-readiness.md)
prepares complete local history and reconstruction for future syncing. Sync and
cloud services are outside the current implementation scope.
The adopted [managed dataset design](db/records/specs/managed-datasets.md) adds
native structured tables over shared immutable history and replayable schemas.
Native storage, capture, reconstruction and versioned schema editing have scoped
evidence. Bounded typed stored-column queries and disposable performance indexes
now have core/CLI qualification. Versioned reusable functions/query templates and
searchable definition history are available through the core/CLI. Registered draft
inventory actions and recoverable native receiving forms now have scoped automated
proof. Conversation can author saved behavior and queue durable workflows;
explicit continuation stops for required review. Foreground scheduled draft
execution has scoped recovery proof. Native schedule controls and persistent
per-Mac permission now have [scoped active-app proof](db/records/specs/native-automation-owner.md).
Background scheduling, full Excel continuity, richer workflows and release checks
remain open.

Start with [the project knowledge map](db/records/overview/start-here.md),
[the specification](db/records/specs/product.md) and
[the implementation plan](db/records/operations/implementation.md).

The app uses SwiftUI, AppKit and SQLite. The native preview integrates pinned
Splash C++/Metal through Swift, with no Python runtime. Production adoption is
still being qualified under the [inference design](db/records/specs/splash-integration.md).
The preserved Slotstream build remains available separately. Sevra Workbook is the primary product; Sevra Websites is
the separate managed service. A workbook
contains a database and ordinary asset files. The repository's `db/` is its
independent [db.md](https://github.com/carloslfu/db.md) knowledge store, not the
workbook storage format.

## Try the development build

Read [Build and run](db/records/operations/build-and-run.md) for prerequisites,
installation, model setup, the synthetic example and uninstall.

~~~sh
git clone https://github.com/carloslfu/sevra-app.git
cd sevra-app
bash scripts/build_native.sh
./output/native/bin/sevra version
open "output/native/Sevra Native Preview.app"
~~~

The native source build requires Apple Silicon, Swift 6.3, Git,
Python 3, Rust 1.96.0 and initial network access for dependencies.
See Build and run for the exact prerequisites, model layout and preserved
baseline installation instructions. Model weights are a separate optional setup.
The current native AI engine requires Apple M3 or newer and macOS 26.4 or newer;
supported memory profiles still need qualification.
There is no hosted-model fallback or in-app telemetry.
