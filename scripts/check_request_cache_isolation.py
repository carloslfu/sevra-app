"""Require actual wire evidence for I2 and refuse its use as a speed gate."""
import base64
import copy
import hashlib
import json
from pathlib import Path
import struct
import tempfile

from check_workflow_isolation import results as fixtures
from probe_request_cache_isolation import ROOT, REQUEST, SALT_HIGH, summarize, verify_salts
from compare_workflow_performance import summarize as performance_summary
from check_workflow_performance import results as cohort, protocol as performance_protocol

protocol = json.loads((ROOT / 'integration/performance/request-cache-isolation-pilot.json').read_text())
with tempfile.TemporaryDirectory() as temporary:
    folder = Path(temporary)
    results = []
    for arm in protocol['arms']:
        for prototype in fixtures[:2]:
            result = copy.deepcopy(prototype)
            result['cacheArm'] = arm
            index = 0
            for job in [result['ready']['prime']] + result['rows']:
                for request in job['trace']['requests']:
                    index += 1
                    fields = [1, 0, 1, 1, 180000000, 1800, 1, 0, 0., 1., 0, 0., 0., 1., 0., 42, 0, 0, 0,
                              index if arm == 'isolated' else 0, SALT_HIGH if arm == 'isolated' else 0, 512, 0, 0]
                    payload = REQUEST.pack(*fields) + struct.pack('<I', 99)
                    frame = struct.pack('<4sHHQ', b'SPLH', 11, 1, len(payload)) + payload
                    checksum = hashlib.sha256(frame).hexdigest()
                    (folder / (checksum + '.request.json')).write_text(json.dumps({'base64': base64.b64encode(frame).decode()}))
                    request['requestSHA256'] = checksum
                    request['metrics']['diagnosticRequestCacheIsolation'] = arm == 'isolated'
            results.append(result)
    directories = {arm: folder for arm in protocol['arms']}
    report = summarize(results, protocol, directories)
    assert report['completeComparison'] and all(a['armPassed'] for a in report['arms'].values())
    assert not report['performanceQualification'] and not report['productionAdoption']
    assert not summarize(results[:-1], protocol, directories)['completeComparison']
    assert not summarize(results + results[:1], protocol, directories)['completeComparison']
    assert not summarize(results, protocol, directories, ['source.swift'])['arms']['isolated']['armPassed']
    for name, mutate in [
        ('missing flag', lambda r: r['metrics'].pop('diagnosticRequestCacheIsolation')),
        ('contradictory flag', lambda r: r['metrics'].update(diagnosticRequestCacheIsolation=False)),
        ('initial reuse', lambda r: r['metrics'].update(matchedPromptTokens=32)),
        ('later reuse', lambda r: r['metrics'].update(deduplicatedKVTokens=32)),
        ('missing frame', lambda r: r.update(requestSHA256='0' * 64)),
        ('path traversal', lambda r: r.update(requestSHA256='../outside')),
        ('repeated salt', lambda r: r.update(requestSHA256=results[2]['ready']['prime']['trace']['requests'][0]['requestSHA256'])),
    ]:
        changed = copy.deepcopy(results)
        mutate(changed[2]['rows'][0]['trace']['requests'][0])
        assert not summarize(changed, protocol, directories)['arms']['isolated']['armPassed'], name
    # A present file is insufficient: bind it to its hash, framing and salt.
    first = results[2]['ready']['prime']['trace']['requests'][0]
    path = folder / (first['requestSHA256'] + '.request.json')
    path.write_text(json.dumps({'base64': base64.b64encode(b'bad frame').decode()}))
    assert verify_salts(results[2], folder, True)['problems']

changed = copy.deepcopy(cohort)
changed[0]['rows'][0]['trace']['requests'][0]['metrics'] = {'diagnosticRequestCacheIsolation': True}
report = performance_summary(changed, performance_protocol, False)
assert not report['workflowGatePassed'] and not report['timingsEligibleForQualification']
print('PASS request-cache isolation requires verified unique wire salts and zero reuse; never qualifies performance')
