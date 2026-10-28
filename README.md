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

Start with [the project knowledge map](db/records/overview/start-here.md),
[the specification](db/records/specs/product.md) and
[the implementation plan](db/records/operations/implementation.md).

The app uses SwiftUI, AppKit and SQLite. The current build uses Slotstream;
the adopted [inference design](db/records/specs/splash-integration.md) integrates
Splash's C++/Metal engine through Swift, with no Python runtime. That migration
is being qualified. Sevra Workbook is the primary product; Sevra Websites is
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
./scripts/build.sh
./scripts/install.sh --no-build
~~~

Source builds require Apple Silicon, a recent Swift toolchain and initial
network access for dependencies. Model weights are a separate optional setup.
There is no hosted-model fallback or in-app telemetry.
