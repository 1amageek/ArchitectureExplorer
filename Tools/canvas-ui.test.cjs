'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
function setup(){
 const elements=new Map();const element=()=>({value:'',hidden:false,disabled:false,addEventListener(){},replaceChildren(){},append(){},click(){}});
 const document={getElementById:id=>{if(!elements.has(id))elements.set(id,element());return elements.get(id);},createElement:()=>element()};
 const sandbox={window:{addEventListener(){},ArchitectureCanvasModel:require("../Sources/ArchitectureGraph/Resources/canvas-model.js")},document,setTimeout,clearTimeout,Promise,URLSearchParams,location:{hash:''}};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../Sources/ArchitectureGraph/Resources/canvas-ui.js'),'utf8'),sandbox);
 let renders=0,updates=0;const ui=new sandbox.window.ArchitectureCanvasUI({saved:false,present(){renders++;},update(){updates++;},problem(error){throw error;},ready:()=>true});
 return {ui,get renders(){return renders;},get updates(){return updates;}};
}
const session=(revision,state={})=>({viewSessionID:'one',revision,document:{sourceDigest:'source',kind:'relations'},state:{filter:{},collapsed:[],layout:'auto',selection:[],geometry:[],...state}});
test('session navigation enters and paints before reading and detaches late success or failure',async()=>{
 const {ui}=setup(),events=[];let paint,reply;
 ui.context.enter=(target,push)=>{events.push('enter:'+target.id);return {paint:new Promise(resolve=>{paint=resolve;}),current:()=>true};};
 ui.context.rpc=()=>{events.push('read');return new Promise((resolve,reject)=>{reply={resolve,reject};});};
 ui.present=()=>events.push('present');ui.context.error=()=>events.push('error');
 const load=ui.openSession('one',true);assert.deepEqual(events,['enter:one']);
 paint();await new Promise(setImmediate);assert.deepEqual(events,['enter:one','read']);
 ui.leaveLocal();reply.resolve(session(1));await load;assert.ok(!events.includes('present'));
 const failed=ui.openSession('one',true);paint();await new Promise(setImmediate);ui.leaveLocal();reply.reject(Error('obsolete'));
 await failed;assert.ok(!events.includes('error'));
});
test('diagram resolution and file bytes start after the destination and retain current failures for retry',async()=>{
 const {ui}=setup(),events=[];let failure;
 ui.context.enter=()=>{events.push('enter');return {paint:Promise.resolve(),current:()=>true};};
 ui.context.error=(load,error,retry)=>{failure={error,retry};events.push('error');};
 ui.context.problem=()=>{};ui.list=async()=>{};
 const data={title:'Model',nodes:[],edges:[]};
 await assert.rejects(ui.contribution(data,{publicationID:'p'},'c',()=>true,async()=>{events.push('resolve');throw Error('source unavailable');}),/source unavailable/);
 assert.deepEqual(events,['enter','resolve','error']);assert.equal(typeof failure.retry,'function');
 events.length=0;
 await assert.rejects(ui.files([{name:'bad.json',size:4,arrayBuffer:async()=>{events.push('bytes');throw Error('read denied');}}]),/read denied/);
 assert.deepEqual(events,['enter','bytes','error']);
});
test('reopening the same session cannot execute queued commands from the previous navigation',async()=>{
 const {ui}=setup();ui.present(session(1));let release,mutations=0;
 ui.queue=new Promise(resolve=>{release=resolve;});ui.mutate=async()=>{mutations++;return session(2);};
 const old=ui.command('canvas.setCamera',{camera:{zoom:2,pan:{x:0,y:0}}});
 ui.leaveLocal();ui.present(session(1));release();
 await assert.rejects(old,error=>error.code==='VIEW_SUPERSEDED');assert.equal(mutations,0);
 let reply;ui.mutate=()=>new Promise(resolve=>{reply=resolve;});
 const inFlight=ui.command('canvas.select',{ids:['old']});await new Promise(setImmediate);
 ui.leaveLocal();ui.present(session(1));reply(session(2,{selection:['old']}));
 await assert.rejects(inFlight,error=>error.code==='VIEW_SUPERSEDED');assert.equal(ui.session.revision,1);
});
test('camera/selection acknowledgments do not rebuild diagram artwork or rerun layout',()=>{
 const page=setup();page.ui.present(session(1));assert.equal(page.renders,1);
 page.ui.present(session(2,{camera:{zoom:1,pan:{x:3,y:4}}}));assert.equal(page.renders,1);assert.equal(page.updates,1);
 page.ui.present(session(3,{selection:['a']}));assert.equal(page.renders,1);assert.equal(page.updates,2);
 page.ui.present(session(4,{filter:{text:'new'}}));assert.equal(page.renders,2);
});
test('late reads cannot roll back acknowledged session revision',()=>{
 const page=setup();page.ui.present(session(4));page.ui.present(session(2));assert.equal(page.renders,1);assert.equal(page.updates,0);assert.equal(page.ui.session.revision,4);
 const replacement=session(5);replacement.document.sourceDigest='changed';page.ui.present(replacement);assert.equal(page.renders,2);
});

