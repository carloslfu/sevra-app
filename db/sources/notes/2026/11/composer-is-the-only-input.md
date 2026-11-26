---
type: note
id: 01m8b0gpj263297ajykmcv24yy
created: 2026-11-26T04:06:15.874135+00:00
updated: 2026-11-26T04:06:15.874135+00:00
summary: Carlos directs that chat questions offer only one-tap answers and that every typed answer goes through the composer.
told_by: Carlos
---
# Owner direction: the composer is the only place to type in chat

On November 25, 2026, Carlos asked whether inline forms in chat were the right interface, or only for multiple choice, since a text field in the conversation duplicates the composer. He asked for a first-principles answer, then wrote:

"Okay, map the current cases, the current things. Map the whole codebase and where this needs to be changed, and change it all, and test that it works."

The rule he accepted: the composer is the only place to type. A question in the conversation offers only one-tap answers (the model's choices, or the options of a single yes-or-no or record field). Every other answer is typed in the composer, which replies to the open question by default and can send a new message instead. Several values at once are a draft the person edits in the workbook's own views, and confirmations prefer act plus Undo.

## What changed

- The question card (`ConversationInputView`) shows no text, number or date fields and saves no field drafts. It shows choice buttons, Yes and No, or record buttons, plus Skip and Cancel question.
- A plain message from the composer answers the open question. The `Answer:` prefix still works. A row above the composer says "Replying to:" the question, with "Send as a new message" and back.
- A yes-or-no answer reads Yes or No in the transcript, not true or false.
- The catalog drops the chat field Draft and Conflict states and the draft-conflict story.

The `ask` schema and the chat instructions are unchanged: they already ask one missing value in plain chat and use `ask` for several. Changing them needs a new prepared header.
