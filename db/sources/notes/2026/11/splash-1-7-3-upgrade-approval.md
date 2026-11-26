---
type: note
id: 01m8ak3x6kc21q5465jtakn02f
created: 2026-11-26T00:12:05.203031+00:00
updated: 2026-11-26T00:12:05.203031+00:00
summary: Carlos asks for the Splash 1.7.3 upgrade through the update-splash skill.
told_by: Carlos
---
# Owner asks for the Splash 1.7.3 upgrade

On November 25, 2026, after asking which Splash version the installed app has (1.7.2), whether it is the latest (1.7.3 was published that day) and what 1.7.3 changes, Carlos was told that it mainly serves Inkling-2-Mini, that Qwen3.6-35B-A3B text is level with 1.7.2, that the one fix that applies to Sevra is the one-lane start on M5 GPUs of 8, 12 or 14 cores, and that the engine protocol moves from 15 to 16. He answered "upgrade to 1.7.3 with the update-splash skill".

This approves the pin move to Splash 1.7.3 and the skill's work. The light testing rules still apply.

After the model checks found that 1.7.3 falls 15 tokens short of 64K at the 8 GiB memory floor, the agent offered a 9 GiB floor or staying on 1.7.2. Carlos answered: "Evaluate what you need to do, and do whatever you think makes the most sense here and has the best user experience. We do need to upgrade to 1.7.3."
