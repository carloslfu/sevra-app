# Conditional-sum semantics

This synthetic corpus exercises SUMIF/SUMIFS ranges, numeric/text/blank criteria,
comparison operators, wildcards, escaped characters and spreadsheet errors.
Artifact-tool creates the source. The finalizer strips caches and forces a fresh
LibreOffice recalculation; `cases.json` preserves those actual results.

```sh
node scripts/make_excel_conditional_fixtures.mjs
python3 scripts/finalize_excel_conditional_fixtures.py
```

`CODEX_NODE_MODULES` locates artifact-tool and `SEVRA_SOFFICE` optionally locates
LibreOffice. Six cases have explicit Excel-contract expectations in
`Tests/SheetFormulaChecks.swift` because Calc differs around numeric-text criteria,
text collation or error/wildcard matching. The reference results are not overwritten
to agree with Sevra. Those six expectations derive from Microsoft's
[SUMIF](https://support.microsoft.com/en-us/excel/functions/sumif-function) and
[SUMIFS](https://support.microsoft.com/en-us/excel/functions/sumifs-function)
contracts and Apache POI's
[criteria implementation](https://github.com/apache/poi/blob/trunk/poi/src/main/java/org/apache/poi/ss/formula/functions/Countif.java).
They are not Microsoft Excel execution evidence. Original-result comparison remains
required when importing an actual workbook.
