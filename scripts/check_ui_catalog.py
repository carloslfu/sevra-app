"""Cheap drift checks; execution/visual evidence comes from the packaged catalog."""
import json, pathlib, re, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
app = ROOT / 'output/ui-catalog/Sevra UI Catalog.app'
manifest = json.loads(subprocess.check_output([str(app / 'Contents/MacOS/Catalog'), '--list'], text=True))
stories = manifest['stories']
assert len({s['id'] for s in stories}) == len(stories)
for story in stories:
    assert (ROOT / story['source']).exists(), story['source']
    assert story['variants'][0] == 'Default' and len(set(story['variants'])) == len(story['variants'])
    assert story['actions'] and story['readiness'] and story['exclusions']
    assert story['evidence'] == 'registered'
source = (ROOT / 'Sources/SevraApp/WorkspaceState.swift').read_text()
routes = set(re.findall(r'case (\w+)', source.split('enum Route: Equatable {')[1].split('\n  }')[0]))
expected = {'space','item','table','tableUpdate','excelImport','search','reviews','activity','automations','automation','workflow','tools','removed'}
assert routes == expected, f'Review changed routes: {routes ^ expected}'
assert {'main.table-update','main.excel','main.workflow-detail','main.automation-detail','main.column-editor','main.references','main.history-search'} <= {s['id'] for s in stories}
# Catalog startup, fixture sources and dependencies must not ship in ordinary builds.
package = (ROOT / 'Package.swift').read_text()
assert 'exclude: uiCatalog ? [] : ["Catalog"]' in package
assert 'SEVRA_UI_CATALOG' in package
assert '#if !SEVRA_UI_CATALOG' in (ROOT / 'Sources/SevraApp/SevraApp.swift').read_text()
print(f'PASS {len(stories)} registered stories, source references, route inventory, metadata and compile boundary')
def run(flag, expected):
    process=subprocess.Popen([str(app / 'Contents/MacOS/Catalog'),flag],stdout=subprocess.PIPE,text=True)
    last=''
    for line in process.stdout:
        print(line,end='',flush=True)
        last=line.rstrip()
    assert process.wait() == 0, 'Catalog process failed'
    assert last == f'CATALOG_DONE {expected}', 'Catalog process ended before completing coverage'
if '--fixtures' in sys.argv:
    run('--validate-fixtures', len(stories))
if '--interactions' in sys.argv:
    run('--check',12)
if '--flows' in sys.argv:
    run('--check-flows',len([s for s in stories if s['group']=='Compositions']))
