#!/usr/bin/env python3
"""Current-format synthetic CLI journeys for reviewed table updates and exact retries."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
from xml.sax.saxutils import escape
import zipfile


def write_xlsx(path, sheets, formats=None):
    """Writes the smallest Office package the importer reads. A cell is a value, or a
    (value, attributes) pair. Strings are inline; tuples set type, style and formula."""
    names = list(sheets)
    numbers = ''.join(f'<numFmt numFmtId="{164 + i}" formatCode="{escape(code)}"/>'
                      for i, code in enumerate(formats or []))
    styles = '<xf numFmtId="0"/>' + ''.join(f'<xf numFmtId="{164 + i}"/>' for i, _ in enumerate(formats or []))
    with zipfile.ZipFile(path, 'w') as package:
        package.writestr('xl/workbook.xml', '<workbook xmlns:r="r"><sheets>' + ''.join(
            f'<sheet name="{escape(name)}" r:id="rId{i + 1}"/>' for i, name in enumerate(names))
            + '</sheets></workbook>')
        package.writestr('xl/_rels/workbook.xml.rels', '<Relationships>' + ''.join(
            f'<Relationship Id="rId{i + 1}" Type="x/worksheet" Target="worksheets/sheet{i + 1}.xml"/>' for i in range(len(names)))
            + '</Relationships>')
        package.writestr('xl/styles.xml', f'<styleSheet><numFmts>{numbers}</numFmts><cellXfs>{styles}</cellXfs></styleSheet>')
        for index, name in enumerate(names):
            rows = ''
            for number, row in sheets[name].items():
                cells = ''
                for column, cell in enumerate(row):
                    value, extra = cell if isinstance(cell, tuple) else (cell, {})
                    reference = '' if extra.get('bare') else f' r="{chr(65 + column)}{number}"'
                    style = f' s="{extra["style"]}"' if 'style' in extra else ''
                    formula = f'<f>{escape(extra["formula"])}</f>' if 'formula' in extra else ''
                    if value is None:
                        cells += f'<c{reference}{style}>{formula}</c>'
                    elif extra.get('error'):
                        cells += f'<c{reference} t="e">{formula}<v>{value}</v></c>'
                    elif isinstance(value, str):
                        cells += f'<c{reference} t="inlineStr"{style}>{formula}<is><t>{escape(value)}</t></is></c>'
                    else:
                        cells += f'<c{reference}{style}>{formula}<v>{value}</v></c>'
                rows += f'<row r="{number}">{cells}</row>'
            package.writestr(f'xl/worksheets/sheet{index + 1}.xml', f'<worksheet><sheetData>{rows}</sheetData></worksheet>')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, default=Path('output/native/bin/sevra'))
    cli = parser.parse_args().cli.resolve()
    checks = []

    def run(*args, error=None):
        reply = subprocess.run([str(cli), *map(str, args)], capture_output=True, text=True, timeout=75)
        data = json.loads(reply.stdout if reply.returncode == 0 else reply.stderr)
        if error:
            assert reply.returncode != 0 and data['error']['code'] == error, data
            return data['error']
        assert reply.returncode == 0 and data['ok'], data
        return data['result']

    def checked(name, condition):
        assert condition, name
        checks.append(name)

    with tempfile.TemporaryDirectory(prefix='sevra-table-updates-') as temporary:
        root = Path(temporary)
        base = root / 'Parts.csv'
        base.write_text('sku,quantity\n0012,4\n0013,5\n')
        incoming = root / 'Incoming.tsv'
        incoming.write_text('code\tamount\tignore\n0012\t7\tnote\n0013\t5\tnote\n0014\t2\tnote\n')
        digest = hashlib.sha256(incoming.read_bytes()).hexdigest()
        for mode in ('append', 'replace', 'merge'):
            book = root / f'{mode}.sevra'
            run('create', book, f'Synthetic {mode}')
            original = run('import', book, base, '--role', 'values')
            table = original['intake']['datasetIDs'][0]
            before = run('rows', book, table)
            captured = run('import', book, incoming, '--role', 'update')
            source = captured['source']['id']
            job = captured['intake']
            checked(f'{mode}: update intake waits without changing rows',
                    job['state'] == 'awaiting_update' and run('rows', book, table) == before)
            inspection = run('table-update-inspect', book, source)
            checked(f'{mode}: bounded inspection supplies exact mapping examples',
                    inspection['headings'] == ['code', 'amount', 'ignore']
                    and inspection['examples'][0][0] == '0012' and inspection['incoming'] == 3)
            options = {'mode': mode, 'mapping': [{'position': 0, 'target': 'sku'},
                       {'position': 1, 'target': 'quantity'}, {'position': 2, 'target': None}],
                       'keys': ['sku'] if mode == 'merge' else []}
            preview = run('table-update-preview', book, source, table, json.dumps(options))
            checked(f'{mode}: preview preserves originals and reports the actual diff',
                    preview['added'] == (1 if mode == 'merge' else 3)
                    and preview['changed'] == (1 if mode == 'merge' else 0)
                    and preview['removed'] == (2 if mode == 'replace' else 0)
                    and run('rows', book, table) == before
                    and hashlib.sha256(incoming.read_bytes()).hexdigest() == digest)
            proposal_args = {**options, 'newRowMeaning': 'estimate', 'newRowScenario': 'forecast',
                             'expectedRevision': preview['revision'],
                             'expectedFingerprint': preview['fingerprint'], 'intakeID': job['id'],
                             'token': 'one-proposal'}
            proposal = run('table-update-propose', book, source, table, json.dumps(proposal_args))
            checked(f'{mode}: proposal retains its durable intake receipt without applying',
                    proposal['status'] == 'draft' and run('rows', book, table) == before
                    and next(j for j in run('intake-status', book)['jobs'] if j['id'] == job['id'])
                    ['report']['proposalID'] == proposal['id'])
            accepted = run('accept', book, proposal['id'], 'one-accept')
            rows = run('rows', book, table)
            checked(f'{mode}: acceptance applies once and keeps new rows estimates',
                    len(rows) == (5 if mode == 'append' else 3)
                    and rows[-1]['data']['sku'] == '0014' and rows[-1]['meaning'] == 'estimate'
                    and rows[-1]['scenario'] == 'forecast'
                    and run('accept', book, proposal['id'], 'one-accept')['id'] == accepted['id']
                    and run('rows', book, table) == rows)
            checked(f'{mode}: post-accept proposal retry returns its original receipt',
                    run('table-update-propose', book, source, table, json.dumps(proposal_args))['id']
                    == proposal['id'])
            undone = run('undo', book, accepted['id'], 'one-undo')
            restored = run('rows', book, table)
            checked(f'{mode}: checked undo restores logical identities, order and exact values',
                    [r['logicalID'] for r in restored] == [r['logicalID'] for r in before]
                    and [r['data'] for r in restored] == [r['data'] for r in before]
                    and run('undo', book, accepted['id'], 'one-undo')['id'] == undone['id'])
            redone = run('undo', book, undone['id'], 'one-redo')
            redone_rows = run('rows', book, table)
            checked(f'{mode}: redo restores the applied values with preserved history',
                    redone['status'] == 'accepted'
                    and [r['data'] for r in redone_rows] == [r['data'] for r in rows])
            archive = root / f'{mode}.sevraz'
            copy = root / f'{mode}-copy.sevra'
            run('export', book, archive)
            run('open-archive', archive, copy)
            run('undo', copy, redone['id'], 'portable-undo')
            checked(f'{mode}: portable reopen retains the complete checked undo context',
                    [r['data'] for r in run('rows', copy, table)] == [r['data'] for r in before]
                    and run('verify', copy)['ok'] and run('verify', book)['ok'])
            run('table-update-preview', book, source, table,
                json.dumps({**options, 'guessKeys': True}), error='update_options')
            run('table-update-inspect', book, source, '0', error='update_header')
            checked(f'{mode}: unknown options and invalid header refuse without working changes',
                    run('rows', book, table) == redone_rows)

        review_journeys(root, run, checked)
    print(json.dumps({'ok': True, 'count': len(checks), 'checks': checks}, indent=2))


def review_journeys(root, run, checked):
    """Suggestions, durable drafts and bounded Excel saved values."""
    book = root / 'review.sevra'
    run('create', book, 'Synthetic review')
    base = root / 'Stock.csv'
    base.write_text('sku,unit_price,note\n0012,1.20,first\n0013,2.50,second\n')
    table = run('import', book, base, '--role', 'values')['intake']['datasetIDs'][0]
    before = run('rows', book, table)
    mapping = [{'position': 0, 'target': 'sku'}, {'position': 1, 'target': 'unit_price'},
               {'position': 2, 'target': 'note'}]

    workbook = root / 'Incoming.xlsx'
    write_xlsx(workbook, {
        'Notes': {1: ['Saved for review']},
        'Quotes': {
            2: ['Stock report'],
            4: ['SKU', 'Unit Price', 'NOTE', ('', {'style': 1})],
            5: ['0012', 1.1999999999999999, 'first', ('', {'style': 1})],
            6: [('', {'style': 1}), ('', {'style': 1})],
            7: ['0013', (2.75, {'formula': 'A1*2'}), ('second', {'bare': False})],
            8: ['0014', 3, 'new'],
        },
    })
    digest = hashlib.sha256(workbook.read_bytes()).hexdigest()
    captured = run('import', book, workbook, '--role', 'update')
    source = captured['source']['id']
    job = captured['intake']
    first = run('table-update-inspect', book, source)
    checked('xlsx: a multi-sheet original names its worksheets before reading one',
            first['sheets'] == ['Notes', 'Quotes'] and first.get('sheet') is None
            and first['headings'] == [] and job['state'] == 'awaiting_update')
    run('table-update-inspect', book, source, '1', 'Missing', error='update_sheet')
    refused = run('table-update-inspect', book, source, '1', 'Quotes', error='update_header')
    checked('xlsx: a missing header row names the first row with values',
            'first row with values is 2' in refused['message'])
    inspection = run('table-update-inspect', book, source, '4', 'Quotes')
    checked('xlsx: headings and values skip empty styled rows and cells',
            inspection['headings'] == ['SKU', 'Unit Price', 'NOTE'] and inspection['incoming'] == 3
            and inspection['examples'][0] == ['0012', '1.2', 'first'])
    suggestion = run('table-update-suggest', book, source, table, '4', 'Quotes')
    checked('xlsx: exact headings suggest a full mapping', suggestion['mapping'] == mapping)

    draft = {'sourceID': source, 'intakeID': job['id'], 'headerRow': 4, 'sheet': 'Quotes',
             'datasetID': table, 'mode': 'merge', 'decisions': mapping[:2], 'keys': ['sku'],
             'meaning': 'estimate', 'scenario': 'forecast', 'version': 1}
    run('table-update-draft-save', book, json.dumps(draft))
    saved = run('table-update-draft', book, source)
    archive = root / 'review.sevraz'
    copy = root / 'review-copy.sevra'
    run('export', book, archive)
    run('open-archive', archive, copy)
    checked('draft: an unfinished mapping survives reopen and portable export',
            saved['decisions'] == mapping[:2] and saved['sheet'] == 'Quotes'
            and run('table-update-draft', copy, source) == saved and run('verify', book)['ok'])
    checked('draft: saving choices changes no working table', run('rows', book, table) == before)
    run('table-update-draft-save', book, json.dumps({**draft, 'decisions': mapping[:1] * 2}),
        error='update_draft')
    run('table-update-draft-save', book, json.dumps({**draft, 'sourceID': before[0]['id']}), error='update_draft')
    checked('draft: a refused save keeps the earlier draft',
            run('table-update-draft', book, source) == saved)

    options = {'mode': 'merge', 'mapping': mapping, 'keys': ['sku'], 'headerRow': 4, 'sheet': 'Quotes'}
    preview = run('table-update-preview', book, source, table, json.dumps(options))
    checked('xlsx: the preview compares amounts, not spelling, and discloses saved formulas',
            preview['added'] == 1 and preview['changed'] == 1 and preview['unchanged'] == 1
            and preview['sheet'] == 'Quotes'
            and any('1 mapped cell is a saved formula result' in line for line in preview['limitations'])
            and run('rows', book, table) == before
            and hashlib.sha256(workbook.read_bytes()).hexdigest() == digest)
    checked('xlsx: a preview locates each row by its worksheet row',
            [e['sourceRecord'] for e in preview['examples']] == [7, 8])
    proposal = run('table-update-propose', book, source, table, json.dumps({
        **options, 'newRowMeaning': 'estimate', 'newRowScenario': 'forecast',
        'expectedRevision': preview['revision'], 'expectedFingerprint': preview['fingerprint'],
        'intakeID': job['id'], 'token': 'xlsx-proposal'}))
    checked('draft: creating the reviewed proposal ends the draft',
            run('table-update-draft', book, source) is None and run('rows', book, table) == before)
    accepted = run('accept', book, proposal['id'], 'xlsx-accept')
    rows = run('rows', book, table)
    checked('xlsx: acceptance keeps leading zeros and the earlier spelling of equal amounts',
            [r['data']['sku'] for r in rows] == ['0012', '0013', '0014']
            and rows[0]['data']['unit_price'] == '1.20' and rows[1]['data']['unit_price'] == '2.75')
    run('undo', book, accepted['id'], 'xlsx-undo')
    checked('xlsx: Undo restores the reviewed table', [r['data'] for r in run('rows', book, table)]
            == [r['data'] for r in before])

    for operation, expected in (('append', ['0012', '0013', '0012', '0099']), ('replace', ['0012', '0099'])):
        other = root / f'xlsx-{operation}.sevra'
        run('create', other, 'Synthetic Excel update')
        target = run('import', other, base, '--role', 'values')['intake']['datasetIDs'][0]
        original = run('rows', other, target)
        file = root / f'{operation}.xlsx'
        write_xlsx(file, {'Sheet': {1: ['sku', 'unit_price', 'note'], 2: ['0012', 1.5, 'a'], 4: ['0099', 2, 'b']}})
        item = run('import', other, file, '--role', 'reference')['source']['id']
        choice = {'mode': operation, 'mapping': mapping}
        shown = run('table-update-preview', other, item, target, json.dumps(choice))
        checked(f'xlsx {operation}: the preview counts the actual change',
                shown['added'] == 2 and shown['removed'] == (2 if operation == 'replace' else 0)
                and run('rows', other, target) == original)
        draft_item = run('table-update-propose', other, item, target, json.dumps({
            **choice, 'newRowMeaning': 'actual', 'newRowScenario': 'actual',
            'expectedRevision': shown['revision'], 'expectedFingerprint': shown['fingerprint']}))
        decision = run('accept', other, draft_item['id'], f'{operation}-accept')
        checked(f'xlsx {operation}: acceptance keeps leading zeros and worksheet row locators',
                [r['data']['sku'] for r in run('rows', other, target)] == expected)
        run('undo', other, decision['id'], f'{operation}-undo')
        checked(f'xlsx {operation}: Undo restores the table',
                [r['data'] for r in run('rows', other, target)] == [r['data'] for r in original])

    def refused_cell(name, rows, code, text, formats=None, keys=('sku',)):
        path = root / f'{name}.xlsx'
        write_xlsx(path, {'Sheet': {1: ['sku', 'unit_price', 'note'], **rows}}, formats)
        item = run('import', book, path, '--role', 'reference')['source']['id']
        error = run('table-update-preview', book, item, table, json.dumps(
            {'mode': 'merge', 'mapping': mapping, 'keys': list(keys)}), error=code)
        checked(f'xlsx: {name} refuses and names the cell', text in error['message'])
        checked(f'xlsx: {name} leaves the table unchanged',
                [r['data'] for r in run('rows', book, table)] == [r['data'] for r in before])

    refused_cell('error-cell', {2: ['0012', ('#REF!', {'error': True}), 'x']}, 'update_value', 'B2')
    refused_cell('uncached-formula', {2: ['0012', (None, {'formula': 'A1*2'}), 'x']}, 'update_value', 'B2')
    refused_cell('padded-number', {2: [(14, {'style': 1}), 1, 'x']}, 'update_value', 'A2', ['0000'])
    refused_cell('lost-zeros', {2: ['12', 1, 'x']}, 'update_key_ambiguous', '0012')
    refused_cell('case-variant', {2: ['0012', 1, 'FIRST']}, 'update_key_ambiguous', 'first', keys=['note'])
    refused_cell('decimal-variant', {2: ['12.0', 1, 'x']}, 'update_key_ambiguous', '0012')
    refused_cell('incoming-variant', {2: ['0015', 1, 'new'], 3: ['0016', 2, ' New']},
                 'update_key_ambiguous', 'new', keys=['note'])
    refused_cell('spaced-decimal', {2: [' 0015', 1, 'x']}, 'number', 'Source record 2')
    refused_cell('decimal-comma', {2: ['0012', '1,20', 'x']}, 'number', 'Source record 2')

    padded = root / 'padded-amount.xlsx'
    write_xlsx(padded, {'Sheet': {1: ['sku', 'unit_price', 'note'], 2: ['0012', (7, {'style': 1}), 'x']}}, ['000'])
    item = run('import', book, padded, '--role', 'reference')['source']['id']
    allowed = run('table-update-preview', book, item, table, json.dumps(
        {'mode': 'merge', 'mapping': mapping, 'keys': ['sku']}))
    checked('xlsx: a padded number is fine in a decimal column', allowed['changed'] == 1)

    bare = root / 'bare-cells.xlsx'
    write_xlsx(bare, {'Sheet': {
        1: [('sku', {'bare': True}), ('unit_price', {'bare': True}), ('note', {'bare': True})],
        2: [('0012', {'bare': True}), (1.2, {'bare': True}), ('first', {'bare': True})]}})
    item = run('import', book, bare, '--role', 'reference')['source']['id']
    checked('xlsx: cells without references keep their column order',
            run('table-update-inspect', book, item)['headings'] == ['sku', 'unit_price', 'note'])

    titled = root / 'titled.xlsx'
    write_xlsx(titled, {'Sheet': {3: ['sku', 'unit_price', 'note'], 4: ['0012', 1, 'x']}})
    pending = run('import', book, titled, '--role', 'update')['intake']
    checked('xlsx: a pending update does not assume the heading is in row 1',
            pending['state'] == 'awaiting_update'
            and run('table-update-inspect', book, pending['sourceID'], '3')['incoming'] == 1)

    wide = root / 'wide.xlsx'
    write_xlsx(wide, {'Sheet': {1: ['sku', 'unit_price', 'note'], 2: ['0012', 1, 'x', 'stray']}})
    item = run('import', book, wide, '--role', 'reference')['source']['id']
    run('table-update-inspect', book, item, error='update_mapping')
    checked('xlsx: a value outside the headings refuses', True)

    limit = root / 'limit.xlsx'
    write_xlsx(limit, {'Sheet': {i: ['sku', 'unit_price', 'note'] if i == 1 else [f'{i:04d}', i, 'x']
                                 for i in range(1, 1003)}})
    item = run('import', book, limit, '--role', 'reference')['source']['id']
    run('table-update-inspect', book, item, error='update_limit')
    checked('xlsx: the 1,000 incoming row bound still applies', True)

    ambiguous = root / 'Ambiguous.csv'
    ambiguous.write_text('sku,SKU,price,unknown\n0012,0013,1,x\n')
    item = run('import', book, ambiguous, '--role', 'reference')['source']['id']
    hint = run('table-update-suggest', book, item, table)
    checked('suggestion: two headings for one column stay for a person to choose',
            hint['mapping'] == [] and len(hint['notes']) == 2)
    run('table-update-preview', book, item, table, json.dumps(
        {'mode': 'append', 'mapping': [{'position': 0, 'target': 'sku'}]}), error='update_mapping')
    checked('suggestion: a preview still requires the complete explicit mapping', True)


if __name__ == '__main__':
    main()
