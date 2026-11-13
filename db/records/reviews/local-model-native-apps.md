---
type: review
id: 01m79e5wmzqy3rm1desn86rea7
created: 2026-11-13T03:10:51.039275+00:00
updated: 2026-11-13T04:51:08.115065+00:00
summary: Adversarial review of local-model native app authoring
title: Local-model native app authoring adversarial review
---
# Native app authoring adversarial review

Scope: [[records/plans/local-model-native-apps]], the local-model tools, sandbox preflight, SDK bridge, native grants and persisted provenance. This is an internal adversarial pass, not an external security certification.

## Findings and repairs

1. **Blocking, AI table provenance:** a policy label is not an accepted rule Source. The initial calculator-only agent test missed empty-table creation. Publish a fixed host-authored policy as a programmatic captured change, then attribute the app/table schema decision to the actual model and exact policy Source. The policy permits inert code and empty schemas only; no runtime grant or business-row acceptance. Added a real agent-dispatch regression over an inventory table and workbook verification.
2. **High, async failures:** unhandled rejected promises could disappear while the UI remained apparently healthy. The C shim now tracks bounded unresolved rejections, releases tracked values, permits handled failures and poisons the worker on an unhandled rejection. Both cases have real-worker checks.
3. **Medium, misleading test visibility:** hidden ancestors, inactive tabs and closed disclosures must not satisfy visible-text checks or accept actions. The scenario runner now checks actual hierarchy visibility and control types/options/ranges.
4. **Medium, ineffective model repairs:** error feedback selected a status label instead of its current text; missing row-count assertions produced a generic failure. Feedback now includes visible values and explicit assertion errors. Test variants have discriminated schemas with required arguments. Picker selection uses the same native change semantics. SDK guidance includes complete native form/calculator examples and warns against frozen signal snapshots.
5. **Medium, response truncation after maintenance:** code authoring needs a larger bounded response than normal chat. A host-owned flag survives context maintenance and enables up to 8192 output tokens; it is never inferred from untrusted prose. Context capacity and generation time bounds still apply.
6. **Low, ambiguous receipts:** native apps get a specific saved-disabled receipt, whole-number assertion counts and correct singular/plural text. Failed attempts reconcile by exact app ID/name.

## Authority and recovery checks

The model cannot supply the host's separate sandbox proof through tool arguments. Core rejects missing/wrong proofs and explicit read-only requests. Test fixtures strip every real dataset ID and use a temporary workbook with no device permission grant. Every write goes through the normal typed native broker. Save uses exact source digest, optimistic app version, atomic captured installation and operation-token replay. New code versions require fresh native approval. Existing data and fixture data remain separate. Failed checks save no app or fixture rows. A first successful AI authoring attempt may publish the fixed policy Source before a later install refusal; receipts never claim that all prior changes were undone.

Resource checks cover package/source sizes, tree shape/properties, async errors, loops, unavailable APIs, request/transaction/frame limits, bounded test steps/fixtures, monotonic overall deadline, XPC response timeout and cleanup. The existing sandbox OS denials and exact-version/physical-file grants remain independently tested. The desktop does not link QuickJS.

## Open verification

Actual local-model creation/edit/repair scenarios and installed visual checks are in progress. No passing synthetic assertion establishes full semantic correctness, unrestricted Excel replacement, external security qualification or arbitrary scale. Final receipts must distinguish model-authored assertions from independent checks and from actual UI observations.

## Additional actual-model and boundary findings

