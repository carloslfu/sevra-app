---
type: spec
meta-type: conclusion
id: 01m5rbxzbe4pdmde0k72e3j6n6
created: 2026-10-25T01:48:47.342811+00:00
updated: 2026-10-28T15:53:21.310918+00:00
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
Versioned JSON result/error envelope, schemaVersion, nonzero errors, bounded output,
app-closed use and optional expectedRevision/idempotency. A shipped `skills/sevra`
skill teaches safe tool composition over this exact CLI, not direct SQL writes.
D06. All durable operations share the same core across UI and CLI. Integration test
opens a package from both processes, rejects stale writes, retries safely, and
observes refreshed UI state. CLI must not need a running desktop app.
D07. Core invariant checks run on CLT-only hosts through an executable test runner
if XCTest is unavailable. Tests use temporary directories and injected failures;
never edit user workbooks. Verify current-format integrity, lost copy, cancellation, hostile ZIP,
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

## Reference feature delivery

D11. The inline-reference slice must pass LJ01-LJ10 in
[[records/specs/references-and-relationships]] before being described as complete.
Expose equivalent version-safe linking/resolution/backlink operations through
native UI, local-agent tools and CLI; no model-authored SQL. Update the repo-owned
skill only with implemented commands and limits. Qualify current-format rebuilds,
competing writers, portable offline reopen and installed app/CLI behavior.
Optional inferred associations and a graph view are not first-slice prerequisites.
Existing engine, context and release gates remain in force.

## Focused verification policy
Owner-approved course correction, October 27, 2026: use the smallest checks that
establish the changed behavior so development time goes toward the app. This
policy controls routine development; it does not weaken release requirements or
permit claiming untested gates passed.

- For a localized fix, reproduce the actual failure, verify the correction and
  one nearby counterexample, then run relevant deterministic checks for affected
  code. Preserve data integrity, arithmetic, permissions, lineage, acceptance and
  Undo invariants. A UI-only wording/presentation change needs one inspection of
  the affected interaction.
- Reuse evidence where the relevant behavior is unchanged. A different prompt or
  executable hash alone does not require rerunning unrelated conversation,
  handoff, guidance, both backends, installation or packaging suites.
- Run the full relevant suite once at a meaningful integration/release milestone.
  Broaden or repeat checks only for a concrete failure, changed boundary or an
  explicit evaluation question. State what a repetition will establish before
  running it. Keep model reliability experiments separate from normal development.
- Bound minor model-language polishing. Record non-blocking wording limitations
  and proceed with product work. Data corruption, unauthorized actions and
  material correctness failures require correction or a safe deterministic
  boundary before release. Never relax assertions or erase failed evidence.
- Safely prevent unnecessary queued verification stages when scope changes.
  Preserve partial logs and completed work, and do not interrupt a workbook
  transaction. Do not build another testing framework merely to apply this rule.
- Close focused checkpoints with appropriate small checks, documentation and a
  commit. Keep the overall app objective and genuinely outstanding gates active.

For the present acceptance/accuracy fix, the relevant evidence is the previously
failing detailed explanation, one direct acceptance-boundaries contrast, and the
existing context-budget regression because this change actually exposed it.
Broader cohorts already performed remain evidence, not a reason to repeat them.

Remote CI follows the same owner-approved policy. The existing complete Checks
job retains all 26 steps and assertions, but runs automatically only on main
integration pushes, v-prefixed release-tag pushes, and non-draft pull requests
when opened, reopened or marked ready for review. Ordinary development pushes
and pull-request synchronize events do not launch it. Draft jobs are skipped;
skipped or untriggered checks are never evidence of passing verification.

Use focused local checks during development. At a meaningful integration,
pre-merge or release milestone, explicitly dispatch Checks for the intended
branch when no applicable current run exists. Record the tested commit and
confirm the final pre-merge/release head; an earlier green run is not approval for
later changes. Keep useful implementation moving while remote CI runs, and
inspect its result at the milestone rather than repeatedly polling. No branch
protection setting or release acceptance requirement is changed by this policy.

GitHub requires the workflow_dispatch configuration on the default branch before
manual dispatch is available. Until this change lands there, opening a non-draft
pull request or marking it ready supplies the initial pre-merge run. Later
pre-merge updates can use draft -> ready or close -> reopen to request a fresh
run. After integration, `gh workflow run check.yml --ref BRANCH` is the explicit
milestone path. These event/dispatch semantics follow
[GitHub's event reference](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#pull_request)
and [manual workflow guidance](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow).

## Pre-1.0 compatibility policy
Owner decision, October 28, 2026. Backward compatibility is not supported or a
release prerequisite during development. Support begins with the first
production-ready version 1.0 that is properly signed, notarized and actually
released for production use. A test deployment, preview, prerelease, CI build,
version tag or notarization of a test artifact does not activate that commitment.
Production 1.0 is the first supported format/API baseline; earlier development
formats do not become supported retrospectively.

Until that milestone, workbook schemas/formats, saved application definitions and
CLI/agent interfaces may change without legacy migrations or compatibility
adapters. Update the canonical initial schema and current interfaces together;
recreate selected disposable synthetic development workbooks/fixtures and document
breaking changes. Do not add old-schema conversion, legacy aliases or older-package
tests solely to preserve unreleased development state. Existing migration code
and receipts are incidental support or historical evidence, not a new gate or
promise. Simplify obsolete paths as part of a deliberate implementation change.

Current-format integrity, atomic writes, stable identities within a workbook,
lineage, Undo, cancellation/reopen and portable export/reopen remain requirements.
This permits resetting selected development fixtures, not silently deleting an
incompatible workbook on open or wiping unrelated/user files, model installations,
original assets or historical evidence. External Excel/CSV continuity and declared
third-party protocols remain separate interoperability requirements. Slotstream's
independent repository/API commitments are outside this app policy.

This section controls older active migration/backward-compatibility requirements
throughout the specs, implementation plan, saved-definition contracts and tests.
Keep historical migration results in their original scope. At production 1.0,
record the released schema/format/API baseline and define transactional upgrades
and regression fixtures for later supported production releases. This policy does
not claim that production release or notarization has happened.

Source: [[sources/notes/2026/10/pre-1-production-compatibility-policy]].
