---
type: operational
meta-type: operational
id: 01m7ebv28bxsk6szwx72sbrcyp
created: 2026-11-15T01:06:11.339074+00:00
updated: 2026-11-15T16:57:31.492551+00:00
summary: Close realistic Excel business application reconstruction, reliable autonomous generation, and integrated chat/native qualification gaps.
title: Realistic Excel business applications
status: in-progress
---
# Realistic Excel business applications

Authority: [[sources/notes/2026/11/excel-business-applications]]. Builds on [[records/plans/fresh-excel-batches]] and [[records/plans/chat-primary-operation]]. Starting integrated code is a238bea. Work directly on main. Preserve previous evidence and unrelated work.

## Outcome and acceptance defined before trials

A person can import a realistic Excel business application, explain the work, review the inferred workflow, let the local model build and repair a native app, approve exact table access, and operate it through conversation and native views. Daily work includes new records, related-table updates, live calculations, explicit input refresh, validation, missing-input clarification, persistence and Undo. Original files remain immutable. No original macro, hidden network connection, credential request, hosted fallback or manually repaired generated app is used.

Use six synthetic business applications with distinct multi-sheet dependencies and meaningful row counts. Synthetic facts must be labeled as such; these are realistic workflows, not customer adoption evidence. Source formulas and independent spreadsheet recalculations define expected outputs. Action outcomes have independently authored state assertions and retained original-result examples where applicable. Hold out changed inputs, new records and invalid states from generation. Generated code must not receive the verifier, expected-result tables or reference JavaScript.

Acceptance requires two consecutive complete six-application fresh batches on unchanged final code and acceptance checks. Each starts with new workbooks, new analysis and generation requests, no retained apps or prior conversations. Ordinary bounded automatic repair is allowed. A production or acceptance change resets the count. Retain every failed trial, refusal, repair, elapsed time, source/runtime hash and final source provenance. Repeat the earlier ten-workflow regression on the combined runtime as a separate regression, not a fresh-generation claim unless it actually generates anew.

## Corpus and business journeys

1. Stock and purchasing: products, purchase/receipt records, shipments and reorder view. Receive and ship stock, reject overdrawn or duplicate operations, add a record, and refresh a supplied price file without silently enabling an external connection.
2. Invoicing and payments: customers, invoices, payment ledger and receivables. Create an invoice, record partial/full payments, preserve zero/credit behavior, reject unknown keys, update balances and Undo all related effects.
3. Job costing: jobs, staff rates, timesheets and job profitability. Enter time, change an applicable rate, distinguish billed revenue from cost, add a later record, summarize by stable job/employee keys and preserve unrelated jobs.
4. Production planning: bill of materials, stock, production jobs and capacity. Change planned quantity, compute component demand/shortages/yield, record a production action atomically and reject insufficient resources.
5. Cash and loans: receipts/payments, debt schedule, assumptions and cash forecast. Recalculate interest/payment/closing balances after changed inputs, preserve period boundaries, zero/negative/blank distinctions and decimal rounding.
6. Service bookings: resources, bookings, customer records and utilization. Add/reschedule/cancel a booking, reject conflicts, ask for missing inputs, recalculate capacity/revenue and survive reopen/Undo.

## Implementation passes

- [x] Trace the integrated import, generation, comparison, row-growth, refresh, approval and shared chat/native session paths. Record concrete gaps before changing them.
- [x] Build versioned readable XLSX/XLSM fixtures, independent recalculated originals and held-out action/state scenarios. Verify source formulas and inspect every source sheet.
- [x] Add a reusable integration harness using production analysis/build/approval/session paths and the installed local model. Check real persisted effects and truthful completion after chat actions, not response wording alone. Never repair generated source.
- [x] Run diagnostic applications. Fix generic context, tool, runtime, formula/row-growth, verification and repair failures with focused counterexamples. Keep original expectations and authority boundaries intact.
- [ ] Complete the two fresh six-application cohorts and the earlier ten-workflow regression on the integrated candidate. Record first-save/retry counts and elapsed distributions honestly; no inferred production success rate.
- [ ] Inspect all six generated native apps and the import/clarification/approval/chat journeys, including loading, errors, spacing, row alignment, compact windows and shared state after chat edits. Fix observed product defects and recheck affected paths.
- [ ] Adversarial passes: hostile workbook evidence and prompt injection; code capability isolation/resource bounds; cross-table/row/formula permissions; missing/ambiguous/duplicate inputs; rollback/stale/version/approval replay; fabricated success and overfitting; copied-workbook authority; cancellation/reopen/Undo; evidence freshness and source provenance.
- [ ] Complete focused regressions, required full suite, exact-code hosted checks, release package/install/extraction and native identity verification. Avoid competing model runs during package refusal tests.
- [ ] Publish sanitized receipts, unchanged generated packages, trial failures and limits; update specs/handoff, commit and push. Remove only task recents/grants, undo UI test edits and preserve workbooks/models/baseline app.

## Design constraints

Reuse the existing importer, managed tables, formula plans, sandboxed behavior, named SDK actions, approval receipts and shared native sessions. Resolve new-record/formula dependencies explicitly rather than pretending inserted records inherit calculations. Keep inference bounded and make recovery feedback specific. Prefer shared deterministic calculation support when it eliminates repeated model mistakes; avoid fixture-name dispatch, hardcoded outputs or per-business app templates. External data comes only from explicit supplied inputs or an explicitly authorized existing connector. Missing services remain a visible dependency, not an invented successful refresh.

A finite corpus cannot establish universal Excel compatibility. Production signing, additional hardware, VoiceOver and independent customer/security qualification are separate from closing these three functional gaps. Any remaining concrete functional blocker stays open in this plan; do not label the work complete because a smaller subset passes.

## Active blockers

1. Cohort 17 is diagnostic: Stock exposed an unsupported nonzero unit-cost rule inferred by the reviewer, although neither the request nor source validation requires it. Candidate 134 challenges such numeric inferences before author repair and adds valid zero-cost acceptance; candidate 135 also clarifies Workspace action IDs after three repeated first-save mistakes. Two consecutive complete fresh six-app cohorts remain required; zero final cohorts are accepted.
2. Candidate 134 is installed with exact package identity. The unchanged native single-import/table-only/original-example route passed wide/compact inspection on candidate 133, and earlier diagnostic app interfaces pass their scoped checks. All six final generated interfaces plus model loading/cancellation, approval and conversational/native shared-state UI checks remain pending on the final candidate.
3. The complete candidate-133 local suite, native package/install/extraction, focused chat/confirmation checks and separately retained 10/10 regression pass. Exact-code hosted CI is running. Candidate 134 focused checks pass; final release checks and sanitized receipts/specs/handoff, commit/push and task-only recent/grant cleanup remain. This is ongoing qualification, not a completed product claim.

## Progress

The integrated chat change is committed and the checkout is clean. Previous frozen-code acceptance remains intact. No new live trial is claimed yet.

### Diagnostic pass 1

Created six three-sheet synthetic business applications, eighteen original/changed XLSX files, and visually inspected all eighteen base sheets. Artifact-tool authored the sources; LibreOffice independently recalculated caches. Added a fresh-generation harness using analysis/build, durable human approval, shared native sessions, conversational business operations, held-out edits, reopen, Undo and portable export. Independent post-action spreadsheet oracles are separate from model context.

Found that input ledgers could not grow within a saved Excel plan. Added stable appended coordinates, atomic recalculation and retained Undo coordinates; formula-bearing sheets still refuse ambiguous row growth. A focused check found logical IDs incorrectly used as immutable provenance inputs; corrected to exact retained versions. Sixteen formula groups then passed. Added malformed-extension validation. Full integration remains pending.

Diagnostic trial 01 was stopped after repeated missing-output failures, with receipts and runtime identity retained; it is not acceptance evidence. The conversion SDK omitted the asynchronous page-result contract, and the coverage failure did not identify omitted formula cells. Added explicit async paging guidance, shared-action error propagation guidance, and missing/extra output coordinates in the failure. Generated apps remain untouched. Trial 02 starts fresh on these changes.

Concurrent Home implementation resumed in the shared checkout. Preserve its changes; final combined-code qualification must wait for a stable checkpoint. Corrected a missing required operation token in its new workflow fixture so core checks could compile. Coordination permission requested separately; no cross-chat message sent yet.

### Diagnostic passes 2 and 3

Both fresh stock trials failed calculation reconstruction and were stopped with receipts retained. Neither counts as acceptance. Trial 02 repeatedly resubmitted interface code while repairing calculations; trial 03 separated calculations but still confused record actions with fixed-cell actions and misread ranges. No generated source was repaired. Added a calculation-only inference scope, retained verified draft reuse, explicit record-action guidance and access to bounded tool-result pages. A projected SDK guide previously directed the model to an unavailable tool.

The adversarial SDK pass found that subscription revisions could advance a write's expected revision during an action's validation. Named actions now capture their starting revision, refuse overlapping named actions and advance only from their own write receipts. Thirteen SDK groups pass, including subscription races, outside-write completion and Undo. This is a concurrency guard for shared actions, not an additional security authority.

**Correction to the first diagnostic report:** opening/exporting through LibreOffice had preserved pre-existing caches. It did not establish independent recalculation. A conditional-sum counterexample exposed this. The new shared recalculation script removes formula caches, forces recalculation, uses fresh output paths and refuses missing results. All eighteen business sources were recalculated through that path. Earlier diagnostics are retained with their original fixture hashes and remain failures. No cohort has been accepted.

Adding native bounded SUMIF/SUMIFS removes repeated model translation of common conditional totals. Original comparison remains mandatory. An independent conditional-sum corpus also records Calc/Excel differences around numeric-text criteria and wildcard/error matching, rather than rewriting the reference answers to match Sevra. Excel semantics are checked against Microsoft's function contract and Apache POI's documented criteria behavior; this does not claim universal formula equivalence.

Home is now committed at `13eb551`; final qualification must include that integrated checkpoint. No cross-chat message was sent. Live business generation, whole-application action checks, native visual review and release gates remain open.

### Diagnostic passes 4 and 5; shared controls and test fidelity

Trial 04 was stopped after repeated generated-source/test failures. The new calculation scope had accidentally retained the default 512-token reasoning limit; all Excel build scopes now receive the existing 2048-token allowance. Removed fixed-cell action examples from ordinary record-action guidance and retained compared behavior across interface repairs. Trial 05 generated a fresh stock app without manual repair and completed receipts, shipments, rejected overdraw/duplicates, explicit supplied price-file update, reopen, Undo, unchanged-source republication and portable verification. Generation took 644 seconds with five save attempts; total operation trial took 950 seconds. All seven post-action/Undo snapshots matched forced independent spreadsheet recalculation. This is diagnostic evidence, not a complete accepted cohort.

Added a reusable native ActionForm built from the existing native controls and registered action contract. It shares the chat handler, labels each input by action and field, preserves failed drafts, clears only successful drafts, exposes busy/error/completion state and refuses actions after their owner unmounts. Sixteen SDK groups pass. Native integration verifies the same form and chat handler; decimal strings retain their entered precision.

The disposable authoring checker previously omitted native formula definitions, making invented derived results disappear. It now carries only formula definitions and worksheet names into synthetic rows, never original customer values, row identities or authority. A focused test verifies new ledger rows update dependent stock/value totals in the disposable workbook while the source workbook remains unchanged. Full focused native authoring/Excel checks pass on this change.

Found a resource freshness issue in the check packaging: building the agent binary alone does not copy an updated worker SDK. The runner now refuses a stale SDK bundle. Trial 05's retained resource hash shows it used the earlier SDK; final qualification must rebuild the worker and include the revision-fenced SDK. The conditional-formula work budget now applies across a whole deterministic recalculation pass, including nested expressions; 17 formula groups pass, including hostile wildcard and shared-budget exhaustion checks.

