---
type: spec
id: 01m61v3tcay3v380asyfhvg260
created: 2026-10-28T18:07:17.386524+00:00
updated: 2026-10-29T07:08:10.456196+00:00
summary: Schema18 definitions, reviewed CSV/TSV intake and queued native workflows have scoped proof; full journeys and release gates remain open.
title: Shared application definitions and actions
status: reviewed
---
# Shared application definitions and actions

This elaborates E2 in [[records/specs/native-app-engine]]. It is an implementation
contract, not a statement of whole-feature completion. E1 is captured at cd5f854.
The current schema18 catalog retains scoped core/CLI registered inventory actions and
recoverable native form implementation in addition to the earlier pure computation.
Agent tools, focused native forms, reusable native computation and exact result
publication have scoped qualification below. Full EJ04/EJ05 remain open. E3 owns durable multi-step execution; do not hide
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
Workflow now has the scoped manual core/CLI executor in [[records/specs/manual-workflows]]. Agent workflow authoring and native workflow surfaces now have scoped qualification in that specification. Automation kinds remain refused until their paths qualify.
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
snapshot-bound cursors and explicit result/coverage metadata. Decimal comparisons
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
and snapshot-bound. No broad table/catalog injection into every model prompt.
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

The initial development schema14 implementation extended the immutable definition catalog to action and
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


## Agent integration contract

Expose bounded definition discovery/inspection and registry/templates on demand,
pure evaluation, versioned authoring, action preview and submission. Do not inject
the whole catalog into the default prompt. Definition metadata and evaluation
arguments are untrusted data; they never become present action authority or proof
of original business facts. Read exact versions before use. Pure evaluation is not
publication. Saved query rows qualify only through their visible row values and
exact item versions; omitted results and catalog hits do not establish absence.

The host selects a deterministic new logical identity for a create request. An edit
requires the existing logical identity and inspected exact base. Source attribution
uses the actual AI caller and captured current request. Read-only requests permit
discovery/evaluation/preview, but refuse authoring and submission even through forms.
Generated native space components may bind an existing form; its core signature,
snapshot refusal and draft lifecycle rules remain in force.

The native `prepare_action(id, arguments)` request journals a fresh read-only
preview within its current active run and conversation. The internal
`commit_action_preview` stage accepts only that successful exact receipt. The host
loads and hash-checks the saved plan rather than letting the model reconstruct it. The plan remains tied to its exact
definition, arguments, fingerprint and current request. Invocation rechecks it under
the canonical write lock and uses the ordinary shared retry/domain path. Historical,
failed, foreign-run, wrong-tool, prepared or malformed receipts refuse. A receipt is
data, not permission; the current request still controls execution.

Before AI inventory submission, an isolated read-only semantic check covers every
resolved movement. It sees only the current request, subjects and bounded original
evidence excerpts, never the action's title, proposed signs, previous interpretations
or instructions from a definition. For a batch, return one indexed direction verdict
per movement, with an exact contiguous quote in its own request/evidence. Reject
missing/duplicate/out-of-range verdicts, unverified quotes and any wrong or unclear
direction. Bound the shared original-evidence text budget and disclose omission;
omission is not evidence of direction. Failure creates no proposal or invocation
Source. Keep the complete review receipt with the tool result. Successful batches
end in a host-rendered needs-review result with exact proposal links and accepted
balances unchanged, without a model claim of acceptance or document fidelity.

Qualify deterministic core receipt/run guards, same-token behavior, read-only and
stale preview refusal, batch direction isolation/coverage/quote/sign errors,
definition edit attribution, form component bindings, native tool JSON/masks and
continuation evidence boundaries. Then test the actual selected local model on
authoring, finding/using a saved action, ambiguous direction and query/calculation
journeys. Scripted inference is integration proof, not real-model qualification.
Record failures and limits before claiming EJ04/EJ05 complete.


## Captured family snapshots and focused tools

Definition catalog pages use `meta.definition-read-snapshot`; managed query pages
use `meta.dataset-read-snapshot`. Relevant writes update these clocks to the same
transaction's commit identity before capture publishes. Both are ordinary captured
metadata in the existing ledger. Journal, context, conversation and presentation
writes do not invalidate their own read continuations. Relevant business/definition
edits still refuse a stale cursor. Function evaluation reports the hash of both
family snapshots. Reconstruction preserves the recorded values without recomputing
results or executing definitions. No physical table/schema change or extra ledger.