test('switching documents invalidates an absent selection so the Inspector clears old details',()=>{
 const page=setup();page.ui.present(session(1,{selection:['old']}));page.ui.inspectionKey='old';
 const next=session(1);next.viewSessionID='two';page.ui.present(next,true);assert.equal(page.ui.inspectionKey,null);assert.notEqual(page.ui.inspectionKey,next.state.selection[0]);
});

test('rejected diagram controls restore the last acknowledged values',async()=>{
 const page=setup();page.ui.present(session(1));page.ui.kind.value='sequence';page.ui.layout.value='sequence';page.ui.mutate=async()=>{throw Error('Unsupported sequence layout');};
 await assert.rejects(page.ui.command('canvas.setLayout',{kind:'sequence',layout:'sequence'}));assert.equal(page.ui.kind.value,'relations');assert.equal(page.ui.layout.value,'auto');assert.equal(page.ui.session.revision,1);
});

test('formal links use the committed snapshot binding and keep provider metadata isolated on open',async()=>{
 const model=require('../Sources/ArchitectureGraph/Resources/canvas-model.js');
 const make=(tag,value)=>({tag,value,dataset:{},childNodes:[],isConnected:true,
   set textContent(v){this.value=v;},get textContent(){return this.value;},
   append(...items){this.childNodes.push(...items);},replaceChildren(...items){this.childNodes=items;},
   setAttribute(){}});
 const document={createElement:make,getElementById:()=>null,body:make('body')};
 const window={ArchitectureCanvasModel:model,addEventListener(){}};
 const sandbox={window,document,Promise,setTimeout,clearTimeout};
 for(const file of ['extensions','canvas-ui'])vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../Sources/ArchitectureGraph/Resources/'+file+'.js'),'utf8'),sandbox);
 const view={workspaceID:'workspace',snapshotID:'snapshot'},binding={...view,entityIDs:['source'],factIDs:['relation']};
 const graph={id:'test:graph',binding,kind:'graph',data:{title:'Model',metadata:{formalKind:'leanProofTerm',architectureIR:{unexpected:true}},nodes:[],edges:[]}};
 const unbound={...graph,id:'test:workspace-model',binding:{...binding,entityIDs:[],factIDs:[]},data:{...graph.data,title:'Workspace model'}};
 const note={id:'test:coverage',binding,kind:'view',data:{kind:'table',columns:['Scope'],rows:[['Source']]}};
 const annotation={id:'test:claim',binding,kind:'annotation',data:{claim:'Recorded finding',reportedStatus:'partial'}};
 const pub={publicationID:'published',applicability:'unknown',binding,contributions:[graph,note,annotation]};
 let opened;
 const ui=new window.ArchitectureCanvasUI({});ui.list=async()=>{};ui.present=()=>{};
 ui.mutate=async(method,params)=>{assert.equal(method,'canvas.open');opened=JSON.parse(params.text);return {document:opened};};
 const extensions=new window.ArchitectureExtensionUI({view:()=>view,rpc:async method=>method==='extensions.pending'?[]:{publications:[
   {...pub,applicability:'stale'},{...pub,binding:{...binding,snapshotID:'older'}},{...pub,binding:{...binding,workspaceID:'other'}},pub,{...pub,binding:unbound.binding,contributions:[unbound]}
 ]},onCanvas:(...args)=>ui.contribution(...args)});
 extensions.render=()=>{};
 const slots=[{entity:'source'},{fact:'relation'},{entity:'unrelated'},{text:'proof term'},{},{entity:'source',nodeMenu:true},{entity:'unrelated',nodeMenu:true}].map(filter=>{
   const host=make('div');extensions.modelSlot(host,filter);return host.childNodes[0];
 });
 await extensions.refresh();
 assert.deepEqual(slots.map(slot=>slot.childNodes.find(child=>child.className==='action-row')?.childNodes.length||0),[3,1,0,2,2,3,0]);
 assert.equal(slots[0].childNodes[1].childNodes[2].textContent,'partial');
 assert.equal(slots[5].childNodes.length,1);
 const header=slots[5].childNodes[0].childNodes;
 assert.deepEqual(header.map(item=>item.textContent),['Lean proof term · Model','test:coverage','Recorded finding']);
 assert.deepEqual(header.map(item=>item.dataset.icon),['proofDependencies','table','document']);
 const display=[];
 extensions.showContribution=(title,publication,entry)=>{
   const content=make('section');extensions.contribution(content,entry,publication);
   display.push({title,content});
 };
 await header[1].onclick();await header[2].onclick();
 assert.equal(display[0].content.childNodes[0].childNodes[1].tag,'table');
 assert.equal(display[1].content.childNodes[0].childNodes[2].textContent,'Recorded finding');
 await slots[0].childNodes[1].childNodes[0].onclick();
 assert.equal(opened.title,'Lean proof term · Model');assert.equal(opened.kind,'proofDependencies');
 assert.deepEqual(opened.metadata.binding,binding);assert.equal(opened.metadata.publicationID,'published');
 assert.equal(opened.metadata.architectureIR,undefined);assert.deepEqual(opened.metadata.providerMetadata,graph.data.metadata);
});

