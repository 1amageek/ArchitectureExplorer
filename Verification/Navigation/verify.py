#!/usr/bin/env python3
"""Check destination commitment and stale reply isolation over three generations."""
import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--toolchain', required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent
tools = args.toolchain.resolve(strict=True)
for name in ['Safe', 'StaleControl']:
    with tempfile.TemporaryDirectory(prefix='explorer-navigation-') as scratch:
        command = [str(tools / 'java/Contents/Home/bin/java'), '-Xmx256m', '-cp', str(tools / 'tla2tools.jar'),
                   'tlc2.TLC', '-workers', '1', '-metadir', scratch, '-config', str(root / (name + '.cfg')), str(root / 'Navigation.tla')]
        result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=45)
        output = result.stdout + result.stderr
        (root / (name + '.log')).write_text(output)
        if name == 'Safe':
            assert result.returncode == 0 and '0 states left on queue.' in output, output
        else:
            assert result.returncode != 0 and 'Invariant CurrentResultOnly is violated' in output, output
        print(name + ': ' + str(result.returncode))
print('Destination commitment and stale-reply control checked.')