The native model sees focused tools: `find_definitions`, `read_definition`,
`definition_registry`, `receiving_template` and `form_template`, plus
`evaluate_definition`, `save_definition`, `save_template`, `preview_action` and
`prepare_action`.
Search has query/kind/historical/cursor; read and form-template take exact version
IDs; registry and receiving-template have no arguments. Strict generation no longer
allows a search query to leak into those no-query operations. The earlier multiplexed
operation API was an uncommitted experiment; no compatibility adapter is retained.
Common property-label descriptions are omitted from prompts, with every required
field, structural bound, enum and host validator unchanged. Authoring formats and
registry details load on demand. `save_definition` requires custom `content`;
`save_template` requires a successful current-run `templateReceiptID`, optionally
changing only the title. The host copies and verifies its exact ordinary template
instead of asking the model to regenerate booleans, signatures and form fields.
Mixed custom/copied content, failed, prepared, foreign, wrong-tool or altered
receipts refuse. The two save tools share canonical versioning, request provenance,
run cancellation and read-only checks. Required input schemas prevent a title-only
call from reaching either path. The earlier overloaded save contract was also an
uncommitted experiment; it has no compatibility adapter.

Submission's isolated semantic check uses at most ten indexed movements per call
and five calls for fifty lines. The evidence budget is 16,000 UTF-8 bytes across
unique Sources, clipped without splitting a scalar. Exact quote verification uses
bytes, so Unicode normalization cannot silently change the quoted original. A late
unclear group refuses the entire batch. Full result-publication, native query/
function composition and EJ04/EJ05 remain separate unfinished work.


## Preview and submission truthfulness

A successful `preview_action` proves a read-only plan, never saved proposals. After
a preview, `finish` must explicitly use `basis=preview`; the host renders the
quantities, subjects, meanings and effective dates from its exact current-run plan
and states that no drafts were saved. It discards model-authored preview prose.
A missing preview or count receipts mixed into that basis refuse. A model trying
to end with another basis after preview receives corrective feedback: submit the
current preview receipt to prepare requested drafts, or explicitly show the preview.
A successful submission already ends through the host-owned needs-review receipt.
Direction/refusal paths already return their exact host clarification without a
model completion claim. This boundary does not qualify arbitrary compound preview
and analysis responses; unsupported combinations must remain explicit.

Plan effect copy uses each resolved movement's actual meaning. An estimate preview
must not be labeled actual, and accepting a forecast/estimate never turns it into
an actual. Native confirmation opens the saved proposals' current status rather
than treating an old form receipt as proof that they are still pending.

## Cold startup and native input behavior

The native engine startup allowance is 360 seconds so first-start native Metal
compilation can complete on the supported Mac being tested. Progress explains that
first start may compile native components. This changes neither generation deadlines
nor output/reasoning limits. Cancellation must still promptly terminate and reap
the exact owned helper, even if it ignores ordinary termination. Cold-start timings
under concurrent builds are functional observations, not a throughput benchmark.

Evidence selection uses a native selectable list and a distinct Choose confirmation.
Search changes clear selection; confirmation only binds a currently displayed match
from that exact loaded query. Keyboard selection and Return must work without a
coordinate-only click. Opening evidence and returning retains the form inputs.
Full VoiceOver, media and appearance qualification remain independent gates.


## One requested preparation, host-owned validation

The V8 real-model run stopped truthfully at a preview when the user requested saved
drafts. The native tool contract therefore replaces the uncommitted `submit_action`
interface with `prepare_action(id, arguments)`. This is one user-level preparation
operation. The host records a successful internal read-only preview, loads that
exact active-run receipt, checks every movement direction and invokes the shared
canonical commit path. The preview receipt and complete semantic review remain in
the outer preparation receipt. Invalid input, ambiguity, read-only mode, stale
bindings or cancelled runs publish no draft. No model-generated plan is trusted.

