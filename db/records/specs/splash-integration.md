---
type: spec
meta-type: conclusion
id: 01m5wps1qcharh0qv8vq40wbjr
created: 2026-10-26T18:15:17.996137+00:00
updated: 2026-11-25T03:08:08.668040+00:00
summary: Python-free Swift integration of pinned upstream Splash, explicit behavior mapping, differential verification and measured adoption gates.
title: Native Splash integration and upgrades
status: reviewed
---
# Native Splash integration and upgrades

Revision 13, November 24, 2026. At the owner's word ([[sources/notes/2026/11/splash-1-7-2-upgrade-approval]]) the native preview pin moves to Splash 1.7.2, protocol 15 unchanged. See "Splash 1.7.2, November 24" below.

Revision 12, November 24, 2026. The five follow-ups of the 1.7.1 upgrade landed the same day, at the owner's word: forced tokens (I14), literal control tokens as characters (I06), `head_tokens` for prompts without a prepared header and a header identity without restore-neutral options; `--verify-rows auto` was measured and not taken. See "Follow-ups" under "Splash 1.7.1, November 24".

Revision 11, November 24, 2026. The owner approved [[records/plans/splash-1-7-1-upgrade]] ([[sources/notes/2026/11/splash-1-7-1-upgrade-approval]]): the native preview moves to Splash 1.7.1, protocol 15, with tree grammar masks and one engine lane. See "Splash 1.7.1, November 24" below.

Revision 10, November 16, 2026. The owner authorized a focused preview upgrade and a practical 32K versus 64K comparison. Splash 1.6.1 was installed in the native preview. The source chooses 64K on Macs with at least 48 GiB of unified memory and 32K below that tier, with a 12 GiB engine budget and automatic context maintenance in both cases. The previous 1.4.1 bundle and model selection are backed up. Broader production qualification retains the earlier failures. See [[records/operations/inference-context-execution]].
Authority: [[sources/notes/2026/10/workbook-primary-splash-direction]].
On November 19, 2026, by owner direction, the Slotstream/MLX build and its product dependencies were removed. Native Splash is the only inference engine; the open gates below are unchanged.

## Product boundary

I01. Reuse upstream Splash C++/Objective-C++/Metal implementation unchanged. Sevra
owns the Swift product, workbook agent and integration. Do not port inference,
attention, expert routing, speculative verification or GPU scheduling to Swift.
No runtime Python interpreter, Python server, HTTP proxy or implicit cloud fallback.
Upstream Python is allowed only in development/reference verification tools.
I02. The native preview pin is Splash 1.7.2, commit
`2afc7337aacc044722fa95e4cb3da75c281a19a8`, protocol 15 and status schema 8. The
1.7.1 pin at `1988a72f26a6031127efc29f861bfb46d36286c4` is preserved in
`integration/splash-1.7.1-preserved.json`. The
1.6.1 pin at `d8af1054aab0f97de21d043e01aa98af3754f10e` is preserved in
`integration/splash-1.6.1-preserved.json`, and the initial 1.4.1 pin at
`1744cfafee415fb463b289449cec59a864e768e9` separately. Pin source,
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
The tokenizer library matches added tokens anywhere in a rendered prompt, so a
document could close its turn and open a system one. As Splash 1.7.1's server
(`PromptTokenizer`), every text the template is given is quoted first: messages, tool
arguments and names, and tool definitions. A mark follows each `<` that begins an added
token, whole or cut off by the text's end, and U+0000 becomes U+FFFD. The rendered prompt
is split at the template's own whole added tokens, and each text between them, its marks
removed, encodes as ordinary text, so a literal control token reaches the model as its
characters. swift-transformers finds the pre-tokenizer's pieces with Foundation's
character-based search. Where a character holds several scalars (`❤️<b>`, an accent after
punctuation) that moves a piece's end, so such text is first cut at the split pattern's own
boundaries, matched over scalars as the reference does. Fixtures compare literal control
tokens, U+0000 and these characters with the pinned reference.
I07. Native transport must reject bad versions, oversized frames, invalid IDs,
duplicate/gapped tokens and unexpected terminal events. Bound buffers, deadlines
and result sizes. Model completion, truncation, cancellation, memory refusal and
engine failure have distinct app states. Engine failures reach the host typed:
`model_refused`, `model_retry`, `model_engine`, and `model_stopped` when the helper
stopped, with its last output when there is any. Kill only a helper owned by this app;
drain its pipes and reap it on exit. A failed helper must not damage the workbook.
Only a failure that closed the helper ends its session, and a helper that died idle
is replaced by the next request. With no session to keep warm, a run's end frees the
model lease at once.
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

The selected Swift frontend probes generation-suffix tokens at startup and verifies the suffix on every rendered prompt. It may reuse exact large request envelopes in a four-entry in-memory cache with an 8 MiB payload budget after validating inputs and the current context limit. The cache is scoped to the frontend lifetime and never grants authority or persists history. Changed envelopes render normally; unlike the upstream tokenizer cache, this initial cache does not reuse partial message prefixes.
## Native grammar implementation

I14. Sevra uses pinned LLGuidance 1.8.0 through its C ABI. This is the
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

