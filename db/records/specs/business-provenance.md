---
type: spec
id: 01m641bnzmgs5fexxwtebjeq6b
created: 2026-10-29T14:34:55.348731+00:00
updated: 2026-10-29T14:37:39.118255+00:00
summary: Reviewed schema27 role/seal capture, producer audit and bounded business-origin inspection. Implementation, independent roots and condition dispatch remain open.
title: Business contribution and control provenance
status: reviewed
---
# Business contribution and control provenance

This reviewed next E4 contract extends [[records/specs/condition-transition-inputs]], [[records/specs/automatic-ancestry]] and [[records/specs/automation-causality]]. The schema26 checkpoint retains exact changed versions, events and activation times. The existing broad lineage graph deliberately includes both data and configuration. Before actual candidate dispatch, the core must distinguish those relationships and prove complete retained input coverage. Do not use actor labels, model guesses or a missing edge as evidence of independent business origin.

## First-principles distinctions

A transformation has business data inputs, configuration/control inputs and an execution producer. These are different relationships, even when one exact version plays more than one role. A catalog row selected for its value is data. The query definition and dataset schema describe how to interpret/select it. The workflow invocation identifies who produced a proposed result. A permission Source records authority at that time; it is not an independent business observation and cannot restore authority later.

An accepted automatic proposal still has its producing run. A later human acceptance, correction, manual workflow, row edit, document edit or clarification cannot erase that origin. Superseding an existing business version retains its revision history. A completely independent observation may establish a new business origin only through the separate qualified business-root rule. The role graph alone never grants that independence.

Use conservative retained data dependencies where a transformation cannot qualify a smaller set. For example, published query provenance can include the complete scoped candidate population, including rows removed by a filter/join. State this coverage explicitly. It is not a minimal causal explanation. A narrower exact selected catalog-row path is appropriate for the already qualified one-match scalar lookup. Do not label broad query candidates as the exact rows that caused a condition crossing.

## Complete per-item role capture

Development schema27 is planned to add trusted role metadata to lineage and a small per-item derivation seal. Preserve existing child/parent/relation/transformation coordinates. Roles are data, control, producer and revision; one edge may have multiple roles. Represent their set canonically rather than letting control overwrite data when the same parent is used twice. A control-only edge is inspectable but is not traversed as business data. Supersession/revision of business inputs and a producer relationship retain automatic origin.

The derivation seal binds the policy, exact item, complete canonical edge count/hash and original-input classification. This detects accidentally missing/extra/altered role edges before an erased producer can look independent. The trusted insertion path must capture every item and edge in the same existing ledger transaction. Definition dependency edges currently added after item insertion must update the seal through one trusted helper within that item's creating transaction. No arbitrary later resealing of historical items, no model-supplied control labels, no raw-model DDL, second ledger or development-schema adapter. Reconstruction retains and verifies roles/seals without executing anything.

Public generic inputs remain conservative data inputs. Only audited host producer code supplies control/producer classifications. Source/Record category and meaning remain independent of these edge roles. An original-looking Source with no retained automatic parent is a candidate original input, not proof of human independence, authenticity or dispatch eligibility. Unknown/unsupported origin policies remain explicit and cannot silently become an empty independent origin.

## Chosen representation and implementation order

Use development schema27, with a roles integer appended to lineage and a derivation JSON seal appended to items. Bits are data=1, control=2, producer=4 and revision=8. They form a set, so an exact parent used for both data and control retains both roles. Public inspection renders named roles, not implementation bits. Existing relations and transformation coordinates remain intact. Ordinary derives-from edges use the first three roles; supersedes carries revision; definition-input carries control. Any unsupported role/relation combination refuses.

The fixed-size item-derivation-v1 seal binds the exact item, canonical ordered edge count/hash and an explicit unclassified-original versus retained-derivation classification. It does not claim human independence. Sort by exact ASCII parent identity and relation; hash canonical tuples including transformation and role set. Compute the initial seal before inserting the item and publish its edges in the same transaction. Avoid inserting an item with a placeholder seal and updating every large body a second time, which would unnecessarily amplify captured bytes and break the qualified 64 MiB transaction bound. Only the small same-transaction definition-dependency additions need resealing. Enforce creating-transaction membership through trusted connection-local capture state, cleared on commit/rollback, rather than scanning a growing captured-row array for every imported item.

