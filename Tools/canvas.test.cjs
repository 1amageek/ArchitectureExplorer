'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.join(__dirname,'../Sources/ArchitectureGraph/Resources');
const model=require(path.join(root,'canvas-model.js'));global.ArchitectureCanvasModel=model;
const layout=require(path.join(root,'layout-model.js')),ELK=require(path.join(root,'elk.bundled.js'));
const fixtures=path.join(__dirname,'../Tests/ArchitectureTests/Fixtures/Canvas');
for(const kind of model.kinds)test('Canvas projection/layout: '+kind,async()=>{
 const document={...JSON.parse(fs.readFileSync(path.join(fixtures,kind+'.json'))),sourceDigest:'digest',format:'json',sourceName:kind+'.json',lanes:kind==='sequence'?JSON.parse(fs.readFileSync(path.join(fixtures,kind+'.json'))).lanes:[]};
 const session={viewSessionID:'session',revision:1,document,state:{collapsed:[],filter:{},layout:'auto'}},view=model.view(session),before=JSON.stringify(document);
 const request={nodes:view.nodes,edges:view.edges,canvas:view.canvas,generation:1,queryID:'session',snapshotID:'digest'};
 const result=await layout.layout(request,new ELK());assert.equal(result.nodes.length,view.nodes.length);assert.equal(JSON.stringify(document),before);
 for(const box of result.nodes)for(const key of ['x','y','width','height'])assert.ok(Number.isFinite(box[key]));
 for(const edge of view.edges)assert.ok(view.nodes.some(n=>n.id===edge.source)&&view.nodes.some(n=>n.id===edge.target));
 if(kind==='sequence'){assert.equal(result.nodes.filter(n=>n.group).length,2);const a=result.nodes.find(n=>n.id==='a'),b=result.nodes.find(n=>n.id==='b');assert.equal(a.y,b.y);assert.ok(a.x<b.x);}
 else assert.equal(result.nodes.find(n=>n.id==='b').width,264);
});
test('collapse projects visible edges without altering original endpoints or losing provenance',()=>{
 const document={kind:'hierarchy',title:'Hierarchy',format:'json',sourceDigest:'d',nodes:[{id:'g',label:'Group',role:'group'},{id:'child',label:'Child',role:'node',parentID:'g'},{id:'outside',label:'Outside',role:'node'}],edges:[{id:'edge',source:'child',target:'outside',label:'Use',role:'dependsOn'}],lanes:[]};
 const result=model.view({viewSessionID:'s',document,state:{collapsed:['g'],filter:{}}});assert.deepEqual(result.nodes.map(n=>n.id),['g','outside']);const edge=result.edges.find(n=>n.id==='edge');assert.equal(edge.source,'g');assert.equal(edge.canvas.source,'child');assert.equal(document.edges[0].source,'child');
});
test('file labels are escaped and static SVG remains image data',()=>{
 const node={name:'<script>alert(1)</script>',kind:'canvas',canvas:{role:'state',details:{status:'<img>'}}};const image=model.card(node,264,88,false,{text:'#000',secondary:'#555',header:'#eee',divider:'#aaa'},s=>s);const svg=decodeURIComponent(image.split(',',2)[1]);assert.ok(svg.includes('&lt;script&gt;'));assert.ok(!svg.includes('<script>'));
 const view=model.view({viewSessionID:'svg',document:{kind:'relations',format:'svg',title:'Vector',sourceDigest:'s',nodes:[],edges:[],lanes:[],svg:'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 100"><text>Literal</text></svg>'},state:{}});assert.equal(view.nodes.length,1);assert.deepEqual(model.size(view.nodes[0]),{width:960,height:240});
});

