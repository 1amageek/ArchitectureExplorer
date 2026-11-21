const test=require('node:test');
const assert=require('node:assert/strict');
require('../Sources/ArchitectureGraph/Resources/c4-layout.js');

test('expanding a system preserves exterior anchors and nested area membership',()=>{
  const scope=[{id:'company',name:'Company'},{id:'domain',name:'Domain'}];
  const system={id:'s',name:'Booking',kind:'softwareSystem',attributes:{'context.areas':scope,'context.containerCount':3}};
  const neighbor={id:'z',name:'External',kind:'softwareSystem'};
  const children=['app','client','database'].map(id=>({id,name:id,attributes:{'context.owner':'s'}}));
  const overview=C4Layout.plan([system,neighbor],[{id:"use-system",source:"z",target:"s"}]);
  const edges=[{id:'use',source:'z',target:'app'},{id:'store',source:'app',target:'database'}];
  const expanded=C4Layout.plan([neighbor,...children,system],edges,system.id);
  assert.deepEqual(overview.positions.get('z'),expanded.positions.get('z'));
  const byID=new Map(expanded.areas.map(a=>[a.id,a]));
  assert(byID.get('company').children.includes(byID.get('domain')));
  assert(byID.get('domain').children.includes(byID.get('s')));
  assert.equal(expanded.paths.length,2);
  for(const {points} of expanded.paths) for(let i=1;i<points.length;i++){
    const [x,z]=points[i], [px,pz]=points[i-1];
    assert(x===px||z===pz);
    assert(Number.isInteger(x)&&Number.isInteger(z));
  }
});

test('C2 places declared app and backend groups in separate areas within the same system',()=>{
  const system={id:'system',name:'System',attributes:{'context.areas':[{id:'domain',name:'Product'}]}};
  const app={id:'app-area',name:'App'}, backend={id:'backend-area',name:'Backend'};
  const container=(id,group)=>({id,name:id,attributes:{'context.owner':system.id,'context.containerGroup':group}});
  const nodes=[system,container('client',app),container('api',backend),container('db',backend),container('other')];
  const edge={id:'request',source:'client',target:'api'};
  const plan=C4Layout.plan(nodes,[edge],system.id);
  const areas=new Map(plan.areas.map(area=>[area.id,area]));
  const parent=areas.get(system.id), left=areas.get(app.id), right=areas.get(backend.id);
  assert.deepEqual(left.children.map(child=>child.id),['client']);
  assert.deepEqual(right.children.map(child=>child.id),['api','db']);
  assert.deepEqual(new Set(parent.children.map(item=>item.id)),new Set([app.id,backend.id,'other']));
  assert(left.x+left.width<=right.x||right.x+right.width<=left.x||
    left.z+left.depth<=right.z||right.z+right.depth<=left.z);
  assert.equal(plan.paths[0].edge,edge);
  assert.deepEqual(new Set(plan.visibleAreas(new Set(['api']))),new Set(['domain',system.id,backend.id]));
  assert.deepEqual(C4Layout.plan([system],[]).areas.map(area=>area.id),['domain']);
});

test('buses start on the source footprint and end at the target approach port',()=>{
  const nodes=['a','b','c','d'].map(id=>({id,name:id,kind:'application'}));
  const edges=nodes.flatMap(source=>nodes.map(target=>({
    id:source.id+'-'+target.id,source:source.id,target:target.id
  })));
  const {positions,paths}=C4Layout.plan(nodes,edges);
  assert.equal(paths.length,edges.length);
  for(const {edge,points} of paths){
    const distance=(p,q)=>Math.max(Math.abs(p[0]-q[0]),Math.abs(p[1]-q[1]));
    const source=positions.get(edge.source),target=positions.get(edge.target);
    const tip=points.at(-1),approach=points.at(-2);
    assert(distance(points[0],source)<=1);
    assert(distance(tip,target)>=3&&distance(tip,target)<=5);
    const axis=tip[0]===approach[0]?1:0;
    assert.equal(Math.sign(tip[axis]-approach[axis]),Math.sign(target[axis]-tip[axis]));
    if(edge.source!==edge.target)assert.notDeepEqual(points[0],points.at(-1));
    for(let i=1;i<points.length;i++){
      const [x,z]=points[i], [px,pz]=points[i-1];
      assert(x===px||z===pz);
      assert(x!==px||z!==pz);
    }
  }
});

test('slightly offset objects in nested C2 areas share a straight port-to-port connection',()=>{
  const user={id:'person',name:'User',kind:'person',attributes:{'context.areas':[{id:'people',name:'People'}]}};
  const system={id:'system',name:'System',kind:'softwareSystem',attributes:{'context.areas':[{id:'local',name:'Local'}],'context.containerCount':2}};
  const children=['application','store'].map(id=>({id,name:id,attributes:{'context.owner':'system'}}));
  const edges=[{id:'store-tasks',source:'application',target:'store'},{id:'use-app',source:'person',target:'application'}];
  const plan=C4Layout.plan([user,system,...children],edges,system.id);
  const source=plan.positions.get('person'),target=plan.positions.get('application');
  assert.notEqual(source[1],target[1],'Nested area offsets put the object centers on different grid lines');
  const points=plan.paths.find(path=>path.edge.id==='use-app').points;
  assert.deepEqual(points,[[source[0],source[1]+1],[target[0]-4,source[1]+1]]);
});