Home is now committed at `b1557b6`. The next fresh cohort includes that checkpoint, the updated worker resource, shared forms, formula-aware synthetic checks and a 205-new-record stock challenge that must reject a duplicate beyond page one. No complete business cohort has yet been accepted.

### First attempted business cohort: stopped diagnostic

Cohort 01 generated stock in 283 seconds, but shipment failed because the saved action required a negative quantity contrary to the positive-input request. Chat repeated the unsuccessful action and correctly stopped without a shipment. The model review had accepted that defect and a broken extra Undo button. Stock therefore failed after 417 seconds. Invoices was interrupted during generation to stop using obsolete code. The failure, untouched package, messages and runtime identity remain in `.build/excel-business/cohort-01`; this is not an accepted cohort.

The generated stock code also checked only the first 200 ledger rows. Added SDK `data.all` to collect a bounded complete table with consistent revision and total across pages, refusing truncation or over 20,000 rows. The model-facing build guide is shorter and action oriented; detailed selection-editor examples remain available through `native_app_sdk`. The conversion save grammar now requires a fixtures object, and explains empty isolated tables and matching-row counts. The reviewer explicitly checks requested input conventions, full-ledger validation and extra Undo controls. Independent shipment/payment scenarios now require the successful action to accept the person's positive value, not silently invert its interface convention. These changes are generic; generated source was never repaired manually.

Seventeen SDK groups pass, including pagination, changed revision, truncated/oversized pages, zero rows, action races and form lifecycle. A saved-plan integrity review found mismatched native coordinate/identity arrays could reach unchecked indexing; early structural validation and a malformed-map regression now refuse that state. Seventeen formula groups pass. Final business cohorts, native UI and release qualification remain open.


### Second diagnostic cohort and native review

Cohort 02's fresh stock app passed original/held-out calculations and generated positive receipt/shipment handlers, but its first conversational operation failed before invocation: the local model omitted expectedVersion and supplied arguments instead of inputs. The rejection did not identify the missing/unexpected fields. Added precise envelope feedback and the app.run shape to shared tool guidance, retaining version checks and supplied-value rules. The untouched app and failed conversation remain retained. Invoices exposed similarly vague native dimension errors: size:'bold' led the model to repeatedly change unrelated heights. Native validation now identifies the exact property, component and node, with a specific size/weight correction. The continuing cohort uses its already-packaged older binary and remains diagnostic.

Native inspection of an isolated portable stock copy verified exact table access, enablement, keyboard traversal, positive shipment, overdraw refusal with draft retention, live stock/value updates and host Undo. The generated source was unchanged. The ordinary imported table's text was visibly high in its rows; it now uses an intrinsic-height field centered inside a native table cell, preserving immutable edit bindings. Existing table editing/sorting/stale-write/clipboard/Undo checks pass. Generated tab content also needed inset from its bezel; added shared native padding. Both visual corrections need inspection in the rebuilt candidate.

The action-input review found date validation accepted impossible calendar dates. The shared SDK now validates Gregorian month/day/leap-year bounds before invoking handlers, without reading a clock; 18 SDK groups pass. Formula-check templates copy only definitions, never original row values/identities/permissions. Model-authored fixture values remain separate untrusted data; this is not a guarantee that a model never repeats a value it saw in source evidence. Full cohorts and final qualification remain open.


### Scoped context, resource review and integrated regressions

Cohort 02 stopped after stock, invoicing and job costing failed; the last two exhausted the ordinary twelve-step budget. Job costing uncovered a real contract mismatch: inference advertised tool_result but the conversion tool guard refused it, preventing access to long saved SDK results. Conversion paging now permits only receipts from the current build request. Integration tests exercise a real long SDK receipt and refusal from a different build. Native UI tests initially failed because their cancellation fixture nested one registered named action inside another, which the revision fence deliberately forbids; the fixture now performs its intended write directly before waiting for cancellation. The full native integration check passes 18 groups, including shared views, revocation and preserved committed effects after cancellation.

The core suite passed 658 checks. The normalized formula tree now counts references across sibling SUMIF expansions before materializing them; the existing 10,000-reference boundary applies to the complete expression. Seventeen formula groups pass with exact-boundary and over-bound counterexamples. Focused Excel checks pass, including scoped SDK pagination. All ten retained batch-03 programs passed on the combined runtime with unchanged source: 302 native interaction steps, 79 saved-edit/reopen/Undo cases and ten verified portable copies. This is explicitly a regression replay, not fresh model generation.

Diagnostic 03 starts production, cash and bookings from fresh workbooks using the shared fixes. Complete fresh six-application cohorts remain required. One intermediate native release build was refused because source changed during compilation; it was not installed. The next build starts after the code/format pass.


### Native recheck and simpler authoring phases

The matching installed/package build FBFD776D-2A1C-3BA1-B44E-4D68A5EA0BA0 shows corrected ordinary-table vertical centering and 12-point tab content inset. Native editing changed the synthetic M1 quantity 5 to 6; Undo restored 5. No generated source changed. A Home integration defect was visible after the table-only import: it still appeared under Needs attention. Table-only and ready conversions now both appear under Continue working, while unfinished states retain their action. This final Home correction still needs rebuilt visual verification.

Production diagnostic 03 eventually saved an app after unnecessary formula translation and repeated interface repairs. Native formula support plus inert VBA previously selected the broad combined build schema. The build now enters interface authoring whenever no missing calculation remains. A genuinely fixed-cell original action can still be compared separately and retained as a verified draft; record-based VBA operations use ordinary shared actions. The compact guide includes exact component constants, numeric tab indices, child placement and async read placement. Calculation comparisons and permission checks remain unchanged. The harness now mirrors the production building/needs-attention transitions and checks immutable row versions on refused requests plus unchanged app source/version on ordinary business commands. Full acceptance still requires fresh cohorts on the final code.


Production diagnostic 03 passed all six conversational operations, direct duplicate refusal, held-out inputs, Undo, reopen, unchanged-source publication after growth and portable-copy verification. It used 980.76 seconds for analysis/generation and 1255.02 seconds overall. Every successful business command produced exactly one transaction receipt; refused commands produced none. Seven saved states independently forced through LibreOffice matched all 105 formula outputs. This remains diagnostic because production/check improvements were made afterward. Cash and bookings continue on that retained diagnostic runtime. The updated tool-description fixture is regenerated from the canonical contract and compared structurally; grammar checks are rerunning after the earlier byte-identity failure exposed that stale fixture.


### Reusable workspace and independent validation probes

Cash diagnostics exposed repeated table/form navigation errors before business
logic could be tested. Added a small SDK Workspace component that composes existing
native tabs, real bound table columns, independent filters and ActionForms. It adds
no capability or business-specific template. The preflight now identifies a control
on an inactive tab and gives the exact selection step; native tests still require
that navigation. New checks exercise native form save/reset and the same named
action through the workspace.

The final corpus now also has direct invalid-input probes for every stated numeric,
key, date-label and nonblank-text rule. Each probe group first runs a valid control
and Undo, preventing unrelated failures from masquerading as validation. Invalid
variants must fail without transaction receipts, changed values or changed immutable
versions. Probes are separate from the model's context and use only identities from
its successful calls; they never rewrite an app. This strengthens acceptance before
any complete cohort has been accepted.

Grammar checks exposed both the outdated canonical description fixture and its
derived upstream-mask fixture. After regenerating those, the normal-tool token
budget caught 41 excess tokens. The app.run description is now shorter while keeping
its exact envelope, user-input and confirmation rules; the budget has not been raised.
A whole-repository format invocation also reported pre-existing unrelated formatting;
all changed Swift files pass strict formatting. Final suite/package checks remain open.

### Candidate qualification after diagnostic 03

Diagnostic 03 finished with production passing (1,255 seconds overall), while cash (862 seconds) and bookings (987 seconds) exhausted the existing twelve-step repair budget. Retained all failed candidates and receipts. Bookings repeatedly supplied a single transaction object instead of an array; the SDK now rejects that shape before sending a write and identifies the exact array contract. Nineteen SDK behavior groups pass, including its valid-array counterexample. No generated program was edited.

The reusable Workspace passed native tab navigation, form save/reset and shared-action checks. Shortened its redundant reference paragraph rather than expanding tool-result or prompt limits. The complete focused authoring checks pass. The ordinary grammar prompt remains 8,439/8,448 tokens and authoring 9,795/10,240, with 84 tool grammars and 787 exact reference masks passing. Row-count feedback now reports the actual synthetic starting count, including padded worksheet positions, while preserving matching-value assertions.

The installed preview UUID 37468D77-934F-3BF6-9085-2DFECEC8DDAF matches the packaged executable and both worker SDK resources. Native visual inspection confirms completed table-only imports belong under Continue working without a false Needs attention warning. This is an intermediate visual checkpoint; later guide/transaction-feedback changes are newer than that release build. Cohort 03 starts all six applications fresh with the final direct validation probes. No accepted full cohort is claimed.

### Header-key adversarial counterexample

Cohort 03 saved a fresh stock app after two test repairs, but an independent SDK
probe of its unchanged source accepted the original worksheet header SKU as a
product. The probe used synthetic header rows and captured the unexpected write
request without persisting it. Stopped that cohort as diagnostic; it is not an
accepted run. Raw worksheet headers and blank positions must not count as business
entities. The shared build/review instructions now require that distinction and a
header-key counterexample, including entity update actions. Independent validation
now covers 68 invalid cases in 13 valid-control groups across the six apps, adding
headers/blanks and the stock unit-cost lookup. Source XLSX files and expected
business outcomes are unchanged. Cohort 04 starts fresh after this generic fix;
no generated source was repaired. The full suite is also running, with affected
agent checks compiled after this change.

### Negative review assertions and diagnostics

Cohort 04 was stopped after the reviewer exhausted its budget on a candidate that
still had the header-key defect. Review/check admission counted only expect_ steps,
even though run_action with an expected error is itself a checked assertion. The
shared assertion predicate now recognizes both. A real action's negative assertion
passes; a successful action fails that expectation; an unknown action is refused
as invalid test setup. The full focused authoring suite passes this consistency fix.
Inconclusive reviews now retain bounded verdict/probe feedback in the run metrics
and failure receipt, preserving the distinction between invalid setup and a
reproduced app defect. Cohort 05 starts fresh with all 68 independent invalid cases.

The first full-suite run passed 658 core checks and the preceding native/SDK,
automation, extraction, persistence and table-update checks, then failed an obsolete
formula diagnostic expectation. Quoted criteria are now parsed for SUMIF/SUMIFS,
so unsupported text concatenation is correctly identified as joined text instead
of the earlier generic text-value message. The CLI assertion now checks that exact
reason and additionally verifies the original saved value remains ab. Its focused
rerun and the remaining complete suite are pending; the failed log is retained.

Native Workspace inspection on an isolated cohort-03 copy passed filter state,
keyboard traversal, save/reset and host Undo. A compact 952 by 682 logical-point
window retained readable stacked forms and scrolling. The test write was undone
and workbook integrity verified. That source remains diagnostic for its separate
business-key defect, not accepted application evidence.

### Host boundaries and rejection fidelity

Cohort 05 was stopped as diagnostic after repeated false review demands for an app-owned Undo control, followed by broken duplicate Undo implementations. The host already supplies Undo last change. Missing generated Undo and controls on unselected tabs now produce invalid-setup feedback, not a reproduced app defect; actual generated Undo controls still execute and are checked. The SDK rejects Undo without a receipt before any write. Focused model-stub checks cover correction of the false review and preserve refusal of a genuinely missing business control.

The same trial revealed a counterexample with a numeric JSON value for a decimal-string input being misreported as an app defect. Successful-action probes now check declared JSON input shapes before execution; explicit error assertions can still exercise runtime refusal. Matching-row failure feedback prioritizes observed rows nearest the expected values, helping repair storage-type mistakes without changing the assertion.

