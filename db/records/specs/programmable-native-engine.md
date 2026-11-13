---
type: spec
meta-type: conclusion
id: 01m78sah1afmhpr6vzfbkrg1r2
created: 2026-11-12T21:06:22.890879+00:00
updated: 2026-11-13T15:44:35.525507+00:00
summary: 'Native programmable spaces: scoped QuickJS/XPC execution, reactive AppKit rendering, shared transactional data, SDK authoring, recovery and bounded capabilities.'
title: Programmable native spaces SDK 1
status: implemented
---
# Programmable native spaces, SDK 1

A programmable space is a portable JavaScript program over native macOS controls and shared workbook data. It runs only after the user enables the exact saved version on this physical workbook. No WebKit, DOM, HTML, CSS, Node runtime or hosted service participates. The reviewed plan and acceptance evidence are in [[records/plans/programmable-native-engine]]. This implements a bounded first SDK, not unlimited macOS access or full Excel compatibility.

## Architecture

The existing SwiftUI workbook shell embeds a retained AppKit renderer. TypeScript/JSX compiles to a bundled JavaScript source package. A pinned QuickJS 2026-06-04 interpreter executes it in a separately sandboxed embedded XPC service. The desktop executable does not link QuickJS. Preact signals-core 1.14.5 supplies signal/computed/effect/batch; no React/Preact DOM or unstable React reconciler is used.

One helper service process can contain multiple independent connection runtimes. Each runtime has its own QuickJS heap; that is logical isolation, not separate OS protection between mini-apps. The service is the OS boundary against the host. A runtime exploit must still cross the validated host capability API. Nothing exposes native pointers, Objective-C selectors, filesystem access, network access, imports or OS modules to JavaScript. Host permissions are associated with the connection, never trusted from script-supplied workbook identifiers.

XPC exchanges are asynchronous, with session UUID and strictly ordered sequence numbers. Startup sends the saved code and native draft/revision state. Steady-state frames contain batched put/remove node patches, requests and subscriptions. The host validates the complete prospective tree before changing any views. Stable component identities preserve controls; only changed properties/structure are applied. Message queues coalesce replaceable input updates and retain discrete actions. Stale sessions and superseded subscription results are discarded.

Native controls own layout, input composition, cursor, selection, scrolling and gestures. Text controls acknowledge edit revisions so older script values cannot replace newer typing. Native canvas dragging updates the display locally; only click/drop decisions cross XPC. Native tables fetch 200-row pages directly from the host and use NSTableView recycling. Rows never cross JavaScript merely to scroll the table. Cell labels are vertically centered in 28-point native rows, columns fill the available width, and numeric columns align right. Programmatic refresh never emits selection events. A `Table` can bind `selection` to a logical row key (empty string clears it); explicit user selection emits the current exact row version.

## Authoring and lifecycle

Use `npm ci --prefix sdk`, then `node sdk/build.mjs examples/apps/inventory`. A custom app directory has `app.json` and `main.tsx`; the builder emits `app.sevraapp`. Authoring dependencies are locked; installed apps need no compiler or Node. Ship ordinary source, never untrusted QuickJS bytecode. The builder bundles JavaScript dependencies; modules needing browser, Node or native OS APIs will not work.

Import from `@sevra/sdk`. Components return JSX or `h(...)` descriptors. Call `mount(App)` once. A component function runs when mounted; reactive properties receive a signal or a getter. This is a documented signals-based component model, not React hook compatibility. Use `signal` for ephemeral state, `computed` for derived values, and `draftSignal(key, initial)` for recoverable input. Native-bound draft values are checkpointed before script processing. Effects and live queries created during component construction are disposed on unmount. Root/global resources live until that runtime closes.

`For` preserves row-local state by a stable `by` key, passing each child a signal containing its current item. Ordinary conditional child expressions replace changed descriptors; a preserved native position does not promise preservation of arbitrary JavaScript objects constructed again inside the expression. Use keyed `For` and component-owned signals for that state. Duplicate sibling keys refuse.

Available primitives: Column, Row, Grid, Split, Scroll, Section, Text, Button, TextField, TextEditor, Toggle, Picker, Slider, DatePicker, Progress, Table, Tabs, Disclosure, Canvas, Image and Spacer. Image displays native SF Symbols in SDK 1. Canvas supports rectangles, circles, lines and text with named hit regions, native drag feedback, arrow-key movement and accessibility buttons. Arbitrary file-backed images/documents, external APIs, OS extensions, custom compiled controls and per-frame JavaScript drawing require separately designed capabilities; the SDK does not imply those permissions. Existing ordinary workbook spaces still provide document/chart/media components.

Layout properties use native points, gap/padding, bounded optional width/height and semantic controls. There is no CSS. Labels/help, keyboard controls, system colors and native accessibility are part of the renderer. Canvas authors must name hit regions. Custom control semantics and broad assistive-technology behavior still need real user qualification.

## Package and data contract

