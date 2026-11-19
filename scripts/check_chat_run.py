"""No-model check of the `run` chat tool: scripts that read, loop and change tables, one Undo,
failures that change nothing, the limits and the sandbox.

Each case calls the tool through the CLI on a temporary synthetic workbook, the same way a
chat request does. It needs no model and no engine.

    swift build --product sevra && swift build --product sevra-extract && python3 scripts/check_chat_run.py

SEVRA_CLI selects another CLI. The helper is the sevra-extract beside it.
"""
from pathlib import Path
import json, os, subprocess, sys, tempfile

ROOT = Path(__file__).resolve().parent.parent
os.environ.setdefault('SEVRA_CLI', str(ROOT / '.build/debug/sevra'))
sys.path.insert(0, str(ROOT / 'scripts'))
from check_chat_jobs import Book, CLIError, levels, parts  # noqa: E402

failures = []


def expect(name, condition, detail=''):
    if not condition:
        failures.append(name + (': ' + str(detail)[:400] if detail != '' else ''))


def run(book, code):
    return book.run('tool', 'run', {'code': code})


def refused(name, book, code, needle=''):
    before = (book.values('Parts'), book.values('Reorder levels'))
    try:
        result = run(book, code)
        expect(name, False, 'not refused: ' + json.dumps(result)[:300])
    except CLIError as error:
        expect(name + ' message', needle in str(error), error)
    expect(name + ' changed nothing', (book.values('Parts'), book.values('Reorder levels')) == before)


with tempfile.TemporaryDirectory() as folder:
    book = Book(Path(folder) / 'run.sevra')
    parts(book)
    levels(book)
    start = book.values('Parts')

    # Reading.
    counted = run(book, "const rows = await sql('SELECT part, stock FROM parts ORDER BY part'); return rows.length;")
    expect('a script reads rows', counted['value'] == 6 and 'changes' not in counted and 'undo' not in counted, counted)
    expect('it names the table it read', [t['table'] for t in counted['read']] == ['parts'], counted['read'])
    typed = run(book, "const rows = await sql('SELECT part, stock FROM parts WHERE part = :p', {p: 'Hex nuts'});"
                      " return [rows[0].part, rows[0].stock + 1, typeof rows[0].stock];")
    expect('numbers are numbers and values bind', typed['value'][0] == 'Hex nuts' and typed['value'][2] == 'number', typed)
    stock = {r['part']: float(r['stock']) for r in start}
    expect('the bound row is the right one', typed['value'][1] == stock['Hex nuts'] + 1, typed)
    fixed = run(book, "return [new Date().getTime() === Date.now(), /^\\d{4}-\\d{2}-\\d{2}$/.test(today),"
                      " typeof fetch, typeof require, typeof process];")
    expect('a fixed clock and nothing to reach', fixed['value'] == [True, True, 'undefined', 'undefined', 'undefined'], fixed)
    logged = run(book, "console.log('checking', {n: 2}); return null;")
    expect('console output comes back', logged.get('log') == ['checking {"n":2}'], logged)

    # A loop that changes two tables is saved once, with one Undo.
    code = """
    const low = await sql('SELECT part, stock, reorder_level FROM parts WHERE stock < reorder_level ORDER BY part');
    for (const row of low) {
      await sql('UPDATE parts SET stock = :stock WHERE part = :part', {stock: row.reorder_level * 2, part: row.part});
    }
    const missing = await sql('SELECT part FROM parts WHERE part NOT IN (SELECT part FROM reorder_levels)');
    for (const row of missing) await sql('INSERT INTO reorder_levels(part, level) VALUES (:part, 0)', {part: row.part});
    const after = await sql('SELECT count(*) AS n FROM parts WHERE stock < reorder_level');
    return {raised: low.map(r => r.part), added: missing.length, stillLow: after[0].n};
    """
    levels_before = book.values('Reorder levels')
    looped = run(book, code)
    low = sorted(r['part'] for r in start if float(r['stock']) < float(r['reorder_level']))
    expect('a loop computes and changes', looped['value'] == {'raised': low, 'added': 3, 'stillLow': 0}, looped['value'])
    expect('both tables changed', sorted(c['table'] for c in looped.get('changes', [])) == ['parts', 'reorder_levels'], looped)
    expect('the script saw its own writes', len(book.values('Reorder levels')) == len(levels_before) + 3)
    book.run('tool', 'sql', {'undo': looped['undo']})
    expect('one undo for the script', book.values('Parts') == start and book.values('Reorder levels') == levels_before)

    # Failures change nothing.
    refused('a thrown error', book, "await sql('UPDATE parts SET stock = 0'); throw new Error('stop here');", 'stop here')
    refused('a missing await', book, "sql('UPDATE parts SET stock = 0'); return 1;", 'await')
    refused('a syntax error', book, "const x = ; return x;", 'syntax')
    refused('an endless loop', book, "while (true) {} return 1;")
    refused('too many calls', book, "for (let i = 0; i < 60; i++) await sql('SELECT ' + i); return 1;", 'at most')
    refused('a refused statement', book, "await sql('UPDATE parts SET stock = 1'); await sql(\"ATTACH DATABASE '/tmp/x.db' AS o\"); return 1;")
    refused('randomness', book, "return Math.random();", 'randomness')
    refused('a result too large', book, "return 'x'.repeat(20000);", '12,000')
    caught = run(book, "try { await sql('SELECT missing FROM parts'); } catch (e) { return 'caught'; }")
    expect('a script can catch a refused statement', caught['value'] == 'caught', caught)

    # Search and read reach the saved workbook.
    appendix = book.document('Supplier note', 'Oak Supply ships on Tuesdays.')
    found = run(book, "const hits = await search('Tuesdays'); const item = await read(%s);"
                      " return [JSON.stringify(hits).includes('Supplier note'), JSON.stringify(item).includes('Tuesdays')];"
                % json.dumps(appendix))
    expect('search and read', found['value'] == [True, True], found)

    # A queued action runs after the script. One that needs the app is refused first.
    table = book.table('Parts')
    queued = run(book, "action('table.schema', {id: %s}); return 'ok';" % json.dumps(table['id']))
    expect('a queued action runs afterwards', queued['value'] == 'ok' and queued['actions'][0]['action'] == 'table.schema'
           and 'result' in queued['actions'][0], queued)
    refused('an action that needs the app', book,
            "await sql('UPDATE parts SET stock = 0'); action('form.submit', {id: 'x', inputs: {}}); return 1;", 'needs the app')
    book.run('verify')

    # The helper cannot read or write a file.
    probe = Path(folder) / 'probe.txt'
    probe.write_text('secret')
    request = Path(folder) / 'request.json'
    request.write_text(json.dumps({'source': 'return 1;', 'answers': [], 'now': 0, 'today': '2026-01-01',
                                   'sandboxProbe': str(probe)}))
    helper = Path(os.environ['SEVRA_CLI']).parent / 'sevra-extract'
    reply = subprocess.run([str(helper), '--chat-script', str(request)], capture_output=True, text=True, timeout=30)
    try:
        denied = json.loads(reply.stdout)['result']
    except Exception:
        denied = reply.stdout + reply.stderr
    expect('the sandbox denies files', denied == {'deniedRead': True, 'deniedWrite': True}, denied)
    expect('the probe left no file', not Path(str(probe) + '.probe').exists())

print('\n'.join(failures) if failures else 'run chat tool: passed')
sys.exit(1 if failures else 0)
