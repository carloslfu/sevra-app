# Jobs run by name after phase 5, November 19, 2026

One run each of `build.rule`, `build.saved_tool` and `build.app`, with the CLI of the installed
app built at `8ee243a`.

- `build.rule` passed in 3 decisions. The model read the rule guide and saved an alert rule
  through `template.rule` with alert text, so no workflow was needed.
- `build.saved_tool` passed in 2 decisions.
- `build.app` failed for a reason outside the job: that CLI sits in `Contents/CLI`, where the
  app checker's XPC service cannot be looked up, so every app check reported that it could not
  reach a helper. See `2026-11-19-phase5-app` for the run where the checker could be reached.

`build-form/` holds a later run of `build.form` at `0a11f40`, from the same app copy as the app
job. It passed in 2 decisions: the model saved the form as a workbook tool that adds the row.
