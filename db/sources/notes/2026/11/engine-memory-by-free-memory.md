---
type: note
id: 01m88byf5w428vf84d5g4zgenb
created: 2026-11-25T03:28:18.108229+00:00
updated: 2026-11-25T03:28:18.108229+00:00
summary: 'Carlos asks for the engine''s memory size to follow free memory: a concise plan, reviewed in detail and as a whole, then built in full.'
told_by: Carlos
---
# Owner asks for the engine memory size to follow free memory, planned, reviewed and built

On November 24, 2026, Carlos asked how Sevra sizes the model's memory. The agent found a fixed
12 GiB engine budget on every Mac and said it was probably too low on his 48 GiB Mac. He wrote
"Yes, compare once", and one run at 12 GiB and one at 22 GiB followed. At 22 GiB the whole model
stayed in memory and answers were written about 2.2 times as fast, with no swap
([[records/plans/engine-memory-by-free-memory]] has the numbers).

Asked whether the app should use about 22 GiB when that much memory is free, Carlos wrote:

"Yes, plan it. Write down the plan, then check it out. Give it a few passes to check out every
single thing, every single detail, and then check it out as a whole to be sure everything's good.
Concise: everything makes sense together and as a whole, and every single part makes sense.

Then, implement it all. Implement the whole plan."
