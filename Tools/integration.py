#!/usr/bin/env python3
"""Exercise compiled CLI, shared daemon and MCP against real source changes."""
import concurrent.futures,json,os,select,socket,subprocess,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CLI=ROOT/'.build/debug/architecture'
checks=[]
def run(workspace,*args,code=0):
    result=subprocess.run([str(CLI),*args,'--workspace',str(workspace)],capture_output=True,text=True,timeout=30)
    assert result.returncode==code,(args,result.returncode,result.stderr)
    return json.loads(result.stdout) if code==0 else result
with tempfile.TemporaryDirectory(prefix='ae-integration-') as directory:
    workspace=Path(directory);source=workspace/'Flow.swift';rust=workspace/'flow.rs'
    source.write_text('func helper(_ x: Int) -> Int { return x + 1 }\nfunc caller() -> Int { return helper(3) }\n')
    rust.write_text('fn helper(x: i32) -> i32 { return x + 1; }\nfn caller() -> i32 { return helper(3); }\n')
    # This source would write a sentinel if an untrusted manifest were evaluated.
    (workspace/'Package.swift').write_text('import Foundation\ntry! Data("executed".utf8).write(to: URL(fileURLWithPath: "'+str(workspace/'executed')+'"))\n')
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            hello=list(pool.map(lambda _:run(workspace,'daemon','start'),range(4)))
        assert len({h['processIdentity'] for h in hello})==1
        checks.append('four simultaneous launches share one daemon identity')
        initial=run(workspace,'index');assert not (workspace/'executed').exists()
        checks.append('untrusted manifest never executes')
        wid=initial['workspaceID'];address=f'/tmp/ae-{os.getuid()}-{wid[-24:]}/rpc.sock'
        for index in range(50):
            peer=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);peer.settimeout(5)
            try:peer.connect(address)
            except ConnectionRefusedError:pass  # A full listen backlog explicitly applies backpressure.
            finally:peer.close()
            time.sleep(.005)
        time.sleep(.5)
        assert run(workspace,'daemon','status')['processIdentity']==hello[0]['processIdentity']
        checks.append('fifty abandoned IPC connections do not terminate the shared daemon')

        hits=run(workspace,'search','--query','helper','--limit','2');assert hits['truncated'] and hits['nextCursor']
        ids=set(n['id'] for n in hits['nodes']);cursor=hits['nextCursor'];snapshot=hits['snapshotID']
        while cursor:
            page=run(workspace,'search','--query','helper','--limit','2','--snapshot',snapshot,'--cursor',cursor)
            assert ids.isdisjoint({n['id'] for n in page['nodes']});ids.update(n['id'] for n in page['nodes']);cursor=page.get('nextCursor')
        checks.append('snapshot-fixed search pages have no duplicates')
        all_hits=run(workspace,'search','--query','helper')
        function=next(n for n in all_hits['nodes'] if n['kind']=='function' and n['language']=='swift')
        cfg=run(workspace,'cfg','--symbol',function['id']);assert cfg['completeness']=='completeWithinScope' and any(e['kind']=='controlFlow' for e in cfg['edges'])
        checks.append('on-demand CFG reaches real control-flow blocks')
        before=run(workspace,'status')['snapshotID']
        source.write_text('\nfunc helper(_ x: Int) -> Int { return x + 2 }\nfunc caller() -> Int { return helper(3) }\n')
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            after=run(workspace,'status')['snapshotID']
            if after!=before:break
            time.sleep(.05)
        assert after!=before
        assert any(n['id']==function['id'] for n in run(workspace,'search','--query','helper')['nodes'])
        delta=run(workspace,'diff','--from',before,'--to',after);assert delta['upsertNodes']
        checks.append('saved edit publishes a new snapshot, preserves callable ID and produces diff')
        source.write_text('func helper( {')
        broken=run(workspace,'index');assert any(d['code']=='SOURCE_PARSE_FAILED' for d in broken['diagnostics'])
        stale=run(workspace,'search','--query','helper');assert any(c['freshness']=='stale' for c in stale['coverage'])
        checks.append('parse failure retains stale last-known-good instead of empty success')
        source.unlink();deleted=run(workspace,'index');assert not any(n['id']==function['id'] for n in run(workspace,'search','--query','helper')['nodes'])
        checks.append('confirmed deletion removes old entities')
        for fmt in ['json','mermaid','svg','html']:
            destination=workspace/('export.'+fmt)
            run(workspace,'export','--level','function','--format',fmt,'--out',str(destination))
            assert destination.stat().st_size>0
            run(workspace,'export','--format',fmt,'--out',str(destination),code=2)
        checks.append('all four exports use real snapshots and refuse overwrite')
        run(workspace,'graph','--require-complete',code=3);run(workspace,'graph','--limit','501',code=6);run(workspace,'graph','--unknown',code=2);run(workspace,'graph','--direction','sideways',code=2);run(workspace,'explore','--port','invalid',code=2)
        checks.append('CLI completeness, budget and argument failures have typed exit codes')
        process=subprocess.Popen([str(CLI),'mcp','--workspace',str(workspace)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        def write(value):process.stdin.write(json.dumps(value)+'\n');process.stdin.flush()
        def read():
            assert select.select([process.stdout],[],[],20)[0],'MCP response timeout'
            line=process.stdout.readline();assert len(line.encode())<=65536
            return json.loads(line)
        write({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2025-11-25','capabilities':{},'clientInfo':{'name':'ArchitectureExplorer integration client','version':'1'}}})
        assert read()['result']['protocolVersion']=='2025-11-25'
        write({'jsonrpc':'2.0','method':'notifications/initialized'})
        write({'jsonrpc':'2.0','id':2,'method':'tools/list'});assert len(read()['result']['tools'])==22
        write({'jsonrpc':'2.0','id':3,'method':'tools/call','params':{'name':'architecture_search','arguments':{'text':'helper'}}})
        result=read();assert not result['result']['isError'];data=result['result']['structuredContent'];assert data['snapshotID']==run(workspace,'status')['snapshotID']
        write({'jsonrpc':'2.0','id':4,'method':'tools/call','params':{'name':'architecture_overview','arguments':{}}});write({'jsonrpc':'2.0','method':'notifications/cancelled','params':{'requestId':4,'reason':'integration cancellation'}});read()
        process.stdin.close();assert process.wait(timeout=10)==0
        checks.append('MCP initialize/list/query/cancel/EOF shutdown uses shared daemon and bounded protocol stdout')
        before=run(workspace,'status');old_hello=run(workspace,'daemon','status');run(workspace,'daemon','stop')
        for _ in range(100):
            status=subprocess.run([str(CLI),'daemon','status','--workspace',str(workspace)],capture_output=True,timeout=5)
            if status.returncode!=0:break
            time.sleep(.02)
        assert status.returncode!=0,'Daemon did not actually stop'
        new_hello=run(workspace,'daemon','start');assert new_hello['processIdentity']!=old_hello['processIdentity']
        run(workspace,'index');after=run(workspace,'status');assert before['snapshotID']==after['snapshotID'] and after['diskReconciled']
        checks.append('restart reconciles disk and preserves committed snapshot')
    finally:
        subprocess.run([str(CLI),'daemon','stop','--workspace',str(workspace)],capture_output=True,timeout=10)
report={'client':'Python standard-library JSON-RPC MCP client','protocolVersion':'2025-11-25','checks':checks,'passed':len(checks)}
(ROOT/'Documentation/integration-results.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
