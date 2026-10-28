#!/usr/bin/env python3
"""Model-free CLI intake roles, capture retries and current-format portability."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, default=Path('output/native/bin/sevra'))
    cli = parser.parse_args().cli.resolve()
    checks = []

    def run(*arguments, error=None):
        reply = subprocess.run([str(cli), *map(str, arguments)], capture_output=True,
                               text=True, timeout=75)
        data = json.loads(reply.stdout if reply.returncode == 0 else reply.stderr)
        assert data['schemaVersion'] == 1, data
        if error:
            assert reply.returncode != 0 and data['error']['code'] == error, data
            return data['error']
        assert reply.returncode == 0 and data['ok'], data
        return data['result']

    def checked(name, condition):
        assert condition, name
        checks.append(name)

    with tempfile.TemporaryDirectory(prefix='sevra-contextual-intake-') as directory:
        folder = Path(directory)
        book = folder / 'Intake.sevra'
        run('create', book, 'Synthetic contextual intake')
        csv = folder / 'Supplier.csv'
        csv.write_text('sku,quantity\n0012,4\n0013,5\n')
        original = run('import', book, csv, '--token', 'same-capture')
        source, job = original['source'], original['intake']
        checked('bare CSV asks for use without creating working data',
                job['state'] == 'awaiting_role' and run('tables', book) == [])
        analysis = run('intake-use', book, job['id'], 'analysis', 'analysis-choice')
        checked('analysis input is inspected without an invented analysis or permanent table',
                analysis['state'] == 'ready' and analysis['datasetIDs'] == []
                and analysis['report']['inspection']['sheets'][0]['rows'] == 3
                and run('tables', book) == [])
        csv.unlink()
        retry = run('import', book, csv, '--token', 'same-capture')
        checked('capture retry reuses the saved original after input disappears',
                retry['source']['id'] == source['id'] and retry['intake']['id'] == job['id'])
        before = run('inspect', book)
        run('import', book, csv, '--role', 'values', '--token', 'same-capture', error='idempotency')
        checked('changed capture intent cannot reuse a receipt', run('inspect', book) == before)
        values = run('intake-from-source', book, source['id'], 'values', 'table-use')
        table = values['datasetIDs'][0]
        rows = run('rows', book, table)
        checked('explicit values create one table and preserve lexical identifiers',
                len(run('tables', book)) == 1 and rows[0]['data']['sku'] == '0012')
        again = run('intake-from-source', book, source['id'], 'values', 'table-use')
        checked('conversion retry does not duplicate rows or tables',
                again['datasetIDs'] == values['datasetIDs'] and len(run('rows', book, table)) == 2
                and len(run('tables', book)) == 1)
        reference = run('intake-from-source', book, source['id'], 'reference', 'reference-use')
        run('resume-intake', book, source['id'])
        checked('later reference use preserves source and existing table identities',
                reference['sourceID'] == source['id'] and reference['datasetIDs'] == []
                and len(run('tables', book)) == 1)
        run('intake-use', book, job['id'], 'merge', error='intake_role')
        xlsx = folder / 'Saved.xlsx'
        with zipfile.ZipFile(xlsx, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('xl/workbook.xml', '<workbook xmlns:r="r"><sheets><sheet name="Parts" r:id="r1"/></sheets></workbook>')
            archive.writestr('xl/_rels/workbook.xml.rels', '<Relationships><Relationship Id="r1" Type="x/worksheet" Target="worksheets/sheet1.xml"/></Relationships>')
            archive.writestr('xl/worksheets/sheet1.xml', '<worksheet><sheetData><row r="1"><c r="A1"><v>3</v></c><c r="B1"><f>A1*2</f><v>6</v></c></row></sheetData></worksheet>')
        saved = run('import', book, xlsx, '--role', 'values')['intake']
        checked('Excel saved values report formula evidence without claiming recalculation',
                saved['report']['conversion'] == 'saved_values'
                and saved['report']['inspection']['liveExcelFormulas'] is False
                and saved['report']['inspection']['sheets'][0]['formulaCount'] == 1
                and 'do not recalculate' in saved['detail'])
        archive = folder / 'Portable.sevraz'
        restored = folder / 'Restored.sevra'
        run('export', book, archive)
        run('open-archive', archive, restored)
        restored_jobs = run('intake-status', restored)['jobs']
        checked('portable reopen preserves selected roles and result identities',
                next(j for j in restored_jobs if j['id'] == values['id']) == values
                and next(j for j in restored_jobs if j['id'] == reference['id']) == reference
                and run('verify', restored)['ok'])
    print(json.dumps({'ok': True, 'checks': checks, 'count': len(checks)}, indent=2))


if __name__ == '__main__':
    main()
