---
type: operational
id: 01m7n93txha62sa78z94gwdynr
created: 2026-11-17T17:33:14.033827+00:00
updated: 2026-11-17T18:12:12.772149+00:00
summary: Build, browse, reproduce and maintain the isolated native UI Catalog with real views, workbook/XPC semantics, controlled services and honest evidence.
title: Native UI Catalog
---
# Native UI Catalog

Sevra UI Catalog is a separate developer application built from the production
SwiftUI/AppKit views. It uses disposable synthetic workbooks, the signed app XPC
worker, real persistence/validation and scripted inference. It does not load model
weights, request speech permission, start a scheduler timer or open a user workbook.
The controlling implementation request is [[sources/notes/2026/11/native-storybook-implementation]];
the coverage contract is [[records/plans/native-storybook]].

## Build and open

From the current app checkout (resolve it using [[records/operations/agent-handoff]]):

```sh
bash scripts/build_ui_catalog.sh
open -n 'output/ui-catalog/Sevra UI Catalog.app'
```

The script resolves its own repository root, enables the native catalog build,
uses `.build/ui-catalog`, packages only to `output/ui-catalog`, and signs both real
app workers. It never installs or replaces the normal app. The catalog bundle has
its own identifier, no workbook document handler, and refuses an unbundled launch.
Compilation still needs the existing engine/toolchain build dependencies; runtime
stories do not need model files. Ordinary builds exclude `Sources/SevraApp/Catalog`.

## Explore

Search by name, stable ID, source or capability. The left outline separates
Compositions, Main app, Home & spaces, Mini apps, Chat and Shared visuals.

- Select a declared State, compact/standard/wide canvas, appearance and reading
  size. Inputs bounds labels and rows, with mini-app gap/grid/split controls; Apply reconstructs the fixture.
- Inputs describes the fixture and copies/loads a bounded JSON configuration.
- Behavior lists executable steps, actual receipts/refusals and the pending transport
  failure gate. Advance flow runs the next step; Reset reconstructs the initial state.
- Implementation locates production source, capability and recipe. Copy SDK/visual
  recipe exports the current synthetic authoring example.
- Window opens the real production surface separately, suitable for keyboard,
  sheets, popovers, drag/drop and native table review. Reset closes its owned window.
- Coverage distinguishes registration, missing render/interaction evidence and
  explicit manual/not-applicable limits. Record visual review needs a note and is
  tied to the reviewed configuration and workbook revision; later changes invalidate it.

Normal controls remain functional: table edit/Undo, form validation, app enable and
revoke, named app actions, sources, layout history, questions, approvals, menus and
exports all exercise the real paths. Native app actions are also callable through
chat's exact `app.run` operation. Free-form chat is scripted and says when no model
script exists; it is not an inference demo.

Every selection creates a new workbook and preference suite under a UUID temporary
root. Competing-edit stories deliberately use another connection to one fixture.
The captured/current composition deliberately shares a single owning workspace and
app session. Reset cancels and awaits preparation before closing the old session;
teardown cancels/awaits its UI task, releases the transport gate, flushes drafts, stops the owned automation
controller/workers and removes only that fixture. Graceful Quit waits for all live sessions. Preferences/grants do not travel
between ordinary stories. Exports are redirected to the catalog scratch root;
file selection supplies synthetic CSV input; external opens are recorded/refused.
Model setup and file transcription are controlled, without downloads/OS permission.

## Reproduce and capture

Commands run the exact packaged binary, without a browser/server:

```sh
'output/ui-catalog/Sevra UI Catalog.app/Contents/MacOS/Catalog' --list
'output/ui-catalog/Sevra UI Catalog.app/Contents/MacOS/Catalog' --capture visual.chart.bar --dark --width 900 --reading 1.5
'output/ui-catalog/Sevra UI Catalog.app/Contents/MacOS/Catalog' --capture composition.surfaces --steps 2
'output/ui-catalog/Sevra UI Catalog.app/Contents/MacOS/Catalog' --capture visual.image --variant Portrait --width 520
'output/ui-catalog/Sevra UI Catalog.app/Contents/MacOS/Catalog' --config output/ui-catalog/captures/visual.chart.bar-default-dark.config.json --capture visual.chart.bar
```