Adversarial review found that an expected error could conceal an earlier successful write. Negative action assertions now also require zero committed transactions, including writes subsequently undone. A counterexample commits then throws and must fail. Required text and record inputs now reject empty or whitespace-only values; optional text preserves blanks and exact literal whitespace. Independent acceptance adds blank references, bringing the corpus to 86 invalid cases across 13 valid-control groups. All generated source remains untouched. Twenty-one SDK groups pass. Two complete fresh accepted cohorts are still pending.

The formula CLI rerun passed all 35 checks including preserved saved values. The ongoing full suite is intermediate evidence because the above checker/SDK changes occurred after its start; final complete-code verification remains required.

### Saved-plan integrity and integrated regression

Seventeen formula groups pass after bounding decoded worksheet maps to the importer contract: at most 100 sheets, 500 columns, 20,000 mapped rows overall, valid cell coordinates and bounded nonnegative omitted-formula counts. Shortened maps, negative widths and an overflowing omitted count are refused. This closes a saved-state reporting overflow; valid large saved-value imports remain covered by the existing sample/count tests.

The full intermediate suite passed, including 658 core checks, grammar/reference masks and knowledge validation. Packaged journeys were explicitly skipped because the packaged build is older than the source. The final-code full suite and package checks still remain. All ten retained earlier programs also passed unchanged again on SDK 47: 302 native interaction steps, 79 edit/reopen/Undo cases and ten portable copies. These are regression replay, not fresh generations.

Cohort 06 is continuing all six business workflows as a complete diagnostic after the subsequent saved-plan integrity change. The local reviewer reproduced both the header-key defect and the incorrect negative-only shipment convention, and the builder is repairing them without source edits. Its frozen runtime remains retained; it cannot count as one of the two final-code cohorts.

### Repair diagnostics and independent review data

Cohort 06 stock failed after 592 seconds. The reviewer correctly reproduced the header-key and negative-only shipment bugs, and the model repaired both, but repeated a numeric-versus-string stored-value mismatch until the unchanged-call guard stopped the run. No generated source was repaired. Failure feedback now names the exact mismatched JSON types and stored column, while preserving strict assertions; successful-action probes also reject unknown assertion columns as invalid setup. The focused numeric/string counterexample and its valid-string control pass. Workflow analysis now explicitly separates entered values from signed ledger storage and preserves the person's stated conventions.

Invoicing exposed a deeper review-coverage gap: author-selected customer fixtures omitted the original header, so the reviewer could identify the raw-row lookup bug but could not reproduce it with those fixtures. Review may now replace specific synthetic fixture tables for its bounded independent counterexample. The same isolated checker, row/count/column limits and original-coordinate bounds apply; no original data or authority is copied. Reproduced defects retain the exact replacement fixtures in repair feedback. Added a wrong lookup versus corrected lookup counterexample and an unchanged-real-workbook assertion. Qualified ActionForm input labels are now reported as test setup guidance rather than falsely declaring that generated native fields are missing.


### Reference recovery and diagnostic cohort 06

The fresh invoicing diagnostic passed its five business requests, all 21 independent invalid-input variants, held-out inputs, Undo, reopen, unchanged-source rebuild and portable copy. Twelve observed states independently recalculated through LibreOffice matched all 108 formula outputs. This is diagnostic evidence, not an accepted final cohort. Stock failed after repeated numeric-versus-string storage mismatches; job costing spent all twelve steps paging the SDK reference and never submitted an app. Production repeatedly left an action description object unclosed before its async handler. No generated app source was repaired.

Explicit tool-result navigation now uses up to 8,000 encoded text bytes within the unchanged 16,000-byte response bound, rather than 1,000 Unicode scalars. Initial receipt projection remains unchanged so existing receipt integrity can still be reproduced. Five focused receipt groups pass, including large Unicode/control-character reconstruction, dense reference reads, cancellation, conversation isolation, portable restoration and tamper refusal. The first paging build exposed a Swift throwing-expression syntax error; the first focused assertion underestimated the 24,000-character reference length. Both were corrected and the failed logs retained.

After a malformed workspace call is corrected and reaches its business handler, the obsolete envelope error is suppressed in the final reply while the actual business refusal and both audit receipts remain. A different app target does not settle the earlier failure. The agent checks pass this behavior. Syntax feedback now explains the three action-registration arguments when QuickJS rejects an unnamed async arrow inside the description object; its focused native-worker test is running.

A final cohort qualifier now requires two distinct complete runs, unchanged code during each run, identical code/fixtures/build products/engine between them, every business refusal and saved-state oracle, all original formula positions, and generated-source equality with the model publication receipt. Runtime evidence records compiled products and guidance identity as well as sources. Final cohorts, native interfaces and exact-code release verification remain open.

### Review grounding and interface repair retention

Diagnostic cohort 07 production passes its complete business journey, all five independent invalid-input variants, held-out values, Undo, reopen, unchanged-source rebuild and portable copy. Generation took 1,103.70 seconds and the complete application check took 1,387.90 seconds. Independent post-action spreadsheet recalculation remains pending. This cohort is diagnostic because review and repair-context fixes were made after its frozen build started; it cannot qualify as final-code acceptance.

Observed reviewer mistakes included requesting an unrequested Batches argument for an existing-record completion action and expecting insufficient stock from ample-stock synthetic inputs. Review guidance now grounds both required arguments and refusal preconditions in the exact user request and original formulas. A bounded interface repair reference retains one earlier candidate that passed isolated interaction tests when a later repair regresses; it never bypasses comparison, tests or review, and cannot cross a build version or successful-save boundary. Focused authoring/conversion checks pass, including anchor removal, size limits and boundary counterexamples. Missing-assertion feedback now distinguishes a full interaction list with no assertions from an excessive test count. Generated app source remains untouched.

The isolated invoicing UI copy passed blank-reference feedback, keyboard traversal, successful invoice creation, form reset, dependent receivable/credit recalculation and host Undo. Undo restored C1 balance 560 and available credit 4,440, removed UI-INVOICE-59 and returned the ledger to 15 rows. Wide native layout shows vertically centered table text and inset tab content; forms scroll with clear labels. The diagnostic version's access was disabled afterward. This is build 59 UI evidence, not final-generation qualification.

The intermediate full suite passed 658 core checks and the preceding integration groups, then found a CLI receipt test still assuming 1,000-scalar explicit pages. That assertion now verifies exact Unicode segments, continuous next offsets, total length and unchanged encoded-byte bounds, including a final partial page. The focused packaged-CLI receipt round trip passes. The failed full-suite log is retained; a final complete suite is still required.

### Intake completion and checked publication

Diagnostic cohort 07 cash/loans passes all journeys, ten invalid-input cases, held-out values, Undo, reopen, unchanged-source rebuild and portable copy. Generation took 635.51 seconds; total application checks took 846.22 seconds. Post-action spreadsheet oracles remain pending. Job costing stopped prematurely after four reads with a prose promise to build and no app submission (213.42 seconds). Automatic Excel build scopes now omit the finish tool: only a successful checked save completes conversion, while cancellation and existing bounded failure paths remain. Scope/schema tests and all focused authoring/conversion checks pass. The original scope allowed this misleading early completion; no generated source was repaired.

Adding a comparison example in the native UI captured its reference but never ran the existing intake job. The UI now completes reference intake before adding the comparison. The realistic harness also follows that ordinary capture/index path for originals, examples and explicitly supplied update files. Focused checks cover an indexed accepted example and a structurally incompatible example that is rejected without changing the conversion while its source remains available. Initial test runs exposed a legitimate partial extraction state and an incorrect test fixture suffix; corrected those expectations/paths and retained the failed logs.

Installed build 63 was matched to the packaged executable UUID 324769FC-2B77-3A4B-BA0B-F156A35B9805, extractor and both workers/SDK resources. Native UI inspection added invoices-2.xlsx on the diagnostic copy, confirmed its saved-cell indexing coverage, and verified it did not appear in pending extraction. The old cohort-06 example remains separately pending because that older harness skipped indexing. Removing only the new comparison restored the prior app/current comparison state and retained the indexed original. The example section remained readable with clear rebuild status. Singular comparison/example/result wording was corrected after seeing the pluralization error; that small copy change awaits the final package.

Cash review also exposed an invalid negative probe: a string was supplied to a numeric action input, so SDK rejection prevented the business rule from running. A mismatched business-error expectation is now classified as invalid setup in that case, with exact expected/observed error feedback; an intentional matching SDK type-rejection test still passes. A correctly typed business-rule failure remains an assertion failure. Focused authoring checks pass all of these boundaries. The first new test expected the internal setup code rather than the checker's public app_check wrapper; corrected it and retained that failed log.

### Decimal boundary, evidence identity and cohort 07 diagnostics

The shared decimal action boundary now rejects finite-looking decimal strings whose
JavaScript numeric conversion overflows to infinity. It preserves the original
valid decimal string, including integers beyond binary floating-point precision.
SDK checks include positive/negative 400-digit values and unchanged precise valid
inputs; the actual worker authoring checks exercise the same refusal. SDK 22 groups
and authoring checks 69 pass. This is input validation, not a claim that arbitrary
model-authored arithmetic is exact.

Qualification now includes bundled source resources and requires identical resource
hashes and one model configuration across both complete cohorts. No accepted cohort
predates this stricter identity inventory.

Cohort 07 remains diagnostic because production code changed during its execution.
Production and cash pass their complete harness journeys. Independent LibreOffice
recalculation agrees with all 255 formula outputs over their 19 saved states.
Jobs stopped with a prose-only build promise; removing finish from Excel build scopes
is covered by authoring checks 64/66 and grammar checks 67, awaiting fresh live proof.
Bookings built in 262 seconds but chat invented missing values after first trying
TODO placeholders. The original accepted app also omitted the weekday restriction.
The shared chat guidance now requires clarification before invocation, explicitly
forbids placeholders and unrelated prior-transaction defaults, and preserves the
user's values after refusals. Builder/reviewer guidance now checks every explicit
allowed-value set on both create and update, plus self-exclusion in conflict checks.
Those changes require fresh whole-flow model evidence; prompt rules alone are not a
proof that arbitrary generated applications are correct. Cohort 07 continues through
all six cases to retain the complete diagnostic result. Generated source was not edited.

Intermediate native UI checks observed an accepted invoice write and successful Undo,
then disabled the app grant. Adding a comparison example through the actual file picker
now completes its reference indexing; removing that comparison example restores the
prior app comparison while retaining the indexed source. The installed package was
verified by executable UUIDs and SDK hashes. Later source changes remain uninstalled.

### Repair diagnostics for asynchronous reads

Cohort 07 stock exposed repeated `await data.all(...).filter(...)` errors after a
header-validation repair. The checker now adds a targeted async-read explanation
when that source pattern accompanies an observed not-a-function failure, including
failures displayed by ActionForm. It does not rewrite source, change assertions or
convert a failure into a pass. A nearby valid `(await data.all(...)).filter(...)`
counterexample is tested through the worker. Action-registration errors now explain
the three-argument contract, with rejected misplaced handlers and valid registration
covered by the SDK. The common action guide recommends existing typed choices for
explicit allowed sets, preserving native pickers and shared runtime validation.

SDK 23 groups pass on candidate 71; strict Swift lint passed all 42 changed Swift
files before the added async diagnostic. Full suite 71 is in progress; focused
worker/authoring checks 72 cover the later diagnostic. Neither is a final release
qualification until the remaining live and installed checks pass.

### Scope of the new diagnostics

Focused authoring check 72 caught a guide-size regression: adding the business-rule
paragraph to the general shared guide pushed a simple source read beyond the existing
16 KB receipt projection budget. Kept that bounded-read guard and moved the paragraph
to the Excel build guide, where it is relevant and present in the generation context.
Focused check 73 verifies that correction without widening response limits.

