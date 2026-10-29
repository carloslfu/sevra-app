#!/usr/bin/env python3
"""Current-format synthetic CLI journeys for reviewed table updates and exact retries."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


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
    print(json.dumps({'ok': True, 'count': len(checks), 'checks': checks}, indent=2))


if __name__ == '__main__':
    main()
