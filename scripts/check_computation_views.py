"""Qualify native computation bindings and explicit result publication across CLI processes."""
import argparse
import copy
import json
from pathlib import Path
import subprocess
import tempfile
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--cli', type=Path, required=True)
parser.add_argument('--output', type=Path)
parser.add_argument('--keep', type=Path)
options = parser.parse_args()
cli = options.cli.resolve(strict=True)


def call(*args, error=None):
    result = subprocess.run([str(cli), *map(str, args)], capture_output=True, text=True, timeout=60)
    payload = json.loads(result.stderr if result.returncode else result.stdout)
    if error:
        assert result.returncode and payload['error']['code'] == error, payload
        return payload
    assert not result.returncode, payload
    return payload['result']


def j(value):
    return json.dumps(value, ensure_ascii=False)


def qualify(root):
    book = root / 'Computations.sevra'
    call('create', book, 'Synthetic shop')
    logical = str(uuid.uuid4())
    content = {'kind': 'function', 'title': 'Case units', 'description': 'Synthetic 12 items per case',
               'parameters': [{'id': 'cases', 'label': 'Cases', 'type': 'decimal', 'required': True}],
               'payload': {'expression': 'cases*12', 'calls': [], 'unit': 'items'}}
    function = call('definition-save', book, logical, j(content), 'new', 'case-units')
    component = {'id': 'case-count', 'type': 'calculation', 'title': 'Case units',
                 'definitionBinding': {'mode': 'live', 'logicalID': logical}, 'arguments': {'cases': '3'}}
    report = call('space', book, 'Case report', j({'version': 1, 'components': [component]}))
    call('space', book, 'Stock count', j({'version': 1, 'components': [component]}))
    evaluation = call('component-evaluate', book, j(component))
    assert evaluation['result'] == '36' and evaluation['unit'] == 'items'
    frozen = call('pin-space', book, report, 'Earlier case report')
    frozen_component = next(x for x in call('spaces', book) if x['id'] == frozen)['definition']['components'][0]
    request = {'id': function['id'], 'arguments': component['arguments'], 'evaluation': evaluation,
               'title': 'Expected items', 'meaning': 'estimate', 'scenario': 'expected delivery'}
    request_file = root / 'publication.json'
    request_file.write_text(j(request))
    published = call('definition-publish', book, '@' + str(request_file), 'publish-case-units')
    assert call('commits', book, 1)[0]['actor']['kind'] == 'programmatic'
    assert published['status'] == 'draft' and published['meaning'] == 'estimate'
    accepted = call('accept', book, published['id'], 'review-estimate')
    assert accepted['meaning'] == 'estimate' and accepted['status'] == 'accepted'
    updated = call('definition-save', book, logical, j({**content, 'payload': {**content['payload'],
                      'expression': 'cases*10'}}), function['id'], 'change-case-size')
    assert call('component-evaluate', book, j(component))['result'] == '30'
    assert call('component-evaluate', book, j(frozen_component))['result'] == '36'
    assert call('definition-publish', book, j(request), 'publish-case-units') == published
    call('definition-publish', book, j(request), 'stale-result', error='stale_evaluation')
    forged = copy.deepcopy(request)
    forged['id'] = updated['id']
    forged['evaluation'] = call('definition-evaluate', book, updated['id'], j(component['arguments']))
    forged['evaluation']['result'] = '999'
    call('definition-publish', book, j(forged), 'forged-result', error='stale_evaluation')
    csv = root / 'counts.csv'
    csv.write_text('Item,Quantity\nbolts,2\nnuts,5\n')
    dataset = call('import', book, csv, '--role', 'values')['intake']['datasetIDs'][0]
    schema = call('table-schema', book, dataset)
    columns = {column['title']: column['id'] for column in schema['columns']}
    query_content = {'kind': 'query', 'title': 'Current quantities', 'description': 'Synthetic counts',
                     'parameters': [], 'payload': {'dataMode': 'live', 'query': {
                         'sources': [{'datasetID': dataset, 'definitionID': schema['definitionID']}],
                         'select': [{'id': 'item', 'column': {'source': 0, 'column': columns['Item']}},
                                    {'id': 'quantity', 'column': {'source': 0, 'column': columns['Quantity']}}],
                         'limit': 1}}}
    query = call('definition-save', book, str(uuid.uuid4()), j(query_content), 'new', 'define-query')
    query_component = {'id': 'counts', 'type': 'query', 'title': 'Current quantities',
                       'definitionBinding': {'mode': 'live', 'logicalID': query['logicalID']}, 'arguments': {}}
    query_space = call('space', book, 'Count review', j({'version': 1, 'components': [query_component]}))
    first = call('component-evaluate', book, j(query_component))
    assert first['result']['hasMore'] and first['nextCursor']
    assert call('component-evaluate', book, j(query_component), first['nextCursor'])['result']['rows'][0]['values']['quantity'] == '5'
    call('definition-publish', book, j({'id': query['id'], 'arguments': {}, 'evaluation': first,
                                      'title': 'Partial counts', 'meaning': 'actual'}), 'partial', error='partial_evaluation')
    frozen_query = call('pin-space', book, query_space, 'Earlier count review')
    saved_query = next(x for x in call('spaces', book) if x['id'] == frozen_query)['definition']['components'][0]
    assert len(saved_query['evaluationSnapshot']['inputPopulation'][0]['rows']) == 2
    call('component-evaluate', book, j(saved_query), first['nextCursor'], error='view_snapshot')
    full_query = copy.deepcopy(query_content)
    full_query['payload']['query']['limit'] = 10
    current = call('definition-save', book, query['logicalID'], j(full_query), query['id'], 'complete-query')
    complete = call('component-evaluate', book, j(query_component))
    counts = call('definition-publish', book, j({'id': current['id'], 'arguments': {}, 'evaluation': complete,
                                               'title': 'Counts snapshot', 'meaning': 'estimate'}), 'save-counts')
    assert len(counts['data']['inputPopulation'][0]['rows']) == 2
    history = call('commits', book, 1000)
    for command, source, destination in [('reconstruct', book, root / 'Replay.sevra'),
                                         ('export', book, root / 'Portable.sevraz')]:
        call(command, source, destination)
    call('open-archive', root / 'Portable.sevraz', root / 'Portable.sevra')
    for restored in [root / 'Replay.sevra', root / 'Portable.sevra']:
        assert call('commits', restored, 1000) == history
        assert call('component-evaluate', restored, j(frozen_component)) == call('component-evaluate', book, j(frozen_component))
        assert call('component-evaluate', restored, j(saved_query)) == first
        assert call('verify', restored)['ok']
    assert call('verify', book)['ok']
    return {'ok': True, 'liveFunctionResult': '30', 'frozenFunctionResult': '36',
            'publishedEstimate': published, 'publishedQuery': counts,
            'staleForgedPartialRefused': True, 'exactRetry': True,
            'frozenQueryPopulation': 2, 'inertReconstruction': True, 'portableReopen': True,
            'workbook': str(book) if options.keep else 'temporary synthetic fixture'}


if options.keep:
    options.keep.mkdir(parents=True, exist_ok=False)
    report = qualify(options.keep)
else:
    with tempfile.TemporaryDirectory(prefix='sevra-computation-') as directory:
        report = qualify(Path(directory))
output = json.dumps(report, indent=2)
if options.output:
    options.output.write_text(output + '\n')
print(output)