The SDK review also found that string choices could be declared on number/boolean
inputs even though such values could never match the string choices. Registration now
rejects that incompatible contract. A valid text choice uses the native picker and the
same named-action validation; both accepted form submission and rejected direct values
are tested. SDK 24 groups pass. This is a shared contract fix, not generated-app repair.

### Complete diagnostic cohort 07 and executed readiness probes

Cohort 07 completed all six fresh applications. Production and cash pass. Jobs stopped
before publication with a prose-only promise; bookings invented missing chat inputs;
stock exhausted its bounded repair steps; invoicing built on its first submission but
accepted the worksheet customer header as a real customer in an independent refusal
probe. The invoicing generation was 209.3 seconds and its full failed journey was
442.9 seconds. No source was repaired. Runtime sourceUnchangedAtEnd is false, so this
whole cohort remains diagnostic. Independent recalculation passes all
369 outputs over 30 retained states; that arithmetic evidence does
not turn the failed business journeys into passes.

A ready model verdict is now insufficient for an Excel app with named actions.
The preflight inventories observed named actions, and the independent reviewer must
submit executable probes covering them. The same isolated worker executes those
probes against synthetic fixtures before publication. Groups of eight actions fit
bounded 16-step batches, with a bounded review budget and no original-data access.
Repeated coverage cannot substitute for an untested action. Failed readiness probes
return observed evidence for test correction or an explicit reproduced defect; they
never silently publish. The qualifier now requires those executed checks and complete
action coverage in each saved model receipt.

Authoring checks 75 pass: missing readiness refuses, a false ready verdict cannot hide
the header-key defect, the corrected synthetic lookup passes, and nine actions require
two distinct passing probe batches. The production model must still demonstrate this
path in fresh cohorts. Checks 76 include the final diagnostic status wording.

Full suite 71 passed core, storage, CLI, formula and document checks before finding an
outdated activity-view assertion that expected the old 1,000-character explicit receipt
page size. The updated check follows exact saved offsets, preserves the response bound
and reconstructs all 30,000 characters; it does not relax the paging contract. Focused
preview verification 76 and the remaining full suite are required. Package 74 was built
before the readiness gate and is not the final source package. The native preview was
closed through its normal Quit action; baseline app and user workbooks were preserved.

### Candidate 76 verification and native intake

Final focused authoring and tool-grammar checks 76 pass. The activity receipt paging
regression passes in focused preview checks 76. The packaged candidate 76 was installed
and matched to its build using Mach-O UUIDs for the main executable, extraction helper
and both isolated workers, plus exact SDK hashes. The baseline app remains preserved.

The actual native Add files picker imported the synthetic three-sheet receivables
workbook into a fresh empty workbook. The single Excel intake view showed the workflow
prompt, Understand my workbook, Just use the tables, the three source sheets and nine
formulas, plus the bounded original-result comparison explanation. File capture and
indexing completed. Wide-window spacing, input alignment and readable hierarchy were
visually checked. No competing model request was started while cohort 08 owned inference.
This verifies intake, not the still-pending complete final model-to-UI journey.

### Assertion contract and large-table adversarial pass

Diagnostic cohort 08 repeatedly confused exact matching-row counts with total table
counts, including in independent review. Its booking app eventually published after
ten submissions, with automatic validation repairs and executed independent action
probes. Generated source was not edited. Later shared checker changes make this cohort
diagnostic even if its final business operations pass.

The canonical test contract now offers expect_row for exactly one row matching its
business key and saved values, without a separate count. Existing cardinality assertions
retain exact counting. Business refusal probes can assert reject:true with complete
correctly typed inputs, without inventing an exact error message. Successful actions,
wrong JSON types and partial writes cannot satisfy that assertion. Malformed assertion
values and incompatible refusal fields are rejected instead of silently ignored.

The same pass found that saved-value assertions only read the first 200 rows and
refused larger tables. They now read bounded complete pages, checking revision, total
and progress. Synthetic checks include a matching row on page two and a duplicate
past row 200. This does not change customer data or widen app permissions.

The native table-only path was exercised through the installed UI: Return entered a
customer credit cell, typing changed 5000 to 5100, the related receivables calculation
changed to 4700, and the durable Undo control restored the input to 5000 and calculated
credit to 4600 after navigation. Text remained centered in selected/unselected rows.
All UI edits were undone. Ten retained workflows replayed on candidate 76 pass with
unchanged runtime evidence; this is regression evidence, not fresh generation.

### Focused assertion checks pass

Authoring checks 79 pass, including unique-row absence/duplicates, malformed input
rejection, zero-write business refusals and page-two matching/duplicate cases. Native
grammar checks 80 pass 86 tool grammars and 817 exact reference masks; ordinary tool
prompt remains 8439/8448 tokens, authoring 9941/10240. The initial candidate 77 used
an unsupported minProperties schema keyword; removed it while retaining host-side
nonempty-value enforcement, regenerated the reference masks and rebuilt. Candidate 81
aligns the header-refusal hint with reject:true and the missing-assertion hint with
expect_row. The 79 runtime tests remain relevant to those wording-only adjustments.

Booking diagnostic 08 generated in 1124.5 seconds and completed in 1363.6 seconds.
Its missing-input answer asks for reference, start hour, duration and customer before
invocation. Seventeen independently varied invalid inputs are refused; held-out
recalculation, unchanged-source rebuild and portable persistence pass. This is useful
failure-recovery evidence, not an accepted final cohort or a product latency claim.

### Booking oracle and temporary visual-access interruption

The independent spreadsheet oracle recalculated all 120 formula outputs across ten
booking journey/Undo/control states, with no mismatches. This uses retained input
snapshots, clears cached answers, and forces recalculation before comparison.

Native UI access stopped returning screenshots or responding to menu input while
preparing the booking layout review. The preview remains running. Requested that the
owner wake/unlock the Mac; no VoiceOver or system-setting changes were attempted.
The previous invoice UI task copy was preserved as UI-workspace-before81; the shared
UI-workspace path now contains a fresh portable copy of diagnostic 08 bookings,
ready for its visual review. The import workbook remains open, with its test edit
undone. No booking UI grant has been enabled.

### Consecutive-cohort evidence gate

Adversarial review found that the qualifier checked chronological order but could
still accept two passing cohorts with an intervening failed business trial. It now
requires one retained trial directory and inspects sibling business runtime receipts,
refusing intervening or overlapping trials. Earlier/later trials and the separately
labeled ten-app regression remain allowed. Focused sequence checks pass and run in
the local full suite and hosted CI. This strengthens qualification; no generated app
or business expectation was changed.

Native package 81 built successfully. Its paths-only checks pass exact resource
identity, missing/altered-resource refusal, signature validation and denial of reads
from the build tree. Packaged native extraction passes PDF/DOCX/text/CSV/XLSX and
original preservation checks. GPU/missing-model refusal checks remain deferred until
the live inference lease is idle; package 81 has not replaced the installed 76 yet.

### Independent oracle exposed frozen job-costing ranges

Diagnostic cohort 08 job costing passed saved-input journeys but failed the independent
recalculation oracle: its generated behavior summed only the original twelve time entries.
A new 3.5-hour entry saved successfully while hours, labor and margin stayed stale. The
source also mapped original job keys to output coordinates. These are real defects;
the cohort is not accepted, and the earlier harness pass is not an end-to-end pass.
No generated package was manually repaired. Stock later exhausted the repeated-failure
budget on an unbalanced nested interface; its failed attempts are retained.

Shared candidate 84 adds bounded native SUMPRODUCT arithmetic/comparison arrays, so the
original job workbook's formulas and full ranges remain authoritative without a model
translation. Thirty-five independent spreadsheet cases cover shapes, text, blank values,
errors and scalar/array arithmetic; Calc's three logical-array coercion differences
remain visible in raw evidence, with Excel's explicit-coercion expectations kept separate.
Microsoft's SUMPRODUCT documentation identifies nonnumeric array entries as zero and
Office's dimension mismatch as VALUE, not NUM. This remains a bounded formula subset.
All nineteen focused formula groups pass, including all three original job files, new
time entries, a rate update, dependent totals, Undo, reopen and reconstructed copy.

The calculation authoring guide now explicitly preserves original range bounds and
formula-row output coordinates, and requires dependent-total assertions after appends.
Syntax-failure feedback offers the existing Workspace component for deeply nested table
layouts, without editing generated source or weakening tests. Candidate 85 additionally
bounds numeric-text coercion work and checks that resource limit. Final fresh cohorts,
complete native UI review, full suite and combined qualification remain pending.

### Runnable repair anchors and action availability

Stock diagnostic 08 regressed from a runnable app with a test failure to repeated syntax
errors. Host-only completed-test progress is now retained in failed-save receipts.
Context maintenance keeps a bounded earlier candidate that completed more checks,
without accepting it or skipping any gate. Full preflight wins over partial progress;
anchors cannot cross build versions or successful publication. Untrusted exception
prose cannot invent progress. Focused authoring checks 87 pass these boundaries and
the existing adversarial authoring suite. Grammar 87 also passes.

Invoice diagnostic 08 generated and completed its conversational actions, but direct
adversarial probing found that the Customer header was accepted as a customer code.
Its independent reviewer had tested unknown keys and duplicates, but omitted headers.
The review policy now puts exact-header probes first for every action requiring an
existing entity. The external refusal suite remains unchanged and still gates acceptance.

Production diagnostic 08 exposed an async enabled predicate. SDK review found that a
Promise resolving false was treated as available. Candidate 88 requires action enabled
to produce a synchronous boolean, consistently across invocation, native ActionForm
and action discovery. Input-dependent asynchronous validation belongs in the handler.
All 25 SDK groups pass, including rejected async/nonboolean predicates and a valid
reactive boolean control. Formula checks 86 pass all 19 groups, including the additional
numeric-text work bound. Combined package and fresh-model verification remain pending.

### Candidate 89 shared checks and artifact integrity

Candidate 88 exposed a small-app receipt-size regression when action availability
guidance was added to the general SDK guide. Moved that detailed instruction to the
Excel build guide; the original receipt bound remains unchanged. Authoring checks 89
pass, including repair-anchor boundaries, the new assertion contract, syntax recovery
feedback and the earlier hostile-code/Excel conversion checks. Native package 89
builds successfully; installed UI still runs candidate 76 while screenshots remain
unavailable and the owner wake/unlock request is pending.

The acceptance qualifier now compares the entire exported package's byte digest with
the harness result, publication check and independent-review digest. This covers
translated calculations and bindings, not only the UI source string. Synthetic
artifact-tamper and stale-review cases refuse; unchanged diagnostic exports pass the
identity check. This does not turn their failed business checks into acceptance.

### Combined regression and second static pass

Ten retained apps replay successfully on candidate 89 with unchanged source identity:
187 independent interface steps plus 115 boundary steps, 79 saved edit/reopen/Undo
cases, and ten verified portable copies. All freshModelTrial flags are false. These
302 headless interaction steps are regression coverage, not fresh-model acceptance
or native visual inspection. Package 89 paths-only and extraction checks pass.

The second static pass reviewed input-row coordinate retention and tombstones, original
formula-range limits, atomic recalculation/Undo, comparison authority, scoped receipt
paging, failed-action reporting, exact package identity and native table/tab layout
changes. New SUMPRODUCT coercion is bounded before parsing long numeric text; partial
check progress is host-created and cannot be supplied by generated exceptions. Source
format checks and Python compilation pass. The six-app model cohort remains diagnostic
and unsuccessful; no final readiness or universal equivalence claim is made.

### Frozen diagnostic stopped after repeated known failures

Stopped candidate-76 cohort 08 during Production after repeated exact-error-string
assertion failures already addressed by reject:true in the newer checker. The identified
checker received SIGINT; supervisor wrote its final runtime receipt, and its checker,
supervisor and model-engine processes exited. The four completed case results, partial
Production receipts and explicit diagnostic-stop record remain intact. Cash was not
started in this diagnostic. It cannot count toward acceptance.

