---
type: spec
id: 01m7bd3448sec8weav20n1fyht
created: 2026-11-13T21:30:20.679849+00:00
updated: 2026-11-16T03:39:31.331147+00:00
summary: Constrained Excel application reconstruction with original-result comparison; ten automatic workflows qualified against 89 independent originals within explicit limits.
title: Excel application reconstruction
status: implemented
---
# Recreate an Excel application with native controls

Extends [[records/specs/single-excel-import]] and [[records/specs/programmable-native-engine]]. Owner direction and acceptance gates: [[records/plans/excel-application-reconstruction]].

## One customer flow

Add or drop an `.xlsx` or `.xlsm`. The original is preserved. The local model reads cells, formulas and bounded original evidence, including readable VBA source, named ranges, validation, layout, charts/pivots and connection definitions. It proposes a workflow for review. Clarifications stay with that import. **Build workspace** creates native controls over the same imported tables, translates missing calculations and business actions, checks original results and runs isolated UI tests plus independent model review. **Open workspace** leads to the existing exact-version table-access approval. No web view or hosted model is introduced.

**Just use the tables** remains the no-model alternative within this flow. Existing-table updates remain a secondary reviewed action. Failures and Stop preserve the original and committed working data; a retry uses the same import and app identity. A copied or rebuilt app needs local access review. Saved calculations work without inference.

**Compare with the original** shows saved-result counts, varied-input cases and remaining gaps. **Add an original-result example** accepts a copy recalculated in Excel with the same worksheets, row coordinates and formulas. For a translated action, start from the original state, perform the action in Excel, save its result and enter the same action arguments in the native form. Up to twelve examples can be included. Removing one preserves its original source and makes a rebuild necessary. Example counts refer to comparison cases; one file can test both recalculation and an action.

## Small shared architecture

The existing conversion record owns original identity, inspected evidence, plan, stable table bindings, original row-identity digests, comparison examples and current app/report identity. The importer, managed tables, immutable history, formula plan, native app package and sandboxed app checker remain shared. There is no parallel database or separate spreadsheet UI engine.

A package may include `excelBehavior` with `source`, `outputs`, `actions` and `gaps`. Its source defines `function recreate(input)`. The input is `{event,cells,arguments}`; cells have exact keys such as `sheet1!B2` and string values. Worksheet aliases follow original nonempty sheet order; header rows retain their coordinates. The model receives explicit address/value and formula evidence, not just positional previews. It can page further evidence and compare candidates through narrow tools.

For `recalculate`, return every declared output as a string. Outputs must be **exactly the original formula cells**. Original expected outputs are removed before evaluation; derived dependencies must be calculated within the program. Reads of otherwise absent coordinates return Excel-style blank strings. Original input cells cannot be reclassified as automatic outputs. All input values, rates and business rules remain data rather than constants pasted into source.

An action declares an ID, human title, exact non-formula write set and named arguments. It receives freshly computed starting outputs. It returns only changes within that write set, then the host recalculates derived cells. The native UI calls `data.transaction([{op:'excel_action',action:'ship',arguments:{quantity:'2'}}])`. Table/version permissions, current revision, rollback, command identity and Undo apply. Cross-sheet input changes commit together before one recalculation. Undo and redo restore inputs and recalculate under the same rule, with final immutable row identities.

Publication repeats original comparison and atomically saves the app, comparison report and formula-plan attachment. It may recalculate exactly the original formula cells from current working inputs; it does not reset inputs to original values. That bounded calculation authorization is recorded by authoring policy v2. Interactive app writes/actions still need exact-version native access approval. Original row identities must still match their imported positions. Host-mapped appended input rows are excluded from that original-identity comparison and retain their stable coordinates across publication; replacing or removing original rows still refuses attachment. Pure program packages cannot bypass original comparison through ordinary standalone app import; use the Excel flow or carry an already checked workbook in a portable copy.

## Isolation and limits

The existing `sevra-extract` helper also runs pure behavior through the pinned QuickJS engine. Core and desktop do not link QuickJS. The helper reads its single private request, then enters a deny-default macOS sandbox before running code. Failure to enter refuses evaluation. No files, network, clocks, randomness, native APIs, timers or SDK are exposed. Native app UI code remains in its separate existing sandboxed XPC worker. Normal file extraction is process-isolated; only the arbitrary behavior mode enters this additional deny-default sandbox.

The pure runtime provides `calendar.addDays(isoDate, dayOffset)` for explicit Gregorian date arithmetic. It accepts a strict `YYYY-MM-DD` string in years 0001 through 9999 and finite numeric offsets within 3,660,000 days, including negative and fractional days. UTC arithmetic returns the resulting calendar date; invalid input and out-of-range results throw. The native Date constructor remains private to a closure, and only a string leaves the helper. Generated code has no Date, current-time or local-timezone API. This is not Excel serial-date/locale parsing or its fictional 1900 leap day; original-result comparison still decides whether a translation matches the source behavior.

