#!/usr/bin/env python3
"""Force independent calculation; opening/exporting an XLSX can retain stale caches."""
import os
import pathlib
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

NS = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'


def recalculate(files, destination):
    files = list(map(pathlib.Path, files))
    if not files or len({file.stem for file in files}) != len(files):
        raise ValueError('Use nonempty inputs with distinct output names.')
    destination = pathlib.Path(destination).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    office = os.environ.get('SEVRA_SOFFICE', '/Applications/LibreOffice.app/Contents/MacOS/soffice')
    with tempfile.TemporaryDirectory(prefix='sevra-recalculation-') as temporary:
        root = pathlib.Path(temporary)
        inputs = root / 'inputs'
        inputs.mkdir()
        outputs = root / 'outputs'
        outputs.mkdir()
        for file in files:
            file = pathlib.Path(file)
            with zipfile.ZipFile(file) as archive:
                parts = {name: archive.read(name) for name in archive.namelist()}
            for name, data in list(parts.items()):
                if name.startswith('xl/worksheets/sheet') and name.endswith('.xml'):
                    sheet = ET.fromstring(data)
                    for cell in sheet.iter('{' + NS + '}c'):
                        if cell.find('{' + NS + '}f') is not None:
                            for value in list(cell):
                                if value.tag in ('{' + NS + '}v', '{' + NS + '}is'):
                                    cell.remove(value)
                            cell.attrib.pop('t', None)
                    parts[name] = ET.tostring(sheet, encoding='utf-8', xml_declaration=True)
            workbook = ET.fromstring(parts['xl/workbook.xml'])
            calc = workbook.find('{' + NS + '}calcPr')
            if calc is None:
                calc = ET.SubElement(workbook, '{' + NS + '}calcPr')
            calc.attrib.update(calcId='0', fullCalcOnLoad='1', forceFullCalc='1', calcMode='auto')
            parts['xl/workbook.xml'] = ET.tostring(workbook, encoding='utf-8', xml_declaration=True)
            with zipfile.ZipFile(inputs / file.name, 'w', zipfile.ZIP_DEFLATED) as archive:
                for name, data in parts.items():
                    archive.writestr(name, data)
        subprocess.run([office, '-env:UserInstallation=' + (root / 'profile').as_uri(),
                        '--headless', '--convert-to', 'xlsx', '--outdir', str(outputs),
                        *map(str, sorted(inputs.iterdir()))], check=True, timeout=180)
        for file in files:
            output = outputs / (file.stem + '.xlsx')
            if not output.is_file():
                raise RuntimeError('Recalculation did not produce ' + str(file))
            with zipfile.ZipFile(output) as archive:
                for name in archive.namelist():
                    if name.startswith('xl/worksheets/sheet') and name.endswith('.xml'):
                        for cell in ET.fromstring(archive.read(name)).iter('{' + NS + '}c'):
                            if cell.find('{' + NS + '}f') is not None and cell.find('{' + NS + '}v') is None:
                                raise RuntimeError('Missing independently calculated value: ' + cell.get('r', ''))
            shutil.copyfile(output, destination / output.name)


if __name__ == '__main__':
    import sys
    recalculate(sys.argv[2:], sys.argv[1])
