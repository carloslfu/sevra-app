---
type: note
id: 01m7r5pw5bmhcqyn3v621ehzjq
created: 2026-11-18T20:31:26.891653+00:00
updated: 2026-11-18T20:31:26.891653+00:00
summary: 'Owner chooses a fast test loop for the general chat tools: thin slice first, English single-run evals while building, full gate twice.'
told_by: Carlos
---
# Owner chooses a fast test loop for the general chat tools

This continues [[sources/notes/2026/11/general-tools-implementation]].

On November 18, 2026, while phase 1 of [[records/plans/general-chat-tools]] was recording its baseline, Carlos asked why it was taking so long and whether there was overtesting or over-engineering. He wrote: "We want to iterate fast on this. We want to make the system simple enough, have enough tests and [evals], but be able to iterate super fast on it."

The agent measured the baseline and reported: 45 minutes for 23 of 46 runs, and of the first 22 runs' 2,550 seconds, 1,408 went to rerunning jobs that had already failed. It proposed a faster loop. Carlos answered "Yes, switch", and then: "Yes, prefer a faster loop so we can iterate on it fast, and I can receive feedback fast."

## What he approved

This is the proposal as it was put to him.

- **A thin slice first.** Build `sql`, reading and writing, and `finish` end to end in rough form. Run the evals. Then add guards where the evals show they are needed.
- **Three levels of test.** Unit checks with no model. An eval in English, one run per job, only the jobs the change touches. The full gate, with both languages, reruns, the timed turns and the full suite, only before the old tools are removed and at the end.
- **The baseline.** Stop it after the job in flight, keep what it recorded, and run the remaining groups once in English.
- **The header.** Run only the resume probe now. The rest waits until the tools work.
- **The plan.** Replace the gate rule and reorder the phases in one short edit, with no more review passes.

He was told the cost: a single English run can miss flaky behavior and Spanish regressions until the full gate.

## The agent's reading

- He wants results reported back often and briefly, not held until a phase ends.
- "Simple enough" is a standing preference for this work: build the smallest form that works, and add machinery when a check or an eval shows the need.
- Nothing here changes what the earlier authorization does not cover.
