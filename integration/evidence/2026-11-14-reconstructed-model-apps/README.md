# Excel reconstruction model and reviewed-app evidence

These synthetic development artifacts preserve both success and failure. They are
not standalone business apps: behavior requires the original workbook, host
comparison and per-device access review.

- The three top-level `.sevraapp` files are unchanged local-model outputs from
  Inventory trial 2 and Loan/Lookup trial 7. `results.json` records their original,
  narrower checks. They are **not accepted final apps**. Expanded checks found
  missing numeric shipment validation, a wrong zero-interest loan sign, and lookup
  keys copied as constants. `boundary-before.json` reproduces all three against the expanded originals.
- `live-9-results.json` and `live-10-results.json` retain later fresh unassisted
  failures. Trial 9 Loan reached a saved app but its probe still referenced the
  old Input label; that harness mismatch was fixed to Principal. Its zero-interest
  logic was also wrong. Trial 10 Inventory and Loan both stopped after repeated
  unsuccessful actions. Do not count these as passing trials.
- `reviewed/` contains explicitly manually reviewed derivatives, **not fresh model
  output**. Repairs cover finite numeric validation, the zero-interest sign,
  reference-cell lookup keys and error results, persistent business field labels,
  and neutral validation feedback. Its results and hashes describe the exact
  tested derivatives. Each passes host comparisons and independent UI checks.

The reference set has 43 LibreOffice-calculated original files across ten business
cases, including zero-interest, renamed lookup and invalid-number boundaries.
No model receives the reference JavaScript translations in actual inference.

To replay a retained candidate, build the authoring checker and extraction/worker
products, then run `scripts/check_native_app_authoring.py --excel-behavior-live`
with normal local resources and a fresh output directory. Set
`SEVRA_EXCEL_REPLAY_DIR` to this directory for the old failing candidates or to
`reviewed/` for the reviewed derivatives. Replay rebinds only host table identities
and does not run fresh inference.

The engine and reviewed workflows have bounded verification. Unassisted model
conversion is not consistently reliable, and finite comparisons do not establish
universal Excel equivalence. See the owning review for installed UI and source
coverage, failures, repairs and qualification limits.
