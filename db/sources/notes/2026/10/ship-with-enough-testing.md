---
type: note
created: 2026-10-30T22:23:41.174699+00:00
updated: 2026-10-30T22:23:41.197170+00:00
summary: Owner keeps the full queue and asks for the smallest reliable version of each item, with fewer tests.
told_by: owner
---
# Keep the full scope, test enough, ship fast

On October 30, 2026, while increment 6 was being repeated against its stress job, the owner
said:

> I want what you were doing. Just evaluate if you were doing too much of it, too many tests, or just do enough. do what is enough for us to ship fast

> Yes, be sure we are not over-engineering or over-building. We just want these things to be good and good enough to ship, so it is reliable for the end user.

> Just to clarify, we want to run all of it, but with a good enough thing, right? We run all of it, all of the scope, but don't make as many tests, or just do ones. Just use your time smartly, is what I mean.

The whole queue stays. Each increment gets its smallest reliable version, the real failure and
one nearby counterexample. The full suite, install and window pass run once on the final
candidate, not once per increment. This restores the verification rule in
[[records/specs/mvp-delivery]], which the per-increment receipts had drifted past.
