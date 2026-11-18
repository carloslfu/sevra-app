---
type: research
meta-type: conclusion
id: 01m7qe9zymnywsn5h23fqsjq9a
created: 2026-11-18T13:42:27.540409+00:00
updated: 2026-11-18T16:40:32.323914+00:00
summary: 'Local token and timing evidence plus published practice on tool selection: a smaller fixed default with groups opened on first read beats a router here.'
title: Tool selection for the native chat prompt
---
# Tool selection for the native chat prompt

## Scope and provenance

Research for [[records/plans/native-chat-prompt-routing]], requested in [[sources/notes/2026/11/chat-tool-routing-direction]]. That plan was superseded by [[records/plans/general-chat-tools]], which keeps this record's cost model and published evidence and replaces its conclusion about tool groups with a small set of general tools. It answers one question: how should an ordinary chat request get only the tool schemas it needs, and does that call for a router.

There are two kinds of evidence. Local evidence is the retained [five-turn trace](../../../integration/evidence/2026-11-17-native-prompt-cache.json) and a new CPU-only [token count](../../../integration/evidence/2026-11-18-chat-tool-schema-tokens/counts.json) at code `a41c05e0b2894d4e24bd3a87445f423cd6b9b227`. Published evidence was collected on November 18, 2026. Statements about it are paraphrases that keep the numbers their sources give. Most papers cited are preprints. No model ran for this research and no candidate build exists.

## What a tool schema costs on the test Mac

These are single observations from the trace's after-fix replay. Local builds overlapped parts of that run.

| Observation | Value |
| --- | --- |
| Priming the shared header after engine start | 6,020 tokens in 4.33 s |
| Priming the ordinary scope block on its first use | 4,969 further tokens in 3.33 s |
| Warm greeting on the ordinary prompt | 13,569 prompt tokens, 10,976 resumed, 2.42 s prefill for the 2,593 that changed, 3.47 s to generate 125 tokens, 6.26 s wall |
| Warm read-only stock turn, two decisions | 2.32 s and 1.50 s prefill, 2.72 s and 5.88 s generation, 12.73 s wall |
| A later decision in the same run | about 530 new tokens, 1.47 to 1.50 s prefill |
| Generation rate across eight calls | 35 to 45 tokens per second |

Three things follow.

1. A schema inside a resumed prefix costs no measurable time. The warm greeting resumed every prefix token. Its time went to the changed tail and to generation.
2. A schema costs time when its prefix is cold or changes. That happens at engine start, after the ten-minute idle unload, and whenever a turn uses a different tool list.
3. One more model decision costs seconds. A later decision pays about 1.5 s of prefill before it generates anything. At the 64-token reasoning allowance a short tool call adds about 2.4 s of generation. That is roughly 4 s, estimated from these observations.

So a design that changes the tool list between turns, or adds a model call to choose tools, spends more time than the tokens it removes were costing on a warm turn. The gains from a smaller default are less priming on a cold start, more room before context maintenance, and fewer tools to choose from.

## Where the schema tokens are

The count uses the production prompt serializer and the selected tokenizer. It reproduces the plan's scope totals within the 9-token scope label.

| Part of the first main-chat prompt | Schemas | Tokens |
| --- | ---: | ---: |
| Finish, including the template's tool preamble | 1 | 433 |
| Evidence and calculation reads | 15 | 1,525 |
| Entry reads: `spaces`, `find_definitions`, `definition_registry`, `native_app_sdk`, `read_native_app` | 5 | 379 |
| Saved-behavior reads in the shared header | 9 | 752 |
| `space_history` in the shared header | 1 | 80 |
| Proposals, draft, archive, threads, navigation and the workspace pair | 12 | 1,336 |
| `request_input` | 1 | 403 |
| View changes: `edit_space` 889, `save_space` 773 and three small tools | 5 | 1,891 |
| Saved-behavior changes | 6 | 497 |
| Total | 55 | 7,296 |

