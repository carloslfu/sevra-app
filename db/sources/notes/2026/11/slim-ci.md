---
type: note
id: 01m7tpf0ezaanyfmmej0s83shw
created: 2026-11-19T20:02:43.807714+00:00
updated: 2026-11-19T20:02:43.807714+00:00
summary: 'Carlos has the app CI slimmed: one shared check list, a quick mode for every push and the full set for releases.'
told_by: Carlos
---
# Owner has the app CI slimmed

On November 19, 2026 Carlos asked:

"Check the CI for Sevra. Is it fast enough? Is it simple enough, or is it overengineering and overtesting? Check every single part of it."

The agent answered that it was none of those: one 41-minute job a push, about half of it compiling, with a hand-kept step list that had drifted from `scripts/check.sh` and left out the seven chat tools' own checks. It proposed one shared list with a quick mode for every push and a full mode for releases, cancelling older runs, building once, and keeping evidence only from a failed run. Asked "Should I slim the app CI as proposed?", Carlos answered:

"Yes, slim it"

## What the agent did with it

- `scripts/check.sh --quick` is what every main push and non-draft pull request runs: the records, links and brand, the app SDK, one build of every product, the core, interface, Splash, workflow-fixture, grammar and full default agent checks, `--sql-tool`, and the no-model `sql` and `run` chat checks.
- `scripts/check.sh` with no option adds the scale limits, crash recovery, search benchmark, signed authoring, the command-line journeys and the packaged app. Release tags and a manual dispatch run it on hosted CI after building the package.
- A newer push cancels an older run of the same branch. One results upload happens only when a run fails.
- The separate `--conversation-surfaces` run was dropped because the default agent run already includes it.

## The agent's reading

- The proposal's optional build cache was left out to keep the change simple.
- The CI run for the seven-tools commit had hung in the product checks until its two-hour timeout, because a synthetic model there still called `save_space`. That fix ships with this change.
