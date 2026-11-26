"""No-model check of the `sql` chat tool: reads, row changes, table shape, saved tools, Undo, drafts and refusals.

Each case calls the tool through the CLI on a temporary synthetic workbook, the same way a
chat request does, and reads the workbook back. It needs no model and no engine.

    swift build --product sevra && python3 scripts/check_chat_sql.py

SEVRA_CLI selects another CLI.
"""
from pathlib import Path
import os, shutil, sys, tempfile

ROOT = Path(__file__).resolve().parent.parent
os.environ.setdefault('SEVRA_CLI', str(ROOT / '.build/debug/sevra'))
# Saved tools grant themselves on this Mac. Keep the checks' grants out of the person's own.
os.environ.setdefault('SEVRA_TOOL_GRANTS', tempfile.mkdtemp(prefix='sevra-tool-grants-'))
sys.path.insert(0, str(ROOT / 'scripts'))
from check_chat_jobs import Book, CLIError, SUPPLIERS, levels, parts  # noqa: E402

failures = []


def expect(name, condition, detail=''):
    if not condition:
        failures.append(name + (': ' + str(detail)[:300] if detail != '' else ''))


def sql(book, *statements, **extra):
    return book.run('tool', 'sql', dict(**({'statements': list(statements)} if statements else {}), **extra))


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
    undone = sql(book, undo=update['undo'])
    expect('undo restores', undone.get('undone') is True and book.values(SUPPLIERS) == start, book.values(SUPPLIERS))
    # A formula read later in the same call sees the change (November 26, 2026: it read the old total).
    same = sql(book, "UPDATE supplier_comparison SET unit_cost = 3 WHERE supplier = 'Cedar Tools'",
               "SELECT supplier, total FROM supplier_comparison ORDER BY supplier")
    expect('formula is current within a call', rows(same, 1) == [['Cedar Tools', '30'], ['Oak Supply', '24']], rows(same, 1))
    sql(book, undo=same['undo'])
    expect('formula undo restores', book.values(SUPPLIERS) == start, book.values(SUPPLIERS))
    try:
        sql(book, undo=update['undo'])
        expect('a second undo is refused', False)
    except CLIError as error:
        expect('a second undo is refused', error.code == 'sql_undo', error)
    mixed = sql(book,
                "INSERT INTO supplier_comparison(supplier, quantity, unit_cost) VALUES ('Birch Metals', 10, 2.55)",
                "UPDATE supplier_comparison SET unit_cost = unit_cost * 1.1 WHERE supplier = 'Oak Supply'",
                "DELETE FROM supplier_comparison WHERE supplier = 'Cedar Tools'")
    change = mixed.get('changes', [{}])[0]
    expect('mixed counts', (change.get('inserted'), change.get('updated'), change.get('deleted')) == (1, 1, 1), mixed)
    after = {r['supplier']: (r['quantity'], r['unit_cost'], r['total']) for r in book.values(SUPPLIERS)}
    expect('mixed result', after == {'Oak Supply': ('10', '2.64', '26.4'), 'Birch Metals': ('10', '2.55', '25.5')}, after)
    book.run('tool', 'workspace_action', {'action': 'table.undo_sql', 'arguments': {'token': mixed['undo']}})
    expect('one undo for the call', book.values(SUPPLIERS) == start, book.values(SUPPLIERS))
    first = sql(book, "UPDATE supplier_comparison SET quantity = 30")
    sql(book, "UPDATE supplier_comparison SET quantity = 40")
    try:
        sql(book, undo=first['undo'])
        expect('undo under a later change is refused', False)
    except CLIError as error:
        expect('undo under a later change is refused', error.code == 'sql_undo', error)
    sql(book, "UPDATE supplier_comparison SET quantity = 10")
    expect('back to the start', book.values(SUPPLIERS) == start, book.values(SUPPLIERS))
    filled = sql(book, "INSERT INTO reorder_levels(part, level) SELECT part, 0 FROM parts "
                       "WHERE part NOT IN (SELECT part FROM reorder_levels)")
    expect('insert from another table', filled['changes'][0]['inserted'] == 3, filled)
    expect('insert kept the other table', len(book.values('Parts')) == 6 and len(book.values('Reorder levels')) == 6)
    same = sql(book, "UPDATE supplier_comparison SET quantity = quantity")
    expect('a change to the same value saves nothing', 'changes' not in same, same)

    # Table shape, on a workbook of its own. Each change is saved through the recorded path.
    shape = Book(Path(folder) / 'shape.sevra')
    parts(shape)
    levels(shape)

    def titles(title):
        return [c['title'] for c in shape.table(title)['columns']]

    made = sql(shape, "CREATE TABLE reorder_plan (item TEXT, level REAL)",
               "INSERT INTO reorder_plan VALUES ('Brass bolts', 12), ('Steel washers', 40), ('Hex nuts', 25)")
    change = made.get('shape', [{}])[0]
    expect('create reports the table', (change.get('change'), change.get('title'), change.get('columns'),
                                        change.get('rows')) == ('created', 'Reorder plan', ['Item', 'Level'], 3), made)
    plan = shape.values('Reorder plan') or []
    expect('create saves the rows', [(r['item'], r['level']) for r in plan]
           == [('Brass bolts', '12'), ('Steel washers', '40'), ('Hex nuts', '25')], plan)
    expect('create types the columns', [c['type'] for c in shape.table('Reorder plan')['columns']]
           == ['text', 'decimal'], shape.table('Reorder plan'))
    sql(shape, "CREATE TABLE stock_by_category AS SELECT category, sum(stock) AS total FROM parts GROUP BY category")
    totals = shape.values('Stock by category') or []
    expect('create from a query', sorted((r['category'], r['total']) for r in totals)
           == [('Fasteners', '397'), ('Tools', '2')], totals)
    expect('a query result column is a number', [c['type'] for c in shape.table('Stock by category')['columns']]
           == ['text', 'decimal'], shape.table('Stock by category'))
    before = shape.values('Parts')
    renamed = sql(shape, "ALTER TABLE parts RENAME COLUMN reorder_level TO minimum_stock")
    expect('rename a column', 'Minimum stock' in titles('Parts') and 'Reorder level' not in titles('Parts'),
           titles('Parts'))
    expect('rename keeps the values', shape.values('Parts') == before)
    sql(shape, undo=renamed['undo'])
    expect('undo a rename', 'Reorder level' in titles('Parts'), titles('Parts'))
    shelved = sql(shape, "ALTER TABLE parts ADD COLUMN shelf TEXT", "UPDATE parts SET shelf = 'S1'",
                  "CREATE TABLE shelf_notes (note TEXT)", "INSERT INTO shelf_notes VALUES ('checked')")
    expect('a column, its values and a table in one call', 'Shelf' in titles('Parts')
           and shape.table('Shelf notes') is not None, shelved)
    sql(shape, undo=shelved['undo'])
    gone = shape.table('Shelf notes')
    expect('one undo takes back the column, its values and the table', 'Shelf' not in titles('Parts')
           and shape.values('Parts') == before and (gone is None or gone.get('archived')), (titles('Parts'), gone))
    sql(shape, "ALTER TABLE parts ADD COLUMN temp TEXT", "UPDATE parts SET temp = 'x'")
    sql(shape, "ALTER TABLE parts DROP COLUMN temp")
    bumped = sql(shape, "UPDATE parts SET stock = stock + 1 WHERE part = 'Hex nuts'")
    expect('rows update after a dropped column', bumped['changes'][0]['updated'] == 1, bumped)
    sql(shape, undo=bumped['undo'])
    sql(shape, "ALTER TABLE parts ADD COLUMN bin TEXT", "UPDATE parts SET bin = 'A1' WHERE part = 'Hex nuts'")
    binned = {r['part']: r.get('bin') for r in shape.values('Parts')}
    expect('add a column and fill it', 'Bin' in titles('Parts') and binned['Hex nuts'] == 'A1'
           and not binned['Brass bolts'], binned)
    sql(shape, "ALTER TABLE parts ADD COLUMN checked TEXT DEFAULT 'no'")
    expect('a default fills every row', {r.get('checked') for r in shape.values('Parts')} == {'no'},
           shape.values('Parts'))
    sql(shape, "ALTER TABLE parts DROP COLUMN bin")
    expect('remove a column', 'Bin' not in titles('Parts') and len(shape.values('Parts')) == 6, titles('Parts'))
    sql(shape, "ALTER TABLE reorder_levels RENAME TO minimum_levels")
    expect('rename a table', shape.table('Reorder levels') is None and len(shape.values('Minimum levels')) == 3)
    sql(shape, "DROP TABLE minimum_levels")
    expect('drop archives the table', shape.table('Minimum levels') is None)
    expect('drop left the other tables', len(shape.values('Parts')) == 6 and len(shape.values('Reorder plan')) == 3)

    # Saved tools: definitions of kind tool, granted on the Mac that saved them.
    def save(target, name, statements=(), inputs=(), description='A check fixture.', source=None):
        thing = {'kind': 'tool', 'name': name, 'description': description,
                 'inputs': [{'name': n, 'type': t} for n, t in inputs]}
        if source is None:
            thing['statements'] = list(statements)
        else:
            thing['source'] = source
        return target.run('tool', 'save', thing)

    def tools(target):
        return {t['name']: t for t in target.run('tools')}

    def unsaved(name, code, *args, **kwargs):
        before = tools(shape)
        try:
            expect(name, False, 'not refused: ' + str(save(shape, *args, **kwargs)))
        except CLIError as error:
            expect(name + ' code', error.code == code, error)
        expect(name + ' saved nothing', tools(shape) == before)

    saved = save(shape, 'low_stock', ["SELECT part FROM parts WHERE stock < reorder_level ORDER BY part"])
    expect('save a tool', saved.get('saved') == 'low_stock' and list(tools(shape)) == ['low_stock']
           and tools(shape)['low_stock']['enabled'] and shape.table('Saved tools') is None, saved)
    listed = shape.run('tool', 'low_stock')
    expect('run a tool by name', [r[0] for r in rows(listed)] == ['Hex key set', 'Hex nuts'], listed)
    expect('run a tool through sql', rows(sql(shape, tool='low_stock')) == rows(listed))
    save(shape, 'add_plan', ["INSERT INTO reorder_plan (item, level) VALUES (:item, :level)"],
         inputs=[('item', 'text'), ('level', 'number')])
    added = sql(shape, tool='add_plan', values={'item': "Wood screws; 'bulk'", 'level': '50'})
    expect('a tool changes rows', added['changes'][0]['inserted'] == 1 and
           ("Wood screws; 'bulk'", '50') in [(r['item'], r['level']) for r in shape.values('Reorder plan')], added)
    sql(shape, undo=added['undo'])
    expect('a tool run undoes', len(shape.values('Reorder plan')) == 3)
    resaved = save(shape, 'low_stock', ["SELECT part, stock FROM parts WHERE stock < reorder_level ORDER BY part"])
    expect('saving again makes a new version', tools(shape)['low_stock']['version'] == 2 and len(tools(shape)) == 2
           and rows(shape.run('tool', 'low_stock'))[0] == ['Hex key set', '0'], resaved)
    shape.run('tool', 'run', {'action': {'name': 'tool.undo', 'arguments': {'id': resaved['definitionID']}}})
    expect('Undo restores the earlier version', tools(shape)['low_stock']['version'] == 3
           and rows(shape.run('tool', 'low_stock')) == rows(listed) and tools(shape)['low_stock']['enabled'])
    # A script tool, and a script calling a SQL tool on its own copy.
    script = save(shape, 'count_below', inputs=[('limit', 'number')], source=(
        "const r = await sql('SELECT count(*) AS n FROM parts WHERE stock < :limit', {limit: inputs.limit});"
        " const low = await tool('low_stock', {}); return {below: r[0].n, low: low.length};"))
    ran = shape.run('tool', 'run', {'tool': 'count_below', 'values': {'limit': 5}})
    expect('a script tool runs with its inputs', script.get('language') == 'javascript'
           and ran.get('value') == {'below': 2, 'low': 2}, ran)
    unsaved('script with a syntax error', 'run', 'broken_script', source='return (;')
    # A copied workbook: its tools wait for this Mac's grant.
    copy = Path(shape.path).with_name('Copied.sevra')
    shutil.copytree(shape.path, copy)
    copied = Book.__new__(Book)
    copied.path = str(copy)
    expect('a copied tool is listed, not enabled', not tools(copied)['low_stock']['enabled'])
    try:
        expect('a copied tool does not run', False, str(copied.run('tool', 'low_stock')))
    except CLIError as error:
        expect('a copied tool is refused', error.code == 'tool_disabled', error)
    copied.run('tool-enable', 'low_stock')
    expect('an enabled copied tool runs', rows(copied.run('tool', 'low_stock')) == rows(listed))
    copied.run('tool-remove', 'low_stock')
    expect('a removed tool is gone', 'low_stock' not in tools(copied) and 'low_stock' in tools(shape))
    unsaved('tool name', 'tool_name', 'Low Stock', ["SELECT 1"])
    unsaved('tool statement refused', 'sql', 'reach_out', ["ATTACH DATABASE '/tmp/sevra-check-should-not-exist.db' AS o"])
    unsaved('tool with an unknown column', 'sql', 'broken', ["SELECT missing FROM parts"])
    unsaved('tool with an undeclared input', 'sql', 'loose', ["SELECT * FROM parts WHERE part = :part"])
    for name, code, arguments in [
            ('missing tool input', 'tool_inputs', {'tool': 'add_plan', 'values': {'item': 'Bolts'}}),
            ('text for a number input', 'tool_inputs', {'tool': 'add_plan', 'values': {'item': 'Bolts', 'level': 'many'}}),
            ('unknown tool input', 'tool_inputs', {'tool': 'low_stock', 'values': {'extra': 1}}),
            ('unknown tool', 'tool', {'tool': 'nothing_here'}),
            ('statements with a tool', 'arguments', {'tool': 'low_stock', 'statements': ['SELECT 1']}),
            ('an input outside a tool', 'sql', {'statements': ['SELECT * FROM parts WHERE part = :part']})]:
        before = shape.values('Reorder plan')
        try:
            expect(name, False, 'not refused: ' + str(shape.run('tool', 'sql', arguments)))
        except CLIError as error:
            expect(name + ' code', error.code == code, error)
        expect(name + ' changed nothing', shape.values('Reorder plan') == before)

    # A draft changes nothing.
    draft = sql(book, "UPDATE supplier_comparison SET unit_cost = 2.60 WHERE supplier = 'Cedar Tools'", draft=True)
    expect('draft is saved', draft.get('drafts', [{}])[0].get('draftRows') == 1, draft)
    expect('draft changes nothing', book.values(SUPPLIERS) == start)
    refused('draft of an insert', book, 'sql_draft',
            "INSERT INTO supplier_comparison(supplier) VALUES ('Elm Fasteners')", draft=True)

    # Refusals. Each leaves the workbook as it was.
    refused('index', book, 'sql_shape', "CREATE INDEX by_part ON parts(part)")
    refused('view', book, 'sql_shape', "CREATE VIEW cheap AS SELECT * FROM supplier_comparison")
    refused('trigger', book, 'sql_shape', "CREATE TRIGGER t AFTER INSERT ON parts BEGIN SELECT 1; END")
    refused('temporary table', book, 'sql_shape', "CREATE TEMP TABLE scratch(a)")
    refused('drop a catalog table', book, 'sql', "DROP TABLE tables")
    refused('alter a catalog table', book, 'sql', "ALTER TABLE columns ADD COLUMN extra TEXT")
    refused('draft of a shape change', book, 'sql_draft', "ALTER TABLE parts ADD COLUMN note TEXT", draft=True)
    refused('create then fail', book, 'sql', "CREATE TABLE extra(a)", "SELECT missing FROM extra")
    expect('a refused call created no table', book.table('Extra') is None)
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
    refused('a quoted name that is no column', book, 'sql', 'SELECT part FROM parts WHERE "stock number" < 5')
    refused('later failure undoes earlier statements', book, 'sql',
            "DELETE FROM supplier_comparison", "SELECT missing FROM parts")
    expect('no file was attached', not os.path.exists('/tmp/sevra-check-should-not-exist.db'))

    # A call saves everything or nothing, even when the saved table refuses its last step.
    atomic = Book(Path(folder) / 'atomic.sevra')
    parts(atomic)
    levels(atomic)
    table = atomic.table('Parts')
    atomic.run('tool', 'workspace_action', {'action': 'table.edit_schema', 'arguments': {
        'id': table['id'], 'expectedVersion': table['version'], 'expectedDefinitionID': table['definitionID'],
        'columns': [dict(c, required=True) if c['id'] == 'category' else c for c in table['columns']]}})
    held = atomic.values('Parts')
    try:
        sql(atomic, "CREATE TABLE side_table (a TEXT)", "INSERT INTO side_table VALUES ('x')",
            "ALTER TABLE reorder_levels ADD COLUMN flag TEXT",
            "UPDATE parts SET category = NULL WHERE part = 'Hex nuts'")
        expect('a refused last step fails the call', False)
    except CLIError as error:
        expect('a refused last step fails the call', error.code == 'required' and 'Nothing was changed' in str(error), error)
    side = atomic.table('Side table')
    expect('the earlier steps were taken back', (side is None or side.get('archived')) and atomic.values('Parts') == held
           and 'Flag' not in [c['title'] for c in atomic.table('Reorder levels')['columns']],
           (side, [c['title'] for c in atomic.table('Reorder levels')['columns']]))
    atomic.run('verify')

    # A large change is one saved edit with one Undo.
    bulk = Book(Path(folder) / 'bulk.sevra')
    sql(bulk, "CREATE TABLE stock_lines (sku TEXT, qty REAL)",
        "WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 300) "
        "INSERT INTO stock_lines SELECT 'SKU-' || i, i FROM n")
    raised = sql(bulk, "UPDATE stock_lines SET qty = qty + 1")
    expect('a bulk update', raised['changes'][0]['updated'] == 300
           and rows(sql(bulk, "SELECT sum(qty) FROM stock_lines")) == [['45450']], raised.get('changes'))
    sql(bulk, undo=raised['undo'])
    expect('a bulk undo', rows(sql(bulk, "SELECT sum(qty), count(*) FROM stock_lines")) == [['45150', '300']])
    bulk.run('verify')

print('\n'.join(failures) if failures else 'sql chat tool: passed')
sys.exit(1 if failures else 0)
