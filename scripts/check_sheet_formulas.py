#!/usr/bin/env python3
"""Current-format synthetic CLI journeys for the declared Excel formula subset: which cells
recalculate, which keep their saved value and why, across edits, Undo, export and reopen."""
import argparse
import json
from pathlib import Path
import signal
import sqlite3
import subprocess
import tempfile
import time

from check_table_updates import write_xlsx


def formula(text, saved, **extra):
    return (saved, {'formula': text, **extra})


def shared(group, text=None, cells=None):
    """Excel writes a filled column once: the first cell has the text, the rest only a group."""
    if text is None:
        return f'<f t="shared" si="{group}"/>'
    return f'<f t="shared" ref="{cells}" si="{group}">{text}</f>'


BUDGET = {
    'Items': {
        1: ['Item', 'Quantity', 'Price', 'Line total'],
        2: ['Bolts', 10, 2, (20, {'f': shared(0, 'B2*C2', 'D2:D4')})],
        3: ['Nuts', 5, 3, (15, {'f': shared(0)})],
        4: ['Washers', 4, 0.5, (2, {'f': shared(0)})],
        5: ['Total', None, None, formula('SUM(D2:D4)', 37)],
        6: ['Average', None, None, formula('AVERAGE(D2:D4)', 12.3333333333333)],
        7: ['Rounded', None, None, formula('ROUND(D6,1)', 12.3)],
        8: ['With tax', None, None, formula("D5*(1+'Tax rate'!$B$1)", 44.03)],
        9: ['Lines', None, None, formula('COUNT(B2:B4)', 3)],
        10: ['Lookup', None, None, formula('VLOOKUP(A2,A2:D4,4,FALSE)', 20)],
        11: ['Reads lookup', None, None, formula('D10*2', 40)],
        12: ['Disagrees', None, None, formula('D5+1', 999)],
        13: ['Loop one', None, None, formula('D14+1', 1)],
        14: ['Loop two', None, None, formula('D13+1', 2)],
        15: ['No saved value', None, None, formula('D5', None)],
        16: ['Text', None, None, formula('"a"&"b"', 'ab')],
        17: ['Percent', None, None, formula('D5*10%', 3.7)],
        18: ['Branch', None, None, formula('IF(D5>30,D5,0)', 37)],
        19: ['Per washer', None, None, formula('D4/B4', 0.5)],
    },
    'Tax rate': {
        1: ['Rate', 0.19],
        3: ['Total with tax', formula('Items!D8', 44.03)],
        4: ['Lines', formula('SUM(Items!D2:D4)', 37)],
    },
    'Notes': {1: ['Plain text only']},
}


