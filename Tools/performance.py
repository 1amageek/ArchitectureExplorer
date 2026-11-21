#!/usr/bin/env python3
"""Measure real daemon progress, API/CLI queries and complete saved-file updates."""
import concurrent.futures,json,os,platform,socket,statistics,subprocess,tempfile,time,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];CLI=Path(os.environ.get('AE_PERF_CLI',str(ROOT/'.build/debug/architecture')))
def command(workspace,*args):
 start=time.perf_counter();p=subprocess.run([str(CLI),*args,'--workspace',str(workspace)],capture_output=True,text=True,timeout=180)
 assert p.returncode==0,p.stderr
 return json.loads(p.stdout),time.perf_counter()-start,len(p.stdout.encode())
def summary(values):
 ordered=sorted(values);return {'count':len(values),'p50Milliseconds':statistics.median(values)*1000,'p95Milliseconds':ordered[min(len(ordered)-1,int(len(ordered)*.95))]*1000}
with tempfile.TemporaryDirectory(prefix='ae-medium-') as directory:
 workspace=Path(directory)
 for index in range(1000):
  methods='\n'.join(f'    func operation{number}() -> Int {{\n        return {number}\n    }}\n' for number in range(10))
  (workspace/f'Component{index:04}.swift').write_text(f'struct Component{index} {{\n'+methods+'\n'*58+'}\n')
 try:
  cold_start=time.perf_counter();hello,ready_time,_=command(directory,'daemon','start');wid=hello['workspaceID'];socket_path=f'/tmp/ae-{os.getuid()}-{wid[-24:]}/rpc.sock'
  def rpc(method,params=None):
   start=time.perf_counter();connection=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);connection.settimeout(30);connection.connect(socket_path)
   request={'jsonrpc':'2.0','id':str(uuid.uuid4()),'method':method,'params':params or {},'workspaceID':wid,'protocolVersion':'1.0'}
   connection.sendall(json.dumps(request).encode()+bytes([10]));stream=connection.makefile('rb');raw=stream.readline(4*1024*1024+1);stream.close();connection.close();response=json.loads(raw)
   assert 'error' not in response,response
   return response['result'],time.perf_counter()-start,len(raw)
  heartbeats=[];peak_workers=0
  with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
   initial=pool.submit(command,directory,'index')
   while not initial.done():
    status,elapsed,_=rpc('workspace.status');heartbeats.append(elapsed);peak_workers=max(peak_workers,status.get('runningWorkers',0));time.sleep(.25)
   cold,_,_=initial.result()
  cold_time=time.perf_counter()-cold_start
  api_times=[];cli_times=[];sizes=[]
  for _ in range(20):
   _,elapsed,size=rpc('graph.overview',{'level':'function','limit':100});api_times.append(elapsed);sizes.append(size)
   _,elapsed,_=command(directory,'graph','--level','function','--limit','100');cli_times.append(elapsed)
  updates=[];source=workspace/'Component0000.swift'
  for index in range(10):
   previous=rpc('workspace.status')[0]['snapshotID'];started=time.perf_counter();source.write_text(source.read_text().replace('return '+str(index),'return '+str(index+1),1))
   while True:
    status,_,_=rpc('workspace.status')
    if status['snapshotID']!=previous:break
    assert time.perf_counter()-started<30
    time.sleep(.05)
   updates.append(time.perf_counter()-started)
  memory=subprocess.check_output(['ps','-o','rss=','-p',str(hello['pid'])],text=True).strip()
  report={'host':{'os':platform.platform(),'architecture':platform.machine(),'memoryBytes':int(subprocess.check_output(['sysctl','-n','hw.memsize'],text=True)),'swift':'6.4.1'},'fixture':{'files':1000,'linesPerFile':101,'entities':cold['entityCount'],'edges':cold['edgeCount']},'conditions':{'build':'release' if '/release/' in str(CLI) else 'debug','cold':'fresh workspace/cache; daemon launch and normal 250 ms progress observation included','warm':'same daemon, exact-byte hashing, 250 ms reconciliation and SQLite FULL publication enabled','query':'100 visible function nodes via Unix API; CLI query timings reported separately','updates':'saved bytes to normal published snapshot; input scans/parse/validation/commit included; 50 ms status observation','memory':'one ps RSS observation after all cycles, not a peak or GPU allocation'},'daemonReadyMilliseconds':ready_time*1000,'indexingStatusLatency':summary(heartbeats),'maximumScheduledWorkersObserved':peak_workers,'coldIndexMilliseconds':cold_time*1000,'warmQuery':summary(api_times),'cliQuery':summary(cli_times),'savedFileUpdate':summary(updates),'maximumQueryResponseBytes':max(sizes),'finalDaemonRSSKiB':int(memory),'targets':{'queryP95Within200ms':summary(api_times)['p95Milliseconds']<=200,'updateP95Within1000ms':summary(updates)['p95Milliseconds']<=1000}}
  (ROOT/'Documentation/performance-results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
 finally:subprocess.run([str(CLI),'daemon','stop','--workspace',directory],capture_output=True,timeout=10)
