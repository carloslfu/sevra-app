---
type: operational
meta-type: operational
id: 01m659x4nd2q89tkpzzsssd7yr
created: 2026-10-30T02:23:30.477380+00:00
updated: 2026-11-26T05:12:32.976358+00:00
summary: 'Where the app stands now: what is built, open owner decisions, known limits and how to work here. Earlier checkpoints are in the handoff history.'
title: Agent handoff
---
# Agent handoff

Where the app stands, for the next agent. This page holds the current state only. Replace a section when it changes instead of adding a dated one; the details of a change belong in its plan or review. The log of earlier checkpoints, October 30 to November 25, 2026, is in [[records/operations/agent-handoff-history]].

## Checkout context

The [[sources/notes/2026/11/durable-agent-checkout-context|owner requires durable checkout context]] in agent instructions and handoff notes. Start by confirming the repository root and current Git status. This app retains its own Git history, remote and public knowledge store even when nested inside another workspace.

If a parent `../AGENTS.md` exists, read its machine-specific checkout and recovery notes before changing local layout, deleting caches or assuming another checkout is redundant. Standalone clones do not require a parent workspace or private repository. Do not copy local paths, private manifests or machine preferences into tracked public files.

Preserve unpublished branches, reflogs, linked worktrees, ignored workbooks, models and build evidence when relocating a checkout. A clean primary tree and synced main branch do not prove that all local state is published. A relocation also does not rebuild or install the app; verify the actual installed executable against the intended packaged build before claiming it is current.

Another agent may be working in the same checkout. Commit only the files your change touched, and leave other uncommitted work alone.

## What Sevra is

A spreadsheet you run by talking to it, with a local model: chat is the input, the workbook keeps the database in typed tables with history and Undo, and spaces (Home and saved views) are the output ([[sources/notes/2026/11/chat-and-spaces-product]]). It is a free source preview for Apple silicon Macs, not a signed or notarized release.

## What is built, as of November 26, 2026

- **Chat works through seven general tools**, `search`, `read`, `sql`, `run`, `save`, `ask` and `finish`, and nothing else ([[records/plans/general-chat-tools]], "The build so far"). SQL changes tables at once through the recorded write path, with Undo. Scripts run in a sandbox that reaches only the workbook. The prompt header is made at build time and restored when the engine starts.
- **Open choices get defaults.** When a request leaves a name, layout or place open, the model picks one and says so. A request stops when it makes no progress instead of at a step limit.
- **Plain chats.** Each workbook has a list of chats with only their own messages; threads and the main conversation are gone ([[records/plans/simple-chats]]).
- **Saved tools.** A workbook carries its own SQL or script tools, granted per Mac. Tools run by name in chat, from a view's button, as `tools.run` actions in workflows and from automations that follow a saved check.
- **Remove and restore** work for every saved kind, in chat with a confirmation and in the app with a Removed list.
- **Chat questions are answered in the composer**, with one-tap buttons for choices, and every box that writes to Sevra has the microphone.
- **The stock ledger is gone.** Stock movements, balances, receiving, stock threshold automations and the supplier-quote guard were removed on November 25 ([[records/reviews/chat-spreadsheet-cleanup-2026-11-25]]). Inventory is ordinary tables and saved tools.
- **The engine** is Splash 1.7.3. Its memory is sized from free memory at each start, between 8 and 20 GiB, and it restarts smaller under memory pressure ([[records/plans/engine-memory-sliding-size]], which replaced the two sizes of [[records/plans/engine-memory-by-free-memory]]).
- **Outside agents** use the tools through `sevra tool` or `sevra mcp`, and learn them from `sevra agent`, which prints the guide built into the CLI with the live tool declarations ([[sources/notes/2026/11/agent-guide-in-the-cli]]). The skill in `skills/sevra` is an optional pointer to it.
- Earlier work still in place: Excel import and reconstruction, programmable mini apps, rich visuals and the Native UI Catalog. Their plans are in `db/records/plans/`.

## Open decisions for the owner

- Whether submitting a form from chat keeps its confirmation now that SQL writes directly. The plan keeps it.
- Whether to remove the lower-level CLI commands that the tools now cover. They are listed under `sevra help all`, and tests and scripts use them.

## Known limits

- A release claims only the chips its header tests passed on, so far an Apple M5 Pro.
- The app job is the least reliable model job and is not in the light set.
- A `sevra` installed before November 26, 2026 has no `sevra agent` or `sevra mcp`; install the app again to get them.
- UI and VoiceOver accessibility are not qualified. The workbook menu's Remove view, Remove table and Removed items were not checked live in the installed app.

## How to work here

- Build, run and the check commands: [[records/operations/build-and-run]]. Installing a build: `bash scripts/install.sh` ([[records/plans/macos-installer-and-updates]]).
- Test lightly, as `AGENTS.md` says: no-model checks for the change, then the light set `python3 scripts/check_chat_jobs.py --output DIR` when chat behavior changed. `scripts/check.sh` runs once on a candidate before a release.
- Interface changes also update the [[records/operations/native-ui-catalog]].
