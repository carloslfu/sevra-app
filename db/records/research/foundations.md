---
type: research
meta-type: conclusion
id: 01m5rbxzbx5q4atmjp4471w04d
created: 2026-10-25T01:48:47.357164+00:00
updated: 2026-10-27T16:50:00.231319+00:00
summary: Primary sources for SQLite retrieval/durability, native readers, on-device voice and current Slotstream integration.
title: Foundation research
---
# Research, October 24, 2026

This is an engineering synthesis, not copied documentation. The local public
Slotstream source and current primary references were inspected before design.

- [SQLite FTS5](https://sqlite.org/fts5.html): lexical indexing, Unicode tokenizer,
prefix/trigram modes, BM25/snippets, external-content triggers and rebuilds.
Inference: use separate typed filters and filename/content ranking; an LLM loop
adds query refinement, not the index itself. Keep search directly accessible.
- [SQLite WAL](https://sqlite.org/wal.html): same-host shared memory requirement,
checkpoint behavior and published WAL-reset advisory. Inference: serialize writes
and initially use FULL rollback journal with the system library; benchmark before
introducing WAL, verify fixed SQLite if adopting it.
- [SQLite backup API](https://sqlite.org/backup.html): coherent live database copy.
Inference: snapshot database first, then copy its referenced immutable assets.
- [Apple PDFKit](https://developer.apple.com/documentation/pdfkit): native PDF
reading and page/text interfaces. OCR is a separate operation, not guaranteed PDF text.
- [Vision text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images): local OCR surface. Preserve page/region and actual coverage.
- [On-device speech](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition): require on-device recognition and capability checks.
- [NSDocument](https://developer.apple.com/documentation/appkit/nsdocument): native
file lifecycle and document behavior. Large packages need coordinated persistence;
do not serialize gigabytes into an in-memory FileWrapper on each edit.
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation): Swift archive library
with large-file support and bounded-memory APIs. Our own path/decompression bounds
and complete snapshot verification remain required.
- [Slotstream](https://github.com/carloslfu/slotstream): MIT, native Swift package,
public Engine, ModelPack and versioned deployment APIs. Local and remote main both
resolved to 7578fb21e57ec362d19f5050922e0f583914935d at research time. Fast pack
includes Qwen3.6-35B-A3B and DFlash2. Current main is newer than v0.2.30; pin commit,
exercise actual library API, package the matching MLX metallib and qualify locally.

## Open evidence

Speech language availability, actual model tool reliability, file-format coverage,
search corpus latency and app memory remain measurements to collect. An API's
existence does not establish that a complete UX works. The reference machine is
Apple Silicon with 48 GiB unified memory; published results must record chip and OS.

## Native cancellation follow-up

Apple documents [VNRequest.cancel()](https://developer.apple.com/documentation/vision/vnrequest/cancel%28%29)
as cancellation before a request completes. Sevra monitors cancellation and its
processing deadline during Vision OCR. Other parser deadlines are cooperative at
bounded stages; an in-process PDFKit call is not a hard process-isolation boundary.

## Splash integration review, October 26

[Splash 1.4.1](https://github.com/incoai/splash/releases/tag/1.4.1) at
`1744cfafee415fb463b289449cec59a864e768e9` is the initial reviewed candidate.
The [Makefile](https://github.com/incoai/splash/blob/1.4.1/Makefile) builds
`libsplash.a` and a native engine. Its [entry point](https://github.com/incoai/splash/blob/1.4.1/runtime/main.mm)
offers `serve-native` through pipes; [protocol v11](https://github.com/incoai/splash/blob/1.4.1/runtime/engine/Protocol.hpp)
carries token IDs, requests, cancellation, masks and terminal results.
The [Python frontend](https://github.com/incoai/splash/blob/1.4.1/server/frontend.py)
and [constraints](https://github.com/incoai/splash/blob/1.4.1/server/constraints.py)
show that tokenization/templates, output parsing and grammar masks need equivalents.
The [local installer](https://github.com/incoai/splash/blob/1.4.1/install/local.py)
documents that prepared layout is private to a release. Pin and compare it.

[Swift C++ interoperability](https://www.swift.org/documentation/cxx-interop/)
supports a bridge, but an existing native helper initially minimizes lifecycle
changes. This is an engineering choice, not measured superiority. The native
core uses custom Metal; a model's MLX file format does not require MLX execution.

Apple file transcription checks both on-device recognition support and
requiresOnDeviceRecognition. The development implementation limits inputs to
60 seconds and publishes timestamped chunks only after final success.
[Capability](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition),
[request](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition).

## Pinned engine numerical and cache conditions
Pinned Splash 1.4.1 documents that numerical results depend on prefill chunking and the rows computed together. Even with verify-rows all, matching output requires matching cached prefixes, and cached KV can be substituted after a request begins even when its initial cache hit is zero. The initial matched-prefix count therefore is not a complete cache identity. A unique cache salt prevents sharing with other requests but does not remove all chunking differences when memory limits state capture. This is upstream's stated execution model, not proof of the cause of Sevra's observed divergence.

Primary source: [pinned sampling documentation](https://github.com/incoai/splash/blob/1744cfafee415fb463b289449cec59a864e768e9/DEVELOPMENT.md#sampling). Local source SHA256: cb7a903da01bc3cdb73783e2b50072dba8c0660c3c902380732e37f6cd63dd52. Its state-precision section says the default recurrent state is FP32; do not attribute this run to optional BF16 state rounding. The runtime Done response reports deduplicated KV tokens separately from Start's matched-prefix count; preserve both in native and reference receipts.

Sevra's controlled reference diagnostic reproduced two different successful answers at an identical request frame with a 2 ms wait before returning each upstream-produced mask. The delay wrapper does not modify that buffer; this does not prove that every mask across the two complete live runs was identical. The no-tracing control also matched native in this later run, so the earlier tracing-on/off association was not a sufficient causal explanation. Do not call this an adapter or engine bug, waive an acceptance gate, or add a delay to the product on that evidence alone. See [[records/specs/splash-integration]] and [[records/operations/implementation]].

## Search snippet cursor reuse
SQLite documents unary + as a way to prevent a WHERE term from driving index
selection: https://www.sqlite.org/optoverview.html#disqualifying_where_clause_terms_using_unary_
Its FTS5 reference describes MATCH-context snippets: https://www.sqlite.org/fts5.html#the_snippet_function
Local profiling on the retained synthetic 100k corpus found repeated snippet
cursor initialization expensive. Range-bounded membership filtering reused a
cursor while producing identical excerpts in the focused checks. This is a local
query-plan observation, not a general SQLite or whole-app speed claim.
