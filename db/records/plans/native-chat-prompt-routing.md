---
type: operational
id: 01m7p8m11gxyx98gpf1pat952y
created: 2026-11-18T02:43:50.448918+00:00
updated: 2026-11-18T16:40:16.915831+00:00
summary: Superseded by the general chat tools plan. Keeps the description of the current request path and the measured inventory of the 59 chat tools.
title: Scope native chat prompts by request
---
# Scope native chat prompts by request

**Superseded on November 18, 2026 by [[records/plans/general-chat-tools]].** Owner direction: [[sources/notes/2026/11/chat-tool-routing-direction]], then [[sources/notes/2026/11/general-tools-direction]].

This plan first proposed a greeting-only prompt, then two tool groups, Views and Saved behaviors, that would open on their first read. Neither was built. The owner then chose a small set of general tools in place of hiding specific ones, so nothing here is to be implemented.

What stays valid and is used by the new plan:

- The cost model in [[records/research/chat-tool-selection]]: schemas in a resumed prompt cost close to nothing, and a model decision costs seconds.
- The description of the current request path and the inventory of the 59 ordinary chat tools below, measured at code `a41c05e0b2894d4e24bd3a87445f423cd6b9b227`. Since then [[records/plans/conversation-follow-up-cache]] changed how follow-up turns resume, at `dcb111e`.
- The decision to have no router.

## How the request works today

| Boundary | Current code and responsibility |
| --- | --- |
| Composer | [WorkspaceState.swift](../../../Sources/SevraApp/WorkspaceState.swift) handles local commands and approval replies before calling `runChat`. It passes the current text, window context and selection. The window owns progress, provisional text and Stop. |
| Run | [ProductAI.swift](../../../Sources/SevraProduct/ProductAI.swift) serializes inference. [WorkbookAgent.swift](../../../Sources/SevraAI/WorkbookAgent.swift) acquires the inference lease, creates or resumes the durable run and captures the submission as a Request Source. `RequestRestrictions`, the conversation and the current phase constrain each step. |
| Context and tools | [ContextMaintenance.swift](../../../Sources/SevraAI/ContextMaintenance.swift) assembles saved history, current state, the live request and retained tool pairs. [WorkbookInference.swift](../../../Sources/SevraAI/WorkbookInference.swift) and [ToolSerialization.swift](../../../Sources/SevraAI/ToolSerialization.swift) select from the tool catalog. `workspace_actions` discovers operation contracts by domain, `workspace_action` dispatches a named operation, and `app.inspect` finds a mini app’s actions. Those calls still start with the broad chat schemas in the prompt. |
| Prompt layout | [NativePreparedRequest.swift](../../../Sources/SevraNativeAI/NativePreparedRequest.swift) renders a shared header first: the 31 read and finish schemas in the template's tool block, then the stable policy, 6,020 tokens in all. A scope block follows with the scope instructions and the remaining schemas as compact JSON. History, host state and the request come last. The same file builds an executable grammar with exact citation, receipt and reference choices from the same tool list. `save_native_app` is listed only after a successful `native_app_sdk` or `read_native_app`. |
| Native generation | [NativeWorkbookModel.swift](../../../Sources/SevraNativeAI/NativeWorkbookModel.swift) reuses preparation for measurement and dispatch, admits against the live capacity and sends tokens to the Splash helper over [Wire.swift](../../../Sources/SevraSplash/Wire.swift). It primes the shared header, and a scope block of at least 2,048 tokens, as resumable checkpoints, and keeps up to four. Splash streams output, with the host exposing only provisional `finish.answer`. |
| Execute and save | The loop checks the candidate and calls [WorkbookTools](../../../Sources/SevraCore/Tools.swift), [ChatOperations](../../../Sources/SevraCore/ChatOperations.swift) or the authorized window handler. It saves the tool result, projects a bounded copy for inference and repeats. [ToolReceipts.swift](../../../Sources/SevraCore/ToolReceipts.swift) keeps the full result. `finish` validates evidence and saves the answer through [Runs.swift](../../../Sources/SevraCore/Runs.swift). Stop keeps any completed receipts and clears the preview. |
| Other paths | CLI `ask` defaults to noninteractive mode. Side threads share the workbook and have separate history. Saved clarifications and thread handoffs carry the original request. Excel analysis/build, app and movement reviews, workflow interpretation and history summaries already have their own scopes or schema. |

The recorded trace shows a 6,020-token shared prefix and a 10,989-token broad prefix before
the conversation tail. The first cold stock turn used two decisions and took 25.67 seconds.
The warm repeated greeting resumed 10,976 tokens and took 6.26 seconds. Those are individual
observations on the test Mac. [Five-turn
trace](../../../integration/evidence/2026-11-17-native-prompt-cache.json) ·
[[records/plans/conversation-latency-fix]]

