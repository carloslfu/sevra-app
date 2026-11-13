---
type: operational
meta-type: operational
id: 01m79cc57776g0jbnzxjd021bs
created: 2026-11-13T02:39:19.271938+00:00
updated: 2026-11-13T04:51:08.137127+00:00
summary: Local model native-app authoring
title: Local model native-app authoring
---
# Local model native-app authoring

Owner: [[sources/notes/2026/11/local-model-native-apps]]. Builds on the accepted [[records/specs/programmable-native-engine]].

## Architecture passes

1. Preserve one runtime and one native component protocol. The local model writes plain JavaScript against the shipped SDK, without a compiler, web view, Node or a second scripting engine in the app. An SDK discovery tool provides exact properties, data shapes and examples.
2. Keep authority in the host. A sandbox check creates only disposable, schema-matching tables, strips all real bindings and exercises the same typed data API. Saving requires a host-owned proof for the exact source and tests, optimistic version checks and normal captured history. The model cannot grant runtime permissions. Each new version remains inert until the user enables it.
3. Keep claims narrower than evidence. Model-authored behavioral assertions establish their particular cases, not arbitrary semantic correctness. Save receipts report tested cases, no business rows inserted, and permission still required. Core tests, adversarial cases, actual local-model scenarios and installed visual checks supply independent evidence.

## Gates

- [x] A. SDK discovery, source inspection and sandbox-checked save/update tools; AI provenance, read-only and cancellation boundaries.
- [x] B. Real worker scenario runner: changes/clicks/selections, visible text and persisted row assertions; bounded work, temporary cleanup, no production bindings or permission grants.
- [x] C. Actual local-model cases: calculator, inventory, jobs/CRM, read-only existing data, requested edit and repair; verify behavior independently of the model's own assertions.
- [x] D. Adversarial review: syntax/loops, invalid native properties, forbidden APIs, wrong aliases, failed writes, stale edits, duplicate retry, read-only requests, cancellation and misleading output.
- [x] E. Installed chat creation/edit/enable/use, native layout and spacing, empty/error/loading states, compact viewport, persisted data/reopen and grants.
- [x] F. Required integration checks, records, commit/push and exact candidate verification. Report limits explicitly.

## Findings

Initial inspection confirms chat exposes only fixed native layouts and typed behavior definitions. Programmable packages are currently installed through CLI/import. The existing signed worker, SDK, native renderer, scoped data API and tool receipts can be reused; no parallel ledger or authority surface is needed.

Actual model acceptance now covers seven independent scenarios plus an inventory edit. See [synthetic receipts](../../../integration/evidence/2026-11-12-local-model-native-apps.json). The installed app is being exercised through ordinary chat and native controls. The full suite is running; E and F remain open.

## Final checkpoint

Gates E and F are closed for this bounded source-preview integration. The [final installed receipt](../../../integration/evidence/2026-11-12-local-model-native-app-final.json) and [[records/reviews/local-model-native-apps]] record exact candidate identity, scoped tests, native creation/edit/approval/use, compact layout, persistence and failures. The broad suite's model-busy packaging interruption was resolved by rerunning the native package/install/extraction tail with inference idle; final localized fixes passed focused authoring and full agent/grammar checks. The main UUID is `6F410451-9213-3901-AE05-925898D789BA`.

The final calculator was generated in a fresh focused thread, then enabled and tested through actual native controls. A preceding long-conversation retry still repeated a syntax error and safely stopped; model reliability is explicitly limited. Seven broader scenarios and an edit pass their independent checks. Human inspection remains necessary for generated behavior and layout. Commit/push carries this checkpoint on main; historical hosted CI is not evidence for newer source. This is not a notarized production release or universal Excel replacement.
