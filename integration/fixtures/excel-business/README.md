# Synthetic Excel business applications

These are invented business records, not customer workbooks or adoption evidence.
Each application has three related worksheets and three independently recalculated
originals: the base, one changed example visible to generation, and a second changed
example held out until after publication. `cases.json` records the owner's simulated
workflow requirements and independent conversational acceptance scenarios.
`adversarial.json` separately challenges each requested validation rule through the
actual generated named action. A valid control must succeed and Undo first; invalid
variants must report failure without changing values or immutable record versions.
The probes reuse observed input identities, never generated source edits or hidden
model instructions.

| Application | Source calculations and work |
| --- | --- |
| Stock | Products, signed movements, available stock/value/reorder; receipt, shipment, duplicate/overdraw refusal and a supplied price CSV |
| Invoices | Customers, invoice/payment/credit ledger and receivables; positive entered amounts and signed stored amounts |
| Jobs | Staff rates, time ledger and job costs/margins; cross-key joins, rate changes and hours validation |
| Production | Materials, production runs and capacity; planned/completed/cancelled transitions, whole batches and all-material checks |
| Cash | Assumptions, cashbook and forecast; PMT, zero-rate cases, periods and signed cash entries |
| Bookings | Resources, appointments and utilization; overlap checks, opening hours, reschedule/cancel and missing inputs |

The stock challenge additionally appends 205 records through the untouched generated
action and checks duplicate refusal beyond the first native page. Original formula
ranges end at row 1000; extending those ranges or copying formula rows is not part of
this corpus. Production's readable `CompleteRun.bas` is packed as inert VBA source;
Sevra reads its business rules but never executes the original macro. Its operation
checks have independently authored persisted-state assertions, not Microsoft Excel
macro-execution evidence.

## Reproduce the source fixtures

Set `CODEX_NODE_MODULES` to a runtime containing `@oai/artifact-tool`, then run:

```sh
node scripts/make_excel_business_fixtures.mjs
python3 scripts/finalize_excel_business_fixtures.py
```

Artifact-tool authors the source formulas and readable worksheet layouts. The
finalizer removes formula caches, forces recalculation in a fresh LibreOffice
profile, verifies new cached values, and packages the inert production macro.
`SEVRA_SOFFICE` can select the LibreOffice executable. The default is its ordinary
macOS application path. The original exports/renders stay under `.build`, while
these finalized source files are versioned.

## Check a fresh model cohort

Build `sevra-agent-checks`, `sevra-extract` and `sevra-app-worker`; rebuilding only the
agent does not refresh the worker SDK. `check_native_app_authoring.py` refuses a stale
SDK bundle. Use its `--excel-business-live MODELS GUIDANCE ENGINE OUTPUT` option with
a new output directory. The optional `SEVRA_BUSINESS_CASES` pipe-separated list is for
diagnostics; acceptance requires every case, twice consecutively on unchanged code.
The real model performs analysis, generation, automatic repair and conversational
operations. No package is reused or manually edited.

After the run, prepare independent spreadsheet scenarios from observed input states:

```sh
node scripts/prepare_excel_business_oracles.mjs OUTPUT
python3 scripts/recalculate_excel_fixtures.py OUTPUT/oracle-results OUTPUT/oracle-inputs/*.xlsx
python3 scripts/verify_excel_business_oracles.py OUTPUT
```

Only input values enter those spreadsheet copies; generated formula outputs remain
separate comparison data. All original formula outputs are compared after each
operation and Undo. This is independent LibreOffice recalculation, not an assertion
of universal Microsoft Excel parity. Runtime manifests retain source, fixture,
resource and binary hashes; failures remain evidence. Current acceptance and limits
belong in the [business-app plan](../../../db/records/plans/excel-business-applications.md).