7. **High, tests can miss the requested outcome:** an actual model generated a literal count heading, with passing heading-only tests. Add a second restricted local-model review of the request, source and tests before saving. This is not a security boundary or correctness proof. A synthetic refusal regression verifies it cannot save and sees only its private verdict tool. Actual populated read-only dashboard checks independently verify the resulting numeric count.
8. **Medium, overly strict review:** a separate static heading followed by a dynamic numeric Text is valid. Clarify the review contract to avoid demanding that the label itself be dynamic. Require preservation of existing initial field values on unrelated edits.
9. **Medium, schema diagnostics:** omitting a read-only binding's write flag produced a generic decoder error and wasted repair attempts. Omission now safely means false. Missing fields report their exact package path. Both have focused regressions.
10. **High, preflight process boundary:** generated source awaiting approval must not share the process used by enabled apps. Package a distinct sandboxed check service and assert different PIDs while both are connected. Independently probe foreign-file and network denial for both; install verification checks each helper's exact packaged bytes and minimal entitlement.
11. **Medium, name lookup and continuation:** source inspection accepts exact name or ID, refuses ambiguity and returns the canonical ID/version. Native authoring now has an explicit continued-work scope. Tests cover existing source, scoped dispatch, optimistic updates and retained bindings.

The initial actual-model failures are retained in the local test output. Early runs exposed missing API imports, frozen signals, malformed assertions, the exact rule-source requirement, shallow count tests and changed calculator defaults. Passing later cases must not be retroactively reported as first-attempt success.

12. **High, canvas test/bridge mismatch:** native drag and arrow-key events supply movement deltas. Early authoring guidance was ambiguous, and one independent fixture treated drops as absolute coordinates. The SDK guide and test schema now explicitly describe deltas. Independent checks exercise repeated movement and clamping, and a focused scenario asserts positions after positive and negative deltas. Shape IDs must match regions for native drag feedback. The initial canvas result remains a retained failure, not accepted evidence.
13. **Low, typography contract:** the renderer accepted a semibold Text property but rendered it as regular. It now uses the requested native semibold weight.

## Installed interface pass, in progress

The first installed chat request generated Workshop stock after two refused synthetic attempts and a successful repair. Those refused checks had confused starting fixtures with expected inserted output. No app or fixture rows were published before passing. Feedback now names the starting fixture count, and the guide explicitly distinguishes seeded rows from expected outputs.

Observed native paths: explicit enable, empty-form error, keyboard Tab from item to quantity, exact decimal 12.5 saved, automatic form clearing after success, live native table row, unmatched search and restoration, and invalid decimal refusal without inserting a row. Row text is visibly centered and numbers align right. The access screen identifies the actual Stock table and its write scope.

Polish findings: a generated search control had an accessible name but no visible hint, and vertical-stack actions stretched to the entire table width. The renderer now falls back to the field label for its placeholder and keeps buttons at intrinsic native width unless an explicit width is provided. New installed verification is required for these final visual changes. A requested chat edit and fresh-version access/reopen checks are still in progress.

## Follow-up edit context repair

The installed conversation edit was intentionally stopped after 4m25s with the previous working app and its saved row intact. Its refused attempts included syntax errors, an invented `data.rows` API and a literal count. Source inspection had returned the package but did not automatically return the SDK on this follow-up turn. `read_native_app` now includes the current guide alongside exact source/version, and a focused check verifies that a normal source read and its guide survive result projection intact. The standalone SDK tool remains available for larger projected responses. JavaScript failures now include a bounded source stack location; an unknown-API regression verifies that feedback names `sevra-app.js`.

The separate local review correctly refused the literal count in this run, but also included an unnecessary layout comment. Its findings remain advisory model judgments with bounded repair attempts, not semantic proof. Final installed re-verification must exercise the same edit with the repaired source-read context.

## Routing, recovery and prompt-budget pass

An installed layout edit initially selected fixed-space tools and produced several failures before successfully saving the programmable app. The active native workspace now explicitly identifies its programmable type and exact ID to the model. Fixed-layout edit and snapshot tools refuse such apps with actionable native-tool guidance before parsing component edits. Duplicate-name guidance selects the correct app-edit path. Regressions verify all refusals preserve the app source and version.

A later successful checked save now settles earlier failed edits to the same app by exact ID or name, including a repaired wrong ID. Failed changes to another app and failed snapshot requests remain visible. All attempts remain in the activity evidence. This prevents repaired errors from dominating a successful final receipt without concealing unrelated failures.

