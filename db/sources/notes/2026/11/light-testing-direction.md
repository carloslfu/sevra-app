---
type: note
id: 01m7t22xnad65zm2xyp1yedbmc
created: 2026-11-19T14:06:36.202933+00:00
updated: 2026-11-19T14:06:36.202933+00:00
summary: 'Carlos stops the overtesting: this app is tested in English, and model tests cover happy paths and edge cases in minutes.'
told_by: Carlos
---
# Owner stops the overtesting: English only, and model tests that take minutes

This continues [[sources/notes/2026/11/general-tools-in-the-app]] and sharpens [[sources/notes/2026/11/fast-loop-direction]].

On November 19, 2026, after the agent reported results for [[records/plans/general-chat-tools]] in English and in Spanish, Carlos wrote:

"Why did you mention Spanish? This is only English. Why are you testing with Spanish? We don't care about Spanish."

The agent reviewed the records and told him that he had never asked for Spanish. The agent had written "in English and Spanish" into the plan's job list and gate itself, copying a habit from earlier agent-written checks. It had cost about an hour of model runs.

He then wrote:

"And also, the model runs shouldn't be that many. They should just test edge cases and the happy paths. We want the lightweight thing that doesn't take an hour to test, even the English ones."

The agent proposed about ten model jobs in English, one run each, three to four minutes, with the mechanics left to the checks that need no model. He answered:

"Yes, do that, do the Spanish thing, and put notes on the agentsMD or ClaudeMD, whatever. Tell which one we are using here, which one is the main one, and be sure this never happens again: that we don't overtest."

## What changed

- The model test harness is English only. Its routine run is a light set of eleven jobs, one run each, measured at 3 minutes 51 seconds. It has no reruns, and it refuses a run of more than twelve jobs without his word.
- The plan's test section was rewritten around that, and Spanish was taken out of its gates.
- `AGENTS.md` has a testing rule.

## The agent's reading

- **English only applies to this app's tests.** He was not asked about the Spanish phrase lists and Spanish checks that older work left in the code, and they were not touched.
- **"Never again" is a standing rule, not a one-time cleanup.** An agent may not add a language, a rerun, a repeated timing or a larger job set to testing without his word, and a plan may not set a heavier gate than the rule in `AGENTS.md`.
- **Light does not mean untested.** The checks that need no model stay and run on every change.
