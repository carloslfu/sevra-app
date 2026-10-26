---
type: spec
meta-type: conclusion
id: 01m5wps1qcharh0qv8vq40wbjr
created: 2026-10-26T18:15:17.996137+00:00
updated: 2026-10-26T20:39:53.630815+00:00
summary: Python-free Swift integration of pinned upstream Splash, explicit behavior mapping, differential verification and measured adoption gates.
title: Native Splash integration and upgrades
status: reviewed
---
# Native Splash integration and upgrades

Revision 4, October 26, 2026. Owner-approved direction; integration not yet qualified.
Authority: [[sources/notes/2026/10/workbook-primary-splash-direction]].
The existing Slotstream build is a preserved baseline, not the future architecture.

## Product boundary

I01. Reuse upstream Splash C++/Objective-C++/Metal implementation unchanged. Sevra
owns the Swift product, workbook agent and integration. Do not port inference,
attention, expert routing, speculative verification or GPU scheduling to Swift.
No runtime Python interpreter, Python server, HTTP proxy or implicit cloud fallback.
Upstream Python is allowed only in development/reference verification tools.
I02. Initial candidate is Splash 1.4.1, commit
`1744cfafee415fb463b289449cec59a864e768e9`, released October 26. Pin source,
runtime archive digest and source-to-binary identity. Retain upstream licenses.
Do not fetch a moving branch at app startup. Follow newer releases through I11.
I03. Initial implementation uses Splash's native executable and binary protocol
through private stdin/stdout pipes. Swift owns lifecycle, isolation and framing;
the native helper owns inference and its existing loop. This avoids rewriting
bootstrap and isolates fatal engine failures. No listening socket. Direct linking
through a small C/Objective-C++ bridge remains optional after measured justification.
Both choices satisfy the owner direction; one production path ships.
I04. Keep Qwen3.6-35B-A3B 4-bit and its matching DFlash2 draft as the first model.
Pin the original target and draft bytes. No model catalog, unrelated weights or
automatic model change accompanies the engine migration. Model data stays outside
workbooks. Keep the old installation usable until the new one verifies.

## Swift responsibilities

I05. Native model setup downloads verified files, resumes and cancels safely,
checks space, and atomically prepares the metadata/layout Splash expects. Match
upstream's selected-model validation and source identities. Reuse original weight
files when compatible. Do not bypass preparation by depending on a developer's
Python-created directory. All normal user setup must work without Python.
I06. Render the selected model's actual chat template, tokenize and incrementally
decode in Swift using maintained libraries where suitable. Compare prompt token
IDs, special tokens, Unicode, system/tool/history formatting and truncation with
the pinned upstream frontend. Never silently substitute a handwritten approximation.
I07. Native transport must reject bad versions, oversized frames, invalid IDs,
duplicate/gapped tokens and unexpected terminal events. Bound buffers, deadlines
and result sizes. Model completion, truncation, cancellation, memory refusal and
engine failure have distinct app states. Kill only a helper owned by this app;
drain its pipes and reap it on exit. A failed helper must not damage the workbook.
I08. Match reasoning/stop parsing, tool schemas and streaming tool-call assembly.
Validate arguments and existing workbook authority rules. Reuse the workbook's
typed tools and persisted traces. Constrained JSON requires a native grammar/mask
implementation compatible with speculative token masks; post-hoc JSON validation
is not equivalent. No constrained-output support claim until that gate passes.
I09. Preserve one active workbook inference run, cancellation, idle release,
memory-pressure handling, context limits and model status. The native engine's
allocation limit is not total process footprint: measure the Swift process plus
helper and remaining host headroom. Native failure and restart preserve proposals
and last accepted data. Never silently replay an accepted mutation.

## Native grammar implementation

I14. The candidate uses pinned LLGuidance 1.8.0 through its C ABI. This is the
native Rust grammar library already used by the Splash reference, not another
inference engine. Swift owns its tokenizer callback, byte vocabulary, per-request
matcher state, cache and speculative masks. No Python extension or interpreter
loads in the native process. Pin source, Cargo.lock, Rust toolchain and copied
header in integration/llguidance.json. The C header and MIT notice are retained.

