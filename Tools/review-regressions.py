#!/usr/bin/env python3
"""Exercise reviewed failure sequences through compiled CLI, daemon, MCP and real pipes."""
import contextlib,http.client,json,os,select,shutil,signal,socket,subprocess,tempfile,time,uuid
from urllib.parse import urlsplit,quote
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];CLI=ROOT/'.build/debug/architecture';checks=[]
def command(workspace,*args,code=0,timeout=10):
 result=subprocess.run([str(CLI),*args,'--workspace',str(workspace)],capture_output=True,text=True,timeout=timeout)
 assert result.returncode==code,(args,result.returncode,result.stderr)
 return json.loads(result.stdout) if code==0 else result

def alive(pid):
 try:os.kill(pid,0);return True
 except ProcessLookupError:return False

def exited(pid,timeout=8):
 deadline=time.monotonic()+timeout
 while alive(pid) and time.monotonic()<deadline:time.sleep(.02)
 assert not alive(pid),f'Owned process {pid} did not exit'

@contextlib.contextmanager
def workspace(source):
 with tempfile.TemporaryDirectory(prefix='ae-regression-') as directory:
  root=Path(directory);(root/'Flow.swift').write_text(source);initial=command(root,'index');hello=command(root,'daemon','status');pid=hello['pid']
  try:yield root,initial,hello
  finally:
   try:
    if alive(pid):command(root,'daemon','stop',timeout=8)
    exited(pid)
   finally:
    if alive(pid):os.kill(pid,signal.SIGKILL)
    provider=root/'provider.pid'
    if provider.exists():
     child=int(provider.read_text())
     if alive(child):os.kill(child,signal.SIGKILL)

