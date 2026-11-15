---
type: review
id: 01m7fb55rgf0b9rfxcfp0683tx
created: 2026-11-15T10:13:28.464388+00:00
updated: 2026-11-15T16:12:29.056633+00:00
summary: Shared formula, review, numeric validation, repair and authority fixes pass scoped checks; final fresh cohorts and native visual qualification remain pending.
title: Excel business application adversarial review
---
# Excel business application adversarial review

Scope: [[records/plans/excel-business-applications]]. This is an in-progress review of
the combined local-model, native-app and conversation path. It supplements
[[records/reviews/excel-reconstruction-and-engine-review]] and
[[records/reviews/native-app-adversarial-review-2026-11-13]]. Candidate numbers identify
retained local builds, not product versions or releases. Final fresh generation,
native visual qualification and exact-code hosted CI remain pending.

## Findings fixed in shared code

| Boundary | Reproduced defect | Resolution and evidence |
| --- | --- | --- |
| Calculated business state | Appended input records were absent from original coordinate maps; conditional totals and job-cost arrays could fail or miss growth. | Stable appended coordinates, retained tombstones/Undo and bounded native SUMIF/SUMIFS/SUMPRODUCT calculation. Formula-bearing sheets refuse invented extension. Independent formulas and post-action spreadsheet oracles cover growth. |
| Concurrent operations | A subscription update could advance the revision used by a named action while it validated older data. | Each action captures its starting revision, excludes overlapping named calls, and advances only through its own successful receipts. SDK race/Undo checks pass. |
| Native shared controls | Handwritten forms repeatedly diverged from conversation actions or lost failed drafts. | ActionForm uses the same registered function and typed inputs; native Workspace composes bound tables and actions. Busy state, disposal, error retention and successful reset have behavior checks. |
| Test integrity | Counts, rejected calls and author-selected wrong output signs could be mistaken for successful action evidence. | Every named action requires a successful direct call immediately followed by an independently derived saved-value/result assertion. The reviewer does not receive builder tests. Wrong-sign and rejection-only counterexamples refuse. |
| Original entity keys | Synthetic fixtures could omit a real worksheet header, letting equality-only lookups accept that header as a customer/product. | Structured key roles map to verified immutable original cells. The host injects each exact header into a successful call's pre-call state and requires rejection with no writes. Missing, forged, ambiguous and sparse header evidence is checked. |
| Evidence completeness | The model's 100-cell/12-KiB input excerpt could omit a later worksheet header, falsely blocking a valid mapping. | Exact host lookup reads retained original data separately from bounded model context. A 150-row first sheet plus sparse later header regression passes. Formula cells and oversized headers refuse. |
| Numeric validation | Cash's generated handler used parseInt before checking integer-ness and accepted month 1.5. | Every actual number/decimal input must receive requested numeric rules. Host-derived fractional, bound and zero probes run with correct types before any successful insert. The real sandbox rejects the flawed code and accepts whole-value validation. Numeric value-role bypass refuses. |
| Probe independence | Fractional bounds, a separate nonzero rule or narrow ranges could confound or omit a numeric check. | Whole/range probes use values that preserve the other applicable rules; narrow intervals get an in-range midpoint. Positive/negative/fractional-bound and precision counterexamples pass in Swift and the independent receipt verifier. |
| Probe state isolation | A rejecting handler can mutate transient closure state without writes and mask later invalid inputs. | Candidate 105 starts each variant in a fresh worker with only its pre-call setup. The deliberately stateful missing-upper-bound regression fails before the fix and passes after it; the qualifier rejects shared-state receipts. |
| Autonomous repair | A repair could forget a more complete runnable candidate or malformed review verdicts could force source rewrites. | Bounded, version-specific anchors use host-observed progress only. Contradictory verdicts get feedback in the independent review context. No retry budget, authority or publication gate was relaxed. |
| Conversation execution | Missing values could be guessed; malformed app.run envelopes were hard to recover; validation-only failures could remain recorded after a corrected call. | Exact argument-shape feedback preserves user values. Missing inputs require clarification. Durable outcomes distinguish validation refusal from actual handler execution and successful correction. Focused checks and the separate retained ten-app replay cover shared operations. |
| Package identity | Rebuilding byte-identical SDK resources changed mtimes and made fresh native packages appear stale. | Build writes only changed bytes. Resource/SDK identity checks include bytes and unchanged mtimes. Native package 104 passes kernel/resource, missing/altered-resource, missing-model, signature and isolated install/update/uninstall checks. |
| Acceptance provenance | Selecting two passing results could hide intervening failed trials or changed behavior source. | Qualification requires consecutive full fresh cohorts, unchanged source/fixture manifests, the complete generated package SHA, matching check/review receipts and independent spreadsheet outputs. Tests reject intervening/overlapping trials and changed calculation programs. |

