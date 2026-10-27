---
type: spec
meta-type: conclusion
id: 01m5wps1qcharh0qv8vq40wbjr
created: 2026-10-26T18:15:17.996137+00:00
updated: 2026-10-27T10:13:13.622122+00:00
summary: Python-free Swift integration of pinned upstream Splash, explicit behavior mapping, differential verification and measured adoption gates.
title: Native Splash integration and upgrades
status: reviewed
---
# Native Splash integration and upgrades

Revision 8, October 27 UTC, 2026. Owner-approved direction; integration not yet qualified.
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

The selected Swift frontend probes generation-suffix tokens at startup and verifies the suffix on every rendered prompt. It may reuse exact large request envelopes in a four-entry in-memory cache with an 8 MiB payload budget after validating inputs and the current context limit. The cache is scoped to the frontend lifetime and never grants authority or persists history. Changed envelopes render normally; unlike the upstream tokenizer cache, this initial cache does not reuse partial message prefixes.
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

## Workbook inference and conversation state

I17. The workbook owns its conversation messages, tool-call values and agent loop.
Keep a package-internal inference boundary for qualifying the native candidate
against the preserved backend. This is not a provider catalog, user backend
selector or public compatibility API. The production app continues to depend on
the baseline until the adoption gates pass.

The native candidate runs blocking engine pipes, tokenizer and grammar work on
one serial worker, outside the main actor and Swift cooperative pool. Verify the
executable and both Metal files before launch, use verified model preparation,
and validate the native grammar library. Keep one process-wide inference lease
across app/CLI backends. Close and reap the owned helper before releasing that
lease; cancel, unload, failure and owner disposal obey the same ownership rule.
A failed stream discards the session. The next request explicitly initializes a
verified helper. Normal idle release remains two minutes.

Constrain the native finish tool's citation array to exact Source/Record versions
inspected during this request. With no inspected evidence, its maximum length is
zero. Space and table IDs, earlier-turn citations and invented UUIDs cannot pass
this field merely because they look valid. Balance results admit their exact opening-basis and accepted effect versions to
this inspected set, just as deterministic row comparisons admit their inputs.
Keep the existing host validator too; a schema-valid reference does not prove that the cited text supports a claim.
The candidate bounds this enum to 256 references and the same context budget;
larger retrieval histories need further context/retrieval qualification.

Use all actual workbook tools with a required single-call grammar. Only a complete,
successful, grammar-checked and schema-validated terminal reaches the agent.
Check cancellation again before dispatch. Preserve existing evidence, calculations,
proposal review, citations and persisted run state. The original probes use an 8,192-token development context; the isolated product
preview uses the provisional 32K profile. Both have an output allowance of at most 1,800 tokens, reduced
to the remaining context capacity. Refuse when fewer than 256 output tokens remain;
a length-limited response cannot execute a tool. Longer-job context management
and its wider workload qualification remain open under [[records/specs/conversation-context]].

Conversation history includes needs-review receipts and explicit cancelled, failed
and interrupted outcomes. Closed requests are not pending instructions to resume. When its saved structured
tool result is available, resolve the proposal's current version through the
workbook's head and include its actual acceptance status, meaning and dataset ID.
Do not infer acceptance from assistant prose. Preserve the original receipt and
history. An accepted forecast remains an estimate, and historical acceptance does
not authorize a new action. Keep the existing bounded tangent parent excerpt and
last eight local user/assistant messages.

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
6. Add proactive context maintenance and durable checkpoints; qualify complete
   32K and practical 64K workloads under C01–C13, then select measured defaults.
7. Run matched model/workbook comparisons; fix regressions before adoption.
8. Remove Slotstream/MLX product dependencies, package, test a clean install and UI.
9. Publish honest measured support/limits and an explicitly qualified release.

Record each checkpoint in [[records/operations/implementation]] and the append-only
log. This plan does not remove existing product acceptance journeys J01–J10.

## Native setup candidate
Native setup now has a candidate Swift-only service and a standalone sevra-native-setup executable, depending only on SevraSplash. It downloads the selected immutable target/draft files with URLSession into private snapshot folders, streams bytes to disk, resumes by verified Content-Range, restarts when a server ignores Range, checks pinned byte counts and SHA-256, keeps partial data on interruption/cancellation, checks available storage and atomically publishes the existing verified assembly format. Compatible explicitly selected target/draft folders can be reused without downloading weights. Failed setup leaves the prior selection intact.

The initial preflight enforces the pinned engine floor of Apple M3 and macOS 26.4. That does not qualify every such Mac for a particular context/memory profile. The isolated native app and CLI now package the helper/grammar and share this setup service. A fresh 21,481,463,614-byte download, deliberate cancellation/resume, jobs using those files and native Settings reuse have passed on the reference Mac. Settings subsequently passed fresh download start, cancellation, partial resume, cancellation again, invalid-folder failure and restored-folder verification. Cancelled setup leaves downloaded bytes resumable without publishing an incomplete selection. The UI clears old progress at start/error and ignores progress from a finished or cancelled operation; cancellation is a normal resumable state. A full fresh download solely through Settings was not separately run. These checks do not qualify all hardware, the complete UI, or performance. Production adoption still requires those gates. The candidate CLI does not switch the installed app.

Implementation references: pinned install/local.py, install/models.py, install/assembly.py and install/upstream.py; Apple URLSessionDataDelegate https://developer.apple.com/documentation/foundation/urlsessiondatadelegate ; HTTP range response semantics https://www.rfc-editor.org/rfc/rfc9110.html#name-range-requests . No dynamic model catalog, remote manifest trust or Python setup process is added.
## Native product isolation
The workbook agent owns tool schemas and conversation values without importing Slotstream or MLX. The preserved engine and history conversion live in SevraBaseline. SevraProduct is the single app/CLI entry point for setup, status, unload and workbook runs. The migration build switch is internal; users do not choose a backend.

The native candidate uses the verified installed assembly, including its separate tokenizer and draft folders. Settings downloads into managed storage by default and can explicitly reuse a complete existing Fast pack in place. Reused originals must remain available. Setup and inference are serialized; cancellation preserves resumable bytes and never publishes an incomplete selection. New sessions validate selected source identities and original files. Repeating setup verifies an existing pinned assembly before considering a download; this preserves explicit reuse without creating a second weight copy. Broken originals can be repaired into managed snapshots, with the previous selection retained until the replacement verifies.

An isolated preview app and CLI package the unchanged Splash helper and Metal files, native grammar library, resource bundles and dependency notices. Runtime lookups resolve only installed locations. Missing packaged resources must fail even when the contributor build tree exists. The preview has a distinct bundle identifier and does not register workbook associations or replace the installed baseline. Candidate builds keep automatic compaction disabled until its adoption gate passes. The 32K context, bounded512 reasoning and 12 GiB engine budget remain qualification settings, not a broad hardware performance claim.

The native product must be tested with build-folder access denied, missing and altered resources, actual model setup and complete workbook jobs. Code signatures and runtime hashes must agree after packaging. CI additionally builds the preview from a fresh checkout and checks installed paths, grammar loading, signatures and missing resources without GPU qualification. Local checks separately exercise Metal and missing-model guidance. SwiftPM still resolves baseline source packages for comparative tests; they are absent from the native product binary. Performance adoption still requires the matched reference comparison in this specification.

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
