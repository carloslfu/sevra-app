#!/usr/bin/env python3
"""Record actual independent conditional-sum answers, including engine differences."""
import json
import pathlib
from recalculate_excel_fixtures import recalculate
from verify_excel_business_oracles import cells

root = pathlib.Path('integration/fixtures/excel-conditional')
recalculate([pathlib.Path('.build/excel-business/conditional-originals/criteria.xlsx')], root)
manifest = json.loads((root / 'cases.json').read_text())
values = cells(root / 'criteria.xlsx')[0]
manifest['expected'] = [values['E' + str(index + 1)] for index in range(len(manifest['formulas']))]
(root / 'cases.json').write_text(json.dumps(manifest, indent=2) + '\n')