The final independent oracle comparison retains the job-costing mismatches; booking
and the completed invoice journey snapshots match their independent recalculations.
Invoice still fails business validation, and stock never published. Generated source
was never edited. Full scripts/check.sh is now running on candidate 89 after db index
rebuild, with the inference lease idle for package refusal checks.


### Full code suite and package-gate closure

Full scripts/check.sh 89 passed all code checks and knowledge validation. Its timestamp
heuristic skipped packaged journeys because the source checker rewrote byte-identical
SDK/license assets. This was a verification tooling defect, not changed runtime bytes.
Candidate 90 makes the SDK/example builder write only changed bytes, and the source
check now asserts unchanged modification times as well as exact bytes. Focused source
and cohort-qualification checks pass; builder/checker identities join cohort receipts.

Verified current native-product executable UUIDs against the packaged app/CLI/extractor,
no newer Swift inputs, and exact source SDK/license bytes in both worker services. The
complete native package check then passed 1,888 Metal kernels, build-tree denial, missing
model guidance with durable failed-run history, all ten missing resources, altered
resource refusal and signature validation. Isolated installation/update/uninstall,
standalone CLI, worker sandbox entitlements, preserved workbook and unrelated CLI/app
protection pass. The old baseline bundle was not changed. Previous extraction 89 remains
valid because runtime and extraction bytes did not change.

Cohort 09 now starts all six fresh applications on these unchanged runtime and acceptance
files. No prior package or conversation is reused, and generated source remains untouched.
The final native installation and visual review are pending UI access, not claimed complete.


### Successful-action review gap found by cohort 09

Stock generated in 243.2 seconds with two save attempts, then failed its second
business journey after 342.9 seconds: a positive entered shipment was stored positive,
increasing stock. The builder's tests asserted that same wrong sign. Independent review
had exercised seven refusals, all passing, but no successful effect. This is a real
publication-gate gap. The conversational call preserved the user's positive quantity;
its earlier malformed envelope was repaired before invocation and did not cause the sign.

Candidate 92 withholds builder tests from independent Excel review. Every action now
requires a successful call immediately followed by an exact value assertion; refusals,
row counts and control-presence assertions cannot qualify that successful-effect coverage.
Review uses up to four remaining actions per 16-step batch, retaining a bounded 24-round
ceiling. Expectations must come from the request and original evidence, including stored
sign and dependent totals. Header/business refusal guidance remains. A focused wrong-sign
case fails despite the builder's wrong passing assertion; the correctly signed control
passes. Refusal-only readiness is rejected, independent inputs hide builder assertions,
and nine distinct actions require three successful batches without duplicated coverage.
Authoring 92 passes all existing checks plus these cases. Qualification independently
requires matching successful-call/value-assertion coverage in the retained review receipts.

Invoices failed after 267.8 seconds on repeated nested layout syntax errors. The detailed
SDK reference now starts with the existing Workspace composition for ordinary multi-sheet
record apps, and the compact guide no longer primes a nested Tabs example before it.
Jobs exposed uppercase/spaced action IDs and tests confusing native tab labels with Text
nodes. SDK registration now reports exact ID syntax separately from duplicates/limits,
and rejects nonstring IDs before coercion; all 25 SDK groups pass. Candidate 93 adds
specific tab-navigation/assertion feedback without accepting a tab title as Text content.
No generated source was edited. Stopped cohort 09 during Jobs, retained all receipts,
and left Production, Bookings and Cash unstarted in that diagnostic. Its source identity
changed while shared fixes were made, so it cannot qualify acceptance. The new package
and focused authoring checks are building before a fresh cohort.


Candidate 93 authoring and grammar checks pass, including wrong-sign refusal, corrected
success, no rejection-only readiness, three distinct review batches, and actionable tab
feedback. Native package 93 builds and passes the complete GPU/resource/missing-model/
signature checks. SDK 92 passes all 25 groups. Cohort 10 starts fresh on this candidate;
there are still zero accepted cohorts. The complete code suite 89 is earlier evidence;
final full-suite closure remains required after the current production changes.


### Cohort 10 price-file ambiguity and unchanged expected data

Fresh Stock generated in 299.6 seconds after one field-label test repair. It passed
independent successful-action review, held-out inputs and the first five real journeys,
including negative shipment storage, overdraw/duplicate refusal and explicit cost update.
The sixth request said "Update the unit cost using the supplied price file" immediately
after editing P1. The model read the file correctly, saw only P2 at 7.25, carried forward
P1 as the target and declined to change it. This failed the harness's intended P2 update
after 567.0 seconds; it did not fabricate a successful change.

Clarified that synthetic request to "Update unit costs for the products listed in the
supplied price file." This corrects test intent, not generated source or product logic.
The supplied CSV, target-row assertion, expected price, preserved P1 requirement and all
remaining business/invalid/oracle checks remain unchanged. Updated both canonical corpus
builder and cases JSON; original workbook bytes are untouched. Retain cohort 10's exact
request, refusal and failed result. It continues diagnostically through the other five
applications; the acceptance counter remains zero and the next cohorts start fresh.

The ten retained regression apps pass again on runtime 93: 302 independent/boundary
interaction steps, 79 saved-edit/reopen/Undo cases and ten portable copies. Every
freshModelTrial flag is false. This is not fresh generation or visual verification.


### Cohort 10 header defect; structured independent lookup probes

Invoices generated in 159.3 seconds and completed all five conversational journeys,
then failed direct validation after 366.9 seconds: createInvoice accepted the original
Customer header as a customer. All three handlers looked up raw rows without excluding
that header. The independent review checked three successful saved effects and three
refusals but omitted the header. Repeating prose instructions had not closed this gap.

Candidate 95 makes ready reviews classify every supplied input of their successful
action probes as an entered/new value or an existing key with its table, column and
original header row. The host verifies those mappings against original input evidence
and synthetic fixtures, derives header substitutions, and executes each in isolation.
It reproduces only the setup BEFORE the valid call, so a duplicate-reference guard
cannot mask the invalid key. Failed header probes return directly to author repair;
they cannot be erased by a subsequent reviewer verdict. Receipts retain roles, original
cell/header, exact probes and checked package digests. The external cohort qualifier
requires complete classifications and all matching executed probes.

Focused authoring 95 and 96 pass, including a defective lookup that the reviewer tested
only positively, corrected lookup success, missing/forged mappings, fractional row
rejection, missing original evidence/headers, unchanged inputs and precise setup replay.
The qualifier rejects missing, duplicate, stale-package and reordered probe receipts.
Candidate 97 adds adversarial edge cases: a header must occur only at its original
fixture position, and number/boolean keys rely on the successful SDK type check because
text headers cannot enter those handlers. String keys receive the business refusal probe.
Classification still relies on bounded model interpretation; this is not a proof of all
business rules or universal Excel equivalence.

Jobs and Production pass cohort 10's business/held-out/refusal/reopen/Undo/portable harness
checks, with generation at 228.2 and 168.6 seconds respectively. Their full saved-state
spreadsheet oracles remain pending the completed diagnostic. Bookings exposed repeated
fixture-preinsertion, literal placeholder labels and numeric change-event values.
The compact authoring guide now distinguishes action IDs from click titles, names real
form labels, specifies string change values and starting-only fixtures. Generated source
remains untouched. Final fresh acceptance resets for these production/acceptance changes.


Candidate 97 focused authoring passes, including numeric/boolean key compatibility and
ambiguous-header fixture refusal. Bookings then exposed a separate reviewer protocol
failure on runtime 93: a contradictory verdict forced the author to resubmit the entire
app. Candidate 98 now gives bounded feedback directly to that reviewer on the unchanged
candidate; inconsistent verdicts never publish. Focused checks pass both recovery on a
corrected second verdict and refusal after three contradictory verdicts. No retry budget
was enlarged. The native package builds. A new real grammar check initially used the
wrong XML parameter order (issues before inputRoles); corrected the fixture to the
existing sorted native contract. The full grammar rerun is pending; this was a test
encoding failure, not evidence of successful live generation.


Stopped cohort 10 during a further Bookings repair after its original-header defect and
invalid reviewer counterexamples repeated on superseded runtime 93. The exact checker
received SIGINT, the supervisor retained runtime/failure/stop receipts and exited, and
Cash was left unstarted. No app source was modified. This is not a completed or accepted
cohort. Candidate 98 fresh cohorts will run Cash, Invoices, Stock, Jobs, Production and
Bookings; the order change does not reuse any app, workbook, conversation or test answer.


Candidate 99b closes the grammar finding. In addition to sorted XML parameters, nested
fixed-schema JSON fields follow the native decoder's schema order. Sorted existing-key
examples now match it. A supported anyOf with mutually exclusive value/existingKey
branches requires all lookup fields; incomplete mappings cannot be emitted. An initial
oneOf attempt was rejected by the existing schema adapter and replaced, without widening
that adapter. The focused real tokenizer/grammar check passes with reasoning on/off,
valid nested roles, incomplete lookup refusal, fractional row refusal, unknown-kind
refusal and no save tool. Host semantics and bounds remain separately checked.

The stopped cohort 10's 31 retained operation/Undo/control states were recalculated
independently from inputs with source formula caches removed: all 351 formula results
match. This includes the formerly failing growing Jobs/SUMPRODUCT calculations. It does
not erase Stock's ambiguous instruction, Invoices' business validation failure or the
incomplete Bookings/Cash trials. No repeated unchanged oracle runs are required.


### Original-header evidence boundary found during the final static pass

The new key gate initially read only calculationEvidence.inputCells, a deliberately
bounded 100-cell/12-KiB model excerpt. A larger first worksheet can consume that excerpt,
leaving valid later-sheet headers unavailable and causing false conversion refusal.
Candidate 100 reads exact declared cells from the verified retained original instead,
without expanding model context. It preserves nonempty-sheet alias mapping and sparse
Excel row coordinates, excludes formula outputs, and refuses headers above 4 KiB rather
than truncating them. A focused fixture has 150 first-sheet inputs plus a sparse later
sheet whose header is absent from the model excerpt; exact lookup must still find it.
Absent/formula cells and malformed coordinates are counterexamples.

The full local suite began on 99b and continues through this narrowly added lookup and
its later agent checks; early calculation/storage tests cover unchanged paths. Record
it as integration evidence with this source change, not a frozen-source acceptance run.
The next live cohorts remain fresh and require unchanged source identities throughout.
Native package 100 and exact-code hosted CI will cover the final combined implementation.


Candidate 100's full local integration suite passes (log full-checks-99b, with the
bounded-excerpt fix explicitly recorded above). The agent checks include the exact
original-header lookup regression and adversarial input-role tests; the real grammar
passes nested role variants with reasoning on/off. Native package 100 passes GPU/resource
identity, missing-model guidance with failed-run retention, ten missing-resource and
altered-resource refusals, signature, isolated install/update/uninstall, and extraction
through the packaged CLI. The separate preserved baseline package was not rebuilt and
its stale packaged journeys were skipped; no native package checks were skipped. Link
and knowledge validation finish with zero issues. No baseline app or original workbook
was changed. The installed Native Preview remains 76 because UI access is unavailable.

Cohort 11 now starts all six applications fresh on candidate 100, in Cash, Invoices,
Stock, Jobs, Production, Bookings order. Source and acceptance files are frozen for
this run. No generated app or earlier conversation is reused, and no source is manually
repaired. Two complete consecutive unchanged cohorts plus original spreadsheet oracles,
final native visual review and exact-code hosted CI still remain before closure.


### Candidate 101: numeric rejection checks derived by the host

Cohort 11 is diagnostic after Cash accepted month 1.5: its generated handler used
parseInt before checking integer-ness. It generated in 369.69 seconds and completed its
failed trial in 566.47 seconds. The separate source/formula comparisons passed, showing
why saved-cell matches cannot qualify the action contract. No generated source was
edited. Invoices subsequently passed its fresh full journey and 21 invalid direct-input
cases (437.96 seconds generation, 660.07 total). Stock's independent original-header
probe caught and returned a real invalid-entity defect to the local author. Preserve
all failures; this cohort cannot count toward the two consecutive clean trials.