test('verification opens the published model before confirmation, then follows only the confirmed run',async()=>{
 const make=tag=>({tag,dataset:{},childNodes:[],append(...items){this.childNodes.push(...items);},replaceChildren(){this.childNodes=[];},setAttribute(){},remove(){}});
 const toolbar=make('div');toolbar.after=()=>{};
 const document={createElement:make,getElementById:id=>id==='canvas-tools'?toolbar:null,body:make('body')};
 const window={ArchitectureCanvasModel:require('../Sources/ArchitectureGraph/Resources/canvas-model.js')};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../Sources/ArchitectureGraph/Resources/extensions.js'),'utf8'),{window,document,Promise,clearTimeout,setTimeout});
 const view={workspaceID:'workspace',snapshotID:'snapshot'},entity={id:'symbol',name:'Selected',kind:'type'};
 const binding={...view,inputManifestDigest:'manifest',entityIDs:[entity.id],factIDs:[]};
 const specification='Verification/Selected/properties.json',definition={id:'verify-model',inputSchemaID:'invar.verify-model.v2'};
 const registration={id:'registration',providerID:'invar',connected:true,permissions:['actions.receive'],manifest:{actions:[definition],displayName:'Invar'}};
 const graph=kind=>({id:kind,binding,kind:'graph',data:{metadata:{formalKind:kind},nodes:[{id:'root'}],edges:[]}});
 const annotation=(claimID,name,entry)=>({id:'invar:report',binding,kind:'annotation',data:{attributes:{conditions:[{claimID,name,entry,bundleID:'bundle',domain:'generatedModel.lean.quantified',outcome:'unproved',scope:'Model only',translation:'unvalidated',requires:'true',ensures:'result == arg0'}]}}});
 const first=annotation('one','within','visible'),second=annotation('two','outside','hidden');
 const published={publicationID:'previous',providerID:'invar',applicability:'unknown',binding,generation:4,runID:'old',contributions:[graph('leanDeclarations'),graph('irControlFlow'),graph('tlaSpecification'),first,second]};
 const next={...published,publicationID:'verified',runID:'confirmed',generation:6};
 const job={requestID:'request',actionID:'verify-model',providerID:'invar',binding,state:'completed',runID:'confirmed'};
 let pages=[{publications:[published]}];const opened=[],calls=[];
 const extension=new window.ArchitectureExtensionUI({view:()=>view,onCanvas:async(data,p,id,active)=>{assert.ok(active());opened.push([p.runID,id]);},rpc:async(method,params)=>{
   if(method==='inputs.manifest')return {manifest:{files:{[specification]:'digest'}},inputManifestDigest:'manifest'};
   if(method==='graph.search')return {nodes:[entity]};
   assert.equal(method,'extensions.view');return pages[Number(params.cursor||0)];
 }});
 extension.modelView=view;extension.data={registrations:[registration]};
 extension.mutate=async(method,params)=>{
   calls.push(method);
   if(method==='actions.confirm'){assert.equal(params.token,'approval');return {};}
   assert.deepEqual(Array.from(params.binding.entityIDs),[entity.id]);assert.equal(params.arguments.specification,specification);
   return {executable:'invar',intent:{...params,requestID:'request',authorizationToken:'approval',requestFingerprint:'fingerprint'}};
 };
 const host=make('div');extension.modelCommand(host,entity,()=>{});extension.modelCommand(host,{...entity,id:'other',name:'Missing'},()=>{});
 await new Promise(setImmediate);
 await host.childNodes[1].onclick();assert.equal(extension.review.panel.dataset.state,"unavailable");assert.match(extension.review.status.textContent,/Select an implementation/);assert.equal(host.childNodes[0].disabled,false);
 assert.equal(host.childNodes[0].textContent,'Verify model');
 await host.childNodes[0].onclick();assert.deepEqual(calls,['actions.prepare']);
 const one='invar:report-bundle-one',two='invar:report-bundle-two';
 assert.deepEqual(opened,[['old',one]]);
 const review=extension.review;
 assert.deepEqual(review.selector.childNodes.map(option=>option.textContent),['Verification condition · within · Lean','Verification condition · outside · Lean','TLA+ specification','Lean declarations']);
 review.selector.value=two;await review.selector.onchange();
 const focus=window.ArchitectureCanvasModel.conditionGraphs(second)[0].data;
 assert.deepEqual(Array.from(focus.nodes,n=>n.label),['outside','hidden','true','result == arg0']);
 assert.deepEqual(Array.from(focus.edges,e=>[e.source,e.target]),[['obligation','entry'],['obligation','requires'],['obligation','ensures']]);
 review.selector.value='leanDeclarations';await review.selector.onchange();
 pages=[{actions:[job],publications:[{...next,runID:'different'}],nextCursor:'1'},{publications:[next]}];
 await review.panel.childNodes[0].childNodes[3].onclick();
 assert.deepEqual(calls,['actions.prepare','actions.confirm']);
 assert.deepEqual(opened,[['old',one],['old',two],['old','leanDeclarations'],['confirmed',one]]);
 assert.equal(review.status.textContent,'Latest verification result');
 pages=[{actions:[job],publications:[{...next,contributions:[graph('irControlFlow')]}]}];
 await extension.followVerification(review,'request');
 assert.match(review.status.textContent,/No condition evidence/);assert.equal(opened.length,4);
 pages=[{actions:[job],publications:[{...next,contributions:[graph('tlaSpecification')]}]}];
 await extension.followVerification(review,'request');assert.equal(opened.length,5);
 review.selector.value='tlaSpecification';await review.selector.onchange();assert.equal(opened.at(-1)[1],'tlaSpecification');
 extension.closeModel();await extension.followVerification(review,'request');assert.equal(opened.length,6);
});

