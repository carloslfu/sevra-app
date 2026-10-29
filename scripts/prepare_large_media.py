"""Create a fully allocated >2 GiB WAV and linked/included workbook fixtures.

Development tooling for native UI qualification. Creates only in a new output
folder, invokes the packaged CLI, and records identities. Does not drive the UI
or claim that playback, cancellation or memory qualification passed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', type=Path, default=ROOT / 'output/native/bin/sevra')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    cli = args.cli.resolve(strict=True)
    output = (args.output or ROOT / f'.build/large-media-ui-{time.time_ns()}').resolve()
    output.mkdir(parents=True, exist_ok=False)
    source = output / 'Large audio.wav'
    book = output / 'Large media.sevra'
    size = 2_148_532_224
    payload = size - 44
    rate, channels, bits = 48_000, 2, 16
    header = (b'RIFF' + struct.pack('<I', size - 8) + b'WAVEfmt '
              + struct.pack('<IHHIIHH', 16, 1, channels, rate, rate * 4, 4, bits)
              + b'data' + struct.pack('<I', payload))
    assert len(header) == 44 and payload % 4 == 0
    started = time.monotonic()
    result = {'prepared': False, 'fileBytes': size, 'durationSeconds': payload / (rate * 4),
              'cliSHA256': hashlib.sha256(cli.read_bytes()).hexdigest(),
              'preparerSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'sourceCommit': subprocess.check_output(
                  ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'source': str(source), 'workbook': str(book),
              'limits': 'Synthetic silent PCM audio. UI and memory checks must run separately.'}

    def run(*arguments):
        command = subprocess.run([str(cli), *map(str, arguments)],
                                 capture_output=True, text=True)
        if command.returncode:
            raise RuntimeError(command.stderr or command.stdout)
        return json.loads(command.stdout)

    try:
        digest = hashlib.sha256()
        with source.open('xb') as file:
            file.write(header)
            digest.update(header)
            block = bytes(1_048_576)
            remaining = payload
            while remaining:
                part = block[:min(remaining, len(block))]
                file.write(part)
                digest.update(part)
                remaining -= len(part)
            file.flush()
            os.fsync(file.fileno())
        result['sourceSHA256'] = digest.hexdigest()
        result['allocatedBytes'] = source.stat().st_blocks * 512
        assert source.stat().st_size == size and result['allocatedBytes'] >= size
        result['created'] = run('create', book, 'Large media check')
        result['linked'] = run('import', book, source, '--link')
        # This extra input name shares the synthetic source inode. The included
        # workbook asset is an independently streamed copy, not a hard link.
        included_source = output / 'Included audio.wav'
        os.link(source, included_source)
        result['included'] = run('import', book, included_source)
        result['verification'] = run('verify', book)
        assert result['verification']['ok'] and result['verification']['result']['ok']
        result['prepared'] = True
    except Exception as error:
        result['error'] = str(error)
        raise
    finally:
        result['preparationSeconds'] = time.monotonic() - started
        (output / 'fixture.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps({'output': str(output), **result}), flush=True)


if __name__ == '__main__':
    main()
