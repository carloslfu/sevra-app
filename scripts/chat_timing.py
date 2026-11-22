"""Reads the chat timing log and shows where each turn's time went.

Turn timing on for the app, reopen it, then chat:

    defaults write com.sevra.workbooks SevraChatTiming -bool true

or run the command line tool with SEVRA_CHAT_TIMING=1. Each turn adds one JSON line to
~/Library/Logs/Sevra/chat-timing.jsonl (SEVRA_CHAT_TIMING_LOG overrides the path).

    python3 scripts/chat_timing.py                 every turn: steps, then a comparison
    python3 scripts/chat_timing.py --last 5        the last five records
    python3 scripts/chat_timing.py --compare       only the comparison table
    python3 scripts/chat_timing.py --all           also list each background refresh read
    python3 scripts/chat_timing.py --self-test     checks this script without a log

Times are seconds from Send. Steps are nested by when they ran: a step inside another ran
while it did. The log holds no message text.
"""
import argparse
import json
import os
from pathlib import Path
import sys

DEFAULT = Path.home() / 'Library/Logs/Sevra/chat-timing.jsonl'
QUIET = {'ui.refresh_read', 'ui.refresh_prepare', 'model.queue_wait', 'engine.warming',
         'model.prepare_reused', 'agent.step', 'model.call'}


def load(path):
    records = []
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if line:
            records.append(json.loads(line))
    return records


def spans(record):
    return [e for e in record['events'] if 'seconds' in e]


def named(record, name):
    return [e for e in record['events'] if e['name'] == name]


def first(record, name):
    found = named(record, name)
    return found[0] if found else None


def total(record, name):
    return sum(e.get('seconds', 0) for e in named(record, name))


def end(event):
    return event['at'] + event.get('seconds', 0)


def tree(record, show_all):
    """Events in order, each nested under the open span that contains it."""
    events = sorted(record['events'], key=lambda e: (e['at'], -e.get('seconds', 0)))
    lines = []
    stack = []
    for event in events:
        # Leave every span that ended before this event, or that this event outlasts.
        while stack and (event['at'] >= end(stack[-1]) - 1e-6
                         or end(event) > end(stack[-1]) + 1e-3):
            stack.pop()
        quiet = event['name'] in QUIET and event.get('seconds', 0) < 0.05
        if show_all or not quiet:
            lines.append((len(stack), event))
        if 'seconds' in event and event['seconds'] > 0:
            stack.append(event)
    return lines


def details(event):
    skip = {'name', 'at', 'seconds', 'metrics'}
    parts = []
    for key, value in event.items():
        if key in skip or value is None:
            continue
        if isinstance(value, float):
            value = f'{value:.3f}' if abs(value) < 1000 else f'{value:.0f}'
        parts.append(f'{key}={value}')
    return ' '.join(parts)


def summary(record):
    """The figures the comparison table shows, from one turn."""
    requests = named(record, 'engine.request')
    calls = named(record, 'agent.model_call')
    drawn = first(record, 'ui.reply_drawn')
    shown = first(record, 'ui.reply_in_view')
    text = first(record, 'ui.first_answer_text')
    finished = first(record, 'turn.request_finished')
    first_request = requests[0] if requests else None
    tools = named(record, 'agent.tool_execute')
    maintenance = total(record, 'agent.context_maintenance') + total(record, 'agent.step_maintenance')
    before_model = first_request['at'] if first_request else None
    return {
        'seconds': record['seconds'],
        'drawn': drawn['at'] if drawn else None,
        'shown': shown['at'] if shown else None,
        'firstText': text['at'] if text else None,
        'requestDone': finished['at'] if finished else None,
        'beforeFirstDispatch': before_model,
        'calls': len(calls),
        'tools': ','.join(e.get('tool', '') for e in tools) or '-',
        'toolSeconds': sum(e['seconds'] for e in tools),
        'maintenance': maintenance,
        'engineStart': total(record, 'model.engine_ready'),
        'sessionSetup': total(record, 'model.session_setup'),
        'prepare': total(record, 'model.prepare'),
        'grammar': total(record, 'model.grammar_compile'),
        'prime': total(record, 'engine.prime'),
        'engine': sum(e['seconds'] for e in requests),
        'prefill': sum(e.get('prefillSeconds', 0) for e in requests),
        'decode': sum(e.get('decodeSeconds', 0) for e in requests),
        'masks': sum(e.get('maskSeconds', 0) for e in requests),
        'promptTokens': first_request.get('promptTokens') if first_request else None,
        'matched': first_request.get('matchedTokens') if first_request else None,
        'computed': sum(e.get('computedTokens', 0) for e in requests),
        'generated': sum(e.get('generatedTokens', 0) for e in requests),
        'reasoning': sum(e.get('reasoningTokens', 0) for e in requests),
        'save': total(record, 'agent.save_answer'),
        'history': record.get('historyMessages'),
        'lockWait': sum(v['seconds'] for k, v in record.get('totals', {}).items()
                        if k.startswith('workbook.lock_wait')),
        'mainLate': record.get('totals', {}).get('ui.main_thread_late', {}).get('seconds', 0),
        'refreshReads': total(record, 'ui.refresh_read'),
    }


