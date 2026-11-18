"""No-model check of the `sql` chat tool: reads, row changes, Undo, drafts and refusals.

Each case calls the tool through the CLI on a temporary synthetic workbook, the same way a
chat request does, and reads the workbook back. It needs no model and no engine.

    swift build --product sevra && python3 scripts/check_chat_sql.py

SEVRA_CLI selects another CLI.
"""
from pathlib import Path
import os, sys, tempfile

ROOT = Path(__file__).resolve().parent.parent
os.environ.setdefault('SEVRA_CLI', str(ROOT / '.build/debug/sevra'))
sys.path.insert(0, str(ROOT / 'scripts'))
from check_chat_jobs import Book, CLIError, SUPPLIERS, levels, parts  # noqa: E402

failures = []


def expect(name, condition, detail=''):
    if not condition:
        failures.append(name + (': ' + str(detail)[:300] if detail != '' else ''))


def sql(book, *statements, **extra):
    return book.run('tool', 'sql', dict(statements=list(statements), **extra))


def refused(name, book, code, *statements, **extra):
    before = book.values(SUPPLIERS)
    try:
        result = sql(book, *statements, **extra)
        expect(name, False, 'not refused: ' + str(result))
    except CLIError as error:
        expect(name + ' code', error.code == code, error)
    expect(name + ' changed nothing', book.values(SUPPLIERS) == before)


def rows(result, index=0):
    return result['results'][index]['rows']


