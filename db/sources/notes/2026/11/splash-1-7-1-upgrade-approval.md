---
type: note
id: 01m86y1cet53w7mxjm3wdxws38
created: 2026-11-24T14:05:59.130586+00:00
updated: 2026-11-24T14:06:07.576649+00:00
summary: Carlos approves the Splash 1.7.1 upgrade plan as written, with int8 cached states and the header-test run, and asks for its implementation.
told_by: Carlos
---
# Owner approves the Splash 1.7.1 upgrade plan and its implementation

On November 23, 2026, after comparing another inference engine with Splash and asking what Splash 1.7.x adds, Carlos wrote:

"let plan the upgrade to Splash to 1.7.1, first, plan do not do anything yet. We are in the planning phase: * Examining everything we have as an integration point, everything this new version comes with, and the repercussions it has or the opportunities it opens. * Check every single thing, check everything, give it a few passes, and reason about it to be sure it is the right thing to do. * Give it a few passes to the plan, and then make it implementation-ready."

The agent wrote [[records/plans/splash-1-7-1-upgrade]] and reviewed it three times. It asked: "Approve the plan as written, with int8 cached states and the header-test run?" On November 24 he answered "Approve, implement".

This approves:

- The plan's steps, decisions D1 to D6 and its follow-ups left for later.
- D2: 1.7.1's default int8 cached states, not `--cached-states exact`.
- The header tests' run of about ten engine starts, estimated at 3 to 5 minutes, beside the light set and two timing conversations.

When the agent found another session's uncommitted chat work in the checkout and asked how to start, he answered "It already finished." The upgrade therefore proceeds in the same checkout, on top of that work, without changing it.

It does not approve pushing or publishing a release. The light testing rules still apply.
