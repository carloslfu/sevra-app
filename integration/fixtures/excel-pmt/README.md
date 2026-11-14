# Constant-payment formula originals

Synthetic inputs only. LibreOffice recalculated the 24 PMT cases in `pmt.xlsx`; `results.json` is extracted from its saved numeric/error cells, not calculated by Sevra or JavaScript. Cases cover payment timing, future balances, signed/fractional periods, negative and tiny rates, blank/text/error operands, half-cent rounding and overflow. These are separate formula-engine regressions, not extra successful model-conversion trials.

The standard arguments and timing follow [Microsoft PMT documentation](https://support.microsoft.com/en-us/excel/functions/pmt-function). Edge-result qualification uses the saved LibreOffice originals; it is not Microsoft Excel execution qualification. The normal import gate still refuses to recalculate a formula whose initial result disagrees with its original cache.

Regenerate with `python3 scripts/make_pmt_fixtures.py`; checks require only the retained files, not LibreOffice. Original financial inputs are public synthetic test data.
