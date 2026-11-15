#!/usr/bin/env python3
"""Retain independently recalculated SUMPRODUCT answers without altering differences."""
import json
from pathlib import Path
from recalculate_excel_fixtures import recalculate
from verify_excel_business_oracles import cells

root = Path('integration/fixtures/excel-product')
recalculate([Path('.build/excel-business/product-originals/products.xlsx')], root)
manifest = json.loads((root / 'cases.json').read_text())
values = cells(root / 'products.xlsx')[0]
manifest['expected'] = [values['E' + str(i + 1)] for i in range(len(manifest['formulas']))]
(root / 'cases.json').write_text(json.dumps(manifest, indent=2) + '\n')
