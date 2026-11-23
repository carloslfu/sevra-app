---
type: note
id: 01m82yhmn1dekjzqftbm4yg3zg
created: 2026-11-23T00:57:54.080961+00:00
updated: 2026-11-23T00:57:54.080961+00:00
summary: Carlos asks for Local AI to start when the window opens and for a sent message, its progress and any failure to show in the chat at once.
told_by: Carlos
---
# Owner asks for Local AI to start with the window and for a sent message to show at once

On November 22, 2026, Carlos reported that right after opening Sevra, typing a message showed "Preparing local AI" and nothing else, and that the state was intermittent and happened only when the app was recently opened. He asked for every code path to be checked.

After the cause was explained, he asked whether preparing the AI should happen when the window opens: "It should be loaded when the window is loaded, don't you think? Or what is the best UX here?"

He then added: "I think the behavior is that immediately I should see the message I sent, the user message, and whatever is happening or is reporting should be said there and should be shown there."

He closed with: "Okay, make all of that happen and test that it works."

## The agent's reading

- **Local AI starts when the first window opens,** and again when Sevra comes back to the front after the idle release, if the model is installed and the Mac can hold it with memory to spare.
- **A sent message appears in its chat at once,** before the model is ready.
- **Everything about it is reported under it:** the start's progress, the reasoning, the reply and any failure, not in the bar at the bottom of the window.
- **Stop ends a wait for the start.** A message that never reached its chat stays under it as not sent, with the reason, Retry and Edit.
