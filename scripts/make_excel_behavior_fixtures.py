#!/usr/bin/env python3
"""Synthetic reconstruction fixtures. LibreOffice, independently of Sevra/JS, saves expected results.
Reuses the repository's existing FODS fixture writer. Original VBA is inert and never executed.
"""
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile
from make_formula_fixtures import FIELDS, sheet

OUT = Path('integration/fixtures/excel-behavior')


def compressed(data):
    # MS-OVBA literal-only compressed chunk; small synthetic modules need no copy tokens.
    body = b''.join(b'\0' + data[i:i+8] for i in range(0, len(data), 8))
    assert 0 < len(body) <= 4096
    return b'\1' + struct.pack('<H', 0xB000 | (len(body) - 1)) + body


def vba_project(source):
    def record(kind, data=b''):
        return struct.pack('<HI', kind, len(data)) + data
    directory = record(3, struct.pack('<H', 1252)) + record(15, struct.pack('<H', 1))
    directory += record(19, b'\0\0') + record(25, b'Business')
    directory += record(26, b'Business') + record(50, 'Business'.encode('utf-16-le'))
    directory += record(49, b'\0'*4) + record(33) + record(43)
    streams = [compressed(directory), compressed(source.encode('cp1252'))]
    mini, allocations, firsts = bytearray(), [], []
    for data in streams:
        first = len(allocations)
        firsts.append(first)
        count = (len(data) + 63) // 64
        mini += data.ljust(count*64, b'\0')
        allocations += list(range(first+1, first+count)) + [0xFFFFFFFE]
    mini_size = len(mini)
    mini = mini.ljust(((len(mini)+511)//512)*512, b'\0')
    mini_sectors = len(mini)//512
    def entry(name, kind, child, first, size, right=0xFFFFFFFF):
        b = bytearray(128)
        encoded = (name+'\0').encode('utf-16-le')
        b[:len(encoded)] = encoded
        struct.pack_into('<HBBIII', b, 64, len(encoded), kind, 1, 0xFFFFFFFF, right, child)
        struct.pack_into('<IQ', b, 116, first, size)
        return b
    entries = entry('Root Entry',5,1,2,mini_size)
    entries += entry('VBA',1,2,0xFFFFFFFE,0)
    entries += entry('dir',2,0xFFFFFFFF,firsts[0],len(streams[0]),right=3)
    entries += entry('Business',2,0xFFFFFFFF,firsts[1],len(streams[1]))
    # Sectors: 0 directory, 1 miniFAT, 2... root mini stream, last FAT.
    fat_sector = 2 + mini_sectors
    fat = [0xFFFFFFFE, 0xFFFFFFFE] + list(range(3, fat_sector)) + [0xFFFFFFFE, 0xFFFFFFFD]
    header = bytearray(512)
    header[:8] = bytes.fromhex('d0cf11e0a1b11ae1')
    struct.pack_into('<HHHHH',header,24,0x003E,3,0xFFFE,9,6)
    struct.pack_into('<IIIIIIIII',header,40,0,1,0,0,4096,1,1,0xFFFFFFFE,0)
    struct.pack_into('<109I',header,76,fat_sector,*([0xFFFFFFFF]*108))
    return bytes(header+entries+struct.pack('<128I',*(allocations+[0xFFFFFFFF]*(128-len(allocations))))
                 +mini+struct.pack('<128I',*(fat+[0xFFFFFFFF]*(128-len(fat)))))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # Every rate, limit and reference value remains an original input cell.
    cases = [
        ('Inventory', ['Item','On hand','Reorder at','To order'], ['Bolts',8,12],
         '=MAX([.C2]-[.B2];0)', 'Math.max(c-b,0)', [6,20,0]),
        ('Invoices', ['Invoice','Subtotal','Tax rate','Total'], ['INV-001',19.95,0.19],
         '=ROUND([.B2]*(1+[.C2]);2)', 'Math.round(b*(1+c)*100)/100', [0,40.25,100]),
        ('Timesheets', ['Person','Hours','Hourly rate','Pay'], ['Alex',8,15.5],
         '=[.B2]*[.C2]', 'b*c', [0,3.5,40]),
        ('Cash flow', ['Month','Income','Expense','Net'], ['November',100,150],
         '=[.B2]-[.C2]', 'b-c', [0,250,75]),
        ('Commission', ['Seller','Revenue','Commission rate','Commission'], ['Sam',2000,0.075],
         '=ROUND([.B2]*[.C2];2)', 'Math.round(b*c*100)/100', [0,1357.2,10000]),
        ('Loan', ['Loan','Principal','Monthly rate','Payment','Months'], ['Equipment',10000,0.01],
         '=ROUND(-PMT([.C2];[.E2];[.B2]);2)', 'Math.round((c===0?b/Number(v["sheet1!E2"]):b*c/(1-Math.pow(1+c,-Number(v["sheet1!E2"]))))*100)/100', [0,20000,1234]),
        ('Production', ['Batch','Good units','Total units','Yield'], ['Batch-A',80,100],
         '=IFERROR([.B2]/[.C2];0)', 'c===0?0:b/c', [0,90,100]),
        ('Lookup quotes', ['Quote','SKU','Quantity','Total','Notes','SKU lookup','Unit price'], ['Quote-A','B',3],
         '=VLOOKUP([.B2];[.$F$2:.$G$3];2;0)*[.C2]', '(()=>{const key=v["sheet1!B2"].toLowerCase();let price;if(key===v["sheet1!F2"].toLowerCase())price=Number(v["sheet1!G2"]);else if(key===v["sheet1!F3"].toLowerCase())price=Number(v["sheet1!G3"]);else return "#N/A";return Number.isFinite(price)&&Number.isFinite(c)?price*c:"#VALUE!"})()', ['A','B','A']),
        ('Due dates', ['Invoice','Invoice date','Terms in days','Due date'], ['INV-D','2024-02-27',1],
         '=TEXT(DATEVALUE([.B2])+[.C2];"YYYY-MM-DD")',
         '(()=>{let [y,m,d]=v["sheet1!B2"].split("-").map(Number),n=Math.trunc(c);const days=()=>[31,(y%4===0&&(y%100!==0||y%400===0)?29:28),31,30,31,30,31,31,30,31,30,31][m-1];while(n>0){d++;if(d>days()){d=1;m++;if(m>12){m=1;y++;}}n--;}while(n<0){d--;if(d<1){m--;if(m<1){m=12;y--;}d=days();}n++;}return String(y).padStart(4,"0")+"-"+String(m).padStart(2,"0")+"-"+String(d).padStart(2,"0")})()',
         ['2024-02-28','2024-12-31','2026-11-13']),
        ('Reference codes', ['Order','Customer prefix','Sequence','Reference'], ['Order-A','acme',42],
         '=UPPER([.B2])&"-"&TEXT([.C2];"0000")',
         'v["sheet1!B2"].toUpperCase()+"-"+String(Math.trunc(c)).padStart(4,"0")', ['north','a b','café']),
    ]
    selected = set(sys.argv[1:])
    manifest = json.loads((OUT/'cases.json').read_text()) if selected and (OUT/'cases.json').exists() else []
    manifest = [c for c in manifest if c['name'] not in selected]
    with tempfile.TemporaryDirectory(prefix='sevra-behavior-reference-') as tmp:
        root = Path(tmp)
        for name, headers, inputs, formula, expression, changed in cases:
            if selected and name not in selected: continue
            files = []
            values = [inputs[1], *changed, *([inputs[1]] if name == 'Loan' else ['new','B'] if name == 'Lookup quotes' else [])]
            for index, value in enumerate(values):
                row = [inputs[0], value, inputs[2], formula]
                rows = [headers, row]
                if name == 'Loan':
                    row.append(12)
                    if index == 4: row[2] = 0
                if name == 'Lookup quotes':
                    row.extend([None,'A',12.5]); rows.append([None,None,None,None,None,'B',20])
                    if index == 4: row[2], row[5] = 2, 'NEW'
                    if index == 5: row[2] = 'invalid'
                title = name.replace(' ', '-').lower() + f'-{index}'
                fods = root / (title+'.fods')
                fods.write_text(f'<?xml version="1.0" encoding="UTF-8"?><office:document {FIELDS} office:version="1.3" office:mimetype="application/vnd.oasis.opendocument.spreadsheet"><office:body><office:spreadsheet>{sheet(name, rows)}</office:spreadsheet></office:body></office:document>')
                subprocess.run(['/Applications/LibreOffice.app/Contents/MacOS/soffice', f'-env:UserInstallation={root.as_uri()}/profile', '--headless', '--convert-to','xlsx','--outdir',str(root),str(fods)],check=True,capture_output=True,timeout=60)
                target = OUT/(title+'.xlsx')
                shutil.copyfile(root/(title+'.xlsx'), target)
                files.append(target.name)
            source = f'function recreate(input){{const v=input.cells,b=Number(v["sheet1!B2"]),c=Number(v["sheet1!C2"]);return {{"sheet1!D2":String({expression})}};}}'
            behavior = {'source':source,'outputs':['sheet1!D2'],'actions':[],'gaps':[]}
            if name == 'Inventory':
                behavior['source'] = source.replace('return {"sheet1!D2"', 'if(input.event==="ship"){const q=Number(input.arguments.quantity);if(!Number.isFinite(q)||q<=0||q>b)throw Error("Enter an available quantity");return {"sheet1!B2":String(b-q)};}return {"sheet1!D2"')
                behavior['actions'] = [{'id':'ship','title':'Ship stock','writes':['sheet1!B2'],'inputs':[{'id':'quantity','title':'Quantity'}]}]
                macro = 'Attribute VB_Name = "Business"\r\nSub ShipStock()\r\n  Dim quantity As Double\r\n  quantity = CDbl(InputBox("Quantity"))\r\n  If quantity <= 0 Or quantity > Range("B2").Value Then Err.Raise 5\r\n  Range("B2").Value = Range("B2").Value - quantity\r\nEnd Sub\r\n'
                binary = vba_project(macro)
                (OUT/'business-vba.bin').write_bytes(binary)
                for old in list(files):
                    target = OUT/old.replace('.xlsx','.xlsm')
                    with zipfile.ZipFile(OUT/old) as original, zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as result:
                        for entry in original.infolist():
                            body = original.read(entry)
                            if entry.filename == '[Content_Types].xml':
                                body = body.replace(b'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml',b'application/vnd.ms-excel.sheet.macroEnabled.main+xml').replace(b'</Types>',b'<Override PartName="/xl/vbaProject.bin" ContentType="application/vnd.ms-office.vbaProject"/></Types>')
                            if entry.filename == 'xl/_rels/workbook.xml.rels':
                                body = body.replace(b'</Relationships>',b'<Relationship Id="businessVBA" Type="http://schemas.microsoft.com/office/2006/relationships/vbaProject" Target="vbaProject.bin"/></Relationships>')
                            result.writestr(entry,body)
                        result.writestr('xl/vbaProject.bin',binary)
                    (OUT/old).unlink()
                files = [name.replace('.xlsx','.xlsm') for name in files]
            manifest.append({'name':name,'files':files,'behavior':behavior,'changedInputs':changed,'inputColumn':'c2'})
    (OUT/'cases.json').write_text(json.dumps(manifest,indent=2)+'\n')
    hashes = {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(OUT.glob('*.xls*'))}
    (OUT/'hashes.json').write_text(json.dumps(hashes,indent=2)+'\n')
    print(f'Saved {len(hashes)} independently calculated reference workbooks for {len(cases)} business workflows.')


if __name__ == '__main__': main()
