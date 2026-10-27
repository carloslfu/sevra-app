"""Real >2 GiB linked-file verification with a fixed process-memory ceiling.

Development-only runner. Uses the same Darwin lifetime-peak measurement as the
inference harness, but runs no inference and makes no rendering/latency claim.
"""
import argparse
import json
from pathlib import Path
import platform
import subprocess
import time

from compare_splash_performance import ROOT, footprint, line, save, sha


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--binary', type=Path, default=ROOT / '.build/debug/sevra-preview-checks')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    binary = args.binary.resolve(strict=True)
    output = (args.output or ROOT / f'.build/large-preview-{time.time_ns()}').resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {
        'binarySHA256': sha(binary),
        'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'machine': platform.machine(), 'os': platform.platform(),
        'sources': {path: sha(ROOT / path) for path in (
            'IntegrationTests/Preview/Checks.swift', 'IntegrationTests/Preview/LargeAssetCheck.swift',
            'Sources/SevraCore/Assets.swift', 'Sources/SevraPreviewUI/AssetPreviewSession.swift',
            'scripts/check_large_preview.py')},
        'maximumLifetimeFootprintBytes': 256 * 1024 * 1024,
        'passed': False,
    }
    process = None
    started = time.monotonic()
    try:
        with (output / 'stderr.log').open('w') as errors:
            process = subprocess.Popen(
                [str(binary), '--large-asset', str(output / 'fixture')],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors,
            )
            result = line(process, timeout=180)
            (output / 'stdout.jsonl').write_text(json.dumps(result) + '\n')
            report['result'] = result
            usage = footprint(process.pid)
            report['memory'] = usage
            assert result['passed'] and int(result['assetBytes']) > 2**31, result
            assert int(result['fullyVerifiedBytes']) == int(result['assetBytes']), result
            assert int(result['cancelledAfterBytes']) == 8_388_608, result
            assert result['changedOriginalRefused'] and result['workbookUnchanged'], result
            assert 0 < usage['bytes'] <= usage['lifetimePeakBytes'] <= report['maximumLifetimeFootprintBytes'], usage
            process.stdin.write(b'finish\n')
            process.stdin.flush()
            remaining, _ = process.communicate(timeout=20)
            report['returncode'] = process.returncode
            assert process.returncode == 0 and not remaining.strip(), remaining
            report['passed'] = True
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait(timeout=20)
        report['fixtureAndVerificationSeconds'] = time.monotonic() - started
        save(output / 'result.json', report)
        print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