Candidate 101 generalizes structured input roles: actual number/decimal action inputs
must declare requested whole-number, inclusive-bound and nonzero rules. The host derives
typed fractional/below/above/zero variants from a successful call, grouped into one
isolated rejection check after precisely its pre-call setup. No successful insert runs
before its invalid variants, so duplicate checks cannot mask missing numeric validation.
Each variant must reject without committed changes. Semantic rules still come from the
independent model's reading of the request; finite checks are not a universal proof.

The private native grammar passes valid numeric/key/value branches with thinking on/off
and rejects malformed or incomplete roles. The independent receipt verifier passes
adversarial missing/stale/reordered/type-bypass cases. Real-worker regression and fresh
candidate-101 cohorts remain pending. UI screenshots are still unavailable; the preserved
installed preview has not been replaced while its visible session cannot be inspected.


Candidate 101b's real-worker regression passes: a positive-only review cannot accept
parseInt-truncated fractional months, corrected whole-value validation passes, and a
numeric input cannot bypass testing by claiming a value role. The first test attempt
incorrectly supplied just one scripted malformed verdict, then inspected the final
feedback after the fixture emitted unrelated empty verdicts. Repeating that malformed
verdict through the bounded reviewer budget fixes the test setup without changing the
product gate. The focused Excel reconstruction/import/review suite passes.

Candidate 102 adds compact named-action readiness guidance after Stock's reviewer kept
emitting UI form-fill sequences without the required successful named-action coverage.
No gate or retry budget was weakened. Stopped cohort 11 with exact checker SIGINT and
retained failure/runtime receipts. Its 18 completed Cash/Invoices operation/Undo states
independently recalculate all 180 formula values with zero mismatches; the invalid Cash
action remains a failure and Stock/other incomplete cases remain unqualified.

Stopped cohort 12 before any completed application after static review found numeric
probe confounding: min=1.5 plus whole=true must test 1, not 0.5 (which could be refused
only for fractionality). Bounds also avoid zero when a separate nonzero rule could mask
the bound. Narrow intervals use an in-range midpoint for integer testing. Candidate 103
adds these focused positive/negative/narrow-range counterexamples, exact-representation
refusal and independent receipt verification. The full focused Excel suite passes.
Candidate 104 also tells the author to validate the original numeric input before
truncation, directly addressing Cash's observed cause. It builds as a native package.
The private grammar shape is unchanged since its candidate-101 passing check.


### Installed native intake check on candidate 104

Recovered visual access after cancelling a stale Window menu through its normal native
accessibility action. Screenshots and controls then worked. Quit the old preview normally,
verified process exit, installed package 104 and compared installed main/CLI/extractor
Mach-O UUIDs and both worker SDK hashes before opening its exact bundle. No baseline app,
VoiceOver or system settings were changed.

Preserved the earlier disposable UI import workbook, then used Start from files and the
native file/save pickers to create a fresh invoice workbook. The single Excel entry shows
purpose, Understand my workbook, Just use the tables, comparison limits and all three
sheets. Tables-only imports correctly; Home resumes that same import and exposes the
imported tables. A keyboard edit changes customer credit 5000 to 5100 and receivables 4600
to 4700. Returning to Customers retains Undo; Command-Z with table focus restores 5000.
The standard Edit menu's Undo is disabled when the unrelated output-view heading has
focus; the tested keyboard path operates from the edited table.

Rows are vertically centered at 1200 and 952 logical-point widths. At 842 points, purpose
text wraps, both primary choices remain visible, the lower worksheet/open-table controls
scroll cleanly and the status line wraps above its action row without covering controls.
No generated app or model build was used in this tables-only visual check. Fresh model
cohort 13 remains running independently; full native model/access and six-app checks remain.

Adversarial findings are consolidated in
[[records/reviews/excel-business-applications-2026-11-15]].


### Candidate 105: separate worker state for every invalid-input variant

Adversarial review found that zero committed writes do not imply unchanged JavaScript
closure/signal state. Grouping fractional/minimum/maximum probes let the first rejection
set a blocked flag that masked a missing upper bound. A real-worker regression first
failed against the grouped checks, then passed after each variant received a fresh worker
and only its exact pre-call setup. Receipts now contain one explicit rule/value and one
invalid call per check. The independent qualifier rejects grouped/shared-state proof; its
counterexamples and the full focused Excel suite pass. No generated source was edited.
Cohort 13 remains diagnostic because it started on 104 before these changes.

Candidate 104's diagnostic native Booking UI passes exact-version access disclosure,
centered tables, long-form scrolling, visible inline missing-number feedback, successful
reschedule with form reset, and Undo restoring Friday 14 from Thursday 15. All UI data
changes were undone and the test-only app grant was revoked. Forms and access disclosure
remain readable at 842 logical points. This retained app tests shared host controls; it
does not count as fresh final-six visual qualification.

Cohort 13 Cash generated after autonomous repairs in 554.05 seconds, then failed its
fifth conversation journey after 779.41 seconds: it asked for a Reference despite the
current request supplying TEST-C2. Earlier writes, original-result comparison and held-out
formula checks passed; the conversation failure remains a failure. Candidate 106 clarifies
that identifiers may follow operation names without field labels and empty visual form
drafts do not mean the current chat request lacks those inputs. This is a bounded prompt
correction, not proof that all natural-language extraction is reliable. Fresh retesting
remains required. Invoices passes its full cohort-13 journey in 438.86 seconds (216.49
seconds generation). The other four cases continue to collect breadth before rerunning.


### Candidates 107–109: recovery and explicit observed input contracts

The external business harness had the same transient-state risk as grouped review
probes. Candidate 107 restarts before every invalid direct input, then requires a valid
correction with the exact previously checked control state and a successful Undo. Row
versions must remain unchanged during refusal. A deliberately poisoned handler is now
refused; a correct handler passes both invalid/correction/Undo sequences. The focused
Excel suite passes. Receipt qualification requires the recovery-case count to equal the
invalid-input count; unchanged control states reuse their independent formula oracle.

Cohort 13 Stock's first two versions accepted the SKU header. Its second automatic repair
changed quantity validation rather than the failing SKU lookup. Candidate 108 combines
the already isolated exact field/rule/value feedback with distinct header-lookup repair
guidance. Stock's third candidate then encountered repeated reviewer decimal type
errors: the reviewer supplied JSON numbers to decimal inputs despite typed feedback.
Candidate 109 sends the actual SDK-observed action input contracts to the independent
reviewer, instead of requiring it to infer each argument type from JavaScript source.
Successful action execution still enforces the exact type; malformed arguments cannot
count as business refusals. Contract propagation and decimal/number/boolean counterexamples
are being checked. No generated source is edited and no retry or acceptance gate is loosened.


### Candidates 110–111: refuse ignored metadata and invented requirements

Candidate 109's SDK-observed input-contract propagation passes the focused Excel,
real-worker decimal/number/boolean and independent-qualifier checks. Cohort 13 remains
on runtime 104 and diagnostic. Stock exhausted twelve submissions; Jobs exhausted eleven.
The complete failures are retained, including malformed reviewer decimal arguments,
header acceptance, test starting-state mistakes, and syntax regressions during repair.
No generated app was manually changed.

Stock also emitted min:0 action-input metadata, which the SDK silently ignored. Candidate
110 now refuses unsupported input options and malformed descriptors at registration,
with a direct instruction to enforce business rules in the shared handler. It does not
pretend UI metadata enforces a business bound. All 26 SDK behavior groups and the focused
Excel suite pass, including explicit valid and invalid handler inputs.

Production exhausted three repeated failed submissions because the reviewer copied a
maximum of 3 from its guidance example, although the original request had no fixed batch
maximum. Candidate 111 uses unbounded numeric examples and requires finite bounds to
come from the actual request or source validation. Dynamic capacity remains a separate
state-dependent check. It also makes the existing host-Undo and Workspace-navigation
contract prominent, after Jobs generated unnecessary staff/Undo actions and the reviewer
demanded corresponding duplicate controls. These are generic context corrections; their
fresh local-model effectiveness remains unproven until the next full cohort. Gates,
expected business effects and retry budgets are unchanged.

Candidate 104's retained Booking comparison screens pass compact-window review: original
saved-result counts, varied examples, remaining limits, add-example instructions, included
example controls, all worksheet links and formula counts remain readable. View original
loads the three-sheet Quick Look preview. No example or workbook data was changed by that
inspection. This is shared host-UI evidence, not final fresh-six app qualification.


### Completed diagnostic cohort 13 and current regression

Cohort 13 completes all six without manual source edits. Invoices and Bookings pass;
Cash, Stock, Jobs and Production retain their failures. Bookings generated after two
submissions in 389.95 seconds and completed its full journey in 611.45 seconds, including
17 invalid direct inputs under the older 104 harness. Its result does not claim the later
107 correction-after-refusal coverage. Across completed Cash/Invoice/Booking operations,
27 retained states match all 288 independently recalculated spreadsheet formula outputs.
These comparisons do not clear the failed actions or incomplete generation cases.

Candidate 111's focused Excel and qualifier checks pass. Its separate ten-app unchanged
source regression passes all ten applications, 79 persisted-edit/reopen/Undo cases and
ten portable copies. It is explicitly a retained-app regression, not fresh generation.
Native package 111 builds and installs after normal preview exit. Installed main, CLI
and extractor UUIDs match packaged products; both worker SDKs match current source bytes,
and strict signature verification passes. The preserved baseline remains untouched.
The native UI now analyzes/builds an Invoice app from a short ordinary business description,
with no prior generated app. Its loading and compact-window feedback are readable.


### Candidate 112: live activity for native Excel builds

The ordinary native Invoice build exposed a real status mismatch: it was generating and
repairing while its conversation activity said Unfinished run with an elapsed time frozen
at zero. Excel's entry point had not attached its request to LiveRequestActivity. Candidate
112 shares the chat activity update/attachment methods, including operation ownership,
late-progress refusal after Stop, revision-aware polling and terminal clearing. Native and
desktop builds plus the preview activity checks pass. The first build attempt caught
private-member access while the adapter was being factored; the completed shared-method
implementation builds cleanly. Native visual recheck of live elapsed time and stopping is
still required. The installed app remains 111 while its unmodified automatic build finishes.


The installed-111 native Invoice build completed in 8m7s after six autonomous submissions,
with separate review catching and repairing an unknown-customer defect. Chat access approval,
explicit Confirm, chat-issued invoice, table recalculation and Undo passed. Native credit
entry refused an unknown customer with draft retention, accepted the corrected key, reset
its fields and updated derived balances; Undo restored all data and access was revoked.
Generation received only the original workbook and a short ordinary purpose description.
Two UI findings are isolated in shared code: live Excel request attachment (112), and
feedback positioned above the submit button so bottom-aligned validation remains visible
(113). Final native rechecks and fresh complete cohorts remain pending.


Candidate 113's 26 SDK behavior groups and focused Excel suite pass; its native package
builds. The shared checkout remains at fd1eabb; comparing current source against the 111
regression identity finds only the intended two activity/UI files and two SDK source/resource
files. No overlapping external changes were found. UI-import's original balances were
restored and its exact app access revoked before normal app exit.


### Candidate 113 final shared checks and fresh cohort 14

All source checks in scripts/check.sh pass. Its timestamp freshness condition skipped packaged journeys because the unchanged CLI is older than UI-only source changes. Explicit native package, isolated install/update/uninstall and extraction checks then pass against the verified candidate: 1,888 kernels, build-tree denial, missing-model guidance, ten missing-resource refusals, altered-resource refusal, strict signature and original-preserving intake. The preserved baseline package was not changed or requalified.