`preview_action` remains for an explicitly requested unsaved plan, using the host
preview finish above. A later request to prepare uses fresh exact inputs and a new
host preview rather than turning historical preview state into authority. The
core's current receipt commit stage is `commit_action_preview`, used by the host
and qualified directly; it is not exposed in the native model schema. The earlier
model-facing submit name has no adapter. CLI `action-preview`/`action-invoke` retain
their independent explicit canonical contract. Success is still draft-only and
terminates with a host-owned needs-review result.


## Agent and visible native qualification, October28

[agent application definition receipt](../../../integration/evidence/2026-10-28-agent-application-definitions.json.gz) retains the final46-tool declaration,52 actual grammar
cases/425 exact masks and8,121/8,192-token largest bare prompt. The fixed gate and
1,800-output/512-reasoning bounds remain. Core223, Splash31 and the broad shared
checks pass. Five real selected-model tasks pass: function author/evaluate, receiving
action/form saved on Home, requested two-draft preparation and ambiguous-direction
clarification without new business effects. Functional timings are not throughput
qualification. V1-V9 failures and the startup-helper cleanup remain recorded.

`Item.technicalKinds` defines request, annotation, application_definition and
application_invocation as technical metadata. Default business search, Recent,
reference discovery and agent evidence reads exclude them. Exact owner search can
explicitly select a technical kind, and definition inspection/history retain it.
Independent single/batch direction reviewers receive no original business text from
technical Sources or derived Records. Current request text can still supply meaning.
No accepted physical-event or semantic-correctness claim follows from a model check.

The latest native receiving form preserves incomplete inputs across quit/reopen,
opens exact evidence and returns, supports keyboard list selection and empty-search
feedback, previews/saves one draft and reaches review. Accept/undo/restore changes
stock 20/25/20/25 with one effect at most. Final verify passes. These are focused
visible AX/keyboard observations, not actual VoiceOver or full appearance/media
qualification. Result publication/native computation views and full EJ04/EJ05 remain
open, together with E3-E6 and the release gates in the implementation record.

## Native computation views and explicit result publication

E2 uses calculation/query native components with a live/exact definitionBinding
and explicit typed arguments. Evaluation stays read-only, bounded and off the UI
actor. Show argument values, units, errors and exact inputs. Query pages retain row
meaning/status/scenario and disclose partial coverage; changed inputs or definitions
invalidate a continuation. No data entry form, SQL or external effect is inferred.

Pinning captures the displayed first evaluation page, exact resolved definitions,
values, coverage and the exact scoped query input population. A partial pinned query is labeled as a saved first page and
cannot silently load current rows. Only the trusted pin path creates these snapshots;
ordinary authored layouts cannot supply or alter claimed evaluation snapshots.
Existing pinned layouts retain their values through label/order edits and replay.

Publishing is separate from display: compare the exact inspected evaluation with a
fresh computation under the canonical write lock, then atomically save an invocation
Source and a draft derived Record, retaining actual actor, submitted arguments,
explicit meaning/scenario, exact definitions and original evidence. A changed input,
read-only request, cancelled run, invalid/partial output or oversized provenance
refuses without a partial publication. Exact retries return the original result.

For complete bounded query publication, preserve the exact scoped input population,
including candidates removed by filters or joins, rather than claiming per-group
membership from an aggregate row. Label that provenance scope. Initial qualification
caps saved input populations at 5,000 scoped row-version entries and each retained
result at 512 KiB, including its provenance. Apply the same bounded closure to
pinning and publication. Refuse larger saves explicitly; normal read-only paged queries remain available. This is a
qualification boundary, not a claim that large workbook queries are complete.

EJ05 proof must reuse a calculation/query in two spaces and a report, change data
and a live called function, retain a prior pinned/published result, refuse stale
publication/cursors, show meaning and partial pages, and preserve both through inert
reconstruction/portable export. Native races and visible input/coverage/error states
need their own focused evidence. This design section is not completion evidence.


### Result presentation and discovery refinement

Saved query result cells also have deterministic reading/search text. Keep the typed
values, scopes and immutable input versions in Record data; searchable text does not
replace structured authority. Native saved-result rendering requires an actual
host-publication lineage transformation, or a review version preserving that exact
result data. Merely copying evaluation-shaped JSON into a proposed Record does not
prove that the core calculated it. Review keeps meaning separate from acceptance.

