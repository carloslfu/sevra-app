---
type: note
id: 01m7qynctharc6cnm64wtv9g3s
created: 2026-11-18T18:28:18.385478+00:00
updated: 2026-11-18T18:28:18.385478+00:00
summary: Owner directs that the prompt header is calculated at build time and restored at engine start, the same way in development and release. Planning only.
told_by: Carlos
---
# The header is calculated at build time, in development too

This continues [[sources/notes/2026/11/general-tools-confirmation]]. All of it was said in conversation on November 18, 2026, in planning. Carlos repeated that nothing was to be built: "We're in planning mode still. Don't implement anything yet".

## What Carlos decided

[[records/plans/general-chat-tools]] proposed making the prompt header during setup on each Mac for now, because Sevra is built from source and no shipped app existed to carry it. Carlos had confirmed that proposal as written. He then changed it.

He asked for development builds to act like a release: "Couldn't we make it so we simulate that for when we are building from source, because this is the development mode, right? Why not have something in development mode and document it so when we have the thing?"

When the agent repeated it back, he stated it himself: "What I mean is that during development, before shipping it, we calculate the KV cache that we're going to restore when it starts for real and in dev."

So the header is calculated ahead of time, as a build step, and the app restores it when the engine starts. The same mechanism runs in a development build and in a release. The agent told him the catch, that the build step needs the model on that Mac and a source build downloads the model after the app is built, so in development the step runs after the model download. He confirmed the idea after hearing that.

## The installer

He then asked the agent to "Check the recent changes" and whether they "add up to our plan". Another session had implemented and rehearsed standalone packaging, recorded in [[records/plans/macos-installer-and-updates]]. The agent reported that it gives the calculated header an app to ship in, and listed what was still missing. He answered: "Align the plan then. Give it a few passes. Make sure it is good and ready for implementation."

## What Carlos did not decide

The agent's reading, not his words: the app itself never computes a header, so a source build needs a second run of the install command after the model download. He has not been asked whether that extra step is acceptable for people who build from source, or what a release should claim about Apple chips it was not tested on. He has not seen a measured size for the header. The plan lists these for him.

This note authorizes changing the plan. It does not authorize implementation, running the model, packaging a release, or installing or operating the app.