def rpc(root,hello,method,params):
 wid=hello['workspaceID'];address=f'/tmp/ae-{os.getuid()}-{wid[-24:]}/rpc.sock'
 with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as connection:
  connection.settimeout(8);connection.connect(address);connection.sendall(json.dumps({'jsonrpc':'2.0','id':'regression','method':method,'params':params,'workspaceID':wid,'protocolVersion':'1.0'}).encode()+b'\n')
  with connection.makefile('rb') as stream:response=json.loads(stream.readline(4*1024*1024+1))
 assert response['error']['data']['code'] in ['SESSION_EXPIRED','AUTHENTICATION_REQUIRED'],response
 web=ROOT/'Apps/ArchitectureExplorerWeb/.build/debug/architecture-web'
 process=subprocess.Popen([str(web),'--workspace',str(root),'--no-open'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 try:
  assert select.select([process.stdout],[],[],20)[0],'Host startup deadline exceeded'
  parts=urlsplit(json.loads(process.stdout.readline())['url']);origin='http://'+parts.netloc
  connection=http.client.HTTPConnection(parts.hostname,parts.port,timeout=8)
  connection.request('POST','/session',json.dumps({'token':parts.fragment.split('=',1)[1]}),{'Origin':origin,'Content-Type':'application/json'})
  response=connection.getresponse();response.read();assert response.status==200
  cookie=response.headers['Set-Cookie'].split(';')[0];connection.close()
  connection=http.client.HTTPConnection(parts.hostname,parts.port,timeout=8)
  connection.request('GET','/api?method='+method+'&params='+quote(json.dumps(params)),headers={'Cookie':cookie,'Origin':origin})
  response=connection.getresponse();value=json.loads(response.read());connection.close();assert response.status==200,value
  return value
 finally:
  process.terminate();process.wait(timeout=8)

source='func loop(_ a: Bool, _ b: Bool) { while a, b { continue }; return }\nfunc target() -> Int { return 1 }\n'
with workspace(source) as (root,initial,hello):
 hits=command(root,'graph','--level','function');functions={n['name']:n for n in hits['nodes'] if n['kind']=='function'}
 cfg=command(root,'cfg','--symbol',functions['loop']['id']);names={n['name'] for n in cfg['nodes']}
 assert {'a','b','continue'}<=names and cfg['completeness']=='completeWithinScope'
 checks.append('CLI CFG retains every while condition')
 original=command(root,'cfg','--symbol',functions['target']['id']);old=original['snapshotID']
 (root/'Flow.swift').write_text(source.replace('return 1','return 2'));command(root,'index')
 historical=command(root,'cfg','--symbol',functions['target']['id'],'--snapshot',old)
 assert historical['snapshotID']==old and any(n['name']=='return 1' for n in historical['nodes'])
 missing=command(root,'cfg','--symbol',functions['target']['id'],'--snapshot',initial['snapshotID'],code=3)
 assert 'CFG_UNAVAILABLE' in missing.stderr
 checks.append('CLI pinned CFG preserves historical bytes and rejects missing recorded CFG')
 process=subprocess.Popen([str(CLI),'mcp','--workspace',str(root)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 try:
  def send(value):process.stdin.write(json.dumps(value)+'\n');process.stdin.flush()
  def receive():
   assert select.select([process.stdout],[],[],8)[0],'MCP deadline exceeded'
   return json.loads(process.stdout.readline())
  send({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25'}});assert receive()['result']['protocolVersion']=='2025-11-25'
  send({'jsonrpc':'2.0','method':'notifications/initialized'})
  send({'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':'architecture_cfg','arguments':{'focus':functions['target']['id'],'snapshotID':old}}})
  response=receive()['result'];assert not response['isError'] and response['structuredContent']['snapshotID']==old
  process.stdin.close();assert process.wait(timeout=8)==0
 finally:
  if process.poll() is None:process.kill();process.wait(timeout=5)
 checks.append('real MCP CFG preserves a pinned snapshot')
 before=command(root,'status')
 entities=[{'id':name,'kind':'function','language':'swift','name':name,'identityKey':'review:'+name,'entityRevision':'1','attributes':{}} for name in ['A','B']]
 imported={'schemaVersion':'1.0','id':'review-import-'+str(uuid.uuid4()),'workspaceID':initial['workspaceID'],'generation':1000000,'contextDigest':'fixture','inputs':{},'entities':entities,'facts':[{'id':'AB','producer':'fixture','scope':'fixture','kind':'calls','source':'A','target':'B','revision':'1','evidenceIDs':[],'attributes':{}}],'evidence':[],'coverage':[],'diagnostics':[],'createdAt':'2026-11-17'}
 file=root/'import.json';file.write_text(json.dumps(imported));result=command(root,'index','--input',str(file));assert result['snapshotID']==imported['id']
 assert command(root,'status')['snapshotID']==before['snapshotID']
 (root/'Flow.swift').write_text(source.replace('return 1','return 3'));command(root,'index');assert command(root,'status')['publishedRevision']<1000000
 assert command(root,'graph','--level','function','--snapshot',imported['id'])['snapshotID']==imported['id']
 checks.append('CLI import preserves pinned IR without poisoning subsequent live generations')
 reverse=rpc(root,hello,'graph.path',{'snapshotID':imported['id'],'focus':'B','target':'A','direction':'incoming','depth':1});assert {n['id'] for n in reverse['nodes']}=={'A','B'}
 checks.append('daemon incoming path reverses the recorded edge')
 overview=rpc(root,hello,'graph.overview',{'snapshotID':imported['id'],'level':'function'});assert len(overview['edges'])==1 and overview['edges'][0]['attributes']['aggregate.count']==1
 checks.append('daemon overview represents a direct fact exactly once')
 command(root,'cfg','--symbol',functions['target']['id']);(root/'Flow.swift').unlink();command(root,'index')
 assert not command(root,'search','--query','target')['nodes']
 checks.append('deleting a source after CFG removes its callable from live search')

large='//'+('x'*(1024*1024))+'\nfunc sample() -> Int { return 1 }\n'
def provider(root):
 executable=root/'provider.py';shutil.copy2(ROOT/'Tests/ArchitectureTests/Fixtures/lsp-provider.py',executable);executable.chmod(0o700);(root/'provider-mode').write_text('afterInitialize');return executable
with workspace(large) as (root,initial,hello):
 executable=provider(root);symbol=next(n['id'] for n in command(root,'search','--query','sample')['nodes'] if n['kind']=='function');start=time.monotonic()
 failure=command(root,'semantic','--entity',symbol,'--provider',str(executable),'--operation','definition','--trusted-workspace',code=6,timeout=24)
 assert 'Language provider operation timed out' in failure.stderr and 'Socket read timed out' not in failure.stderr
 assert time.monotonic()-start<23;exited(int((root/'provider.pid').read_text()))
 checks.append('real provider backpressure ends at its send deadline and reaps the child')
with workspace(large) as (root,initial,hello):
 executable=provider(root);symbol=next(n['id'] for n in command(root,'search','--query','sample')['nodes'] if n['kind']=='function')
 process=subprocess.Popen([str(CLI),'semantic','--workspace',str(root),'--entity',symbol,'--provider',str(executable),'--operation','definition','--trusted-workspace'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 try:
  deadline=time.monotonic()+5
  while not (root/'provider.blocked').exists():
   assert time.monotonic()<deadline,'Provider initialization timed out';time.sleep(.01)
  time.sleep(.1);start=time.monotonic();command(root,'daemon','stop',timeout=5);exited(hello['pid']);exited(int((root/'provider.pid').read_text()))
  process.communicate(timeout=8);assert process.returncode!=0 and time.monotonic()-start<8
 finally:
  if process.poll() is None:process.kill();process.wait(timeout=5)
 checks.append('daemon stop during a blocked provider write exits and reaps owned processes')
report={'checks':checks,'passed':len(checks)};(ROOT/'Documentation/review-regression-results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
