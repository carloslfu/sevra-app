"""Check packaged Swift extraction from app/CLI layouts with build reads denied."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--product', type=Path, default=ROOT / 'output/native')
args = parser.parse_args()
product = args.product.resolve(strict=True)
apps = list(product.glob('*.app'))
assert len(apps) == 1, apps
profile = '(version 1) (allow default) (deny file-read* (subpath ' + json.dumps(str(ROOT / '.build')) + '))'
with tempfile.TemporaryDirectory(prefix='sevra-extraction-package-') as directory:
    folder = Path(directory)
    plain = folder / 'Original.txt'
    plain.write_text('Package invoice 1042')
    office = folder / 'Original.docx'
    with zipfile.ZipFile(office, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('word/document.xml', '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>Package invoice 1042</w:t></w:r></w:p></w:body></w:document>')
    pdf = folder / 'Original.pdf'
    content = b'BT /F1 16 Tf 30 120 Td (Package invoice 1042) Tj ET'
    objects = [b'<< /Type /Catalog /Pages 2 0 R >>',
               b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
               b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 500 200] /Contents 5 0 R /Resources << /Font << /F1 4 0 R >> >> >>',
               b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
               b'<< /Length ' + str(len(content)).encode() + b' >>\nstream\n' + content + b'\nendstream']
    data = bytearray(b'%PDF-1.4\n'); offsets = [0]
    for index, obj in enumerate(objects, 1):
        offsets.append(len(data)); data.extend(f'{index} 0 obj\n'.encode() + obj + b'\nendobj\n')
    start = len(data)
    data.extend(b'xref\n0 6\n0000000000 65535 f \n')
    for offset in offsets[1:]: data.extend(f'{offset:010d} 00000 n \n'.encode())
    data.extend(f'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n{start}\n%%EOF\n'.encode())
    pdf.write_bytes(data)
    for helper in [product / 'bin/sevra-extract', apps[0] / 'Contents/MacOS/sevra-extract']:
        for source in [plain, office, pdf]:
            run = subprocess.run(['sandbox-exec', '-p', profile, str(helper), str(source)], capture_output=True, text=True, timeout=75)
            assert run.returncode == 0, run.stderr
            reply = json.loads(run.stdout)
            assert reply['version'] == 1 and 'error' not in reply and reply['result']['state'] == 'ready', reply
            assert any('Package invoice 1042' in c['text'] for c in reply['result']['chunks']), reply
        libraries = subprocess.check_output(['otool', '-L', str(helper)], text=True).lower()
        assert not any(name in libraries for name in ['python', 'mlx', 'slotstream'])
        print(json.dumps({'helper': str(helper.relative_to(product)), 'buildTreeDenied': True,
                          'textPDFDOCX': True, 'noPythonOrModelRuntime': True}), flush=True)
    cli = product / 'bin/sevra'
    workbook = folder / 'Intake.sevra'
    def command(*arguments):
        run = subprocess.run(['sandbox-exec', '-p', profile, str(cli), *map(str, arguments)], capture_output=True, text=True, timeout=75)
        assert run.returncode == 0, run.stdout + run.stderr
        value = json.loads(run.stdout); assert value['ok'], value
        return value['result']
    command('create', workbook)
    for source in [plain, office, pdf]:
        item = command('import', workbook, source)
        result = command('tool', workbook, 'read', json.dumps({'id': item['id']}))
        assert result['extraction']['state'] == 'ready', result
    assert command('verify', workbook)['ok']
    print(json.dumps({'packagedCLIIntake': True, 'originalsVerified': True}), flush=True)
