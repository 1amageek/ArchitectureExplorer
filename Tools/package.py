#!/usr/bin/env python3
"""Assemble a local, unsigned portable bundle; never sign, publish or deploy."""
import argparse,shutil,subprocess,sys,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--configuration',choices=['debug','release'],default='debug');args=parser.parse_args()
subprocess.run([sys.executable,str(root/'Tools/build.py'),'--configuration',args.configuration],check=True)
destination=root/'Dist';destination.mkdir(exist_ok=True);output=destination/'ArchitectureExplorer'
with tempfile.TemporaryDirectory(prefix='.architecture-package-',dir=destination) as directory:
 staged=Path(directory)/'ArchitectureExplorer';staged.mkdir();binary=staged/'bin';binary.mkdir()
 for package,name in [(root,'architecture'),(root/'Apps/ArchitectureExplorerWeb','architecture-web')]:
  source=package/'.build'/args.configuration
  shutil.copy2(source/name,binary/name)
  for resource in source.iterdir():
   if resource.name.endswith(('.bundle','.resources')) and not resource.name.startswith('ArchitectureExplorer_ArchitectureTests.'):
    target=binary/resource.name
    if not target.exists():shutil.copytree(resource,target)
 shutil.copytree(root/'Schemas',staged/'Schemas')
 shutil.copytree(root/'Sources/ArchitectureGraph/Resources',staged/'LicensesAndAssets')
 shutil.copy2(root/'Apps/ArchitectureExplorerWeb/Sources/ArchitectureHTTPHost/Runtime/UPSTREAM-LICENSE',staged/'LicensesAndAssets/SwiftWeb-MIT')
 for name in ('README.md','toolchain.lock.json','dependency-lock.json'):
  shutil.copy2(root/name,staged/name)
 previous=Path(directory)/'previous'
 if output.exists():output.rename(previous)
 try:staged.rename(output)
 except BaseException:
  if previous.exists():previous.rename(output)
  raise
print(output)