Current bounds: 128 KiB program source, 2,000 formula outputs, 24 actions with at most 64 written cells and 16 named inputs each, 100,000 calculation cells/2 MB input text, 4 MB request, 1 MB serialized output, 32 KB per returned value, 64 MB JS heap, 512 KB JS stack, 500 ms JS interrupt budget, 4-second host deadline and 256 MB helper memory allowance. Native reconstruction is limited to twelve nonempty worksheets, existing 50-column app bindings, 64 KB prepared context and 2,000 isolated-check row positions. These are enforced resource boundaries, not claims of unlimited Excel compatibility.

OOXML evidence is inert and paged. ZIP entries, duplicate names, CRCs, traversal, expansion size and XML DTDs are checked. Bounded CFB/MS-OVBA decoding reads source modules without executing original code, bytecode or forms. The source decoder limits directory depth, sectors, streams, compressed back references and decoded text. Incomplete VBA, embedded/ActiveX binaries and external connections remain explicit evidence gaps. Image/layout inspection is not pixel-equivalence verification.

The local `sandbox_init` entry point is deprecated in the macOS SDK. Local denial probes and resource tests qualify the current host only; the implementation fails closed if unavailable. Production signing/notarization, platform migration and external security assessment remain separate qualification work.

## What verification establishes

The host reads immutable original bytes and derives expected results itself. It compares the baseline and user-selected result files, records their source hashes, conversion version and program digest, and refuses mismatches before publication. Formula outputs with no saved result remain unverified. Numeric comparison accepts only canonical numeric strings with a relative tolerance of 5e-14; leading-zero text remains exact. The host reports actions without original examples, missing evidence, model-declared gaps and behavior outside cell comparisons.

An original-result match covers those finite examples. It cannot prove all branches or detect every model misunderstanding or deliberately overfit program. Synthetic native tests prove the tested controls/transactions, not original spreadsheet equivalence. Separate model review checks the requested workflow through independent behavior probes, but is also fallible. These evidence classes remain distinct in the saved report and customer copy.

Input ledgers without formulas now append stable Excel coordinates inside the same transaction and recalculate dependent native or translated outputs. Undo leaves a coordinate tombstone, so a later insertion cannot shift old references. Translations must read current input cells within the original formula ranges. Sheets containing formulas still refuse ambiguous row insertion; automatic copying or inference of new formula rows is not implemented. Original VBA and connections never execute, and credentials or service integrations are never inferred. Binary `.xls`/`.xlsb`, encrypted originals, unavailable dependencies, exact Excel rendering and every possible Excel semantic are not qualified. Such gaps must remain visible; preserving a file is not the same as reconstructing all of it.

## Developer references

The parser follows Microsoft's [MS-OVBA compression](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ovba/492124cc-5afc-48c8-b439-b42ad7087a7b), [module records](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ovba/f6475ef5-0436-47c6-b31f-ea8f23810dc6) and [CFB format](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/05060311-bfce-4b12-874d-71fd4ce63aea). Fixture provenance is [documented with the fixtures](../../../integration/fixtures/excel-behavior/README.md). Independent spreadsheet results come from LibreOffice, not a Microsoft Excel execution test. Acceptance evidence and remaining qualification belong in the owning plan/review.

## Qualification checkpoint, November 14

Automatic conversion is qualified for ten finite business workflows under [[records/plans/automatic-excel-reliability]]. Ten unchanged local-model-generated candidates from successive runs pass 89 independently recalculated originals (84 comparison cases and five held-out states), 302 independent UI steps, 79 saved-edit/reopen/Undo cases and ten portable copies on the final code. Loan and Commission use native formula evaluation; Inventory uses a constrained translated business action. No generated source is manually repaired. Native UI checks include spacing, compact layouts, initial/input guards, invalid values, repeated edits and Undo. The [acceptance receipt](../../../integration/evidence/2026-11-14-automatic-excel-reliability.json) records exact-code hosted checks, package identity and retained failures. Finite examples cannot prove every business rule or first-attempt generation reliability; generation can still fail or take minutes. Original action-execution equivalence remains unverified. Earlier reviewed derivatives are historical and are not counted as automatic generation.

## Business-app integration work

[[records/plans/excel-business-applications]] owns the current six-application cohort and its qualification. The build separates missing-calculation translation from interface/action authoring, retains only a matched draft, and repeats original comparison before publication. Native SUMIF/SUMIFS and SUMPRODUCT join the bounded declared formula subset. Conditional sums preserve typed criteria and wildcard matching; SUMPRODUCT supports bounded arithmetic/comparison arrays with shape validation and explicit logical coercion. A deterministic shared work budget bounds the complete recalculation pass, including numeric-text and comparison work. This does not remove original-result comparison or establish all Excel criteria/locale equivalence.

Disposable app checks receive the original formula definitions and worksheet names over invented input rows, never original business values or row identities. Both native and translated calculations run after synthetic actions. The conversion grammar requires a fixtures object. The separate reviewer examines ordinary named record actions as well as UI calls to translated fixed-cell operations; calculation comparison alone does not verify validation, duplicates, stock limits or input conventions.


