---
type: spec
meta-type: conclusion
id: 01m5rbxzbe4pdmde0k72e3j6n6
created: 2026-10-25T01:48:47.342811+00:00
updated: 2026-10-27T18:42:11.604724+00:00
summary: Independent source build, native bundle, CLI skill, portable format and end-to-end release gates.
title: Distribution and verification
status: reviewed
---
# Distribution and verification

D01. Public MIT repository from bootstrap. No proprietary assets, credentials,
private repository links or absolute developer paths required. Preserve upstream
licenses/notices for redistributed dependencies. Product trademark is not licensed
as endorsement by a fork. Synthetic sample workbook is generated deterministically.
D02. The Splash integration targets Apple M3+ and macOS 26.4+, subject to physical
runtime qualification. The earlier macOS 14 declaration described the Slotstream
baseline, not future Splash support. Package pinned native engine and Metal
resources with verified hashes and licenses. Source builds may use upstream
development tools; the shipped app's setup and inference must not need Python.
D03. `scripts/build.sh` builds CLI/app/check runner and the native sevra-extract
helper, stages a valid `.app`, required
resources, Info.plist document types, microphone/speech usage strings and signatures.
Both product layouts ship sevra-extract adjacent to the real app/CLI executable.
Resolving an installed CLI symlink must still find its helper. A missing helper
refuses extraction without silently returning to in-process parsing.
`scripts/install.sh` installs to user Applications plus a user-owned CLI bin folder,
refuses unexpected overwrite, and records version. Uninstall removes binaries only;
workbooks/model files survive. Unsigned/ad-hoc builds are labeled honestly.
D04. README gives exact prerequisites, fresh-checkout commands, launch, setup, demo,
CLI usage, verification, troubleshooting and data locations. No fabricated one-line
release installer before a verified release exists. Never globally disable Gatekeeper.
D05. CLI `sevra` exposes create, import, search, read, records, tables, calculate,
accept/correct, spaces, conversation, inspect, verify, export/open and local ask.
Stable JSON result/error envelope, schemaVersion, nonzero errors, bounded output,
app-closed use and optional expectedRevision/idempotency. A shipped `skills/sevra`
skill teaches safe tool composition over this exact CLI, not direct SQL writes.
D06. All durable operations share the same core across UI and CLI. Integration test
opens a package from both processes, rejects stale writes, retries safely, and
observes refreshed UI state. CLI must not need a running desktop app.
D07. Core invariant checks run on CLT-only hosts through an executable test runner
if XCTest is unavailable. Tests use temporary directories and injected failures;
never edit user workbooks. Verify migration, lost copy, cancellation, hostile ZIP,
search index rebuild, Decimal calculations, lineage, event idempotency and undo.
D08. UI checks exercise create/open/import/search/evidence/space/draft/edit/undo,
keyboard and appearance, live text/voice setup permissions, media and missing files.
Record what could/couldn't be tested. Voice hardware tests cannot be simulated into
success. Accessibility permission failures are a real verification limitation.
D09. Local-model eval uses real pinned weights and recorded synthetic questions.
Require actual search/read tools and correct citations, arithmetic, refusal to
execute imported instructions, cancellation and context overflow recovery.
D10. Fresh clone builds/installs, complete demo runs, portable export reopens with
matching evidence, and CI passes on public source. Release includes hashes and
explicit supported platforms/formats/limits. No blanket Excel-compatibility claim.

## Deliberate boundaries

First release is a local single-user workbook, not collaborative Excel parity.
No cloud sync, Windows/Linux implementation, macros, arbitrary generated plugins,
website-service connector or finance compliance certification is implied. Native
preview availability is broader than supported extraction and editing; document
that matrix. These boundaries do not excuse incomplete core first-version journeys.
