'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const assets=path.join(__dirname,'../Sources/ArchitectureGraph/Resources');
const model=require(path.join(assets,'layout-model.js'));
const ELK=require(path.join(assets,'elk.bundled.js'));
const node=(id,kind='module')=>({id,name:id,kind});
const edge=(id,source,target,kind='dependsOn',attributes={})=>({id,source,target,kind,attributes});
const request=(nodes,edges)=>({generation:7,queryID:'query',snapshotID:'snapshot',nodes,edges});
const overlaps=(a,b)=>a.x<b.x+b.width&&a.x+a.width>b.x&&a.y<b.y+b.height&&a.y+a.height>b.y;
function disjoint(nodes){for(let i=0;i<nodes.length;i++)for(let j=i+1;j<nodes.length;j++)assert.equal(overlaps(nodes[i],nodes[j]),false,`${nodes[i].id} overlaps ${nodes[j].id}`);}
test('recorded containment becomes frames while dependencies determine ranks and routes',async()=>{
  const input=request([node('workspace','workspace'),node('package','package'),node('app'),node('service'),node('core'),node('other','package')],[edge('wp','workspace','package','contains'),edge('wo','workspace','other','contains'),...['app','service','core'].map(id=>edge('p-'+id,'package',id,'contains')),edge('as','app','service'),edge('sc','service','core')]);
  const before=JSON.stringify(input),plan=model.plan(input),result=await model.layout(input,new ELK()),nodes=new Map(result.nodes.map(n=>[n.id,n]));
  assert.equal(JSON.stringify(input),before);assert.equal(plan.hidden.size,5);assert.deepEqual([...plan.groups].sort(),['package','workspace']);
  assert.equal(result.nodes.length,input.nodes.length);assert.equal(result.generation,7);
  assert.ok(nodes.get('app').y+112<nodes.get('service').y);assert.ok(nodes.get('service').y+112<nodes.get('core').y);
  for(const id of ['app','service','core']){const p=nodes.get('package'),n=nodes.get(id);assert.ok(n.x>=p.x+24&&n.y>=p.y+88&&n.x+264<=p.x+p.width-24&&n.y+112<=p.y+p.height-24);}
  disjoint(result.nodes.filter(n=>!n.group));
  assert.deepEqual(result.routes.map(r=>r.id).sort(),['as','sc']);
  for(const route of result.routes)for(let i=1;i<route.points.length;i++){const a=route.points[i-1],b=route.points[i];assert.ok(a.x===b.x||a.y===b.y,'Orthogonal ELK segments');}
  const source=nodes.get('app'),first=result.routes.find(r=>r.id==='as').points[0];assert.ok(first.x>=source.x&&first.x<=source.x+264&&first.y>=source.y&&first.y<=source.y+112,'Route coordinates include container offsets');
});
test('source layout direction arranges linked and independent nodes along the selected axis',async()=>{
  for(const edges of [[],[edge('ab','a','b')]]){
    const input=request([node('a'),node('b')],edges);
    for(const [direction,axis,extent] of [['RIGHT','x','width'],['DOWN','y','height']]){
      const result=await model.layout({...input,direction},new ELK());
      const a=result.nodes.find(n=>n.id==='a'),b=result.nodes.find(n=>n.id==='b');
      assert.ok(a[axis]+a[extent]<b[axis]);
      assert.deepEqual(result.routes.map(r=>r.id),edges.map(e=>e.id));
    }
  }
});
test('input enumeration does not change placement; cycles and disconnected nodes stay visible',async()=>{
  const input=request([node('a'),node('b'),node('c'),node('isolated')],[edge('ab','a','b'),edge('bc','b','c'),edge('ca','c','a')]);
  const engine=new ELK(),first=await model.layout(input,engine);
  await model.layout(request([node('unrelated-a'),node('unrelated-b')],[edge('unrelated','unrelated-a','unrelated-b')]),engine);
  const second=await model.layout({...input,nodes:[...input.nodes].reverse(),edges:[...input.edges].reverse()},engine);
  assert.deepEqual(first,second);assert.equal(first.nodes.length,4);disjoint(first.nodes);
  assert.deepEqual(input.edges.map(e=>[e.source,e.target]),[['a','b'],['b','c'],['c','a']]);
});
test('ambiguous parents stay explicit and malformed containment fails visibly',()=>{
  const input=request([node('p','package'),node('q','package'),node('child')],[edge('pc','p','child','contains'),edge('qc','q','child','contains')]);
  const plan=model.plan(input);assert.equal(plan.parents.size,0);assert.equal(plan.hidden.size,0);assert.equal(plan.graph.edges.length,2);
  assert.throws(()=>model.plan(request([node('p','package'),node('q','package')],[edge('pq','p','q','contains'),edge('qp','q','p','contains')])),/Cyclic containment/);
  assert.throws(()=>model.plan(request([node('a')],[edge('ab','a','missing')])),/endpoint is missing/);
  assert.throws(()=>model.plan(request([node('a'),node('a')],[])),/Duplicate/);
});
test('CFG uses recorded flow constraints and keeps declaration headers outside executable ranks',async()=>{
  const nodes=[node('function','function'),...['entry','condition','body','exit'].map(id=>node(id,'basicBlock'))];
  const edges=[...nodes.slice(1).map(n=>edge('owns-'+n.id,'function',n.id,'contains')),edge('entry','entry','condition','controlFlow',{'cfg.branch':'entry'}),edge('true','condition','body','controlFlow',{'cfg.branch':'true'}),edge('false','condition','exit','controlFlow',{'cfg.branch':'false'}),edge('repeat','body','condition','controlFlow',{'cfg.branch':'continue'})];
  const input=request(nodes,edges),plan=model.plan(input),result=await model.layout(input,new ELK()),positions=new Map(result.nodes.map(n=>[n.id,n]));
  assert.equal(plan.parents.size,0);assert.equal(plan.graph.edges.length,4);assert.equal(result.nodes.length,5);
  assert.ok(positions.get('function').y+112<positions.get('entry').y);assert.ok(positions.get('entry').y<positions.get('condition').y);disjoint(result.nodes);
  assert.equal(edges.find(e=>e.id==='repeat').source,'body');
});
test('maximum supported view is finite and over-budget requests never invoke ELK',async()=>{
  const nodes=Array.from({length:500},(_,i)=>node('n'+String(i).padStart(3,'0'))),edges=Array.from({length:499},(_,i)=>edge('e'+i,nodes[i].id,nodes[i+1].id));
  const result=await model.layout(request(nodes,edges),new ELK());assert.equal(result.nodes.length,500);assert.ok(result.nodes.every(n=>Number.isFinite(n.x)&&Number.isFinite(n.y)));disjoint(result.nodes);
  let invoked=false;const engine={layout(){invoked=true;}};
  await assert.rejects(model.layout(request([...nodes,node('overflow')],edges),engine),/budget/);assert.equal(invoked,false);
  await assert.rejects(model.layout(request([node('one')],Array.from({length:1501},(_,i)=>edge('e'+i,'one','one'))),engine),/budget/);
});
test('worker coalesces pending views and restarts ELK on its owned deadline',async()=>{
  const active=[],responses=[],timers=new Map();let timerID=0,engines=0,terminated=0;
  const sandbox={ArchitectureLayout:{layout(input){return new Promise((resolve,reject)=>active.push({input,resolve,reject}));}},ELK:class{constructor(){engines++;}terminateWorker(){terminated++;}},Worker:class{},self:{postMessage:value=>responses.push(value)},importScripts(){},setTimeout:callback=>{timers.set(++timerID,callback);return timerID;},clearTimeout:id=>timers.delete(id)};
  vm.runInNewContext(fs.readFileSync(path.join(assets,'layout-worker.js'),'utf8'),sandbox);
  const send=generation=>sandbox.self.onmessage({data:{generation,queryID:'q',snapshotID:'s'}});
  send(1);send(2);send(3);assert.equal(active.length,1);active[0].resolve({generation:1});await new Promise(setImmediate);assert.equal(active.length,2);assert.equal(active[1].input.generation,3);
  [...timers.values()][0]();await new Promise(setImmediate);assert.match(responses[1].error,/deadline/);assert.equal(responses[1].generation,3);assert.equal(terminated,1);assert.equal(engines,2);
  send(4);assert.equal(active[2].input.generation,4);active[2].resolve({generation:4});await new Promise(setImmediate);assert.equal(responses[2].generation,4);assert.equal(timers.size,0);
});

