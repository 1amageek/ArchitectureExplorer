#!/usr/bin/env python3
"""Bound Swift test processes and reject synchronous waiting in deinitializers."""
import argparse,fcntl,os,re,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def check(paths):
 failures=[]
 for base in paths:
  path=Path(base);files=path.rglob('*.swift') if path.is_dir() else [path]
  for file in files:
   source=file.read_text()
   for start in re.finditer(r'\bdeinit\s*\{',source):
    depth=1;end=start.end()
    while end<len(source) and depth:
     depth+=(source[end]=='{')-(source[end]=='}');end+=1
    body=source[start.end():end]
    if re.search(r'\b(syncShutdownGracefully|waitUntilExit)\s*\(|\b(semaphore|group)\s*\.\s*wait\s*\(',body):failures.append(str(file))
 if failures:raise SystemExit('Synchronous deinit shutdown: '+', '.join(failures))
 print('No synchronous shutdown waits in deinitializers.',flush=True)
def run(seconds,args):
 if not 1<=seconds<=120:raise SystemExit('Test deadline must be in 1...120 seconds.')
 code=subprocess.run([sys.executable,str(ROOT/'Tools/run.py'),str(seconds),'swift','test',*args],cwd=ROOT).returncode
 if code:
  directory=ROOT/'.test-artifacts/hang-guard'/str(time.time_ns());directory.mkdir(parents=True)
  lines=subprocess.check_output(['ps','-axo','pid=,stat=,command='],text=True).splitlines()
  owned=[line for line in lines if str(ROOT) in line or 'swiftpm-testing-helper' in line]
  (directory/'failure.diag.txt').write_text('\n'.join(owned)+'\n'+repr((ROOT/'.build/.lock').exists())+'\n')
 return code
def helpers():
 return {line.strip() for line in subprocess.check_output(['ps','-axo','pid=,command='],text=True).splitlines() if 'swiftpm-testing-helper' in line and str(ROOT) in line}
mode=sys.argv[1];rest=sys.argv[2:]
if mode=='check':check(rest or [str(ROOT/'Sources'),str(ROOT/'Tests')]);raise SystemExit(0)
artifacts=ROOT/'.test-artifacts';artifacts.mkdir(exist_ok=True)
with (artifacts/'hang-guard.lock').open('w') as lock:
 try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 except BlockingIOError:raise SystemExit(3)
 if mode=='run':
  seconds=int(rest.pop(0));rest=rest[1:] if rest[:1]==['--'] else rest;raise SystemExit(run(seconds,rest))
 parser=argparse.ArgumentParser();parser.add_argument('--repeats',type=int,default=3);parser.add_argument('--timeout',type=int,default=30);parser.add_argument('--build-timeout',type=int,default=120);options,args=parser.parse_known_args(rest)
 args=args[1:] if args[:1]==['--'] else args
 if options.repeats<1:raise SystemExit('At least one run is required.')
 check([str(ROOT/'Sources/ArchitectureFrontend/Semantic'),str(ROOT/'Tests')]);before=helpers()
 # The first execution includes build and fresh child-process initialization.
 for index in range(options.repeats):
  command=args if index==0 else ['--skip-build',*args]
  code=run(options.build_timeout if index==0 else options.timeout,command)
  if code:raise SystemExit(code)
  leaked=helpers()-before
  if leaked:raise SystemExit('Stale test helpers: '+repr(leaked))
 print(f'OK: {options.repeats} bounded runs without timeout or stale helper.')
