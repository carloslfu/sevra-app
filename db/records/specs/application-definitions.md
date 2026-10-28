---
type: spec
id: 01m61v3tcay3v380asyfhvg260
created: 2026-10-28T18:07:17.386524+00:00
updated: 2026-10-28T21:04:23.564686+00:00
summary: Schema14 versioned inventory actions and recoverable native forms have automated scoped proof; visible UI, agent/EJ, workflow and release gates remain open.
title: Shared application definitions and actions
status: reviewed
---
# Shared application definitions and actions

This elaborates E2 in [[records/specs/native-app-engine]]. It is an implementation
contract, not a statement of whole-feature completion. E1 is captured at cd5f854.
The schema14 catalog now includes scoped core/CLI registered inventory actions and
recoverable native form implementation in addition to the earlier pure computation.
Result publication, query/function composition, agent tools and visible native journey
qualification remain open. E3 owns durable multi-step execution; do not hide
a workflow scheduler in this layer. No arbitrary SQL, generated executable code,
provider calls or external effects are accepted by a definition.

## Managed dataset prerequisite

The adopted [[records/specs/managed-datasets]] E0-D foundation precedes dependent
E2 dataset queries/actions. Reuse registered native columns, stable logical IDs,
versioned definitions and the same replayable capture/apply contract. Definition
catalog work may proceed independently, but dataset mutations must not introduce
another editable JSON backend or a separate history ledger. The E2 sequence here
follows that storage prerequisite. The scoped catalog receipt is separate from
complete E0-D, EJ04/EJ05 or release evidence.

## Storage and identity

Use the canonical schema version selected with E0-D, with no old-schema adapter.
Preserve older user/synthetic packages and recreate only selected fixtures. app_definitions retains immutable
exact-version IDs, stable logical ID, sequential version, kind, title, description,
typed parameter list, typed payload, authoring Source and recorded time.
app_definition_heads selects the current version. app_definition_dependencies
records outgoing definition/data bindings with live versus exact-version policy.
All three ordinary tables join the complete capture inventory. Retained historical
versions remain portable and inert during reconstruction. No second journal.

Each save/restore requires an exact current-version ID when a logical definition
already exists. A source captures the exact submitted definition and links to its
authoring request/explicit evidence. Actor attribution describes the actual caller;
a generated definition is not a human-approved business rule. All of this, its
head, dependency rows and operation receipt commit together. Unknown behavior,
missing references, stale bases, cycles and invalid parameters roll back entirely.
Retry tokens and exact arguments return the original version after later edits.
Removing a component never removes a definition or its history.

Definition kinds start with function and query, followed by action and form.
Future workflow/automation kinds remain refused until their executors qualify.
Use UUID logical/exact IDs independently from names. Exact bindings keep their
version; live bindings follow the head. Current and historical scope is explicit.
Saving executable intent never grants authority to run it or accept business data.

## Inputs and pure computation

A parameter has a stable identifier, label, declared type, required flag and
optional default/unit/bounds/choices. Start with text, decimal, boolean, date,
exact item reference and choice. Dates require explicit ISO8601/time-zone semantics;
financial numbers are decimal strings. Missing and null differ; optional omissions
are preserved and cannot quietly become zero. Reject extra fields and mismatched
types/units. Bounded repeating entries arrive with the receiving form rather than
pretending arbitrary nested JSON is already a validated form. Defaults cannot read
hidden UI selection, today's date or a model's memory.

A pure function has a bounded Decimal expression and declared function calls with
stable alias, target binding and explicit argument mappings. Input bindings are a
literal or named caller parameter, never code. Resolve calls lazily, reject cycles
across current and pinned paths, enforce depth/work budgets and preserve all exact
resolved definition versions in evaluation output. No implicit unit conversion.
Output unit/rounding is declared; existing Numbers/Formula remains the evaluator.
Unknown names/functions/ranges refuse at save; division-by-zero and missing-input
errors remain explicit at evaluation. A published result is a new derived Record
linked to exact inputs/definition evidence; evaluating for display can remain read-only.

