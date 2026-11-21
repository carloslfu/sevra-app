---
type: note
id: 01m7zqd3s7e163pj9038b5h4pq
created: 2026-11-21T18:55:22.407610+00:00
updated: 2026-11-21T18:55:22.407610+00:00
summary: Carlos asks for an in-depth code audit of the start window paths and chooses fixes 1 to 4 of its seven findings.
told_by: Carlos
---
# Owner asks for a code audit of the start window and fixes four gaps

This follows [[sources/notes/2026/11/start-window-closes]].

On November 21, 2026, after the first fix was installed and pushed, Carlos asked whether it was all fixed, then wrote:

"Without doing that, you can just check the code, right? Check the code in depth, every single detail, and see if there are missing things, right? If there are missing paths"

The agent audited every way a window opens, closes or shows a workbook, changed nothing, and reported seven findings. Carlos answered: "Fix 1 to 4"

## The four fixes he chose

1. A window still opening its workbook showed the start page, and closing it could leave no window.
2. A failed window that becomes the start page was registered as one only by the next window update.
3. The same workbook reached by another spelling of its path opened a second window.
4. The automation "Open workbook" button did not use the shared open step.

The other three findings (native tabs making a second start page, an error shown while Sevra is in the background, and inconsistent error titles) were not chosen and stay open.
