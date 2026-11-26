---
type: note
id: 01m8b2be9yknspf8w01edqwpgg
created: 2026-11-26T04:38:20.733900+00:00
updated: 2026-11-26T04:38:20.733900+00:00
summary: Carlos asks for the CLI skill and command line to follow the seven tools, judged from first principles and product taste.
told_by: Carlos
---
# Owner asks for the CLI skill to follow the seven tools

On November 25, 2026, Carlos relayed a claim he had heard: "The agent skill is 49 KB. Most of it documents the older workflow and ledger machinery, and no outside agent will use that well. The CLI should mirror the seven tools." The agent measured it: the skill was 45,719 bytes, about 90% of it the workflow, action, form, automation and definition commands, and the CLI already ran five of the seven tools through `sevra tool`. Carlos then wrote:

"Analyze this from first principles and based on the best UX taste and product taste, and do whatever you need to do."

## The agent's reading

- An outside agent should work a workbook the way the app's model does, so the skill teaches the tools and leaves the long command list to `sevra help all`. Guides and the action list are read on demand through `read`, as the app's model reads them.
- `ask` and `finish` are how the app's model talks to the person in a chat turn. An outside agent talks to its own user, so the command line refuses them with a clear message instead of mirroring them.
- The lower-level commands stay. Removing them is a separate decision, and tests and scripts use them.
- This was not read as permission to push.
