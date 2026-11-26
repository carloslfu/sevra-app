---
type: note
id: 01m8b4yy845hp2ywn01skhb8cs
created: 2026-11-26T05:23:56.804193+00:00
updated: 2026-11-26T05:23:56.804193+00:00
summary: Carlos asks that agents learn Sevra from the CLI itself rather than an installed skill, with an MCP server, and that all of it be tested.
told_by: Carlos
---
# Owner asks for the agent guide to come from the CLI, with MCP

This continues [[sources/notes/2026/11/cli-skill-seven-tools]].

On November 26, 2026, after the agent said the skill was installed for Codex only, Carlos wrote:

"why do we need to install it? We don't need to have it installed. We just need a way for people to get this skill, install it, right? Maybe not even install it, but I don't know. Reason about what the best way to go about this is, and tell me what the best UX is in the agentic era."

The agent proposed that the CLI teach itself: `sevra agent` prints the guide from the binary, `sevra help` points there, the skill becomes a pointer, and an MCP server can come later. Carlos answered:

"yes, do it all, including the MCP and testing that it works. test that everything works."

## The agent's reading

- The guide lives in the CLI's source and prints with the tool declarations Sevra's chat model is shown, so it cannot drift from the installed version.
- `sevra mcp` offers the same five tools as `sevra tool`, with their declared schemas and a workbook path. `ask` and `finish` stay out, as in the CLI.
- Installing the skill stays possible and optional. Nothing new is installed on this Mac for Claude Code.
- "Do it all" was not read as permission to push.
