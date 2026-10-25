---
type: research
meta-type: conclusion
id: 01m5rbxzbx5q4atmjp4471w04d
created: 2026-10-25T01:48:47.357164+00:00
updated: 2026-10-25T02:59:23.416227+00:00
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