test('object captions shorten above the silhouette and their center stays over the object',()=>{
  const footprint={left:-20,right:20,top:0,bottom:35};
  const item={type:'object-label',id:'database',footprint,height:12,
    variants:[{text:'Reservations database',width:120},{text:'Res…',width:32}]};
  const neighbors=[{left:-100,right:-24,top:-30,bottom:0},{left:24,right:100,top:-30,bottom:0}];
  const p=C4Layout.placeCaptions([item],[footprint,...neighbors],1).get(item.id);
  assert(p.visible);assert.equal(p.text,'Res…');assert(p.box.bottom<footprint.top);
  assert(p.x>=footprint.left&&p.x<=footprint.right);
});

test('nested captions use front edges and reserve the active area when both sides fill',()=>{
  const area=(id,shift)=>({type:'area-label',id,height:12,variants:[{text:id,width:50}],
    segments:[{a:[100,110-shift],b:[0,60-shift]},{a:[200,60-shift],b:[100,110-shift]}]});
  const items=['outer','middle','active'].map((id,i)=>area(id,i*2));
  const p=C4Layout.placeCaptions(items,[],1,'active');
  assert(!p.get('outer').visible);
  assert.equal(p.get('middle').segment,items[1].segments[1]);
  assert.equal(p.get('active').segment,items[2].segments[0]);
  assert(p.get('active').visible);
});

test('container group captions can slide along a crowded edge and retain priority over the system caption',()=>{
  const segment={a:[0,40],b:[120,0]};
  const group={type:'area-label',id:'app',containerGroup:true,height:12,
    variants:[{text:'App',width:24}],segments:[segment]};
  const system={...group,id:'system',containerGroup:false,segments:[{a:[0,40],b:[30,30]}]};
  const glyph={left:42,right:78,top:8,bottom:27};
  const captions=C4Layout.placeCaptions([group,system],[glyph],1,system.id);
  assert(captions.get(group.id).visible);
  assert.equal(captions.get(group.id).offset,.125);
  assert(!captions.get(system.id).visible);
});

test('operation captions use a clear straight segment and generic labels wait for interaction',()=>{
  const segment=(a,b)=>({a,b});
  const first=segment([0,0],[140,50]),second=segment([140,50],[260,110]);
  const operation={type:'edge-label',id:'uses',height:12,variants:[{text:'Uses API',width:50}],segments:[first,second]};
  const dependency={...operation,id:'dependency',generic:true,segments:[segment([70,-20],[70,70])]};
  const p=C4Layout.placeCaptions([operation,dependency],[],1);
  assert(p.get('uses').visible);
  assert.equal(p.get('uses').segment,second);
  assert(!p.get('dependency').visible);
});

test('every visible Map object has a visible containing area at either level',()=>{
  const nodes=[{id:'app',kind:'softwareSystem',name:'Core',attributes:{'context.containerCount':2}},
    {id:'db',kind:'softwareSystem',name:'Database'},{id:'p',kind:'person',name:'Operator'}];
  for(const n of nodes)n.attributes={...n.attributes,'context.areas':[{id:'area-'+n.id,name:n.name}]};
  const children=['one','two'].map(id=>({id,name:id,attributes:{'context.owner':'app'}}));
  for(const view of [C4Layout.plan(nodes,[]),C4Layout.plan([...nodes,...children],[],'app')]){
    for(const object of view.objects){
      const visible=view.visibleAreas(new Set([object.id]));
      assert(visible.size);
      const floor=view.areas.find(a=>visible.has(a.id)&&a.children.includes(object));
      assert(floor);
      assert(object.x>=floor.x && object.z>=floor.z);
      assert(object.x+object.width<=floor.x+floor.width && object.z+object.depth<=floor.z+floor.depth);
    }
  }
});

test('relation flow orders declared areas and their contents without inventing boundaries',()=>{
  const node=(id,area)=>({id,name:id,attributes:{'context.areas':[{id:area,name:area}]}});
  const nodes=[node('z','entry'),node('a','core'),node('m','core'),node('b','storage')];
  const edges=[['z','m'],['m','a'],['a','b']].map(([source,target])=>({id:source+target,source,target}));
  const forward=C4Layout.plan(nodes,edges), repeat=C4Layout.plan([...nodes].reverse(),[...edges].reverse());
  const horizontal=(plan,id)=>{const [x,z]=plan.positions.get(id);return x-z;};
  assert.deepEqual(forward.positions,repeat.positions);
  assert.deepEqual(new Set(forward.areas.map(a=>a.id)),new Set(['entry','core','storage']));
  assert(horizontal(forward,'entry')<horizontal(forward,'storage'));
  assert(horizontal(forward,'m')<horizontal(forward,'a'));
  assert.equal(C4Layout.plan([{id:'unassigned',name:'Unassigned'}],[]).areas.length,0);
});
