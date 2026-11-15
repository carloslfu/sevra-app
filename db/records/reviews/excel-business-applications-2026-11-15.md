---
type: review
id: 01m7fb55rgf0b9rfxcfp0683tx
created: 2026-11-15T10:13:28.464388+00:00
updated: 2026-11-15T13:17:12.762082+00:00
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