The grammar library is loaded only from an explicit trusted, hash-verified native library
path. Never accept that path from workbook content or model output. Cache at most
32 immutable grammar states within an 8 MiB source budget; each run gets its own
clone. Compiler limits remain enabled; suppress detailed grammar/output dumps in
errors. Validate mask dimensions exactly.

Since Splash 1.7.1 a mask request carries the draft as a tree: each token's parent is an
earlier token, and the first token's is `0xFFFFFFFF`. Row 0 is the mask after the committed
tokens and row i + 1 the mask after token i's path. As the reference's
`TokenConstraint.masks`, the host walks the tree depth first and only forward, on a copy of
the committed matcher, and gives every child but a row's last its own copy. No matcher takes
a token back: LLGuidance 1.8.0 keeps its last mask keyed by lexer state and parser row,
which another branch can reach after a rollback (Splash #790, LLGuidance #390). A token
outside the vocabulary, a stop token or a refused token is a row the target never accepts;
it and its descendants take the parent's mask. A request holds at most Ready's mask rows (17
in 1.7.1) and the wire's 32 tokens; under `--verify-rows all` a lane verifies eight. As the
reference's `_reach`, the host returns forced tokens (`llg_matcher_compute_ff_tokens`) after
every reached row from 1, and after row 0 only when the request has no draft, at most Ready's
mask rows less one a row; the engine uses a row's run only when the target selected its first
token. Fixtures hold chains, trees with a valid, a refused and a stop branch, and Splash's #790
case, and every row's mask and forced tokens must equal the reference.

The pinned Rust toolchain is a contributor build/check dependency; the installed
app does not need Rust. The app packages the grammar library. All transitive
license notices and signed-library identity remain part of I12's adoption gate.
A direct C ABI does not imply that arbitrary
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
duplicate parameters or nested keys instead of applying upstream's permissive repair.
Cap calls at 16, each argument object/parameter at 256 KiB and JSON nesting at 32.
Integer tokens must first fit Int64; workbook arguments also obey I16's exact-range
gate. Exact decimals and larger identifiers use strings: a number past 15 significant
digits that a Double cannot give back refuses. Reject lossy conversion before
Foundation JSON parsing and before dispatch into workbook storage. The model gets the
reason for a refused argument back and can correct the call; nothing from that call ran.

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

Tool-history rendering must preserve nested nulls, booleans and floats. Bridge NSNull
to the maintained Swift Jinja library's boxed-nil representation, after input bounds
validation, convert boolean and floating NSNumber values to their Swift types, which
that library would otherwise read as integers, and verify exact prompt token IDs
against the upstream template.

## Workbook inference and conversation state

I17. The workbook owns its conversation messages, tool-call values and agent loop.
Keep a package-internal inference boundary between the agent and the engine.
This is not a provider catalog, user backend selector or public compatibility API.

The native adapter runs blocking engine pipes, tokenizer and grammar work on
one serial worker, outside the main actor and Swift cooperative pool. Verify the
executable and both Metal files before launch, use verified model preparation,
and validate the native grammar library. Keep one process-wide inference lease
across app and CLI processes. Close and reap the owned helper before releasing that
lease; cancel, unload, failure and owner disposal obey the same ownership rule.
A failed stream discards the session. The next request explicitly initializes a
verified helper. Normal idle release remains two minutes.

Constrain the native finish tool's citation array to exact Source/Record versions
inspected during this request. With no inspected evidence, its maximum length is
zero. Space and table IDs, earlier-turn citations and invented UUIDs cannot pass
this field merely because they look valid. Balance results admit their exact opening-basis and accepted effect versions to
this inspected set, just as deterministic row comparisons admit their inputs.
Keep the existing host validator too; a schema-valid reference does not prove that the cited text supports a claim.
The native adapter bounds this enum to 256 references and the same context budget;
larger retrieval histories need further context/retrieval qualification.

Use all actual workbook tools with a required single-call grammar. Only a complete,
successful, grammar-checked and schema-validated terminal reaches the agent.
Check cancellation again before dispatch. Preserve existing evidence, calculations,
proposal review, citations and persisted run state. The original probes use an 8,192-token development context; the isolated product
preview selects 64K/32K under the current physical-memory tier policy in [[records/specs/conversation-context]]. Native requests use a common prepared scope/schema/token array for measurement and dispatch. Complete mode ceilings and token-bounded next-result reservations are specified in [[records/specs/conversation-context]]. Refuse before model startup when they cannot fit, then recheck actual Ready capacity. A length-limited response cannot execute a tool. Existing bounded malformed/truncated-response retries remain; neither a wider context nor an engine change silently expands them.

Conversation history includes needs-review receipts and explicit cancelled, failed
and interrupted outcomes. Closed requests are not pending instructions to resume. When its saved structured
tool result is available, resolve the proposal's current version through the
workbook's head and include its actual acceptance status, meaning and dataset ID.
Do not infer acceptance from assistant prose. Preserve the original receipt and
history. An accepted forecast remains an estimate, and historical acceptance does
not authorize a new action. Keep the last eight local user/assistant messages of
the open chat.

After three consecutive successful searches with no hits, stop with an app-owned
receipt containing the searched queries and actual incomplete-source count. Do not
let a model invent an indexing problem or infer a missing document's contents.
This is a completed evidence-gap response, not proof that a document does not exist.
Record the search tools and terminal result. Counts greater than zero explicitly
state that available evidence is partial. A successful search resets this budget.

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


The first matched request protocol is frozen in integration/performance/protocol.json,
with synthetic inputs in integration/performance/workloads.json. It uses the same
pinned native helper, target/draft assembly, 32K context, 12 GiB engine budget,
seed 42, zero temperature and disabled persistent disk cache. Ten alternating
paired process blocks provide twenty measured samples per workload and backend,
after one warmup per workload per process. Workload order rotates identically.
The five cases cover plain copying, Unicode JSON, occupied-context lookup,
formula-bearing workbook proposals and bounded reasoning over tool history.

The development reference calls the pinned upstream Frontend/NativeBackend directly;
Swift calls its production frontend, grammar and transport primitives. Neither
uses an HTTP listener in the timed path. Record process startup separately,
request/first-token/prefill/decode latency, exact prompts, generated tokens,
terminal output, failures and sampled frontend-plus-helper physical footprint.
OS file caches are uncontrolled. This is not SSD-cold measurement. Preserve all
pilot failures, and commit the tested harness before the qualifying cohort.
A pilot cannot pass the gate. Power/thermal exclusions affect both members of a
paired block and prevent this fixed-size cohort from qualifying; requests and
swap growth cannot be silently dropped. Actual WorkbookAgent job timing and the
remaining adoption gates are independent of this request benchmark.

Keep raw-model request semantics separate from application completion. The R1 cohort matched tokens and met request latency thresholds, but its four warmup currency errors fail its recorded success gate. Matching invalid outputs are not correct answers. The workbook host rejects that observed error, and four separately labeled recovery probes pass; release qualification still needs complete validated workflows, including correction latency. Preserve both results rather than converting the raw failure into a pass.
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
6. Add proactive context maintenance and durable checkpoints; qualify complete
   32K and practical 64K workloads under C01–C13, then select measured defaults.
7. Run matched model/workbook comparisons; fix regressions before adoption.
8. Remove Slotstream/MLX product dependencies, package, test a clean install and UI.
   The removal was done on November 19, 2026, by owner direction, before step 7
   finished. Clean-install and UI tests remain.
9. Publish honest measured support/limits and an explicitly qualified release.

Record each checkpoint in [[records/operations/implementation]] and the append-only
log. This plan does not remove existing product acceptance journeys J01–J10.

## Native setup
Native setup has a Swift-only service and a standalone sevra-native-setup executable, depending only on SevraSplash. It downloads the selected immutable target/draft files with URLSession into private snapshot folders, streams bytes to disk, resumes by verified Content-Range, restarts when a server ignores Range, checks pinned byte counts and SHA-256, keeps partial data on interruption/cancellation, checks available storage and atomically publishes the existing verified assembly format. Compatible explicitly selected target/draft folders can be reused without downloading weights. Failed setup leaves the prior selection intact.

The initial preflight enforces the pinned engine floor of Apple M3 and macOS 26.4. That does not qualify every such Mac for a particular context/memory profile. The native app and CLI package the helper/grammar and share this setup service. A fresh 21,481,463,614-byte download, deliberate cancellation/resume, jobs using those files and native Settings reuse have passed on the reference Mac. Settings subsequently passed fresh download start, cancellation, partial resume, cancellation again, invalid-folder failure and restored-folder verification. Cancelled setup leaves downloaded bytes resumable without publishing an incomplete selection. The UI clears old progress at start/error and ignores progress from a finished or cancelled operation; cancellation is a normal resumable state. A full fresh download solely through Settings was not separately run. These checks do not qualify all hardware, the complete UI, or performance. Production adoption still requires those gates.

Implementation references: pinned install/local.py, install/models.py, install/assembly.py and install/upstream.py; Apple URLSessionDataDelegate https://developer.apple.com/documentation/foundation/urlsessiondatadelegate ; HTTP range response semantics https://www.rfc-editor.org/rfc/rfc9110.html#name-range-requests . No dynamic model catalog, remote manifest trust or Python setup process is added.
## Native product isolation
The workbook agent owns tool schemas and conversation values. SevraProduct is the single app/CLI entry point for setup, status, unload and workbook runs. Users do not choose a backend.

The app uses the verified installed assembly, including its separate tokenizer and draft folders. Settings downloads into managed storage by default and can explicitly reuse a complete existing compatible model folder in place. Reused originals must remain available. Setup and inference are serialized; cancellation preserves resumable bytes and never publishes an incomplete selection. New sessions validate selected source identities and original files: each launch checks sizes and recorded identities and hashes only a file whose identity moved. Verify model files hashes every file of an existing pinned assembly before considering a download; this preserves explicit reuse without creating a second weight copy. Only a missing or changed original starts a download, repaired into managed snapshots with the previous selection retained until the replacement verifies. Any other failure, such as a busy lock, stops setup with its error.

The app and CLI package the unchanged Splash helper and Metal files, native grammar library, resource bundles and dependency notices. Runtime lookups resolve only installed locations. Missing packaged resources must fail even when the contributor build tree exists. The preview has its own bundle identifier and does not register workbook associations. Candidate builds keep automatic compaction disabled until its adoption gate passes. The 32K context, bounded512 reasoning and 12 GiB engine budget remain qualification settings, not a broad hardware performance claim.

The native product must be tested with build-folder access denied, missing and altered resources, actual model setup and complete workbook jobs. Code signatures and runtime hashes must agree after packaging. CI additionally builds the preview from a fresh checkout and checks installed paths, grammar loading, signatures and missing resources without GPU qualification. Local checks separately exercise Metal and missing-model guidance. Performance adoption still requires the matched reference comparison in this specification.

## Nested schema property order
LLGuidance fixes JSON object property order to the order supplied in each schema. Canonically sorting every nested property alphabetically placed optional formula before required id; once a model emitted id it could no longer add a formula. A real native planning-table test exposed both a fixed numeric replacement and a missing total. Prompt-only changes did not repair this constraint.

For JSON-valued tool arguments, Sevra now emits nested properties in declared required-field order followed by optional fields in alphabetical order. XML argument order remains unchanged. This keeps column identity/type before optional formula and unit metadata. Required properties, types, additional-property rules and terminal validation are unchanged. The pinned reference receives the same application-owned schema order; the grammar engine itself is unchanged.

The fixture generator records required-first nested ordering and includes a planning-table formula case. All 28 actual-tool cases and 249 speculative mask comparisons match the pinned reference. These fixture results establish grammar parity for the declared inputs, not model success on every request.

## Complete-workbook comparison W1
W1 runs the actual shared WorkbookAgent, typed tools, SQLite persistence and validation against two frontends: the native Swift candidate and a development-only private-pipe adapter to the pinned Python reference. Both use the same unchanged Splash C++/Metal helper and selected model bytes. The reference target is absent from the installed app and CLI. This is an internal qualification boundary, not a user backend selection.

A package-internal task-local fixture context gives paired workbooks identical synthetic UUIDs and timestamps. No product setting or environment variable enables it. Ordinary production IDs and time retain their existing sources. Call IDs are normalized in both test wrappers before the shared host receives them. An optional native observation callback records actual prompt arrays, generation prefixes and generated tokens without changing inference. Its production default is nil. The internal actor protocol permits asynchronous lease acquisition so the observation wrapper forwards real admission rather than bypassing it.

The preregistered protocol is integration/performance/workflow-protocol.json. Four jobs cover supplier comparison and native table/chart composition, a reviewed formula proposal followed by scripted acceptance/edit/undo, cited stock replay, and a missing contract with an explicit unsupported source. Complete job time includes validation, any model corrections, tools and persisted completion. Fixture setup and result assertions are outside timing. Scripted human actions are included; human deliberation is excluded. Reference pipe/serialization cost remains in the wall time and is separately observable.

Each worker first completes an identical Ready job to load the model. Ten alternating paired blocks rotate workflow order, with one warmup and two measured jobs per workflow/backend/block. This yields twenty measured observations per workflow and frontend. The same 32K allocation, 24K maximum actual prompt, 1800-token output budget, bounded512 reasoning, greedy seed 42, 12 GiB engine budget, disabled persistent cache and required-first nested grammar ordering apply. Workers own the real shared inference lease and run sequentially. No overlapping builds, downloads or model runs are permitted during qualification.

The gate requires every priming, warmup and measured job to pass, exact paired starting evidence and prompt/prefix/generated-token sequences, full declared sampling, successful cleanup, all expected jobs and no more than 5% median or 10% p95 complete-job regression. Corrected invalid model answers are allowed only after host validation succeeds; their latency stays included. Lost AC power or serious/critical thermal pressure excludes the whole paired block and prevents the fixed-size cohort from passing. Preserve partial and failed attempts. A pilot cannot qualify adoption.

Sample physical footprint every 0.2 seconds for the Swift host and helper; include the Python bridge as a third process on the reference side. Record thermal state, power and swap around each worker. Priming has separately reported launch-to-ready time; OS file caches are uncontrolled and startup does not have simultaneous footprint qualification. These four jobs do not establish full UI responsiveness, all model behavior, full occupied 32K/64K support, a hardware envelope or a general Python-removal speedup. R1 raw-model failures remain failures, regardless of W1 results.

## Request-priority comparison correction, October 27
During W1 pilot review, code inspection found a request parameter omitted from the earlier matching checks: Swift SplashWire.Request defaults to foreground priority (wire 0), while the pinned Python Frontend defaults to normal (wire 1). The earlier R1 reference body did not override it. R1 retains its recorded token equality, raw timings and failed currency outcomes, but it does not establish performance under fully identical request parameters. The original frozen protocol, receipts and failures remain preserved; do not promote its latency result as a completed matched-configuration gate. A newly preregistered request cohort with verified actual parameter bytes is required for that claim.

W1 now explicitly supplies foreground priority to the reference and captures each actual serialized request frame on both sides. Normalize only the request ID and deadline stamps, then compare every remaining byte, including prompts, sampling, thinking terminators, flags, cache salt and priority. Preserve unmatched frames. Record matched-prefix token counts to investigate cache-related variation. The earlier W1 pilot had some differing reasoning sequences despite identical input prompts; the priority discrepancy is a verified confound, not yet a proven explanation for that divergence.

## Divergence diagnostics
When actual request bytes match but generated tokens differ, first replay the exact native worker, source identity, synthetic starting state, priming job and preceding job order. Preserve both complete traces. This distinguishes an observed within-native difference from a cross-frontend difference; even an exact replay is not universal determinism proof.

A separate pilot-only mode observes the actual grammar text and every returned mask row on both paths. Hash all little-endian UInt32 words, including padding, and identify each row by the committed output plus its hypothetical simulation prefix. Save the committed length and simulation token IDs so every prefix hash can be verified later. Production configurations leave the observation callback nil. The pinned engine, grammar library and reference mask provider remain unchanged.

Compare masks at shared actual and speculative prefixes. Preserve multiple observations of a prefix and flag inconsistent masks. Missing observations are gaps, never matches. At the first differing generated token, report whether both sides observed that prefix and whether their masks agree. Equal masks there do not identify an engine bug or rule out differences at unshared speculative prefixes, other commands, cache state or timing. Capture actual grammar identities separately from mask equivalence.

Instrumented timings cannot qualify W1, even if all jobs pass or a summary is called with a non-pilot flag. Never remove diagnostic failures or relax generated-token equality to promote the candidate. Commands and retained results belong in [[records/operations/build-and-run]] and [[records/operations/implementation]].

## Diagnostic evidence limits, October 27
The traced W1 pilot matched all 42 request/output sequences and all 16,130 shared mask prefixes. Turning tracing off on the same reference build restored the older reference output, including its four same-wire differences from native. Therefore a matching diagnostic trace does not clear the uninstrumented parity gate. Preserve both results and isolate mask-response pacing, observation serialization and command/cache effects separately. Do not introduce an artificial product delay or redefine a successful pilot as a qualified comparison. The unchanged native engine remains pinned, and production adoption remains disabled. See [[records/operations/implementation]] for exact evidence and limits.

## Cache-equivalent comparison conditions
Record both matchedPromptTokens from native Start and deduplicatedKVTokens from Done. The latter includes KV substituted later, beyond the state restored at startup. It is not another name for the initial hit count. Counts are diagnostics, not cached-byte identities, and can include prior generated tokens where full token prefixes match. Check the complete prior prompt/output history before attributing their positions.

The observed W1 differences include unequal later cache reuse at equal initial prefix counts. Preserve W1 as a failed comparison and do not attribute its differing answers to Swift or qualify its timings as identical-computation evidence. Pinned upstream numerical conditions are summarized in [[records/research/foundations]].

The preregistered fresh-worker isolation pilot I1 removes cross-workflow history by giving each workload/backend pair a new process. It retains the same real workbook tasks, exact requests and generated outputs, 32K context, bounded512 reasoning, 12 GiB memory, masks, output validation and formula review/undo. It adds explicit initial/later cache-counter comparison, with missing data treated as unknown. It cannot qualify performance or adoption. A passing isolated pilot must lead to a separately reviewed and preregistered qualifying protocol, while mixed-workload robustness remains required. See integration/performance/workflow-isolation-pilot.json and [[records/operations/implementation]].

I1 completed all sixteen workbook jobs and eight Ready primes, but failed its exact comparison. Formula, inventory and missing-evidence pairs matched requests, outputs and both cache counters. The supplier case first differed in measured step 6 at generated-token offset 171, with identical normalized request bytes, initial matched count 4640 and later reuse count 0 on both sides. Subsequent requests and counters diverged with the changed conversation. Fresh workers per workload are insufficient to establish parity, and equal counters do not establish identical numerical state. Neither an engine defect nor a Swift defect is established. No qualifying isolated cohort follows this failed pilot.

Keep two questions separate: whether the frontends perform identical computation, and whether either completes useful work without avoidable correction loops. The I1 stock case exposed the same evidence-reference confusion and three rejected finishes on both frontends, despite exact token parity. Fixing that tool contract is shared application work, not a resolution of native/reference parity. Preserve pre-change observations and use separately identified functional recovery probes. Production adoption and performance qualification remain gated.

## Request-cache isolation diagnostic I2
I2 is preregistered in integration/performance/request-cache-isolation-pilot.json. It compares the supplier workflow with ordinary shared caching and a unique raw 128-bit engine cache identity on every request, including Ready. Each arm uses fresh native and reference workers, followed by the same warmup and measured fixture seeds. The reference intervention sets the raw cache field before unchanged upstream request serialization; this does not test its string-hashing API. Product callers leave the package-internal diagnostic option disabled.

Require actual saved wire frames with verified hashes, expected distinct salts, zero initial and later cache reuse in the isolated arm, complete jobs and samples, unchanged measured sources and exact paired requests/generated tokens. Keep both arms and all failed jobs. This isolates prior prompt/KV sharing, not all memory-dependent chunking or numerical state. Neither arm qualifies performance or adoption; a passing isolated arm cannot excuse a failed shared-cache control. The standard W1 gate also refuses requests marked with this intervention, even if a caller forgets its diagnostic label.

## Complete-workflow command and source identity
The complete-workflow reference must not add a status request after each response solely for benchmark telemetry when the native product does not make that request. Such a probe changes command history and adds work inside the timed reference bridge. The request-level R1 harness is separate: both sides obtain status outside its request timing. Preserve earlier W1/I1/I2 results with their original source identities; removing this asymmetry does not establish the cause of historical token divergence.

Freeze measured sources, model manifest and release worker binary. Verify their identities before every worker and when finalizing, and refuse qualification or another worker after any change. A clean worktree at startup alone is insufficient. I2 passed both current supplier arms, but its newer prompts and one sample per frontend do not qualify performance. Continue with an uninstrumented W1 pilot under normal caching before considering a qualifying cohort.

## Current W1 pilot boundary
The corrected normal-cache W1 pilot on fda029e completed sixteen jobs plus two Ready primes with 32 exact paired requests and generated outputs, no sampling/condition failures, and retained currency correction latency. This satisfies the pilot prerequisite only. Run the already preregistered complete cohort on committed frozen sources before assessing the recorded latency gate. Keep I1 and earlier W1 divergences as historical evidence; a newer passing prompt set and telemetry correction do not establish a universal determinism claim or a single root cause.

## Complete W1 result, October 27
The frozen 0e45190 ten-block cohort completes all 260 jobs and meets the
registered timing thresholds, but fails exact paired-output parity in one
inventory warmup. Identical request bytes first diverge in generated reasoning;
subsequent prompt differences are consequences. Preserve the entire cohort and
isolate this discrepancy with a focused replay before considering another
qualification run. No native production adoption or passed W1 speed gate follows.
See [[records/operations/implementation]] and the preserved cohort2 evidence.

## D9 fixed-prefix repeatability diagnostic
D9 is preregistered in integration/performance/workflow-prefix-repeatability.json.
It reuses the preserved 0e45190 worker and verifies its recorded original source
tree, actual engine/grammar/model manifest and reference script/dependencies.
Run four fresh workers in reference/native/native/reference order. Each performs
Ready, formula_review seed 9001, and inventory_evidence seed 9002, preserving the
complete per-worker cache history before the first W1 divergence. Compare every
repeat with both historical prefixes and within/across frontends. Keep different
tokens as evidence; missing/invalid jobs, samples or cleanup invalidate the probe.
Do not infer a root cause from equal cache counters. This cannot qualify speed,
relax W1 parity, or authorize production adoption. No measured worker rebuild,
extra masks/status calls or cache intervention is allowed.

The completed replay on controller 22cca90 retained four valid workers and twelve
correct jobs. Both native repeats match each other and the second reference
repeat. The first reference repeat differs at output token 19 for the same second
inventory request and identical preceding requests/outputs. Thus the current
reference also fails exact repeatability. This rules out treating the W1 mismatch
alone as proof of a Swift frontend defect; it does not identify a numerical root
cause, prove universal native determinism, or qualify production adoption.
Preserve the failed W1 and first incomplete D9 attempt. The next engine review
must distinguish frontend request/tokenizer/grammar equivalence from upstream
numerical repeatability before choosing another experiment or revising a gate.
Do not blindly repeat the full cohort until one happens to pass. Complete replay
and independent hash/process audit: integration/evidence/2026-10-27-prefix-d9-repeatability.json.gz.

## Reviewed inference and context upgrade plan, November 15
[[records/plans/inference-context-upgrade]] is revision 5 after three original passes and a complete follow-up review. [[records/reviews/inference-context-plan-full-review]] records every section's coverage and 18 resolved gaps/ambiguities. The plan covers shared exact-scope admission, mode-specific output/result/transition reserves, actual admitted capacity, Splash 1.6.1 and controlled context/memory experiments. This describes the original planning checkpoint. The owner authorized implementation on November 16. The common accounting path and mode-aware 75%/reserve policy are now implemented and tested on 1.4.1; the explicit engine/profile adoption gates remain. [[records/operations/inference-context-execution]] records current evidence and gaps. The historical review and qualification failures remain preserved.

## Earlier candidate 1.6.1 execution, November 16

This subsection preserves the assessment before the later focused preview adoption described at the top. Candidate-only and adoption-blocked statements below describe that earlier gate; its failures remain relevant to broad production qualification.
The owner-authorized [[records/plans/inference-context-upgrade]] is in execution. The candidate pin is Splash 1.6.1, commit `d8af1054aab0f97de21d043e01aa98af3754f10e`, protocol 13/status 8. The previous 1.4.1 pin remains in `integration/splash-1.4.1-preserved.json`; preserved source, workers and bundle identities are recorded in [[records/operations/inference-context-execution]]. This is a source candidate, not an adopted production runtime or an installed-preview replacement.

The Swift adapter handles bounded startup Warming, Ready vocabulary/stop-token/mask-row capabilities, typed StartFailed shortfalls, and successful frontend Stop separately from user Cancel. The lease owner retains the child before readiness can fail; teardown must reap it before releasing ownership. Native assembly matches the pinned upstream record and reuses unchanged target/draft/tokenizer bytes without a new model download. LLGuidance stays 1.8.0 and Swift package pins are unchanged. Qualification fixes BF16 activations, int8 KV, fp32 state, ANE on, 32K context and 12 GiB engine budget. Automatic M5 precision is not enabled by upgrading the default.

Exact prompt/streaming/projection and vocabulary/tool-mask fixtures, 37 protocol/resource/setup checks and native startup/cancel/recovery checks pass. The frozen P2-agent R/N/N/R prefix, before later continuity fixes, passes twelve jobs with exact request and generated-token equality. The historical fixed-input prefix instead retains within-native and within-reference variation. Instrumented comparison finds zero mask differences across 2,830 shared prefixes, but cannot clear the uninstrumented strict parity failure or qualify performance. The first packaged candidate calculator-authoring trial also fails after repeated invalid source; the host refuses to publish a broken app. These failures block adoption and the later larger-context qualification sweep. See `integration/evidence/2026-11-16-splash-upgrade.json` for retained evidence and precise limits.

The accounting and history fixes are independent host behavior: exact scope/output/result budgeting, preserved original receipts, review metadata retention and bounded navigation candidates that do not hide explicit original pointers behind incidental history IDs. Real multi-compaction, portable continuation, false-digest/current-authority, summary cancellation and explicit retry checks pass after documented repairs. User-facing inference progress uses real preparation/reading/response phases rather than token counts. Full profile/performance and final native UI gates remain distinct from these headless results.
## Prepared prompt header, November 19

[[records/plans/general-chat-tools]] phase H3. The ordinary chat header, the instructions and shared tool declarations every ordinary chat turn starts with, is made ahead of time by `sevra header make` and sealed in the app. The app never computes it. Before every engine start the host restores its four data files into an emptied cache directory and launches with `serve-native MODEL CONTEXT MEMORY 8589934592 --persistent-cache on --cache-dir ~/Library/Caches/Sevra/PromptCache` and `--idle-sleep allow --verify-rows all --kv-format int8 --state-format fp32 --ane on --activations bf16`, since Splash 1.7.1 followed by `--max-concurrent-requests 1`. The 8 GiB quota holds the header and a conversation that fills the context. After Ready the host requires `disk.persistent`, the manifest's restore points taken back and none left behind; it repeats a short start once from the app's files and then reports a damaged installation. Every request that starts with the header must resume it to its last complete page; a miss is cancelled before it generates and sent once more after a restart. The directory is removed at every stop.

A header is named by the digest of its inputs, which need no model, and its manifest must match the engine release and commit, the engine settings above, the selected model pack, and after the model loads the assembly key and the header's tokens. Since phase H2 the assembly's `model.json` holds no path or file time of this Mac, so the assembly key and the engine's cache name are the same on every Mac for the same pack; this Mac's paths and times sit beside the assembly in a file the engine never reads. One header serves both memory tiers: a 64K header is taken back and resumed at 32K.

Qualification of this pin now includes the header tests in `sevra-agent-checks --header-tests`: resumed and not computed, faster for the header's share of a first decision, the same decisions and factual answers as the comparison setting that computes the header, recovery from a missed resume without computing, loud failure with no header, a mismatched manifest or a damaged file, nothing kept after a stop, the header only after a forced kill, and the same header from a model prepared in another folder. The engine is not repeatable token for token across processes, so same answers means the same decisions and factual answers. Evidence: `integration/evidence/2026-11-19-header-tests/`.

## Splash 1.7.1, November 24

[[records/plans/splash-1-7-1-upgrade]] moved the pin from 1.6.1 to the tagged 1.7.1 (1.7.2 on upstream `main` is untagged). The engine files, model, model folder format, status schema, launch flags and cache file names are unchanged; the host changed in five places.

- **Wire, protocol 15.** A request carries `head_tokens` (0: ordinary chat resumes the prepared header). A start carries the KV-matched prefix, where the resumed state came from (none, memory or disk) and whether a state was lost; the host checks both counts against the prompt and records them as `prefixTokens`, `stateSource` and `lostState`. Mask requests carry parents, and mask responses carry forced pairs (empty at first; follow-up F4).
- **Tool grammar.** As upstream 1.6.2: a required or named call starts at its first token, and the whitespace after reasoning belongs to the thinking rule.
- **Tree masks** (I14 above).
- **Header.** Remade: the cache namespace's GDN state layout changed. Cached states are int8 codes, so the header's state file is 20.5 MB instead of 66.7 MB. The namespace holds no path, context, memory, lanes or verify rows, so one header still serves both tiers and every Mac.
- **One lane.** The app runs one request at a time. At 64K and 12 GiB one lane left the expert store 7,901 MiB against 7,705 at four lanes and dropped three decode warm-ups.

Decisions: keep `--verify-rows all` (repeatable output, the tree at 1.6.1's step size, no step-cost measurement); take the int8 cached-states default; send `head_tokens` 0 and no forced tokens; keep the app's space after `<` in literal control tokens. Later: `auto` verify rows, header identity without restore-point-neutral options, `head_tokens` for prompts without a prepared header, forced tokens from `llg_matcher_compute_ff_tokens`, and literal control tokens as characters.

Results, one run each on a 48 GiB M5 Pro: every model-free check passes, including byte parity with every 1.7.1 protocol golden and 1,655 tree and chain masks equal to the reference; both context tiers start at 12 GiB; the eight header tests pass; the light set passes 11 of 11 on the first run. The five-message timing conversation decoded 92.9 tokens a second against 50.7 on 1.6.1, at 45.6 ms and 4.23 tokens a cycle against 77.1 ms and 3.91, with grammar masks at 0.92 ms against 2.04; page-cache state between the two runs was not controlled. The Neural Engine split and step costs do not apply to this model and setting. The performance and differential harnesses (`compare_*_performance.py`, `splash_performance_reference.py`, `check_splash_reference.py`) load the pinned reference and cannot run against 1.7.1 until ported; `check.sh` imports only their pure helpers. Evidence: `integration/evidence/2026-11-24-splash-1-7-1/`.

Follow-ups, the same day, at the owner's word, one run each:

- **F1, `--verify-rows auto`: not taken.** On the timing conversation it decoded 4.09 tokens a cycle against 4.18 under `all` with forced tokens, both at 58 ms a cycle, so it saved no step cost and accepted fewer tokens. The 45.6 ms of the upgrade run came with about 27 GiB reclaimable against about 22 for these two, so cycle times compare only with each other.
- **F2, header identity.** A manifest no longer mismatches on `--verify-rows`, `--max-concurrent-requests` or `--idle-sleep`, which change no restore point; activations still count, as they change the stored numbers.
- **F3, `head_tokens`.** A prompt without a prepared header (Excel conversion, reviews, scope blocks, the comparison setting) sends the shared prefix, or a stable scope at least 2,048 tokens past it, as `head_tokens` in the request itself; the host records the state only where the engine keeps one (the head's last complete page, at least 2,048 tokens past the resumed state and not past the replay boundary). The one-token prime requests are gone.
- **F4, forced tokens** (I14). The timing conversation decoded 72.0 tokens a second at 4.18 tokens a cycle; it holds too few tool calls to show a gain, and the host now matches the reference's forced pairs.
- **F5, literal control tokens as characters, U+0000 as U+FFFD** (I06). Every prompt now renders and splits one way. Fixing it found the character-based search difference in swift-transformers, which also changed ordinary text such as `❤️<b>`.

Results: 32 text cases, 214 grammar steps (1,326 forced pairs) and 1,441 workbook tool masks (14,800 forced pairs) equal the reference; 39 Splash checks and the agent checks pass. The packaged header's inputs are unchanged (4,429 tokens). The eight header tests pass: with the comparison setting the first request carries `head_tokens` 4,429 and its first decision takes 2.16 s against 1.30 s from the restored header. The light set passes 11 of 11 on the first run. Evidence: `chat-timing-1.7.1-auto.jsonl`, `chat-timing-1.7.1-forced.jsonl`, `header-tests-followups.json` and `light-followups/` in the same folder.

## Splash 1.7.2, November 24

The pin moved from 1.7.1 to the tagged 1.7.2 (commit `2afc733`), at the owner's word ([[sources/notes/2026/11/splash-1-7-2-upgrade-approval]]). Protocol 15, status schema 8, the model, the model folder assembly (`install/*.py`), the protocol golden, `host-step.metallib`, the licenses and the third-party notices are unchanged. The engine and `splash.metallib` changed.

Upstream's mapped Python surfaces changed only to add Inkling 2's chat format (JSON calls, framed answer text, a model that opens its own message); Qwen's values are the same. Regenerated from the 1.7.2 reference, all four fixture sets equal Sevra's byte for byte apart from the recorded commit: 32 text cases, the grammar masks, the 1,441 workbook tool masks and the output projections. One generator change: upstream's `_generation_prompt` now takes the chat format, and `generate_splash_text_fixtures.py` passes Qwen's. No host Swift behavior changed; only the release and commit constants did.

What 1.7.2 changes for Sevra's MLX 4-bit Qwen: little. Its int8 Q8_0 prefill applies to GGUF only (MLX 4-bit already took int8 activations in 1.7.1), and Qwen decode is level. The cache fixes apply where the app runs: with `--persistent-cache on`, the header's state is now written to the SSD cache after its publication, and a long suspended reply resumes at its newest state. The MoE image gains an expert-scales section, so the persistent cache starts cold once after the upgrade. The app sends normal priority, so the background promotion does not apply.

Results, one run each on a 48 GiB M5 Pro, with the installed app quit: 39 Splash checks and the text, grammar and agent checks pass; the packaged engine's digest equals the pin; the prompt header was remade (4,480 tokens; its inputs changed with the chat tools since the 1.7.1 run, not with the engine) and the engine took it back; the eight header tests pass; the light set passes 11 of 11 on the first run in 119 s of model jobs against 112 s on 1.7.1, the same 30 model calls. Evidence: `integration/evidence/2026-11-24-splash-1-7-2/`. Not run: the timing conversation, the 32K tier start and the broader qualification, which stays blocked for the reasons in `integration/splash.json`.
