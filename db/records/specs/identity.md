---
type: spec
id: 01m5wv7836pwvthpfcpa39g0hq
created: 2026-10-26T19:32:57.574249+00:00
updated: 2026-10-26T19:32:57.574249+00:00
summary: Approved Observer zebra, exact original Mac icon, native outlined wordmark and restrained light/dark placement.
title: Sevra workbook visual identity
status: reviewed
---
# Sevra workbook identity

B01. Reuse the approved Observer zebra and lighter lowercase sevra wordmark.
This is the same identity as the Sevra website and the historical Sevra-named
Mac app. Do not substitute the earlier striped S or current Slotstream icon.
Owner authority: [[sources/notes/2026/10/observer-workbook-identity]].

B02. Resources/Sevra.icns is the original Mac app icon, unchanged. Declare it
with CFBundleIconFile, copy it into Contents/Resources before signing, and keep
it present through install and update. The standard macOS About panel uses it.
Finder/Dock cache refresh is not an excuse to change the approved geometry.

B03. The welcome screen shows the mark and outlined wordmark. A small mark in
the workbook header identifies the app while the workbook title remains primary.
Avoid logos beside every message, on every document or over user-owned content.
No new navigation or branding controls are required.

B04. Native vector paths preserve the checked-in SVG geometry and clear space.
Use semantic primary color in the app so the same shapes remain readable in
Light, Dark and System. The icon retains its original sumi (#141414) zebra on
warm off-white (#f4f3ee). Body and control text use native system typography.
The wordmark outlines come from Poppins Medium 500, tracking -0.025em; they do
not require a font download or runtime font registration. Retain its OFL notice.
The welcome lockup has one accessible Sevra label; the adjacent header mark is
decorative because the workbook title and app name already supply context.

## Self-contained assets and provenance

Resources/Brand/sevra-mark.svg SHA-256:
`66c4c382bb39a74c6ffa247bc5e9530741e60e6d066a6b8647e981eb70e0ef3b`.
Resources/Brand/sevra-wordmark.svg SHA-256:
`c1f8b3f425667ad5cc753e3cb8868629beea79edb853d2607bd13fa5e0541fb4`.
Both preserve the existing website source vectors, whose asset revision was
`2f74546605cc4d512817b09c14639acb606529a5`. No website checkout is required.

Resources/Sevra.icns SHA-256:
`b28f2df8e40cafc2e89fb3ae5a0e361b5470851d833495df9b3dd4ca0395471d`.
Imported from the public Slotstream history at commit
`848025db92ea8fe105651b6928d40194cfaa89d8`, path
apps/macos/Resources/Sevra.icns. That repository is a reference, not modified.

scripts/generate_brand.py deterministically translates the two local SVG files
into Sources/SevraApp/BrandShapes.swift. Its restricted primitive set is intentional;
unsupported geometry fails rather than silently changing the mark. Run with
--check during builds. The generated shapes need only SwiftUI, not a webview,
SVG parser or font runtime. Source artwork remains editable in this repository.

## Verification

The installer check verifies the icon declaration and exact installed digest.
Native UI qualification checks welcome/header/standard About rendering in Light
and Dark, with System restored afterward. This preserves the existing ICNS
format; a layered Icon Composer redesign has not been requested or qualified.

See [[records/specs/product]] and [[records/operations/implementation]].
