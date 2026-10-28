---
type: spec
id: 01m61v3tcay3v380asyfhvg260
created: 2026-10-28T18:07:17.386524+00:00
updated: 2026-10-28T20:31:52.270598+00:00
summary: Schema13 definition catalog, typed pure functions/query templates and FTS have scoped core/CLI proof; actions/forms/native bindings and EJ04/EJ05 remain open.
title: Shared application definitions and actions
status: reviewed
---
# Shared application definitions and actions

This elaborates E2 in [[records/specs/native-app-engine]]. It is an implementation
contract, not a statement of whole-feature completion. E1 is captured at cd5f854.
The schema13 definition catalog and pure computation slice now has core/CLI scoped
proof below. Shared actions/forms, result publication, native bindings and agent/
native journey qualification remain open. E3 owns durable multi-step execution; do not hide
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
