---
type: operational
id: 01m7p8m11gxyx98gpf1pat952y
created: 2026-11-18T02:43:50.448918+00:00
updated: 2026-11-18T13:46:19.813921+00:00
summary: 'Plan to open rare tool groups on their first read, with no separate router: measured prompt costs, tool inventory, compatibility checks and replay gates.'
title: Scope native chat prompts by request
---
# Scope native chat prompts by request

Owner direction: [[sources/notes/2026/11/chat-tool-routing-direction]]. Evidence: [[records/research/chat-tool-selection]].

Reviewed against the agent code at `a41c05e0b2894d4e24bd3a87445f423cd6b9b227`. The tool inventory, per-schema token counts and research are complete. No candidate code exists. Runtime quality and latency qualification are pending.

## Decision

Add no router. Give every ordinary chat request a smaller prompt, and let the model's own first read bring in the rest.

Of the 55 schemas in an ordinary first decision, 21 only matter for two jobs: changing saved views, and working with saved behaviors (definitions, templates, workflows and automations). They hold 3,220 of the 7,305 schema tokens. They leave the default prompt. A group comes back for the rest of the run when the model makes the read that job already starts with.

| Group | Opens after a successful | Schemas | Tokens removed from the default |
| --- | --- | ---: | ---: |
| Views | `spaces` | 6 | 1,971 |
| Saved behaviors | `find_definitions` or `definition_registry` | 15 | 1,249 |

The app already works this way for mini apps: a successful `native_app_sdk` or `read_native_app` makes `save_native_app` available for the rest of the run. This plan gives two more groups the same switch.

The route is the model's first tool call, made with the request, the history and the visible context in view. There is no phrase list to maintain in each language, no second model call, and no wrong route that leaves a request without its tool.

What a request that opens nothing would carry. The "after" columns are sums of per-schema counts. A rendered candidate must confirm them.

| Context | Schemas now | After | Schema tokens now | After |
| --- | ---: | ---: | ---: | ---: |
| First main-chat decision | 55 | 34 | 7,305 | about 4,085 |
| Read-only main chat | 34 | 24 | 3,755 | about 2,920 |
| Side thread | 58 | 37 | 7,500 | about 4,280 |
| Main chat during mini-app authoring | 56 | 35 | 8,543 | about 5,320 |

The prompt ahead of history for an ordinary request falls from 10,989 tokens to about 7,800, and to about 7,200 once step 3 moves the matching instructions.

### Why not a router

- **A text match that picks a tool list.** It adds no model call. It must also be right before the model has read anything, in English and Spanish, for requests whose needs appear mid-task. Keyword matching is the weakest selector wherever it has been measured, and a miss removes the needed tool with nothing to recover it. The chat template puts tools first, so each tool list is a different prompt from its first tokens, and alternating lists re-prefills everything after. The agent's one text rule, `RequestRestrictions`, describes itself as a denial rule and "not a general intent classifier". The hardcoded greeting matcher was removed on November 17.
- **A separate model call that picks a tool list.** On the test Mac a later decision pays about 1.5 seconds of prefill before it generates anything. A routing call would cost every turn at least that, to remove tokens that cost nothing measurable on a warm turn. GitHub replaced model-based tool grouping because it was slow and unreliable, and none of the vendor guidance reviewed recommends a per-request call that rewrites the tool list.
- **An embedding or classifier selector.** It needs a second model on the device and in-domain training to beat showing everything. In the closest published case, 16 tools on a Mac, plain embedding retrieval lowered task success by 4 to 5 points. For Qwen3 8B and 14B at 17 to 41 tools, a selector that removed tools lowered selection accuracy on three of four test sets.

### What this buys, and what it does not

- **Warm turns: no time expected.** In the retained trace a warm greeting resumed all 10,976 prefix tokens. Its 6.26 seconds went to 2.42 seconds of prefill for the changed tail and 3.47 seconds of generation. A schema in a resumed prefix is close to free.
- **Cold starts: about 2 seconds less priming.** The shared header and scope block are primed after engine start and after the ten-minute idle release. This is arithmetic from the observed rate, 4,969 tokens in 3.33 seconds.
- **Room.** 3,220 more tokens for history and evidence on every ordinary prompt before context maintenance.
- **Focus.** The model chooses among 34 tools, not 55. Published tests show small models choose worse as the list grows.
- **Cost.** A job pays one more decision, an estimated 4 seconds on the test Mac, when it needs a group and would not otherwise read first: creating a view without reading `spaces`, or pinning the active view. Opening a group also re-prefills the run's tail once, an estimated 1 to 2 seconds. Both land on jobs that already take several decisions.
- **Not addressed.** Generation time and the changed tail dominate warm turns. They belong to [[records/plans/conversation-latency-fix]].

