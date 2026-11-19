---
type: note
id: 01m7tahq7tf11wsr2vn1evzprz
created: 2026-11-19T16:34:29.754968+00:00
updated: 2026-11-19T16:34:29.754968+00:00
summary: Carlos makes the seven tools the only chat tools and asks to remove the old way, with no backward compatibility.
told_by: Carlos
---
# Owner makes the seven tools the only chat tools

This continues [[sources/notes/2026/11/general-tools-in-the-app]].

On November 19, 2026, after the agent explained that the seven tools were not yet the default in the code, Carlos wrote:

"No, we want the new tools. Make them the default and remove the old way. We want the new way. Remove any package, any other stuff from the old way. We don't need backwards compatibility or to have the other way. We only need this way. This is the new way."

## What the agent did with it

- Removed the tool profile and its settings: `SEVRA_TOOL_PROFILE`, the app's `SevraToolProfile` setting and the `current` profile. Every chat request is offered the seven tools.
- Removed the old chat instructions, the old-only tools `compare_rows`, `propose_table` and `propose_table_edit`, the unused text tool guide in the core, the profile's byte-identity check and fixture, and two probes that only exercised the removed tools.
- Moved the agent checks, the grammar checks and the model-job harness to the seven tools.

## The agent's reading

- "The old way" was read as the old chat tools and everything that kept them selectable. Reviews and Excel conversion have tool lists of their own that are not chat; they stay, and so do the operations the seven tools route to.
- A separate session removed the Slotstream baseline package at the same time. That work is its own and is not described here.
- "Remove any package" was not read as permission to push or publish.
