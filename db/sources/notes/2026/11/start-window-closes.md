---
type: note
id: 01m7zm6syg493n7056fyhgj37q
created: 2026-11-21T17:59:30.000622+00:00
updated: 2026-11-21T17:59:30.000622+00:00
summary: Carlos asks for the start window to close whenever a workbook opens, and leaves the last-close behavior to the best UX.
told_by: Carlos
---
# Owner asks for the start window to close when a workbook opens

On November 21, 2026, Carlos opened his workbook from Sevra's start window, and the start window stayed open behind it. He wrote:

"Open the workbook, but it kept the window behind open, even though I opened the workbook. Check that all of the tabs after the first window always close it (I mean, the ones that make sense). Reason about the best UX possible here."

Asked whether closing the last workbook should bring the start window back, quit Sevra or leave it running with no window, he answered: "Choose the best way, the best UX."

## The agent's reading

- **Every way into a workbook closes the start window** once the workbook is in front: a recent workbook, Open, a new or example workbook, Start from files, and a workbook opened from Finder or a command line link. That includes a workbook already open in another window, which only comes forward.
- **The start window stays when nothing opens:** a cancelled panel, a failed open, Settings.
- **A failed open never leaves a second start window.** A workbook that is no longer on disk is reported before any window opens and leaves the recent list.
- **Closing the last workbook window brings the start window back,** as a welcome window does in Xcode. Quitting does not. There is one start window at a time.
- **The change is built, installed and checked in the app,** with the existing VoiceOver and system-setting boundaries. Testing stays light.