## Tool coverage

This inventory comes from the current serializers and their executable policy.
The 59 ordinary tool names are the union across main chat, side threads and authoring.
Eight further tools appear only in specialized phases. Workflow interpretation adds a
separately generated output tool. The 81 workspace operations are nested under
`workspace_action` and discovered through `workspace_actions`. A read-only interactive
turn can expose 26 of them. Named mini-app actions are specific to the selected workbook
and discovered through `app.inspect`. [Tool serialization](../../../Sources/SevraAI/ToolSerialization.swift) ·
[Scope rules](../../../Sources/SevraAI/WorkbookInference.swift) ·
[Workspace operations](../../../Sources/SevraCore/ChatOperations.swift) ·
[Interpretation output](../../../Sources/SevraSplashGrammar/ToolPolicy.swift)

| Native context in the probe | Schemas displayed | Callable with no history reference | Schema tokens |
| --- | ---: | ---: | ---: |
| First main-chat decision | 55 | 54 | 7,305 |
| Read-only main chat | 34 | 33 | 3,755 |
| Side thread | 58 | 57 | 7,500 |
| Main chat during mini-app authoring | 56 | 55 | 8,543 |
| Finish only, using the existing scope with input disabled | 1 | 1 | 433 |

The ordinary main and read-only prompts share 31 displayed schemas at 3,169
tokens. The first main-chat decision adds 24 schemas at 4,136 tokens.
`history_read` stays in the stable prompt vocabulary and becomes callable when
there is an eligible history reference. These are counts from the actual template
and tokenizer with synthetic messages. Schema tokens are the difference from rendering
those messages without tool definitions. The shared header is a cache layout used by
several scopes. There is no tool common to all scopes, including isolated review calls.

A second CPU-only count measured each schema on its own with the same serializer and
tokenizer, and reproduces these totals within the 9-token scope label.
[Per-schema counts](../../../integration/evidence/2026-11-18-chat-tool-schema-tokens/counts.json) ·
[Probe](../../../integration/evidence/2026-11-18-chat-tool-schema-tokens/probe.swift)

| Part of the first main-chat prompt | Schemas | Tokens |
| --- | ---: | ---: |
| `finish`, including the template's tool preamble | 1 | 433 |
| Evidence and calculation reads | 15 | 1,525 |
| Entry reads: `spaces`, `find_definitions`, `definition_registry`, `native_app_sdk`, `read_native_app` | 5 | 379 |
| Proposals, `draft`, archive, threads, navigation and the workspace pair | 12 | 1,336 |
| `request_input` | 1 | 403 |
| View changes and `space_history` | 6 | 1,971 |
| Saved-behavior reads and changes | 15 | 1,249 |

The following lists record the observed names. The serializer stays the authority
for eligibility.

- **31 schemas in the ordinary shared header** `archive_members`, `balance`, `calculate`, `compare_rows`, `count_records`,
  `datasets`, `definition_registry`, `evaluate_definition`, `find_definitions`,
  `finish`, `form_template`, `history_read`, `history_search`,
  `inventory_automation_template`, `lineage`, `native_app_sdk`, `preview_action`,
  `read`, `read_definition`, `read_native_app`, `read_workflow`, `receiving_template`,
  `references`, `review_queue`, `rows`, `search`, `space_history`, `spaces`,
  `tool_result`, `workflow_activity`, `workflow_template`.
- **28 additional ordinary names across contexts** `draft`, `edit_space`, `include_archive_members`, `open_automation`, `open_reviews`,
  `open_space`, `pin_space`, `prepare_action`, `propose_movement`, `propose_record`,
  `propose_table`, `propose_table_edit`, `publish_result`, `rename_current_thread`,
  `request_input`, `restore_space`, `return_to_main`, `review_thread_summary`,
  `save_definition`, `save_native_app`, `save_space`, `save_template`,
  `set_space_pinned`, `start_thread`, `start_thread_and_continue`, `start_workflow`,
  `workspace_action`, `workspace_actions`.
- **8 phase-only names** `compare_excel_behavior`, `describe_excel_workflow`, `inspect_excel_evidence`,
  `inspect_excel_rows`, `prepare_workflow_answer`, `review_action_directions`,
  `review_movement_direction`, `review_native_app`.
- **Separate workflow output** `interpretation_result` has the schema of the saved
  interpretation request. History summarization uses its own structured response.
  `commit_action_preview` is internal dispatch following host review, outside the
  offered tool list.