test('source-only menu click confirms one draft and reopens the unverified TLA+ and Lean Canvas without another dispatch',async()=>{
 const make=tag=>({tag,dataset:{},childNodes:[],append(...items){this.childNodes.push(...items);},replaceChildren(...items){this.childNodes=items;},setAttribute(){},remove(){}});
 const toolbar=make('div');toolbar.after=()=>{};
 const document={createElement:make,getElementById:id=>id==='canvas-tools'?toolbar:null,body:make('body')};
 const window={ArchitectureCanvasModel:require('../Sources/ArchitectureGraph/Resources/canvas-model.js')};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../Sources/ArchitectureGraph/Resources/extensions.js'),'utf8'),{window,document,Promise,setTimeout,clearTimeout});
 const view={workspaceID:'workspace',snapshotID:'source'},entity={id:'entity',name:'visible',kind:'function'};
 const binding={...view,inputManifestDigest:'manifest',entityIDs:[entity.id],factIDs:[]};
 const registration={id:'grant',providerID:'invar',connected:true,permissions:['actions.receive'],manifest:{actions:[{id:'verify-model',inputSchemaID:'invar.verify-model.v2'}]}};
 const graph=kind=>({id:kind,binding,kind:'graph',data:{title:'Program',metadata:{formalKind:kind,modelStatus:'generatedUnverified',outcome:'notEvaluated'},nodes:[{id:'a'}],edges:[]}});
 const publication={providerID:'invar',binding,runID:'draft',generation:1,applicability:'unknown',contributions:['tlaSpecification','leanDeclarations'].map(graph)};
 const job={requestID:'request',actionID:'verify-model',providerID:'invar',binding,state:'completed',runID:'draft'};
 const data={registrations:[registration],publications:[],actions:[]},calls=[],opened=[];
 const extension=new window.ArchitectureExtensionUI({view:()=>view,rpc:async method=>{
   if(method==='inputs.manifest')return {manifest:{files:{}},inputManifestDigest:'manifest'};
   assert.equal(method,'extensions.view');return data;
 },onCanvas:async value=>opened.push(window.ArchitectureCanvasModel.formalModel(value).title)});
 extension.data=data;extension.modelView=view;
 extension.mutate=async(method,params)=>{
   calls.push(method);
   if(method==='actions.prepare'){
     assert.equal(Object.keys(params.arguments).length,0);assert.deepEqual(Array.from(params.binding.entityIDs),[entity.id]);
     return {executable:'invar',intent:{...params,authorizationToken:'confirmation',requestFingerprint:'pinned',requestID:'request',deadline:Date.now()/1000+300}};
   }
   assert.equal(params.token,'confirmation');data.publications=[publication];data.actions=[job];
 };
 const open=async()=>{const host=make('div');extension.modelCommand(host,entity,()=>{});await new Promise(setImmediate);assert.equal(host.childNodes[0].disabled,false);await host.childNodes[0].onclick();};
 await open();assert.deepEqual(calls,['actions.prepare','actions.confirm']);
 assert.match(extension.review.status.textContent,/Unverified/);
 assert.deepEqual(opened,['TLA+ specification · Program · Unverified']);
 extension.review.selector.value='leanDeclarations';await extension.review.selector.onchange();
 assert.equal(opened.at(-1),'Lean declarations · Program · Unverified');
 await open();assert.equal(extension.review.status.textContent,'Unverified · No verification conditions');assert.equal(opened.length,3);assert.deepEqual(calls,['actions.prepare','actions.confirm']);
 extension.closeModel();
 data.publications=[];
 const early=make('div');extension.modelCommand(early,entity,()=>{});
 await early.childNodes[0].onclick();
 assert.equal(calls.filter(m=>m==='actions.confirm').length,1);
 assert.match(extension.review.status.textContent,/Ready to generate/);
 const review=extension.review;
 data.attempts=[{runID:'draft',completion:'partial',diagnostic:'Unsupported source at line 5'}];
 extension.mutate=async method=>{assert.equal(method,'actions.confirm');};
 await review.panel.childNodes[0].childNodes[3].onclick();
 assert.equal(review.panel.dataset.state,'unavailable');assert.equal(review.heading.textContent,'Model unavailable');
 assert.equal(review.status.textContent,'Unsupported source at line 5');assert.equal(opened.length,3);
 extension.closeModel();
});

