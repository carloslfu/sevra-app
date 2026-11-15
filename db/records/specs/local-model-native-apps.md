---
type: spec
id: 01m79fs6ac5qjrxm82yqwa255e
created: 2026-11-13T03:38:52.108343+00:00
updated: 2026-11-15T14:36:08.019281+00:00
summary: Local-model native app authoring, isolated checks, independent review and exact-version access.
title: Local-model native app authoring
status: implemented
---
# Local-model native app authoring

Owner request: [[sources/notes/2026/11/local-model-native-apps]]. Implementation and acceptance: [[records/plans/local-model-native-apps]], with adversarial findings in [[records/reviews/local-model-native-apps]]. The runtime/component contract remains [[records/specs/programmable-native-engine]].

## User workflow

Ask the workbook conversation to build a named mini app and describe its fields, actions and data. For example: “Build a Stock desk app with Item and Quantity fields, an Add item button, validation and a searchable inventory table.” The local model reads the shipped SDK, inspects existing tables where needed, writes native JavaScript, and supplies synthetic behavioral checks. An existing app is inspected by exact name or ID before an exact-version update.

The host runs those checks, then requests a separate local-model review against the request, proposed source, tests and previous source. A failed check or review returns actionable feedback for a bounded repair attempt. Only successful checks and review permit saving. The saved result opens the native app's access review. The person enables the exact saved version on this Mac. The app itself then runs independently of the inference model. Changing its source requires approval again. Tests never populate the actual workbook.

## One engine, two isolated processes

The model authors plain JavaScript against the shipped Sevra SDK. There is no JSX compiler, browser, web view or Node runtime in the installed app. Native AppKit controls and the existing typed data broker remain the interface and data authority. Source packages and the external TypeScript/JSX SDK remain available for developer authoring.

`native_app_sdk` supplies the precise contract, complete examples and layout guidance. `read_native_app` returns exact source, bindings, ID and version. `save_native_app` carries the package, sequential tests and optional synthetic fixtures. A host-owned authoring flag grants a bounded larger response allowance after SDK/source discovery; it survives conversation maintenance without being inferred from model text. Scoped new-chat continuation supports the same authoring tools.

Unapproved source runs in the separately signed `app-check-worker` XPC service; enabled apps use `app-worker`. They share pinned runtime code, but are distinct OS processes with the minimal sandbox entitlement. Neither receives filesystem/network capabilities. The check host creates a disposable workbook, strips all real dataset bindings, seeds only synthetic fixtures, restores declared read/write permissions and uses the production typed broker. No real workbook or device grant is passed to the checker.

## Checks and authority

The checker supports native inputs, buttons, picker/tab/table selection, row activation, canvas actions, visible text/control/value assertions, region positions and persisted row counts/values. Hidden ancestors and inactive panels cannot satisfy visibility checks. Action steps also refuse disabled ancestors, matching native host dispatch; inspecting an inert canvas region remains allowed. Every step settles asynchronous replies and reactive subscriptions. Decimal math uses the core calculator; formula columns remain derived values. Read-only bindings default to no write permission.

Budgets bound source/package size, fixtures, test steps, runtime, XPC replies, bridge requests, transactions, subscriptions and frames. Unhandled promise failures stop the worker instead of leaving an apparently healthy app. Cancellation refuses publication. Temporary files and access objects are cleaned up.

The separate review model has only `review_native_app`, no write or enable tools. Source, comments and test data are untrusted. The host binds its successful verdict and sandbox result to the exact package digest and current captured request. Neither proof can be supplied through model-controlled tool arguments. A fixed host-authored rule Source records narrow AI authority to publish inert code and empty schemas; it grants no business-event acceptance or execution permission. Current-version checks, atomic installation, captured history, duplicate-name refusal and operation-token replay protect updates. Existing data stays in its existing bindings.

## Limits

Synthetic assertions and a separate model review reduce mistakes; neither proves every behavior or visual quality. Generated apps require human inspection and ordinary testing before real business use. Requests may exhaust the bounded repair/context budget or repeatedly select the wrong tool. The November 13 fresh-baseline check failed even in a new workbook, and a guided follow-up did not recover; see [[records/reviews/native-app-fresh-start-2026-11-13]]. A fresh focused thread has helped in other observed cases but does not guarantee creation. The SDK is extensible but finite, and does not promise full Excel fidelity, arbitrary OS access or custom compiled native controls. Native layout, assistive technology, external security assessment and scale require evidence appropriate to the actual app. This remains a locally signed source preview.

## Measured authoring context

Ordinary chat exposes SDK/source discovery but omits the large save/test schema. SDK delivery sets a host-owned flag that exposes save_native_app and permits up to 8192 output tokens. Compaction and both local adapters use the same flag for measurement and generation. Pinned tokenizer checks gate ordinary tool prompts at 8448 tokens (measured 8361) and authoring prompts at 10240 (measured 9506), inside the same 32768-token context. The separate review scope still exposes only its verdict tool. The SDK is returned with source inspection so follow-up edits do not have to invent APIs from code alone. A failed lookup in a writable request also supplies the host SDK and creation guidance: a failed build has no saved app to edit. Read-only requests never enable the save schema.

Active programmable spaces identify their type and exact ID in native workspace context. Fixed-layout tools return a native-edit route before attempting component edits. A later checked save settles failed edits to the same app in the final receipt while preserving every attempt in activity and retaining unrelated failures.

## Conversational operation

The later [[records/specs/chat-primary-operation]] contract makes chat the primary operating interface. Named SDK actions and existing semantic controls use the same worker and broker without a renderer. Access review and exact-version approval can be completed in chat. Views remain optional clients of the same actions. The authoring checker also accepts `run_action` with typed inputs and optional expected validation errors.


### Review setup and source repair

Independent review distinguishes demonstrated app defects from an inconclusive review. The latter retains its exact diagnostic in the durable tool receipt, exposes a retrieval pointer and tells the builder to retry the unchanged checked candidate within its existing budget. Review-only numeric roles are never SDK input metadata. Numeric fields are derived from the observed action contracts, including string-encoded decimals. Named-action counterexamples that claim saved effects validate declared input roles and original lookup-header positions before a shifted fixture can be blamed on generated source. This does not establish universal semantic equivalence; final realistic-workflow qualification remains in [[records/plans/excel-business-applications]].