The complete typed behavioral-test schema increased the full tool prompt to 9542 tokens. Ordinary chat now omits that save schema until successful SDK/source inspection; its measured prompt is 8361 tokens, with an explicit 8448-token gate. The authoring mode has a separate 10240-token prompt gate and bounded 8192-token output allowance inside the same 32768-token context. The host flag propagates through context measurement, generation and compaction in both inference adapters. The private review scope remains restricted to its verdict tool. These limits are measured against the pinned tokenizer, not character estimates.

The grammar-reference generator now supports anyOf test variants, unions and open objects. Canonical schemas and all pinned-reference masks were regenerated: 56 tools, 80 cases and 744 exact masks. Focused authoring and grammar/agent suites pass after the routing and confirmation changes.

## Installed visual and data observations

The SDK-in-source-read repair allowed the inventory edit to save a live count while retaining the original table and its saved decimal 12.5. A subsequent layout request was needed to place the two buttons in one horizontal Row; the model review had missed that visual requirement. The corrected Row was inspected at normal and constrained widths, with visible Search items placeholder, native button sizing, centered table text and right-aligned decimals. Human visual inspection remains necessary for generated apps.

Before any new inference request after reopening, the enabled app inserted a second synthetic row and Undo restored the original row. No local inference server was running during those operations. This demonstrates that saved mini-app execution is independent of generation. Final-candidate generation, package identity and the full release gate are recorded separately when complete.

The last contract pass corrected canvas press simulation to send zero movement, matching native clicks. Press steps no longer offer unused coordinates; drag and region-position steps still require them. A real-worker regression asserts that a click preserves coordinates before positive and negative drags. The canonical reference masks were regenerated again; final authoring prompt size is 9506 tokens (ordinary chat remains 8361). Strict formatting for 29 Swift files, changed Python compilation and documentation links pass.

## Final-candidate context-boundary regression

A fresh calculator request in the long installed test conversation read the SDK, then failed its first synthetic assertion because initial zero values were tested as though empty. Before repair, the host stopped at 24777 tokens against its unchanged 24576-token maintenance trigger. Investigation found a real metadata bug: reference annotation rebuilt each inference message without its authoring flag. Maintenance therefore measured the smaller ordinary tool schema, underestimated this prompt by 1145 tokens and skipped needed compaction; the final dispatch measurement correctly refused it.

Reference annotation now preserves the host-owned authoring flag. A threshold regression reproduces that exact undercount: ordinary 23632 tokens appears below the trigger, while the actual 24777-token authoring prompt must compact. It checks that the compacted result retains authoring mode, the exact current request and original history. The neighboring ordinary/boundary/irreducible-floor/no-gain/incomplete-retry cases remain enforced. No context trigger, capacity, authority boundary or failure safeguard was raised to make this pass. Installed retry on the corrected candidate remains required.

The corrected installed candidate compacted the same conversation from an actual 24747-token authoring prompt; subsequent dispatch used 16917 tokens, retaining the 8192-token output allowance. This closes the measurement mismatch. The next failure was independent: the model repeated an extra closing parenthesis three times and the existing repetition limit stopped it without publishing an app. Compiler feedback now includes a bounded, numbered source excerpt around the reported line and explicitly says no test steps ran. The excerpt accounts for the runtime's one-line prelude. A focused regression checks the offending source line and a nearby runtime error remains correctly distinguished from a syntax failure. No generated code is silently rewritten or accepted by a heuristic.

## Missing-app recovery and canvas UI

A later continuation tried to read a calculator that had never passed its checks. The generic missing-space response led the model toward fixed-layout tools, which correctly refused it. Missing native-app lookup now explicitly explains that failed builds save no app and identifies the native creation route. Writable requests also receive the host SDK with the lookup failure, enabling the same bounded authoring schema after real SDK delivery. Read-only requests still cannot enable writes. A real agent-dispatch regression starts from a missing app, verifies the host authoring mode transition, then performs a checked creation with no duplicate or preexisting app.