The default C tokenizer.json path and the reference HF adapter do not have
identical special-token rules. Swift must reproduce the latter, including added
<...> tokens and padded vocabulary entries. Compare the byte vocabulary for every
token and the full bitmask bytes. Match the reference's stopped-EOS handling.
Speculative prefixes use cloned state; rejected proposals never advance committed
state. Every final generated batch is checked after the last mask.

The candidate is loaded only from an explicit trusted, hash-verified native library
path. Never accept that path from workbook content or model output. Cache at most
32 immutable grammar states within an 8 MiB source budget; each run gets its own
clone. Compiler limits remain enabled; suppress detailed grammar/output dumps in
errors. Bound simulation to eight tokens and validate mask dimensions exactly.

The pinned Rust toolchain is a contributor build/check dependency. Native library
packaging, all transitive license notices, signed-library identity and production
app wiring remain part of I12's adoption gate. Current app installation does not
need Rust or the candidate library. A direct C ABI does not imply that arbitrary
upstream Python tool/schema semantics have already been ported.

## Streaming output and tool candidates

I15. Decode committed tokens incrementally using the selected ByteLevel vocabulary.
Match the pinned reference's special-token rules, incomplete UTF-8 behavior and
stop sequences. Grammar-special markers are not necessarily tokenizer-special
markers; an ordinary 0xff byte is not a grammar sentinel. Preserve exact Unicode
bytes and avoid full-response redecoding on every token. Share the immutable
vocabulary across requests and bound output to 2 MiB.

Separate reasoning from visible text and parse Qwen's XML tool framing across
arbitrary chunk boundaries. Structured JSON keeps marker strings as data. Keep
string parameters verbatim and project typed values according to their declared
types. The initial workbook projection supports app-owned ASCII names, explicit
parameter types and no undeclared parameters. It is not an implementation of
all upstream schema composition, arbitrary tool metadata or API protocols.

Only a verified successful native terminal can return tool candidates. Cancellation,
truncation, errors and caller stop sequences authorize no calls, including calls
that closed before the interruption. Refuse unfinished framing, unknown names and
duplicate parameters instead of applying upstream's permissive repair. Cap calls
at 16, each argument object/parameter at 256 KiB and JSON nesting at 32. Integer
tokens must first fit Int64; workbook arguments also obey I16's exact-range gate.
Exact decimals and larger identifiers use strings. Reject lossy conversion before
Foundation JSON parsing and before dispatch into workbook storage.

A projected candidate is not yet a validated or authorized action. Validate the
complete schema, required fields, semantic limits, evidence references and workbook
permissions before dispatch. The existing proposal/review/accept contracts remain
in force. The workbook agent adapter must complete this gate before production adoption.

## Workbook tool schema contract

I16. Build grammars from the actual NativeTools declarations. The prompt, grammar,
output projection and terminal validator share one normalized schema. Keep the
normalized fixture checked against those declarations so a copied schema cannot
drift. Apply the selected Qwen XML framing and pinned upstream grammar conventions,
including required, automatic and named single-call choices and optional reasoning.

Preserve JSON Schema's default-open nested objects explicitly before strict
normalization. Table rows, cell edits, named calculation values and record data
must retain arbitrary application data keys. Top-level tool arguments remain
closed. These normalized inputs are identical in the Swift/reference comparison.
No implicit closure of a nested row may discard or prohibit its columns.

The native dialect supports explicit JSON types, nested properties/required and
additionalProperties, arrays/items, enum/const, string and array size bounds,
and numeric bounds. Schema depth is at most 24 with 32,768 visited nodes; tool
names and top-level parameter names use the app's bounded ASCII identifiers.
References, composition and unknown keywords fail setup instead of being ignored.
This bounded contract covers all current workbook tools; it is not a general
replacement for a complete JSON Schema validator.

