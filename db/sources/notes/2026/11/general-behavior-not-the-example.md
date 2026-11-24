---
type: note
id: 01m85qw00cx0c67qryjf2fwejs
created: 2026-11-24T02:58:56.652272+00:00
updated: 2026-11-24T02:58:56.669647+00:00
summary: Carlos asks that the defaults and button work be general, built for real use cases, not fitted to his counter example, and reviewed several times.
told_by: Carlos
---
# Owner asks for general behavior, not a fit to the example

On November 23, 2026, after a button and a size setting were added for his "Change my Home to show a big counter button" request, Carlos asked: "Did you have to hardcode my button request, or was it general enough? What did you do? This was supposed to be general."

The agent read the code and reported that the stop rule, skipping and the defaults rule were general, but that the button only added an empty row, the instructions carried a recipe for "a counter people press", size applied to two component types, the field-order fix covered only what his request touched, raw decode errors remained in seven places, the summary showed only after a saved view, and the only defaults test was his own sentence. It also found that the view guide contradicted itself about buttons.

He answered: "But it should be done as a general thing. Do you get what I'm saying? Not for counters and stuff, but for real use cases. This is just one use case, and you should fix the general behavior. That's what I meant. Check the whole code. Is that how this is doing it?" After the agent proposed a plan and asked whether to make it general, he answered: "Yes, make it general and also fix whatever else you see there. Review the whole thing a few times."

## The agent's reading

- **The example is one use case.** Fixes belong in how chat behaves for any request: building blocks the model combines, not recipes for one request.
- **The two open points take the general answer.** The summary shows after every kind of save, and size applies to every component where it has a meaning. The agent read "make it general" as covering both.
- **A button runs a saved tool.** Tools are the workbook's general actions, with typed inputs, history and Undo, so a button can record, change or remove rows, not only count.
- **Tests are real requests,** not only his sentence.