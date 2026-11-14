# Fresh Excel conversion batches

Twenty newly generated native apps from two consecutive complete ten-workflow local-model batches on frozen commit `da3c4720e05033b5aaea620ebb01abde28123d9e`. No generated app source was manually repaired and no app was replayed. Normal automatic repair remains part of the product flow.

The [receipt](../2026-11-14-fresh-excel-batches.json) records source provenance, exact scope, independent checks, installed identity, native visual observations and limits. Each batch passes 89 independent originals, 302 UI steps, 79 saved-edit/reopen/Undo cases and ten portable-copy checks. These repeat the same 89 unique originals; they are not 178 unique files.

| Batch | Workflow | Observed seconds | Builder tool calls |
| --- | --- | ---: | ---: |
| batch-02 | Inventory | 598 | 10 |
| batch-02 | Invoices | 187 | 2 |
| batch-02 | Timesheets | 149 | 1 |
| batch-02 | Cash flow | 117 | 1 |
| batch-02 | Commission | 217 | 1 |
| batch-02 | Loan | 168 | 1 |
| batch-02 | Production | 149 | 1 |
| batch-02 | Lookup quotes | 235 | 3 |
| batch-02 | Due dates | 314 | 4 |
| batch-02 | Reference codes | 596 | 8 |
| batch-03 | Inventory | 373 | 4 |
| batch-03 | Invoices | 151 | 1 |
| batch-03 | Timesheets | 175 | 2 |
| batch-03 | Cash flow | 154 | 1 |
| batch-03 | Commission | 163 | 1 |
| batch-03 | Loan | 619 | 9 |
| batch-03 | Production | 180 | 2 |
| batch-03 | Lookup quotes | 287 | 4 |
| batch-03 | Due dates | 249 | 2 |
| batch-03 | Reference codes | 295 | 3 |

Packages are inert evidence artifacts. Only workbook-specific dataset IDs are removed; generated source and all other package fields are preserved. Apps with translated Excel behavior must be attached through the checked conversion flow, not ordinary app import.

`trials-and-checks.json.gz` contains complete sanitized retained results, model calls and metrics, runtime manifests, failures and check logs. No model weights or real business data are included. Inspect with `gzip -dc trials-and-checks.json.gz`.

The first diagnostic batch failed two independent UI checks and is retained unchanged. The shared-checkout full suite later encountered another chat's unfinished source changes; the owner selected the frozen checkpoint and a clean isolated verification run. Newer chat-operation code is outside this acceptance. Two passing batches are finite evidence, not universal spreadsheet equivalence or a statistical reliability claim. Original VBA never executes.