`--story` selects a story at interactive launch; `--config` selects its bounded
inputs. Batch capture also accepts `--variant`, `--width`, `--height`, `--reading`,
`--dark`, `--steps` (0–10), and `--output`. Unknown stories, unsupported variants and
out-of-range configurations are refused. `--list` is the machine-readable inventory
with sources, capabilities, state policy, transitions, initial configuration and
qualification limits. There is no catalog driver in the shipped agent prompt/tools.

PNG, receipt JSON and reusable configuration JSON default to the ignored
`output/ui-catalog/captures` directory. Receipts retain commit/dirty state, binary
UUID, SDK/OS, actual points/pixels/backing scale, locale/time zone, reading size,
service mode, fixture ID, readiness and actual events. Capture mounts and settles a
real window; it refuses unready/empty canvases. It never turns rendering into visual
approval. Separate sheets/popovers and Quick Look/media layers need live review.
Full-shell examples have a 740-point native minimum; focused workspaces have a
450-point minimum. The inspector labels requested dimensions, while captures record
actual dimensions. Mini-app/visual/comparison stories begin in workspace focus for
compact inspection. Smaller catalog windows collapse the inspector and then sidebar.

## Focused checks

```sh
python3 scripts/check_ui_catalog.py
python3 scripts/check_ui_catalog.py --fixtures
python3 scripts/check_ui_catalog.py --interactions
python3 scripts/check_ui_catalog.py --flows
npm run typecheck --prefix sdk
```

The first is cheap drift/metadata/source/route validation. Fixtures opens each
registered default once and validates real queries and expected worker states.
Interactions covers table edit/Undo/stale refusal, Home change/stale refusal, XPC
shared action/invalid input/revoke, typed false/duplicate answer, exact approval,
captured/current/preset/version/revoke, reopen and fixture isolation. Completion
requires an explicit terminal marker; a process that quits early is not a pass.
During repair, `--validate-fixtures --from <stable-ID>` resumes the packaged fixture
runner at a failed entry. The default runner remains the full declared set.

Flows replays all ten declared compositions through their production operations. The SDK
declaration fixture uses a pinned local TypeScript dependency; builds explicitly ignore
parent-project TypeScript settings, so a nested checkout produces the same bundles.

Run one affected story plus its nearby refusal while iterating. Reuse unchanged
core/SDK proof; do not add a per-pixel baseline or run every input combination.
At an integration/release checkpoint, use `scripts/check.sh` and ordinary native
compilation as required by [[records/specs/distribution]]. The catalog is not part
of the product release/install path.

## Maintenance contract for coding agents

For UI, navigation, schema, node/property, SDK helper/action input, visual style,
chat interaction or lifecycle changes, update the matching catalog fixture and
registry entry in the same change. Add a scoped story when a capability is new.
Closed sets compare against canonical core/protocol enums; the route inventory is
explicit. Do not inflate coverage with repeated generic screenshots or claim a
state exists merely because it has a selector label. Prefer the actual production
renderer and state transition, including its validation, authority and receipts.

Keep controlled external/presentation states explicit. Keep real workbook/XPC
semantics real. Never add catalog-only behavior to core validators, copy renderers,
swap process-global product preferences or place catalog fixtures/drivers in the
shipped agent's tool/prompt scope. Update the owning plan and append actual evidence.

OS accessibility, VoiceOver, additional hardware, real model reliability and
production signing/notarization remain separate qualification. A declared app
image view is intentionally unsupported; the native Image node uses a granted
image alias. Arbitrary JavaScript layouts and unbounded data are not enumerable.

## Accepted implementation checkpoint

The November 17 implementation has 176 registered/default-fixture entries, twelve
focused interaction paths, ten executable compositions and sixteen additional
state captures. The repository check, ordinary native compilation and focused
native visual/functional review pass. Read [[records/reviews/native-ui-catalog]]
for the precise commands, findings, reused evidence, build identities and limits.
This is a finite developer catalog, not approval of every selectable arrangement.
