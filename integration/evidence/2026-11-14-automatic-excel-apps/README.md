# Automatic Excel conversion evidence

Ten local-model-generated native app packages, with no manual UI or calculation-source repairs. These are inert evidence artifacts, not hand-authored reference implementations. Workbook-specific binding IDs are stripped; generated code is unchanged. Apps with Excel behavior must be attached through the checked Excel conversion flow, not bypass it through ordinary app import.

The [acceptance receipt](../2026-11-14-automatic-excel-reliability.json) identifies exact runtime/source hashes, installed build, native UI observations, verification and limits. All ten candidates pass the final runtime replay against 89 independently recalculated originals (84 comparison cases and five held-out cases), 302 independent UI steps, 79 saved-edit/reopen/Undo cases and ten portable copies.

| Workflow | Fresh generation origin | Original cases | Independent UI steps | Saved-edit/reopen/Undo cases |
| --- | --- | ---: | ---: | ---: |
| Inventory | qualification-15 | 5 | 28 | 5 |
| Invoices | qualification-7 | 9 | 38 | 8 |
| Timesheets | qualification-4 | 7 | 33 | 6 |
| Cash flow | qualification-4 | 7 | 33 | 6 |
| Commission | qualification-12 | 11 | 33 | 11 |
| Loan | qualification-12 | 13 | 33 | 14 |
| Production | qualification-4 | 7 | 28 | 6 |
| Lookup quotes | qualification-4 | 9 | 20 | 8 |
| Due dates | qualification-10 | 7 | 28 | 7 |
| Reference codes | qualification-4 | 9 | 28 | 8 |

`trials-and-checks.json.gz` contains the sanitized complete retained results, model messages and request metrics, runtime manifests, failure reproductions, interruptions and local check logs. Paths are replaced with `<checkout>`, `<home>` and `<temporary>`; original and sanitized hashes are distinguished. No real business data or model weights are included. To inspect: `gzip -dc trials-and-checks.json.gz`.

The accepted set combines successive fresh runs, not a single ten-of-ten trial or a statistical first-attempt success rate. Raw failed flags remain unchanged. Earlier Inventory passes missed partial numeric validation; an earlier Loan missed signed half-cent rounding; an earlier Invoice missed partial numeric and blank-plus-invalid-rate cases. Later source inspection exposed Loan blank-rate coercion, Due dates partial offsets, Inventory invalid stock, and Commission binary half-cent rounding and partial numeric rates. Another Inventory attempt repeated an overlapping action-write/formula-output declaration after an ambiguous diagnostic; precise feedback now identifies the conflict. Native PMT and supported formula reuse replace unnecessary generated financial calculations. Those weaker passes remain recorded and are not accepted for the expanded scope. Expanded originals disqualified those candidates and new model-generated candidates replaced them. A prior shipment-label mismatch and Loan-period/numeric-output harness errors are explicitly distinguished from product defects.

The original VBA is never executed. Inventory action checks use explicit changed inputs and saved recalculation, so original action-execution equivalence is not established. Original-result checks cover finite examples, not all Excel behavior. See the [fixture provenance](../../fixtures/excel-behavior/README.md).
