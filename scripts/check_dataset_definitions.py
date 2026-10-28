"""Current-format dataset definition lifecycle through the installed CLI surface."""
import argparse
import copy
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cli', type=Path, required=True)
parser.add_argument('--output', type=Path)
options = parser.parse_args()
cli = options.cli.resolve(strict=True)


def call(*args, error=None):
    process = subprocess.run([str(cli), *map(str, args)], capture_output=True, text=True, timeout=60)
    payload = json.loads(process.stderr if process.returncode else process.stdout)
    if error:
        assert process.returncode and payload['error']['code'] == error, payload
        return payload
    assert not process.returncode, payload
    return payload['result']


with tempfile.TemporaryDirectory(prefix='sevra-definitions-') as directory:
    root = Path(directory)
    book = root / 'Definitions.sevra'
    call('create', book, 'Schema lifecycle')
    csv = root / 'Original.csv'
    csv.write_text('sku,cost\n0012,2.40\n0013,3.25\n')
    dataset = call('import', book, csv, '--role', 'values')['intake']['datasetIDs'][0]
    csv.unlink()
    original = call('table-schema', book, dataset)
    base_id = original['definitionID']
    fields = copy.deepcopy(original['columns'])
    # CSV's heuristic currently treats the numeric SKU as decimal. This fixture
    # explicitly gives it text identity while retaining the original lexical form.
    fields[0]['type'] = 'text'
    fields[0]['required'] = True
    fields[0]['unique'] = True
    options_json = json.dumps({'title': 'Current orders', 'columns': fields[:1]})
    removed = call('table-edit-schema', book, dataset, 1, base_id, options_json, 'remove-cost')
    assert call('table-edit-schema', book, dataset, 1, base_id, options_json, 'remove-cost') == removed
    rows = call('rows', book, dataset)
    assert rows[0]['data'] == {'sku': '0012'}
    edited = call('edit-row', book, rows[0]['id'], json.dumps({'sku': '0099'}))
    assert edited['data']['cost'] == '2.40'
    call('table-edit-schema', book, dataset, 1, base_id, '{"title":"Losing draft"}', 'stale', error='stale_schema')
    call('table-edit-schema', book, dataset, 1, base_id, '{"title":"Changed retry"}', 'remove-cost', error='idempotency')
    call('table-edit-schema', book, dataset, 2, removed['id'], '{"archived":"yes"}', 'bad', error='arguments')
    call('table-edit-schema', book, dataset, 2, removed['id'], '{"sql":"DROP TABLE items"}', 'bad', error='arguments')
    # Two independent processes author against one frozen causal base.
    def compete(label):
        process = subprocess.run([str(cli), 'table-edit-schema', str(book), dataset, '2', removed['id'], json.dumps({'title': label}), label], capture_output=True, text=True, timeout=60)
        return process.returncode, json.loads(process.stderr if process.returncode else process.stdout)
    with ThreadPoolExecutor(2) as pool:
        results = list(pool.map(compete, ['Writer A', 'Writer B']))
    assert sum(code == 0 for code, _ in results) == 1, results
    assert next(payload['error']['code'] for code, payload in results if code) == 'stale_schema'
    base = call('table-schema', book, dataset)
    archived = call('table-edit-schema', book, dataset, base['version'], base['definitionID'], '{"archived":true}', 'archive')
    assert call('tables', book) == []
    assert call('tables', book, '--archived')[0]['id'] == dataset
    current = call('rows', book, dataset)[0]
    call('edit-row', book, current['id'], '{"sku":"blocked"}', error='archived_dataset')
    restored = call('table-restore-schema', book, dataset, base_id, archived['version'], archived['id'], 'restore')
    assert restored['id'] != base_id and restored['previousID'] == archived['id']
    assert restored['columns'] == original['columns']
    assert call('rows', book, dataset)[0]['data'] == {'sku': '0099', 'cost': '2.40'}
    assert call('verify', book)['ok']
    history = call('table-schema-history', book, dataset)
    assert len(history) == 5 and history[-1]['id'] == base_id
    assert call('table-schema-history', book, dataset, 3)[0]['version'] == 2
    revision = call('inspect', book)['revision']
    call('table-rebuild', book, dataset, revision, 'rebuild-schema')
    replay = root / 'Replayed.sevra'
    call('reconstruct', book, replay)
    assert call('table-schema-history', replay, dataset) == history
    assert call('rows', replay, dataset) == call('rows', book, dataset)
    assert call('commits', replay, 1000) == call('commits', book, 1000)
    archive = root / 'Portable.sevraz'
    call('export', replay, archive)
    portable = root / 'Portable.sevra'
    call('open-archive', archive, portable)
    assert call('table-schema', portable, dataset) == call('table-schema', book, dataset)
    assert call('verify', portable)['ok']
    merge_book = root / 'UniqueMerge.sevra'
    call('create', merge_book, 'Unique merge')
    base_file = root / 'Keys.csv'
    base_file.write_text('sku,cost\nA,1\nB,2\n')
    merge_id = call('import', merge_book, base_file, '--role', 'values')['intake']['datasetIDs'][0]
    merge_schema = call('table-schema', merge_book, merge_id)
    merge_columns = merge_schema['columns']
    merge_columns[0]['unique'] = True
    merge_columns[1]['unique'] = True
    call('table-edit-schema', merge_book, merge_id, 1, merge_schema['definitionID'],
         json.dumps({'columns': merge_columns}), 'make-unique')
    before_merge = [row['data'] for row in call('rows', merge_book, merge_id)]
    incoming = root / 'Incoming.csv'
    incoming.write_text('sku,cost\nA,2\nB,1\n')
    capture = call('import', merge_book, incoming, '--role', 'update')
    source_id = capture['source']['id']
    merge_options = {'mode': 'merge', 'mapping': [{'position': 0, 'target': 'sku'},
                      {'position': 1, 'target': 'cost'}], 'keys': ['sku']}
    preview = call('table-update-preview', merge_book, source_id, merge_id, json.dumps(merge_options))
    proposal = call('table-update-propose', merge_book, source_id, merge_id, json.dumps({
        **merge_options, 'newRowMeaning': 'actual', 'newRowScenario': 'actual',
        'expectedRevision': preview['revision'], 'expectedFingerprint': preview['fingerprint'],
        'intakeID': capture['intake']['id'], 'token': 'unique-merge'}))
    accepted = call('accept', merge_book, proposal['id'], 'accept-unique-merge')
    assert [row['data']['cost'] for row in call('rows', merge_book, merge_id)] == ['2', '1']
    undone = call('undo', merge_book, accepted['id'], 'undo-unique-merge')
    assert [row['data'] for row in call('rows', merge_book, merge_id)] == before_merge
    call('undo', merge_book, undone['id'], 'redo-unique-merge')
    assert [row['data']['cost'] for row in call('rows', merge_book, merge_id)] == ['2', '1']
    merge_replay = root / 'UniqueMergeReplay.sevra'
    call('reconstruct', merge_book, merge_replay)
    assert call('commits', merge_replay, 1000) == call('commits', merge_book, 1000)
    assert call('verify', merge_replay)['ok']
    report = {'ok': True, 'schemaDefinitions': len(history), 'competingWriters': results,
              'removedValues': 'retained through edits and restore', 'projectionRebuild': True,
              'inertReconstruction': True, 'portableReopen': True, 'uniqueMergeUndoRedo': True,
              'scope': 'synthetic current-format CLI lifecycle; no model or multi-device claim'}
    if options.output:
        options.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
