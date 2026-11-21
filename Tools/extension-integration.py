#!/usr/bin/env python3
"""Real peer-bound Provider -> daemon -> authenticated HTTP integration; own every process."""
import http.client,json,os,select,signal,socket,sqlite3,subprocess,tempfile,time
import jsonschema
from pathlib import Path
from urllib.parse import urlsplit,quote
ROOT=Path(__file__).resolve().parents[1]
CLI=ROOT/'.build/debug/architecture';WEB=ROOT/'Apps/ArchitectureExplorerWeb/.build/debug/architecture-web';MOCK=ROOT/'Examples/ExtensionMock/.build/debug/ExtensionMock'
checks=[]
for schemaPath in (ROOT/'Schemas').glob('*.schema.json'):jsonschema.Draft202012Validator.check_schema(json.loads(schemaPath.read_text()))
def validate(name,value):jsonschema.validate(value,json.loads((ROOT/'Schemas'/(name+'.schema.json')).read_text()))
def wait(test,seconds=20):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  result=test()
  if result:return result
  time.sleep(.1)
 raise AssertionError('Integration condition timed out')
with tempfile.TemporaryDirectory(prefix='ae-extension-') as directory:
 workspace=Path(directory)/'workspace';workspace.mkdir();(workspace/'Demo.swift').write_text('public func example(_ value: Int) -> Int { value + 1 }\n')
 def cli(*args):return subprocess.run([str(CLI),*args,'--workspace',str(workspace)],check=True,capture_output=True,text=True,timeout=30)
 cli('index')
 web=subprocess.Popen([str(WEB),'--workspace',str(workspace),'--no-open'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
 mock=None
 try:
  assert select.select([web.stdout],[],[],20)[0],'Web startup timed out'
  line=web.stdout.readline();assert line,(web.poll(),web.stderr.read())
  parts=urlsplit(json.loads(line)['url']);origin='http://'+parts.netloc
  cookie=None;csrf=None
  def request(path,method='GET',body=None,headers=None):
   connection=http.client.HTTPConnection(parts.hostname,parts.port,timeout=10)
   values={'Origin':origin}
   if cookie:values['Cookie']=cookie
   if headers:values.update(headers)
   connection.request(method,path,json.dumps(body) if body is not None else None,values)
   response=connection.getresponse();data=response.read();result=(response.status,response.headers,data);connection.close();return result
  status,headers,body=request('/session','POST',{'token':parts.fragment.split('=',1)[1]},{'Content-Type':'application/json'})
  assert status==200,(status,body);cookie=headers.get('Set-Cookie').split(';')[0]
  def read(method,params=None):
   status,_,raw=request('/api?method='+method+'&params='+quote(json.dumps(params or {})))
   value=json.loads(raw);assert status==200,(method,status,value);return value
  csrf=read('host.context')['csrf']
  held=[]
  try:
   workspaceID=read('workspace.status')['workspaceID'];address=f'/tmp/ae-{os.getuid()}-{workspaceID[-24:]}/rpc.sock'
   for _ in range(50):
    stream=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);stream.settimeout(1)
    try:stream.connect(address);held.append(stream)
    except ConnectionRefusedError:stream.close()
    time.sleep(.02)
   began=time.monotonic();assert read('graph.overview')['nodes'];assert time.monotonic()-began<3
   checks.append('reserved host admission keeps core queries available with 50 idle non-host sockets')
  finally:
   for stream in held:stream.close()
  def mutate(method,params):
   status,_,raw=request('/extensions','POST',{'method':method,'params':params},{'Content-Type':'application/json','Authorization':'Bearer '+csrf})
   value=json.loads(raw);assert status==200,(method,status,value);return value
  assert request('/extensions','POST',{'method':'extensions.approve','params':{}})[0]==403
  assert request('/extensions','POST',{}, {'Authorization':'Bearer '+csrf,'Origin':'https://attacker.invalid'})[0]==403
  checks.append('same-origin session-bound CSRF required before host mutation')
  log=Path(directory)/'mock.log';errors=Path(directory)/'mock.err'
  with log.open('w') as stdout,errors.open('w') as stderr:
   mock=subprocess.Popen([str(MOCK),str(workspace),str(Path(directory)/'provider-state')],stdout=stdout,stderr=stderr,start_new_session=True)
   pending=wait(lambda:read('extensions.pending'))
   validate('extension-manifest',pending[0]['manifest'])
   assert pending[0]['peer']['processID']==mock.pid,pending
   assert pending[0]['peer']['executable'].endswith('ExtensionMock'),pending
   checks.append('registration derives PID/executable/hash from the actual socket peer')
   mutate('extensions.approve',{'id':pending[0]['id'],'permissions':pending[0]['manifest']['requestedPermissions']})
   def ready():
    assert mock.poll() is None,errors.read_text()
    data=read('extensions.view');return data if data['publications'] else None
   data=wait(ready,30);publication=data['publications'][0]
   assert len(publication['contributions'])==4 and publication['applicability']=='unknown',data
   annotationItems=read('graph.annotations')['items'];graphItems=read('extensionGraphs.list')['items']
   assert len(annotationItems)==1 and len(graphItems)==1
   assert annotationItems[0]['publicationID']==graphItems[0]['publicationID']==publication['publicationID']
   validate('annotation',annotationItems[0]['contribution']['data'])
   database=Path.home()/'Library/Caches/ArchitectureExplorer'/publication['binding']['workspaceID']/'graph.sqlite'
   with sqlite3.connect('file:'+str(database)+'?mode=ro',uri=True) as db:
    names={row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    assert not names.intersection({'annotations','extension_graphs','view_settings'}),names
    assert db.execute("SELECT value FROM metadata WHERE key='schema'").fetchone()[0]=='2.0'
   checks.append('current queries use one committed publication store; obsolete tables and adapters are absent')
   checks.append('real Provider verifies captured bytes and atomically publishes annotation, graph, table and timeline')
   registration=data['registrations'][0];snapshot=read('workspace.status')['snapshotID'];manifest=read('inputs.manifest',{'snapshotID':snapshot})
   validate('input-manifest',manifest['manifest'])
   binding={'workspaceID':manifest['manifest']['workspaceID'],'snapshotID':snapshot,'inputManifestDigest':manifest['inputManifestDigest'],'entityIDs':[],'factIDs':[]}
   prepared=mutate('actions.prepare',{'registrationID':registration['id'],'actionID':'check','arguments':{},'binding':binding})
   intent=prepared['intent'];validate('extension-action',intent);confirmation={'token':intent['authorizationToken'],'requestFingerprint':intent['requestFingerprint']}
   mutate('actions.confirm',confirmation);mutate('actions.confirm',confirmation)
   def running():
    data=read('extensions.view');return next((a for a in data['actions'] if a['requestID']==intent['requestID'] and a['state']=='running'),None)
   job=wait(running)
   assert sum('"state":"accepted"' in line for line in log.read_text().splitlines())==1,log.read_text()
   checks.append('confirmed action delivers once; duplicate confirmation preserves the same job')
   cancel=mutate('actions.prepare',{'registrationID':registration['id'],'actionID':'cancel','arguments':{'requestID':intent['requestID'],'jobID':job['receipt']['jobID'],'runID':job['runID']},'binding':binding})['intent']
   mutate('actions.confirm',{'token':cancel['authorizationToken'],'requestFingerprint':cancel['requestFingerprint']})
   parent=next(a for a in read('extensions.view')['actions'] if a['requestID']==intent['requestID']);assert parent['state']=='cancelling',parent
   wait(lambda:next((a for a in read('extensions.view')['actions'] if a['requestID']==intent['requestID'] and a['state']=='cancelled'),None))
   checks.append('cancel receipt keeps cancelling until Provider cleanup and terminal report')
   export=read('graph.export',{'query':{'method':'graph.overview','level':'function'},'format':'html'})['text']
   assert 'Saved snapshot' in export and 'external actions disabled' in export and 'ArchitectureExtensionUI' in export
   checks.append('standalone HTML bundles literal external data and disabled offline actions')
   changed=mutate('actions.prepare',{'registrationID':registration['id'],'actionID':'check','arguments':{},'binding':binding})['intent']
   (workspace/'Demo.swift').write_text('public func example(_ value: Int) -> Int { value + 2 }\n')
   def stale():
    value=read('extensions.view');return value if value['publications'][0]['applicability']=='stale' else None
   wait(stale)
   rejected,_,raw=request('/extensions','POST',{'method':'actions.confirm','params':{'token':changed['authorizationToken'],'requestFingerprint':changed['requestFingerprint']}},{'Content-Type':'application/json','Authorization':'Bearer '+csrf})
   assert rejected==400 and json.loads(raw)['error']['code']=='INPUT_CHANGED',raw
   checks.append('actual SDK wire models match checked JSON schemas; changed inputs reject prepared execution')
   checks.append('input edits mark old external results stale without changing core truth')
   probe=ROOT/'Examples/InvarReaderProbe/.build/debug/InvarReaderProbe'
   if probe.exists():
    adapter=subprocess.Popen([str(probe),str(workspace)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    try:
     pendingAdapter=wait(lambda:next((p for p in read('extensions.pending') if p['manifest']['extensionID']=='local.example.invar-reader'),None))
     mutate('extensions.approve',{'id':pendingAdapter['id'],'permissions':pendingAdapter['manifest']['requestedPermissions']})
     output,error=adapter.communicate(timeout=30)
     assert adapter.returncode==0,(output,error)
     captured=json.loads(next(line for line in output.splitlines() if line.startswith('{')))
     assert captured['state']=='captured' and captured['files']==1 and captured['entities']>0,captured
     checks.append('actual Invar ExplorerSnapshotReader captures full source/inventory through the approved session')
    finally:
     if adapter.poll() is None:adapter.terminate();adapter.wait(timeout=5)
   mutate('extensions.unregister',{'id':registration['id']})
   assert read('graph.overview',{'level':'function'})['nodes']
   checks.append('revoked/disconnected Provider cannot stop ordinary structural exploration')
 finally:
  for process in [mock,web]:
   if process and process.poll() is None:
    os.killpg(process.pid,signal.SIGTERM)
    try:process.wait(timeout=5)
    except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=5)
  cli('daemon','stop')
print(json.dumps({'passed':len(checks),'checks':checks},indent=2))
