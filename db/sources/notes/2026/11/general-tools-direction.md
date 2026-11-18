---
type: note
id: 01m7qqr2mwxjc6zshpgfe8d1sy
created: 2026-11-18T16:27:26.236226+00:00
updated: 2026-11-18T17:09:55.122299+00:00
summary: 'Owner directs general chat tools: direct SQL writes, sandboxed code, per-workbook tools, and a shipped pre-read prompt header with no fallback.'
told_by: Carlos
---
# General tools, direct SQL, sandboxed code and a shipped prompt header

This continues [[sources/notes/2026/11/chat-tool-routing-direction]]. Carlos reviewed the two-group revision of [[records/plans/native-chat-prompt-routing]] in conversation on November 18, 2026 and changed the direction step by step. All of it was said in planning. He repeated that nothing was to be built yet.

## What Carlos decided

**The default prompt should be very light.** He first asked for a default of "a few tools, only 5 to 9", with groups for everything else. He rejected two mechanisms the agent proposed along the way. Groups that hold a single tool: "There are groups with one, too? That doesn't make sense". Groups shown from workbook state: "This is a code smell or something. It should be the same as the other groups".

**The tools themselves are too specific.** "Some of the tools are too specific. They should be general. They should produce SQL. They should produce code and be able to do things with code. There should be a code execution tool. For instance, there should be generic tools to work with the workbook, not fixed tools." And: "We want freeform tools because this is a freeform tool".

**SQL writes directly, and code is arbitrary but sandboxed.** Asked whether model-written SQL may change data or only read it, he answered: "Yes, it can write. I'm telling you: write SQL changes directly, and this is a general-purpose tool." And: "This is going to be able to execute sandboxed arbitrary code and SQL against the thing."

**Each workbook has its own tools.** "There will be some tools that are per workbook, but that's up to the user to configure." And: "Those are discoverable, like the views, the apps, some tools that the workbook will have, and some extra tools."

**This replaces earlier rules.** The agent told him that the specifications currently say "no model-authored SQL" and "No arbitrary SQL, generated executable code", and that going general means deliberately replacing those rules. He confirmed the direction after hearing that.

**The fixed start of the prompt ships already read.** He proposed keeping "the KV cache of the initial prefill of tokens that always go" in the app so it is reused. He then required that it always match: "It is not acceptable for a user in production" to reach the slow path. "We have to create a test even for this, so it never fails and we never have this path at runtime." "Before release, we test this". "There should be no fallback." When the agent described shipping the file inside the signed app, treating a mismatch as an error, and proving the match with release tests, he answered: "Yes, this is what I want."

**Planning request.** "Okay, now plan how to do it thoroughly. Make sure the plan is solid and ready for execution. Also, check the latest state of the code". "If you're going to reuse the other plan, modify it and be sure it is aligned with everything we decided here. Give the plan a few passes".

## What Carlos did not decide
The agent proposed seven built-in tools named `search`, `read`, `sql`, `run`, `save`, `ask` and `finish`, with no built-in groups. Carlos asked for the plan without confirming or changing that list.

Two points were in the agent's summaries of what had been agreed. Carlos did not object to them, but he did not state them himself. One is that no router chooses tools, by text matching or by an extra model call. The other is that inventory, receiving and quote comparison leave the built-in tools and the shared instructions. His earlier note asked for the simplest router and allowed a model router. The plan asks him to confirm both.

He was also asked, and did not answer, what the app should do on a Mac or model outside the tested set, what happens to drafts and acceptance once writes are direct, and how far the sandbox reaches. The agent's assumption for the last one was the workbook only.

Two things were found while planning, after the conversation, and have not been put to him. Sevra is built from source on each Mac and has no installer, so no signed app exists that could carry a header file today. The plan proposes making the header during setup on each Mac now and shipping it once an installer exists. The plan also proposes that a tool arriving inside a copied workbook stays disabled until the person enables it on that Mac. Both await his answer.

This note authorizes planning. It does not authorize implementation, an engine change, a model download, app installation or interface testing.
