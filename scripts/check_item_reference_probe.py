"""Ensure R2 keeps its recorded failures and rejects incomplete evidence."""
import copy
import gzip
import json
from pathlib import Path
from probe_item_references import problems_for

root = Path(__file__).resolve().parents[1]
archive = json.loads(gzip.decompress((root / 'integration/evidence/2026-10-27-exact-item-references.json.gz').read_bytes()))
files = archive['runs']['item-references1']
protocol = files['identity.json']['content']['protocol']
for backend in ['native', 'reference']:
    actual = files[f'0-{backend}.json']['content']
    assert problems_for(actual, protocol) == [
        backend + '/6: failed, excessive or corrected job', backend + '/6: reference detour']
    # The first five trials are the positive control, not a relabeling of R2.
    control = copy.deepcopy(actual)
    control['rows'] = control['rows'][:5]
    scope = dict(protocol, prompts=protocol['prompts'][:5])
    assert not problems_for(control, scope)
    mutations = [
        lambda r: r['rows'].pop(),
        lambda r: r['rows'][0].update(steps=None),
        lambda r: r['rows'][0].update(steps=True),
        lambda r: r['rows'][0].update(validationFailures=1),
        lambda r: r['rows'][0].update(seed=99),
        lambda r: r['rows'][0].update(completeSeconds=float('nan')),
        lambda r: r.update(closed=None),
        lambda r: r['rows'][0]['memory'].update(errors=['failed']),
        lambda r: r['rows'][0]['messages'].append({'role': 'tool', 'body': json.dumps({'result': {'error': 'refused'}})}),
    ]
    for mutate in mutations:
        broken = copy.deepcopy(control)
        mutate(broken)
        assert problems_for(broken, scope)
print('PASS R2 preserves recorded detours and refuses missing/malformed jobs, rejected calls, cleanup and sampling failures')