Installed 113 visibly shows a bottom-form validation error above Submit, retains the invalid draft and leaves records unchanged. Its temporary grant was revoked. A new Invoice workbook then passed analysis and build admission: request activity changed from 4s to 15s with live Reasoning and a saved SDK tool step. Stop persisted Stopped at 23s, exposed Build workspace again and retained the original purpose and tables. Retry started a distinct request at 4s; Stop persisted its separate 10s result. The preview exited normally before cohort 14 began. No generated source was modified. The disposable activity workbook is named Untitled and remains task evidence.

Cohort 14 starts Cash, Invoices, Stock, Jobs, Production and Bookings from scratch on candidate 113. No production or acceptance source will change during an eligible cohort. No passing batch is claimed before the complete outcome and independent verification.


### Diagnostic cohort 14 and candidate 114–115

Cash generated in 472.62 seconds after five submissions, including automatic repairs to a wrong typed test, a valid-month rejection expectation, numeric native field input shape, and a host-derived fractional cash-month counterexample. Its independent checks and held-out formulas passed. The fifth live chat journey nevertheless asked for a reference despite the literal request containing TEST-C2. Total Cash trial time was 650.83 seconds. This is the same conversation failure as cohort 13; candidate 106 wording alone did not resolve it. Cohort 14 continues all six on its frozen 113 executable, but is diagnostic and cannot qualify acceptance.

Candidate 114 makes app-inspection model context distinguish named-action contracts from empty native drafts. For apps with named actions, visual input details receive an explicit omission/receipt/path; the exact full result stays in the journal and tool_result can retrieve those controls. Short current requests are repeated verbatim beside the contract, sourced only from the admitted request, never app metadata. Longer requests stay intact in their original user message rather than being truncated. Control-only apps keep their existing inspection. Focused checks verify receipt identity/retrieval, hostile metadata replacement, long-request handling and the nearby control-only path. Chat checks pass after correcting a test-only method name.

Candidate 115 adds a diagnostic business-program replay option to isolate live conversation failures without regenerating code. It imports fresh original tables and rebinds an untouched retained package, marks freshModelTrial false and records the prior digest. It never qualifies fresh-generation acceptance. No generated source is changed. Focused chat and qualification checks pass. The local-model effectiveness of the simplified inspection remains unverified until cohort 14 releases the engine.


### Cohort 14 Stock false acceptance and candidate 116

Invoices passes its complete diagnostic journey in 737.02 seconds, including 21 independent invalid inputs and 21 successful corrections with Undo; generation took 538.24 seconds. Stock generated in 177.60 seconds after two submissions but failed the second chat operation at 280.03 seconds: Ship stock saved a positive quantity rather than a negative ledger movement. Its local reviewer copied the same wrong positive expectation and reported ready. The external business assertion caught the saved-value mismatch. This is a false acceptance by model review, not a verified app. The failed package remains untouched.

Candidate 116 removes implementation anchoring from independent Excel named-action review. When named actions exist, neither proposed nor prior implementation source nor builder tests are presented. The reviewer receives the actual SDK input contracts, a host-observed initial control structure (no value/text results from builder tests), original input cells/formulas and readable original logic. Existing control-only and non-Excel review behavior remains unchanged. No additional model pass, larger budget or weaker gate is introduced. Tests verify source/test withholding, contract/control propagation, no value/text properties or builder-test results, wrong-sign refusal and the corrected-sign counterpart. Focused verification is running. Fresh local-model effectiveness remains to be measured; zero final cohorts are accepted.


### Candidate 117: committed-effect evidence

A focused adversarial fixture reproduced a readiness false positive: a no-op action correctly rejected invalid numbers but matched a pre-existing expected row. The RED check failed at the intended assertion. Native app checks now retain host-observed committed transaction counts per named-action step, and independent saved-row readiness requires a positive count. Read-only value/text probes keep their existing contract. The external cohort qualifier enforces the same evidence and rejects missing/zero counts. Generated apps are unchanged. Focused GREEN checks are in progress; no new final cohort is accepted.


Candidate 117 focused GREEN verification passes: agent build, the complete isolated Excel conversion check group, the external cohort-qualification adversarial checks, strict formatting and diff whitespace validation. The no-op fixture now refuses; existing valid negative-sign saves and read-only numeric actions still pass. Live-model effectiveness of the context/review changes remains pending.


The separately labeled retained ten-app regression 117 passes 10/10 on the updated runtime, including 79 saved-edit/reopen/Undo cases and ten portable-copy checks. It reuses untouched earlier generated source and does not count as fresh generation.


### Diagnostic cohort 14 completed

All six fresh applications ran on the retained candidate-113 runtime. Invoices, Job Costing, Production and Bookings pass their full operating, refusal/recovery, Undo, reopen and portable journeys. Cash fails to map the supplied TEST-C2 reference into its named action; Stock publishes the wrong positive shipment sign and fails the independent saved-state assertion. The final source changed during this diagnostic, and zero final cohorts are accepted.

Generation/total seconds and save submissions: Cash 472.6/650.8 (5), Invoices 538.2/737.0 (5), Stock 177.6/280.0 (2), Job Costing 386.2/622.9 (6), Production 259.3/499.2 (2), Bookings 1070.3/1260.3 (10). The four passing apps complete respectively 21, 15, 5 and 17 independent invalid-input cases, each followed by a valid correction and Undo. Bookings repairs syntax/mount/fixture/control/test-setup errors autonomously; a reviewer setup failure and subsequent regressions remain in the record. No generated source was manually edited.

Independent cache-stripped spreadsheet recalculation matches 537 formula outputs over 48 retained states. This verifies calculations from the observed inputs; it does not erase the Cash invocation failure or Stock's incorrect business input sign. The unchanged Cash app is being replayed diagnostically with candidate 117 to test operation-context changes.


### Candidate 117: Cash replay and full source checks

The untouched cohort-14 Cash app passes its diagnostic operating replay on candidate 117 in 204.8 seconds, including the previously failed TEST-C2 request, ten invalid-input cases with valid correction/Undo, held-out calculations, reopening, portable copy and unchanged-source rebuild. Source is reused and no generation occurs, so this is not a fresh cohort and does not isolate context presentation from the different replay history. Fresh generation remains the decisive check.

The complete `scripts/check.sh` suite passes on candidate 117, including the new review/operation tests and db validation. Packaged native journeys require the new package; an explicit native build/package/install/extraction sequence is now running with no other model workload. The preserved baseline package remains separate.


### Candidate 118: keep reviewer setup failures out of source repairs

The first case in fresh cohort 15 reproduced another repair boundary problem. Cash passed builder checks, but the independent reviewer classified several string-encoded decimal inputs as text/value roles. After its bounded review failed, generic save-failure feedback exposed that review-only metadata as an apparent source defect. The builder then inserted unsupported minimum/maximum/whole fields into SDK action metadata; the SDK correctly refused them. No app was saved by those failed attempts. The running cohort remains on frozen candidate 117 and becomes diagnostic because production fixes are now in progress; zero final cohorts are accepted.

Candidate 118 explicitly lists numeric fields observed in the SDK and reports all numeric-as-value classification mistakes together. Actual numeric bounds remain inferred from the original request, not defaulted or relaxed. Inconclusive review gets its own host error category. The exact reviewer diagnostic remains in the durable receipt and is explicitly retrievable, while the builder receives a concise unchanged-candidate retry instruction. Reproduced business defects keep their full repair feedback. Check budgets, refusal gates and runtime authority stay unchanged. Regression checks cover aggregate decimal/number feedback, reviewer-only diagnostics retained in receipts, unchanged-source retry and terminal publication; focused verification is running.


### November 15 follow-up: candidates 119–120

The candidate 118 review-protocol checks pass. Native inspection then found a distinct completion-reporting defect in cohort 15 Cash: a corrected app.run saved the loan but the final answer repeated the earlier malformed-envelope refusal. State-only assertions had missed it, so cohort 15 remains diagnostic regardless of its old passed flags. Candidate 119 correlates only exact unambiguous nested app.run repairs and adds structured completion acceptance. Candidate 120 removes excess short-table whitespace while retaining explicit sizing and a bounded ledger viewport. Focused confirmation checks pass; renderer/visual checks and two unchanged fresh full cohorts remain required. The native diagnostic copy was restored with Undo, its grant revoked, and the app quit.


### Candidate 122: preserve input repair without hiding business refusals

The wider confirmation checks caught a regression in candidate 121: hashing all business inputs also left a stale failure when the model supplied an omitted required field. Using a generic app_input error code was insufficient; the nearby separate-item refusal check rejected that shortcut. The native session now retains the exact pre-invocation SDK input contract in its receipt. Confirmation recovery uses that structured contract to identify missing/mistyped inputs with zero writes and requires every already-valid supplied value to remain unchanged. Different business values and partial writes cannot settle the earlier failure. The original malformed outer envelope still never executes. Focused confirmation and chat checks pass on candidate 122. An initial bare-executable Excel check could not launch its XPC service; the required signed packaging runner is being used for that check. No production failure or acceptance pass is inferred from that runner error.


### Candidate 124: pace business qualification within the runtime budget

Candidate 123's signed Excel checks pass, including refusal of shifted-header counterexamples and the genuine wrong-sign defect. The full repository suite is running; native production compilation is prepared separately from packaging so its GPU checks do not overlap the local-model run.

Cohort 15 Stock generated in 763.9 seconds with seven submissions. All six conversational operations and Undo reached their expected saved states, then its tight 205-record growth loop exceeded the documented 16-transaction-per-second runtime cap. That remains a failed diagnostic result. Candidate 124 paces only synthetic business-harness commands with a 100 ms interval. Production budgets, generated source, the 205 new records, beyond-page duplicate refusal, exact state checks and atomicity requirements are unchanged. This qualifies business behavior and paging within the supported operating rate, not overload throughput. Final fresh cohorts will use the paced harness.


### Candidate 125: actionable native action-ID diagnostics

Cohort 15 Job Costing failed generation after five submissions in 310.3 seconds. After correcting an initial JavaScript syntax error, three submissions repeated a Workspace reference to the display title Log Time instead of registered ID logTime. The generic error did not identify either the rejected value or the valid IDs. Candidate 125 retains strict ID validation and reports the bounded rejected value, registered IDs and the distinction between IDs, titles and handler functions in both Workspace and ActionForm. It does not guess a mapping or rewrite generated source. The focused regression failed before the change and passes afterward; all 27 SDK tests and generated-resource consistency checks pass. Worker resources have been rebuilt. Fresh-model recovery remains to be demonstrated.


### Candidate 126: outer-envelope repair preserves business inputs

A further adversarial counterexample showed that a missing expectedVersion in an ordinary app.run envelope could be cleared by a later successful call with different business inputs on the same action. The regression failed before the fix. Reporting now requires every supplied business input digest to remain unchanged before outer-envelope validation can be settled. The malformed call still never executes; unrelated transactions and handler refusals remain visible. Focused confirmation and chat checks pass, including genuine same-input repairs, nested-envelope recovery, separate business refusals and missing/mistyped SDK input correction. Native release compilation is running on this candidate. No generated source was manually changed.


### Cohort 15 completed: diagnostic failures retained

The frozen candidate-117 run completed all six fresh cases with no manual source repairs. Production passed in 426.2 seconds overall, with one save submission and 160.1 seconds for generation. Cash's state-only pass remains disqualified by its observed stale-failure completion. Invoices exhausted its request (10 submissions, 1433.4 seconds); Stock exceeded the unpaced command rate after its conversational journeys (7 submissions, 1078.5 seconds); Job Costing and Bookings repeated display titles instead of Workspace action IDs (5 submissions each, 310.3 and 384.5 seconds). Every failed result and source is retained. Source changed during this diagnostic, so no final cohort is accepted. Independent spreadsheet recalculation of the retained completed journey states is running; it cannot erase these operational failures.


### Candidate 127: required blank-input recovery and checkpoint verification