A reusable table query has a dataset ID, selected stable column IDs, typed bounded
filters and meaning/status/scenario scope. SQL is authored and parameterized by the
host against E0-D registered native columns. Query pages use coherent read snapshots
and stable order, exact item IDs,
revision-bound cursors and explicit result/coverage metadata. Decimal comparisons
use the existing exact decimal collation, not floating point. Stored columns come
first; calculated-column predicates require separate bounded/materialized support.
Do not infer low inventory from a supplier price table or apply a partial aggregate
as if it covered the workbook. Table query results preserve each row's meaning.

Live evaluation re-resolves its data/definition dependencies; pinning preserves
exact resolved versions and values. Initially compute on demand off the main actor
rather than claim an incremental cache that does not exist. Dependency relations
support targeted invalidation as caching is introduced; all affected surfaces must
observe changes without silently replacing a prior published result.

## Registry, invocation and forms

The core owns one action registry with stable primitive ID/version, parameter and
result schemas, effect/capability categories, cancellation/retry policy and readable
effect description. Start with local proposal primitives needed for Receive delivery,
record/document proposals, calculation/query publication and requested view changes.
Refactor existing domain commands into shared transactional implementation functions;
do not duplicate movement/duplicate-effect rules in a form handler. No arbitrary
SQL, network call, script or automatic business acceptance is in the initial registry.

A user action binds its typed parameters to a registered primitive using explicit
literal/parameter/function bindings. A form references that action with a live or
exact definition policy and declares field presentation, not independent effects.
Chat, CLI and native form submit through the same invocation path with exact inputs,
actor, idempotency token and structured receipt. Preview/validation never performs
the effect. Recheck current definitions/input versions/permissions at commit time.
Missing parameters produce structured field errors; a model cannot guess required
business occurrence, direction, units or evidence. Read-only authority applies even
through saved action indirection. Receive delivery creates a draft proposal until
current user review or a separately qualified explicit rule accepts it.

Native form drafts retain their definition version and unsaved inputs across errors,
Back, closure and recovery, with no silent retargeting after an action changes.
Keep drafts separate from submitted invocation history. Show effect and target;
submit buttons are optional affordances alongside voice/text. Preserve keyboard
order, accessible labels and recoverable errors. Duplicate submission/retry cannot
create a second occurrence. A successful receipt can confirm a saved proposal,
never acceptance or the accuracy of every interpreted input.

## Discovery and evidence