After successful generation and final grammar validation, check required fields,
exact types, bounds, enums, constants and additional properties before dispatch.
Booleans must not compare equal to numeric constants. The workbook's current JSON
Value representation uses Double, so integer arguments beyond ±9,007,199,254,740,991
are refused before dispatch; larger identifiers and precise decimal values must
be strings. Domain rules, evidence checks and user authority remain separate and
are still required. Model calls can create proposals; human acceptance remains a
separate operation. Cancellation/truncation cannot dispatch a previously closed call.

Tool-history rendering must preserve nested nulls. Bridge NSNull to the maintained
Swift Jinja library's boxed-nil representation, after input bounds validation,
and verify exact prompt token IDs against the upstream template.

## Verification and performance

I10. Use a recorded differential suite against the pinned upstream server, with
Python only in the reference environment. First verify transport goldens and exact
prompt IDs; then compare outputs, tool arguments and terminal behavior. For exact
generation comparison fix seed/sampling, verification rows, cache history and
numerical formats. Adaptive scheduling may change output, so record that setting
and use semantic/workflow checks separately. No vague claim of universal parity.

Required cases: cold/warm load, plain/Unicode chat, multiple turns, tool calls and
tool results, malformed output, constrained JSON, cancellation plus a next request,
context overflow plus recovery, absent/corrupt model, missing kernels, child exit,
memory refusal, repeated runs and workbook import/search/read/cite/propose/accept.
Fixtures are synthetic. Same requests must reach the same model configuration.

Preregister matched hardware, weights/quantization, draft, context, prompt/output
length, cache state, memory/SSD budget, power/thermal state and concurrent load.
Use interleaved runs with cold setup separated from warmed serving. Report
first-token latency, complete request and workbook-job latency, decode/prefill
throughput, memory and failures, not only tokens/s. Whole-protocol paging/thermal
exclusions stay recorded. A provisional adoption gate is no >5% median regression
in complete request time on each declared workload, no >10% p95 regression, and
no behavior regression; require enough repetitions to expose variation. A speedup
claim needs repeatable complete-workflow evidence. Python removal alone proves none.

## Upstream maintenance

I11. `skills/update-splash/SKILL.md` owns the agent workflow. Keep a machine-readable
pin and a mapping from upstream files to Swift counterparts, tests and unsupported
features. The update process fetches an isolated source snapshot, verifies identity,
reviews release/diff changes, records affected surfaces, updates in small steps,
runs the relevant differential/core/real-model/install gates, and records retained
failures. A new version stays a candidate until the gates pass. Preserve the prior
pin and measured baseline. No unattended recurring task or automatic promotion.
I12. Source/runtime dependencies remain reproducible from public URLs. Package only
native artifacts and required tokenizer/grammar resources. Scan shipped contents
and loaded processes to prove no Python or MLX inference runtime is present in
the final Splash product. Source/build tooling may use Python and is documented.
The current Slotstream build must remain explicitly labeled during transition.
I13. Splash's current floor is Apple M3 or newer and macOS 26.4+. Detect capability
before model setup; do not retain the old unconditional macOS 14 inference claim.
Qualify physical hardware individually. Source builds need suitable Metal tooling;
verified upstream prebuilt kernels/runtime are allowed where tools are unavailable.

## Ordered checkpoints

1. Preserve and validate the current workbook baseline; update context and records.
2. Fetch pinned source/runtime, map frontend responsibilities, add upgrade tooling.
3. Implement/test native framing and lifecycle with upstream protocol goldens.
4. Implement selected-model preparation, tokenization and streaming equivalence.
5. Integrate agent tools and native constraints; exercise failures and recovery.
6. Run matched model/workbook comparisons; fix regressions before adoption.
7. Remove Slotstream/MLX product dependencies, package, test a clean install and UI.
8. Publish honest measured support/limits and an explicitly qualified release.

Record each checkpoint in [[records/operations/implementation]] and the append-only
log. This plan does not remove existing product acceptance journeys J01–J09.
