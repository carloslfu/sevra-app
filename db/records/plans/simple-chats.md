---
type: operational
id: 01m7ztjmrzpf9tmhwz36yxhg47
created: 2026-11-21T19:50:49.375684+00:00
updated: 2026-11-21T20:03:59.751371+00:00
summary: Threads, chapters, bookmarks and the main conversation became one plain list of chats per workbook, in format 33 with no conversion. Built, reviewed twice and checked; light set 11 of 11.
title: Plain chats
---
# Plain chats: one list of chats per workbook

Owner request: [[sources/notes/2026/11/simple-chats]]. Status: built and checked on November 21, 2026. Not committed.

## What the person sees

- The conversation pane's header shows the open chat's title. Clicking it opens the chat list in place of the open chat. (A first version used a dropdown menu of titles; on November 21 the owner asked for a better history view, and the panel below replaced it.)
- The chat list: New Chat and Back in its header, a search box, then the chats grouped Today, Yesterday, Previous 7 days, Previous 30 days and Older. Each row shows the title and the last-activity time, marks the open chat, and offers Rename… inline and Delete…. Arrow keys move, Return opens, Escape returns. Chat > Show Chats is Option-Command-L.
- Beside it: a pencil button for a new chat, and a menu with Rename Chat…, Search This Chat… and Delete Chat…. The menu-bar menu is called Chat and has the same actions, with New Chat on Shift-Command-N.
- A new chat is called "New chat" until the person's first message names it: plain text from the message, at most 64 words and 120 characters, without a sentence's final period. A title the person chose is kept.
- New Chat on a chat that is still empty stays there instead of piling up empty chats.
- Deleting asks first. Deleting the open chat moves to the most recent other chat, or to a new one when it was the last. A chat whose answer is still running cannot be deleted until it stops.
- Opening a workbook shows the chat that was open on this Mac, or the most recently active one.

## What a chat is

- A chat holds only its own messages. Nothing is carried from one chat to another: no parent excerpt, no inherited history, no shared summary. Search, history reads and tool results stay inside the chat.
- Context-window management is unchanged and runs per chat: compaction checkpoints belong to one chat.
- Only the person makes, switches, renames and deletes chats. The model has no tool for it.

## Storage: format 33

- `conversations(id, title, created, deleted)`. The 'main' row and the `chapters` and `bookmarks` tables are gone.
- A new workbook records one change, its first chat, so a rebuilt copy has it too. A fresh workbook is revision 1.
- Delete is a recorded change that sets `deleted=1` and removes the chat's unsent draft. Its messages stay, because the Sources and receipts its requests created point at them. A trigger refuses any message written into a deleted chat, and every Swift path refuses with `chat_deleted` first.
- No conversion. Under the [pre-1.0 policy](../specs/distribution.md#pre-10-compatibility-policy) older workbooks are refused. The owner asked to have the old ones removed from his way rather than converted.

## Removed

- Threads, return to main, shared summaries, chapters, bookmarks ("Save this exchange") and tangents, in the core, the app, the CLI and the checks.
- Typed commands: "start a thread", "thread:", "tangent:", "chapter:", "back to our main conversation", "share summary with conversation".
- The model's thread tools and actions (start_thread, start_thread_and_continue, rename_current_thread, return_to_main, review_thread_summary, conversation_action, thread.*), the request handoff that continued work in a new thread, its "continued" run status and lineage, and the `change` tool scope that only served it. The grammar now has eleven exact action shapes.

## Command line

- `chats`, `chat-new`, `chat-rename CHAT_ID TITLE`, `chat-delete CHAT_ID`.
- `ask WORKBOOK QUESTION [MODEL_DIRECTORY] [--chat CHAT_ID]` answers in the most recently active chat unless one is named, and reports the chat.
- Commands with an optional CHAT_ID use the most recently active chat.

## Checks

- Core: a new chat-lifecycle check (titles, rename refusals, ordering, delete, deleted-chat refusals including a direct insert, busy delete, last-chat delete, draft removal, rebuild) and history windows across two interleaved chats.
- Checks that used a tangent as "another conversation" now use a second chat. Checks that relied on 'main' use the chat a new workbook starts with, through small check-only helpers.
- The compaction scope check now proves that nothing from another chat reaches a chat's context.
- The light model set swaps `conversation.new_thread` for `conversation.greeting` and records any chat a request starts as `newChats`.
- Tool snapshot and grammar fixtures regenerated: 50 internal tools, 78 cases, 739 masks.

## Review findings, November 21

Two independent read-only reviews, one of the core, model and command line, one of the app, catalog, checks and scripts. Fixed:

- A crash could leave a run marked as running, which kept its chat from ever being deleted. The app's delete now closes such a run as interrupted; the command line stays strict.
- A shortened automatic title could be 121 characters, longer than a rename accepts. It now keeps room for its "…".
- Titles could hold direction overrides and invisible characters. They are refused in a rename and dropped from an automatic title; the two joiners stay. Titles are stored in canonical (NFC) form.
- Deleting a chat while an import or URL capture was still writing into it reported a saved import as failed. Delete Chat is now unavailable while anything is working, and an import's closing note tolerates a chat deleted meanwhile.
- A link to a message in a deleted chat showed a draft-save error. It now says the chat was deleted.
- A window whose open chat was deleted from outside (such as `chat-delete`) stopped refreshing. It now moves to the most recent chat.
- Two fast New Chat presses could make two empty chats. The workbook, not the list on screen, now decides whether the open chat is still empty.
- `ask` took an option such as `-x` as the model folder. Leftover "conversation" wording in chat messages, dead code and a stale comment.

Recorded, not changed:

- A deleted chat's messages remain readable by ID through the command line (`conversation`, `history-read`, `tool-receipt`). This is the provenance the soft delete keeps; the app and the model cannot open it.
- If deleting the open chat is refused after the app has moved to another chat, the person stays in the other chat, and when the deleted chat was the last, a new empty chat remains. With Delete offered only while nothing works, that needs a run started from another process.

## Results, November 21

- Core: 658 checks pass, including the chat lifecycle and two-chat history windows.
- Agent and grammar suite, preview, document, product and automation UI checks pass. The native app check that needs the packaged XPC worker fails in a plain build, as before; it is unrelated to chats.
- Persistence, history and receipt scripts pass against the new command line. The chat-job self-test passes all eleven light jobs.
- Light model set, once, on the packaged build: 11 of 11 passed, 281 s. That build preceded the review fixes, none of which change prompt or tool text. The prompt header is 5,172 tokens.
- Catalog captures of the `chat.chats` story (default, empty, long title, dark) were reviewed. The open title menu, rename sheet and delete alert are not captured by the batch renderer and were not seen live.
