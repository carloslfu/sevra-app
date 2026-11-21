---
type: note
id: 01m7znqk44nyj7ckr9bekpt1vk
created: 2026-11-21T18:26:08.644093+00:00
updated: 2026-11-21T18:37:57.746707+00:00
summary: Carlos asks where a first request's time goes and whether the built KV cache is used, then for every fix at its root and a new measurement.
told_by: Carlos
---
# Owner asks where a first request's time goes, then for every fix and a new measurement

On November 21, 2026 Carlos sent a screenshot of a new conversation in the installed app. He wrote "hi". The answer, "Hello! How can I help you today?", took 14 seconds, and its activity showed a failed step, "Read earlier conversation: This conversation message is missing." He wrote:

"And during the first request, measure every single time that is used. Where is the time going, and why does it take so long for it to do anything? And tell me, is it using the built kv cache?"

The agent measured the turn from its saved metrics and with one cold command line run on a copy of the workbook. It reported the engine start, the two model calls, a made-up message ID behind the failed step, and that the prepared header was resumed but covered only half the prompt. It proposed four fixes: start the engine before Send, resume follow-up turns past the header, put the chat scope text into the header, and look at the first decision's 64-token thinking limit. He answered:

"yes, start with the engine prewarm. And do all of the fixes that you need to do first, getting at the root cause and then fixing them generally. Fix all of the things, and then measure it again and come back with the improvement."

The work and both measurements are in [[records/plans/first-request-latency]].