test('self messages have separate endpoints, routed returns and visible interaction fragments',async()=>{
 const document={kind:'sequence',title:'Self call',format:'json',sourceDigest:'d',lanes:[{id:'worker',label:'Worker'}],nodes:[{id:'send',label:'call',role:'send',laneID:'worker',order:0},{id:'receive',label:'call',role:'receive',laneID:'worker',order:0}],edges:[{id:'self',source:'send',target:'receive',label:'call',role:'message'}],metadata:{fragments:[{kind:'loop',label:'until done',start:0,end:1}]}};
 const view=model.view({viewSessionID:'s',document,state:{}}),result=await layout.layout({nodes:view.nodes,edges:view.edges,canvas:view.canvas},new ELK());
 const a=result.nodes.find(n=>n.id==='send'),b=result.nodes.find(n=>n.id==='receive');assert.ok(a.y+a.height<b.y);assert.ok(result.routes.some(r=>r.id==='self'&&r.points.length===4));const fragment=result.nodes.find(n=>n.id==='__fragment:0');assert.ok(fragment.y<a.y&&fragment.y+fragment.height>b.y+b.height);
});
test('sequence notes retain readable labels and occupy a complete ordered row',async()=>{
 const document={kind:'sequence',title:'Note',format:'json',sourceDigest:'d',lanes:[{id:'a',label:'Actor'}],nodes:[{id:'note',label:'Important state',role:'note',laneID:'a',order:0},{id:'event',label:'next',role:'send',laneID:'a',order:1}],edges:[]};
 const view=model.view({viewSessionID:'s',document,state:{}}),result=await layout.layout({nodes:view.nodes,edges:view.edges,canvas:view.canvas},new ELK()),note=result.nodes.find(n=>n.id==='note'),event=result.nodes.find(n=>n.id==='event');assert.equal(note.width,240);assert.ok(note.y+note.height<event.y);
 const svg=decodeURIComponent(model.card(view.nodes.find(n=>n.id==='note'),240,88,false,{text:'#111',secondary:'#555',header:'#eee',divider:'#aaa'},s=>s).split(',',2)[1]);assert.ok(svg.includes('Important state'));
});

test('formal kind controls diagram presentation and never implies proof status',()=>{
  assert.deepEqual(model.formalModel({title:'Interval',metadata:{formalKind:'leanDeclarations'}}),
    {title:'Lean declarations · Interval',kind:'proofDependencies'});
  assert.equal(model.formalModel({title:'Interval',metadata:{formalKind:'toString'}}),null);
  assert.equal(model.formalModel({kind:'counterexample'}),null);
});

test('counterexample steps follow observed transitions, rejecting partial and ambiguous traces',()=>{
  const graph={metadata:{providerMetadata:{formalKind:'counterexample'}},nodes:['c','b','a'].map(id=>({id})),
    edges:[{source:'b',target:'c',role:'observedTransition'},{source:'a',target:'b',role:'observedTransition'},{source:'c',target:'b',role:'loopBack'}]};
  assert.deepEqual(model.traceOrder(graph),['a','b','c']);
  for(const edges of [[],[...graph.edges,{source:'a',target:'c',role:'observedTransition'}],
    [...graph.edges,{source:'c',target:'a',role:'observedTransition'}]]){
    assert.deepEqual(model.traceOrder({...graph,edges}),[]);
  }
  for(const flags of [{hasMorePages:true},{selectionComplete:false},{frontierCount:1},{pageComplete:false}]){
    assert.deepEqual(model.traceOrder({...graph,metadata:{providerMetadata:{formalKind:'counterexample',...flags}}}),[]);
  }
});

test('a verified postcondition binds complete tokens to the selected call and keeps its original formula',async()=>{
  const call='visible(é, clock < end)',bytes=Buffer.from(call);
  const range=text=>({start:bytes.indexOf(text)+12,end:bytes.indexOf(text)+12+Buffer.byteLength(text)});
  const site={entityID:'file',path:'Sources/Clock.swift',line:9,digest:'digest',start:12,end:12+bytes.length,
    ifCondition:true,arguments:[range('é'),range('clock < end')]};
  const record={claimID:'claim',bundleID:'bundle',name:'bounds',entry:'visible',domain:'generatedModel.lean.quantified',
    outcome:'proved',scope:'model',translation:'unvalidated',requires:'true',ensures:'result == (arg0 && arg1)',
    sourceBindings:{parameters:['started','beforeEnd'],sites:[{...site,entityID:'test-file',path:'Tests/ClockTests.swift',ifCondition:false},site]}};
  const [first,second]=model.conditionGraphs({id:'report',kind:'annotation',data:{attributes:{conditions:[record]}}});
  assert.notEqual(first.id,second.id);assert.equal(first.site.path,site.path);
  const reply={snapshotID:'snapshot',anchor:{path:site.path,digest:'digest',startByte:12,endByte:site.end},text:call};
  const display=await model.readConditionCall(first,async(method,params)=>{
    assert.equal(method,'source.read');assert.equal(params.snapshotID,'snapshot');return reply;
  },'snapshot');
  const post=display.data.nodes.find(n=>n.id==='ensures');
  assert.equal(post.label,'result == (started && beforeEnd)');
  assert.equal(post.details.original,record.ensures);
  assert.deepEqual(post.details.parameters.map(p=>p.expression),['é','clock < end']);
  const card={name:post.label,kind:'canvas',canvas:post},size=model.size(card);
  const svg=decodeURIComponent(model.card(card,size.width,size.height,false,{},s=>s).split(',')[1]);
  for(const text of ['arg0 · started','clock &lt; end','If condition · Clock.swift:9'])assert.ok(svg.includes(text));
  const stale=await model.readConditionCall(first,async()=>({...reply,snapshotID:'other'}),'snapshot');
  const stalePost=stale.data.nodes.find(n=>n.id==='ensures');
  assert.match(stalePost.details.sourceIssue,/snapshot/);assert.equal(stalePost.details.parameters[0].expression,undefined);
});

