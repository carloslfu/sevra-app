---
type: review
meta-type: conclusion
id: 01m7jkxmqq80nch39e99wtvrj3
created: 2026-11-16T16:44:22.135406+00:00
updated: 2026-11-16T16:45:41.020274+00:00
summary: 'Three-pass image audit: mini apps and embedded Home support images; inline chat and standalone Home need the new P1-image increment.'
title: Image support and implementation readiness
---
# Image support and implementation readiness

Owner request: [[sources/notes/2026/11/image-support-plan]]. Reviewed November 16, 2026. The owning [[records/plans/rich-native-visuals]] advances to revision 14 after three passes. Initial clean source was `c0669207d67a4a238afdaf90fa38c7184215c83b`; the concurrent enlargement follow-up `05d3fe8b4f946bf66557a69123f2974112710ba4` was committed during the audit and its complete relevant diff was also inspected. This review changes planning only and preserves that separate implementation. It does not verify the installed bundle, launch the app or claim a new UI/model acceptance run.

## What works now

| Surface | Current source behavior | Limit |
| --- | --- | --- |
| Mini apps | Real included workbook images through `Image.asset` and up to eight named manifest aliases; SF Symbols remain `Image.symbol`. Access review names the images. The follow-up adds an enlarge sheet using the shared native zoom viewer. | Included assets only, with current exact app permission. No URL/path image source or arbitrary row-derived asset access. Captions and shared broker/resource guarantees in the new plan are not yet implemented. |
| Home | An embedded mini app uses the same NativeAppSpaceView/session and therefore can display and enlarge its declared images. | A standalone ordinary `asset` component renders an Open file button, not an inline image. Showing an app image through Home is not a standalone Home image component. |
| Chat | Imported files create saved event links. Messages render attributed text and native tables; links can navigate to the separate file viewer. | No typed inline image block or image renderer in either user/event or assistant messages. Markdown image text is not an implemented pixel-rendering contract. |
| File viewer | ImageIO decoding and native image zoom already exist separately from chat/Home. | Opening an image elsewhere is not inline support. OCR and user-authored descriptions are separate from display and do not establish visual model understanding. |

This corrects the stale revision 13 assertion that mini-app Image meant only SF Symbols. It also avoids the opposite overstatement that all three surfaces already support images because file previews exist.

## Pass 1: implementation inventory

- [NativeAppPackage.swift](../../../Sources/SevraCore/NativeAppPackage.swift), [NativeAppProtocol.swift](../../../Sources/SevraAppProtocol/NativeAppProtocol.swift), [NativeAppTools.swift](../../../Sources/SevraAI/NativeAppTools.swift), [NativeAppAuthoring.swift](../../../Sources/SevraCore/NativeAppAuthoring.swift) and [SDK declarations](../../../sdk/index.d.ts): existing eight-image alias manifest, exact included asset IDs, declaration validation, access and authoring guidance. Reuse these rather than add a competing image SDK.
- [NativeAppSession.swift](../../../Sources/SevraAppUI/NativeAppSession.swift), [NativeAppRenderer.swift](../../../Sources/SevraAppUI/NativeAppRenderer.swift) and [NativeAppSpaceView.swift](../../../Sources/SevraAppUI/NativeAppSpaceView.swift): current grant/epoch checks, 1,024-pixel thumbnail loading, native image controls and the later 4,096-pixel enlargement route. Current decoding is detached in-process work, not a bounded helper; alias tasks cache their result, including failure, until the session resets.
- [HomeViews.swift](../../../Sources/SevraApp/HomeViews.swift) and [ContentViews.swift](../../../Sources/SevraApp/ContentViews.swift): shared live app embedding, versus an ordinary asset component that only navigates to an item.
- [ConversationBlocks.swift](../../../Sources/SevraPreviewUI/ConversationBlocks.swift), [ConversationPresentation.swift](../../../Sources/SevraPreviewUI/ConversationPresentation.swift) and [ConversationViews.swift](../../../Sources/SevraApp/ConversationViews.swift): both parsed content enums have only text/table cases, and the native row switch renders only those cases. The current content cache uses message body identity, which must include typed payload identity when image results arrive.
- [WorkbookView.swift](../../../Sources/SevraApp/WorkbookView.swift) and [WorkspaceState.swift](../../../Sources/SevraApp/WorkspaceState.swift): file-URL drops call the existing capture/intake pipeline and append an Included/Linked source event. No bitmap-paste image attachment adapter was found in this path; the composer must keep its text/focus when that adapter is added.
- [Assets.swift](../../../Sources/SevraCore/Assets.swift), [AssetPreviewSession.swift](../../../Sources/SevraPreviewUI/AssetPreviewSession.swift), [MediaFiles.swift](../../../Sources/SevraPreviewUI/MediaFiles.swift), [ImageViewer.swift](../../../Sources/SevraPreviewUI/ImageViewer.swift), [Viewers.swift](../../../Sources/SevraApp/Viewers.swift) and [ImageDescription.swift](../../../Sources/SevraCore/ImageDescription.swift): included originals/hash metadata, optional byte verification, cancellable resolution, ImageIO thumbnails/orientation, shared zoom and explicitly human-authored description provenance. The native app image resolver validates binding/path/existence but does not itself hash the bytes it subsequently decodes. A safe path is not proof that changed bytes match the recorded source.