def number(value, digits=2):
    if value is None:
        return '-'
    if isinstance(value, float):
        return f'{value:.{digits}f}'
    return str(value)


def show(record, index, show_all):
    title = f"#{index}  {record['kind']}  {record.get('startedAt', '')}  {record['seconds']:.2f} s  {record['outcome']}"
    if record['kind'] == 'turn':
        title += f"  origin={record.get('origin')} history={record.get('historyMessages', '-')}"
    print(title)
    for depth, event in tree(record, show_all):
        label = '  ' * (depth + 1) + event['name']
        when = f"{event['at']:8.3f}"
        length = f"{event['seconds']:8.3f}" if 'seconds' in event else '       ·'
        print(f'{when} {length}  {label}  {details(event)}'.rstrip())
    totals = record.get('totals', {})
    if totals:
        print('  totals: ' + ', '.join(
            f"{k} {v['count']}x {v['seconds']:.3f} s" for k, v in sorted(totals.items())))
    print()


COLUMNS = [
    ('turn', None), ('hist', 'history'), ('total', 'seconds'), ('text', 'firstText'),
    ('shown', 'shown'), ('pre', 'beforeFirstDispatch'), ('calls', 'calls'),
    ('start', 'engineStart'), ('prep', 'prepare'), ('gram', 'grammar'), ('prime', 'prime'),
    ('engine', 'engine'), ('prefill', 'prefill'), ('decode', 'decode'), ('mask', 'masks'),
    ('prompt', 'promptTokens'), ('match', 'matched'), ('comp', 'computed'),
    ('gen', 'generated'), ('think', 'reasoning'), ('tool', 'toolSeconds'),
    ('maint', 'maintenance'), ('save', 'save'), ('lock', 'lockWait'), ('late', 'mainLate'),
    ('tools', 'tools'),
]


def compare(records):
    turns = [(i, r) for i, r in enumerate(records, 1) if r['kind'] == 'turn']
    if not turns:
        print('No chat turns in the log.')
        return
    rows = []
    for index, record in turns:
        s = summary(record)
        row = []
        for header, key in COLUMNS:
            row.append(f'#{index}' if key is None else number(s[key]))
        rows.append(row)
    widths = [max(len(h), *(len(r[c]) for r in rows)) for c, (h, _) in enumerate(COLUMNS)]
    print('  '.join(h.rjust(w) for (h, _), w in zip(COLUMNS, widths)))
    for row in rows:
        print('  '.join(v.rjust(w) for v, w in zip(row, widths)))
    print()
    print('total: Send to the reply drawn. text: first answer text on screen. shown: saved reply in the')
    print('chat. pre: Send to the first engine request. start: engine start. prep: prompt building')
    print('and tokenizing. gram: grammar compile. engine: engine request time, of which prefill and')
    print('decode as the engine counts them, and mask the host spent on grammar masks. prompt and')
    print('match: tokens of the first call and how many it resumed. comp: tokens computed in all calls.')
    print('gen and think: tokens generated and of those, hidden reasoning. tool: tool time. maint: context')
    print('maintenance. lock: waits for the workbook lock. late: main thread lateness over 20 ms.')


def self_test():
    record = {
        'kind': 'turn', 'outcome': 'complete', 'seconds': 3.0, 'origin': 'app',
        'historyMessages': 2, 'totals': {'workbook.lock_wait': {'count': 1, 'seconds': 0.01}},
        'events': [
            {'name': 'ui.send', 'at': 0},
            {'name': 'agent.model_call', 'at': 0.5, 'seconds': 2.0, 'step': 1},
            {'name': 'engine.request', 'at': 0.6, 'seconds': 1.8, 'prefillSeconds': 0.5,
             'decodeSeconds': 1.2, 'promptTokens': 6000, 'matchedTokens': 5000,
             'computedTokens': 1000, 'generatedTokens': 40, 'reasoningTokens': 20,
             'maskSeconds': 0.05},
            {'name': 'ui.first_answer_text', 'at': 2.0},
            {'name': 'ui.reply_in_view', 'at': 2.9},
            {'name': 'ui.reply_drawn', 'at': 2.95},
        ],
    }
    lines = tree(record, False)
    nested = {e['name']: depth for depth, e in lines}
    assert nested['engine.request'] == nested['agent.model_call'] + 1, nested
    s = summary(record)
    assert s['calls'] == 1 and s['computed'] == 1000 and s['firstText'] == 2.0, s
    assert s['lockWait'] == 0.01 and s['beforeFirstDispatch'] == 0.6, s
    print('chat_timing self-test passed')


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('log', nargs='?', default=os.environ.get('SEVRA_CHAT_TIMING_LOG', DEFAULT))
    parser.add_argument('--last', type=int)
    parser.add_argument('--compare', action='store_true')
    parser.add_argument('--all', action='store_true')
    parser.add_argument('--self-test', action='store_true')
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return
    if not Path(arguments.log).exists():
        sys.exit(f'No timing log at {arguments.log}. Turn chat timing on first; see --help.')
    records = load(arguments.log)
    if arguments.last:
        records = records[-arguments.last:]
    if not arguments.compare:
        for index, record in enumerate(records, 1):
            show(record, index, arguments.all)
    compare(records)


if __name__ == '__main__':
    main()
