---
type: note
id: 01m5remrm06r2d6f2bw17kxnhv
created: 2026-10-25T02:36:11.264492+00:00
updated: 2026-10-25T02:36:11.264492+00:00
summary: Owner-approved Sevra product direction, public independent repository, full specification, implementation and end-to-end verification request.
told_by: Carlos Galarza
---
# Owner's requested product and build

Carlos requested an independent open-source Sevra app repository, a deeply
reviewed specification, a working first native version, polished installation
instructions and end-to-end verification. The project must own a complete,
independent db.md store containing its design, goals, research and work records.

The adopted product direction is a workbook for gathering information, reasoning
about it, calculating and presenting results. It uses local AI and a native
Swift/SwiftUI/AppKit interface, with Slotstream as the inference engine. The engine
version should be chosen from the latest suitable release during implementation
rather than frozen by an earlier brainstorming model name.

Interaction centers on one evolving text/voice conversation and a workspace pane.
Spaces are saved native compositions; temporary document/media exploration should
not create unnecessary spaces. Chapters, tangents and saved exchanges preserve
continuity. Generated interfaces should compose native components safely.

Sources hold original inputs of many kinds. Records hold interpretations and
derivations. History, lineage, accepted business events, deterministic rules and
separate meaning/acceptance make results explainable. Assets are ordinary files
outside SQLite but inside the workbook by default. Explicit links are possible.

Search must be agentic over real indexes, including FTS and filename/structured
indexes, and must scale without loading every document into model context. A CLI
and harness skill should expose the same workbook behavior to external agents.

This note records the owner's instructions from the project conversation on
October 24, 2026. Specific schemas, limits and implementation choices in the
specifications are engineering decisions derived from that direction.
