# Sevra app

This is the open-source native app for Sevra: a spreadsheet you run by talking
to it, with a local model. Chat is the input, the workbook keeps the database
(typed tables with history and Undo), and spaces are the output: Home and saved
views with tables, charts, totals, buttons, forms and small native apps, built
and changed through chat. Supplier quotes, Excel import, mini apps and inventory
are uses of that loop. See the [owner's statement](db/sources/notes/2026/11/chat-and-spaces-product.md).

## Start here

1. Read the [agent handoff](db/records/operations/agent-handoff.md): where the app
   stands, its [checkout context](db/records/operations/agent-handoff.md#checkout-context),
   open owner decisions and how to work here.
2. Read db/DB.md and [Start here](db/records/overview/start-here.md) before
   changing the project, and the owning plan in `db/records/plans/` before changing
   its area. Chat tools: read "The build so far" in the
   [general chat tools plan](db/records/plans/general-chat-tools.md).
3. If this repository is nested in a local workspace and `../AGENTS.md` exists,
   read it and its checkout/recovery notes. Standalone clones do not need it; this
   public repository stays self-contained. Keep machine-specific paths and private
   recovery evidence out of tracked app files.

Another agent may be working in the same checkout. Commit only the files your
change touched and preserve unrelated changes.

## What the owner has authorized

- **Build, package, install and test the interface on this Mac.** This started with
  the [native-engine approval](db/sources/notes/2026/11/programmable-native-engine.md)
  and was continued by each later request; see [Authorization history](#authorization-history).
  VoiceOver and system-setting changes are not authorized.
- **Chat works through the seven general tools only**, with no tool profile and no
  backward compatibility for the old tools ([removed](db/sources/notes/2026/11/general-tools-only.md)).
  Model SQL may change table shapes through the recorded write path, and `sql` keeps
  15-digit numbers ([answers](db/sources/notes/2026/11/general-tools-answers.md)).
- **Do not push or publish a release without the owner's word in the current
  request.** A request to build, fix or finish something is not that word.
- Cloud sync, transport, replica coordination and a new resolver are out of scope.
  Do not change the website business as a side effect.

## Public product language

The owner's [November 17 launch-copy direction](db/sources/notes/2026/11/readme-launch-wording.md)
applies. Call the product Sevra or Sevra Workbook. Describe the current Mac source
preview and its actual setup and feature limits without implying a production
release. Preserve historical labels in dated evidence and compatibility anchors.
Follow the [README copy review](db/records/reviews/readme-launch-copy.md) for the
four product distinctions, claim boundaries and publication checks. Keep public
claims tied to measured acceptance.

## Engineering

Swift/SwiftUI/AppKit; shared Swift core and CLI. Local inference uses upstream
Splash C++/Metal through a Python-free Swift adapter, under the
[integration spec](db/records/specs/splash-integration.md). Use the repo-owned
[update-splash skill](skills/update-splash/SKILL.md) for engine upgrades and keep
the unchanged native engine separate from the Swift frontend. Every file asset is
outside SQLite inside the workbook unless explicitly linked. Use deterministic
calculations, immutable input versions, lineage, bounded retrieval and truthful
completion. No hidden hosted model or telemetry.

Keep specifications and work records in this repo's db.md store. Update the owning
plan or review with each change, and keep the handoff a current-state page: replace
its sections rather than adding dated ones. No private paths, private repository
requirements, credentials or real business fixtures.

Before the first notarized, production-ready 1.0 release, do not keep backward
compatibility for development schemas, formats or CLI/agent contracts. Update the
canonical schemas and interfaces and recreate disposable fixtures instead of adding
migrations or adapters. Preserve current-format integrity and user data. The
controlling policy is [pre-1.0 compatibility](db/records/specs/distribution.md#pre-10-compatibility-policy);
the [persistence-readiness requirement](db/records/specs/persistence-readiness.md)
adds complete saved changes, causal identities, deterministic local reconstruction
and accurate decision provenance.

Outside agents learn the workbook from the CLI itself: `sevra agent` prints the
guide in `Sources/SevraCLI/AgentGuide.swift` followed by the live tool declarations,
and `sevra mcp` serves the same tools over MCP. Change the guide with the tools or
the CLI it describes. `skills/sevra/SKILL.md` only points to `sevra agent`.

## Git

Work directly on `main`, with no feature branch or pull request. Run
`dbmd index rebuild` before the suite, because its first step validates the
records. Commit messages never say Claude in any form, trailers and author names
included. To name the CLAUDE.md link or a .claude/ file, write "the agent
instructions" or "the agent settings". The repository's agent settings keep the
tool from adding attribution lines.

## Keep testing light

The owner stopped an overtested build on November 19, 2026:
[light testing direction](db/sources/notes/2026/11/light-testing-direction.md). An agent had run
every model job in two languages, with reruns and repeated timings, for hours. He had asked for
none of it. Here overtesting is a failure, the same as undertesting. These rules win over any
plan, skill, checklist or earlier habit that asks for more.

- **English only.** Do not test in another language unless the owner asks for that language.
- **Checks that need no model come first.** They carry the mechanics and take seconds. Run the
  ones that cover the change.
- **Model runs cover happy paths and the edge cases that matter, nothing else.** The routine run
  is the light set: `python3 scripts/check_chat_jobs.py --output DIR`, eleven jobs, one run
  each, under four minutes. Run another job by name only when its own area changes.
- **One run.** Read the transcript of a failure, then fix it or record it. Do not run it again to
  see whether it passes, and do not take a timing several times.
- **Ask before anything long.** If testing a change would take more than about five minutes of
  model or build time, or you want a job set, a language or a repeat these rules do not allow,
  stop and ask the owner first, and say how long it would take.
- **`scripts/check.sh` runs once on a candidate before a release.** It is not part of iterating.
- **A plan may not set a heavier gate than this.** When you write a plan, its tests are these.
  When you follow one that asks for more, these rules win and you say so.

The [focused verification policy](db/records/specs/distribution.md#focused-verification-policy)
says the same for fixes: verify the actual fix plus a nearby counterexample and reuse
unchanged evidence ([owner asked](db/sources/notes/2026/10/ship-with-enough-testing.md)).

## Interface quality

The owner explicitly requires deep visual and functional review of interface work.
Inspect spacing, alignment, density, hierarchy, empty/loading/error states, native
keyboard behavior and constrained-window layouts, not only compilation or saved
data. Fix observed issues and inspect the result.

## Native UI Catalog maintenance

The owner's [end-to-end catalog implementation request](db/sources/notes/2026/11/native-storybook-implementation.md)
authorizes the isolated developer app and its focused native visual/functional
verification. Read [Native UI Catalog](db/records/operations/native-ui-catalog.md)
when changing UI, navigation, Home/space components, mini-app protocol/SDK, visuals,
chat interactions or their lifecycle. Update the matching registry/fixture in the
same change; add a bounded state/composition for new capabilities. Exercise the
production path and one nearby refusal. Separate registration, rendering,
interaction evidence and visual review; never count an early-exiting runner as a
pass. Keep fixtures, scripts and controlled services out of normal packaging and
the shipped agent's prompt/tools. Do not open an active user workbook, download a
model, start product schedules or change OS settings for catalog checks.

## Authorization history

How the current authority came about, oldest first. These are history: the
sections above state what holds now.

- The [fast MVP](db/records/specs/mvp-delivery.md) delivery order, then the
  owner's October 29 [minimum feature increments](db/records/operations/minimum-feature-delivery.md).
- November 12: an [adversarial static accessibility review](db/records/reviews/accessibility-static-review-2026-11-12.md),
  [all ten code fixes](db/sources/notes/2026/11/accessibility-code-fixes-and-pause.md) and a
  [headless checkpoint](db/sources/notes/2026/11/accessibility-headless-tests-and-pause.md), after
  which work was paused with no app or UI use. The
  [known-limit closure plan](db/records/plans/known-limit-closure-2026-11-12.md) records what stayed open.
- The [native-engine request and installation/UI approval](db/sources/notes/2026/11/programmable-native-engine.md)
  ended that pause for the [native engine implementation](db/records/plans/programmable-native-engine.md).
  The same authority continued through the [local-model mini-app request](db/sources/notes/2026/11/local-model-native-apps.md)
  ([plan](db/records/plans/local-model-native-apps.md)), the [single Excel import request](db/sources/notes/2026/11/single-excel-import.md)
  ([plan](db/records/plans/single-excel-import.md)), the [Excel application reconstruction request](db/sources/notes/2026/11/excel-application-reconstruction.md)
  ([plan](db/records/plans/excel-application-reconstruction.md)) and the
  [whole-app adversarial review request](db/sources/notes/2026/11/app-engine-adversarial-review.md)
  ([plan](db/records/plans/app-engine-adversarial-review.md)).
- November 18 and 19: the [general chat tools authorization](db/sources/notes/2026/11/general-tools-implementation.md),
  the owner's [answers](db/sources/notes/2026/11/general-tools-answers.md), the request for the tools
  [in the app and the whole plan done](db/sources/notes/2026/11/general-tools-in-the-app.md), and the
  seven tools made the only chat tools with the old way [removed](db/sources/notes/2026/11/general-tools-only.md).