### What this replaces

The greeting scope and the stock scope from the earlier revision are withdrawn. A finish-only prompt has a different first schema, so it cannot resume the shared header and needs its own checkpoint. It removes tokens that are free on a warm turn, for four words in two languages. The stock scope has the same shape and adds subject binding and evidence recovery. Both requests get the smaller default instead. The stock and greeting replays stay as controls. A one-decision greeting remains a later candidate in step 4.

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

| Part of the first main-chat prompt | Schemas | Tokens | Planned |
| --- | ---: | ---: | --- |
| `finish`, including the template's tool preamble | 1 | 433 | Stays |
| Evidence and calculation reads | 15 | 1,525 | Stays |
| Entry reads: `spaces`, `find_definitions`, `definition_registry`, `native_app_sdk`, `read_native_app` | 5 | 379 | Stays |
| Proposals, `draft`, archive, threads, navigation and the workspace pair | 12 | 1,336 | Stays |
| `request_input` | 1 | 403 | Stays |
| View changes and `space_history` | 6 | 1,971 | Views group |
| Saved-behavior reads and changes | 15 | 1,249 | Saved behaviors group |

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
- **Views group, 6 names** `edit_space` (889 tokens), `save_space` (773), `restore_space`,
  `pin_space`, `set_space_pinned`, `space_history`. `open_space` stays in the default
  because it works from an exact name.
- **Saved behaviors group, 15 names** `evaluate_definition`, `form_template`,
  `inventory_automation_template`, `open_automation`, `prepare_action`, `preview_action`,
  `publish_result`, `read_definition`, `read_workflow`, `receiving_template`,
  `save_definition`, `save_template`, `start_workflow`, `workflow_activity`,
  `workflow_template`.

## 1. Open tool groups on their first read

1. **Declare the groups once.** Add one table beside the tool catalog in `SevraAI`: each
   group's entry tools and members, as listed above. Checks and counts derive from it.
   No second list lives in test code.
2. **Carry open groups as host run state.** Add the set to `InferenceMessage` beside
   `nativeAppAuthoring`. It starts empty for each run, sits on the policy message, and is
   re-attached after [ContextMaintenance.swift](../../../Sources/SevraAI/ContextMaintenance.swift)
   the way `enableNativeAppAuthoring` does it. It is never inferred from model prose,
   history or tool output.
3. **Filter in one place.** `NativeTools.referenceDefinitions` drops the members of a closed
   group, where it already drops `save_native_app` outside authoring. The displayed tool
   list and the executable grammar both come from this function, so they cannot disagree.
   Apply the filter to the ordinary chat scopes only: `all`, `answer`,
   `conversationAnswer` and their bounded forms. Handoff, Excel, review and interpretation
   scopes keep today's declarations. Where such a scope allows a member, as `save_space`
   and `propose_record` do, its group starts open.
4. **Keep the shared header identical.** In `NativePreparedRequest`, list group members with
   the scope block's additional tools and never in the template's tool block. The shared
   header is then the same tokens for every ordinary turn, whatever is open.
5. **Open on a successful entry read.** In `WorkbookAgent.runPhase`, beside the mini-app
   switch, add a group when one of its entry tools succeeds. An empty list is a success. A
   failed call opens nothing. The read-only restriction still filters writes, so a
   read-only request that opens Views sees only `space_history`.
6. **Leave authority alone.** Groups decide what is offered, not what is permitted.
   `toolScope.allows`, the read-only denial in `WorkbookTools`, confirmations and receipts
   do not change. Scripted fixtures that call a member directly keep working.
7. **Tell the model once.** Add one sentence to the stable policy naming the three entry
   reads and what each makes available. Leave the existing scope instructions in place for
   this step, so a behavior change can be traced to the schemas alone.
8. **Do not prime a scope block that first appears mid-run.** `primePrefix` would treat an
   opened block as a new checkpoint and spend an extra round trip on it. The run's own
   state already covers its later steps.

## 2. Qualify it on the current engine

- **Surfaces, CPU only.** Extend the all-scope check in `checkConversationSurfaces` to compare
  baseline and candidate tool schemas, executable names and permitted workspace operations
  with the production serializers on both builds. With every group open, each ordinary
  scope must equal the baseline exactly. With none open it must equal the baseline minus
  the declared members. Every other scope must be identical. Cover ordinary and read-only
  main chat, side threads, authoring, clarification off and on, and known and absent
  history references. A names-only comparison would miss changes to operation or citation
  choices. Reuse the named app action, exact-ID, receipt and approval checks.