test('the persistent result summarizes the published claim even when the graph is filtered',()=>{
  const condition={claimID:'claim',bundleID:'bundle',name:'interval',entry:'visible',domain:'generatedModel.lean.quantified',
    outcome:'proved',translation:'UNVALIDATED',scope:'All typed inputs under explicit preconditions',requires:'true',ensures:'result == start'};
  const [graph]=model.conditionGraphs({id:'report',kind:'annotation',data:{attributes:{conditions:[condition]}}});
  const document={...graph.data,metadata:{providerMetadata:graph.data.metadata}};
  const view=model.view({viewSessionID:'session',document,state:{filter:{text:'absent'}}});
  assert.equal(view.nodes.length,0);
  assert.deepEqual(view.canvas.verification,{backend:'Lean',title:'Proved',tone:'positive',symbol:'✓',subject:'interval',
    formula:'result == start',scope:condition.scope,translation:'Equivalence to source not validated'});
  for(const [outcome,title] of [['unproved','Unproved'],['counterexample','Counterexample'],['modelChecked','Model checked'],['newStatus','Inconclusive']]){
    document.metadata.providerMetadata.outcome=outcome;document.nodes[0].details.outcome=outcome;
    assert.equal(model.verificationSummary(document).title,title);
  }
  document.metadata.providerMetadata.bundleID='other';
  assert.equal(model.verificationSummary(document).title,'Inconclusive');
});

test('structural graphs keep generated models distinct from proved conditions',()=>{
  const document={nodes:[],metadata:{providerMetadata:{formalKind:'leanDeclarations',outcome:'proved'}}};
  assert.equal(model.verificationSummary(document).title,'Lean declarations');
  document.metadata.providerMetadata={formalKind:'tlaSpecification',modelStatus:'generatedUnverified',outcome:'notEvaluated'};
  assert.equal(model.verificationSummary(document).title,'Unverified');
  assert.equal(model.verificationSummary(document).subject,'No verification conditions');
  document.metadata.providerMetadata.producer='swift-formal/swift-expression-v1';
  assert.equal(model.verificationSummary(document).title,'Partial model');
  assert.match(model.verificationSummary(document).scope,/64-bit Swift integers/);
  assert.equal(model.verificationSummary({metadata:{},nodes:[]}),null);
});

test('specification verdict counts all declared obligations, including hidden failures',()=>{
  const input={kind:'proofDependencies',nodes:['a','b','result','boundary'].map(id=>({id,label:id,role:'node'})),edges:[]};
  function present(checks,openQuestions=['boundary']){
    const document={...input,metadata:{specVerification:{checks,openQuestions}}};
    return model.view({viewSessionID:'s',document,state:{filter:{text:'a'}}}).canvas.specReport;
  }
  const a={id:'a1',nodeID:'a',evidenceID:'result',outcome:'passed'},b={...a,id:'b1',nodeID:'b'};
  assert.equal(present([a,b]).title,'2 of 2 checks passed');
  assert.deepEqual(present([a,b]).open,['boundary']);
  assert.equal(present([a,{...b,outcome:'failed'}]).tone,'negative');
  assert.equal(present([a,{...b,outcome:'notVerified'}]).tone,'neutral');
  for(const invalid of [[],[a,a],[{...a,evidenceID:'missing'}],[{...a,outcome:'success'}]]){
    assert.equal(present(invalid).tone,'neutral');
  }
  assert.equal(present([a],['missing']).tone,'neutral');
  assert.equal(model.view({viewSessionID:'s',document:input}).canvas.specReport,null);
});

