"""Exercise versioned pure application definitions through the packaged CLI."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import tempfile
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cli', type=Path, required=True)
parser.add_argument('--output', type=Path)
options = parser.parse_args()
cli = options.cli.resolve(strict=True)


def run(*args):
    result = subprocess.run([str(cli), *map(str, args)], capture_output=True, text=True, timeout=60)
    payload = json.loads(result.stderr if result.returncode else result.stdout)
    return result.returncode, payload


def call(*args, error=None):
    code, payload = run(*args)
    if error:
        assert code and payload['error']['code'] == error, payload
        return payload
    assert not code, payload
    return payload['result']


def identifier():
    return str(uuid.uuid4())


def function(expression='x*2', title='Reusable citrus cost', calls=None):
    return {'kind': 'function', 'title': title, 'description': 'Synthetic definition, not execution authority',
            'parameters': [{'id': 'x', 'label': 'Quantity', 'type': 'decimal', 'required': True, 'unit': 'USD'}],
            'payload': {'expression': expression, 'unit': 'USD', 'calls': calls or []}}


with tempfile.TemporaryDirectory(prefix='sevra-application-definitions-') as directory:
    root = Path(directory)
    book = root / 'Definitions.sevra'
    call('create', book, 'Application definitions')
    logical, token = identifier(), identifier()
    content = function()
    first = call('definition-save', book, logical, json.dumps(content), 'new', token)
    caller_content = function('base+1', title='Reusable linked calculation', calls=[
        {'alias': 'base', 'binding': {'mode': 'live', 'logicalID': logical},
         'arguments': {'x': {'parameter': 'x'}}}])
    caller = call('definition-save', book, identifier(), json.dumps(caller_content), 'new', identifier())
    history = call('commits', book, 1000)
    args = json.dumps({'x': '2.10'})
    original = call('definition-evaluate', book, caller['logicalID'], args)
    assert original['result'] == '5.2' and len(original['resolvedDefinitions']) == 2
    assert call('commits', book, 1000) == history
    call('definition-evaluate', book, logical, '{"x":2.1}', error='definition_input')
    call('definition-save', book, first['id'], json.dumps(content), 'new', identifier(), error='definition_identity')

    # Independent processes edit one causal base; exactly one may publish.
    def compete(multiplier):
        return run('definition-save', book, logical, json.dumps(function(f'x*{multiplier}')),
                   first['id'], f'compete-{multiplier}')
    with ThreadPoolExecutor(2) as pool:
        writers = list(pool.map(compete, [3, 4]))
    assert sum(code == 0 for code, _ in writers) == 1, writers
    assert next(payload['error']['code'] for code, payload in writers if code) == 'stale_definition'
    winner = next(payload['result'] for code, payload in writers if not code)
    assert call('definition-save', book, logical, json.dumps(content), 'new', token) == first
    call('definition-save', book, logical, json.dumps(function('x+9')), 'new', token, error='idempotency')
    dependencies = call('definition-dependencies', book, caller['id'])
    assert dependencies[0]['target_version'] == first['id']
    current = call('definition-evaluate', book, caller['id'], args)
    assert any(entry['id'] == winner['id'] for entry in current['resolvedDefinitions'])
    saved_history = call('definition-history', book, logical)
    assert [version['id'] for version in saved_history] == [winner['id'], first['id']]
    restored = call('definition-restore', book, logical, first['id'], winner['id'], 'restore-original')
    assert restored['version'] == 3 and restored['previousID'] == winner['id']
    assert call('definition-evaluate', book, caller['id'], args)['result'] == '5.2'
    assert call('definition-restore', book, logical, first['id'], winner['id'], 'restore-original') == restored

    search = call('definition-search', book, 'Quantity', '{"limit":1}')
    assert len(search['hits']) == 1 and search['nextCursor']
    second = call('definition-search', book, 'Quantity', json.dumps({'limit': 1, 'cursor': search['nextCursor']}))
    assert len(second['hits']) == 1 and second['hits'][0]['id'] != search['hits'][0]['id']
    assert len(call('definition-search', book, 'citrus')['hits']) == 1
    assert len(call('definition-search', book, 'citrus', '{"historical":true}')['hits']) == 3
    call('definition-search', book, 'citrus', '{"historical":"yes"}', error='arguments')

    csv = root / 'Original.csv'
    csv.write_text('sku,price\n0012,2.10\n0013,3.20\n')
    dataset = call('import', book, csv, '--role', 'values')['intake']['datasetIDs'][0]
    schema = call('table-schema', book, dataset)
    price = next(column for column in schema['columns'] if column['title'] == 'price')
    columns = schema['columns']
    price['unit'] = 'USD'
    schema = call('table-edit-schema', book, dataset, schema['version'], schema['definitionID'], json.dumps({'columns': columns}), 'unit')
    query = {'kind': 'query', 'title': 'Citrus price view', 'description': 'Current accepted actual prices',
             'parameters': [{'id': 'minimum', 'label': 'Minimum price', 'type': 'decimal', 'required': True, 'unit': 'USD'}],
             'payload': {'dataMode': 'live', 'query': {
                 'sources': [{'datasetID': dataset, 'definitionID': schema['id'], 'scope': {'meaning': 'actual', 'status': 'accepted'}}],
                 'select': [{'id': 'price', 'column': {'source': 0, 'column': price['id']}}],
                 'filters': [{'column': {'source': 0, 'column': price['id']}, 'op': 'gte', 'value': {'parameter': 'minimum'}}],
                 'sort': [{'field': 'price'}], 'limit': 1}}}
    saved_query = call('definition-save', book, identifier(), json.dumps(query), 'new', 'query')
    result = call('definition-evaluate', book, saved_query['id'], '{"minimum":"2"}')
    assert result['result']['rows'][0]['values']['price'] == '2.1' and result['nextCursor']
    page = call('definition-evaluate', book, saved_query['id'], '{"minimum":"2"}', result['nextCursor'])
    assert page['result']['rows'][0]['values']['price'] == '3.2'
    call('definition-save', book, identifier(), json.dumps({**query, 'sql': 'DROP TABLE items'}), 'new', 'bad', error='definition')
    csv.unlink()
    assert call('verify', book)['ok']
    final_history = call('commits', book, 1000)
    replay = root / 'Replayed.sevra'
    call('reconstruct', book, replay)
    assert call('commits', replay, 1000) == final_history
    assert call('definition-read', replay, caller['id']) == caller
    assert call('definition-dependencies', replay, caller['id']) == dependencies
    assert call('definition-evaluate', replay, caller['id'], args)['result'] == '5.2'
    assert call('definition-evaluate', replay, saved_query['id'], '{"minimum":"2"}') == result
    assert call('definition-search', replay, 'citrus')['hits'] == call('definition-search', book, 'citrus')['hits']
    archive = root / 'Portable.sevraz'
    call('export', replay, archive)
    portable = root / 'Portable.sevra'
    call('open-archive', archive, portable)
    assert call('verify', portable)['ok']
    assert call('definition-read', portable, logical)['id'] == restored['id']
    report = {'ok': True, 'competingEditors': writers, 'first': first, 'restored': restored,
              'retainedDependency': dependencies, 'initialEvaluation': original, 'changedLiveEvaluation': current,
              'queryEvaluation': result, 'queryContinuation': page,
              'inertReconstruction': True, 'portableReopen': True,
              'scope': 'public CLI catalog/function/query surface; no new in-app model tool or native form claim'}
    output = json.dumps(report, indent=2)
    if options.output:
        options.output.write_text(output + '\n')
    print(output)
