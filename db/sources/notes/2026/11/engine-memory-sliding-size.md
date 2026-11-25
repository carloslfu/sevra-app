---
type: note
id: 01m89ba95qwgk5savn6hx11xtj
created: 2026-11-25T12:36:31.000000+00:00
updated: 2026-11-25T12:36:31.000000+00:00
summary: 'Carlos asks for engine memory sizes beyond 12 and 22 GiB, for different Macs, written as a plan and reviewed until it is ready to implement.'
told_by: Carlos
---
# Owner asks for engine sizes beyond two, planned and reviewed, not yet built

On November 25, 2026, after the engine began choosing 12 or 22 GiB at each start
([[records/plans/engine-memory-by-free-memory]]), Carlos asked whether a running engine shrinks
or grows with memory, and whether that is the best experience. The agent said a 12 GiB engine
never moves up while it stays loaded, and offered to time a restart. Carlos wrote:

"Yes, and not only those sizes, but check other sizes that could make sense for different
computers and for different. We don't want only two sizes, do we? Analyze it from first
principles. Tell me what is the best UX. Think about it deeply."

One run each at 8, 16 and 19 GiB followed, beside the earlier 12 and 22 GiB runs. The agent
proposed a size that follows free memory from 8 to 20 GiB, moving up when the app comes forward.
Carlos then wrote:

"Check this plan. Check if this is the best. Evaluate every single thing and the plan as a whole.
Write down the plan and then give it a few passes. Make sure it is ready to implement."

He asked for the plan and its review, not for the build.