The existing [signed image check](../../../IntegrationTests/NativeApps/Checks.swift) constructs a known PNG, removes its external source, checks actual decoded dimensions, switches between image/symbol, refuses linked/undeclared sources and checks revocation. The later enlargement check covers its callback and symbol behavior. The original implementation's [[records/plans/programmable-native-engine]] records its native tests and UI observations. These records support their bounded mini-app scope; this review did not rerun them and does not extrapolate them to inline chat or standalone Home.

## Pass 2: useful complete image path

Revision 14 adds a concrete early P1-image increment rather than leaving all images bundled with diagrams in P4:

1. One typed exact item/asset reference and host-issued image receipt, distinct from query/aggregate results. Reuse the existing manifest, ordinary workbook ownership and exact app grants.
2. Actual image pixels in imported-file events and assistant answers; a standalone versioned Home image component; the existing mini-app image and shared zoom viewer. No new executable app just to show one picture.
3. File and explicit bitmap-paste capture through existing included-asset storage, preserving composer text, conversation target, duplicate protection and committed import receipts. Unsupported clipboard data has a useful refusal; no ambient clipboard reads.
4. Chat operations to show, pin, caption, replace, remove and inspect an exact image, through the visual operation envelope. Included-file display does not wait for successful OCR, a query engine or a vision-model call. No implicit remote-image download or linked-file inclusion.
5. One bounded media broker/helper/cache, with actual-byte identity, late-result rejection, source retry, orientation/alpha and original preservation. A detached task does not provide hard memory/time cancellation. Current ImageIO support is a foundation, not proof that proposed memory limits pass.
6. Captured historical images remain readable after app revocation while live app pixels/actions clear. Portable copies retain originals/references and never device grants. Missing/corrupt originals remain explicit; a thumbnail is not the only surviving evidence.

The pass also corrected the proposed source-dimension limit: 16 megapixels would unnecessarily exclude ordinary 24/48-megapixel phone images. The new 100-megapixel/32 MiB/maximum-side targets and single-job deadline remain measured acceptance gates, not claims of safe unbounded decoding. Existing PNG/JPEG/HEIC and additional ImageIO formats receive explicit format/first-frame coverage before advertising. No arbitrary SVG/HTML execution or animation/editor scope was added.

## Pass 3: integration and scope consistency

The enlargement follow-up landed during review. Revision 14 now reuses its shared ImageViewer instead of prescribing a second inspector. Moving decoding types to proposed SevraMedia and image presentation to VisualUI avoids a VisualUI/PreviewUI import cycle; existing native adapters keep authority. No product source was changed by this audit.

The complete plan was checked for all image/P4 references, component catalog, file map, runtime/agent integration, historic capture rules, stage table, acceptance matrix and completion checklist. Concrete corrections:

- P1-image consumes the common P0-chat result/event envelope; full question/needs-input continuation completion is not a necessary predecessor. It can ship independently of P0a, charts and diagrams.
- The visual operation envelope and image result branch are defined in P1-image; the chart spike extends them later. Read-only display/inspection remains separate from pin/configure writes.
- Basic image support is no longer described as P4 work. P4 retains diagrams and optional repeated record-thumbnail composition under the existing explicit binding limits.
- Captions are bounded visible presentation; accessible descriptions use supplied text, an exact stored annotation revision or a neutral filename fallback. Display success cannot become invented visual evidence.
- Explicit image paste does not intercept ordinary text paste in form fields. A failed decoder cannot silently escape its limits through an inline Quick Look or unbounded decode fallback.
- Six image scenarios have independent pixel/source/history/refusal oracles, text/control parity and actual-model source-selection checks. Native appearance, focus, scroll, cache/scheduler limits and common phone-photo sizes are mandatory acceptance work. No implementation boxes are checked by this planning review.

## Verdict and verification

The image increment is ready for implementation under its stated gates. Current source supports mini-app images and embedded-app images on Home; inline chat and standalone Home images are the actual missing surfaces. No app launch, installed-build claim, new model-vision capability or completed cross-surface image implementation is implied.

Documentation verification passed: `dbmd validate --all db --json` reports zero errors and warnings; `python3 scripts/check_links.py` passes; both JSON excerpts parse; the nine main sections, seven chat subsections, three image review passes, corrected capability inventory, independent image-stage ordering and selected contradiction checks pass; `git diff --check` passes. These are documentation checks only, not an executed image schema, runtime benchmark or cross-surface UI acceptance. Product tests and native UI work remain the implementation gates above.
