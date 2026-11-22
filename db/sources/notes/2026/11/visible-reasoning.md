---
type: note
id: 01m82et9vyc6kbqkj0v3z4hscy
created: 2026-11-22T20:23:00.734707+00:00
updated: 2026-11-22T20:23:03.666317+00:00
summary: Carlos asks that people see the model's reasoning and the calls Sevra sends back, by default, collapsed under each request.
told_by: Carlos
---
# Owner asks that people see the model's reasoning by default

On November 22, 2026, after reading where chat time goes, Carlos asked:

"Shouldn't the user be able to see the reasoning traces so the model can be debugged by themselves and also so they can see what the model is doing? Shouldn't that be the default?"

He added that he means by default, not in a debug mode: the person should be able to see the reasoning and the messages.

The agent pointed out that the app hid reasoning on purpose: [[records/specs/agent-activity]] AA03 said not to expose raw private reasoning, and [[records/specs/intelligence]] said reasoning is never saved. It proposed showing it live and collapsed under each request, keeping it after the reply and after reopening, labeling it as the model's working notes, and showing answers Sevra sends back as steps with the reason. Carlos replied:

"Yes, do it. Make it happen, and be sure it looks good, it has a good UX, and it's what a user would expect."

## The agent's reading

- **This reverses the AA03 line and the intelligence spec's "never saved" rule.** Both are updated to say what the app now does.
- **The reasoning is for the person, never for the model.** It is saved with the run's per-call record, which no prompt, tool, search or summary reads. Later requests still rebuild their context with no old reasoning.
- **Collapsed by default, one click away.** While the model reasons, its latest words show on one line under the activity title without opening it.
- **No workbook format change.** The run's existing record holds the thoughts, so current workbooks keep opening.
