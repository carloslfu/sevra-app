---
type: note
id: 01m78qhn74x086mafvtdvdk1zk
created: 2026-11-12T20:35:19.396022+00:00
updated: 2026-11-12T20:35:19.396022+00:00
summary: Owner requests full native programmable app-engine implementation and verification, explicitly permitting installation and UI testing.
told_by: Carlos
---
# Programmable native engine implementation direction

Carlos requests a highly native, tightly integrated macOS mini-app engine: arbitrary JavaScript in a constrained sandbox, React-like composition, reactive data and efficient native messaging, with no web view or HTML/CSS interface.

After discussing the architecture, Carlos instructed: "Revise the architecture and how the implementation would work a little, and create a full plan for it. Give it a few passes, fix any inconsistencies or anything that needs improvement, and then implement it all end to end and verify that it works and is complete and functioning".

The agent identified the repository's earlier explicit no-install/no-UI restriction and asked whether final verification could install and operate Sevra Native Preview. Carlos explicitly answered: "Allow app installation and UI testing". This permits app installation and UI verification for the implementation, superseding that earlier restriction for this task. It does not request VoiceOver or system-setting changes, a production release or changes to the separate website business.
