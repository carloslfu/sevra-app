#!/usr/bin/env python3
"""Check installed calendar planning without opening a workbook or loading AI."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    cli = args.cli.resolve(strict=True)
    scratch = None if args.output else tempfile.TemporaryDirectory(prefix='sevra-calendar-')
    output = args.output.resolve() if args.output else Path(scratch.name)
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    result = {
        'ok': False, 'calls': [],
        'recordedUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'sourceCommit': subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'cliSHA256': hashlib.sha256(cli.read_bytes()).hexdigest(),
        'sourceSHA256': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                         for p in [ROOT / 'Sources/SevraCore/CalendarSchedule.swift',
                                   ROOT / 'Sources/SevraCLI/CLISchedules.swift',
                                   ROOT / 'Sources/SevraCLI/CLI.swift', Path(__file__).resolve()]},
        'limits': ['Synthetic deterministic calendar previews only. No activation, durable trigger '
                   'dispatch, missed-run execution, native UI, inference or release claim.'],
    }

    def save():
        (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')

    def rule(zone='UTC', hour=9, minute=0, recurrence=None):
        return {'policy': 'native-calendar-v1', 'timeZone': zone, 'hour': hour, 'minute': minute,
                'recurrence': recurrence or {'kind': 'daily'}}

    with tempfile.TemporaryDirectory(prefix='sevra-schedule-preview-') as directory:
        work = Path(directory)

        def call(schedule, after='2026-10-29T00:00:00Z', *limits, error=None, extra=()):
            raw = json.dumps(schedule) if isinstance(schedule, dict) else schedule
            started = time.monotonic()
            p = subprocess.run([str(cli), 'schedule-preview', raw, after, *map(str, limits), *extra],
                               cwd=work, capture_output=True, text=True, timeout=30)
            result['calls'].append({'schedule': raw, 'after': after, 'limits': list(limits),
                                    'extra': list(extra), 'expectedError': error,
                                    'returncode': p.returncode, 'seconds': time.monotonic() - started,
                                    'stdout': p.stdout, 'stderr': p.stderr})
            save()
            if error:
                assert p.returncode != 0 and not p.stdout, result['calls'][-1]
                value = json.loads(p.stderr)
                assert not value['ok'] and value['error']['code'] == error, value
                return value
            assert p.returncode == 0 and not p.stderr, result['calls'][-1]
            envelope = json.loads(p.stdout)
            assert envelope['ok'], envelope
            value = envelope['result']
            assert value['scope'] == 'schedule-preview-only' and value['execution'] == 'none'
            instants = [o['due'] for o in value['occurrences']]
            keys = [o['slotKey'] for o in value['occurrences']]
            assert len(keys) == len(set(keys)) and instants == sorted(set(instants)), value
            return value

        try:
            bogota = call(rule('America/Bogota'), '2026-10-29T14:00:00Z', 2)
            assert [o['due'] for o in bogota['occurrences']] == [
                '2026-10-30T14:00:00.000Z', '2026-10-31T14:00:00.000Z']
            gap = call(rule('America/New_York', 2, 37), '2026-03-07T12:00:00Z', 2)
            assert gap['occurrences'][0]['due'] == '2026-03-08T07:00:00.000Z'
            assert gap['occurrences'][0]['shifted'] and not gap['occurrences'][1]['shifted']
            fold = call(rule('America/New_York', 1, 30), '2026-11-01T05:45:00Z', 1)
            assert fold['occurrences'][0]['localDate'] == '2026-11-02'
            half = call(rule('Australia/Lord_Howe', 2, 15), '2026-10-03T03:00:00Z', 1)
            assert half['occurrences'][0]['due'] == '2026-10-03T15:30:00.000Z'
            assert half['occurrences'][0]['actualLocalTime'] == '02:30:00'
            historic = call(rule('Africa/Monrovia', 0, 30), '1972-01-06T12:00:00Z', 1)
            assert historic['occurrences'][0]['actualLocalTime'] == '00:44:30'
            skipped = call(rule('Pacific/Apia'), '2011-12-29T00:00:00Z', 3)
            assert [o['localDate'] for o in skipped['occurrences']] == [
                '2011-12-29', '2011-12-31', '2012-01-01']
            weekly = call(rule(recurrence={'kind': 'weekly', 'weekdays': [7, 1]}),
                          '2026-12-31T00:00:00Z', 3)
            assert weekly['schedule']['recurrence']['weekdays'] == [1, 7]
            assert [o['localDate'] for o in weekly['occurrences']] == [
                '2027-01-03', '2027-01-04', '2027-01-10']
            monthly = call(rule(recurrence={'kind': 'monthly', 'day': 31}),
                           '2026-01-31T10:00:00Z', 2)
            assert [o['localDate'] for o in monthly['occurrences']] == ['2026-03-31', '2026-05-31']
            last = call(rule(recurrence={'kind': 'monthly', 'day': 'last'}),
                        '2028-01-31T10:00:00Z', 1)
            assert last['occurrences'][0]['localDate'] == '2028-02-29'
            leap = call(rule(recurrence={'kind': 'yearly', 'month': 2, 'day': 29}),
                        '2096-03-01T00:00:00Z', 1)
            assert leap['occurrences'][0]['localDate'] == '2104-02-29'
            bounded = call(rule(), '2026-10-29T10:00:00Z', 1, 1)
            assert not bounded['occurrences'] and bounded['stopReason'] == 'horizon'
            assert not bounded['countReached'] and bounded['examinedDays'] == 1
            assert bounded['scannedThroughExclusive'] == '2026-10-30T00:00:00.000Z'
            maximum = call(rule(hour=23, minute=59), '2026-10-29T00:00:00Z', 100, 3660)
            assert maximum['countReached'] and len(maximum['occurrences']) == 100
            fixture = work / 'schedule.json'
            fixture.write_text(json.dumps(rule('America/Bogota')))
            assert call('@' + str(fixture), '2026-10-29T14:00:00Z', 2) == bogota
            call(rule(), '2026-10-29', error='date')
            call(rule(), '2026-10-29T09:00:00', error='date')
            call(rule(), '2026-02-30T09:00:00Z', error='date')
            call(rule(hour=24), error='schedule')
            call(rule('PST'), error='schedule_zone')
            call(rule(recurrence={'kind': 'weekly', 'weekdays': [1, 1]}), error='schedule')
            call(rule(recurrence={'kind': 'weekly', 'weekdays': [1.5]}), error='schedule')
            call(rule(recurrence={'kind': 'yearly', 'month': 2, 'day': 30}), error='schedule')
            call({**rule(), 'enabled': True}, error='schedule')
            call(rule(), '2026-10-29T00:00:00Z', 101, error='schedule_limit')
            call(rule(), '2026-10-29T00:00:00Z', 1, 3661, error='schedule_limit')
            call(rule(), '2026-10-29T00:00:00Z', 'invalid', error='schedule_limit')
            call(rule(), '2026-10-29T00:00:00Z', extra=('1', '1', 'extra'), error='usage')
            oversized = work / 'oversized.json'
            oversized.write_bytes(b' ' * 65_537)
            call('@' + str(oversized), error='schedule_limit')
            call(' ' * 65_537, error='schedule_limit')
            invalid_utf8 = work / 'invalid.json'
            invalid_utf8.write_bytes(b'\xff')
            call('@' + str(invalid_utf8), error='schedule')
            call('@' + str(work), error='schedule')
            fifo = work / 'pipe.json'
            os.mkfifo(fifo)
            call('@' + str(fifo), error='schedule')
            assert not list(work.glob('*.sevra'))
            result['ok'] = True
        finally:
            save()
    print(json.dumps({'ok': result['ok'], 'calls': len(result['calls']), 'output': str(args.output or '')}))


if __name__ == '__main__':
    main()