## Authority and hostile-input pass

The generated worker still has no filesystem/network/process authority. Imported VBA is
read as evidence and translated; original VBA is never executed. Capability grants are
owned by the host and scoped to exact app versions and table bindings. Saving and copied
workbooks do not implicitly enable execution. The independent reviewer has only its
review tool, with separate grammar/typed payload validation and bounded synthetic checks.

Existing adversarial checks retain CPU/memory/serialization limits, missing clocks and
randomness in reconstructed behavior, exact allowed writes, hostile XML/container
refusal, cyclic macro-container refusal, schema/stale/read-only/foreign-record refusal,
atomic rollback, revoke and portable-copy authority. Changed paths were checked again
in the full candidate-100 integration suite and the candidate-103 focused Excel suite.
The native package uses the pinned unchanged engine; no new server or hosted fallback
was added. These are scoped tests and source review, not an independent security audit.

## Evidence and remaining qualification

The prior ten-app unchanged-source replay on the combined runtime passes all ten,
including 302 independent/boundary steps, 79 persisted-edit/reopen/Undo checks and ten
portable copies. It is explicitly not new model generation. Later changes address
review/probe acceptance and context, not that unchanged SDK business execution path.

Diagnostic cohort 10's 31 retained states match 351 independently recalculated formula
outputs. Diagnostic cohort 11's 18 Cash/Invoices states match 180 outputs. Their action,
review and incomplete-generation failures remain failures. Zero final cohorts are
accepted at this writing. Cohorts 11 and 12 have explicit diagnostic stop receipts.
No generated source has been manually repaired.

Final qualification must still include two complete consecutive fresh six-app cohorts,
all six final native interfaces and complete import/access/chat journeys on the exact
installed build, the exact-code hosted suite, sanitized receipts and final cleanup.
Native visual access is restored. Candidate 104 is installed with matching Mach-O UUIDs
and worker SDK hashes. Its fresh file-picker/tables-only journey, centered rows, keyboard
edit/recalculation/Undo and 1200/952/842-point layouts pass. Final generated-app and model
import/access checks remain pending. The preserved baseline app and user workbooks remain intact.

Finite cases do not establish universal Excel equivalence, correctness for arbitrary
future model output, all macOS/hardware combinations, VoiceOver behavior, production
signing, external services or customer adoption. Declared format and formula limits
remain visible; unsupported reconstruction cannot be described as verified success.


The candidate-105 focused Excel suite passes after the state-isolation regression.
Candidate 104's retained Booking UI additionally passes scrolling, inline validation,
successful reschedule/reset, Undo and compact-window access disclosure; the grant was
revoked and UI writes undone. Cohort 13 is diagnostic: Cash failed a conversation request
by overlooking an explicitly supplied reference, while Invoices passed. Candidate 106
clarifies request-to-input mapping; it remains to be measured on fresh generation and
conversation trials. No final cohort is accepted.


The external acceptance harness now also restarts between invalid inputs and requires
a valid correction plus Undo after each refusal. A poisoned-handler regression and
the focused Excel suite pass on 107. Stock's retained diagnostic repairs exposed
misdirected numeric fixes for header lookups and repeated decimal argument-type errors
in independent review. Candidates 108–109 provide field-specific header feedback and
SDK-observed input contracts to that reviewer; their focused/live verification is pending.


Candidate 109's type-contract propagation and focused/qualifier checks pass. Candidate
110 refuses ignored action-input metadata (such as min) and malformed descriptions;
26 SDK behavior groups and the focused Excel suite pass. Stock and Jobs in diagnostic
cohort 13 exhausted their bounded generation budgets. Production was falsely blocked
by a reviewer-invented maximum copied from a policy example. Candidate 111 removes that
anchoring and clarifies host-owned Undo/navigation; fresh live verification is pending.
None of these failures is omitted from acceptance or repaired by editing generated code.
The original/comparison/example screens and loaded Quick Look also pass the retained
compact Booking UI check; no data or examples were modified.


