#!/usr/bin/env python3
"""Copy the shared offline renderer into the Web package and verify pinned vendors."""
import hashlib,json,shutil
from pathlib import Path
root=Path(__file__).resolve().parents[1];source=root/'Sources/ArchitectureGraph/Resources';target=root/'Apps/ArchitectureExplorerWeb/Sources/ArchitectureWeb/Assets'
for entry in json.loads((root/'dependency-lock.json').read_text())['assets']:
 assert hashlib.sha256((source/entry['file']).read_bytes()).hexdigest()==entry['sha256'],entry['file']
for path in source.iterdir():shutil.copy2(path,target/path.name)
print('Shared renderer assets synchronized; vendor hashes match.')
