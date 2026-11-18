---
type: operational
id: 01m7p8m11gxyx98gpf1pat952y
created: 2026-11-18T02:43:50.448918+00:00
updated: 2026-11-18T02:43:50.448918+00:00
summary: Implementation-ready plan for two narrow native chat tool scopes, existing evidence recovery, and measured prompt and latency comparison.
title: Scope native chat prompts by request
---
# Scope native chat prompts by request

Reviewed against source commit `a41c05e0b2894d4e24bd3a87445f423cd6b9b227`. Code changes and
performance qualification are pending.

## Decision

Choose smaller tool sets in Swift for two kinds of new main-chat turns. Let the same Qwen3.6
model generate the reply and choose the tool calls through Splash 1.6.1. Keep the current
model pack, DFlash 2, context capacity, saved history and workbook rules. Qualify the
greeting route and the stock route separately so either can ship on its own.

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

## 1. Select a route once

In `WorkbookAgent.runPhase`, select from the original submitted text after the host has
resolved mode and continuation state. Apply the two routes only to new interactive main-chat
turns with no handoff, saved answer or Excel conversion. If `unreadStoppedRequest`
identifies the immediately preceding stopped turn, use the ordinary path so the existing
recovery can ask for its history. Choose the route before the first context-maintenance
call. Preserve the submitted text exactly in both the request and its saved Source.

| Eligible submission | Scope | Completion |
| --- | --- | --- |
| The entire trimmed message is `hi`, `hello`, `hey` or `hola`, ignoring case and trailing `.`, `!` or `?` | `.greeting` with `finish` | A model-generated greeting with `basis=general` and empty citations. |
| One of the two stock questions below with the permitted read-only ending, and `RequestRestrictions` already marks it read-only | `.stockAnswer` with `balance` and `finish` | A checked balance for the extracted subject, then a model-generated answer with the host’s calculation citations. |
| Everything else | Current admission and scope selection | Current run, tool discovery and authority rules. |

Match the entire stock submission against these forms.

- `What is the current stock of <subject>?`
- `How many <subject> are currently in stock?`

Require the final sentence `Do not change the workbook.` or `No changes.`. Allow
`Use the balance tool and cite the evidence.` immediately before it. Match the
fixed wording case-insensitively and trim surrounding whitespace. Admit a
nonempty subject made of letters, digits, spaces and hyphens. Preserve its case
and spelling. Compound subjects containing `and`, `or` or `then`, extra clauses
and other phrasings use the ordinary path. This first scope covers the measured
requests and ordinary variants that explicitly ask to leave the workbook alone.

Implement one private matcher and two cases in `InferenceToolScope`. Both cases exclude
`request_input` and workspace operations by construction. Use the same route scope in native
preparation and the dispatch guard. Leave the existing scope resolution for unmatched turns
intact. Excel, handoff, inspection, workflow and repeat-calculation scopes take precedence.
The runner can drop the route once during recovery and does not select it again from model
text, history, selected content or tool output.

## 2. Run the existing loop

- Keep the shared prompt policy, context reconstruction and exact-ID checks. Apply one short guidance sentence per narrow scope in `NativePreparedRequest`, before volatile state. Ask for a simple general greeting in `.greeting`. In `.stockAnswer`, call `balance` for the exact requested subject, then use its quantity with `finish` and let the host attach its inputs. Keep both stock schemas across the two decisions to give them the same stable prefix.
- Preserve the present short budgets when the engine is configured for bounded reasoning. Extend the existing 64-token initial-decision and 128-token verified-calculation checks to the relevant new scopes. Leave ordinary retries, existing `.finish` and other phases with their current budgets. Keep the output cap, result and recovery reserves, and the existing cache priming policy.
- For a scoped `balance`, check the arguments against the extracted subject with the same Unicode normalization as the ledger, before calling `WorkbookTools`. A wrong subject goes through the existing failed-tool receipt path. Use the existing verified calculation handling to attach the basis and effects. A zero quantity or an opening basis with zero effects is a valid result. The happy path executes one balance through the existing tool and takes two model decisions. The existing duplicate-reuse rule still handles exact repeats with the original receipt and bounded retries.
- Add the route’s completion check to the existing `finish` validation. A greeting needs a nonempty general answer with empty citations. Stock needs `basis=evidence` and the quantity from a visible, successful matching balance in this run. Use `numericValues` to check that the quantity appears in the answer. Tying that check to the exact subject and current-run receipt keeps it independent of any earlier text. Review the prose and units in the real replay. The host attaches the original inputs and runs its current version and citation checks. A premature or unresolved stock finish takes the normal rejected-answer path.
- On missing basis, wrong subject, or a result projection without the necessary quantity and proof, drop the stock route at the existing completed-tool boundary and continue with the ordinary read-only scope. Drop a narrow route when its `finish` is rejected and clear its provisional text before any maintenance. Keep any narrower recovery phase selected by the existing validator, such as `.inspection` for a moved citation. After either transition, use the existing maintenance and admission with that actual next scope before generation. Retain the last complete tool/validation pair and discard any route-specific quantity whose proof is no longer retained. The ordinary run owns any further recovery. Existing non-default phases take precedence and clear the route so it cannot reappear after inspection.
- Keep malformed and truncated response recovery inside its current retry limits. The host guard independently refuses calls outside the chosen scope before dispatch. Cancellation, model failures and irreducible context overflow use the existing terminal paths. A fallback stays in the same run, lease, deadline and step budget with the same read-only restrictions and receipts. The reply still streams through the ordinary provisional path.

