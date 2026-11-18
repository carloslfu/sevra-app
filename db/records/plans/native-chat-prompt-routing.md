---
type: operational
id: 01m7p8m11gxyx98gpf1pat952y
created: 2026-11-18T02:43:50.448918+00:00
updated: 2026-11-18T02:57:21.138618+00:00
summary: Greeting-first implementation plan with the full native tool inventory, prompt measurements, compatibility checks and a separate stock candidate.
title: Scope native chat prompts by request
---
# Scope native chat prompts by request

Reviewed against the current agent code at `a41c05e0b2894d4e24bd3a87445f423cd6b9b227`.
The catalog and tokenizer checks are complete. Runtime implementation and latency
qualification are pending.

## Decision

Qualify one Swift-selected tool scope for standalone greetings first. The same Qwen3.6
model generates the reply through Splash 1.6.1. Text for a greeting is still generated
on every turn. The model pack, DFlash 2, history, context capacity and workbook rules
carry through the comparison.

A finish-only prompt used 433 schema tokens in the tokenizer probe, versus 7,305 in
the ordinary first main-chat prompt. That is a worthwhile first experiment with one
existing terminal tool. The current stock path already completes the measured lookup
with a balance and a cited finish. Keep stock as a separate candidate because forcing
a smaller tool set there adds subject binding and evidence recovery.

## How the request works today

| Boundary | Current code and responsibility |
| --- | --- |
| Composer | [WorkspaceState.swift](../../../Sources/SevraApp/WorkspaceState.swift) handles local commands and approval replies before calling `runChat`. It passes the current text, window context and selection. The window owns progress, provisional text and Stop. |
| Run | [ProductAI.swift](../../../Sources/SevraProduct/ProductAI.swift) serializes inference. [WorkbookAgent.swift](../../../Sources/SevraAI/WorkbookAgent.swift) acquires the inference lease, creates or resumes the durable run and captures the submission as a Request Source. `RequestRestrictions`, the conversation and the current phase constrain each step. |
| Context and tools | [ContextMaintenance.swift](../../../Sources/SevraAI/ContextMaintenance.swift) assembles saved history, current state, the live request and retained tool pairs. [WorkbookInference.swift](../../../Sources/SevraAI/WorkbookInference.swift) and [ToolSerialization.swift](../../../Sources/SevraAI/ToolSerialization.swift) select from the tool catalog. `workspace_actions` discovers operation contracts by domain, `workspace_action` dispatches a named operation, and `app.inspect` finds a mini app’s actions. Those calls still start with the broad chat schemas in the prompt. |
| Native generation | [NativePreparedRequest.swift](../../../Sources/SevraNativeAI/NativePreparedRequest.swift) renders the prompt and builds an executable grammar with exact citation, receipt and reference choices. [NativeWorkbookModel.swift](../../../Sources/SevraNativeAI/NativeWorkbookModel.swift) reuses preparation for measurement and dispatch, admits against the live capacity and sends tokens to the Splash helper over [Wire.swift](../../../Sources/SevraSplash/Wire.swift). Splash can resume matching KV pages and streams output, with the host exposing only provisional `finish.answer`. |
| Execute and save | The loop checks the candidate and calls [WorkbookTools](../../../Sources/SevraCore/Tools.swift), [ChatOperations](../../../Sources/SevraCore/ChatOperations.swift) or the authorized window handler. It saves the tool result, projects a bounded copy for inference and repeats. [ToolReceipts.swift](../../../Sources/SevraCore/ToolReceipts.swift) keeps the full result. `finish` validates evidence and saves the answer through [Runs.swift](../../../Sources/SevraCore/Runs.swift). Stop keeps any completed receipts and clears the preview. |
| Other paths | CLI `ask` defaults to noninteractive mode. Side threads share the workbook and have separate history. Saved clarifications and thread handoffs carry the original request. Excel analysis/build, app and movement reviews, workflow interpretation and history summaries already have their own scopes or schema. |

