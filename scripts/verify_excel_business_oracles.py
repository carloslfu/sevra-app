#!/usr/bin/env python3
"""Compare all formula outputs with independently recalculated spreadsheet values."""
import decimal
import json
import pathlib
import sys
import xml.etree.ElementTree as ET
import zipfile

NS = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}


def cells(path):
    with zipfile.ZipFile(path) as archive:
        strings = []
        if 'xl/sharedStrings.xml' in archive.namelist():
            strings = [''.join(node.itertext()) for node in ET.fromstring(
                archive.read('xl/sharedStrings.xml')).findall('s:si', NS)]
        sheets = []
        workbook = ET.fromstring(archive.read('xl/workbook.xml'))
        rels = {node.attrib['Id']: node.attrib['Target'] for node in ET.fromstring(
            archive.read('xl/_rels/workbook.xml.rels'))}
        for sheet in workbook.findall('s:sheets/s:sheet', NS):
            target = rels[sheet.attrib['{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id']]
            target = target.lstrip('/') if target.startswith('/') else 'xl/' + target
            values = {}
            for cell in ET.fromstring(archive.read(target)).findall('.//s:sheetData/s:row/s:c', NS):
                value = cell.findtext('s:v', default='', namespaces=NS)
                if cell.get('t') == 's':
                    value = strings[int(value)]
                elif cell.get('t') == 'inlineStr':
                    value = ''.join(cell.find('s:is', NS).itertext())
                values[cell.attrib['r']] = value
            sheets.append(values)
        return sheets


def equivalent(actual, expected):
    if actual == expected:
        return True
    try:
        a, b = decimal.Decimal(actual), decimal.Decimal(expected)
        return a.is_finite() and b.is_finite() and abs(a-b) <= max(abs(a), abs(b), decimal.Decimal(1)) * decimal.Decimal('0.00000000000005')
    except decimal.InvalidOperation:
        return False


def main():
    root = pathlib.Path(sys.argv[1])
    manifest = json.loads((root / 'oracle-manifest.json').read_text())
    results = []
    count = 0
    for scenario in manifest:
        expected = cells(root / 'oracle-results' / scenario['file'])
        mismatches = []
        for output in scenario['outputs']:
            column = output['column']
            address = ''
            while column >= 0:
                address = chr(65 + column % 26) + address
                column = column // 26 - 1
            address += str(output['row'] + 1)
            value = expected[output['sheet']].get(address, '')
            if not equivalent(str(output['actual']), value):
                mismatches.append({**output, 'cell': address, 'expected': value})
            count += 1
        results.append({'slug': scenario['slug'], 'step': scenario['step'], 'mismatches': mismatches})
    report = {'scenarios': len(results), 'formulaComparisons': count, 'results': results,
              'passed': bool(results) and count > 0 and all(not row['mismatches'] for row in results)}
    (root / 'oracle-verification.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