Diagnostic cohort 13 completed all six: Invoices and Bookings passed, four failed.
All 27 completed operation states match 288 independent spreadsheet formula values;
failed actions remain failures. Candidate 111's separately labeled retained ten-app
regression passes all ten, 79 saved-edit/reopen/Undo cases and ten portable copies.
Its focused Excel/qualifier checks pass, and installed main/CLI/extractor UUIDs and
both SDK hashes match the native package. Strict installed signature verification passes.
A broad-description native Invoice model build is running; zero final cohorts are accepted.


Native end-to-end Invoice flow on installed 111 passed from a short ordinary business
description: analysis, six automatic submissions, independent review, publication disabled,
chat-requested exact-table access, explicit Confirm, chat invoice creation and live formula
refresh. The build took 8m7s; enabling through chat took 22s; issuing the invoice took 43s.
These are observations, not a general performance guarantee. Reviewer counterexamples
caught missing customer-key validation, and the local author repaired it without source edits.

The chat invoice changed C1 balance/available credit from 400/4600 to 500/4500; native Undo
restored 400/4600. The native credit form rejected C99, retained all entered fields, then
accepted correction to C1 and stored -50, giving 350/4650. Undo restored the original state.
All UI test writes were undone and the grant was revoked. Tables, labels and all three
forms were inspected at 842 logical points. Two observed shared-UI defects are being
closed: candidate 112 attaches Excel builds to live request activity (native/desktop and
preview checks pass); candidate 113 moves shared form feedback above Submit because an
error appended below a bottom-aligned button was initially offscreen. Its tests and final
native recheck remain pending. No generated app source was manually repaired.


Candidate 113 completes the shared-UI rechecks: invalid credit/customer feedback is visible above Submit at a compact 842-point width, with retained draft and no writes. Live native Excel activity increments elapsed time, records real tool progress, stops durably and admits a distinct retry; both disposable requests were stopped and the app exited. All source checks and explicit native package/install/extraction checks pass. Packaging was run explicitly after the suite timestamp heuristic skipped the unchanged CLI. The baseline package remains preserved. Fresh cohort 14 is running; zero final cohorts are accepted.


Cohort 14 is diagnostic: Cash's fifth conversation again overlooked its explicitly supplied TEST-C2 reference. Publication and held-out calculations had passed, so this isolates a conversation-mapping failure rather than generated-app failure. Candidate 114 simplifies only model-facing app inspection: preserve named-action contracts and the exact current request, make visual drafts explicitly retrievable from the unchanged receipt, and leave control-only inspections intact. Regression checks verify untrusted app metadata cannot replace that current request and omitted controls remain available. Candidate 115's diagnostic replay is explicitly nonfresh; live verification remains pending. No generated program was edited.


A new false-acceptance counterexample is retained in cohort 14 Stock: both author and reviewer expected a positive stored shipment, and all their checks passed. The external operation oracle rejected it. Candidate 116 therefore withholds proposed/prior implementation source from Excel named-action review, alongside the already-withheld builder tests. Initial control structure and typed action contracts come from host observation; independent expected effects come from the request and original input/formula/macro evidence. Dynamic control values and builder-test outputs are omitted. Source review of control-only/non-Excel apps is preserved. The focused wrong-sign regression and context-boundary checks are running; live effectiveness remains unqualified.


### Candidate 117: no-op action could qualify against an existing row

The adversarial RED fixture made the expected saved row exist before calling a no-op action. The action correctly refused nonpositive amounts, so independent input-refusal checks could not expose its missing successful effect. The prior reviewer accepted it. Record host-observed committed writes per named-action step and require a positive count for readiness claims using saved-row assertions. Read-only text/value assertions remain permitted. The external qualifier also rejects absent/zero write evidence. This does not prove full business equivalence or rule out unrelated writes; independently derived exact values and the full external business journeys remain required. Focused GREEN verification is pending.


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


### Candidate 119: truthful completion after a nested tool-envelope repair