A package contains `sdkVersion: 1`, `name`, bundled `source`, and `datasets` keyed by aliases. Each binding declares a title, columns, writable flag and optional existing dataset ID. Installation creates missing empty tables or validates existing tables. Updating an app reuses its previous alias bindings when IDs are omitted. A schema mismatch refuses instead of silently altering data. Schema evolution uses the existing native table/definition tools, then an updated package.

The installed package is part of SpaceDefinition and space_versions. Installation, revision and restoration use the existing captured transaction path. Removing/changing interface code never deletes business data. Exported app templates clear dataset IDs; portable workbooks retain exact app code, bindings, originals and data. Saving/importing/reconstructing does not execute scripts or grant access. Existing fixed spaces and app spaces coexist.

`liveQuery({table: 'stock', search, limit})` returns a signal with loading/error/rows/total/revision. `liveQuery(query, 'query')` uses the existing typed dataset query grammar with source aliases `{table:'stock'}` in place of physical dataset/definition identifiers. The native broker resolves current schema IDs and checks every alias. Each page, typed query and fingerprint read validates the exact approved columns and active table state in the same read transaction; added, removed or changed columns require an updated binding and fresh approval. A table rename alone does not expand access. `data.page` and `data.query` return one result. The existing deterministic Decimal query/aggregate and `calculate` paths remain authoritative for precision; JS Number is not a replacement for financial Decimal arithmetic.

Workbook revision polling is read-only and runs every 500 ms while the space is mounted. On a revision change the host compares bound-table schema and current immutable row fingerprints, then refreshes subscriptions dependent on changed aliases. It is deliberately invalidation plus bounded re-querying, not an incremental SQL engine. Native mutations also trigger an immediate revision check. Read snapshots identify their revision and exact row versions. Irrelevant workbook revisions update the revision signal without rebuilding unchanged query results.

`data.transaction(operations, {revision?, token?})` submits 1–64 insert/update/delete operations against writable aliases. Insert takes values; update/delete take an exact current row version ID. The default base is the last observed workbook revision; callers can pass the query revision explicitly. All operations commit atomically or none do. Permission, current package, schema, stale base, row membership and value constraints are checked natively. A final authority guard runs before commit. Revocation stops new work immediately; the final guard is the authorization linearization point for an already-committing operation. No arbitrary SQL/DDL is accepted.

Receipts contain the operation token, resulting revision and exact row IDs. Reusing a token with identical arguments returns the original receipt; different arguments refuse. `data.undo(receipt)` reverses the stored operation through a new captured transaction, only while its affected versions still match. Native app chrome offers undo of the latest session command. Immutable prior versions and the exact program digest remain in history. Programmatic writes are attributed as programmatic, not as human acceptance or AI output. Imported records preserve the workbook's origin/meaning distinctions.

## Permissions, recovery and limits

The native Enable surface lists requested table read/write access using names resolved from the bound workbook tables, not package-authored labels. Enable remains disabled until the native host validates those bindings. The device-local grant key includes the physical SQLite file identity, workbook ID, space ID/version and package digest. Changing code/bindings/version or copying/replacing the database requires a fresh grant. Each approval stores a fresh device-local generation. Data admission and the final write guard compare the captured generation, so Disable also fences other live sessions using that grant and reapproval cannot revive their old access. Revision polling removes stale UI even when no workbook data changed. Disable/navigation close the connection and revoke its in-memory capability; navigation alone does not erase the saved device approval. Development approvals and synthetic fixtures are disposable, with no conversion or migration path; [[sources/notes/2026/11/mini-app-fresh-start]] confirms the fresh baseline. Newly created apps follow the normal review and initial Enable flow. Draft checkpoints may finish after closing because they carry no business-write authority. Draft writes are serialized and restart waits for them. Native fields protect newer unsent values against older script frames.

Trusted chrome retains error/disable/restart controls outside the generated tree. A failed script poisons its runtime; it is not resumed in a partially evaluated state. Restart mounts saved source and retained drafts; it does not replay recorded database transactions. Authors must avoid unconditional business side effects during mount and retain operation tokens for explicit retry of uncertain requests. JavaScript source is portable but grants and OS privileges are not.

Current budgets: package 1 MiB, source 512 KiB, 16 dataset bindings of at most 50 columns, 64 MiB JS heap, 512 KiB JS stack, 500 ms per evaluation including microtasks, 10,000 microtasks, independent 3-second service watchdog, 4-second host response deadline, 2 MiB wire messages, 512 mounted nodes/depth 24, 128 messages per frame, 32 live queries/in-flight host requests, 120 frames/8 MiB output/16 transaction requests per second, 64 operations per transaction, 200-row native pages, 1 MiB returned data, and 64 KiB drafts. Exceeding a bound yields a visible refusal/failure rather than silently truncating business results. The table explicitly labels page coverage.