A focused reporting probe reproduced a stale failure after correcting a required blank text/record value. Reporting now recognizes the SDK's exact ECMAScript whitespace contract before preserving valid input digests. Optional blank values and U+0085 remain valid supplied values, so changing them cannot erase a separate refusal. The pre-fix regression failed as expected; confirmation/chat checks and all 27 SDK groups pass, including the nearby optional/Unicode counterexamples. Signed Excel checks and native packaging are running. This change does not change the SDK's input acceptance or execute invalid calls.

The repository suite completed successfully through candidate 126, with packaged journeys explicitly skipped because their old output was stale. Candidate 127 has focused delta checks; exact-code hosted checks and explicit native package/install/extraction proof remain required. Cohort 15's independent cache-stripped spreadsheet recalculation matches 339 formula outputs across 26 retained states. Operational failures remain failures.


### Candidate 127: installed visual review and retained regression

The signed Excel checks, release build, explicit package resource/refusal checks (1,888 kernels), isolated install/update/uninstall and extraction journeys all pass. The actual installed preview matches package main UUID 0909FDFE-1E89-3EB8-975B-4C514775C2DA, CLI UUID 8C627540-03FB-37B6-99B3-925B959B6797 and both worker UUIDs F4AB035C-8125-381A-AF6B-00B9B0161A3E. Both installed worker SDK digests match source (443225eb66a98160bc2a3f91475aa0b634e4bd49414568cd0eab0f1bf20897bb). Strict signatures pass. The preserved baseline app was not replaced.

Native Cash inspection confirms compact short-table height, centered rows, wide/split/focused layouts, an approximately 844-point-wide window, native Tab navigation, visible invalid-month feedback and retained drafts. Correcting months 0 to 13 saved, reset the form and showed Completed; Undo restored the original 12-month state and forecast values. Filtering to no matches shrank the table and displayed the empty message; clearing restored it. All test writes were undone, access revoked and the preview quit. This reuses the untouched diagnostic Cash source for renderer verification, not fresh-generation acceptance. All six final generated interfaces still require inspection.

The separately labeled retained ten-workflow regression passes 10/10 on candidate 127: 79 saved-edit/reopen/Undo cases, ten portable copies and 302 independent/boundary UI steps. Source stayed unchanged. It reused earlier generated packages and performed no fresh generation. Final fresh six-app cohorts are next.


### Candidates 128–132: repair the review, preserve the acceptance boundary

Cohort 16 Stock repeated the identical candidate three times after isolated checks passed. Each independent review restarted with the same mistakes: a ready verdict with an issues checklist, decimal fields supplied as JSON numbers, then invented trailing decimal padding in an exact string assertion. Candidate 128 combines already-known verdict/input setup feedback and explains decimal spelling differences without accepting them. Candidate 129 replaces floating-point diagnostic equivalence with exact decimal spelling, so distinct large integers cannot be described as a type-only mismatch. Exact assertions remain unchanged.

Candidate 130 retains only the last host-recorded rejected review for an identical package/fixture/test fingerprint within the same authoring request. Changed candidates, successful reviews, actual app defects and separate requests discard it. Every retry still reruns isolated checks and all readiness probes. Prior diagnostics are explicitly untrusted and fit within the existing review-context budget. Candidate 132 bounds oversized diagnostic text by UTF-8 bytes with room for JSON escaping; combining-character and control-character regressions cover the limit.

Cohort 16 Production supplied a claimed operation defect whose counterexample only expected nonexistent saved rows, without invoking any operation. Candidate 131 routes that setup failure back to the reviewer instead of presenting it as a demonstrated app defect. Initial row assertions may still pass; a real operation followed by a wrong-result assertion still blocks publication. Regressions reproduced both the unchanged-review feedback loss and the fixture-only false diagnosis before their fixes. Focused signed GREEN verification is running on the combined candidate.

Cohort 16 remains diagnostic because Stock and Production failed and source changed during the run. Cash, Invoices and Job Costing complete their operating, refusal/recovery, Undo, held-out, reopening and portable-copy checks. Bookings is still running. No generated package was manually edited. Separate native copies of the three passing apps were checked at wide and compact sizes, including keyboard entry, retained invalid drafts, correction, dependent recalculation and Undo; all test writes were undone and grants revoked. These are diagnostic interface checks, not final fresh-cohort qualification. Candidate 127 exact-code hosted CI passed (run 43726304990).


### Candidate 133: distinguish a finished operation from its visual drafts

Cohort 16 completed with three full passes (Cash, Invoices, Job Costing) and three retained failures. Bookings generated a checked app in 555.5 seconds after four submissions, but its conversational overlap-refusal journey failed: the app correctly refused the overlap with zero changes, then the model repeatedly inspected mistyped app IDs rather than reporting that refusal. The 724.8-second failure is preserved. Independent cache-stripped spreadsheet recalculation matches 342 formula outputs across 34 retained states; this does not erase operational failures.

Named-action result presentation now foregrounds the host-recorded outcome, errors, returned result and saved changes instead of repeating unrelated visual drafts and the entire action catalog. The exact snapshot stays in the durable receipt. Bounded field omissions navigate original receipt paths, not offsets in a derived object. Guidance calls for reporting business refusals without retrying unchanged inputs or inventing replacements. Partial changes remain visible; no automatic success or early completion is introduced. Focused chat and confirmation checks pass for refusal with zero writes, failure after a saved change, successful writes, oversized results, untrusted replacement metadata and receipt retrieval.

Candidate 131 signed authoring checks and candidate 132 signed Excel checks pass, including continued-review isolation, fixture-only false-diagnosis recovery, genuine wrong-result refusal and exact decimal/large-integer assertions. The candidate-132 signed checker matches the current build UUID; signing changes byte hashes as expected. Strict formatting and whitespace checks pass. The repository suite and candidate-133 release compilation are running. An explicitly labeled diagnostic replay of the untouched cohort-16 Bookings package is testing the conversation correction. It cannot qualify fresh generation. Zero final cohorts are accepted.


### Candidate 133 verification and first fresh cohort

The complete local repository suite passes on the combined candidate, including all signed native/Excel checks, 1,888 packaged kernels, ten missing-resource cases plus an altered resource, model-absence guidance with a retained failed run, isolated install/update/uninstall, unrelated-CLI protection and extraction without Python/model/build-tree access. Only the preserved stale baseline package is skipped. The suite started under the candidate-132 log name and its later agent/native stages compiled and checked candidate 133 after that focused change. Candidate 133 chat/confirmation checks also pass separately.

Commit 1f7519d is pushed; exact-code hosted CI is running. The candidate-133 preview is installed and matches the packaged build: main UUID A9D161B9-5A2C-3933-B659-F15690035407, CLI B75CCE8E-BC5B-3442-910D-07B73E8DAE84, and both workers 5605BD53-B372-3D4E-801A-296977FA5514. Strict signatures pass and both installed SDK digests match source (443225eb66a98160bc2a3f91475aa0b634e4bd49414568cd0eab0f1bf20897bb). The preserved baseline app remains intact.

The untouched cohort-16 Bookings app passes its full diagnostic replay in 209.5 seconds: ten retained states, 17 invalid-input checks with successful correction and Undo, conversational overlap refusal, rescheduling/cancellation, missing-input clarification, held-out values, portable reopen and unchanged-source checks. Independent recalculation matches 120 formula outputs across ten states. The overlap now receives the truthful answer Couldn’t finish that action. Overlaps an existing booking. This replay is explicitly not fresh generation.

Native candidate-133 inspection passes the single Start from files entry with a new synthetic Production workbook, the table-only route, all three worksheet links, wide/compact layout, wrapped workflow draft, macro-source guidance, original-example selection/count, centered rows and a clear empty filter state. No model was invoked for that UI test, no execution grant was created, the filter was cleared and the preview quit. The workbook integrity check passes. Final model loading/cancellation and approval/chat/shared-state UI checks remain pending.

Fresh cohort 17 is running on unchanged commit 1f7519d, with Stock, Production, Bookings, Cash, Invoices and Job Costing in that order. Every case starts from a new workbook, analysis and generation; no replay or manual generated-source repair is used. Zero final cohorts are accepted until the complete run and its independent verifier pass. A separate retained ten-app regression is running on the same code and does not count toward fresh acceptance.


### Candidate 134: challenge unsupported numeric restrictions

Cohort 17 Stock reached a passing independent action probe, but the review inferred `nonzero:true` for unit cost. The original request requires positive receipt/shipment quantities, not positive unit cost; its original worksheets contain no data validation imposing that restriction. The host previously forwarded this failed derived probe directly as a proven app defect. That could pressure the author to prohibit a valid zero-priced item. Cohort 17 remains diagnostic even when its earlier checks pass.

Numeric probe failures now return to the same bounded independent review with `unconfirmed_input_rule`. The reviewer must ground the specific restriction in the original request/source, return a concrete reproducing revise verdict for a real defect, or correct its own input roles and rerun readiness. No action qualifies until its checks pass; no new inference budget, automatic publication or manual generated-source repair is introduced. Both policy and tool schema now use neutral numeric defaults and require authority for whole/nonzero as well as finite bounds. Header-key safeguards remain intact.

The focused regression first failed against the former behavior because a genuinely required fractional-month defect bypassed review confirmation (one review instead of two). Added coverage also requires an unsupported price restriction to be corrected with the unchanged app accepting zero. The six-business acceptance corpus now independently exercises a valid zero-cost update and exact Undo. Existing refusal and correction checks remain unchanged. Focused green verification is in progress.

The separately retained candidate-133 ten-workflow regression completed 10/10: 79 saved-edit/reopen/Undo cases, ten portable copies and 302 independent/boundary interface steps. This reused untouched generated packages and performed no fresh model generation; it is separate regression evidence.


Candidate 134 verification: the focused Excel suite and full signed authoring suite pass. Final tests also require an unresolved repeated numeric rule to remain inconclusive, preserve the rejected inference in the accepted receipt, and match the unchanged app digest. Static pinned-source/generated-SDK checks and cohort-qualification adversarial checks pass. The boundary corpus additionally tests zero hourly cost, zero loan principal, fractional stock receipt and fractional booking duration, each followed by exact Undo; these inputs are permitted by their existing requests. No original invalid probe was removed.

Candidate 134 is packaged and installed. Main executable UUID is `84F4980E-7094-3157-8DE7-BF592381D4EA`; CLI UUID is `B3B8BB5F-D92C-3738-BA46-9CA0F665BEDA`. Packaged and installed main/CLI/extractor/workers match their UUIDs, both worker SDK resources match current source, and strict signatures pass. The baseline app remains preserved. Full release checks and final native/local-model acceptance are still pending; the installation check only performed resource-path verification while the model cohort ran.


### Candidate 135: explicit Workspace action identifiers

Cohort 17 Stock, Production and Bookings each initially supplied display titles in Workspace action arrays. The runtime correctly refused unknown IDs and the author repaired them automatically, but this repeated an avoidable failed submission. The canonical short and shared component guides now explicitly say Workspace `sections[].actions` takes registered action IDs, just like ActionForm and named calls, while click tests use visible titles. No title aliasing, runtime fallback or business template was added. Candidate 134 numeric fixes and stronger allowed-boundary corpus are preserved. Full signed authoring verification is running; the next fresh model cohorts will measure whether this guidance reduces retries.

Cohort 17 Production completed its full diagnostic business journey in about 508 seconds, with generation about 242 seconds and three save submissions. Stock also completed its earlier checks, but those checks had not yet included the newly added valid zero-cost control. Neither case qualifies as final acceptance; the entire cohort remains diagnostic and all source repairs were performed by the local model.


Candidate 135 compiles and passes the complete signed native authoring and Excel suite. The guide change affects authoring context only; action resolution, permissions, source review and executable checks are unchanged. Cohort 17 Bookings published automatically after three submissions and is exercising its business journeys. Final fresh qualification remains pending.