Independent Excel named-action review withholds the candidate implementation and the builder's tests so they cannot become
expected-value authority. To accept a named action it must execute a successful call
followed immediately by a saved-value assertion, or a value/text assertion for a read-only
result. Rejection-only probes, total row counts and control presence do not satisfy that
successful-effect coverage. The reviewer also probes requested business boundaries,
including actual worksheet headers used as entity keys. Probes use separate invented
fixtures, 1..16 steps and up to four new actions per batch, with a bounded review budget.
Every probe executes against the proposed package before acceptance. Expectations and
business interpretation remain model judgments; the independent business harness and
spreadsheet oracle are separate qualification. Current broader acceptance is pending in
[[records/plans/excel-business-applications]].

Each ready action batch also classifies every supplied input in `inputRoles`: a new/entered
value, or an existing key with its worksheet alias, column and original header row. The
host validates that mapping and reads the exact header cell from the verified retained
original, independent of the bounded model excerpt. Sparse row coordinates and skipped
empty sheets retain their original mapping; formula outputs cannot be lookup headers,
and headers over 4 KiB refuse without truncation. String-key probes substitute
that header into the successful call, replay only the prior setup in a fresh disposable
workbook, and require rejection without writes. The successful call itself is not replayed
first, because duplicate-reference checks could mask the invalid key. Fixture headers
must be unique at their original positions. Successful numeric/boolean input contracts
already prevent text headers reaching their handlers. Receipts retain classifications,
original cells/headers, exact probes and package digests. The bounded reviewer can correct
an inconsistent verdict without resubmitting the candidate source; exhausted review
still refuses publication. Classification remains a model judgment, not universal proof.

Actual number/decimal inputs must instead declare requested whole-number, inclusive
minimum/maximum and nonzero rules. The host derives typed counterexamples from an
independently successful call. Whole-number and boundary variants avoid violating other
applicable rules; narrow ranges use an in-range fractional midpoint. Values that cannot
be represented within the checked numeric type refuse rather than silently losing a
probe. Each header or numeric variant receives its own worker and only the exact setup
preceding the successful call. Refusal must commit no writes. Separate workers also
prevent a rejection's transient closure state from masking another invalid input.
Receipts retain individual rule/value/tests/check digests. These checks validate declared
rules; the model can still misunderstand which rules the business actually requires.


For named-action review, the host provides the executed action input contracts, initial native control identities/labels (without value/text properties), original cells/formulas and available original logic. The reviewer derives expected effects before running the candidate. A saved-row assertion must follow a successful named action with a host-observed committed write; matching a pre-existing row after a no-op does not establish a saved effect. Read-only actions may use value/text assertions. Receipts distinguish contract probes from source review and retain committed-write counts by test-step index. These checks do not establish universal equivalence or replace independent business journeys.

An independent effect on an original worksheet compares exact saved strings or null.
Named-action input types remain independent of worksheet storage. A reviewer classifying
a matching original heading and a unique synthetic fixture key as free text must show
a valid fixture-independent value or classify the lookup against its actual source.
The hint does not invent a business rule and does not override explicit SDK choices.
Admissible zero and fractional variants also check handler completion when faithfully
representable without widening the starting magnitude. The independent business corpus
still checks their exact saved effects and Undo. Neither review nor reported original
examples prove universal equivalence.

## Disputed numeric rules
The first reviewer receives the original worksheet validation operator, formulas and explicit blank or error metadata where available. When a derived numeric action's observed result disagrees with the review, a new structured local interpretation receives only the exact field and typed value, actual user clarification and bounded original worksheet validation or readable VBA evidence. It cannot see candidate source, its observed result or the earlier rule. A decision to forbid requires a literal supporting original passage. A user passage must identify this specific field. An unclear answer blocks publication. The host must independently reproduce a reversed expectation in the same isolated state before it changes the accepted rule. Review coverage records the executed typed probes under their actual action IDs.

The first reviewer may express input roles by field if the fields are unique across its exercised actions and every role maps to one exact supplied input. The saved review always groups those complete roles by action. The ordinary role, evidence, typing and probe checks still apply. An inconclusive independent review remains a retryable review failure. A later verified counterexample from the same draft is a distinct outcome that can be used for repair under the normal build step limit.

A successful isolated named-action probe accounts for every input it changes. The checker reads committed broker receipts, identifies the affected logical records and compares each direct input with the exact saved row asserted by the reviewer. An unrelated row cannot witness a change. The checker requires identifying values for removals and treats an ambiguous match as incomplete evidence. Recomputed formula outputs require no additional input write. A repeated idempotent receipt does not count as a second commit. A saved row that was already present establishes no write by itself.

The host checks derived input variants using contracts already observed in the isolated builder check. An authored refusal with invalid setup cannot block an otherwise executable check of an original worksheet heading. Those derived variants still use the exact earlier setup and run in disposable worksheets. Every submitted ready probe must still pass before publication. The model derives the expected effects from original evidence and clarification, and the held-out operating corpus checks the saved workbook separately.

Tentative lookup detection uses the original heading even when a synthetic fixture omits it. A successful call that reuses a unique fixture key under an exact original heading needs a verified lookup role or a distinct valid free-text example. Unambiguously malformed or truncated review responses use the remaining review attempts. Their diagnostics remain available and no partial verdict can authorize publication.
