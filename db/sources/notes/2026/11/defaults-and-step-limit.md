---
type: note
id: 01m84kxbt1qkf2h35h0gp0yfat
created: 2026-11-23T16:30:32.769548+00:00
updated: 2026-11-23T16:30:32.769548+00:00
summary: Carlos asks that chat use defaults instead of asking about choices and that no small step limit end a request, after a Home counter request failed.
told_by: Carlos
---
# Owner asks for defaults instead of questions, and no small step limit

On November 23, 2026, Carlos sent screenshots of a chat in a new, empty workbook. He had asked "Change my Home to show a big counter button". Sevra asked which dataset to count and what style to use. He skipped the question and Sevra refused. He then wrote "invent one and make it big, you figure it out", and the request ended with "This request reached its step limit." With the screenshots he wrote:

"Check everything about this and tell me what errors you find. Do the research on this and tell me what could be improved. For instance step limit: you can replay this thing and check it out, but two pieces of feedback that should go are:

1. Step limit: we should have no step limit, or maybe, if it is crazy, we should have a good enough step limit.
2. We should use defaults. We shouldn't be asking if the user asks for a button. There should be default styles, and the model should do the default and do something by default, and then the user can iterate on it."

He added: "We want the best UX possible here."

The agent read the run from the workbook's saved record and reported what it found: [[records/reviews/home-counter-run-2026-11-23]]. Asked whether to implement the fixes, he answered "Yes, fix them".

## The agent's reading

- **A count of steps is not the stop rule.** A chat request stops when it stops getting anywhere, and it closes with the model's own account of what it did. A high count stays as a backstop against a run that never ends.
- **Choices get defaults.** How something looks, what it is called, where it goes and what it shows first are Sevra's to choose and to say. Business values are still never invented, and are still asked for.
- **Skipping a question hands the choice over.** It is not a refusal and does not make the request read-only.
- **An error names what is wrong.** One message for five possible faults, and Foundation's own words for a missing field, each cost the model steps it could not use.
- **Example rows are not a default.** A table made for a request starts empty unless the person asks for examples.
