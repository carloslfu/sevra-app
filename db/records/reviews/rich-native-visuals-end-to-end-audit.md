---
type: review
meta-type: conclusion
id: 01m7jmyvc7gf8bmnpseqvq0bwk
created: 2026-11-16T17:02:30.279060+00:00
updated: 2026-11-16T17:03:50.164226+00:00
summary: Three-pass code and plan audit closes eight handoff gaps; 28 SDK, 20 signed native and 21 preview groups pass within existing scope.
title: End-to-end code and visual-plan audit
---
# End-to-end code and visual-plan audit

Owner request: [[sources/notes/2026/11/rich-visual-end-to-end-review]]. Reviewed November 16, 2026, against source `6d833206dd9b56bf839d0ead2b811124686c57bc`. The owning [[records/plans/rich-native-visuals]] advances from revision 14 to 15 after three passes. This is an end-to-end trace of the affected visual, image, conversation and agent paths plus focused execution of the existing implementation, not a claim that every repository feature or future renderer was tested. Concurrent inference/context work is separate and preserved; its code edits appeared after these focused checks and are not qualified by this review.

## Decision

The plan is ready to begin staged implementation, with the corrections below. The current product is not the complete planned experience. Mini-app images and their Home embeddings work; standalone Home images and inline chat images remain absent. Rich chat input/results, the common visual contract and bounded media helper remain proposed. Passing existing tests does not qualify those missing features.

## Pass 1: trace the actual paths

| Boundary | Code inspected | Result and remaining implementation work |
| --- | --- | --- |
| Input to included original | WorkbookView, WorkspaceState.importFiles, ContextualIntake, Assets | File-URL drops capture an immutable included original and intake job. Bitmap paste is absent. Intake capture has a durable token, but its separate addMessage event does not share that identity. |
| Original to image pixels | NativeAppPackage, NativeAppProtocol, NativeAppSession, NativeAppRenderer, MediaFiles | Eight included-image aliases, exact app approval and native rendering exist. The resolver checks binding/path/type metadata, not a hash of the bytes decoded. Decode is synchronous ImageIO inside detached work; failed thumbnail tasks remain cached until reset. |
| Surface to inspection | NativeAppSpaceView, ImageViewer, HomeViews, ContentViews | Mini apps open a shared zoom sheet; Home embeds the same app. An ordinary asset component only opens a file. Enlargement is a host callback, not a chat operation; zoom scales a bounded preview. |
| Conversation storage to row | ConversationNavigation, WorkspaceSnapshot, ConversationContext, ConversationPresentation, ConversationViews | History tools can retrieve payloads, but the native window projection returns messages without a general rich-payload projection. Body-only cache/equality cannot represent independent surface/receipt changes. Chat blocks are text and tables. |
| Changes to history | SpaceEditing, Spaces, ChangeCapture, Archive, ImageDescription | Versioned replace/move/remove and immutable snapshot bindings are foundations. Source rebinding must use space/package mutations, not presentation-only overrides. Descriptions remain attributed evidence; display does not establish model vision. |
| Agent intent to operation | ChatOperations, ChatTools, NativeAppTools/Authoring, NativeAppSession.conversationSnapshot, ChatActions, CLI | Actions and table/input inspection exist. Image catalog/navigation is missing from app inspection. Existing app template export retains image asset IDs while exporting no image bytes; CLI and native host also differ on overwrite behavior. |
| Publication to continuation | Runs, RequestActivity, ConversationContext, ConversationHistory, ContinuationState and the prior full audit's prompt/scope/grammar mapping | The proposed request_input/needs_input protocol still requires atomic publication, terminal consumers and causal continuation. Existing finish/question guidance must change coherently. The inference/context plan remains the owner of context preparation. |
| Data to future visual | ComponentData, DatasetQuery/compiler/execution, DefinitionQueries, managed projections and plan examples | Existing ordinary charts do not provide the proposed shared typed system. Complete aggregation, exact Decimal values, typed Excel domains, snapshot-bound drill-down and independent oracles remain gates. Images must not depend on these query extensions. |

The prior [[records/reviews/rich-native-visuals-final-audit]] supplies the detailed agent seam map; [[records/reviews/image-support-and-plan-readiness]] preserves the image introduction/enlargement baseline. This pass rechecks their conclusions rather than treating old claims as runtime acceptance.

## Pass 2: adversarial findings and corrections

