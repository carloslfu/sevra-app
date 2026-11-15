#!/usr/bin/env python3
"""Independent cache recalculation and inert VBA packaging after artifact authoring.

Artifact-tool does not author VBA projects. This narrow OOXML packaging step
reuses the tested fixture CFB writer; no original macro is executed.
"""
import json
import pathlib
import zipfile
from make_excel_behavior_fixtures import vba_project
from recalculate_excel_fixtures import recalculate


def main():
    raw = pathlib.Path('.build/excel-business/originals')
    out = pathlib.Path('integration/fixtures/excel-business')
    recalculate(sorted(raw.glob('*.xlsx')), out)
    macro = vba_project((out / 'CompleteRun.bas').read_text())
    for original in sorted(out.glob('production-*.xlsx')):
        with zipfile.ZipFile(original) as archive:
            parts = {name: archive.read(name) for name in archive.namelist()}
        content = parts['[Content_Types].xml'].decode().replace(
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml',
            'application/vnd.ms-excel.sheet.macroEnabled.main+xml')
        content = content.replace('</Types>', '<Override PartName="/xl/vbaProject.bin" ContentType="application/vnd.ms-office.vbaProject"/></Types>')
        parts['[Content_Types].xml'] = content.encode()
        relationships = parts['xl/_rels/workbook.xml.rels'].decode().replace(
            '</Relationships>', '<Relationship Id="sevraSyntheticVBA" Type="http://schemas.microsoft.com/office/2006/relationships/vbaProject" Target="vbaProject.bin"/></Relationships>')
        parts['xl/_rels/workbook.xml.rels'] = relationships.encode()
        parts['xl/vbaProject.bin'] = macro
        with zipfile.ZipFile(original.with_suffix('.xlsm'), 'w', zipfile.ZIP_DEFLATED) as archive:
            for name, data in parts.items():
                archive.writestr(name, data)
        original.unlink()
    manifest = json.loads((out / 'cases.json').read_text())
    for case in manifest:
        if case['slug'] == 'production':
            case['files'] = [str(pathlib.Path(file).with_suffix('.xlsm')) for file in case['files']]
    (out / 'cases.json').write_text(json.dumps(manifest, indent=2) + '\n')


if __name__ == '__main__':
    main()
