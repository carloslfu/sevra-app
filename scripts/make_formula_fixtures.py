#!/usr/bin/env python3
"""Writes the synthetic workbooks check_sheet_formulas.py compares Sevra against. LibreOffice
calculates and saves them, so every expected value comes from another spreadsheet engine.
Run this only to change the fixtures. The checks read the saved files and need no LibreOffice."""
import argparse
from pathlib import Path
import random
import shutil
import subprocess
import tempfile
from xml.sax.saxutils import escape, quoteattr

ROWS = 150
INPUTS = "'Inputs 2026'"
FIELDS = '''xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
 xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
 xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
 xmlns:of="urn:oasis:names:tc:opendocument:xmlns:of:1.2"'''


def cell(value):
    if value is None:
        return '<table:table-cell/>'
    if isinstance(value, str) and value.startswith('='):
        return f'<table:table-cell table:formula={quoteattr("of:" + value)}/>'
    if isinstance(value, str):
        return f'<table:table-cell office:value-type="string"><text:p>{escape(value)}</text:p></table:table-cell>'
    return f'<table:table-cell office:value-type="float" office:value="{value}"><text:p>{value}</text:p></table:table-cell>'


def sheet(name, rows):
    cells = ''.join('<table:table-row>' + ''.join(map(cell, row)) + '</table:table-row>' for row in rows)
    return f'<table:table table:name={quoteattr(name)}>{cells}</table:table>'


def amount(random_source):
    return random_source.choice([
        0, 1, 2, 3, 7, 10, 25, 100, -1, -4, 0.5, 0.25, 1.005, 2.675, 1234.5678, -19.99, 0.1, 0.2,
        random_source.randint(-500, 500), round(random_source.uniform(-1000, 1000), 2)])


def inputs(random_source):
    rows = [['Row', 'First', 'Second', 'Third', 'Note']]
    for number in range(2, ROWS + 2):
        rows.append([
            f'Line {number}',
            None if random_source.random() < 0.08 else amount(random_source),
            None if random_source.random() < 0.08 else amount(random_source),
            None if random_source.random() < 0.08 else amount(random_source),
            random_source.choice([None, None, 'n/a', 'checked', amount(random_source)])])
    return rows


def formulas():
    def source(row, column):
        return f'[{INPUTS}.{column}{row}]'

    def span(row, end):
        return f'[{INPUTS}.B{row}:.{end}{row}]'

    templates = [
        lambda r: f'={source(r, "B")}+{source(r, "C")}*{source(r, "D")}',
        lambda r: f'=({source(r, "B")}-{source(r, "C")})/{source(r, "D")}',
        lambda r: f'=SUM({span(r, "D")})',
        lambda r: f'=AVERAGE({span(r, "E")})',
        lambda r: f'=MIN({span(r, "E")})',
        lambda r: f'=MAX({span(r, "E")})',
        lambda r: f'=COUNT({span(r, "E")})',
        lambda r: f'=ROUND({source(r, "B")}/7;2)',
        lambda r: f'=ROUND({source(r, "C")}*1.005;2)',
        lambda r: f'=ROUND({source(r, "D")}*1234.5678;-2)',
        lambda r: f'=IF({source(r, "B")}>{source(r, "C")};{source(r, "B")};{source(r, "C")}*2)',
        lambda r: f'=IF({source(r, "B")}={source(r, "C")};1;0)',
        lambda r: f'=IF({source(r, "D")}<>0;{source(r, "B")}/{source(r, "D")};0)',
        lambda r: f'=-{source(r, "B")}%*50%',
        lambda r: f'=[.C{r}]*2+[.D{r}]',
        lambda r: f'=SUM([.$C$2:.C{r}])',
        lambda r: f'=[.$D$2]+[.P{r}]',
        lambda r: f'=COUNT([.B{r}:.Q{r}])',
        lambda r: f'=IF({source(r, "E")}>5;1;0)',
        lambda r: f'=IF({source(r, "E")}={source(r, "D")};1;0)',
        lambda r: f'=IF({source(r, "E")};1;2)',
        lambda r: f'=IF({source(r, "B")}>0;IF({source(r, "C")}>0;1;2);3)',
        lambda r: f'=SUM({source(r, "E")};{source(r, "B")};5)',
        lambda r: f'=MAX({span(r, "C")};10)-MIN({source(r, "D")};{source(r, "E")})',
    ]
    rows = [['Row'] + [f'Formula {index + 1}' for index in range(len(templates))]]
    for row in range(2, ROWS + 2):
        rows.append([f'Line {row}'] + [template(row) for template in templates])
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--soffice', default='/Applications/LibreOffice.app/Contents/MacOS/soffice')
    parser.add_argument('--out', type=Path, default=Path('integration/fixtures/formulas'))
    arguments = parser.parse_args()
    arguments.out.mkdir(parents=True, exist_ok=True)
    random_source = random.Random(20261030)
    before = inputs(random_source)
    after = [list(row) for row in before]
    for row in random_source.sample(range(1, ROWS + 1), 20):
        after[row][random_source.randint(1, 3)] = amount(random_source)
    with tempfile.TemporaryDirectory(prefix='sevra-formula-fixtures-') as temporary:
        root = Path(temporary)
        for name, values in [('libreoffice-before', before), ('libreoffice-after', after)]:
            document = root / (name + '.fods')
            body = sheet('Inputs 2026', values) + sheet('Formulas', formulas())
            document.write_text(
                f'<?xml version="1.0" encoding="UTF-8"?><office:document {FIELDS} office:version="1.3"'
                ' office:mimetype="application/vnd.oasis.opendocument.spreadsheet"><office:body>'
                f'<office:spreadsheet>{body}</office:spreadsheet></office:body></office:document>')
            subprocess.run([
                arguments.soffice, f'-env:UserInstallation=file://{root}/profile', '--headless',
                '--convert-to', 'xlsx', '--outdir', str(root), str(document)],
                check=True, capture_output=True, timeout=120)
            shutil.copyfile(root / (name + '.xlsx'), arguments.out / (name + '.xlsx'))


if __name__ == '__main__':
    main()
