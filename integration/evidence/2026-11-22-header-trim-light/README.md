# Header trim, November 22, 2026

The prepared chat header went from 5,172 to 3,809 tokens. What was cut and what was kept is in
the general chat tools plan, under "The build so far".

Counted without the model, with `sevra-agent-checks --header-parts`, which loads only the
tokenizer: [before](header-parts-before.json) and [after](header-parts-after.json).

| Part | Before | After |
| --- | ---: | ---: |
| Whole header | 5,172 | 3,809 |
| Instructions | 1,148 | 701 |
| `save` | 1,762 | 875 |
| `ask` | 555 | 555 |
| `run` | 516 | 500 |
| `read` | 343 | 359 |
| `sql` | 267 | 238 |
| `finish` | 237 | 237 |
| `search` | 143 | 143 |
| Template framing of the tools | 197 | 197 |

One run with the real model on the rebuilt release CLI, the light set: 11 of 11 passed on the
first run, in 29 decisions and 215 seconds. The same eleven took 29 decisions and 216 seconds on
November 21. A first prompt is about 4,500 tokens, from about 5,870. `build.view` passed in 4
decisions and did not read the new view guide.

Two jobs by name, because their text moved, one run each:
[the run](../2026-11-22-header-trim-named/results.json). `build.saved_tool` passed in 2
decisions. `build.rule` passed in 4 and read the rule guide first.

Not run: `build.app` and `build.form`.

Checked first without the model: `sevra-agent-checks --prompt-header-checks`, `--chat-checks`,
`--conversation-surfaces`, `--space-action-checks` and `--sql-tool`, the default scripted
groups, `scripts/check_splash_grammar.py`, `scripts/check_chat_sql.py`,
`scripts/check_chat_run.py` and `scripts/check_chat_jobs.py --self-test` pass.

`workingTreeChanges` in `results.json` also lists `ConversationViewState.swift` and
`ConversationSession.swift`. They are other work in progress in the same checkout, on how the
app shows a conversation, and are not part of this change.