## 3. Verify and ship by route

1. Extend the scripted fixtures in [ConversationLatencyChecks.swift](../../../IntegrationTests/Agent/ConversationLatencyChecks.swift). Assert the actual offered scopes, verbatim submission, result and receipts. Keep the existing preview catalog fixtures for submission, streaming and Stop as regression surfaces. Cover English and Spanish greetings, a greeting plus a task, `tell me more`, `tldr`, an explicit continue after Stop, an input answer and a side thread. Cover the two stock forms, exact subject case, valid zero, an unknown subject, a wrong-subject call, a premature finish, a paged result and a moved source. Check that a broad fallback can inspect evidence, that `request_input` and writes cannot execute while narrow, and that a failed narrow step cannot widen a read-only turn into a write. Reuse the current stock, repeated-calculation, conversation-action and cancellation fixtures.
2. Extend [ContextAccountingProbe.swift](../../../IntegrationTests/Agent/ContextAccountingProbe.swift) with both scopes. Assert actual token counts against canonical rendering, exact tool masks and the intended reasoning allowance. Test a fallback near the maintenance threshold with its retained receipt. Measure again after widening and confirm an over-limit request stops through existing diagnostics. Run `--conversation-latency-checks`, `--context-accounting MODELS_ROOT GUIDANCE_LIBRARY OUTPUT`, `--conversation-surfaces` and `--chat-checks` on `sevra-agent-checks`.
3. Compare the implementation against the pre-change native binary on one idle Mac with the same model, engine, context profile and disposable workbook. Reuse `--conversation-cache-trace MODELS_ROOT GUIDANCE_LIBRARY SPLASH_EXECUTABLE NEW_OUTPUT_DIRECTORY` for cold stock, warm stock, consecutive greetings and stock after the pause. Run the original sequence on both builds. For the mixed replay, use the same probe with one ordinary chat turn inserted on both builds. Preserve the baseline’s shared-cache check on the comparable broad sequence. On cross-scope calls, record actual cache matches, including zero, and check warm same-scope reuse separately. Include a desktop-context stock run with the existing `--conversation-desktop-trace` path. Use the existing run diagnostics for the selected scope. Save scope/tool names, total and matched prompt tokens, reasoning tokens, primes and their prefill, executed tool calls, first visible text, wall time and answer/receipt results. Repeat the matched replay to distinguish a regression from timing variation.
4. Accept a route when it sends fewer prompt tokens across the whole turn, preserves task completion and evidence, and shows no reproducible wall-time regression in its warm or mixed replay. Require one model decision and zero `WorkbookTools.execute` calls for the generated greeting. Require one successful balance and a cited response for stock. Verify the fixture’s actual 18 units from its opening 20 and accepted delivery of −2, original item integrity, cancellation and preview clearing. Keep the route out of the default path if the comparison fails. Before publishing the accepted code, rebuild the db.md index and run `scripts/check.sh` on the candidate. Record code identity, exact commands and measured limits in this plan.

## After the first comparison

Use the measured split between schemas, policy, history and tool results to choose the next
change. If schema text still dominates, shorten duplicated descriptions and replay the
existing cases. If a few more clear intents dominate, add their scopes individually. Use a
model-based selector or a deferred tool catalog only if a meaningful share of requests needs
routing that the host cannot resolve reliably with a few rules. Fine-tuning would need its
own data and evaluation and still use host-enforced permissions and evidence. Treat those as
separate experiments after the first comparison.

## Review passes

1. **Request and inference.** Traced the composer, CLI, lease, request source,
   context rebuild, scope filtering, native grammar, sizing, reasoning and
   Splash dispatch. The plan now selects the scope before the first measurement
   and preserves the small reasoning allowance on both narrow paths.
2. **Evidence and recovery.** Traced the exact ledger lookup, failed-tool receipts,
   projection, duplicate reuse, finish validation and stopped-request recovery.
   The plan now binds the lookup to the submitted subject, retains proof across
   fallback, clears rejected previews and uses the current read-only recovery.
3. **Simplicity and verification.** Reduced the change to two scopes and one
   route selection per turn. The plan reuses the existing retry loop and
   measurement probes and accounts for cache misses when switching scopes.