test('whole-project verdict requires the complete inventory and both phases with correspondence',()=>{
  const phases=['specification','implementation','correspondence'];
  const requirements=['A01','A02'].map(id=>({id,nodeID:id,...Object.fromEntries(phases.map(phase=>[phase,{outcome:'passed',claims:[id+phase]}]))}));
  const evidence=requirements.flatMap(row=>phases.map(phase=>({id:row.id+phase,requirements:[row.id],outcome:'passed',domain:phase==='specification'?'specification.lean':phase==='implementation'?'generatedModel.lean.quantified':'translation.validated'})));
  const metadata={verificationReport:{schemaVersion:1,inventory:['A01','A02'],requirements,evidence}};
  const document={kind:'proofDependencies',nodes:['A01','A02'].map(id=>({id,label:id,role:'requirement'})),edges:[],metadata};
  const result=()=>model.view({viewSessionID:'s',document,state:{filter:{text:'A01'}}}).canvas.specReport;
  assert.equal(result().title,'All 2 project requirements verified');
  requirements[1].correspondence={outcome:'notVerified',claims:[],detail:'No source correspondence'};
  assert.equal(result().tone,'neutral');
  assert.match(result().title,/0 of 2|1 of 2/);
  assert.equal(result().scope,'Specification 2/2 · Code 2/2 · Correspondence 1/2');
  requirements[1].implementation={outcome:'failed',claims:[]};
  assert.equal(result().tone,'negative');
  requirements.pop();
  assert.equal(result().title,'Invalid project verification report');
});

test('project reports cannot promote a regression or unvalidated translation to proof',()=>{
  const requirement={id:'R01',nodeID:'R01',specification:{outcome:'passed',claims:['s']},implementation:{outcome:'passed',claims:['c']},correspondence:{outcome:'passed',claims:['t']}};
  const evidence=[{id:'s',requirements:['R01'],domain:'specification.lean',outcome:'passed'},{id:'c',requirements:['R01'],domain:'generatedModel.lean.quantified',outcome:'passed'},{id:'t',requirements:['R01'],domain:'translation.unvalidated',outcome:'passed'}];
  const document={nodes:[{id:'R01',label:'R01'}],metadata:{verificationReport:{schemaVersion:1,inventory:['R01'],requirements:[requirement],evidence}}};
  assert.equal(model.specificationReport(document).summary.title,'Invalid project verification report');
  evidence[2].domain='translation.validated';evidence[1].domain='regression.unit';
  assert.equal(model.specificationReport(document).summary.title,'Invalid project verification report');
  evidence[1].domain='generatedModel.lean.quantified';evidence[1].outcome='unknown';
  assert.equal(model.specificationReport(document).summary.title,'Invalid project verification report');
  document.metadata.verificationReport.evidence=[null];
  assert.equal(model.specificationReport(document).summary.title,'Invalid project verification report');
});

test('reviewed project gates prevent complete evidence from becoming an unreviewed project success',()=>{
  const phases=['specification','implementation','correspondence'],order=['requirements',...phases,'integration'];
  const requirement={id:'R01',nodeID:'R01',...Object.fromEntries(phases.map(phase=>[phase,{outcome:'passed',claims:[phase]}]))};
  const evidence=phases.map(phase=>({id:phase,requirements:['R01'],outcome:'passed',domain:phase==='specification'?'specification.lean':phase==='implementation'?'generatedModel.lean':'translation.validated'}));
  const stages=order.map(id=>({id,nodeID:'gate-'+id,status:'passed',evidence:'passed',review:'passed'}));
  const report={schemaVersion:2,inventory:['R01'],requirements:[requirement],evidence,outcome:'passed',workflow:{schemaVersion:1,stages,outcome:'passed',returnTo:null}};
  const document={kind:'proofDependencies',nodes:[{id:'R01',label:'Contract'},...stages.map(stage=>({id:stage.nodeID,label:stage.id,role:'workflow gate'}))],edges:[],metadata:{verificationReport:report}};
  const present=()=>model.specificationReport(document);
  assert.equal(present().summary.tone,'positive');
  stages[1].status='incomplete';stages[1].review='incomplete';
  for(const stage of stages.slice(2))stage.status='blocked';
  report.outcome='incomplete';report.workflow.outcome='incomplete';report.workflow.returnTo='specification';
  assert.equal(present().summary.tone,'neutral');
  assert.match(present().summary.title,/0 of 1/);
  assert.match(present().summary.scope,/Return to specification/);
  assert.notEqual(present().marks.get('R01').tone,'positive');
  assert.equal(present().marks.get('gate-requirements').tone,'positive');
  assert.equal(model.view({viewSessionID:'s',document,state:{filter:{text:'Contract'}}}).canvas.specReport.tone,'neutral');
  stages[2].status='passed';
  assert.equal(present().summary.title,'Invalid project verification report');
  delete report.workflow;
  assert.equal(present().summary.title,'Invalid project verification report');
});