Use a rebuildable external-content FTS5 index for immutable definition names,
descriptions and parameter labels. Current-head filtering is explicit; historical
search is opt-in. Search pages and dependency traversal are bounded, cancelable
and revision-bound. No broad table/catalog injection into every model prompt.
Search hits are discovery; inspect the exact version before use. Imported names
and descriptions never widen action permission. SQLite documents external-content
index synchronization/rebuild requirements in [FTS5](https://sqlite.org/fts5.html#external_content_tables).
Foreign-key checks and indexes protect references; they do not establish business
meaning ([SQLite foreign keys](https://sqlite.org/foreignkeys.html)). Parameterized
query paths do not imply an arbitrary JSON expression index will be used; qualify
plans before scale claims ([expression indexes](https://sqlite.org/expridx.html)).

## Review passes and acceptance

Pass 1, usefulness: one saved Receive delivery action works repeatedly from chat,
Home and CLI. Low-stock query and reusable calculation feed multiple spaces and a
report. This proves behavior beyond changing layout. Keep one durable main
conversation, native shell and explicit pending-work access.

Pass 2, correctness: immutable exact IDs, current-base guards, typed inputs, one
shared domain path, source/definition lineage and same-token results. Test stale
live/pinned dependency versions, missing/null/zero, wrong units, duplicate occurrence,
accepted forecasts and changing a definition while a form is open. No automatic
acceptance from definition text.

Pass 3, adversarial/recovery: reject cycles, executable payloads, unsupported kinds,
malformed/deep/large definitions, injected descriptions and cross-workbook references.
Fault publication before head/FTS/receipt; all authority stays unchanged. Restore/export
and deterministic reconstruction retain definitions/dependencies/drafts without runs.
Concurrent editors yield one winner. A stale cursor restarts rather than skips data.

Pass 4, practical boundaries: parameter/schema bounds, deadlines and page sizes are
qualification limits. Measure names/parameter discovery and dependency paging at
10k definitions; query larger synthetic tables without loading every row. Reuse
unchanged extraction/model evidence. Qualify real model authoring/invocation and
native keyboard/VoiceOver separately. Passing catalog tests alone closes neither
EJ04/EJ05 nor whole-app release gates. Record exact commands, retained failures,
source/build hashes and limitations in [[records/operations/implementation]].

## First catalog and pure-evaluation slice

The implemented schema13 slice adds immutable app_definitions, selected app_definition_heads and retained
app_definition_dependencies to the same capture inventory. Definitions and their
authoring Sources are metadata, not a third business category. Canonical definitions
store validated typed descriptors and exact previous IDs. An actual/accepted
authoring Source records the observed save, exact submitted content and actual actor;
this does not mark definition logic or business results accepted. It adds no business
approval task. FTS5 indexes title/description/parameter labels as a disposable external-content
projection over retained versions. Rebuild it after inert replay. No migration of
older development workbooks, scheduled execution or automatic business acceptance.

The first public definition object has kind, title, description, parameters and
payload. Function payloads declare expression, unit, optional rounding and calls.
A call declares an alias, a live logical-ID or exact version-ID binding, and explicit
parameter/literal mappings with units. Only declared Decimal names and bounded
built-in Formula operations are admitted. Resolve calls lazily, enforce depth 16
and work 128, and revalidate changed live signatures at evaluation. Save rejects
cycles across effective live/exact paths; a definition update cannot change kind.
Inputs distinguish omitted/null/defaults; defaults are literals with no ambient reads.
Decimal strings, Boolean values, ISO dates, bounded choices and exact local item
versions are strict types. Caller and callee units must match. Formula arithmetic
uses the existing Decimal behavior; output declares unit and optional plain rounding.
This layer does not infer physical dimensions or exchange rates.

Query payloads contain a managed typed query template and dataMode live or exact.
Filter value may be a named parameter binding. Other query fields remain literal.
Live mode rebinds current dataset definitions only while every referenced stored
column retains type/unit/formula meaning. Exact mode refuses after its bound schema
changes; it does not fabricate a historical projection. Both modes read current
rows at the explicit current snapshot. A frozen business result is a separate
published Record, not this exact schema mode. Returned results expose exact root,
resolved function/data definitions, normalized arguments and ordinary query coverage.
Continuation binds root definition as well as query/snapshot. No implicit cache.

Create requires a caller-selected UUID logical ID and no base; edit/restore requires
the exact current definition UUID. Stable request tokens return their original
version after later edits. Version inspection, history and search remain bounded,
cancelable and portable. Discovery filters current heads by default, with historical
scope opt-in; hits are metadata, not execution authority. Dependency inspection
shows retained bindings rather than pretending live targets never change.

This slice closes neither E2 nor EJ04/EJ05. Shared action registry, native form drafts,
view bindings, result publication, model authoring/invocation and 10k discovery/resource
qualification still need actual implementation and scoped receipts. Definition
catalog work is independent of the still-open Excel sparse/formula continuity gates.

## Scoped implementation evidence

[application definition receipt](../../../integration/evidence/2026-10-28-application-definitions.json.gz), 42,911 bytes,
SHA-256 4c90977fb56a47c1b51ddadfbe40747f100732bfaf65ff9c46581b049f094b58.
All 106 prior evidence files remain byte-identical. Core 208 groups pass. The full
scripts/check.sh pass had 207 groups before the final authoring Source/review-queue
metadata correction; final focused208 and native/CLI probes qualify that correction.
No full-script rerun after it is claimed. Final native packaging, installed resource
refusals/signature, strict lint (19 Swift files) and skill validation pass. Two
independent CLI editors yield one saved version and one stale-definition refusal.

A final public-core corpus created 10,000 functions plus a shared base, retaining
5,000 explicit dependencies. Creation took 22.685 s; median 50-hit pages were
0.644 ms for 1,000 matching names, 1.990 ms for all 10,001 parameter-label matches,
and 0.217 ms for a full catalog listing. All pages were complete/unique. Verification
took 4.415 s, inert reconstruction 20.074 s; maximum benchmark-process lifetime RSS
135,053,312 bytes. Database 105,459,712 bytes; retained history 54,665,015 bytes.
Actual FTS plan uses the virtual index, rowid/covering head lookups and a temporary
B-tree for stable ordering. The final packaged CLI opened this corpus, searched in
0.045 s, evaluated in 0.043 s and verified in 3.691 s, including process/open time.
These are one-Mac observations under ordinary development load, with some core
checks/native packaging overlapping the benchmark, not isolated performance or
hardware qualification. The earlier prototype corpus is retained separately.

The first input cohort caught ISO8601DateFormatter rolling an impossible February
30 into another date. Shared BusinessTime now validates date syntax/calendar/clock/
zone before parsing. Leap-date/offset, impossible business-event, newline/CRLF and
nearby valid inputs pass. Strict end-of-input anchors also protect shared decimal
strings and definition identifiers. Initial build/test failures are retained.

The final visual launch attempt was blocked by the locked Mac. No schema13 native
workbook/UI or VoiceOver proof is claimed. Native UI code and the local model/tool
contract are unchanged. E2 still requires shared action registry, forms/drafts,
result publication, native definition/query bindings, agent authoring/invocation and
EJ04/EJ05. E3-E6, Excel sparse/formula continuity, complete MJ/FJ and remaining whole
installation/accessibility/hardware/notarized release/main integration remain open.
Older development packages are preserved unsupported, without a migration adapter.


## Receiving actions and forms: concrete implementation contract

The next canonical development schema adds action and form definitions to the same
immutable catalog. No old-schema migration. The first registered primitive is
`inventory.receiveDelivery` version 1. It accepts an explicit delivery identity,
effective date, exact local evidence item, and one to fifty lines. Each line has
a distinct caller-supplied line identity, inventory subject and positive Decimal
item count. This first primitive counts discrete items; it neither converts units
nor claims physical-unit inventory support. A deterministic occurrence identity
combines delivery and line identity. Same-occurrence duplicates use the existing
movement guard. All lines create draft actual movements atomically, with separate
review required before balances change. No partial delivery publication.

Actions map typed parameters and literals, or qualified pure function results, to
a registered primitive. Forms reference an action live or exact and retain an
identical parameter signature while customizing field labels/help. Native drafts
open at exact form/action/function versions and retain raw incomplete inputs.
A changed live signature/version requires explicit reopening after keeping the
draft; no silent retargeting. Preview is a bounded read transaction and creates no
Source, operation or movement. Submission recomputes the plan under the package
write lock and checks the exact preview fingerprint, current definition bindings,
exact evidence and duplicate effects. The preview is a consistency check, never
permission. Core read-only authority refuses invocation even through forms.

One invocation Source records the caller, submitted inputs, resolved definitions
and normalized plan. Every movement derives from it and its original evidence.
The same transaction publishes all movements, Source and idempotency receipt.
An exact retry returns its original receipt even after definition changes. A new
request with the same delivery lines refuses duplicates. Preview and submission
use the shared movement validator/executor also called by direct movement tools;
there is no form-specific inventory implementation. Other registry primitives,
result publication, model tools and native journeys remain separately qualified.


## Registered action and form implementation

Current development schema14 extends the immutable definition catalog to action and
form kinds. The same three canonical definition families remain in the complete
capture inventory. No old-schema adapter. `inventory.receiveDelivery` v1 accepts
an explicit delivery identity/date/evidence and one to fifty distinct lines with
positive whole item counts. `inventory.proposeMovement` v1 accepts a signed nonzero
whole item count, meaning and an optional exact correction. This first registry
counts discrete items; it does not infer/convert units. Registry metadata exposes
typed parameters, a machine-readable result schema, capability/effect category,
three-second cancellation budget, retry policy and readable effect.

Actions map declared parameters, literals or qualified pure Decimal function results
with matching units. Forms bind an action live or exact, preserve its full parameter
signature and customize field presentation. Dependencies retain exact resolved
versions; historical verification never follows a newer live head. Core read-only
authority refuses invocation through either action or form. No new model tools,
arbitrary code, external effects, workflow scheduler or automatic acceptance.

Preview is a bounded read transaction. Submit re-resolves the plan under the
canonical write lock, checks the exact preview, validates exact evidence and uses
the shared movement validator/executor. Existing movement CLI/tools use that same
path. One invocation Source records actual actor, submitted inputs, normalized plan
and exact definition lineage. All draft movements, Source and retry receipt publish
atomically. Exact retries return the original after later changes; a new request
cannot duplicate the same delivery line, including a changed inventory subject.
A successful receipt proves saved proposals, not their semantic accuracy or accepted
stock. Balances change only after separate acceptance.

Native Home/space layout editing can add a Receive delivery starter. The component
binds a saved form and renders native scalar/choice/evidence/repeating-line controls,
field diagnostics, preview, draft submission and review access. Evidence search is
bounded, and selected originals can be opened. Back/removing a view retains its
window-owned draft session. Close/quit/open-workbook flushes pending inputs; failed
saves retain the session and block dropping it. An open form keeps exact definitions;
a changed live action/function needs explicit refresh, retaining prior inputs as an
alternative. Submitted forms require explicit New entry before another submission.

Unsent state uses classified `meta` keys `form-draft:` via presentationMutation,
not business evidence or a keystroke journal. It retains exact form/bindings, raw
incomplete values, retry token, actual last receipt and up to eight alternatives.
Concurrent windows refuse overwrites; Keep both retains both exact inputs. Recovery
reconciles a committed invocation after a crash before its presentation confirmation,
without resubmission. Limits: 64 KB current input, 1 MB checkpoint including alternatives,
256 draft keys per workbook and 128 bound definitions. Current checkpoints copy
separately during inert reconstruction and portable export. The original remains.

Evidence: [registered action and form receipt](../../../integration/evidence/2026-10-28-registered-actions-forms.json.gz), 31,349 bytes, SHA-256 dcb447bf7ee7e1127c4a31871f25f8fe76473e787bd82bc737e30e09155acb38. All 107 prior evidence files remain byte-identical. Broad scripts/check.sh passes with core217,
extraction19, document27, voice15 and Splash30 groups plus the existing shared
harnesses. New draft lifecycle checks pass. The final small registry-metadata pass
adds its machine-readable result schema/category/deadline and preserves custom action titles in form templates; focused final CLI/package
checks qualify that metadata after the broad run. Independent CLI writers produce
one two-proposal batch and one duplicate refusal. Maximum fifty-line publication,
late failure rollback, cancellation, stale live/pinned definitions, computed argument
lineage, nested field paths, exact retries, keep-both and inert/portable reopening
have scoped proof. Strict Swift lint, skill and repository knowledge/link gates pass.

The final native bundle is built and its installed resources/refusals/signature are
checked. CUA still reports the Mac locked, so visible new-form creation/filling,
keyboard/VoiceOver and light/dark/narrow behavior are unqualified. Automated native
session checks do not replace those journeys. No new model/hardware throughput
cohort is claimed. E2 still needs in-app agent authoring/invocation, reusable result
publication/query/function composition and full EJ04/EJ05. E3-E6 workflows,
automations/helper/templates, Excel sparse/formula continuity, full MJ/FJ and the
remaining installation/accessibility/hardware/notarized-release/main-integration
gates remain open. This checkpoint is not a ready release.

## Final form identity review, October 28

A draft key now hashes the structured space/component ID pair. Delimiter-containing
IDs cannot alias two components, and maximum-length legal IDs remain within the key
budget. Native view ownership also resets with the workbook interaction identity;
the window-owned scope retains the proper draft across Back and refuses to carry
one workbook's session into another. Focused native-session counterexamples pass,
along with the rebuilt native package paths/resources/signature checks, packaged CLI
action/race/portable/reconstruction probe and strict lint of 27 Swift files.

[form identity correction receipt](../../../integration/evidence/2026-10-28-form-draft-identity.json.gz): 11,074 bytes, SHA-256
`bdda49a349db48f6371cc83d077ddfbeee6d5715b71d2f63ffcf0a3c34ad7b3f`.
All 108 preceding receipt files remain byte-identical, including the earlier action/
form foundation receipt. That earlier receipt retains its original source/binary
hashes. Its broad core217/shared checks are reused; the small identity correction
has focused proof rather than a claimed broad rerun. A first lint invocation lacked
swift-format on PATH; the documented xcrun invocation passes. Visible native UI,
agent invocation, complete E2-E6 and release gates remain open.