test('independent package frames start with the largest scope and cross-package facts remain constraints',async()=>{
  const nodes=[node('w','workspace'),node('p','package'),node('q','package'),node('a'),node('b'),node('c')];
  const contains=[edge('wp','w','p','contains'),edge('wq','w','q','contains'),edge('pa','p','a','contains'),edge('pb','p','b','contains'),edge('qc','q','c','contains')];
  const input=request(nodes,[...contains,edge('ab','a','b')]),local=await model.layout(input,new ELK()),positions=new Map(local.nodes.map(n=>[n.id,n]));
  assert.ok(positions.get('p').y+positions.get('p').height<positions.get('q').y);assert.equal(positions.get('p').x,positions.get('q').x);
  const cross=await model.layout({...input,edges:[...input.edges,edge('bc','b','c')]},new ELK());assert.equal(cross.nodes.length,6);assert.ok(cross.routes.some(r=>r.id==='bc'));disjoint(cross.nodes.filter(n=>!n.group));
});

test('dense dependency routing avoids unnecessary detours and unrelated card interiors',async()=>{
  const input=JSON.parse(fs.readFileSync(path.join(__dirname,'Fixtures/architecture-layout.json'),'utf8'));
  const result=await model.layout(input,new ELK()),facts=new Map(input.edges.map(e=>[e.id,e])),leaves=result.nodes.filter(n=>!n.group);
  const dependencyCount=input.edges.filter(e=>e.kind==='dependsOn').length;
  assert.equal(result.routes.length,dependencyCount);disjoint(leaves);
  const bends=result.routes.reduce((sum,r)=>sum+r.points.length-2,0);
  assert.ok(bends<=dependencyCount*3,`${bends} bends for ${dependencyCount} dependency edges`);
  for(const route of result.routes)for(const point of route.points.slice(1,-1))for(const box of leaves){
    const fact=facts.get(route.id);if(box.id===fact.source||box.id===fact.target)continue;
    const dx=Math.max(box.x-point.x,0,point.x-box.x-box.width),dy=Math.max(box.y-point.y,0,point.y-box.y-box.height);
    assert.ok(Math.hypot(dx,dy)>=8,'Rounded corners stay clear of unrelated cards');
  }
  for(const route of result.routes)for(let i=1;i<route.points.length;i++){
    const a=route.points[i-1],b=route.points[i],fact=facts.get(route.id);
    for(const box of leaves){
      if(box.id===fact.source||box.id===fact.target)continue;
      const intersects=a.y===b.y?a.y>box.y&&a.y<box.y+box.height&&Math.max(a.x,b.x)>box.x&&Math.min(a.x,b.x)<box.x+box.width:a.x>box.x&&a.x<box.x+box.width&&Math.max(a.y,b.y)>box.y&&Math.min(a.y,b.y)<box.y+box.height;
      assert.equal(intersects,false,`${route.id} crosses the interior of ${box.id}`);
    }
  }
});