Keep all metadata in existing captured items/lineage families; add no parallel origin ledger. Do not expose arbitrary role overrides through generic addItem, the CLI add operation or model tools. Extend trusted insertItem with explicit control/producer inputs, retaining conservative data inputs as the default. Merge roles when the same exact parent occurs in several sets. Schema-derived row definition inputs are control, unless that exact version is explicitly consumed as data too. Centralize same-transaction dependency publication/sealing instead of letting callers modify raw lineage after creation.

Implement in this order: role/seal capture and integrity; explicit classifications across the audited producers; role-aware bounded inspection; condition-window origin resolution; independent-root policy and integrated current-grant dispatch. Each phase must preserve ordinary storage, arithmetic, review and reconstruction. Do not enable condition workflows after only the first phases.

## Required producer audit and implementation

Audit and qualify all these paths before claiming general coverage:

- Original imports and structured intake: retain original asset/version/hash/extraction coordinates. Extraction/index refresh is interpretation of the existing original, not a new independent business occurrence. Source revisions preserve prior history.
- Generic Sources/Records and inventory movements: exact evidence and current-request versions are data; corrections retain superseded versions. No supplied metadata or actor label overrides a registered producer.
- Human acceptance, withdrawal, undo and table edits: retain the old proposal/version and new decision. Review is a new Source, never an ancestry reset. Decision context can remain inspectable control where it does not supply business values.
- Dataset creation/schema/edit/intake: schema versions are control when used to interpret rows; exact row versions, imported originals, proposals and prior versions remain data. Do not classify whole table membership as an exact per-row cause if the retained transformation only establishes a candidate population.
- Application definition authoring: retain all authoring evidence and exact dependencies. A definition used as configuration is control at the consuming edge. If explicitly consumed as data, that role must also remain represented.
- Published function/query results: resolved definitions and schema are control; explicit item arguments, retained row populations and submitted business evidence are data. Preserve exact publication snapshot/coverage and producer invocation. Do not imply per-group membership from a retained scoped population.
- Action/document publication: definitions are control; exact evidence, mapped interpretation/catalog values and prior business versions are data; the invoking workflow is producer. Direct manual actions have their captured submission as provenance, not a fabricated automatic run.
- Workflow invocation: bind exact workflow, typed nested item arguments, captured user request/form and origin. Separate configuration/authorization from data. Use the indexed authoritative workflow source binding to identify an automatic producer. A registered source with missing/erased/contradictory metadata refuses. Manual continuation keeps original producer history.
- Workflow interpretation/clarification: evidence and original interpreted versions remain data; exact interpretation definition is control; workflow invocation is producer. A human clarification or unsent AI preparation/confirmation does not clear the original automatic origin.
- Workflow scalar/function/query mappings: walk only the mapped upstream steps, retaining exact selected catalog row versions and model/clarification Records. Query definitions are control. Function chaining must carry the upstream data provenance instead of laundering it through a scalar literal. Preserve existing meaning/scenario checks.
- Workflow table intake: original file and exact target/membership dependencies remain data, mapping/schema definitions are control, and the workflow invocation is producer. Acceptance and row reconstruction preserve these paths.
- Generated and edited documents: source copies bind exact original versions/spans. A free-text revision or separate draft retains the original and new submission. Referencing or previewing an asset does not create a new business occurrence.
- Technical extraction/reference annotations and automation authorization/planning/dispatch Sources: retain their relationship for inspection. Treat control-only technical metadata as control. An annotation must not invent business independence or hide a real data/producer relationship.

There are only two direct production lineage insertion sites today: Workbook.insertItem and application-definition dependency publication. Centralize role/seal publication there, then pass audited classifications from the callers. Existing readers that assert exact relations, including acceptance, file-reference preservation and automatic parent bindings, must keep their invariants. The broad ancestry inspector continues to show all roles and remains explicitly non-minimal.

