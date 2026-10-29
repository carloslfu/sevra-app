---
type: spec
meta-type: conclusion
id: 01m64rrj1eavy9xqkkv2yfz9tb
created: 2026-10-29T21:23:54.542069+00:00
updated: 2026-10-29T21:56:06.889309+00:00
summary: Native live agent activity with shimmer, exact tool receipts, cancellation, bounded inspection and durable history.
title: Live agent activity
status: implemented
---
# Live agent activity

Owner-approved October 29, 2026 after the first human supplier walkthrough.
A static Thinking locally label concealed whether the app was working. This
iteration makes actual execution visible in the ongoing conversation.

## Interaction

AA01. Place one compact activity disclosure immediately below the request it
belongs to. While preparing admission, show the same live treatment at the end
of the originating conversation. Never attach one request's progress to another
conversation or a newer request.

AA02. The collapsed row shows the current real phase, elapsed time and Stop.
A restrained shimmer passes across the phase text while work is active. It is
an indeterminate activity signal, not a percentage, countdown or success claim.
Use native SwiftUI, semantic colors, keyboard controls and accessible labels.
No new web UI dependency. Reduce Motion, increased contrast and inactive scenes
use fully readable static text. Stop immediately changes the label to Stopping
and prevents late callbacks from restoring a working label.

AA03. Model checking/loading, context preparation, generation and actual tool
dispatch update the row. Native committed token events distinguish reasoning
from response preparation and show counts in expanded details at a bounded update
rate. Keep the collapsed phase label brief. Counts are
generated tokens for the current model call, not a forecast or throughput claim.
Do not expose raw private reasoning or generate extra model calls to invent a
progress narrative. Useful user-facing reasoning belongs in the final answer;
activity is a truthful execution summary.

AA04. Expansion shows ordered real tool steps with completed, failed or no-final-
receipt states. Include the actual search terms, inspected originals, result
summaries and optional exact input/result inspection. Large results use the
existing bounded receipt pager. A zero-hit page proves no exhaustive absence.
A tool completion means its receipt is saved, not that its content is true or a
consequential business change was accepted. Interrupted prepared work may have
partial effects; never replay it automatically or call it successful.

AA05. After completion, collapse remains user-controlled. Show Finished, Needs
your review, Stopped, Interrupted, Continued in a thread or Stopped with an error
from saved run state. Completed steps remain inspectable after close/reopen and
in portable copies. A running journal entry without a live owner is Unfinished
run, with no shimmer. Model identity is optional disclosure, not default clutter.
The existing full assistant answer/error remains a separate message.

## Data and lifecycle

AA06. Reuse run_requests, agent_runs and tool_calls as authority. Add no parallel
activity ledger or schema migration. The coherent workspace snapshot projects
only visible request IDs in the current conversation, ordered tool receipts and
bounded label fields and small complete results, with a 512 KiB aggregate result
budget. Exact inputs are fetched only when a receipt is opened. More than 64 steps
per request is explicitly indicated;
large results are loaded on demand. Original model reasoning stays ephemeral,
consistent with [[records/specs/intelligence]].

AA07. Admission reports exact request/run identity to the native window. Existing
workspace-operation ownership fences reject late progress after Stop, completion,
window closure or workbook changes. Streaming progress never writes tokens to the
database and does not rebuild unchanged history. Browsing, citations, scrolling
and Stop remain available while inference runs. Existing review and action
permissions are unchanged.

AA08. User-facing structured information is native content, never a raw JSON
dump. Saved reads show document excerpts, row reads show a table and searches
show titled matches. Other results and request fields use labeled values and
expandable lists/objects. Identifiers stay in optional detail. Preserve codes,
full numeric precision, false, zero, missing and empty as distinct values.
Workflow diagnostic responses use the same presentation while retaining their
unvalidated status. Valid imported JSON files use the structured viewer; invalid
or over-1-MB files explain the preview limit and keep the original available.
No raw JSON toggle is added to the app. The machine-readable CLI stays JSON.

Wide collections reveal 20 fields/entries at a time, long text expands on demand
and deeply nested data requires explicit exploration after eight levels. Large
saved results use exact receipt paths, bounded pages and Back to result. No
serialization into a clipped text block and no silent omission presented as
complete content. No model call is needed to format or explain data.

## Design review

First-principles pass: the user needs to know whether work is alive, what it is
using and how to interrupt it. A moving label alone answers only the first part;
a default diagnostic dump obscures the work. A compact disclosure provides both
levels without displacing the workbook.

Adversarial pass: animation must not simulate progress, searches must not imply
coverage, a failed call must not become a checkmark, saved running work must not
animate forever after reopening, cancelled callbacks must not revive the label,
and large receipts must not load unbounded text into the conversation.

Reference review: Vercel's [collapsible activity steps](https://elements.ai-sdk.dev/components/chain-of-thought)
separate active/completed/pending steps and optional detail. Its
[text shimmer](https://elements.ai-sdk.dev/components/shimmer) demonstrates a
small indeterminate text signal. These are interaction references, not packages
or dependencies. Native implementation and truthful receipt authority are Sevra's
choices. This does not establish a latency or correctness improvement.

## Verification

Focused acceptance covers exact request/conversation scope, prepared/failed/
cancelled outcomes, close/reopen, large result paging, unchanged snapshot polling,
Stop/late progress, native build and actual visible local-model activity.
Structured presentation additionally covers codes and precision, false/empty/
missing values, nested data, saved-result exploration and visible native views. Reuse
unchanged engine grammar, storage reconstruction, portable-copy and installer
proof only where their code boundaries remain unchanged. Record exact outcomes
and limitations in [[records/operations/implementation]].

Parent contracts: [[records/specs/product]], [[records/specs/conversation-context]],
[[records/specs/intelligence]] and [[records/specs/mvp-delivery]].