test('property sections are source ordered compact rows above other declarations, including cross-scope relations',async()=>{
  const fields=[...Array(14)].map((_,i)=>({...node('p'+i,'field'),anchor:{startByte:i*30},attributes:{'declaration.binding':'let'}}));
  const nodes=[node('file','file'),node('owner','type'),...fields,node('init','method'),node('nested','type'),node('external','type')];
  const edges=[edge('file-owner','file','owner','contains'),...fields.map(n=>edge('owns-'+n.id,'owner',n.id,'contains')),edge('oi','owner','init','contains'),edge('on','owner','nested','contains'),edge('use','p3','external','usesType'),edge('call','init','external','calls')];
  const input=request(nodes,edges),before=JSON.stringify(input),result=await model.layout(input,new ELK()),byID=new Map(result.nodes.map(n=>[n.id,n]));
  assert.equal(JSON.stringify(input),before);assert.equal(result.nodes.length,nodes.length);
  fields.forEach((field,i)=>{const n=byID.get(field.id);assert.equal(n.width,640);assert.equal(n.height,32);assert.equal(n.x,byID.get('p0').x);if(i)assert.equal(n.y,byID.get('p'+(i-1)).y+32);});
  assert.ok(byID.get('init').y>=byID.get('p13').y+32+24);assert.ok(byID.get('nested').y>=byID.get('p13').y+32+24);
  disjoint(result.nodes.filter(n=>!n.group));assert.equal(result.routes.some(r=>r.id==='use'),false,'Row edges retain original native endpoints');
  const reversed=await model.layout({...input,nodes:[...nodes].reverse(),edges:[...edges].reverse()},new ELK());assert.deepEqual(result,reversed);
  assert.notEqual(model.plan(input).key,model.plan({...input,nodes:nodes.map(n=>n.id==='p0'?{...n,anchor:{startByte:9999}}:n)}).key,'Reordering declarations invalidates placement');
  assert.deepEqual(model.size({...node('alias','field'),attributes:{'declaration.kind':'typeAlias'}}),model.card);
});