def same(first, second):
    """Equal text, or numbers within the last places binary arithmetic can leave."""
    try:
        a, b = float(first), float(second)
    except ValueError:
        return first == second
    return abs(a - b) <= max(abs(a), abs(b)) * 5e-14


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, default=Path('output/native/bin/sevra'))
    cli = parser.parse_args().cli.resolve()
    checks = []

    def run(*args, error=None, timeout=240):
        reply = subprocess.run([str(cli), *map(str, args)], capture_output=True, text=True, timeout=timeout)
        data = json.loads(reply.stdout if reply.returncode == 0 else reply.stderr)
        if error:
            assert reply.returncode != 0 and data['error']['code'] == error, data
            return data['error']
        assert reply.returncode == 0 and data['ok'], data
        return data['result']

    def checked(name, condition):
        assert condition, name
        checks.append(name)

    def tables(book):
        return {t['title'].rsplit(' · ', 1)[-1]: t for t in run('tables', book)}

    def grid(book, table):
        """Cells by Excel row, in stored order. Row numbers come from the first column."""
        return {row['data']['c1']: row for row in run('rows', book, table['id'])}

    def edit(book, row, **cells):
        return run('edit-row', book, row['id'], json.dumps({**row['data'], **cells}))

    with tempfile.TemporaryDirectory(prefix='sevra-sheet-formulas-') as temporary:
        root = Path(temporary)
        budget = root / 'Budget.xlsx'
        write_xlsx(budget, BUDGET)
        book = root / 'Budget.sevra'
        run('create', book, 'Synthetic budget')
        imported = run('import', book, budget, '--role', 'values')['intake']
        sheets = tables(book)
        items = sheets['Items']
        report = run('table-formulas', book, items['id'])
        reasons = {cell['cell']: cell['reason'] for cell in report['savedCells']}
        checked('import reports how many formulas recalculate',
                imported['state'] == 'ready' and 'recalculate' in imported['detail']
                and report['recalculating'] == 11 and report['saved'] == 7
                and report['valuesChanged'] is False)
        checked('an unsupported function is named',
                reasons['D10'] == 'Uses VLOOKUP, which Sevra does not calculate.')
        checked('a formula reading a saved value keeps its own saved value',
                reasons['D11'].startswith('Reads ') and 'D10' in reasons['D11'])
        checked('a result that differs from Excel keeps the saved value',
                'differs' in reasons['D12'] and grid(book, items)['Disagrees']['data']['c4'] == '999')
        checked('a circular reference keeps its saved values',
                'circular' in reasons['D13'] and 'circular' in reasons['D14'])
        checked('a formula with no saved value stays unresolved',
                'no value' in reasons['D15']
                and grid(book, items)['No saved value']['data']['c4'] == '#NO_CACHED_VALUE')
        filled = root / 'Filled.xlsx'
        write_xlsx(filled, {'Fill': {
            1: [1, (2, {'f': shared(0, '+'.join(['A1'] * 1300), 'B1:B2701')})],
            **{row: [1, (2, {'f': shared(0)})] for row in range(2, 2702)}}})
        fill = run('import', book, filled, '--role', 'values')['intake']
        checked('a fill past its bound imports and keeps its saved values',
                fill['state'] == 'ready' and 'recalculate' in fill['detail']
                and run('table-formulas', book, fill['datasetIDs'][0])['recalculating'] == 0)
        checked('text operators keep the saved value',
                reasons['D16'] == 'Uses text values, which Sevra does not calculate.')
        rows = grid(book, items)
        checked('import leaves every saved value as Excel wrote it',
                [rows[name]['data']['c4'] for name in ('Bolts', 'Nuts', 'Washers', 'Total', 'Rounded')]
                == ['20', '15', '2', '37', '12.3'])

        edit(book, rows['Bolts'], c2='20')
        rows = grid(book, items)
        tax = grid(book, sheets['Tax rate'])
        checked('an edit recalculates shared formulas and every dependent cell',
                rows['Bolts']['data']['c4'] == '40' and rows['Total']['data']['c4'] == '57'
                and rows['Average']['data']['c4'] == '19' and rows['Rounded']['data']['c4'] == '19'
                and rows['With tax']['data']['c4'] == '67.83' and rows['Percent']['data']['c4'] == '5.7'
                and rows['Branch']['data']['c4'] == '57')
        checked('an edit reaches formulas on another sheet',
                tax['Total with tax']['data']['c2'] == '67.83' and tax['Lines']['data']['c2'] == '57')
        checked('cells that cannot recalculate keep their values and say they may be behind',
                rows['Lookup']['data']['c4'] == '20' and rows['Reads lookup']['data']['c4'] == '40'
                and run('table-formulas', book, items['id'])['valuesChanged'] is True)
        checked('recalculation keeps the workbook valid', run('verify', book)['ok'] is True)
        edit(book, tax['Rate'], c2='0.25')
        rows = grid(book, items)
        checked('an edit on the other sheet flows back',
                rows['With tax']['data']['c4'] == '71.25'
                and grid(book, sheets['Tax rate'])['Total with tax']['data']['c2'] == '71.25')
        edit(book, grid(book, sheets['Tax rate'])['Rate'], c2='0.19')
        page = run('tool', book, 'rows', json.dumps({'datasetID': items['id']}))
        lookup = next(row for row in page['rows'] if row['values']['c1'] == 'Lookup')
        total = next(row for row in page['rows'] if row['values']['c1'] == 'Total')
        checked('agent tools see which cells recalculate and which keep saved values',
                page['excelFormulas']['saved'] == 7
                and lookup['excelFormulas']['c4']['reason'].startswith('Uses VLOOKUP')
                and total['excelFormulas']['c4']['formula'] == 'SUM(D2:D4)'
                and 'reason' not in total['excelFormulas']['c4'])
        update = root / 'Incoming.csv'
        update.write_text('A,B\nRate,0.5\n')
        captured = run('import', book, update, '--role', 'update')
        run('table-update-preview', book, captured['source']['id'], sheets['Tax rate']['id'],
            json.dumps({'mode': 'replace', 'mapping': [{'position': 0, 'target': 'c1'},
                        {'position': 1, 'target': 'c2'}], 'keys': []}), error='update_formulas')
        checked('a reviewed update cannot silently replace rows formulas read',
                grid(book, sheets['Tax rate'])['Rate']['data']['c2'] == '0.19')

        before = rows['Total']['data']['c4']
        run('edit-row', book, rows['Total']['id'], json.dumps({**rows['Total']['data'], 'c4': '1'}),
            error='calculated_cell')
        checked('a recalculating cell refuses a typed value',
                grid(book, items)['Total']['data']['c4'] == before)
        edit(book, rows['Lookup'], c4='21')
        rows = grid(book, items)
        checked('a saved-value cell can still be corrected by hand, and nothing recalculates from it',
                rows['Lookup']['data']['c4'] == '21' and rows['Reads lookup']['data']['c4'] == '40')

        edit(book, rows['Nuts'], c2='many')
        rows = grid(book, items)
        checked('text in an input shows an error and carries it forward',
                rows['Nuts']['data']['c4'] == '#VALUE!' and rows['Total']['data']['c4'] == '#VALUE!'
                and rows['Lines']['data']['c4'] == '2')
        edit(book, rows['Nuts'], c2='5')
        edit(book, grid(book, items)['Washers'], c2='0')
        rows = grid(book, items)
        checked('a corrected input recovers, and division by zero is shown',
                rows['Nuts']['data']['c4'] == '15' and rows['Total']['data']['c4'] == '55'
                and rows['Per washer']['data']['c4'] == '#DIV/0!')
        edit(book, rows['Washers'], c2='4')

        archive = root / 'Budget.sevraz'
        reopened = root / 'Reopened.sevra'
        run('export', book, archive)
        run('open-archive', archive, reopened)
        moved = tables(reopened)
        rows = grid(reopened, moved['Items'])
        edit(reopened, rows['Bolts'], c3='3')
        rows = grid(reopened, moved['Items'])
        checked('an exported workbook keeps recalculating after it reopens',
                rows['Bolts']['data']['c4'] == '60' and rows['Total']['data']['c4'] == '77'
                and run('verify', reopened)['ok'] is True
                and run('table-formulas', reopened, moved['Items']['id'])['recalculating'] == 11)

        # Undo restores a row version without going through a table edit.
        rows = grid(reopened, moved['Items'])
        run('undo', reopened, rows['Bolts']['id'])
        rows = grid(reopened, moved['Items'])
        checked('undoing a row recalculates everything that read it',
                rows['Bolts']['data']['c3'] == '2' and rows['Bolts']['data']['c4'] == '40'
                and rows['Total']['data']['c4'] == '57' and run('verify', reopened)['ok'] is True)

        # Removing a column a formula reads breaks the reference instead of leaving old totals.
        schema = run('table-schema', reopened, moved['Items']['id'])
        run('table-edit-schema', reopened, moved['Items']['id'], schema['version'],
            schema['definitionID'], json.dumps({'columns': [
                c for c in schema['columns'] if c['id'] != 'c3']}), 'drop-price')
        rows = grid(reopened, moved['Items'])
        checked('a removed column shows a broken reference',
                rows['Bolts']['data']['c4'] == '#REF!' and rows['Total']['data']['c4'] == '#REF!')

        # Filled formulas keep absolute parts and move relative ones. A stop keeps one plan.
        rows_needed = 2300
        filled = root / 'Filled.xlsx'
        write_xlsx(filled, {
            'Rates': {1: ['Rate', 2]},
            'Lines': {
                1: ['Units', 'Cost'],
                2: [1, (2, {'f': shared(0, '$A2*Rates!$B$1', f'B2:B{rows_needed}')})],
                **{n: [n - 1, (2 * (n - 1), {'f': shared(0)})] for n in range(3, rows_needed + 1)},
            }})
        book = root / 'Stopped.sevra'
        run('create', book, 'Synthetic stopped')
        process = subprocess.Popen([str(cli), 'import', book, filled, '--role', 'values', '--token', 'one'],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline and process.poll() is None:
            try:
                connection = sqlite3.connect(f'file:{book / "workbook.sqlite"}?mode=ro', uri=True, timeout=5)
                saved = [json.loads(row[0])['completed'] for row in connection.execute(
                    "SELECT value FROM meta WHERE key LIKE 'intake:%'")]
                connection.close()
            except sqlite3.Error:
                saved = []
            if sum(saved) >= 1000:
                process.send_signal(signal.SIGINT)
                break
            time.sleep(0.01)
        _, stopped = process.communicate(timeout=120)
        job = run('intake-status', book)['jobs'][0]
        checked('the stop reached the import before it finished',
                process.returncode != 0 and json.loads(stopped)['error']['code'] == 'cancelled'
                and job['state'] == 'cancelled')
        finished = run('intake-resume', book, job['id'])
        repeat = run('import', book, filled, '--role', 'values', '--token', 'one')
        lines = tables(book)['Lines']
        checked('a stopped import builds its formulas once and they cover every row',
                finished['state'] == 'ready' and repeat['intake']['id'] == finished['id']
                and run('table-formulas', book, lines['id'])['recalculating'] == rows_needed - 1
                and len(run('records', book, 'excel-formulas')) == 1)
        rates = tables(book)['Rates']
        first = run('rows', book, rates['id'])[0]
        run('edit-row', book, first['id'], json.dumps({**first['data'], 'c2': '3'}),
            error='formula_limit')
        checked('an edit past the rewrite bound saves nothing',
                run('rows', book, rates['id'])[0]['data']['c2'] == '2'
                and run('rows', book, lines['id'], 1)[0]['data']['c2'] == '2')

        # Bounds keep the saved values rather than recalculating part of a file.
        many = root / 'Many.xlsx'
        write_xlsx(many, {'Sheet1': {
            n: [n, formula(f'A{n}*2', n * 2)] for n in range(1, 10_002)}})
        book = root / 'Many.sevra'
        run('create', book, 'Synthetic many')
        run('import', book, many, '--role', 'values')
        table = tables(book)['Sheet1']
        report = run('table-formulas', book, table['id'])
        checked('a file over the formula bound keeps every saved value and says why',
                report['recalculating'] == 0 and report['saved'] == 10_001
                and 'too many' in report['savedCells'][0]['reason'])

        # Excel sees numbers and dates that imported as text. The saved value exposes the gap.
        typed = root / 'Typed.xlsx'
        write_xlsx(typed, {'Sheet1': {
            1: ['0012', formula('SUM(A1:A2)', 5)], 2: [5, 'x'],
            3: [(45000, {'style': 1}), formula('A3+30', 45030)],
        }}, formats=['yyyy-mm-dd'])
        book = root / 'Typed.sevra'
        run('create', book, 'Synthetic typed')
        run('import', book, typed, '--role', 'values')
        table = tables(book)['Sheet1']
        report = run('table-formulas', book, table['id'])
        checked('text that looks numeric and dates stay on their saved values',
                report['recalculating'] == 0
                and {cell['cell'] for cell in report['savedCells']} == {'B1', 'B3'})

        # Array formulas fill cells of their own. A cell reading one cannot be current.
        filled = root / 'Filled.xlsx'
        write_xlsx(filled, {'Sheet1': {
            1: [2, (4, {'f': '<f t="array" ref="B1:B2">A1:A2*2</f>'})],
            2: [3, 6],
            3: [None, formula('B2+1', 7)],
        }})
        book = root / 'Filled.sevra'
        run('create', book, 'Synthetic filled')
        run('import', book, filled, '--role', 'values')
        report = run('table-formulas', book, tables(book)['Sheet1']['id'])
        checked('array formulas and cells reading them keep saved values',
                report['recalculating'] == 0
                and {cell['cell'] for cell in report['savedCells']} == {'B1', 'B2', 'B3'})

        # A column given a type keeps it, and an archived table stays current with its file.
        linked = root / 'Linked.xlsx'
        write_xlsx(linked, {
            'Lines': {1: [10, 2, formula('A1/B1', 5)]},
            'Other': {1: [1, formula('Lines!C1+A1', 6)]},
        })
        book = root / 'Linked.sevra'
        run('create', book, 'Synthetic linked')
        run('import', book, linked, '--role', 'values')
        sheets = tables(book)
        lines = sheets['Lines']
        schema = run('table-schema', book, lines['id'])
        columns = [{**c, 'type': 'decimal'} if c['id'] == 'c3' else c for c in schema['columns']]
        run('table-edit-schema', book, lines['id'], schema['version'], schema['definitionID'],
            json.dumps({'columns': columns}), 'number-column')
        first = run('rows', book, lines['id'])[0]
        refused = run('edit-row', book, first['id'], json.dumps({**first['data'], 'c2': '0'}),
                      error='formula_type')
        checked('a result a typed column cannot hold saves nothing and says why',
                '#DIV/0!' in refused['message']
                and run('rows', book, lines['id'])[0]['data']['c2'] == '2')
        schema = run('table-schema', book, sheets['Other']['id'])
        run('table-edit-schema', book, sheets['Other']['id'], schema['version'],
            schema['definitionID'], json.dumps({'archived': True}), 'archive-other')
        run('edit-row', book, first['id'], json.dumps({**first['data'], 'c2': '5'}))
        checked('an archived table stays current with the file it came from',
                run('rows', book, sheets['Other']['id'])[0]['data']['c2'] == '3'
                and run('verify', book)['ok'] is True)

        # Another spreadsheet engine calculated and saved these two files. They hold the same
        # formulas over different inputs, so the second has what recalculating must reach.
        fixtures = Path(__file__).resolve().parent.parent / 'integration' / 'fixtures' / 'formulas'
        book, saved = root / 'Compared.sevra', root / 'Saved.sevra'
        for workbook, name in [(book, 'before'), (saved, 'after')]:
            run('create', workbook, 'Synthetic comparison')
            run('import', workbook, fixtures / f'libreoffice-{name}.xlsx', '--role', 'values')
        mine, theirs = tables(book), tables(saved)
        report = run('table-formulas', book, mine['Formulas']['id'])
        checked('every formula a file from LibreOffice saved matches on import',
                report['recalculating'] == 3600 and report['saved'] == 0)
        wanted = grid(saved, theirs['Inputs 2026'])
        changed = [row for name, row in grid(book, mine['Inputs 2026']).items()
                   if row['data'] != wanted[name]['data']]
        for row in changed:
            edit(book, row, **wanted[row['data']['c1']]['data'])
        result, expected = grid(book, mine['Formulas']), grid(saved, theirs['Formulas'])
        differing = [(name, column) for name, row in expected.items()
                     for column, value in row['data'].items()
                     if not same(result[name]['data'][column], value)]
        checked('after the same edits every value matches what LibreOffice calculated',
                len(changed) == 20 and not differing)

    print(json.dumps({'checks': checks, 'count': len(checks)}, indent=2))


if __name__ == '__main__':
    main()