test('verification presents the selected source before reading results and ignores replies after Back',async()=>{
 const element=()=>({dataset:{},append(){},remove(){},setAttribute(){}});
 const document={createElement:element,body:element(),getElementById:id=>id==='canvas-tools'?{after(){}}:null};
 const window={};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../Sources/ArchitectureGraph/Resources/extensions.js'),'utf8'),{window,document,clearTimeout});
 const view={workspaceID:'workspace',snapshotID:'snapshot'},entity={id:'entity',name:'Selected'};
 let painted,releaseResult,reads=0;
 const extension=new window.ArchitectureExtensionUI({
   view:()=>view,
   enterVerification(source,selection){
     assert.equal(source,view);assert.equal(selection,entity);
     assert.equal(extension.review.panel.dataset.presentation,'pending');
     assert.equal(extension.review.status.textContent,'Loading model…');
     return new Promise(resolve=>{painted=resolve;});
   },
   rpc:async method=>{
     assert.equal(method,'extensions.view');reads++;
     return new Promise(resolve=>{releaseResult=resolve;});
   },
   onCanvas:()=>assert.fail('A dismissed result was displayed')
 });
 const model={specification:'spec',registration:{providerID:'invar'},inputManifestDigest:'digest'};
 const opening=extension.reviewModel(view,entity,Promise.resolve(model),false,()=>{});
 assert.equal(reads,0);
 painted();await new Promise(setImmediate);
 assert.equal(reads,1);
 const binding={...view,inputManifestDigest:'digest',entityIDs:[entity.id]};
 const graph={id:'proof',kind:'graph',binding,data:{metadata:{formalKind:'leanDeclarations'},nodes:[{id:'entry'}],edges:[]}};
 extension.showVerificationGraphs=()=>assert.fail('A late publication reached the renderer');
 extension.closeModel();
 releaseResult({publications:[{providerID:'invar',binding,applicability:'unknown',contributions:[graph]}]});
 await opening;
 assert.equal(extension.review,null);
});

