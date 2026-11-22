---
type: note
id: 01m80gbgbdkhqck4y5rkzgx3pz
created: 2026-11-22T02:11:24.141818+00:00
updated: 2026-11-22T02:11:28.090781+00:00
summary: Carlos asks for chat evals good enough to swap models and check accuracy, without over-engineering or over-testing.
told_by: Carlos
---
# Owner asks for evals that can compare models

This continues [[sources/notes/2026/11/light-testing-direction]] for [[records/plans/general-chat-tools]].

On November 21, 2026, Carlos asked:

"Do we have a set of evals for everything that the model needs to do here, so we can swap models and check accuracy?"

The agent answered that the chat jobs in `scripts/check_chat_jobs.py` were the evals, with 25 jobs graded against fixed results, and that the build pins one model pack. He then asked whether they were enough, "Be super practical." The agent's view was that they catch a clearly worse model but cannot tell two good ones apart: every workbook held 2 to 6 rows, every job was one turn, an answer passed when the right number appeared anywhere in it, and there was one injection, a blunt one. He answered:

"Yes, improve the evals and test them. Give it a few passes to be sure we're not over-engineering or over-testing, but these are actually evaluating valuable stuff."

## What this asks for

- Jobs and graders that catch the failures most likely when the model changes, each worth its run.
- Testing as the light-testing direction sets it: the checks that need no model first, then one run of the new jobs.
- It does not ask for a model switch, a new model, or a change to the light set.