Ordinary unfiltered agent search discovers business evidence, scoped conversation
and up to four current definition metadata matches in separate fields. Filtered or
continued business searches do not broaden into either other scope. Metadata stays
outside business hits, citation admission and direction-review evidence. Catalog
matches instruct the agent to inspect an exact version and use find_definitions for
full bounded pages. No match remains an observation about the searches performed.
This closes a practical discovery gap without making technical Sources into business
proof or providing any new write permission.

## Computation qualification checkpoint, October 28
The [native computation receipt](../../../integration/evidence/2026-10-28-native-computation.json.gz) retains core231,47 native tools,57 grammar cases/492 exact pinned-reference masks and the fixed8,176/8,192-token bare-prompt gate. V32 broad shared checks pass. Focused final core/agent/native/package checks qualify subsequent receipt, separated-search and UI fixes; unchanged broad results are reused under the verification policy. No reasoning/output gate increased.

Four V5 selected-model tasks pass: a saved calculation in two native spaces, complete query publication as an estimate draft, an exact-result-derived draft report, and comparison of changed live data with the preserved result. V1-V4 failures remain in the receipt. Timings are functional latency under build activity, not throughput qualification.

Successful evaluate_definition includes its host-generated receiptID. Publication requires the same active run/conversation's intact completed first-page receipt; the host strips receipt metadata before comparing canonical values. A snapshot hash is not a tool receipt. The final scripted agent consumes the actual visible response and confirms optional review without acceptance.

Visible native checks show live30/33/42 after explicit definition edits, pinned36, saved query values/provenance, one-row Next/Previous pages and a pinned first page with no live continuation. The item-bound save sheet retains its chosen evaluation. Stale refusal appears inside it with title/scenario retained and no result Record. Refreshed42 saves as an estimate draft and remains an estimate with unchanged exact data after native acceptance. Internal empty arrays do not appear as scalar fields.

Final packaged CLI, portable/inert reconstruction, full native Metal/resources/refusals/signature, strict29-file Swift lint and skill checks pass. Isolated baseline installation passes after repairing its import-response assertion. Native Splash stays separate from the preserved Slotstream baseline. Full EJ04/EJ05 scale/voice, broad accessibility/appearance/media/hardware gates, E3-E6, Excel continuity and notarized release remain open.

## Conversation workflow surface
Workflow discovery/save/form templates reuse the same catalog validation and exact-base writes. workflow_activity/read_workflow are bounded reads. start_workflow queues an exact saved workflow with explicit typed inputs, current AI request lineage and in-transaction authority revalidation. It never executes a step. A host-owned terminal receipt names saved status and native Activity; business acceptance remains separate. Read-only and unrelated task handoffs cannot queue runs. See [[records/specs/manual-workflows]] and the [scoped receipt](../../../integration/evidence/2026-10-28-agent-workflows.json.gz). Full workflow AI execution remains open.

## Explicit interpretation definitions, schema16
A reusable interpretation declares bounded instruction text, required exact business item evidence parameters,1..32 typed output fields without defaults, meaning and scenario. Exact interpret workflow steps capture full bounded text/data or ready/untruncated extraction, actual model/schema/budget/read revision and exact quotations. Output is a separately reviewable draft Record. No tools, raw code, search or acceptance run inside interpretation. Typed named output mappings and transitive calculation lineage retain actual/estimate/scenario boundaries. See [[records/specs/manual-workflows]] for contracts and scoped core/native/actual-model qualification.

Core/CLI and conversation save_definition/find_definitions now author/discover interpretation with scoped grammar/model qualification in [[records/specs/manual-workflows]]. In-app creation omits expectedDefinitionID; editing supplies only its exact inspected base. The host derives identity. workflow_template copies exact validated behavior parameters/bindings for save_template without execution. Standalone evaluate_definition remains pure function/query evaluation. No implicit inference on discovery, opening, reconstruction or saved Home rendering.