test('a restored verification screen resolves the provider for its pinned snapshot during a workspace refresh',async()=>{
 const element=()=>({append(){},setAttribute(){}});
 const document={createElement:element,body:element(),getElementById:()=>null},window={};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../Sources/ArchitectureGraph/Resources/extensions.js'),'utf8'),{window,document});
 const registration={id:'live',connected:true,permissions:['actions.receive'],manifest:{actions:[{inputSchemaID:'invar.verify-model.v2'}]}};
 const extension=new window.ArchitectureExtensionUI({rpc:async(method,params)=>{
   assert.equal(params.snapshotID,'pinned');
   if(method==='extensions.view')return {registrations:[registration]};
   assert.equal(method,'inputs.manifest');return {manifest:{files:{'Verification/node/properties.json':'content'}},inputManifestDigest:'digest'};
 }});
 const restored=await extension.modelAvailability({snapshotID:'pinned'},{id:'node',name:'Selected'});
 assert.equal(restored.registration,registration);assert.equal(restored.inputManifestDigest,'digest');
});

test('source node results follow published bindings across pages and open the recorded claim without dispatch',async()=>{
 const model=require('../Sources/ArchitectureGraph/Resources/canvas-model.js');
 const window={ArchitectureCanvasModel:model},make=()=>({append(){},setAttribute(){}}),document={createElement:make,getElementById:()=>null,body:make()};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../Sources/ArchitectureGraph/Resources/extensions.js'),'utf8'),{window,document});
 const view={workspaceID:'ws',snapshotID:'snapshot'};
 const binding={...view,inputManifestDigest:'digest',entityIDs:['a','b'],factIDs:[]};
 const condition={claimID:'c',bundleID:'bundle',name:'within',entry:'visible',domain:'generatedModel.lean.quantified',outcome:'proved',requires:'true',ensures:'result',scope:'model',translation:'unvalidated'};
 const annotation={kind:'annotation',id:'report',binding:{...binding,entityIDs:['a']},data:{attributes:{conditions:[condition,{...condition,claimID:'d',outcome:'counterexample'}]}}};
 const pub={publicationID:'pub',applicability:'unknown',binding,contributions:[annotation]};
 const calls=[],opened=[];
 const ui=new window.ArchitectureExtensionUI({view:()=>view,rpc:async(method,params)=>{
   calls.push(method);if(method==='extensions.pending')return [];
   assert.equal(method,'extensions.view');
   if(params.cursor)return {publications:[pub]};
   return {nextCursor:'next',publications:[{...pub,applicability:'stale'},{...pub,binding:{...binding,snapshotID:'old'}},
     {...pub,contributions:[{...annotation,binding:{...binding,inputManifestDigest:'other'}}]},
     {...pub,contributions:[{kind:'graph',data:{metadata:{modelStatus:'generatedUnverified'}}}]}]};
 },onCanvas:(data,origin,id,active)=>{assert.ok(active());opened.push([data.metadata.outcome,origin.publicationID,id]);}});
 ui.render=()=>{};
 await ui.refresh();
 assert.deepEqual(Array.from(ui.nodeAccessories.keys()),['a']);
 const results=ui.nodeAccessories.get('a');
 assert.deepEqual(Array.from(results,r=>r.label),['Proved','Counterexample']);
 await ui.openNodeAccessory('a',results[1],()=>true);
 assert.deepEqual(opened,[['counterexample','pub','report-bundle-d']]);
 const custom=(icon,tone)=>({...annotation,data:{attributes:{nodeAccessory:{icon,tone,label:'Design note'}}}});
 const index=new Map();
 ui.collectNodeAccessories(index,view,{publications:[{...pub,contributions:[custom('flag','accent'),custom('other','accent'),custom('info','invalid')]}]});
 assert.deepEqual(Array.from(index.get('a'),a=>a.icon),['flag']);
 ui.nodeAccessories=index;
 let shown;ui.showContribution=(label,origin,contribution)=>{shown=[label,origin.publicationID,contribution.id];};
 await ui.openNodeAccessory('a',index.get('a')[0],()=>true);
 assert.deepEqual(shown,['Design note','pub','report']);
 ui.nodeAccessories.clear();
 await ui.openNodeAccessory('a',results[1],()=>true);
 assert.equal(opened.length,1);
 assert.deepEqual(calls,['extensions.view','extensions.pending','extensions.view']);
});