Two schemas, `edit_space` and `save_space`, hold 1,662 tokens. The tools that only matter for saved views and saved behaviors hold 3,220 tokens across 21 schemas. Tool descriptions are short: 3 to 47 tokens each. The scope policy text is 837 tokens, of which 617 are instructions for views, behaviors and mini-app authoring. The stable policy text is 2,886 tokens.

The shared header is rendered by the chat template at 3,169 tokens. The same 31 schemas as sorted compact JSON, the form the scope block already uses, count 2,273.

## Published practice

- **Do not change the cached tool list mid-conversation.** Anthropic documents that modifying tool definitions invalidates the tools, system and message caches ([tool use with prompt caching](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-use-with-prompt-caching)). OpenAI says to keep tool definitions and order fixed and to restrict callable tools with `allowed_tools` ([prompt caching guide](https://developers.openai.com/api/docs/guides/prompt-caching), [function calling guide](https://developers.openai.com/api/docs/guides/function-calling)). Manus reports that it tried loading tools on demand, then moved to masking token logits over a fixed list, because tool definitions sit at the front of the context and earlier steps that mention removed tools confuse the model ([Manus, July 2025](https://manus.im/blog/Context-Engineering-for-AI-Agents-Lessons-from-Building-Manus)).
- **Large catalogs load on demand, and the model asks.** Anthropic's tool search keeps deferred tools out of the prefix and expands a found tool inline, so the cache survives ([tool search tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool)). OpenAI's tool search injects loaded tools at the end of the context ([tool search guide](https://developers.openai.com/api/docs/guides/tools-tool-search)). Claude Code defers MCP tools by default ([Claude Code MCP](https://code.claude.com/docs/en/mcp)). Cursor keeps tool names in the prompt and full descriptions in files ([Cursor, January 2026](https://cursor.com/blog/dynamic-context-discovery)).
- **Published results.** Anthropic's internal tests: about 77K to 8.7K tokens, and accuracy from 49% to 74% on Opus 4 and 79.5% to 88.1% on Opus 4.5 ([advanced tool use, November 2025](https://www.anthropic.com/engineering/advanced-tool-use)). Cursor's A/B test: 46.9% fewer total tokens in runs that called an MCP tool. Those catalogs are far larger than this app's 7,305 schema tokens. Anthropic's guidance says plain tool calling fits when there are fewer than 10 tools or the definitions are small, and that selection degrades past 30 to 50 tools.
- **A small core stays loaded.** Anthropic keeps the 3 to 5 most-used tools loaded. GitHub Copilot keeps 13 core tools and four expandable groups. OpenAI suggests fewer than 20 functions at the start of a turn.
- **None of the sources read recommends a per-request model call that rewrites the tool list.** GitHub replaced its model-based tool grouping because it was slow, costly and sometimes dropped tools. Its embedding-guided selection covered 94.5% of needed tools, against 87.5% for model-based selection and 69.0% for a static list. Each group expansion still costs a cache miss and an extra round trip ([GitHub, November 2025](https://github.blog/ai-and-ml/github-copilot/how-were-making-github-copilot-smarter-with-fewer-tools/)). Anthropic endorses routing only for clearly distinct request categories with an accurate classifier, and each route is then a separate workflow ([building effective agents](https://www.anthropic.com/engineering/building-effective-agents)).

## Published measurements

- **More tools hurt small models, with no clean threshold.** On BFCL, Qwen2.5-7B falls from 76.95 to 69.24 and Qwen2.5-3B from 70.80 to 53.54 when the candidate list grows to 20 ([Tool-DC](https://arxiv.org/abs/2603.11495)). A 4-bit Llama 3.1 8B on a Jetson failed one query with 46 tools and succeeded with 19 ([Less is More](https://arxiv.org/abs/2411.15399)). At hundreds of tools the drop is severe ([LongFuncEval](https://arxiv.org/abs/2505.10570)).
- **For 8B and larger models at this catalog size, a selector that removes tools can make things worse.** With the full list of 17 to 41 tools, Qwen3 8B picks the right function 70.5% to 93.9% of the time on three TaskBench sets. Both retrievers tested lowered that, for example 93.9 to 91.0 and 75.3. They helped models of 4B and smaller. A removed tool has no recovery path ([DTDR](https://arxiv.org/abs/2512.17052)).
- **Plain embedding retrieval hurt the closest on-device case.** With 16 Mac tools, embedding retrieval had 0.949 recall and lowered success by 4 to 5 points. A classifier fine-tuned on in-domain data reached 0.998 recall, halved the prompt and added 1 to 2 points ([TinyAgent](https://arxiv.org/abs/2409.00608)). That result is English only and needs training data.
- **Retrievers miss, and keyword matching is the weakest.** Off-the-shelf retrievers stay under 52% recall at 10 on ToolRet, and BM25 trails every embedding model ([ToolRet](https://arxiv.org/abs/2503.01763)). Retrieval errors were half of the agent failures in [LiveMCPBench](https://arxiv.org/abs/2508.01780). Static retrieval from the first message can fail before planning starts, and re-retrieving during the task added 26.7 points ([FitText](https://arxiv.org/abs/2605.02411)).
- **A model picking from a list is a weak router. A model stating its need is a good one.** A model-written tool request matched 95.19% against 71.63% for the raw user message ([MCP-Zero](https://arxiv.org/abs/2506.01056)). A prompted 8B model routed three domains at 95.66%, and a 3B model collapsed to 26.37% ([Guarded Query Routing](https://arxiv.org/abs/2505.14524)).
- **Open models manage their own tool list poorly.** Asked to add and remove tools over a long conversation, Llama 3 70B removed 24% of unused tools and reached 0.42 tool correctness ([MemTool](https://arxiv.org/abs/2507.21428)).
- **Spanish changes arguments more than tool choice.** With 55 functions in the prompt, Llama 3.1 8B selected the right function 63.68% of the time in English and 62.11% in Spanish. Full-call accuracy fell from 20.00% to 11.05% ([MASSIVE-Agents](https://aclanthology.org/2025.findings-emnlp.1099/)). These cells were read from the PDF text layer and deserve a second look before reuse.
- **Mechanics.** The Qwen3 template renders tools at the start of the first system block, so a different tool list changes the prompt from its first tokens ([Qwen3 chat template](https://huggingface.co/Qwen/Qwen3-8B/blob/main/tokenizer_config.json)). Local runtimes reuse cached state only for the longest common token prefix ([llama.cpp server](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)). Grammar masks cost tens of microseconds per token ([llguidance](https://github.com/guidance-ai/llguidance)).

## What this supports

| Option | Extra model calls | Effect on the cached prefix | Main failure |
| --- | --- | --- | --- |
| Text match picks a tool list | None | A distinct prefix per list | Misses are silent, need per-language phrase lists, and a removed tool has no recovery |
| Separate model call picks a tool list | One per turn, about 1.5 s or more here | A distinct prefix per list | Weak selection from a list, and the same missing recovery |
| Embedding or classifier selector | None, but a second model on the device | A distinct prefix per list | Needs in-domain training to beat showing everything |
| Fixed prompt, restrict choices in the grammar | None | Unchanged | Removes no tokens |
| Smaller fixed default, groups open when the model makes their first read | None on flows that already start with that read, one otherwise | Shared header unchanged, scope block grows once | The model must make the entry read, which needs its own check |

The last row matches what the app already does for mini apps: reading `native_app_sdk` or `read_native_app` makes `save_native_app` available for the rest of the run. It also matches the published direction: a small fixed core, model-driven loading, nothing removed mid-run.

## Limits

- The timing observations come from one Mac, one trace and synthetic data. The four-second decision cost and the cold-start savings in the plan are arithmetic from them, to be replaced by a matched replay.
- No published test covers a current small local model at about 55 tools, a first-message router's miss rate, Spanish tool routing, or quality when the grammar and the displayed list differ.
- No published test shows a Qwen3 model calling tools defined outside the template's tool block. This app's own replays do: 24 schemas already sit in a later system message and the conversation-action cohort passed with them.
- OpenAI's reported 47% token reduction with tool search could not be confirmed at its primary page and is left out above.
