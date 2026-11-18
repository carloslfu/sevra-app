---
type: note
id: 01m7rgczazk4jsn83564586cyn
created: 2026-11-18T23:38:16.799625+00:00
updated: 2026-11-18T23:38:16.799625+00:00
summary: 'Owner''s four answers after the first sql slice: agent decides the DB.md DDL line, format changes need no compatibility, header paused, 15-digit numbers kept.'
told_by: Carlos
---
# Owner's answers on the general chat tools, after the first slice

This continues [[sources/notes/2026/11/fast-loop-direction]].

On November 18, 2026, after the first slice of `sql` passed its English evals and the header probe was measured, the agent put four decisions from [[records/plans/general-chat-tools]] to Carlos. His answers, in his words where he wrote his own:

1. **The rule against raw-model DDL in `db/DB.md`.** Asked whether the agent should edit the line, he would, or the rule should stay, he wrote: "Do whatever makes sense to do here. Do your best."
2. **Workbooks made by earlier development builds,** which stop opening when the workbook format changes for saved tools. He wrote: "This hasn't been released, so backwards compatibility is not a problem. Just ship stuff."
3. **The header work,** after the probe measured today's header at 131.5 MB on disk for a saving of about 2.6 seconds per engine start. He chose: pause until the tools are done.
4. **Numbers in `sql`.** He chose to keep rounding to 15 significant digits, not the exact side table.

## The agent's reading

- **`db/DB.md`.** He left the choice to the agent. The agent changes that one line, so model SQL may change a table's shape only on the scratch copy, applied through the recorded write path. Nothing else in that file is the agent's to edit.
- **Format changes.** The plan's wait before phase 5 is lifted. Format changes for this plan need no compatibility work and no further question.
- **Header.** Phases H2 to H4 and the rest of H1 wait until the general tools pass their gate. P6 to P9 stay unanswered until then. The size is measured again on the final header before he decides.
- **Numbers.** The exact side table in the plan's design is not built unless a check or an eval shows a need.
