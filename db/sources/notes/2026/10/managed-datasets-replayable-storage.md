---
type: note
id: 01m61vcs1sp96hm8abekgng0t7
created: 2026-10-28T18:12:10.937609+00:00
updated: 2026-10-28T18:12:10.937609+00:00
summary: Owner adoption of managed native datasets aligned with existing replayable persistence; replication remains future work.
told_by: Carlos Galarza
---
# Managed datasets aligned with replayable persistence

Recorded October 28, 2026 from Carlos Galarza's design conversation.

## Owner statements

Carlos asked:

> ok, back to db structure. what is your best advice here? What is best? A managed schema with some reserved tables, or the shared way of doing things?

After discussing reserved system tables, native tables for structured datasets,
and shared history, he clarified:

> Is this aligned with the new thing? We've taken into account that everything here is prepared for synchronization. Check. Tell me if you know what I'm talking about. Like an event-sourced system that can then easily be done with replication

He then requested review against the recent replayable persistence changes and
adopted alignment of the design, documentation and main implementation agent:

> Are you sure? If you're sure align everything, align the main agent and the documentation towards what we want

## Discussion context

The recommendation adopted in this exchange is a managed SQLite schema with
reserved system tables, native current-state tables for structured datasets,
and shared immutable history and lineage. Spreadsheet sheets can contain mixed
cells, formulas, notes and multiple regions, so a worksheet is not automatically
one structured dataset. Agents request validated core operations rather than
write arbitrary SQL. The recommendation is an architectural choice, not a measured
speed claim.

The review identified the existing complete committed-change capture and inert
local reconstruction implementation. Managed tables must extend that same
foundation, including schema definitions and stable identities. The current
single-chain, physical-rowid replay is local evidence; concurrent replication and
semantic conflict resolution remain future work under the existing scoped
persistence requirement. This exchange does not authorize implementing cloud or
synchronization services.
