# Interface look and update test, November 20, 2026

The owner asked for the checks that had waited on window access. The look used the UI Catalog
and the installed app on a disposable sample workbook. Every workbook was synthetic.

## Tools screen

The catalog's `main.tools` story was captured in light at 1100 points, in dark at 760 points and
in its empty state, and used live. The cards, the "Not enabled on this Mac" and "Enabled on this
Mac" states, "What it runs" and "Enable on this Mac" all worked. "Enable on this Mac" turned the
card to enabled with "Turn off on this Mac". The sample script tool counted tables while its
description said it counts parts below a reorder level; it now reads the `stock` table with its
`level` input.

## "Change saved" and "Undo this change"

Two faults, both fixed at `46f6b58`:

- The row never appeared, in the catalog or the app. Its loader was a task on a SwiftUI `Group`
  that was empty until the task ran, and an empty `Group` never starts one. The row is now a
  stack outside the message's spaced stack. A reply without a change is pixel-identical to the
  old build in the catalog's empty state.
- Its Undo for a `sql` change called the app's host actions, which do not handle
  `table.undo_sql`, and showed "This conversational operation is not connected yet." It now
  calls the core undo with the person as the actor. The row turns to "Change undone" and the
  status reads "Change undone." The headless SQL check gained the case: a new table and its rows
  from one call offer one undo, and the person's undo takes them back.

In the installed app, one chat asked for a new Reorder levels table with one row. The answer
took 17 seconds and showed "Change saved · Undo this change".

## Export save panel

- Asked "Export the Supplier comparison table as a CSV file.", the model searched, queried and
  ran a script, then wrote the CSV into its answer. It never read the action list, so it never
  reached `file.export_table`. Not fixed.
- In that answer the fenced CSV block lost its line breaks. Chat text is parsed as inline
  markdown, so a fence becomes one code span. Not fixed; it predates this plan.
- Asked to use `file.export_table`, the model called it once with `tableID`, was refused, then
  called it with `id`. The app opened the standard save panel titled "Export", named "Supplier
  comparison.csv" with the extension hidden. Cancel returned "The person closed the save panel.
  Nothing was exported." But the answer showed the first call's refusal, not that the export
  was cancelled. Not fixed.

## H4 update test

Build 4 (`0.9.0-qa.4`, header `793529b6`, 2,572 tokens) was installed from its disk image into
an empty folder; the app, its CLI and a CLI link found its header. Build 5 (`0.9.0-qa.5` from
`46f6b58`, header `4b5222b7`, 2,707 tokens, 152,015,708 bytes) was built clean and a signed
loopback feed for it was served. The owner declined window access to the QA app, so Check for
Updates was not run. The test is not done.
