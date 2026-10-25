---
type: operational
meta-type: conclusion
id: 01m5rbxzcsjnewm0pwmb9a06cj
created: 2026-10-25T01:48:47.385772+00:00
updated: 2026-10-25T03:05:15.036022+00:00
summary: Ordered work and honest requirement status for the first Sevra release.
title: Implementation and acceptance
---
# Implementation and acceptance

This is a working development build, not a qualified release. Requirements in the
specifications remain the acceptance contract. A source commit does not imply that
every requirement or supported hardware profile has passed.

## Implemented

- Native SwiftUI/AppKit document windows with conversation and workspace panes,
  searchable spaces, Home, recent workbooks, native viewers and model settings.
- Shared Swift core and JSON CLI; SQLite metadata, immutable external asset files
  inside the package, SHA-256 verification, explicit external links and ZIP64 export.
- Sources/Records, immutable revisions and lineage, separate meaning and acceptance,
  unique event effects, deterministic inventory replay, corrections and undo.
- CSV and XLSX saved-value intake, typed edits, atomic multi-row paste, undo/redo,
  formulas with decimal arithmetic, lazy IF, ROUND, cell/range references, cycle
  errors, column history, unit labels and coherent snapshot CSV export.
- Resumable 1,000-row structured intake batches with idempotent retry. Original files
  remain intact. Native PDF text, Vision OCR, text/DOCX extraction and explicit
  unsupported/partial states. Checksums and bounded cooperative processing.
- FTS5 chunks, Unicode lexical and trigram filename indexes, metadata filters,
  current/historical search, source deduplication and revision-bound cursors.
  Native paging/facets are implemented but still require interaction qualification.
- Versioned native table, bar/line chart, metric, document, asset, search, text and
  comparison components. Live bindings and pinned copies with exact values/input
  versions. Charts disclose excluded/partial rows. Pinned tables and metrics are
  bounded to 1,000 rows and refuse misleading partial aggregation.
- Main conversation, chapters, saved exchanges, parent-linked tangents, evidence
  locators, draft autosave, optional continued playback and linked-file recovery.
- Native Slotstream Fast integration at the pinned public revision, model setup,
  typed tools, bounded agent turns, persisted traces/run metrics, citation checks
  and idempotent agent mutations. Real inference has run; full eval is pending.
- On-device dictation code. Actual microphone recognition remains unqualified.
- App/CLI bundling, verified Metal kernels, dependency notices, ad-hoc signing,
  user-local install/update/uninstall and optional Codex/Claude Code skill installer.

## Verification checkpoint, October 24 local / October 25 UTC, 2026

40 executable core checks pass. They cover lineage, actual/estimate separation,
acceptance/withdrawal, unique effects, stale revisions, immutable imports, changed
and missing links, cancellation, quoted CSV, atomic editing/undo, spaces,
conversations, XLSX, index recovery, unsafe paths/schema/archives, lazy formulas,
precision, cursors, search cancellation/deadline cleanup, pin retry identity, deterministic percentages, CSV snapshots, live versus pinned
values, type/history checks, resumed intake and real PDF text/image OCR locators.

Packaged-binary checks also pass:

- Isolated install, update, standalone CLI, demo, verification and uninstall,
  preservation of workbooks and refusal to replace an unrelated CLI.
- Thirty concurrent CLI writers, cross-process structured-intake retry, idempotent retry, stale-write refusal and coherent
  export/reopen with preserved inventory and asset verification.
- Loopback HTTP fixture: capture through redirect, indexed content, refusal of a
  redirect loop, explicit access failure, non-HTTP refusal and origin-token redaction.
- A 4,296,015,872-byte synthetic asset: include, remove original, verify, ZIP64
  export, reopen and verify. Archive size 4,296,022,031 bytes; peak process RSS
  39,141,376 bytes after the buffer-lifetime fix. Synthetic sparse bytes are not a
  real-video playback or storage-throughput benchmark.

## Model and scale findings

A real local model answered the example stock question with valid citations.
Initial generated-view attempts failed on missing chart bindings. Native typed
tools produced a valid table/chart, but that answer invented currency and used an
incorrect percentage denominator. Deterministic comparison and answer checks are
implemented; the corrected run is pending because another Slotstream process owns
inference. Do not mark J02 complete or claim general factual reliability.

At 100,000 rows, initial broad-query warm p95 was about 589 ms. Derived index
metadata reduced a later run to about 220 ms; the 200 ms target remains unqualified.
Exact identifier lookups were below 1 ms. New-connection numbers are not OS-cold
measurements. Runs overlapping inference are not performance qualification.

## Remaining work

1. Native end-to-end interaction: cell editing/paste/undo, Finder opening, search
   paging/Back/facets, chapters/tangents, draft autosave, pinned/comparison views,
   locators, media, dictation, narrow windows, appearance and keyboard/VoiceOver.
   The Mac is currently locked; computer use needs the owner to unlock it.
2. Corrected real-model comparison/view creation, adversarial evidence, no-match
   honesty, cancellation/recovery and measured whole-task latency.
3. Search scale/recall with many chunks per document; further broad-query optimization and cancellation during actual long-running searches.
4. Remaining extraction crash/isolation tests, timestamped on-device media
   transcription capability handling, failed-URL reference recovery and explicit
   archive-member intake. Parser deadlines are cooperative, not process isolation.
5. Complete text/voice workflow coverage, review agent tools against user authority,
   and qualify formula/units behavior. Units are labels, not automatic conversion.
6. Fresh public clone/build, resource isolation, real user installation, harness
   skill installation, CI and a properly labeled public release package.

## Completion rule

J01–J09 in [[records/specs/product]] require recorded outcomes, not inferred
success. Keep this register current. Do not label the whole app or full
specification complete while required work remains.
