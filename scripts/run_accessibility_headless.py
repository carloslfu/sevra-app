"""Run only the windowless accessibility decision/storage checks under a no-UI sandbox."""
import argparse
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--binary', default='.build/native-product/release/sevra-accessibility-headless-checks')
args = parser.parse_args()
binary = (root / args.binary).resolve()
if binary.name != 'sevra-accessibility-headless-checks' or not binary.is_file():
    parser.error('Build the dedicated sevra-accessibility-headless-checks executable first.')
fixtures = root / '.build/accessibility-headless'
fixtures.mkdir(parents=True, exist_ok=True)
# Foundation atomic writes use an item-replacement directory, not TMPDIR.
foundation_temp = Path(subprocess.check_output(['/usr/bin/getconf', 'DARWIN_USER_TEMP_DIR'], text=True).strip()).resolve() / 'TemporaryItems'
foundation_pattern = '^' + re.escape(str(foundation_temp)) + '/NSIRD_sevra-accessibility-headless-checks_[^/]+(/|$)'
result = subprocess.run([
    '/usr/bin/sandbox-exec', '-D', f'FIXTURE_ROOT={fixtures}', '-D', f'CHECK_BINARY={binary}',
    '-D', f'FOUNDATION_TEMP_PATTERN={foundation_pattern}',
    '-D', f'FOUNDATION_TEMP_ROOT={foundation_temp}',
    '-f', str(root / 'IntegrationTests/AccessibilityHeadless/NoUI.sb'), str(binary),
], cwd=root, capture_output=True, text=True)
print(result.stdout, end='')
print(result.stderr, end='')
raise SystemExit(result.returncode)
