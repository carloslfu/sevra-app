# The app job after phase 5, November 19, 2026

`build.app` needs the app checker, an XPC service that the CLI finds only when it is the main
executable of an app. These runs used a copy of the packaged app whose main executable is the
CLI.

- At `8ee243a` it failed: the checker found real faults, then the model sent the same app four
  times after the check said to add the selected rows to fixtures. The message named the field
  but gave no shape.
- At `0a11f40` the message gives the field with a row of the app's own table. One run passed in
  5 decisions and 78 seconds; this folder holds that run.
