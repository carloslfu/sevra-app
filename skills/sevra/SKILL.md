---
name: sevra
description: Work in a Sevra workbook (.sevra, or a .sevraz portable copy), a spreadsheet run through chat with a local model. Use when the user mentions Sevra or one of its workbooks. Run `sevra agent` first; it prints the guide for the installed version.
---

# Sevra workbook

Run `sevra agent` before working in a workbook. It prints how to use the workbook
tools (`sql`, `run`, `save`, `search`, `read`) and their exact arguments, from the
installed `sevra` itself, so it always matches that version. This file only points
there.

To call the tools over MCP instead of the command line, run `sevra mcp [WORKBOOK]`
as a stdio server.

If `sevra agent` is an unknown command, the installed CLI is older: run
`sevra help` and follow it. If `sevra` is not on the PATH, the Sevra app installs it
at `~/.local/bin/sevra` (`bash scripts/install.sh` in
https://github.com/carloslfu/sevra-app).