test('a reopened published graph reuses only a session containing the exact emitted document',async()=>{
 const model=require('../Sources/ArchitectureGraph/Resources/canvas-model.js'),crypto=require('node:crypto');
 const window={ArchitectureCanvasModel:model},document={getElementById:()=>null};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../Sources/ArchitectureGraph/Resources/canvas-ui.js'),'utf8'),{window,document,TextEncoder,crypto:crypto.webcrypto,setTimeout,clearTimeout});
 const sessions=new Map(),opened=[];
 const ui=new window.ArchitectureCanvasUI({rpc:async(method,{viewSessionID})=>{assert.equal(method,'canvas.get');return sessions.get(viewSessionID);}});
 ui.list=async()=>{};ui.present=result=>opened.push(result.viewSessionID);
 ui.mutate=async(method,{text,name})=>{
   assert.equal(method,'canvas.open');
   const document=JSON.parse(text);document.sourceName=name;document.sourceDigest=crypto.createHash('sha256').update(text).digest('hex');
   const session={document,viewSessionID:'exact'};sessions.set('exact',session);return session;
 };
 const data={nodes:[],edges:[],title:'Program',metadata:{formalKind:'leanDeclarations'}},publication={publicationID:'pub',binding:{},runID:'run'};
 await ui.contribution(data,publication,'model');ui.contributionSessions.clear();
 const {document:original}=sessions.get('exact');
 sessions.set('different',{document:{...original,sourceDigest:'different'},viewSessionID:'different'});
 ui.sessions=['different','exact'].map(viewSessionID=>({viewSessionID,title:original.title}));
 ui.mutate=async()=>{throw Error('An existing session must not consume another slot.');};
 await ui.contribution(data,publication,'model');
 assert.deepEqual(opened,['exact','exact']);
});

test('Map navigation resolves exact report bindings and rechecks a chosen session',async()=>{
  const {ui}=setup(),target={workspaceID:'w',snapshotID:'s',entityID:'system'};
  const reports=new Map();
  for(const [id,binding] of Object.entries({first:target,second:target,other:{...target,entityID:'container'},old:{...target,snapshotID:'old'},foreign:{...target,workspaceID:'other'}})){
    reports.set(id,{...session(1),viewSessionID:id,document:{nodes:[],title:id,sourceDigest:id,metadata:{specVerification:{mapBinding:binding,checks:[]}}}});
  }
  let reads=0,opened;
  ui.context.rpc=async(method,p)=>{if(method==='canvas.list')return {sessions:[...reports.values()]};reads++;return reports.get(p.viewSessionID);};
  ui.present=(result,push)=>{assert.equal(push,true);opened=result.viewSessionID;};
  const matches=await ui.mapReports(target,()=>true);
  assert.deepEqual(Array.from(matches,r=>r.id),['first','second']);
  const scopeMatches=await ui.mapReports({workspaceID:'w',snapshotID:'s'},()=>true,[...reports.values()]);
  assert.deepEqual(Array.from(scopeMatches,r=>r.id),['first','other','second']);
  assert.equal(scopeMatches[0].summary.title,'Incomplete verification report');
  const count=reads;
  await ui.mapReports(target,()=>true);assert.equal(reads,count);
  await ui.openMapReport(matches[0],target,()=>true);assert.equal(opened,'first');
  reports.get('second').document.metadata.specVerification.mapBinding={...target,entityID:'other'};
  await assert.rejects(ui.openMapReport(matches[1],target,()=>true),/changed/);
  await ui.openMapReport(matches[0],target,()=>false);assert.equal(opened,'first');
});