1. **Source replacement conflicted with presentation authority.** Revision 14 prohibited new asset bindings in presentation overrides but promised image replacement through that route. Revision 15 confines configure to allowed caption/layout fields, uses exact-version edit_space replace for ordinary images and reviewed package replacement for app bindings, and preserves frozen snapshots. Remove/move affects placement only.
2. **Capture retry did not guarantee one chat event.** WorkspaceState calls captureIntake then an independent addMessage. Revision 15 specifies a durable original conversation/publication intent and idempotent event receipt using existing mutation storage. Crash recovery reuses the captured source and exact message identity. Bitmap staging retains the input identity required by the path-hash replay check. No transaction spans copy, decoding or OCR.
3. **The promised chat viewer had no callable contract.** Current enlargement callbacks and app.inspect's text/table/control projection do not expose image navigation. Add bounded image discovery plus proposed visual.navigate for open/return, fit/zoom and retry, shared with controls. Headless navigation reports unavailable instead of claiming a visible window. Retry cannot reimport or replay business work.
4. **Payload persistence was not enough to render the transcript.** Specify coherent, bounded summary projection into WorkspaceSnapshot, revision-aware cache/row identity and visible hydration. The current 100-message, 2 MiB body window cannot eagerly load 100 additional 128,000-byte payloads. Share-to-main retains text and an origin link, never a copied actionable approval.
5. **The proposed image memory budget could not guarantee its maximum resolution.** A 4,096-square RGBA buffer consumes 64 MiB before other retained allocations. Specify reservation, actual row-stride accounting, pinned mounted consumers, further downsampling/refusal and separately measured helper/copy peaks. Zoom is not a claim of original-resolution decoding.
6. **The current image check could accept the wrong same-sized image.** It builds a green PNG but checks dimensions, callbacks and revocation, not its pixel colors. Acceptance now separates original-byte SHA verification from a decoded pixel oracle, with declared color conversion tolerance, identical-size/different-color fixtures, rapid alias switches, enlarged revocation and restored-file retry.
7. **Early images inherited contracts assigned to later charts.** P1-image now owns the minimum canonical owner/reference/presentation foundation and metadata/reconstruction registration. P0-visual extends it. The common P0-chat result/event projection blocks images; unfinished question continuation and diagram work do not. Export discovery is gated by implemented capability.
8. **Image template exports are not portable.** Native ChatActions and CLI clear dataset IDs but retain image IDs in a JSON-only template. The plan requires a shared Core export boundary, unchanged-destination refusal and explicit refusal of image-bound templates until a real unbound-image/rebinding contract exists. Portable workbook copies preserve originals; they are not silently substituted for a template. This correctness guard belongs to P1-image, not deferred rendered-visual export.

These are corrections to the implementation plan and documented current limitations, not claims that new runtime safeguards have shipped. No product code was changed in this audit.

## Pass 3: whole-plan consistency

| Plan section | Final consistency check |
| --- | --- |
| 1. Inventory | Distinguishes actual mini-app/embedded images, file inspection, absent chat/standalone images and unimplemented shared visuals. |
| 2. Experience | Chat can express semantic operations; controls remain useful without an extra model turn. Compact views retain meaning and original navigation; no silent Home rearrangement. |
| 3. Catalog | Basic images are early, repeated media and diagrams later. No app generated merely to display a picture or ask a question. |
| 4. Architecture | Module direction stays acyclic. Owner/preset/capture authority, canonical source mutations, exact image identity, recoverable publication, reservation-based media and export boundaries agree. Existing assets/history remain authoritative. |
| 5. Chat and agent | Request publication, supplied values, exact review claims, per-question drafts, partial effects, direct operations, continuation and read-only policy remain coherent. Projection and viewer discovery now have explicit owners and bounds. |
| 6. Technology | Native Charts integration and layout-engine selection remain measured gates. No new dependency was selected or qualified in this audit. |
| 7. Delivery | Common publication first; usable chat and early image paths can finish independently; charts extend the image foundation; diagrams cannot block earlier increments. |
| 8. Verification | Positive and adjacent refusal cases cover attachment event crashes, transcript limits, source replacement, image identity, memory admission, template export and destination preservation. Existing dimension tests are not described as a pixel oracle. |
| 9. Gates | Checkboxes remain open. Each family has bounded acceptance and honest unavailable behavior; no global all-actions/all-visuals or production reliability claim. |

The first implementation checkpoint should resolve only three groups of work: the shared publication/transcript foundation, exact semantic ownership/dispatch routes, and the first increment's native/media acceptance. Later chart/diagram features remain queued. The plan is a staged program, not a requirement to build the whole catalog before anything becomes useful.

## Executed verification

All checks used synthetic fixtures and current source; no installed bundle was opened/replaced and the active user app was not controlled. The native harness packages its own signed test host and XPC workers; preview checks mount offscreen native views.

| Command | Observed result | Scope |
| --- | --- | --- |
| `npm test` in sdk | 28 passed, 0 failed | SDK actions, validation, events, revisions and native contract behavior. |
| `swift build --product sevra-app-worker -j 4` | Passed | Current worker compiles. |
| `swift build --product sevra-native-app-checks -j 4` then `python3 scripts/check_native_apps.py` | 20 passed, 0 failed | Signed XPC/native controls, real transaction/recovery, conversation actions, included PNG rendering/enlargement callbacks and revocation. Includes workbook copy/replay and access separation within existing fixtures. |
| `swift build --product sevra-preview-checks -j 4` then `.build/debug/sevra-preview-checks` | Exit 0; all 21 reported groups passed | Preview ownership/cancellation/retry, workspace snapshots, conversation state/history, drafts/review/clarification, native text/tables and image decode foundations. |

No new actual-model cohort, cross-surface image journey, bitmap-paste test, pixel-color oracle, production media-resource measurement, VoiceOver/system-setting test, installed-build qualification or full release suite was run. Missing planned features cannot pass an end-to-end test before implementation. Broad suite repetition is unnecessary for this documentation-only revision under the focused verification policy. Final validation passes: dbmd validate --all db reports zero errors/warnings; scripts/check_links.py and git diff --check pass. Both JSON examples parse, all nine numbered plan sections remain present and every implementation checkbox remains open. Generated catalogs are staged from this review alone so concurrent inference/context records and code are excluded from its commit.