The recorded trace shows a 6,020-token shared prefix and a 10,989-token broad prefix before
the conversation tail. The first cold stock turn used two decisions and took 25.67 seconds.
The warm repeated greeting resumed 10,976 tokens and took 6.26 seconds. Those are individual
observations on the test Mac. Changing the first schema can change the KV prefix even when
the prose is identical. Compare wall time as well as token counts. [Five-turn
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

Extend the existing all-scope check in `checkConversationSurfaces` to compare baseline
and candidate tool schemas, executable names and permitted workspace operations.
Use the production serializers on both builds. Cover ordinary and read-only main chat,
side threads, authoring, clarification off and on, known and absent history references,
and the existing specialized scopes. A names-only comparison would miss changes to
operation or citation choices. For unmatched turns, require the same prompt and
executable declarations with the same inputs. Reuse the named app action, exact-ID,
receipt and approval checks. Generate the comparison from the existing catalog
without maintaining a second list in test code.

## 1. Implement the greeting scope

1. In `WorkbookAgent.runPhase`, match the complete original submission after trimming
   whitespace, folding case and removing trailing `.`, `!` or `?`. The supported words
   are `hi`, `hello`, `hey` and `hola`. Apply this to a new interactive main-chat
   request with no handoff, saved answer or Excel conversion. When the immediately
   preceding run stopped, preserve the normal recovery path using
   `unreadStoppedRequest`. The request and saved Source keep the submitted text.
2. Add `.greeting` to the existing `InferenceToolScope` with exactly `finish`. Use it in
   both native scope resolution and the host dispatch guard, before the first
   `ContextMaintenance.maintain` call. Existing phase overrides keep priority.
   The older `.finish` phase can allow `request_input` after repeated calculations.
   A distinct scope makes greeting admission explicit and keeps that phase's behavior.
3. Add one greeting sentence to the existing scope instructions in
   `NativePreparedRequest`. Use the 64-token reasoning allowance for its first decision
   under the default bounded configuration. Keep the regular renderer, full history,
   output cap, result and recovery reserves, grammar and cache priming. Keep the short
   budget change local to `.greeting`.
4. Use existing `finish` validation and saving. Require a nonempty general answer
   with empty citations. If a candidate fails that validation, clear provisional text,
   drop the greeting scope for the rest of the run, and use the ordinary validation
   receipt and context-maintenance boundary before generating under the wider scope.
   Malformed output, truncation and cancellation use the existing handling and limits.
   The run ID, lease, deadline and step budget carry through. Match the route once
   from the submitted text. History, selection and tool results stay reference data.

## 2. Qualify it on the current engine

- Extend [ConversationLatencyChecks.swift](../../../IntegrationTests/Agent/ConversationLatencyChecks.swift)
  with a generated English greeting and a generated Spanish greeting. Verify the
  exact offered scope and original text. Include a compound greeting with a task,
  `tell me more`, `tldr`, a side thread, saved input and continuation after Stop.
  Check rejected finish, dispatch refusal, preview clearing and a near-threshold
  fallback with the retained validation pair.
- Extend [ContextAccountingProbe.swift](../../../IntegrationTests/Agent/ContextAccountingProbe.swift)
  to compare prepared and canonical tokens for the greeting scope and confirm the
  exact mask and reasoning budget. Replay the current tool-coverage checks.
  Run `--conversation-latency-checks`, `--context-accounting MODELS_ROOT GUIDANCE_LIBRARY OUTPUT`,
  `--conversation-surfaces` and `--chat-checks` on `sevra-agent-checks`.
- Compare the current and candidate native agent builds on one idle Mac. Reuse
  `--conversation-cache-trace MODELS_ROOT GUIDANCE_LIBRARY SPLASH_EXECUTABLE NEW_OUTPUT_DIRECTORY`
  for matched cold, consecutive-greeting and mixed-scope sequences. Include a cold
  start on the greeting itself and a broad request between greetings on both builds.
  Measure actual prompt tokens, total wall time, reasoning, first visible text,
  executed calls, matched KV tokens and explicit primes. Include priming and any
  summary work in the turn totals. Keep the shared-cache check for comparable scopes.
  Report each cross-scope match, including zero.
- Enable the scope when a generated greeting still takes one model decision, runs
  zero `WorkbookTools.execute` calls, reduces the total prompt tokens across the
  turn, and preserves correct broad outcomes with no reproducible latency regression
  in the matched replay. Rebuild the db.md index and run `scripts/check.sh` before
  publishing the accepted code. Record the exact code identities, commands and results here.

## 3. Choose the next change from the replay

**Stock is a separate candidate.** A synthetic two-schema stock prompt measured 504
schema tokens. The existing read-only prompt measured 3,755. That difference alone
says little about the two-call turn when the read-only cache is warm. Exercise the
current stock path as a control. If a second scope is justified, offer `balance` and
`finish` for standalone forms such as `What is the current stock of <subject>?`
and `How many <subject> are currently in stock?` when the existing restriction
recognizer marks the request read-only. Match the whole message and only allow known
read-only and cite-the-balance endings. Bind the exact extracted subject with the
ledger's Unicode normalization. Compare at least one wording outside the recorded
brass-bolt prompt.

Use the existing balance and receipts. Finish from a successful current-run result
for that subject, with its visible quantity and inspected basis and effects, including
a valid zero. A failed lookup, incomplete proof or rejected finish drops the narrow
scope once. Re-admit the ordinary read-only scope at the existing tool or validation
boundary with the retained receipt. Give citation inspection and repeat-calculation
phases priority. Test unknown and wrong subjects, paged results, a moved source,
attempted writes and the successful fixture's 18 units from its opening 20 and
accepted delivery of −2. Use the existing desktop-context trace and a matched mixed
replay before enabling this scope.

**Broad prompt shortening serves more turns.** Emptying the tool-level summaries
mechanically removed 1,003 tokens from the same full main-chat sample. This shows the
size of that prose. A candidate can consolidate genuinely duplicated instructions
while preserving each tool's selection cues and schema. Compare actual actions and
evidence on the broad path before adopting it. Consider a deferred catalog or a
model selector only if measured broad workloads still carry substantial avoidable
context after these smaller steps. The current catalog already defers the nested
operation details. Fine-tuning would need its own quality comparison and would
still use the host's evidence and permission rules.

## Review passes

1. Traced the composer, CLI, lease, request Source, context rebuild, tool filtering,
   native grammar, capacity, reasoning and Splash dispatch.
2. Followed the exact ledger lookup, receipts, projection, repeat reuse, finish
   validation and stopped-run recovery through the fallback boundary.
3. Added matched warm and mixed replays after checking how changing the offered
   schemas affects the cache prefix.
4. Enumerated every native inference scope against the current executable tool
   policies and measured the actual prompt template. Moved stock to a separately
   qualified candidate and added a compatibility check across all current scopes.