with tempfile.TemporaryDirectory() as folder:
    book = Book(Path(folder) / 'check.sevra')
    parts(book)
    levels(book)
    start = book.values(SUPPLIERS)

    # Reading.
    catalog = sql(book, "SELECT table_name, name, type FROM columns ORDER BY 1, 2")
    names = {(r[0], r[1]) for r in rows(catalog)}
    expect('catalog names tables and columns',
           {('supplier_comparison', 'supplier'), ('parts', 'reorder_level'), ('reorder_levels', 'level')} <= names,
           sorted(names))
    expect('catalog marks the formula', ['supplier_comparison', 'total', 'formula'] in rows(catalog), rows(catalog))
    read = sql(book, "SELECT supplier, total FROM supplier_comparison ORDER BY total")
    expect('reads calculated totals', rows(read) == [['Oak Supply', '24'], ['Cedar Tools', '27.5']], rows(read))
    expect('names the table it read', [t['table'] for t in read['read']] == ['supplier_comparison'], read['read'])
    expect('offers the rows it read', len(read['inputs']) == 2, read['inputs'])
    figures = sql(book, "SELECT round(100.0 * (27.5 - 24) / 27.5, 2), 0.1 + 0.2, count(*), sum(stock) FROM parts")
    expect('arithmetic is clean', rows(figures) == [['12.73', '0.3', '6', '399']], rows(figures))
    joined = sql(book, "SELECT p.part FROM parts p LEFT JOIN reorder_levels l ON l.part = p.part "
                       "WHERE l.part IS NULL ORDER BY p.part")
    expect('joins tables', [r[0] for r in rows(joined)] == ['Hex key set', 'Torque wrench', 'Wood screws'], rows(joined))
    expect('a read saves nothing', 'changes' not in read and book.values(SUPPLIERS) == start)
    listed = sql(book, "SELECT title, row_count FROM tables WHERE name = 'supplier_comparison'")
    expect('tables are found by name', rows(listed) == [['Supplier comparison', '2']], rows(listed))

    # Row changes, each one saved transaction with an Undo.
    update = sql(book, "UPDATE supplier_comparison SET quantity = 20")
    change = update.get('changes', [{}])[0]
    expect('update counts', (change.get('updated'), change.get('inserted'), change.get('deleted')) == (2, 0, 0), update)
    after = {r['supplier']: (r['quantity'], r['total']) for r in book.values(SUPPLIERS)}
    expect('update recalculates', after == {'Oak Supply': ('20', '48'), 'Cedar Tools': ('20', '55')}, after)
    book.run('tool', 'workspace_action', {'action': 'table.undo_rows', 'arguments': change['undo']})
    expect('undo restores', book.values(SUPPLIERS) == start, book.values(SUPPLIERS))
    mixed = sql(book,
                "INSERT INTO supplier_comparison(supplier, quantity, unit_cost) VALUES ('Birch Metals', 10, 2.55)",
                "UPDATE supplier_comparison SET unit_cost = unit_cost * 1.1 WHERE supplier = 'Oak Supply'",
                "DELETE FROM supplier_comparison WHERE supplier = 'Cedar Tools'")
    change = mixed.get('changes', [{}])[0]
    expect('mixed counts', (change.get('inserted'), change.get('updated'), change.get('deleted')) == (1, 1, 1), mixed)
    after = {r['supplier']: (r['quantity'], r['unit_cost'], r['total']) for r in book.values(SUPPLIERS)}
    expect('mixed result', after == {'Oak Supply': ('10', '2.64', '26.4'), 'Birch Metals': ('10', '2.55', '25.5')}, after)
    book.run('tool', 'workspace_action', {'action': 'table.undo_rows', 'arguments': change['undo']})
    expect('one undo for the call', book.values(SUPPLIERS) == start, book.values(SUPPLIERS))
    filled = sql(book, "INSERT INTO reorder_levels(part, level) SELECT part, 0 FROM parts "
                       "WHERE part NOT IN (SELECT part FROM reorder_levels)")
    expect('insert from another table', filled['changes'][0]['inserted'] == 3, filled)
    expect('insert kept the other table', len(book.values('Parts')) == 6 and len(book.values('Reorder levels')) == 6)
    same = sql(book, "UPDATE supplier_comparison SET quantity = quantity")
    expect('a change to the same value saves nothing', 'changes' not in same, same)

    # A draft changes nothing.
    draft = sql(book, "UPDATE supplier_comparison SET unit_cost = 2.60 WHERE supplier = 'Cedar Tools'", draft=True)
    expect('draft is saved', draft.get('drafts', [{}])[0].get('draftRows') == 1, draft)
    expect('draft changes nothing', book.values(SUPPLIERS) == start)
    refused('draft of an insert', book, 'sql_draft',
            "INSERT INTO supplier_comparison(supplier) VALUES ('Elm Fasteners')", draft=True)

    # Refusals. Each leaves the workbook as it was.
    refused('drop', book, 'sql_shape', "DROP TABLE supplier_comparison")
    refused('create', book, 'sql_shape', "CREATE TABLE extra(a)")
    refused('alter', book, 'sql_shape', "ALTER TABLE supplier_comparison RENAME COLUMN unit_cost TO price_each")
    refused('attach', book, 'sql', "ATTACH DATABASE '/tmp/sevra-check-should-not-exist.db' AS other")
    refused('pragma', book, 'sql', "PRAGMA table_info(parts)")
    refused('transaction', book, 'sql', "BEGIN")
    refused('schema table', book, 'sql', "SELECT * FROM sqlite_master")
    refused('host log', book, 'sql', "DELETE FROM _sevra_log")
    refused('catalog write', book, 'sql', "DELETE FROM tables")
    refused('formula column', book, 'sql', "UPDATE supplier_comparison SET total = 1")
    refused('two statements in one entry', book, 'sql', "SELECT 1; DELETE FROM supplier_comparison")
    refused('text in a number column', book, 'sql_value', "UPDATE supplier_comparison SET quantity = 'many'")
    refused('unknown column', book, 'sql', "SELECT missing FROM parts")
    refused('later failure undoes earlier statements', book, 'sql',
            "DELETE FROM supplier_comparison", "SELECT missing FROM parts")
    expect('no file was attached', not os.path.exists('/tmp/sevra-check-should-not-exist.db'))

print('\n'.join(failures) if failures else 'sql chat tool: passed')
sys.exit(1 if failures else 0)
