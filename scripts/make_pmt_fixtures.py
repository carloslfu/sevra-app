#!/usr/bin/env python3
"""Generate synthetic PMT references with LibreOffice; never use Sevra to calculate expectations."""
from pathlib import Path
import sys,subprocess,zipfile,xml.etree.ElementTree as E,json
sys.path.insert(0,'scripts')
from make_formula_fixtures import FIELDS,sheet
import tempfile,shutil
workspace=tempfile.TemporaryDirectory(prefix='sevra-pmt-originals-')
root=Path(workspace.name)
out=Path('integration/fixtures/excel-pmt');out.mkdir(parents=True,exist_ok=True)
cases=[('ordinary',.01,12,10000,0,0),('due',.01,12,10000,0,1),('future',.01,12,10000,500,0),('fraction',.01,12.5,10000,500,1),('negative periods',.01,-12,10000,0,0),('negative rate',-.01,12,10000,0,0),('rate minus one',-1,12,10000,0,0),('rate minus one due',-1,12,10000,0,1),('lower rate',-2,12,10000,0,0),('lower rate odd',-2,11,10000,0,0),('zero both',0,0,10000,0,0),('zero periods',.01,0,10000,0,0),('negative type',.01,12,10000,0,-1),('type two',.01,12,10000,0,2),('half type',.01,12,10000,0,.5),('half cent',0,1,1.005,0,0),('negative half',0,1,-1.005,0,0),('tiny rate',1e-12,12,10000,0,0),('huge periods',.01,1e8,10000,0,0),('negative period low rate',-.01,-12,10000,0,0),('blank rate',None,12,10000,0,0),('blank principal invalid rate','invalid',12,None,0,0),('partial rate','0.01abc',12,10000,0,0),('blank periods',.01,None,10000,0,0)]
rows=[['Case','Rate','Periods','Principal','Future value','Type','Payment','Rounded payment']]
for i,c in enumerate(cases,2):rows.append([*c,f'=PMT([.B{i}];[.C{i}];[.D{i}];[.E{i}];[.F{i}])',f'=ROUND(-[.G{i}];2)'])
p=root/'pmt.fods';p.write_text(f'<?xml version="1.0" encoding="UTF-8"?><office:document {FIELDS} office:version="1.3" office:mimetype="application/vnd.oasis.opendocument.spreadsheet"><office:body><office:spreadsheet>{sheet("Payments",rows)}</office:spreadsheet></office:body></office:document>')
subprocess.run(['/Applications/LibreOffice.app/Contents/MacOS/soffice',f'-env:UserInstallation={root.as_uri()}/profile','--headless','--convert-to','xlsx','--outdir',str(root),str(p)],check=True,capture_output=True,timeout=60)
ns={'x':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
with zipfile.ZipFile(root/'pmt.xlsx') as z:
 doc=E.fromstring(z.read('xl/worksheets/sheet1.xml'))
 cells={c.attrib['r']:c.findtext('x:v',namespaces=ns) for c in doc.findall('.//x:c',ns)}
 result=[{'name':c[0],'arguments':c[1:],'payment':cells.get(f'G{i}'),'roundedNegated':cells.get(f'H{i}')} for i,c in enumerate(cases,2)]
(root/'results.json').write_text(json.dumps(result,indent=2)+'\n')
for name in ['pmt.xlsx','results.json']: shutil.copyfile(root/name,out/name)
workspace.cleanup()
print(f'Saved {len(result)} independently recalculated payment cases.')