test('leaf cards keep fixed widths while original property rows and parent frames retain their geometry',async()=>{
  const leaves=[node('plain','type'),{...node('short','method'),language:'swift'},
    {...node('long','function'),language:'rust',name:'longName'.repeat(40),attributes:{'declaration.parameters':'argument: Value, '.repeat(80),'declaration.callable':{version:1,access:'pub(crate)',results:[{type:'Result<LongType, Error>'}]}}},
    {...node('property','field'),attributes:{'declaration.type':'SomeType'.repeat(80)}}];
  const nodes=[node('file','file'),...leaves],edges=leaves.map(n=>edge('owns-'+n.id,'file',n.id,'contains'));
  const input=request(nodes,edges),result=await model.layout(input,new ELK()),byID=new Map(result.nodes.map(n=>[n.id,n]));
  for(const leaf of leaves)assert.equal(byID.get(leaf.id).width,leaf.kind==='field'?640:264);
  assert.ok(byID.get('file').width>264,'Only the parent frame grows to wrap children');
  disjoint(result.nodes.filter(n=>!n.group));
  for(const leaf of leaves){const child=byID.get(leaf.id),parent=byID.get('file');assert.ok(child.x>=parent.x+24&&child.x+child.width<=parent.x+parent.width-24);}
  const edited={...input,nodes:nodes.map(n=>n.id==='long'?{...n,name:'f',attributes:{}}:n)};
  assert.equal(model.plan(input).key,model.plan(edited).key,'Metadata changes cannot invalidate geometry');
  assert.deepEqual(await model.layout(edited,new ELK()),result);
});

test('method nodes retain dependency ranks, separate bounds, original routes and CFG header geometry',async()=>{
  const nodes=[node('owner','actor'),node('caller','method'),node('callee','method'),node('outside','function')];
  const edges=[edge('owns-caller','owner','caller','contains'),edge('owns-callee','owner','callee','contains'),edge('call','caller','callee','calls'),edge('external','callee','outside','calls')];
  const input=request(nodes,edges),result=await model.layout(input,new ELK()),byID=new Map(result.nodes.map(n=>[n.id,n]));
  assert.equal(model.plan(input).rows.size,0,'Methods are graph nodes, not member rows');
  for(const id of ['caller','callee']){assert.equal(byID.get(id).width,264);assert.equal(byID.get(id).height,140);}
  assert.ok(byID.get('callee').y>byID.get('caller').y+140);disjoint(result.nodes.filter(n=>!n.group));
  assert.deepEqual(result.routes.map(r=>r.id).sort(),['call','external']);
  for(const route of result.routes){const fact=edges.find(e=>e.id===route.id),source=byID.get(fact.source),target=byID.get(fact.target),first=route.points[0],last=route.points.at(-1);assert.ok(first.x>=source.x&&first.x<=source.x+source.width&&first.y>=source.y&&first.y<=source.y+source.height);assert.ok(last.x>=target.x&&last.x<=target.x+target.width&&last.y>=target.y&&last.y<=target.y+target.height);}
  assert.deepEqual(result,await model.layout({...input,nodes:[...nodes].reverse(),edges:[...edges].reverse()},new ELK()));
  const cfg=await model.layout(request([node('method','method'),node('entry','basicBlock'),node('exit','basicBlock')],[edge('flow','entry','exit','controlFlow')]),new ELK());
  const header=cfg.nodes.find(n=>n.id==='method');assert.equal(header.width,264);assert.equal(header.height,112);disjoint(cfg.nodes);
});

test('independent callable children use their fixed geometry for a compact two-column grid',async()=>{
  const nodes=[node('owner','type'),...['a','b','c'].map(id=>node(id,'method'))],edges=nodes.slice(1).map(n=>edge('owns-'+n.id,'owner',n.id,'contains'));
  const result=await model.layout(request(nodes,edges),new ELK()),byID=new Map(result.nodes.map(n=>[n.id,n]));
  assert.equal(byID.get('a').y,byID.get('b').y);assert.equal(byID.get('a').x,byID.get('c').x);
  assert.equal(byID.get('b').x-byID.get('a').x,264+36);assert.equal(byID.get('c').y-byID.get('a').y,140+48);
  disjoint(result.nodes.filter(n=>!n.group));
});