A native inspection of cohort 15 Cash exposed a false-failure answer after the loan update had committed. The first app.run placed its ID/version/inputs inside another arguments object. Validation correctly refused it, and the model corrected the envelope and saved the requested zero-rate loan, but confirmation grouping retained the earlier missing-fields error. The prior state/transaction assertions missed the user-facing contradiction. Cash's existing passed flag is diagnostic only; it does not establish end-to-end acceptance. Cohort 14 journey receipts contain no identical “was not invoked” symptom, but are not retroactively qualified by that narrower scan.

The reporting fix fingerprints the unambiguous one-level app.run invocation, including exact ID, version, action and inputs. It never executes or normalizes a refused call. Conflicting nested fields and unrelated later calls cannot settle the failure. A genuine handler refusal replaces the stale envelope error without becoming success. A focused regression reproduced the original failure before the fix; corrected-call, unrelated-target/input/version, conflicting-envelope and handler-refusal checks pass. Finish receipts now expose unresolvedActionFailure, and fresh journey acceptance requires both no unresolved failure and completed_action basis. The standalone qualifier refuses missing/contradictory completion evidence.

### Candidate 120: short-table density

The installed candidate 117 Cash interface was exercised on a separate synthetic workbook copy. Zero loan months was refused inline with the draft retained; correction to 13 saved, and Undo restored 12. Forecast and cashbook tabs displayed the expected rows; row labels were vertically centered. App access was revoked and the preview quit after the check. No generated source was edited. The short two-row assumptions table retained excessive blank viewport space and pushed its form below the fold. Default native table height now follows the row count with a bounded ledger viewport, and Workspace no longer forces a fixed table height. Explicit heights remain supported. Renderer checks and visual reinspection of this change are pending.


### Candidate 121: distinguish separate business transactions in confirmations

The follow-up adversarial pass found that two valid app.run calls with different inputs shared a reporting attempt key. A later successful transaction could therefore hide the earlier transaction's business refusal. A focused regression reproduced this false settlement. The attempt identity now hashes the exact app/action/inputs, while allowing the same business request to retry after refreshing its expected version. Nested-envelope correlation remains stricter and includes the version. The refusal and successful receipt both remain in history. Focused confirmation, chat and Excel checks are running on this candidate. Candidate 120's signed native worker/renderer suite passed all 18 groups, including compact two-row sizing and retained explicit heights; SDK tests and strict formatting also passed. No model-generated package has been manually changed.


### Candidates 122–123: input-repair and counterexample setup boundaries

Candidate 121's expanded confirmation regression caught both an omitted-input false failure and an unsafe attempt to classify generic app_input errors as validation. Candidate 122 instead retains the native session's pre-invocation SDK input contract. Reporting identifies missing/mistyped fields only with zero recorded writes, preserves all already-valid input values by digest, and keeps separate business refusals and partial writes unresolved. Focused confirmation, chat, signed Excel and all 18 native integration groups pass. The native event-through-XPC measurement was p50 2.62 ms and p95 3.04 ms across 30 samples; this is an internal event measurement, not local-model generation latency. A bare-executable Excel check failed to connect to XPC; the signed packaging runner passed and is the valid evidence.

Cohort 15 Invoices exhausted its request after 10 save submissions. Its last independent counterexamples were false source diagnoses: customer fixtures omitted the header, shifting C1 into Excel row 1 while the original formula still read row 2. The reviewer blamed the resulting absent C1 output on the candidate. A regression reproduced that false accusation. Candidate 123 validates declared numeric/key roles and original lookup-header positions for named-action revise probes before a failing expectation can be sent to the builder as a demonstrated defect. The reviewer can correct its fixtures within the same bounded review. A genuine wrong-sign counterexample remains a refusal with the actual SDK input contract supplied. Final focused checks are running.


### Candidate 124: separate paging qualification from overload testing

Stock's cohort 15 generated app passed its conversational receipt, shipment, overdrawn/duplicate refusals, explicit price-file update and Undo, but the unpaced 205-action stress loop crossed the documented 16 transaction requests/second cap. The runtime correctly stopped the app; this is not evidence that paging itself failed. The failure is retained. Business scenario calls now pause 100 ms before dispatch, including correction/Undo loops, while production budgets and all saved-effect/205-row/duplicate assertions remain unchanged. Runaway work inside one action still has the same runtime limits. The next fresh cohorts must demonstrate the full paced flow; this change alone is not a pass.


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