- **Accounting, CPU only.** Extend [ContextAccountingProbe.swift](../../../IntegrationTests/Agent/ContextAccountingProbe.swift)
  to confirm the shared header tokens are identical across every open state, compare
  prepared and canonical tokens, and record rendered schema tokens for each context in
  place of the computed figures above.
- **Reach, real model.** For each group, in English and Spanish, on both builds: create a
  view, change an existing view, pin the active view, restore a layout; save a receiving
  template, create an inventory rule, start a workflow, inspect a workflow run; and one
  read-only explanation each. A case passes when it reaches the same final tool and saved
  result as the baseline with at most one added decision, and never answers that the app
  cannot do it. Stock, supplier comparison, a movement proposal, a draft, a new thread and
  a greeting must open no group. Run the existing live probes for these areas on both
  builds: `--home-live`, `--automation-authoring`, `--intake-authoring`, `--workflow-tools`,
  `--application-tools`, `--request-handoff` and `--conversation-actions`.
- **Replay, real model, one idle Mac.** Reuse
  `--conversation-cache-trace MODELS_ROOT GUIDANCE_LIBRARY SPLASH_EXECUTABLE NEW_OUTPUT_DIRECTORY`
  for matched cold, warm and mixed-scope sequences on both builds, and add one
  view-creating turn and one saved-behavior turn. Record prompt tokens, resumed tokens,
  primes, prefill, generation, decisions and wall time. Report each group opening and what
  it cost.
- **Enable when** the surface and accounting checks pass, every reach case passes, ordinary
  turns carry fewer prompt tokens and less cold priming, and the matched replay shows no
  reproducible warm regression. A group that fails its reach cases stays in the default
  prompt and the other can still ship. Run `--conversation-latency-checks`,
  `--conversation-surfaces` and `--chat-checks`, rebuild the db.md index and run
  `scripts/check.sh` before publishing the accepted code. Record the exact code identities,
  commands and results here.

## 3. Move group instructions with their group

The scope instructions are 837 tokens. Of these, 617 only guide the three on-demand jobs:
views 189, saved behaviors 321 and mini-app authoring 107. After step 2 passes, render each
of those paragraphs only while its group is open. The stable policy sentence from step 1
keeps the entry reads visible.

The ordinary scope block then falls to about 1,960 tokens, under the 2,048-token minimum
for a second checkpoint in `primePrefix`. Lower that minimum in the same change so ordinary
turns keep resuming their scope block. Gate it with the step 2 reach cases and replay.
Restore any paragraph whose move changes an ordinary outcome.

## 4. Choose later changes from the replay

- **One-decision greeting.** If a greeting still takes more than one decision, restrict the
  callable set to `finish` in the grammar over the unchanged prompt. This removes no tokens
  and needs no new prefix. It still needs a text match, so it waits for evidence.
- **Open a group from host state.** When the visible context already names an active view,
  the host can open Views at the start and save the extra decision. Use host state only,
  never request text.
- **Deliver an opened group after its entry result.** This avoids the tail re-prefill. It
  must survive context maintenance, and an earlier layout with schemas after history
  produced unnecessary tool calls in one replay.
- **Compact shared header.** The 31 shared schemas count 3,169 tokens as the template
  renders them and 2,273 as the compact JSON the scope block already uses. The model was
  trained on the template form, so compare actions and arguments before adopting it.
- **Largest remaining schemas.** `finish` 433 and `request_input` 403.
- **Stable policy.** It is 2,886 tokens. Some paragraphs serve one tool family and could
  move beside it under the same gate as step 3.
- **A learned selector.** Consider an embedding or classifier selector only if measured
  ordinary prompts still carry substantial avoidable schemas after these steps. It would
  need its own quality comparison and would still use the host's evidence and permission
  rules.

## Review passes

1. Traced the composer, CLI, lease, request Source, context rebuild, tool filtering,
   native grammar, capacity, reasoning and Splash dispatch.
2. Followed the exact ledger lookup, receipts, projection, repeat reuse, finish
   validation and stopped-run recovery through the fallback boundary.
3. Added matched warm and mixed replays after checking how changing the offered
   schemas affects the cache prefix.
4. Enumerated every native inference scope against the current executable tool
   policies and measured the actual prompt template.
5. Rebuilt the cost model from the retained per-call trace: resumed prefix tokens,
   changed tail, priming and generation for each decision.
6. Counted every schema and each scope instruction with the production serializer and
   tokenizer, and checked the sums against the earlier scope totals.
7. Compared a text match, a routing model call, a learned selector, grammar restriction
   and on-demand groups against published practice and measurements.
8. Checked the design against the mini-app switch, the shared-header layout, checkpoint
   priming, handoff scopes, read-only filtering and context maintenance.
