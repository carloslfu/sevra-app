---
type: note
id: 01m7qzyxtfp5fpt9scmxxd2zea
created: 2026-11-18T18:50:59.279011+00:00
updated: 2026-11-18T18:50:59.279011+00:00
summary: Owner authorizes implementing the general chat tools plan end to end. Lists what the authorization does not cover.
told_by: Carlos
---
# Owner authorizes implementing the general chat tools plan

This continues [[sources/notes/2026/11/prebuilt-header-direction]].

On November 18, 2026, after [[records/plans/general-chat-tools]] had been aligned with the release packaging and the build-time header, Carlos wrote: "Check the latest changes and align anything else that needs alignment in the plan. Implement this whole thing end to end."

## What this authorizes

His words authorize implementing the plan as a whole. The rest of this section is the agent's reading. It covers what the plan's own steps and exits require, phase by phase: code changes on `main`, real-model and engine runs on this Mac for the gates and the engine probe, packaging development builds, and installing and operating the native preview where an exit requires an interface check, as earlier tasks did.

## What it does not cover

This section is also the agent's reading.

- **The `db/DB.md` line.** Agents do not edit that file. Phase 3 waits until he changes its rule against raw-model DDL, or tells an agent to.
- **P6, P7 and P8.** The plan he authorized lists them as unconfirmed, and they had not been put to him in conversation when he wrote this. Phases H3 and H4 ask him first.
- **Earlier development workbooks.** Phase 5 changes the workbook format. What happens to workbooks made by earlier builds is still his to decide.
- **Publishing.** Pushing to GitHub, publishing a release, and changing the installer plan's release order are not part of this. He answered "Not yet" to pushing the first plan commit, and other sessions push `main`.
- **Outside the plan.** VoiceOver, system settings, an upstream engine change and a model download stay out of scope. The model is already on this Mac.

The memory rules for this Mac still apply: one heavy process at a time, reclaimable memory checked before the model is loaded, and test processes stopped when done.
