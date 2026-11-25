---
type: note
id: 01m88argh2pn4j3wrq86af2494
created: 2026-11-25T03:07:34.306462+00:00
updated: 2026-11-25T03:07:34.306462+00:00
summary: Carlos asks for the Splash 1.7.2 upgrade and approves quitting Sevra for one real-model check run.
told_by: Carlos
---
# Owner asks for the Splash 1.7.2 upgrade

On November 24, 2026, after asking what Splash 1.7.2 changes against the pinned 1.7.1 and whether it would help, Carlos was told that it brings no measurable gain for Sevra's MLX 4-bit Qwen model, mainly the cache fixes, and that skipping it was the recommendation. He answered "upgrade".

After the model-free checks passed, the agent found the installed Sevra app running its own engine with about 11.7 GB reclaimable and asked whether he would quit Sevra so the real-model checks could run. He answered "Quit, run checks". The agent quit the app normally and ran the header tests and the light set, one run each.

This approves the pin move to Splash 1.7.2 and those checks. It does not approve installing the app or publishing a release. The light testing rules still apply.
