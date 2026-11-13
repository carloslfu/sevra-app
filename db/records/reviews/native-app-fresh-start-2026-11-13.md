---
type: review
meta-type: conclusion
id: 01m7at4vwrjmkj1cbb497pgrgt
created: 2026-11-13T15:59:14.840580+00:00
updated: 2026-11-13T15:59:14.840580+00:00
summary: Fresh mini-app test state retired; 28 focused groups and imported-app UI pass, but both new local-model calculator attempts fail.
title: Fresh native-app baseline, November 13
---
# Fresh native-app baseline, November 13

## Scope and outcome

The owner clarified that there are no existing mini-app customers to migrate, then approved a clean current implementation. [[sources/notes/2026/11/mini-app-fresh-start]] is the authority. The selected obsolete development workbooks, packages, approvals and recent entries are removed. No compatibility adapter or migration was added. The native-app product already uses one current contract; this checkpoint changes test cleanup and documentation, not runtime behavior.

The fresh canonical-package path works. A new actual-model calculator request and its guided follow-up both failed safely. **The cleanup is complete; reliable chat creation for this request is not.** These results must not be combined into an unqualified authoring-success claim.

## Cleanup and regression protection

- Removed the owned mini-app engine, authoring and adversarial workbooks/bundles, including the seven old live-model fixture directories' workbook/package contents. Retained historical logs, receipts and evidence.
- Removed 20 obsolete native-app approvals (18 boolean and two generation strings), three matching recent entries, 56 empty synthetic test preference files and obsolete native-check temporary workbooks. Preserved other preferences, unrelated workbooks/recents, canonical examples, model files and the older baseline app.
- The native check executable previously called `exit` before its temporary-root `defer` could execute. Its async runner now returns its status before process exit. Synthetic preference domains also clean up when checks return.
- Both Python check runners use unique temporary app bundle directories and clean them after success or ordinary failure/timeout. The live probe's explicit output remains separately retained as evidence. Success plus intentionally missing-binary failure paths left no temporary host bundle.
- The native XPC inventory check now proves a new app has no grant, access, rendered tree or business rows before approval, then retains the existing enabled data/reactivity/restart checks.

## Verification

`swift build --product sevra-native-app-checks -j 4` and `python3 scripts/check_native_apps.py` pass all **17 native groups**. `python3 scripts/check_native_app_authoring.py` passes **11 authoring groups**. Strict Swift formatting, Python compilation and whitespace checks pass. The unchanged full product suite and package/signature proof from [[records/reviews/native-app-adversarial-review-2026-11-13]] are reused under the focused verification policy; no new full-suite or universal correctness claim is made.

Installed main UUID `C1206D73-F023-3CB9-8A3B-C052F9A93B38` matches the packaged candidate. In a new empty workbook, ordinary Add Native App imported the canonical Inventory package. The access review named the real Stock table and remained inert until Enable. Native controls passed empty-name refusal, saving synthetic Test bolts with quantity 3, reactive count/row presentation and Undo back to zero. The permission layout, field labels, row centering and normal/narrow window spacing were inspected. CLI independently confirmed no rows after Undo and clean workbook integrity.

After recording evidence, the final synthetic workbook, its single approval and recent entry were removed. Sevra is on Welcome with unrelated recents preserved. No old mini-app acceptance workbook is left open. No VoiceOver or system setting was changed.

## Actual-model failure retained

The initial request asked for a two-input Fresh calculator, exact decimal multiplication and invalid-input feedback. It stopped at the step limit after 4m37s: repeated extra closing parentheses, a trailing-zero expectation (`17.50` versus actual `17.5`), an incorrect error substring, then invented update IDs before any app existed. The host refused every invalid save. Source-line feedback and SDK guidance were present.

A guided follow-up explicitly requested the native tool, simpler composition, correct decimal/error expectations and creation without update IDs. It stopped after 1m47s, having read the stopped request and repeatedly selected the fixed `save_space` tool, which refused missing item bindings. No calculator or other space was saved. Workbook integrity passed. No replacement source was hand-authored or presented as model success.

This broadens the prior reliability limit: even a fresh focused request can fail, and a technical follow-up need not recover. The successful imported example qualifies the runtime/approval path only. Further local-model authoring/recovery work remains open; no inference or prompt behavior changed in this cleanup checkpoint.

The [synthetic evidence receipt](../../../integration/evidence/2026-11-13-native-app-fresh-start.json) records outcomes, changed-file hashes, local evidence hashes and preserved limits. Production signing, external security assessment and other hardware qualification remain outside this checkpoint.
