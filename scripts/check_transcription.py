#!/usr/bin/env python3
"""Real on-device transcription on the packaged CLI. Speech on both sides of a long pause survives
with its real times, and a repeat replaces the transcript. It needs the Mac's speech model, so it
runs in scripts/check.sh and not in hosted CI."""
import argparse
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile
import wave

BEFORE = (
    'Maria confirmed the copper pipe order for the harbor office on Monday. '
    'The cedar boards from the river depot arrived late and Oscar updated the invoice.'
)
AFTER = (
    'Daniel asked whether the main store could hold the olive oil until Friday. '
    'We agreed that Helen will call the supplier about the damaged bottles.'
)
PAUSE_SECONDS = 8


def speak(text, path):
    subprocess.run(
        ['say', '-r', '165', '-o', str(path), '--file-format=WAVE',
         '--data-format=LEI16@22050', text],
        check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', required=True)
    cli = parser.parse_args().cli

    def call(*args):
        run = subprocess.run([cli, *args], capture_output=True, text=True)
        assert run.returncode == 0, run.stdout + run.stderr
        return json.loads(run.stdout)['result']

    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        speak(BEFORE, root / 'before.wav')
        speak(AFTER, root / 'after.wav')
        recording = root / 'Pause.wav'
        with wave.open(str(root / 'before.wav')) as first, wave.open(str(root / 'after.wav')) as last:
            with wave.open(str(recording), 'wb') as out:
                out.setparams(first.getparams())
                out.writeframes(first.readframes(first.getnframes()))
                pause_end = first.getnframes() / first.getframerate() + PAUSE_SECONDS
                out.writeframes(b'\0\0' * (PAUSE_SECONDS * first.getframerate()))
                out.writeframes(last.readframes(last.getnframes()))

        book = root / 'Speech.sevra'
        call('create', str(book), 'Speech')
        report = call('import', str(book), str(recording), '--role', 'reference')
        item = report['intake']['report']['index']['item_id']

        def transcript():
            with sqlite3.connect(f'file:{book}/workbook.sqlite?mode=ro', uri=True) as db:
                return db.execute(
                    "SELECT body, locator FROM chunks WHERE item_id=? AND locator LIKE 'time=%' "
                    'ORDER BY id', (item,)).fetchall()

        call('transcribe', str(book), item)
        chunks = transcript()
        heard = ' '.join(body for body, _ in chunks).lower()
        for word in ('copper', 'invoice', 'olive', 'bottles'):
            assert word in heard, f'{word} was lost: {heard}'
        print('PASS: speech on both sides of a long pause survives')
        times = [float(re.match(r'time=([0-9.]+)', locator).group(1)) for _, locator in chunks]
        ends = [float(re.search(r'end=([0-9.]+)', locator).group(1)) for _, locator in chunks]
        assert times[0] < 1 and times == sorted(times), times
        assert ends[-1] > pause_end, (ends, pause_end)
        print('PASS: words keep their real times across the pause')
        assert call('search', str(book), 'olive')['hits'], 'the transcript is not searchable'
        call('transcribe', str(book), item)
        assert transcript() == chunks, 'a repeat changed the transcript'
        assert call('verify', str(book))['ok']
        print('PASS: a repeat replaces the transcript and the workbook verifies')


if __name__ == '__main__':
    main()