The local-model-generated Seating plan package was imported and enabled without business-table access. Actual native dragging moved Table A while Table B stayed fixed; Right and Down then moved only the selected region. The accessible native region buttons and canvas focus ring were visible. Reopen persistence is the remaining final UI check for this sample. Generated canvas labels still warrant per-app visual design review; the engine does not enforce an aesthetic layout from arbitrary source.

## Final installed acceptance and retained limits

The final installed main UUID is `6F410451-9213-3901-AE05-925898D789BA`; both isolated runtime identities use worker UUID `1AFBF675-2DF8-3840-B235-BDE64AF75671`. Main UUIDs match the packaged build and both signed helper bundles match exact packaged bytes. Strict bundle signatures and resource checks pass. The installer adds the CLI and re-signs the bundle, so the installed main signed bytes differ from the packaged main; UUID and source/build evidence are recorded explicitly. See the [final acceptance receipt](../../../integration/evidence/2026-11-12-local-model-native-app-final.json).

Canvas reopening preserved Table A at (90,100), after native drag and arrow-key movement, and Table B at (160,20). Stock creation and subsequent source edits preserved the shared table and original 12.5 row, required fresh version approval, and passed native validation, search, live count and Undo. The final button rename produced a clean saved-disabled receipt while retaining refused attempts in activity. Normal and constrained widths were visually inspected; table cells are centered vertically and decimal values align right.

The final long-conversation calculator retry correctly used native tools after missing-app feedback, but still repeated a closing-delimiter error three times. It stopped without publishing. This is an observed remaining model reliability limit, not a completed repair claim. A fresh focused thread on the same final build then repaired two syntax attempts and an incorrect test expectation, passed five assertions and separate local review, and saved Price check in 1m48s. Actual UI checks confirmed both inputs initially 0, initial Total 0, keyboard Tab between fields, exact 3 × 2.40 = 7.2, and visible invalid-decimal feedback. Labels, spacing, focus rings, button sizing and the full error were inspected. The generated calculator uses a shared Total/result area for errors; per-app styling can still be improved through a follow-up request.

The seven broader actual-model scenarios plus inventory edit retain independent behavior checks in [the scenario receipt](../../../integration/evidence/2026-11-12-local-model-native-apps.json). They establish representative successful outcomes after iteration, not a pass rate or universal first-attempt reliability. Complex or long conversations can still need a focused new thread. The separate model review missed one requested horizontal layout, so it does not replace native visual inspection.

## Final verification ledger

`scripts/check.sh` ran the broad functional suite through desktop compilation: 5 SDK tests, 14 native runtime groups, 650 core checks, CLI/database/durability/document/UI/voice checks, and agent/grammar/performance-harness checks passed. The native package stage then refused `model_busy` because an installed UI generation run was active. This was retained as a failed invocation, not reported as a clean full-script exit. After inference stopped, final localized fixes passed `python3 scripts/check_native_app_authoring.py` (10 groups) and `python3 scripts/check_splash_grammar.py` (complete agent suite; 80 grammar cases, 744 masks). `scripts/build_native.sh` and the final release build succeeded. The remaining native tail passed separately: `python3 scripts/check_native_package.py`, `python3 scripts/check_install.py --native`, and `python3 scripts/check_extraction_package.py`. Actual installation and exact candidate identity verification passed. The preserved baseline package was stale and its optional journeys were skipped, not passed.

Strict `swift format lint --strict` passes for all 32 changed/new Swift files. All four changed Python files compile, and `git diff --check` passes. Final documentation links and db.md validation are part of the closing checkpoint. Public receipts contain relative source hashes and log hashes, synthetic outcomes, installed identities and qualification limits; local log contents and private paths are not published. Hosted CI for this new source is not claimed by historical successful runs.

The authoring integration is complete as a source preview with these explicit limits. This internal adversarial review is not an external security audit. VoiceOver, production signing/notarization, additional hardware, arbitrary native APIs and full Excel compatibility remain unqualified. No real business workbook, website repository or preserved baseline app was changed.