test('Map project verification enters first, confirms one new run and preserves the complete incomplete report',async()=>{
 const make=tag=>({tag,dataset:{},childNodes:[],append(...items){this.childNodes.push(...items);},replaceChildren(...items){this.childNodes=items;},setAttribute(){},remove(){}});
 const toolbar=make('div');toolbar.after=()=>{};
 const document={createElement:make,getElementById:id=>id==='canvas-tools'?toolbar:null,body:make('body')};
 const window={ArchitectureCanvasModel:require('../Sources/ArchitectureGraph/Resources/canvas-model.js')};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../Sources/ArchitectureGraph/Resources/extensions.js'),'utf8'),{window,document,Promise,setTimeout,clearTimeout});
 const view={workspaceID:'workspace',snapshotID:'fixed'},entity={id:'system',kind:'softwareSystem',name:'System',anchor:{path:'ARCHITECTURE.dsl'}};
 const binding={...view,inputManifestDigest:'digest',entityIDs:[entity.id],factIDs:[]};
 const registration={id:'r',providerID:'invar',connected:true,permissions:['actions.receive'],manifest:{actions:[{id:'verify-project',inputSchemaID:'invar.verify-project.v1'}]}};
 const report={id:'invar:project',kind:'graph',binding,data:{title:'Project verification',kind:'proofDependencies',nodes:[{id:'invar:A01',label:'Requirement'}],edges:[],metadata:{verificationReport:{schemaVersion:1,outcome:'incomplete',inventory:['A01'],requirements:[{id:'A01',nodeID:'invar:A01',specification:{outcome:'passed',claims:['s']},implementation:{outcome:'unsupported',claims:[]},correspondence:{outcome:'notVerified',claims:[]}}],evidence:[{id:'s',requirements:['A01'],domain:'specification.lean.quantified',outcome:'passed',scope:'Fixture'}],openQuestions:[]}}}};
 const data={registrations:[registration],publications:[{providerID:'invar',binding,runID:'old',generation:1,applicability:'unknown',contributions:[report]}]},events=[],opened=[];
 let releasePaint;
 const extension=new window.ArchitectureExtensionUI({view:()=>view,enterVerification:async(v,e,project)=>{assert.equal(project,true);events.push('enter');await new Promise(resolve=>{releasePaint=resolve;});},rpc:async method=>method==='inputs.manifest'?{manifest:{files:{'Verification/Project/invar.json':'config'}},inputManifestDigest:'digest'}:data,onCanvas:async(value,p)=>opened.push([value,p.runID])});
 extension.modelView=view;extension.data=data;
 extension.mutate=async(method,params)=>{events.push(method);if(method==='actions.prepare'){assert.equal(params.actionID,'verify-project');assert.equal(params.arguments.configuration,'Verification/Project/invar.json');return {executable:'invar',intent:{requestID:'new',requestFingerprint:'fingerprint',authorizationToken:'token',deadline:Date.now()/1000+60}};}
  assert.equal(method,'actions.confirm');data.actions=[{requestID:'new',providerID:'invar',actionID:'verify-project',binding,state:'completed',runID:'new-run'}];data.publications.push({providerID:'invar',binding,runID:'new-run',generation:2,applicability:'unknown',contributions:[report]});};
 const host=make('div');extension.modelCommand(host,entity,()=>{});await new Promise(setImmediate);assert.equal(host.childNodes[0].textContent,'Verify project');
 const pending=host.childNodes[0].onclick();assert.deepEqual(events,['enter']);assert.equal(opened.length,0);releasePaint();await pending;
 assert.deepEqual(events,['enter','actions.prepare']);assert.equal(opened.length,0);
 assert.match(extension.review.status.textContent,/Ready to verify specification/);
 await extension.review.panel.childNodes[0].childNodes[3].onclick();
 assert.deepEqual(events,['enter','actions.prepare','actions.confirm']);assert.equal(opened[0][1],'new-run');
 assert.equal(opened[0][0].metadata.verificationReport.requirements.length,1);assert.match(extension.review.status.textContent,/incomplete/);
 extension.closeModel();
});

test('published project report metadata reaches the shared Canvas verdict rather than being hidden in provider metadata',async()=>{
 const {ui}=setup();let captured;
 ui.context.enter=()=>({paint:Promise.resolve(),current:()=>true});ui.list=async()=>{};
 ui.mutate=async(method,params)=>{assert.equal(method,'canvas.open');captured=JSON.parse(params.text);return {viewSessionID:'report',revision:1,document:{...captured,sourceDigest:'d'},state:{}};};
 const assessment={schemaVersion:1,inventory:['A01'],requirements:[],outcome:'incomplete'};
 await ui.contribution({title:'Report',kind:'proofDependencies',nodes:[{id:'a',label:'A'}],edges:[],metadata:{verificationReport:assessment}},{publicationID:'p',providerID:'invar'},'invar:report');
 assert.deepEqual(captured.metadata.verificationReport,assessment);
});
