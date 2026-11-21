#!/usr/bin/python3
"""Real stdio provider fixture for framing, backpressure and process lifecycle tests."""
import json,os,signal,sys,time
from pathlib import Path
mode_file=Path('provider-mode')
mode=mode_file.read_text().strip() if mode_file.exists() else 'echo'
if mode=='stubborn':signal.signal(signal.SIGTERM,signal.SIG_IGN)
if mode=='closed':os.close(0)
Path('provider.pid.tmp').write_text(str(os.getpid()))
Path('provider.pid.tmp').replace('provider.pid')
if mode in ('blocked','stubborn','closed'):time.sleep(90);raise SystemExit(0)
notifications=0
while True:
 length=None
 while True:
  line=sys.stdin.buffer.readline()
  if not line:raise SystemExit(0)
  if line==b'\r\n':break
  if line.lower().startswith(b'content-length:'):length=int(line.split(b':',1)[1])
 if length is None:raise SystemExit(2)
 message=json.loads(sys.stdin.buffer.read(length))
 method=message.get('method')
 if method=='exit':raise SystemExit(0)
 if 'id' not in message:notifications+=1;continue
 if method=='initialize':result={'capabilities':{'definitionProvider':True,'positionEncoding':'utf-16'},'serverInfo':{'name':'fixture','version':'1'}}
 elif method=='shutdown':result=None
 else:
  params=message.get('params') or {};result={'token':params.get('token'),'size':len(params.get('text','')),'notifications':notifications}
 payload=json.dumps({'jsonrpc':'2.0','id':message['id'],'result':result}).encode()
 sys.stdout.buffer.write(b'Content-Length: '+str(len(payload)).encode()+b'\r\n\r\n'+payload);sys.stdout.buffer.flush()
 if mode=='afterInitialize' and method=='initialize':
  Path('provider.blocked').write_text('initialized')
  time.sleep(90);raise SystemExit(0)
