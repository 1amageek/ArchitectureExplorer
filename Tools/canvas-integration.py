#!/usr/bin/env python3
"""Real file -> daemon -> authenticated HTTP/MCP -> production Canvas engine."""
import http.client,json,os,select,signal,subprocess,tempfile
from pathlib import Path
from urllib.parse import urlsplit,quote
ROOT=Path(__file__).resolve().parents[1];CLI=ROOT/'.build/debug/architecture';WEB=ROOT/'Apps/ArchitectureExplorerWeb/.build/debug/architecture-web'
checks=[]
with tempfile.TemporaryDirectory(prefix='ae-canvas-') as temporary:
 workspace=Path(temporary);(workspace/'Example.swift').write_text('struct Example {}\n')
 subprocess.run([str(CLI),'daemon','start','--workspace',temporary],check=True,capture_output=True,timeout=30)
 web=subprocess.Popen([str(WEB),'--workspace',temporary,'--no-open'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 mcp=None
 try:
  assert select.select([web.stdout],[],[],30)[0],'Web startup timeout'
  line=web.stdout.readline();assert line,(web.poll(),web.stderr.read())
  launch=json.loads(line);parts=urlsplit(launch['url']);origin='http://'+parts.netloc
  def request(path,method='GET',data=None,headers=None):
   connection=http.client.HTTPConnection(parts.hostname,parts.port,timeout=8);connection.request(method,path,json.dumps(data) if data is not None else None,headers or {});response=connection.getresponse();body=response.read();status=response.status;fields=response.headers;connection.close();return status,fields,body
  status,headers,_=request('/session','POST',{'token':parts.fragment.split('=',1)[1]},{'Origin':origin,'Content-Type':'application/json'});assert status==200
  cookie=next(value.split(';')[0] for value in headers.get_all('Set-Cookie') if value.startswith('architecture-session-'))
  def read(method,params=None):
   status,_,body=request('/api?method='+method+'&params='+quote(json.dumps(params or {})),headers={'Cookie':cookie});assert status==200,(method,status,body);return json.loads(body)
  csrf=read('host.context')['csrf']
  def mutate(method,params=None,expect=200):
   status,_,body=request('/canvas','POST',{'method':method,'params':params or {}},{'Cookie':cookie,'Origin':origin,'Authorization':'Bearer '+csrf,'Content-Type':'application/json'});assert status==expect,(method,status,body);return json.loads(body)
  assert request('/canvas','POST',{'method':'canvas.open','params':{}})[0]==403
  assert request('/api?method=canvas.open',headers={'Cookie':cookie})[0]==400
  checks.append('Canvas mutation requires authenticated same-origin POST and cannot run through GET')
  documents=[];sessions=[]
  for file in sorted((ROOT/'Tests/ArchitectureTests/Fixtures/Canvas').iterdir()):
   result=mutate('canvas.open',{'name':file.name,'text':file.read_text()});documents.append(result['document']);sessions.append(result)
  assert len(documents)==22
  assert all(len(n['sourceDigest'])==64 for n in documents)
  assert next(n for n in documents if n['sourceName']=='architecture.json')['metadata']['architectureIR']['schemaVersion']=='1.0'
  assert set(n['format'] for n in documents)=={'json','dot','mmd','puml','graphml','scxml','xmi','svg'}
  assert set(n['kind'] for n in documents)=={'hierarchy','relations','controlFlow','dataFlow','stateTransition','sequence','proofDependencies'}
  checks.append('22 real files across all eight formats and seven diagram kinds open as shared sessions')
  fixture_file=workspace/'canvas-documents.json';fixture_file.write_text(json.dumps(documents))
  subprocess.run(['node','--test','--test-name-pattern','^real imported files',str(ROOT/'Tools/node-cards.test.cjs')],env={**os.environ,'AE_CANVAS_DOCUMENTS':str(fixture_file)},check=True,timeout=60)
  checks.append('Native parsed files use production Cytoscape/ELK with selectable nodes, original edges and theme-stable positions')
  selected=next(s for s in sessions if s['document']['sourceName']=='relations.json');sid=selected['viewSessionID']
  rejected=mutate('canvas.open',{'viewSessionID':sid,'name':'broken.dot','text':'digraph { invalid ->'},expect=400);assert rejected['error']['code']=='INVALID_CANVAS'
  assert read('canvas.get',{'viewSessionID':sid})==selected
  checks.append('Rejected file replacement preserves the complete previous session')
  mcp=subprocess.Popen([str(CLI),'mcp','--workspace',temporary],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
  def send(value):mcp.stdin.write(json.dumps(value)+'\n');mcp.stdin.flush()
  def receive():
   assert select.select([mcp.stdout],[],[],15)[0],'MCP timeout';line=mcp.stdout.readline();assert line,(mcp.poll(),mcp.stderr.read());return json.loads(line)
  send({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25'}});assert 'result' in receive()
  send({'jsonrpc':'2.0','method':'notifications/initialized'})
  send({'jsonrpc':'2.0','id':2,'method':'tools/list'});tools=receive()['result']['tools'];assert len(tools)==22
  assert next(t for t in tools if t['name']=='canvas_select')['annotations']['readOnlyHint'] is False
  def call(name,arguments):
   send({'jsonrpc':'2.0','id':3,'method':'tools/call','params':{'name':name,'arguments':arguments}});return receive()['result']
  result=call('canvas_select',{'viewSessionID':sid,'expectedRevision':1,'ids':['a']});assert result['isError'] is False,result
  state=read('canvas.get',{'viewSessionID':sid});assert state['state']['selection']==['a'] and state['revision']==2
  result=call('canvas_get',{'viewSessionID':sid,'collection':'state'});assert result['structuredContent']['state']['selection']==['a']
  assert 'geometry' not in result['structuredContent']['state']
  result=call('canvas_select',{'viewSessionID':sid,'expectedRevision':1,'ids':['b']});assert result['isError'] is True
  assert read('canvas.get',{'viewSessionID':sid})['state']['selection']==['a']
  result=call('canvas_get',{'viewSessionID':sid,'collection':'nodes','limit':1});payload=json.loads(result['content'][0]['text']);assert payload['items'][0]['id']=='a' and payload['truncated'] is True
  result=call('canvas_get',{'viewSessionID':sid,'collection':'nodes','limit':1,'cursor':payload['nextCursor']});payload=json.loads(result['content'][0]['text']);assert payload['items'][0]['id']=='b'
  checks.append('MCP and HTTP share selection/revision, reject stale writes, and page the same original nodes')
  for method,params in [('canvas.focus',{'ids':['b']}),('canvas.setFilter',{'filter':{'text':'Input'}}),('canvas.setLayout',{'layout':'grid'}),('canvas.setCamera',{'camera':{'zoom':1.2,'pan':{'x':30,'y':40}}})]:mutate(method,{'viewSessionID':sid,**params})
  current=read('canvas.get',{'viewSessionID':sid});assert current['state']['focus']==['b'] and current['state']['camera']['zoom']==1.2
  hierarchy=next(s for s in sessions if s['document']['kind']=='hierarchy' and s['document']['format']=='json')['viewSessionID']
  mutate('canvas.collapse',{'viewSessionID':hierarchy,'ids':['a']});assert read('canvas.get',{'viewSessionID':hierarchy})['state']['collapsed']==['a']
  mutate('canvas.expand',{'viewSessionID':hierarchy,'ids':['a']});assert read('canvas.get',{'viewSessionID':hierarchy})['state']['collapsed']==[]
  for session in sessions:
   exported=read('canvas.export',{'viewSessionID':session['viewSessionID'],'format':'json'});roundtrip=mutate('canvas.open',{'viewSessionID':session['viewSessionID'],'name':'roundtrip.json','text':exported['text']});assert len(roundtrip['document']['nodes'])==len(session['document']['nodes'])
  checks.append('Focus/filter/layout/camera/expand/collapse and JSON roundtrips retain imported data')
  mutate('canvas.close',{'viewSessionID':sid});status,_,body=request('/api?method=canvas.get&params='+quote(json.dumps({'viewSessionID':sid})),headers={'Cookie':cookie});assert status==400 and json.loads(body)['error']['code']=='VIEW_SESSION_NOT_FOUND'
  checks.append('Closed sessions fail explicitly')
 finally:
  if mcp:
   mcp.stdin.close()
   try:mcp.wait(timeout=10)
   except subprocess.TimeoutExpired:mcp.kill();mcp.wait();raise
  web.send_signal(signal.SIGTERM)
  try:web.wait(timeout=10)
  except subprocess.TimeoutExpired:web.kill();web.wait();raise
  subprocess.run([str(CLI),'daemon','stop','--workspace',temporary],capture_output=True,timeout=10)
print(json.dumps({'checks':checks,'passed':len(checks)},indent=2))
