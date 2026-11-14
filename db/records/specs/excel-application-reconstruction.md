---
type: spec
id: 01m7bd3448sec8weav20n1fyht
created: 2026-11-13T21:30:20.679849+00:00
updated: 2026-11-14T17:22:25.276055+00:00
summary: Native Excel behavior translation, original-result comparison and constrained calculation/action contract
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

Publication repeats original comparison and atomically saves the app, comparison report and formula-plan attachment. It may recalculate exactly the original formula cells from current working inputs; it does not reset inputs to original values. That bounded calculation authorization is recorded by authoring policy v2. Interactive app writes/actions still need exact-version native access approval. Row identities must match the original imported positions, preventing attachment to inserted/replaced rows. Pure program packages cannot bypass original comparison through ordinary standalone app import; use the Excel flow or carry an already checked workbook in a portable copy.

## Isolation and limits

The existing `sevra-extract` helper also runs pure behavior through the pinned QuickJS engine. Core and desktop do not link QuickJS. The helper reads its single private request, then enters a deny-default macOS sandbox before running code. Failure to enter refuses evaluation. No files, network, clocks, randomness, native APIs, timers or SDK are exposed. Native app UI code remains in its separate existing sandboxed XPC worker. Normal file extraction is process-isolated; only the arbitrary behavior mode enters this additional deny-default sandbox.

The pure runtime provides `calendar.addDays(isoDate, dayOffset)` for explicit Gregorian date arithmetic. It accepts a strict `YYYY-MM-DD` string in years 0001 through 9999 and finite numeric offsets within 3,660,000 days, including negative and fractional days. UTC arithmetic returns the resulting calendar date; invalid input and out-of-range results throw. The native Date constructor remains private to a closure, and only a string leaves the helper. Generated code has no Date, current-time or local-timezone API. This is not Excel serial-date/locale parsing or its fictional 1900 leap day; original-result comparison still decides whether a translation matches the source behavior.

Current bounds: 128 KiB program source, 2,000 formula outputs, 24 actions with at most 64 written cells and 16 named inputs each, 100,000 calculation cells/2 MB input text, 4 MB request, 1 MB serialized output, 32 KB per returned value, 64 MB JS heap, 512 KB JS stack, 500 ms JS interrupt budget, 4-second host deadline and 256 MB helper memory allowance. Native reconstruction is limited to twelve nonempty worksheets, existing 50-column app bindings, 64 KB prepared context and 2,000 isolated-check row positions. These are enforced resource boundaries, not claims of unlimited Excel compatibility.

OOXML evidence is inert and paged. ZIP entries, duplicate names, CRCs, traversal, expansion size and XML DTDs are checked. Bounded CFB/MS-OVBA decoding reads source modules without executing original code, bytecode or forms. The source decoder limits directory depth, sectors, streams, compressed back references and decoded text. Incomplete VBA, embedded/ActiveX binaries and external connections remain explicit evidence gaps. Image/layout inspection is not pixel-equivalence verification.

The local `sandbox_init` entry point is deprecated in the macOS SDK. Local denial probes and resource tests qualify the current host only; the implementation fails closed if unavailable. Production signing/notarization, platform migration and external security assessment remain separate qualification work.

## What verification establishes

The host reads immutable original bytes and derives expected results itself. It compares the baseline and user-selected result files, records their source hashes, conversion version and program digest, and refuses mismatches before publication. Formula outputs with no saved result remain unverified. Numeric comparison accepts only canonical numeric strings with a relative tolerance of 5e-14; leading-zero text remains exact. The host reports actions without original examples, missing evidence, model-declared gaps and behavior outside cell comparisons.

An original-result match covers those finite examples. It cannot prove all branches or detect every model misunderstanding or deliberately overfit program. Synthetic native tests prove the tested controls/transactions, not original spreadsheet equivalence. Separate model review checks the requested workflow and code, but is also fallible. These evidence classes remain distinct in the saved report and customer copy.

No automatic row-insertion formula extension is implemented. Original VBA and connections never execute, and credentials or service integrations are never inferred. Binary `.xls`/`.xlsb`, encrypted originals, unavailable dependencies, exact Excel rendering and every possible Excel semantic are not qualified. Such gaps must remain visible; preserving a file is not the same as reconstructing all of it.

## Developer references

The parser follows Microsoft's [MS-OVBA compression](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ovba/492124cc-5afc-48c8-b439-b42ad7087a7b), [module records](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-ovba/f6475ef5-0436-47c6-b31f-ea8f23810dc6) and [CFB format](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/05060311-bfce-4b12-874d-71fd4ce63aea). Fixture provenance is [documented with the fixtures](../../../integration/fixtures/excel-behavior/README.md). Independent spreadsheet results come from LibreOffice, not a Microsoft Excel execution test. Acceptance evidence and remaining qualification belong in the owning plan/review.

## Qualification checkpoint, November 14

The engine contract is implemented and verified; see [[records/reviews/excel-reconstruction-and-engine-review]]. Automatic model conversion is not consistently reliable. Latest unassisted Inventory and Loan trials failed safely. Reviewed example programs are explicitly distinguished from fresh model output. Forty-three independent original files and finite synthetic tests establish bounded behavior, not universal business equivalence.
