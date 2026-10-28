"""Qualify current-format registered actions/forms using independent CLI processes."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import copy
import hashlib
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

def run(*args):
    p = subprocess.run([str(cli), *map(str, args)], capture_output=True, text=True, timeout=60)
    return p.returncode, json.loads(p.stderr if p.returncode else p.stdout)
def call(*args, error=None):
    code, result = run(*args)
    if error:
        assert code and result['error']['code'] == error, (code, result)
        return result
    assert not code, result
    return result['result']
def j(value):
    return json.dumps(value, ensure_ascii=False)
def ident():
    return str(uuid.uuid4())

def qualify(root):
    book = root / 'Receiving.sevra'
    call('create', book, 'Receiving')
    source = call('add', book, j({'category': 'source', 'kind': 'observation', 'title': 'Delivery receipt',
                                  'text': 'Received 5 bolts and 2 nuts.', 'status': 'accepted'}))
    registry = call('action-registry', book)
    assert {x['id'] for x in registry} == {'inventory.receiveDelivery', 'inventory.proposeMovement'}
    template = call('receiving-template', book)
    action = call('definition-save', book, ident(), j(template), 'new', 'define-action')
    form_content = call('form-template', book, action['id'])
    form = call('definition-save', book, ident(), j(form_content), 'new', 'define-form')
    initial = call('form-draft-new', book, form['logicalID'])
    assert initial['definitionID'] == form['id']
    draft = copy.deepcopy(initial)
    draft['arguments'] = {'delivery': 'receipt-001', 'effective': '2026-10-28', 'evidence': source['id'],
                         'lines': [{'line': '1', 'subject': 'bolts', 'quantity': '5'},
                                   {'line': '2', 'subject': 'nuts', 'quantity': '2'}]}
    revision = call('inspect', book)
    saved = call('form-draft-save', book, 'Home:receiving', j(draft), 'null')
    assert call('inspect', book) == revision
    assert call('form-draft-read', book, 'Home:receiving') == saved
    preview = call('form-draft-preview', book, j(saved))
    assert len(preview['movements']) == 2
    assert call('inspect', book) == revision
    # Two processes race the same preview. One business proposal batch wins.
    def compete(token):
        return run('action-invoke', book, form['id'], j(saved['arguments']), j(preview), token)
    with ThreadPoolExecutor(2) as pool:
        race = list(pool.map(compete, ['receive-one', 'receive-two']))
    assert sum(code == 0 for code, _ in race) == 1, race
    winner = next(result['result'] for code, result in race if not code)
    token = next(token for token, (code, _) in zip(['receive-one', 'receive-two'], race) if not code)
    assert next(result['error']['code'] for code, result in race if code) == 'duplicate_effect'
    schema = registry[0]['resultSchema']
    assert schema['type'] == 'object' and not schema['additionalProperties']
    assert set(schema['required']) == set(schema['properties']) == set(winner)
    assert winner['state'] == 'draft' and winner['acceptedBalanceChanged'] is False
    assert all(call('read', book, x)['item']['status'] == 'draft' for x in winner['proposals'])
    original_history = call('commits', book, 1000)
    assert call('action-invoke', book, form['id'], j(saved['arguments']), j(preview), token) == winner
    assert call('commits', book, 1000) == original_history
    # Store the actual submitted receipt only with its exact invocation identity.
    submitted = copy.deepcopy(saved)
    submitted['invocationToken'] = token
    submitted['lastReceipt'] = winner
    submitted = call('form-draft-save', book, 'Home:receiving', j(submitted), j(saved))
    call('form-draft-preview', book, j(submitted), error='form_submitted')
    forged = copy.deepcopy(submitted); forged['arguments']['delivery'] = 'forged'
    call('form-draft-save', book, 'Home:receiving', j(forged), j(submitted), error='action_token')
    # A form component is reusable native metadata, never a pinned action result.
    space = {'version': 1, 'components': [{'id': 'receiving', 'type': 'form', 'title': 'Receive delivery',
             'definitionBinding': {'mode': 'live', 'logicalID': form['logicalID']}}]}
    space_id = call('space', book, 'Receiving', j(space))
    call('pin-space', book, space_id, error='view_limit')
    assert len(call('definition-search', book, 'delivery', '{"kind":"form"}')['hits']) == 1
    # Explicit stale-base conflict retains both incomplete raw drafts without effects.
    fresh = call('form-draft-new', book, form['id'])
    fresh['arguments'] = {'delivery': 'incomplete α'}
    call('form-draft-save', book, 'Conflict', j(fresh), 'null')
    competing = copy.deepcopy(fresh); competing['arguments']['delivery'] = 'other β'
    call('form-draft-save', book, 'Conflict', j(competing), 'null', error='form_draft_conflict')
    kept = call('form-draft-save', book, 'Conflict', j(competing), 'null', '--keep-both')
    assert kept['arguments']['delivery'] == 'other β' and kept['alternatives'][0]['arguments']['delivery'] == 'incomplete α'
    renamed = copy.deepcopy(template)
    renamed['title'] = 'Prepare a count correction'
    renamed['description'] = 'Explicit custom action title'
    renamed_action = call('definition-save', book, ident(), j(renamed), 'new', 'renamed-action')
    renamed_form = call('form-template', book, renamed_action['id'])
    assert renamed_form['title'] == renamed_action['title'] and renamed_form['description'] == renamed_action['description']
    reconstructed = root / 'Reconstructed.sevra'
    call('reconstruct', book, reconstructed)
    assert call('form-draft-read', reconstructed, 'Home:receiving') == submitted
    assert call('form-draft-read', reconstructed, 'Conflict') == kept
    call('verify', reconstructed)
    portable = root / 'Receiving.sevraz'
    call('export', book, portable)
    imported = root / 'Portable.sevra'
    call('open-archive', portable, imported)
    assert call('form-draft-read', imported, 'Home:receiving') == submitted
    assert call('definition-read', imported, form['id']) == form
    call('verify', imported)
    return {'schema': 14, 'registry': [x['id'] for x in registry], 'proposalCount': len(winner['proposals']),
            'race': [{'code': code, 'error': result.get('error')} for code, result in race],
            'portableBytes': portable.stat().st_size, 'portableSHA256': hashlib.sha256(portable.read_bytes()).hexdigest(),
            'scope': 'Synthetic independent CLI writers, exact retries, draft conflict retention, reconstruction and portable round trip; no model or visible UI claim'}

if options.keep:
    root = options.keep.resolve()
    root.mkdir(parents=True, exist_ok=False)
    result = qualify(root)
else:
    with tempfile.TemporaryDirectory(prefix='sevra-registered-actions-') as directory:
        result = qualify(Path(directory))
if options.output:
    options.output.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
