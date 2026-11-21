#!/usr/bin/env python3
"""Exercise the real loopback HTTP/WebSocket host and one-use browser sessions."""
import argparse,base64,http.client,http.cookiejar,json,os,select,signal,socket,subprocess,tempfile,urllib.request,shutil
from pathlib import Path
from urllib.parse import urlsplit, quote
ROOT=Path(__file__).resolve().parents[1];CLI=ROOT/'.build/debug/architecture';WEB=ROOT/'Apps/ArchitectureExplorerWeb/.build/debug/architecture-web'
parser=argparse.ArgumentParser()
parser.add_argument('--unpaired-cli',type=Path,help='Path to a standalone headless architecture executable for pairing regression checks')
args=parser.parse_args()
checks=[]
invalid=subprocess.run([str(WEB),'--unknown-option'],capture_output=True,text=True,timeout=5)
assert invalid.returncode==4 and 'unknownOption("--unknown-option")' in invalid.stderr
unbound = subprocess.run([str(WEB), '--codex-browser'], env={k:v for k,v in os.environ.items() if k!='CODEX_THREAD_ID'},
                         capture_output=True, text=True, timeout=5)
assert unbound.returncode == 4 and 'invalidBrowserSession' in unbound.stderr
checks.append('property analysis requires an originating Codex conversation')
checks.append('unknown Web host option fails before startup with a typed argument error')
with tempfile.TemporaryDirectory(prefix='ae-web-') as directory:
    workspace=Path(directory);(workspace/'Flow.swift').write_text('actor SessionAuthority { let token: String = \"local\"; func authorize() -> Bool { return true } }\nfunc value() -> Int { return 1 }\n')
    (workspace/'TypeLinks.swift').write_text('struct Dates { static func start() {} }\nstruct Month { func show() { Dates.start() } }\n')
    for source in (ROOT/'Tests/ArchitectureTests/Fixtures/CallableNodes').iterdir():shutil.copyfile(source,workspace/source.name)
    subprocess.run([str(CLI),'daemon','start','--workspace',directory],capture_output=True,check=True,timeout=30)
    process=subprocess.Popen([str(WEB),'--workspace',directory,'--no-open'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    try:
        assert select.select([process.stdout],[],[],30)[0],'Web host startup timed out'
        line=process.stdout.readline();assert line,(process.poll(),process.stderr.read())
        launch=json.loads(line);parts=urlsplit(launch['url']);origin=f'http://{parts.netloc}';token=parts.fragment.split('=',1)[1]
        def request(path,method='GET',body=None,headers=None):
            conn=http.client.HTTPConnection(parts.hostname,parts.port,timeout=5);conn.request(method,path,body,headers or {});response=conn.getresponse();data=response.read();result=(response.status,response.headers,data);conn.close();return result
        status,_,page=request('/');assert status==200 and b'/assets/layout-model.js' in page
        assert all(str(path).encode() not in page for path in (workspace,workspace.resolve()))
        status,_,layout=request('/assets/layout-model.js');assert status==200 and b'ArchitectureLayout' in layout
        checks.append('page loads its bundled shared layout model through the actual asset route')
        status,_,syntax=request('/assets/highlight.min.js')
        assert status==200 and syntax==(ROOT/'Sources/ArchitectureGraph/Resources/highlight.min.js').read_bytes()
        assert page.index(b'/assets/highlight.min.js') < page.index(b'/assets/explorer.js')
        checks.append('pinned Swift/Rust syntax grammars load locally before the renderer')
        assert request('/api?method=workspace.status')[0]==403;checks.append('unauthenticated graph HTTP rejected')
        assert request('/',headers={'Host':'attacker.invalid'})[0]==403;checks.append('foreign Host rejected')
        assert request('/',headers={'Origin':'https://attacker.invalid'})[0]==403;checks.append('foreign Origin rejected')
        jar=http.cookiejar.CookieJar();opener=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        authentication=urllib.request.Request(origin+'/session',json.dumps({'token':token}).encode(),headers={'Origin':origin,'Content-Type':'application/json'})
        with opener.open(authentication,timeout=5) as response:
            status=response.status;headers=response.headers;response.read()
        assert status==200
        cookies=[v for v in headers.get_all('Set-Cookie',[]) if v.startswith(f'architecture-session-{parts.port}=')]
        assert cookies and 'HttpOnly' in cookies[0] and 'SameSite=Strict' in cookies[0] and 'Secure' not in cookies[0]
        cookie=cookies[0].split(';',1)[0];checks.append('one-use token creates host-only HttpOnly/SameSite session for local HTTP')
        assert request('/session','POST',json.dumps({'token':token}),{'Origin':origin,'Content-Type':'application/json'})[0]==403;checks.append('launch token replay rejected')
        status,_,data=request('/api?method=workspace.status',headers={'Cookie':cookie});assert status==200 and json.loads(data)['snapshotID'];checks.append('authenticated HTTP reads the shared daemon snapshot')
        def graph(method, params):
            status, _, data = request('/api?method='+method+'&params='+quote(json.dumps(params)), headers={'Cookie':cookie})
            assert status == 200, data
            return json.loads(data)
        host = graph('host.context', {})
        assert 'propertyActions' not in host
        reported_root=Path(host['workspaceRoot'])
        assert reported_root.is_absolute() and reported_root.samefile(workspace),(reported_root,workspace)
        assert request('/api?method=host.context')[0]==403
        assert request('/api?method=host.context',headers={'Cookie':cookie,'Origin':'https://attacker.invalid'})[0]==403
        checks.append('the workspace root is available only to an authenticated same-origin browser session')
        status, _, _ = request('/properties', 'POST', '{}', {'Cookie':cookie, 'Origin':origin, 'Authorization':'Bearer '+host['csrf']})
        assert status == 404, status
        checks.append('ordinary authenticated browser hosts have no property context route')
        types = graph('graph.overview', {'level':'component','kinds':['candidateTypeReference']})
        month = next(n for n in types['nodes'] if n['name']=='Month')
        dates = next(n for n in types['nodes'] if n['name']=='Dates')
        edge = next(e for e in types['edges'] if e['source']==month['id'] and e['target']==dates['id'])
        thread_id = '81759d28-0dd3-44ef-91ec-86fdd7c60447'
        bound = subprocess.Popen([str(WEB),'--workspace',directory,'--codex-browser'],
                                 env={**os.environ, 'CODEX_THREAD_ID':thread_id}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            assert select.select([bound.stdout],[],[],15)[0]
            bound_url = urlsplit(json.loads(bound.stdout.readline())['url'])
            bound_origin = 'http://'+bound_url.netloc
            bound_client = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
            def bound_post(path, body, csrf=None):
                headers = {'Origin':bound_origin, 'Content-Type':'application/json'}
                if csrf: headers['Authorization'] = 'Bearer '+csrf
                req = urllib.request.Request(bound_origin+path, json.dumps(body).encode(), headers=headers)
                with bound_client.open(req,timeout=8) as resp: return json.load(resp)
            bound_post('/session', {'token':bound_url.fragment.split('=',1)[1]})
            with bound_client.open(bound_origin+'/api?method=host.context',timeout=5) as resp: session=json.load(resp)
            assert session['propertyActions'] and thread_id not in json.dumps(session)
            for candidate, csrf in [('different-conversation',session['csrf']), (thread_id,None)]:
                try: bound_post('/properties', {'connect':True, 'threadID':candidate}, csrf)
                except urllib.error.HTTPError as err: assert err.code==403
                else: raise AssertionError('foreign conversation or missing CSRF accepted')
            assert bound_post('/properties', {'connect':True, 'threadID':thread_id}, session['csrf']) == {}
            context = bound_post('/properties', {'threadID':thread_id, 'workspaceID':types['workspaceID'],
                                 'snapshotID':types['snapshotID'], 'entityID':month['id']}, session['csrf'])
            assert context['snapshotID']==types['snapshotID'] and context['entityID']==month['id']
            source=next(f for f in context['files'] if f['role']=='selected')
            assert source['text']==(workspace/source['path']).read_text()
            checks.append('thread-bound browser reads exact snapshot sources and rejects wrong recipients and missing CSRF')
        finally:
            bound.terminate()
            try: bound.wait(timeout=10)
            except subprocess.TimeoutExpired: bound.kill();bound.wait();raise
        site = edge['attributes']['reference.site']
        bounds = {'entityID':month['id'],'snapshotID':types['snapshotID'],'startByte':site['startByte'],'endByte':site['endByte']}
        assert graph('source.read',bounds)['text']=='Dates.start'
        for invalid in [{**bounds,'startByte':0}, {**bounds,'endByte':site['startByte']-1}, {k:v for k,v in bounds.items() if k!='endByte'}]:
            status, _, data = request('/api?method=source.read&params='+quote(json.dumps(invalid)),headers={'Cookie':cookie})
            assert status!=200 and b'INVALID_ARGUMENT' in data
        outline = graph('graph.overview', {'level':'file','depth':2})
        assert outline['extensions']['file.outline'] is True
        assert any(e['id']==edge['id'] and e['attributes']['reference.site']==site for e in outline['edges'])
        file = next(n for n in outline['nodes'] if n['kind']=='file' and n['name']=='Flow.swift')
        actor = next(n for n in outline['nodes'] if n['kind']=='actor')
        property_node = next(n for n in outline['nodes'] if n['name']=='token' and n['kind']=='field')
        assert property_node['attributes']['declaration.binding']=='let' and property_node['attributes']['declaration.type']=='String'
        method = next(n for n in outline['nodes'] if n['kind']=='method' and n['name']=='authorize')
        assert method['attributes']['declaration.parameters']=='()' and method['attributes']['declaration.returnType']=='Bool' and method['attributes']['declaration.returnTypeExplicit'] is True
        assert any(e['kind']=='contains' and e['source']==file['id'] and e['target']==actor['id'] for e in outline['edges'])
        assert any(e['kind']=='contains' and e['source']==actor['id'] and e['target']==method['id'] for e in outline['edges'])
        expanded = graph('graph.children', {'focus':file['id'],'level':'file','depth':2,'kinds':['calls']})
        assert {file['id'],actor['id'],method['id']} <= {n['id'] for n in expanded['nodes']}
        assert any(e['source']==actor['id'] and e['target']==method['id'] for e in expanded['edges'])
        checks.append('real Swift file outlines retain nested actor/method ownership through authenticated filtered queries')
        callable_views=[]
        for language,free_name in [('swift','callableSwift'),('rust','callable_rust')]:
            for name in [free_name,'update']:
                declaration=next(n for n in outline['nodes'] if n['language']==language and n['name']==name and n['kind'] in ['function','method'])
                view=graph('graph.neighbors',{'focus':declaration['id'],'snapshotID':outline['snapshotID'],'direction':'outgoing','depth':2,'limit':500,'edgeLimit':1500})
                assert view['snapshotID']==outline['snapshotID'] and not view['truncated']
                assert next(n for n in view['nodes'] if n['id']==declaration['id'])['attributes']['declaration.callable']['version']==1
                callable_views.append({'language':language,'name':name,'view':view})
        callable_file=workspace/'callable-graphs.json';callable_file.write_text(json.dumps(callable_views))
        subprocess.run(['node','--test','--test-name-pattern','^real Swift/Rust source graphs',str(ROOT/'Tools/node-cards.test.cjs')],env={**os.environ,'AE_CALLABLE_GRAPHS':str(callable_file)},check=True,timeout=30)
        checks.append('real Swift/Rust parsing through authenticated queries renders structured function/method nodes with original Edge endpoints in Cytoscape/ELK')

        ancestry = graph('graph.neighbors', {'focus':method['id'],'snapshotID':outline['snapshotID'],'kinds':['contains'],'direction':'incoming','depth':8,'limit':500,'edgeLimit':1500})
        assert ancestry['snapshotID']==outline['snapshotID'] and not ancestry['truncated']
        assert {file['id'],actor['id'],method['id']} <= {n['id'] for n in ancestry['nodes']}
        assert all(e['kind']=='contains' for e in ancestry['edges'])
        checks.append('snapshot-pinned incoming containment supplies breadcrumb ancestors outside the focused view')
        def websocket(headers,target=parts):
            stream=socket.create_connection((target.hostname,target.port),timeout=5);key=base64.b64encode(os.urandom(16)).decode();lines=[f'GET /events HTTP/1.1',f'Host: {target.netloc}','Upgrade: websocket','Connection: Upgrade',f'Sec-WebSocket-Key: {key}','Sec-WebSocket-Version: 13']+[k+': '+v for k,v in headers.items()]
            separator=chr(13)+chr(10);stream.sendall((separator.join(lines)+separator*2).encode());data=stream.recv(8192);stream.close();return data.split(bytes([13,10]),1)[0].decode()
        assert '101' in websocket({'Origin':origin,'Cookie':cookie});checks.append('authenticated same-origin WebSocket upgrades')
        assert '101' not in websocket({'Origin':origin});checks.append('unauthenticated WebSocket upgrade rejected')
        assert '101' not in websocket({'Origin':'https://attacker.invalid','Cookie':cookie});checks.append('foreign-origin WebSocket upgrade rejected')
        with tempfile.TemporaryDirectory(prefix='ae-web-peer-') as peer_directory:
            peer_workspace=Path(peer_directory);(peer_workspace/'Peer.swift').write_text('func peer() {}\n')
            subprocess.run([str(CLI),'index','--workspace',peer_directory],capture_output=True,check=True,timeout=20)
            peer_process=subprocess.Popen([str(WEB),'--workspace',peer_directory,'--no-open'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            try:
                assert select.select([peer_process.stdout],[],[],20)[0]
                peer_launch=json.loads(peer_process.stdout.readline());peer_parts=urlsplit(peer_launch['url']);peer_origin=f'http://{peer_parts.netloc}';peer_token=peer_parts.fragment.split('=',1)[1]
                peer_auth=urllib.request.Request(peer_origin+'/session',json.dumps({'token':peer_token}).encode(),headers={'Origin':peer_origin,'Content-Type':'application/json'})
                with opener.open(peer_auth,timeout=5) as response:assert response.status==200
                for endpoint in [origin,peer_origin]:
                    with opener.open(endpoint+'/api?method=workspace.status',timeout=5) as response:assert response.status==200
                checks.append('two loopback helpers remain authenticated in one browser cookie jar')
                for endpoint,target in [(origin,parts),(peer_origin,peer_parts)]:
                    upgrade=urllib.request.Request(endpoint+'/events');jar.add_cookie_header(upgrade)
                    assert '101' in websocket({'Origin':endpoint,'Cookie':upgrade.get_header('Cookie')},target=target)
                checks.append('both helpers upgrade WebSockets with their own session cookies')
                foreign=http.client.HTTPConnection(peer_parts.hostname,peer_parts.port,timeout=5)
                foreign.request('GET','/api?method=workspace.status',headers={'Cookie':cookie});response=foreign.getresponse();assert response.status==403;response.read();foreign.close()
                checks.append('another helper session cookie cannot authenticate a peer')
            finally:
                peer_process.send_signal(signal.SIGTERM)
                try:peer_process.wait(timeout=8)
                except subprocess.TimeoutExpired:peer_process.kill();peer_process.wait(timeout=5);raise
                subprocess.run([str(CLI),'daemon','stop','--workspace',peer_directory],capture_output=True,timeout=8)
        def event_channel():
            channel=socket.create_connection((parts.hostname,parts.port),timeout=5)
            lines=['GET /events HTTP/1.1',f'Host: {parts.netloc}','Upgrade: websocket','Connection: Upgrade',f'Sec-WebSocket-Key: {base64.b64encode(os.urandom(16)).decode()}','Sec-WebSocket-Version: 13',f'Origin: {origin}',f'Cookie: {cookie}']
            channel.sendall(('\r\n'.join(lines)+'\r\n\r\n').encode())
            return channel

        def frames(channel):
            with channel.makefile('rb') as stream:
                assert b'101' in stream.readline()
                while line:=stream.readline():
                    if line==b'\r\n':break
                else:raise AssertionError('WebSocket response ended before the frame stream')
                while header:=stream.read(2):
                    assert len(header)==2
                    opcode=header[0]&15
                    length=header[1]&127
                    if length in (126,127):
                        length=int.from_bytes(stream.read(2 if length==126 else 8),'big')
                    assert length<=4*1024*1024
                    yield opcode,stream.read(length)
                    if opcode==8:return

        with event_channel() as channel:
            events=frames(channel)
            opcode,body=next(events)
            assert opcode==1 and json.loads(body)['type'] in ('viewInvalidated','analysisStatusChanged')
            subprocess.run([str(CLI),'daemon','stop','--workspace',directory],capture_output=True,text=True,check=True,timeout=10)
            assert any(opcode==8 for opcode,_ in events)
        checks.append('backend failure closes an authenticated stream without a self-await deadlock')

        if args.unpaired_cli:
            unpaired=str(args.unpaired_cli.resolve())
            subprocess.run([unpaired,'daemon','start','--workspace',directory],capture_output=True,check=True,timeout=30)
            try:
                denied=subprocess.run([str(WEB),'--workspace',directory,'--no-open'],capture_output=True,text=True,timeout=10)
                assert denied.returncode!=0 and not denied.stdout and 'WEB_HOST_PAIRING_MISMATCH' in denied.stderr,denied
                with event_channel() as channel:
                    events=frames(channel)
                    opcode,body=next(events)
                    failure=json.loads(body)
                    assert opcode==1 and failure['type']=='liveUnavailable' and failure['code']=='WEB_HOST_PAIRING_MISMATCH',failure
                    assert next(events)[0]==8
                checks.append('an unpaired daemon rejects startup and emits a terminal event to existing browser sessions')
            finally:
                subprocess.run([unpaired,'daemon','stop','--workspace',directory],capture_output=True,check=True,timeout=10)
            subprocess.run([str(CLI),'daemon','start','--workspace',directory],capture_output=True,check=True,timeout=30)
            with event_channel() as channel:
                events=frames(channel)
                opcode,body=next(events)
                assert opcode==1 and json.loads(body)['type'] in ('viewInvalidated','analysisStatusChanged')
            checks.append('same paired build restores index delivery to an existing authenticated browser session')

    finally:
        process.send_signal(signal.SIGTERM)
        try:process.wait(timeout=10)
        except subprocess.TimeoutExpired:process.kill();process.wait();raise
        subprocess.run([str(CLI),'daemon','stop','--workspace',directory],capture_output=True,timeout=10)
report={'checks':checks,'passed':len(checks)};(ROOT/'Documentation/web-security-results.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
