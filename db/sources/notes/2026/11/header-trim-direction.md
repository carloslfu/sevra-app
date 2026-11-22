---
type: note
id: 01m81whp21yafn5q23gj1shzpy
created: 2026-11-22T15:03:43.937791+00:00
updated: 2026-11-22T15:03:43.937791+00:00
summary: Carlos asks for the chat header at its minimum expression that still does the work, and says to trim it and run the light set once.
told_by: Carlos
---
# Owner asks for the chat header at its minimum, and has it trimmed

This continues [[sources/notes/2026/11/general-tools-only]] and [[sources/notes/2026/11/first-request-latency]].

On November 22, 2026 Carlos asked:

"How many tools does the agent have? and is there a way to reduce the context size? To its minimum expression that still does the work?"

The agent answered that chat is offered seven tools, that the prepared header was 5,172 tokens and a first prompt about 5,850, and that a smaller header would not make a turn faster, because the header is restored and not read. It listed five possible cuts with sizes estimated from the source text, and asked whether to trim the header and run the light set once. He answered:

"Yes, trim it"

## The agent's reading

- **The goal is the smallest header that still does the work, judged by the light set.** One run, as [[sources/notes/2026/11/light-testing-direction]] sets.
- **He approved the cuts as listed, on estimates.** Where a measurement showed an estimate or a premise was wrong, the agent followed the measurement and said so. What was cut, what was kept and why is in [[records/plans/general-chat-tools]].
- **This is not a word to push or release.** The header changed, so a source build needs the install command again.
