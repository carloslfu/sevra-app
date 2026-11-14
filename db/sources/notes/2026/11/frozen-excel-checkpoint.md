---
type: note
id: 01m7e37fy281vtg7c7vd62m3hf
created: 2026-11-14T22:35:41.377796+00:00
updated: 2026-11-14T22:35:41.377796+00:00
summary: Owner selects continued Excel verification on exact frozen da3c472 checkpoint while another chat changes the shared engine.
told_by: Carlos
---
# Frozen Excel verification checkpoint

During the fresh ten-workflow verification, another active chat changed the shared app checkout, including authoring, SDK and native interface files. The ongoing local suite encountered compile errors in the new chat-operation code. The existing live Excel batch had already copied its isolated binary and resources, so those changes did not affect it.

Carlos was asked whether to coordinate the two chats for a stable checkpoint or continue testing the frozen Excel checkpoint. He selected:

> Keep testing the frozen Excel checkpoint

Verification therefore targets exact commit `da3c4720e05033b5aaea620ebb01abde28123d9e` in an isolated read-only source checkout. No other chat is messaged or its changes reverted. The next fresh batch uses the same engine binary and exact source/fixture hashes as the current batch, with new workbooks and local-model requests. Newer chat-operation code is outside this acceptance. Installation, if completed, must identify this frozen checkpoint rather than imply it includes newer unbuilt source.
