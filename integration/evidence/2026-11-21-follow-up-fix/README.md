# Follow-up fix, November 21, 2026

`conversation.follow_up` failed in [the first run of the new jobs](../2026-11-21-new-jobs/README.md):
on "Change its quantity to 20." the model took "its" as the brass bolts of the stock list instead
of Cedar Tools from the turn before. Earlier turns reached it labelled only as historical
information. The saved conversation now also says that the current request may refer back to
it (`historyReferenceNote` in `Sources/SevraAI/ContextMaintenance.swift`). The sentence follows the
prepared header, which is unchanged.

One run with the real model on the rebuilt release CLI: the follow-up job and the eleven light
jobs, because the saved conversation reaches every turn. 12 of 12 passed on the first run, in 36
decisions, 36 model calls and 270 seconds.

- `conversation.follow_up`: passed in 7 decisions over its two turns. The answer: Cedar Tools
  quantity 20, total 55. Oak Supply unchanged.
- The light set: 11 of 11 in 29 decisions and 216 seconds. On November 20 it took 31 decisions
  and 259 seconds.

Checked first without the model: `sevra-agent-checks --conversation-latency-checks` (the saved
conversation appends across turns), `--prompt-header-checks`, `--conversation-surfaces` and
`--chat-checks` pass.

`workingTreeChanges` in `results.json` lists an unrelated `SevraApp.swift` change in the working
tree. It is app interface code and is not part of the CLI that ran these jobs.