The sandboxed helper has only the app-sandbox entitlement. The packaged check verifies actual denial of a synthetic foreign file and network connection. Runtime memory and message limits complement OS isolation; no claim of invulnerability follows. Native host validation is required even if a script bypasses the SDK.

## Verification

Run `npm test --prefix sdk`, `python3 scripts/check_native_app_sources.py`, build `sevra-app-worker` and `sevra-native-app-checks`, then `python3 scripts/check_native_apps.py`. The packaged test uses the production SDK, service, host, AppKit renderer and workbook broker, including actual sandbox denials, native actions, reactive save, stable control identity and draft recovery. Core checks include refused/atomic writes, exact decimals, undo, portable/reconstructed code and data, stale/revoked grants, runaway scripts and malformed trees. SDK checks cover keyed state, conditional replacement, input acknowledgements, batching and cleanup.

The owner-authorized final installed journey, benchmark numbers, broad checks and precise qualification limits are recorded in [[records/plans/programmable-native-engine]]. Production notarization, uncoached external use and additional hardware remain separate gates.

## Design context

The owner describes small businesses doing the jobs they currently do with Excel, with spaces that become flexible mini apps. The explicit aesthetic is deeply native macOS: stable, fast, tightly integrated, with system controls rather than HTML/CSS. Favor calm and precise placement, readable business data and direct actions. Use native system fonts/colors, restrained spacing in a 4-point scale, centered row content and consistent field/action alignment. More flexible app logic must not compromise workbook authority or immediate native input. The November 12 spacing feedback specifically requests close attention to table rows and element placement.

## Interface review requirement

The owner's standing direction in [[sources/notes/2026/11/native-interface-quality]] requires actual inspection of spacing, hierarchy, native control alignment, states and compact windows. Each app surface uses a native scrolling viewport around natural-height content; the host UI stays outside it. App history loads bounded 50-version pages. This code-level support and the observed synthetic journeys do not claim comprehensive VoiceOver qualification.


## Accepted delivery and authoring limits

SDK 1 is implemented and accepted; see the plan and its portable receipts for exact
local, hosted and installed visual verification. The final authoritative-name
permission dialog and standard app re-enable flow both passed in the installed build. The three bundled examples are an
inventory editor, job tracker with grouped status counts, and visual card planner.
The planner deliberately shows the first 100 cards and discloses its total; its native
scrolling document grows to include those cards. Source/CLI/package import is the
programmable authoring path. Existing local-AI tools still compose ordinary fixed
spaces; this increment does not add an AI tool that generates JavaScript packages.


## Manual product walkthrough

Use a disposable workbook and the bundled `examples/apps/*/app.sevraapp` packages.
Choose **Workbook > Add Native App…**, select a package, open its space and review
its table access before **Enable app**.

1. **Inventory:** add an item and quantity, select its row, change the quantity,
   save, then use the native **Undo last change** action. Search for part of its
   name, try a name with no matches and clear search. Check centered row labels,
   right-aligned quantities and readable form labels.
2. **Jobs:** add a job and owner, select it, change its stage with the native picker
   and save. The grouped status count and table should agree. Use Tab to move
   through fields and controls; enter another job without touching the mouse.
3. **Planner:** add a card, drag it, select it and use arrow keys. Switch spaces
   and return; the saved position should remain. Enough cards to exceed the
   window should remain reachable by scrolling.
4. **Persistence and draft:** leave an unfinished inventory name, disable the
   app and enable it again. Its draft should return. Close and reopen the
   workbook; saved records and app source should remain.
5. **Code lifecycle:** export an app template from **App**, import it into another
   disposable workbook, and verify that it needs enabling and starts with its
   own tables. Updating an existing space keeps its bindings. Restoring code
   from the workspace action menu creates a new version, preserves business
   records and requires reviewing access again.
6. **Layout:** compare the split conversation/workspace layout with focused
   workspace, then make the window smaller. Check field labels, action grouping,
   row alignment, empty results and the table footer. Content must stay reachable
   through native scrolling while trusted app controls remain available.

## Local model authoring

The local workbook conversation now uses SDK discovery, exact source inspection and an isolated behavioral check followed by a separate local-model review before saving inert app source. See [[records/specs/local-model-native-apps]] for the authoring flow, authority and limits, and [[records/plans/local-model-native-apps]] for current acceptance. Unapproved programs use a distinct sandboxed check process; enabled apps retain the existing runtime process. Unhandled promise rejections are bounded failures. Canvas drop x/y values are movement deltas to add to the selected region's current position, not absolute destination coordinates. Shape IDs matching their region enable native drag feedback.

## November 13 adversarial follow-up

[[records/reviews/native-app-adversarial-review-2026-11-13]] records two permission findings and three native-state findings with failing probes and fixes. Disabled or hidden containers fence descendant interactions in the native renderer, host event dispatcher and authoring checker. Controlled table sort/selection and tab selection apply on the initial frame; tab title changes preserve current selection. These are bounded behavior guarantees, not general security certification.