## Native document preparation definitions, schema17
extraction declares payload parser=native-v1 and file=the one required item parameter ID, without defaults or units. Exact extract workflow steps accept an included business file; no folder/path/network capability is granted. Map a completed extract output with {step: PREPARE_ID, field: item} to an interpretation item parameter to pin its exact retained extraction. Saving a definition never parses or invokes a model. Core/CLI preparation authoring and native execution have scoped proof in [[records/specs/manual-workflows]]. Conversation discovery/save and workflow_template now support extraction with scoped grammar/actual-model qualification in [[records/specs/manual-workflows]]. Authoring inputs are exact existing item-version UUIDs, not parameter names. Current request lineage is automatic; saving/queueing does not parse or execute.

## Registered document action, schema17

records.draftDocument v1 declares required title/body/evidence/meaning/scenario. The body is new prose up to 16,384 UTF-8 bytes, with no original-copy fidelity claim. Its preview is pure; execution creates one lineage-bound draft document through the shared captured action transaction. Retry returns that same proposal. Native forms retain multiline inputs and recover the committed receipt without duplication. Workflow review accepts only unchanged direct acceptance successors for movements or documents, with exact meaning/scenario and decision provenance. Mapped estimates cannot become actual reports. Document acceptance never changes stock.

The registry exposes the distinct workbook.draft_document capability. Direct registered-action chat submission remains closed while native forms, CLI and explicit workflow continuation have scoped proof. Existing inventory semantic direction checks remain intact. The existing draft tool and exact-source composition remain separate surfaces. See [[records/specs/manual-workflows]] for the current qualification and remaining E3/EJ release limits.

## Structured intake definitions, schema18

The intake kind describes one reusable reviewed CSV/TSV update over an existing managed dataset. Parameters contain exactly one required item with no default or unit. Payload fields are parser (native-v1), file (that parameter ID), datasetID, definitionID (exact schema version), mode (append/replace/merge), mapping, keys, headerRow, newRowMeaning and newRowScenario. mapping accounts for every consecutive input position using {position,target}, where null explicitly ignores a column. Each stored target column is mapped once; calculated targets refuse. Merge requires distinct mapped keys; append/replace use an empty keys array. Header row and incoming meaning/scenario are explicit. Current schema/archive checks apply at save and execution; historical integrity uses its saved schema.

One dataset dependency and ordinary authoring Source retain the schema/mapping. An exact intake workflow step supplies the included business-file version and must have one later review. Parsing outside locks returns a host-only opaque preparation. The shared table-update insertion/application path owns both direct and workflow row changes; no new SQL family, parser in a mutation or separate ledger. Native Activity shows affected counts and new-row semantics, with exact proposal navigation. Recoverable workflow forms queue inertly. In-app conversation save/template authoring for intake now has scoped exact-mapping, mandatory-review, inert-queue and explicit missing-intent qualification. It adds no execution authority. See [[records/specs/manual-workflows]] for bounds, exact review provenance and current proof.

## Workflow scalar lookup

Saved workflow evaluate-query steps now permit {step,field,unit?} mappings into matching scalar parameters. The first boundary requires one ungrouped source and exactly one complete result row. Every consumer field is validated before checkpoint; null/empty/ambiguous/partial matches refuse. Exact selected row versions and query Source join transitive action lineage and meaning checks, including after later catalog edits. Explicit catalog repair/retry preserves completed preparation/model work. No new schema/catalog or first-row guessing. Contract, proof and remaining limits: [[records/specs/manual-workflows]].

## Interpretation clarification

Interpretations returning needs_input preserve their original result and declared schema. An exact current target may receive complete typed supplied values and reason through shared core/CLI. This creates a separate Source/Record and downstream lineage, without changing meaning/scenario or accepting business effects. Model defaults remain prohibited. Native response grammar now constrains state and values together in one result parameter and shares terminal validation. Human provenance is reserved for actual native submission; CLI remains programmatic and AI submission is closed. Contract and scoped proof: [[records/specs/manual-workflows]].

## Native clarification controls

Shared declared output types drive the native clarification editor. Raw incomplete values remain presentation data until complete typed preview and deliberate human submission. The original model result, meaning/scenario and evidence scope stay fixed. Reuse the exact core clarification operation and canonical receipt; no new definition kind or execution authority. Persistent input/lifecycle proof is scoped in [[records/specs/manual-workflows]].