## Bounded data-origin inspection

Provide a read-only trusted inspection of exact versions, and subsequently exact retained condition windows. Preserve the existing three-second/short-wait cancellable snapshot and 8 MiB response budgets. Use indexed exact item/source/edge reads with the qualified graph bounds: at most16 supplied starting versions, 1024 visited items, 4096 edges and depth128. A condition window can contain more than16 inputs, so its later integrated resolver must process retained inputs in bounded captured pages or refuse explicit excess coverage; it cannot truncate to16 and claim a complete origin.

Validate the complete role seal for every visited version. Traverse data/revision/producer roles with DAG deduplication and cycle detection. Record control links separately for explanation. At an authoritative automatic workflow invocation, validate its saved run/automation/admission binding and retain that producer as an automatic parent boundary. Do not pull unrelated configuration ancestry into the business graph. Manual invocation paths continue through their actual data inputs and original automatic dependencies. Missing producers, erased metadata, unsupported policies, malformed/extra/missing edges, cycles, cancellation or limits refuse without a misleading partial success or an independent fallback.

Output explicitly distinguishes retained business dependency coverage, automatic producers, original-input candidates, unclassified origins and control links. Report minimalCauseSet=false, independentBusinessRoots=not-established, dispatchEligibility=not-evaluated, execution=none and enabled=false. These labels are part of the public contract. No new model tools or UI authoring grants are implied.

## Independent roots and actual dispatch remain separate

The subsequent candidate dispatcher must qualify independent business roots from exact accepted changes/clock activations and current human intent. It must not create one unrelated root per consumer or target automation for the same atomic business cause, which would bypass the shared root work budget. Distinct consumers responding to the same cause need shared root identity. An independent clock activation must bind the introducing business knowledge and effective instant, not today's wall clock alone. Mixed automatic/independent inputs need explicit merged origin semantics and bounds.

Unknown-gap, limit-exceeded, unclassified/unsupported producer or incomplete per-item/condition coverage cannot silently create a fresh root. Candidate resolution/admission/run/occurrence/Source/current-grant binding must eventually publish atomically. Saved history never restores a live physical-file/device/AI grant. Keep independent-root identity and the integrated dispatcher reviewed and tested before enabling it; this provenance slice does not choose that rule or add condition execution.

## Three review passes

1. Business meaning: preserve review/correction origin; distinguish data from configuration without ignoring dual roles; classify execution producers by authoritative bindings; avoid confusing candidate populations with exact/minimal causes or absence of ancestry with independent business evidence.
2. Persistence: every item/edge/seal shares capture and inert reconstruction. Later same-transaction definition edges are sealed, historical items cannot be resealed arbitrarily, and missing metadata/edges cannot erase an automatic producer. Existing acceptance/reference and automatic admission invariants remain valid.
3. Bounds and adversarial behavior: shared DAGs, dual roles, manual scalar chains, query population limits, same-version control/data, forged kind/origin labels, erased registered invocations, missing/extra/altered edges, cycles and cancellation refuse honestly. Large condition windows need explicit bounded resolution, not hidden truncation. Root deduplication and live dispatch authority remain later gates.

## Acceptance

Before enabling role-aware inspection, finish the audited classification at every producer caller using the representation above. Qualify original/derived/control paths for every listed producer family, automatic output followed by human review/correction/manual use, a manual workflow using an automatic-authored configuration with independent data, a selected catalog value versus unrelated configuration ancestry, function chaining, query candidate-population labeling, dual-role parents, complete source binding, mutation rollback/retry, foreign/missing/corrupt metadata, graph DAG/depth/edge/item limits, real lock cancellation and inert reconstruction.

Run full core for the schema change, focused role/origin checks, installed native read-only inspection and nearby condition/feed/ancestry/admission/owner/ProductAI/resource/refusal/signature checks. Preserve unchanged evidence and failed iterations, strict changed Swift lint, zero-warning db.md/link/diff checks, commit/push and exact CI. Fresh visible/native/hardware/production qualification remains separate. The whole app is not complete from this foundation.
