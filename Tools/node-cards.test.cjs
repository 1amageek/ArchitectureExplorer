/* Exercise the production renderer with the pinned Cytoscape engine in a DOM host double. */
'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const assets=path.join(__dirname,'../Sources/ArchitectureGraph/Resources');
class Element {
  constructor(tag='div'){this.tagName=tag;this.children=[];this.dataset={};this.style={setProperty(key,value){this[key]=value;},getPropertyValue(key){return this[key]||'';}};this.hidden=false;this.value='';this.listeners=new Map();this.width=1041;const classes=new Set();this.classList={toggle:(key,on)=>on?classes.add(key):classes.delete(key),add:key=>classes.add(key),remove:key=>classes.delete(key),contains:key=>classes.has(key)};}
  append(...children){this.children.push(...children);}
  replaceChildren(...children){this.children=children;}
  addEventListener(type,callback){if(!this.listeners.has(type))this.listeners.set(type,[]);this.listeners.get(type).push(callback);}
  fire(type,event={}){const value={preventDefault(){},stopPropagation(){},...event};for(const callback of this.listeners.get(type)||[])callback(value);}
  getBoundingClientRect(){return {width:this.width,height:885,left:0,top:44};}
  focus(){}
  showModal(){this.open=true;}
  close(){this.open=false;this.fire('close');}
  remove(){}
  matches(){return !!this.open;}
  showPopover(){this.open=true;}
  hidePopover(){this.open=false;}
  removeAttribute(key){delete this[key];}
  querySelector(){return null;}
  blur(){}
  setPointerCapture(id){this.pointer=id;}
  hasPointerCapture(id){return this.pointer===id;}
  releasePointerCapture(id){if(this.pointer===id){this.pointer=undefined;this.fire('lostpointercapture',{pointerId:id});}}
  setAttribute(key,value){this[key]=value;}
  getContext(){return {font:'',measureText:value=>({width:Array.from(value).length*7})};}
}
const listRows=host=>host?.children.filter(child=>child.tagName==='ul').flatMap(list=>list.children.map(item=>item.children[0]))||[];
const entity=(id,kind,attributes={},extra={})=>({id,kind,name:id,language:'swift',attributes,...extra});
async function render(nodes,edges=[],saved=false,settings={}){
  const elements=new Map(),theme={value:'light'},media={},workers=[],sockets=[],networkRequests=[],observers=[],frames=new Map();let cy,frameID=0;
  const roots=[...fs.readFileSync(path.join(assets,'explorer.css'),'utf8').matchAll(/:root\s*\{([^}]+)\}/g)];
  const palette={light:{},dark:{}};
  roots.forEach((root,i)=>{for(const match of root[1].matchAll(/--graph-([\w-]+):\s*([^;]+);/g))palette[i?'dark':'light'][match[1]]=match[2].trim();});
  const documentListeners=new Map();
  const document={querySelector:selector=>settings.repository&&selector==='meta[name="repository-map"]'?{}:null,documentElement:{},getElementById:id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id);},createElement:tag=>new Element(tag),addEventListener:(type,callback)=>{if(!documentListeners.has(type))documentListeners.set(type,[]);documentListeners.get(type).push(callback);},querySelectorAll:()=>[...listRows(elements.get('navigator')),...listRows(elements.get('node-list')).filter(row=>row.dataset.entityId)]};
  const view={extensions:settings.extensions,...(settings.diagram?{canvas:settings.diagram}:{}),workspaceID:'workspace',snapshotID:'snapshot',queryID:'query',freshness:'current',completeness:'partial',nodes,edges,evidence:[],coverage:[]};
  const windowListeners=new Map(),entries=[{state:settings.state||null,url:settings.hash||'/'}];let entryIndex=0;
  const history={get state(){return structuredClone(entries[entryIndex].state);},entries,get index(){return entryIndex;},pushState(state,unused,url){entries.splice(++entryIndex);entries.push({state:structuredClone(state),url:url||entries[entryIndex-1].url});if(settings.repository)sandbox.location.hash=url;},replaceState(state,unused,url){entries[entryIndex]={state:structuredClone(state),url:url||entries[entryIndex].url};},back(){if(entryIndex>0){entryIndex--;queueMicrotask(()=>{for(const listener of windowListeners.get('popstate')||[])listener({state:history.state});});}},forward(){if(entryIndex+1<entries.length){entryIndex++;queueMicrotask(()=>{for(const listener of windowListeners.get('popstate')||[])listener({state:history.state});});}}};
  const sandbox={document,window:{history,addEventListener:(name,listener)=>{if(!windowListeners.has(name))windowListeners.set(name,[]);windowListeners.get(name).push(listener);},ARCHITECTURE_SAVED:saved?Buffer.from(JSON.stringify(view)).toString('base64'):undefined},TextDecoder,Uint8Array,atob,location:{hash:settings.hash||'',host:'localhost',pathname:'/'},getComputedStyle:()=>({getPropertyValue:key=>{const width=document.getElementById('workspace-body').width;if(key==='--sidebar-default')return (width<=780?0:width<=1100?190:216)+'px';if(key==='--inspector-default')return (width<=780?220:width<=1100?240:272)+'px';if(key==='--selection')return roots[theme.value==='dark'?1:0][1].match(/--selection:\s*([^;]+);/)[1].trim();if(key.startsWith('--graph-'))return palette[theme.value][key.replace('--graph-','')];const token=roots[theme.value==='dark'?1:0][1].match(new RegExp(key+':\\s*([^;]+);'));return token?token[1].trim():'';}}),matchMedia:()=>({addEventListener:(_,callback)=>{media.change=callback;}}),fetch:async (url,options)=>{networkRequests.push(url);return settings.fetch?settings.fetch(url,view,options):{ok:true,json:async()=>view};},Worker:class {constructor(){workers.push(this);}postMessage(value){this.message=value;}},WebSocket:class {constructor(){sockets.push(this);}},ResizeObserver:class {constructor(callback){this.callback=callback;observers.push(this);}observe(target){this.target=target;}},requestAnimationFrame:callback=>{frames.set(++frameID,callback);return frameID;},cancelAnimationFrame:id=>frames.delete(id),URLSearchParams,URL,setTimeout,clearTimeout,queueMicrotask,console};
  if(settings.propertyBrowser){
    document.body=new Element('body');
    document.modelContext={registerTool:tool=>settings.propertyBrowser.tools.set(tool.name,tool)};
    document.oai={annotation:{request:settings.propertyBrowser.annotate}};
    sandbox.sessionStorage={getItem:()=>null,setItem(){}};
    sandbox.crypto=require('node:crypto').webcrypto;
    sandbox.window.ArchitectureExtensionUI=class {async refresh(){} modelSlot(){} modelCommand(){}};
  }
  if(settings.accessoryUI)sandbox.window.ArchitectureExtensionUI=settings.accessoryUI;
  if(settings.mapUI)sandbox.C4Map=class {
    constructor(host,source,actions){sandbox.mapTest=this;this.actions=actions;this.targets=new Map(source.nodes.map(n=>[n.id,new Element()]));this.svg=new Element('svg');this.cx=0;this.cy=0;this.scale=1;}
    select(){} dispose(){} paint(){}
  };
  if(settings.repository){
    elements.set('search',Object.assign(new Element(),{parentElement:new Element()}));
    elements.set('snapshot-short',Object.assign(new Element(),{parentElement:new Element()}));
    elements.set('repository-source',null);
  }
  const runtime=vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(path.join(assets,'cytoscape.min.js'),'utf8'),runtime);
  // Keep the engine's frame scheduler separate from page resize-frame ownership.
  vm.runInContext('Object.assign(globalThis,window);window=globalThis;',runtime);
  vm.runInContext('const engine=cytoscape; cytoscape=options=>(window.graph=engine({...options,container:undefined,headless:true,styleEnabled:true}));',runtime);
  vm.runInContext(fs.readFileSync(path.join(assets,'canvas-model.js'),'utf8'),runtime);
  vm.runInContext(fs.readFileSync(path.join(assets,'layout-model.js'),'utf8'),runtime);
  vm.runInContext(fs.readFileSync(path.join(assets,'elk.bundled.js'),'utf8')+'; var ELK=window.ELK;',runtime);
  vm.runInContext(fs.readFileSync(path.join(assets,'highlight.min.js'),'utf8'),runtime);
  if(settings.canvasUI){vm.runInContext(fs.readFileSync(path.join(assets,'canvas-ui.js'),'utf8'),runtime);vm.runInContext('const BaseCanvasUI=window.ArchitectureCanvasUI;window.ArchitectureCanvasUI=class extends BaseCanvasUI {constructor(context){super(context);window.importedCanvas=this;}async start(){}};',runtime);}
  vm.runInContext(fs.readFileSync(path.join(assets,'explorer.js'),'utf8'),runtime);
  if(saved){const deadline=Date.now()+5000;while(!elements.get('zoom-value')?.textContent){assert.ok(Date.now()<deadline,'Saved layout completed in the actual page realm');await new Promise(resolve=>setTimeout(resolve,10));}}else await new Promise(setImmediate);
  cy=sandbox.window.graph;
  if(!settings.mapUI)assert.ok(cy,'Production startup created the graph');
  const svg=id=>decodeURIComponent(cy.getElementById(id).data('card').split(',',2)[1]);
  return {get cy(){return sandbox.window.graph;},svg,elements,theme,media,networkRequests,frames,observers,flushFrames:()=>{const callbacks=[...frames.values()];frames.clear();callbacks.forEach(callback=>callback());},worker:workers[0],history,sockets,view,key:code=>{for(const fn of documentListeners.get('keydown')||[])fn({key:code,target:{tagName:'DIV'},preventDefault(){}});},run:code=>vm.runInContext(code,runtime)};
}
function terminalMessages(page){
  const output=page.elements.get('terminal-output');
  if(output.hidden)page.elements.get('terminal-toggle').onclick();
  return output.children.map(line=>line.children[2].textContent).join('\n');
}
test('Terminal retains bounded live events while collapsed and reopens without a graph query',async t=>{
  const page=await render([entity('Service','module')]);t.after(()=>page.cy.destroy());
  const toggle=page.elements.get('terminal-toggle'),output=page.elements.get('terminal-output');
  const count=page.networkRequests.length,socket=page.sockets[0];
  assert.equal(output.hidden,true);assert.equal(toggle['aria-expanded'],'false');
  socket.onopen?.();
  assert.doesNotMatch(terminalMessages(page),/Connected to the live index/);
  toggle.onclick();
  const update=i=>socket.onmessage({data:JSON.stringify({type:'analysisStatusChanged',progress:{completedSources:i,totalSources:100,runningWorkers:2}})});
  update(30);update(30);
  assert.equal(output.children.length,0);
  const history=terminalMessages(page);
  assert.match(history,/Loaded graph.overview/);assert.match(history,/Connected to the live index/);
  assert.equal(history.split('Indexing 30 / 100').length,2);
  assert.equal(toggle['aria-expanded'],'true');toggle.onclick();
  for(let i=0;i<300;i++)update(i%2===0?40:50);
  assert.equal(output.children.length,0);
  assert.doesNotMatch(terminalMessages(page),/Indexing 30/);assert.equal(output.children.length,250);
  assert.equal(page.networkRequests.length,count);
});
test('live index reports a pairing denial once and preserves the loaded graph',async t=>{
  const page=await render([entity('Service','module')]);t.after(()=>page.cy.destroy());
  const socket=page.sockets[0],count=page.networkRequests.length;
  page.run('let retries=[]; setTimeout=callback=>retries.push(callback)');
  const denial={data:JSON.stringify({type:'liveUnavailable',code:'WEB_HOST_PAIRING_MISMATCH',message:'Restart Explorer and the daemon using the same paired build.'})};
  socket.onmessage(denial);socket.onmessage(denial);socket.onclose();
  assert.equal(page.elements.get('live').textContent,'Live index unavailable');
  assert.equal(page.cy.getElementById('Service').length,1);
  assert.equal(page.run('retries.length'),0);
  assert.equal(page.networkRequests.length,count);
  const history=terminalMessages(page);
  assert.equal((history.match(/using the same paired build/g)||[]).length,1);
  assert.doesNotMatch(history,/Connected to the live index|Reconnecting/);
});
test('a transient live index interruption reconnects without repeating graph reads or warnings',async t=>{
  const page=await render([entity('Service','module')]);t.after(()=>page.cy.destroy());
  const count=page.networkRequests.length;
  page.run('let retries=[]; setTimeout=callback=>retries.push(callback)');
  page.sockets[0].onclose();page.run('retries.shift()()');
  page.sockets[1].onclose();page.run('retries.shift()()');
  assert.equal(page.networkRequests.length,count);
  page.sockets[2].onmessage({data:JSON.stringify({type:'viewInvalidated',snapshotID:'snapshot'})});
  assert.equal(page.elements.get('live').textContent,'Live index');
  const history=terminalMessages(page);
  assert.equal((history.match(/Reconnecting/g)||[]).length,1);
  assert.equal((history.match(/Connected to the live index/g)||[]).length,1);
});
test('recorded roles stay distinct; unknown refinements use the coarse category',async t=>{
  const roles=['class','struct','protocol','trait','function','method','module'];
  const nodes=roles.map(role=>entity(role,role==='function'||role==='method'?role:'type',{'declaration.kind':role}));
  nodes.push(entity('ClassInName','type',{'declaration.kind':'futureKind'}));
  const page=await render(nodes);t.after(()=>page.cy.destroy());
  for(const role of roles)assert.match(page.svg(role),new RegExp('>'+role[0].toUpperCase()+role.slice(1)+'<'));
  assert.match(page.svg('ClassInName'),/>Type</);assert.doesNotMatch(page.svg('ClassInName'),/>Class</);
  const accent=id=>page.svg(id).match(/<g data-role="[^"]+"[^>]*><rect[^>]* fill="([^"]+)"/)[1];
  assert.equal(new Set(['class','struct','function','module'].map(accent)).size,4,'Primary paradigms have distinguishable accents');
  const palette=Object.fromEntries([...fs.readFileSync(path.join(assets,'explorer.css'),'utf8').split('@media')[0].matchAll(/(--graph-role-[\w-]+):\s*(#[\da-f]{6})/g)].map(m=>[m[1],m[2]]));
  for(const role of roles){const mark=listRows(page.elements.get('navigator')).find(n=>n.dataset.entityId===role).children[0];const token=mark.style.getPropertyValue('--role-accent').match(/var\(([^)]+)\)/)[1];assert.equal(palette[token],accent(role),'Navigator and Canvas use the same recorded role accent');}
  assert.match(page.svg('ClassInName'),/<g data-role="type"/);assert.equal(accent('ClassInName'),palette['--graph-role-type']);
});
test('source Canvas filter keeps ancestor frames and both controls operate on the loaded graph',async t=>{
  const nodes=[entity('Folder','file'),entity('Needle','type'),entity('Other','type')];
  const edges=[{id:'contains',source:'Folder',target:'Needle',kind:'contains'},{id:'uses',source:'Needle',target:'Other',kind:'calls'}];
  const page=await render(nodes,edges);t.after(()=>page.cy.destroy());
  const filter=page.elements.get('local-filter'),layout=page.elements.get('local-layout');
  const requests=page.networkRequests.length;
  assert.equal(page.elements.get('canvas-tools').hidden,false);
  filter.value='needle';filter.oninput();await new Promise(resolve=>setTimeout(resolve,170));
  assert.deepEqual(Array.from(page.cy.nodes(),n=>n.id()).sort(),['Folder','Needle']);
  assert.equal(page.cy.getElementById('Needle').parent().id(),'Folder');
  layout.value='right';layout.onchange();
  assert.equal(page.worker.message.direction,'RIGHT');
  filter.value='missing';layout.onchange();
  assert.equal(page.cy.nodes().length,0);assert.equal(page.elements.get('empty').textContent,'No matching entities.');
  filter.value='';layout.onchange();
  assert.equal(page.cy.nodes().length,3);assert.equal(page.cy.getElementById('uses').length,1);
  assert.equal(page.networkRequests.length,requests);
});
test('card and accessible List preserve signature, source, owner and synthetic origin',async t=>{
  const signature='func save(_ tasks: List) throws -> Int';
  const callable={'declaration.callable':{version:1,parameters:[{spelling:'_ tasks: List'}],effects:['throws'],resultStatus:'recorded',results:[{type:'Int'}]},'syntax.signature':signature};
  const page=await render([entity('Owner','function',{'syntax.signature':'func Owner(_ x: Int) -> Int'},{anchor:{path:'Sources/Flow.swift'}}),entity('save','method',callable,{anchor:{path:'Sources/Flow.swift'}}),entity('Boundary','basicBlock',{'cfg.synthetic':true,'cfg.functionID':'Owner'}),entity('Target','module',{'project.manifest':'Package.swift'}),entity('TypeOwner','type'),entity('Member','method')],[{id:'member-owner',source:'TypeOwner',target:'Member',kind:'contains'}]);t.after(()=>page.cy.destroy());
  assert.match(page.svg('Owner'),/func Owner\(_ x: Int\) -&gt; Int/);
  assert.match(page.svg('Owner'),/Sources\/Flow.swift/);
  assert.match(page.svg('Boundary'),/Basic Block · Synthetic/);assert.match(page.svg('Boundary'),/in Owner/);assert.match(page.svg('Boundary'),/No source anchor/);
  assert.match(page.svg('Target'),/Package.swift/);assert.match(page.svg('Member'),/in TypeOwner/);
  const save=page.svg('save');
  assert.equal(page.cy.getElementById('save').height(),112);
  assert.match(save,/<text x="12" y="54"[^>]*>save\(_ tasks: List\)<\/text>/);
  assert.match(save,/<text x="12" y="75"[^>]*>throws → Int<\/text>/);
  assert.equal(save.split('_ tasks: List').length,2);
  page.cy.getElementById('save').emit('mouseover');
  assert.ok(page.elements.get('graph').title.includes(signature));
  const row=listRows(page.elements.get('node-list'))[0];assert.match(row.children[1].children[1].textContent,/func Owner\(_ x: Int\) -> Int.*Sources\/Flow.swift/);
});
test('source strings become escaped bounded SVG text, never executable markup',async t=>{
  const hostile='</text><script>alert("x")</script>&';
  const longName='非常に長い名前😀'.repeat(400);
  const page=await render([entity('hostile','type',{'syntax.signature':hostile},{name:hostile,anchor:{path:hostile}}),entity('long','type',{}, {name:longName})]);t.after(()=>page.cy.destroy());
  const svg=page.svg('hostile');assert.doesNotMatch(svg,/<script|alert\("x"\)/);assert.match(svg,/&lt;\/text&gt;/);assert.match(svg,/&amp;/);
  assert.ok([...page.svg('long').matchAll(/<text[^>]*>(.*?)<\/text>/g)].map(m=>m[1]).join('').length<250);assert.match(page.svg('long'),/…/);
  assert.equal(listRows(page.elements.get('navigator'))[1].children[1].textContent,longName);
});
test('ELK and canvas use identical dimensions and true center coordinates',async t=>{
  const page=await render([entity('one','module'),entity('two','function')]);t.after(()=>page.cy.destroy());
  const request=page.worker.message;
  for(const node of request.nodes){const w=264,h=node.kind==='function'?140:112;assert.equal(node.width,w);assert.equal(node.height,h);assert.equal(page.cy.getElementById(node.id).width(),w);assert.ok(page.svg(node.id).includes(`width="${w}" height="${h}"`));}
  page.worker.onmessage({data:{...request,nodes:request.nodes.map((n,i)=>({...n,x:i*300,y:i*180}))}});
  assert.deepEqual({...page.cy.getElementById('one').position()},{x:132,y:56});assert.deepEqual({...page.cy.getElementById('two').position()},{x:432,y:250});
});
test('system appearance refreshes card images without changing selection or viewport',async t=>{
  const page=await render([entity('one','type',{'declaration.kind':'struct'})]);t.after(()=>page.cy.destroy());
  page.run("window.graph.getElementById('one').position({x:132,y:56}).select();window.graph.zoom(1.25);window.graph.pan({x:123,y:87});");
  const light=page.svg('one');page.theme.value='dark';page.media.change();assert.notEqual(page.svg('one'),light);assert.match(page.svg('one'),/#303030/);
  assert.deepEqual({...page.cy.pan()},{x:123,y:87});assert.equal(page.cy.zoom(),1.25);assert.equal(page.cy.$(':selected').id(),'one');assert.deepEqual({...page.cy.getElementById('one').position()},{x:132,y:56});
  page.theme.value='light';page.media.change();assert.equal(page.svg('one'),light);
});

test('standalone saved views use the same cards without a worker or network',async t=>{
  const page=await render([entity('Saved','type',{'declaration.kind':'class','syntax.signature':'class Saved'}, {anchor:{path:'Saved.swift'}})],[],true);t.after(()=>page.cy.destroy());
  assert.equal(page.worker,undefined);assert.equal(page.networkRequests.length,0);assert.match(page.elements.get('live').textContent,/Saved.*not live/);assert.match(page.svg('Saved'),/>Class</);assert.match(page.svg('Saved'),/Saved.swift/);assert.equal(page.cy.getElementById('Saved').height(),112);
  page.cy.getElementById('Saved').emit('tap');assert.equal(page.cy.$(':selected').id(),'Saved');assert.equal(listRows(page.elements.get('navigator'))[0]['aria-pressed'],'true');assert.ok(page.elements.get('inspector').children.some(e=>e.tagName==='h2'&&e.textContent==='Saved'));
});

test('language slots use bundled logos, keep accessible names, and preserve unknown languages',async t=>{
  const page=await render([entity('swift-node','function'),entity('rust-node','type',{}, {language:'rust'}),entity('unknown-node','type',{}, {language:'kotlin'}),entity('no-language','module',{}, {language:'none'})],[],true);t.after(()=>page.cy.destroy());
  for(const [id,language,label]of [['swift-node','swift','Swift'],['rust-node','rust','Rust']]){
    assert.match(page.svg(id),new RegExp('data-language="'+language+'" transform="translate\\((8|10) '));
    assert.match(page.svg(id),new RegExp('<title>'+label+'</title><(?:path|rect)'));
    assert.match(page.svg(id),new RegExp('data-language="'+language+'"[^>]+fill="'+(language==='swift'?'#f05138':'#a84a2a')+'"'));
    assert.doesNotMatch(page.svg(id),new RegExp('>'+label+'</text>'));
    assert.doesNotMatch(page.svg(id),/<image|(?:href|src)=/);
    const row=listRows(page.elements.get('node-list')).find(e=>e.dataset.entityId===id);
    assert.match(row.children[2].textContent,new RegExp(label));
  }
  assert.match(page.svg('unknown-node'),/data-language="kotlin"/);assert.match(listRows(page.elements.get('node-list'))[2].children[2].textContent,/kotlin/i);assert.doesNotMatch(page.svg('no-language'),/data-language=/);
  page.cy.getElementById('swift-node').emit('mouseover');assert.match(page.elements.get('graph').title,/Swift/);
  page.cy.getElementById('swift-node').emit('mouseout');assert.equal(page.elements.get('graph').title,'');
  const before=page.svg('rust-node');page.theme.value='dark';page.media.change();assert.notEqual(page.svg('rust-node'),before);assert.match(page.svg('rust-node'),/data-language="rust"[^>]+fill="#df8656"/);
});

test('edges convey recorded relation families and CFG branches without permanent labels',async t=>{
  const kinds=['contains','dependsOn','imports','calls','candidateCalls','usesType','references','memberOf','controlFlow','futureRelation'];
  const edges=kinds.map((kind,i)=>({id:'edge-'+i,kind,source:'source',target:'target',attributes:{}}));
  edges.push({id:'true-edge',kind:'controlFlow',source:'source',target:'target',attributes:{'cfg.branch':'true'}},{id:'false-edge',kind:'controlFlow',source:'source',target:'target',attributes:{'cfg.branch':'false'}},{id:'return-edge',kind:'controlFlow',source:'source',target:'target',attributes:{'cfg.branch':'return'}});
  const page=await render([entity('source','function'),entity('target','function')],edges,true);t.after(()=>page.cy.destroy());
  const line=id=>page.cy.getElementById(id).style('line-color');
  const groups=[line('edge-0'),line('edge-1'),line('edge-3'),line('edge-5'),line('edge-7'),line('edge-8'),line('true-edge'),line('false-edge')];
  assert.equal(new Set(groups).size,groups.length);
  for(const edge of page.cy.edges()){assert.equal(edge.style('label'),'');assert.equal(edge.style('line-color'),edge.style('target-arrow-color'));assert.ok(parseFloat(edge.style('width'))>0);}
  assert.equal(page.cy.getElementById('edge-4').style('line-style'),'dashed');assert.equal(page.cy.getElementById('false-edge').style('line-style'),'dashed');assert.equal(page.cy.getElementById('edge-9').style('line-style'),'dotted');assert.equal(line('return-edge'),line('edge-8'));
  const legend=page.elements.get('edge-legend').children.map(e=>e.textContent||e.children.map(c=>c.textContent||'').join('')).join(' ');
  assert.match(legend,/Contains/);assert.match(legend,/Possible calls/);assert.match(legend,/True branch/);assert.match(legend,/False branch/);assert.match(legend,/Other/);
  page.cy.getElementById('false-edge').emit('mouseover');assert.match(page.elements.get('graph').title,/source.*controlFlow.*false.*target/);
  page.cy.getElementById('false-edge').emit('mouseout');assert.equal(page.elements.get('graph').title,'');
  const rows=listRows(page.elements.get('node-list')).filter(e=>e.className==='relation-row');assert.equal(rows.length,edges.length);assert.ok(rows.some(e=>e.children.some(c=>String(c.textContent).includes('futureRelation'))));
  const before=line('true-edge');page.run("window.graph.zoom(1.25);window.graph.pan({x:123,y:87});");page.cy.getElementById('false-edge').select();page.theme.value='dark';page.media.change();assert.notEqual(line('true-edge'),before);assert.deepEqual({...page.cy.pan()},{x:123,y:87});assert.equal(page.cy.zoom(),1.25);assert.equal(page.cy.$(':selected').id(),'false-edge');
});

test('edge palettes contrast with both backgrounds and do not infer branches outside CFG',async t=>{
  const roots=[...fs.readFileSync(path.join(assets,'explorer.css'),'utf8').matchAll(/:root\s*\{([^}]+)\}/g)];
  const luminance=hex=>{const values=hex.slice(1).match(/../g).map(v=>parseInt(v,16)/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4);return values[0]*.2126+values[1]*.7152+values[2]*.0722;};
  for(const root of roots){const background=root[1].match(/--surface:\s*(#[\da-f]{6});/)[1];for(const match of root[1].matchAll(/--graph-edge-[\w-]+:\s*(#[\da-f]{6});/g)){const a=luminance(background),b=luminance(match[1]);assert.ok((Math.max(a,b)+.05)/(Math.min(a,b)+.05)>=3,match[0]);}}
  for(const root of roots){const background=root[1].match(/--graph-node-header:\s*(#[\da-f]{6});/)[1];for(const match of root[1].matchAll(/--graph-language-[\w-]+:\s*(#[\da-f]{6});/g)){const a=luminance(background),b=luminance(match[1]);assert.ok((Math.max(a,b)+.05)/(Math.min(a,b)+.05)>=3,match[0]);}}
  for(const root of roots){
    const rgb=hex=>hex.slice(1).match(/../g).map(v=>parseInt(v,16));
    const header=rgb(root[1].match(/--graph-node-header:\s*(#[\da-f]{6});/)[1]);
    for(const match of root[1].matchAll(/--graph-role-[\w-]+:\s*(#[\da-f]{6});/g)){
      const accent=rgb(match[1]),tile='#'+accent.map((v,i)=>Math.round(v*.14+header[i]*.86).toString(16).padStart(2,'0')).join('');
      const a=luminance(match[1]),b=luminance(tile);assert.ok((Math.max(a,b)+.05)/(Math.min(a,b)+.05)>=4.5,'Role mark text contrast: '+match[0]);
    }
  }
  const page=await render([entity('source','function'),entity('target','function')],[{id:'not-cfg',kind:'candidateCalls',source:'source',target:'target',attributes:{'cfg.branch':'false'}},{id:'unknown',kind:'branch:true',source:'source',target:'target',attributes:{}}],true);t.after(()=>page.cy.destroy());
  assert.equal(page.cy.getElementById('not-cfg').data('relation'),'candidate-calls');assert.equal(page.cy.getElementById('unknown').data('relation'),'other');
  const labels=page.elements.get('edge-legend').children.map(row=>row.children[1].textContent);assert.deepEqual(labels,['Possible calls','Other']);assert.equal(page.networkRequests.length,0);
});


test('panel drag coalesces movement, respects canvas budget, and cleans up cancellation',async t=>{
  const page=await render([entity('one','module')],[],true);t.after(()=>page.cy.destroy());
  const left=page.elements.get('sidebar-resizer'),right=page.elements.get('inspector-resizer'),workspace=page.elements.get('workspace-body');
  page.run("window.graph.zoom(1.3);window.graph.pan({x:123,y:87});window.graph.getElementById('one').position({x:111,y:222}).select();");
  assert.equal(left['aria-valuenow'],'190');assert.equal(right['aria-valuenow'],'240');
  left.fire('pointerdown',{button:0,pointerId:7,clientX:190});left.fire('pointermove',{pointerId:8,clientX:500});assert.equal(page.frames.size,0);
  left.fire('pointermove',{pointerId:7,clientX:250});left.fire('pointermove',{pointerId:7,clientX:1000});assert.equal(page.frames.size,1);assert.equal(left['aria-valuenow'],'190');page.flushFrames();assert.equal(left['aria-valuenow'],'400');
  left.fire('pointerup',{pointerId:7,clientX:1001});assert.equal(left.pointer,undefined);assert.equal(workspace.classList.contains('is-resizing'),false);
  right.fire('pointerdown',{button:0,pointerId:9,clientX:801});right.fire('pointermove',{pointerId:9,clientX:600});right.fire('pointercancel',{pointerId:9});
  assert.equal(right['aria-valuenow'],'321');assert.equal(right['aria-valuemax'],'321');assert.equal(right.pointer,undefined);assert.equal(page.frames.size,0);assert.equal(workspace.classList.contains('is-resizing'),false);
  page.observers.find(item=>item.target===page.elements.get('graph')).callback();assert.equal(page.cy.zoom(),1.3);assert.deepEqual({...page.cy.pan()},{x:123,y:87});assert.equal(page.cy.$(':selected').id(),'one');assert.deepEqual({...page.cy.getElementById('one').position()},{x:111,y:222});
});

test('panel keyboard, bounds, reset and lost capture use the same resize contract',async t=>{
  const page=await render([entity('one','module')],[],true);t.after(()=>page.cy.destroy());
  const left=page.elements.get('sidebar-resizer'),right=page.elements.get('inspector-resizer');
  left.fire('keydown',{key:'ArrowRight'});assert.equal(left['aria-valuenow'],'198');right.fire('keydown',{key:'ArrowLeft'});assert.equal(right['aria-valuenow'],'248');right.fire('keydown',{key:'ArrowRight',shiftKey:true});assert.equal(right['aria-valuenow'],'216');
  left.fire('keydown',{key:'Home'});assert.equal(left['aria-valuenow'],'160');left.fire('keydown',{key:'End'});assert.equal(left['aria-valuenow'],'400');left.fire('dblclick');assert.equal(left['aria-valuenow'],'190');right.fire('dblclick');assert.equal(right['aria-valuenow'],'240');
  left.fire('pointerdown',{button:0,pointerId:2,clientX:190});left.fire('pointermove',{pointerId:2,clientX:250});left.fire('pointerup',{pointerId:2,clientX:280});assert.equal(left['aria-valuenow'],'280');assert.equal(page.frames.size,0);left.fire('dblclick');
  left.fire('pointerdown',{button:0,pointerId:1,clientX:190});left.fire('pointermove',{pointerId:1,clientX:290});left.fire('lostpointercapture',{pointerId:1});assert.equal(left['aria-valuenow'],'290');assert.equal(page.frames.size,0);assert.equal(page.elements.get('workspace-body').classList.contains('is-resizing'),false);
  left.fire('pointerdown',{button:0,pointerId:3,clientX:290});left.fire('pointermove',{pointerId:3,clientX:310});left.fire('keydown',{key:'Escape'});assert.equal(left['aria-valuenow'],'310');assert.equal(left.pointer,undefined);assert.equal(page.frames.size,0);assert.equal(page.elements.get('workspace-body').classList.contains('is-resizing'),false);
});

test('responsive panel limits keep widths bounded and work in saved and live views',async t=>{
  for(const saved of [true,false]){
    const page=await render([entity('one','module')],[],saved);t.after(()=>page.cy.destroy());
    const workspace=page.elements.get('workspace-body'),left=page.elements.get('sidebar-resizer'),right=page.elements.get('inspector-resizer');
    right.fire('keydown',{key:'ArrowLeft',shiftKey:true});const preferred=right['aria-valuenow'];
    const observer=page.observers.find(item=>item.target===workspace);assert.ok(observer);
    workspace.width=700;observer.callback();assert.equal(left.hidden,true);assert.equal(workspace.style.getPropertyValue('--sidebar-width'),'0px');assert.equal(right['aria-valuenow'],preferred);
    workspace.width=400;observer.callback();assert.equal(right['aria-valuenow'],'180');assert.equal(right['aria-valuemin'],'180');assert.equal(right['aria-valuemax'],'180');
    workspace.width=1400;observer.callback();assert.equal(left.hidden,false);assert.equal(right['aria-valuenow'],preferred);assert.equal(page.networkRequests.length,saved?0:2);
  }
});

test('logo-specific fills keep Swift white and preserve Rust negative space in both themes',async t=>{
  const page=await render([entity('swift-logo','function'),entity('rust-logo','function',{}, {language:'rust'})],[],true);t.after(()=>page.cy.destroy());
  for(const theme of ['light','dark']){
    page.theme.value=theme;page.media.change();
    const swift=page.svg('swift-logo');
    assert.match(swift,/<path data-logo-part="background"[^>]+fill="#[0-9a-f]{6}"/);
    assert.match(swift,/<path data-logo-part="bird"[^>]+fill="#ffffff"/);
    const rustMark=page.svg('rust-logo').match(/<g data-language="rust"[^>]*>([\s\S]*?)<\/g>/)[1];
    assert.match(rustMark,/<path data-logo-part="symbol" d="M23\.8346/);
    assert.doesNotMatch(rustMark,/<rect|data-logo-part="background"|fill="#ffffff"/);
    assert.doesNotMatch(page.svg('rust-logo'),/data-logo-part="bird"/);
    assert.equal(page.networkRequests.length,0);
  }
});

test('compound rendering keeps every fact in List and retains routes and manual positions on unchanged refresh',async t=>{
  const nodes=[entity('package','package'),entity('consumer','module'),entity('dependency','module')];
  const edges=[{id:'owns-c',source:'package',target:'consumer',kind:'contains'},{id:'owns-d',source:'package',target:'dependency',kind:'contains'},{id:'uses',source:'consumer',target:'dependency',kind:'dependsOn'}];
  const page=await render(nodes,edges);t.after(()=>page.cy.destroy());
  const model=require(path.join(assets,'layout-model.js')),ELK=require(path.join(assets,'elk.bundled.js'));
  const response=await model.layout(page.worker.message,new ELK());page.worker.onmessage({data:response});
  assert.equal(page.cy.nodes().length,3);assert.equal(page.cy.edges().length,1);assert.ok(page.cy.getElementById('package').isParent());assert.equal(page.cy.getElementById('consumer').parent().id(),'package');
  const p=page.cy.getElementById('package').boundingBox(),c=page.cy.getElementById('consumer').boundingBox();assert.ok(c.x1>p.x1&&c.y1>p.y1+64);
  assert.equal(page.cy.zoom(),.75);assert.deepEqual({...page.cy.pan()},{x:24-p.x1*.75,y:24-p.y1*.75});
  assert.match(page.svg('package'),/height="64"/);assert.equal(listRows(page.elements.get('node-list')).filter(e=>e.className==='relation-row').length,3);assert.match(page.elements.get('edge-legend').children[0].children[1].textContent,/frames/);
  assert.ok(page.cy.getElementById('uses').hasClass('direct')||page.cy.getElementById('uses').hasClass('routed'));
  page.run("window.graph.getElementById('consumer').position({x:333,y:444}).select().emit('drag');");assert.equal(page.cy.getElementById('uses').hasClass('routed'),false);assert.equal(page.cy.getElementById('uses').hasClass('direct'),false);
  assert.deepEqual({...page.cy.getElementById('consumer').position()},{x:333,y:444},'Drag changes the card position');
  page.run("window.graph.zoom(1.2);window.graph.pan({x:123,y:87});");const sent=page.worker.message;
  page.view.snapshotID='new-snapshot';page.sockets[0].onmessage({data:JSON.stringify({type:'viewInvalidated',snapshotID:'invalidated'})});await new Promise(setImmediate);
  assert.equal(page.worker.message,sent,'Unchanged topology does not request layout');assert.deepEqual({...page.cy.getElementById('consumer').position()},{x:333,y:444});assert.equal(page.cy.$(':selected').id(),'consumer');assert.deepEqual({...page.cy.pan()},{x:123,y:87});assert.equal(page.cy.zoom(),1.2);
  page.worker.onmessage({data:response});assert.deepEqual({...page.cy.getElementById('consumer').position()},{x:333,y:444},'Stale active result is ignored');
  page.view.edges=edges.filter(e=>e.id!=='owns-c');page.view.snapshotID='structure-change';page.sockets[0].onmessage({data:JSON.stringify({type:'viewInvalidated',snapshotID:'invalidated-again'})});await new Promise(setImmediate);
  assert.notEqual(page.worker.message,sent);assert.equal(page.cy.getElementById('consumer').parent().length,0);
  page.worker.onmessage({data:await model.layout(page.worker.message,new ELK())});assert.deepEqual({...page.cy.pan()},{x:123,y:87});assert.equal(page.cy.zoom(),1.2);
});

const settle=()=>new Promise(setImmediate);
test('the focused source canvas opens with all direct references in frame',async t=>{
  const from='entry',targets=['store','repository','workspace'];
  const nodes=[entity(from,'type'),...targets.map(id=>entity(id,'type'))];
  const edges=targets.map(target=>({id:'ref-'+target,source:from,target,kind:'candidateTypeReference'}));
  const query={method:'graph.overview',level:'component',focus:from};
  const page=await render(nodes,edges,false,{extensions:{'implementation.scope':'Module · App'},
    state:{architectureExplorer:1,index:1,level:'component',query}});
  t.after(()=>page.cy.destroy());
  page.cy.width=()=>550;
  page.cy.height=()=>700;
  const model=require(path.join(assets,'layout-model.js')),ELK=require(path.join(assets,'elk.bundled.js'));
  page.worker.onmessage({data:await model.layout(page.worker.message,new ELK())});
  const bounds=page.cy.nodes().renderedBoundingBox();
  assert.ok(bounds.x1>=24&&bounds.x2<=526&&bounds.y1>=24&&bounds.y2<=676,
    'The entry and every direct dependency fit the initial viewport');
});
const requestedQuery=page=>JSON.parse(new URL('http://localhost'+page.networkRequests.filter(url=>url.startsWith('/api?')&&JSON.parse(new URL('http://localhost'+url).searchParams.get('params')).method).at(-1)).searchParams.get('params'));
test('outgoing and incoming navigation pin the displayed live snapshot',async t=>{
  for(const [label,method] of [['Neighbors','graph.neighbors'],['Impact','graph.impact']]){
    const page=await render([entity('Entry','type')]);t.after(()=>page.cy.destroy());
    page.worker.onmessage({data:{...page.worker.message,nodes:[{id:'Entry',x:0,y:0}]}});
    assert.equal(requestedQuery(page).snapshotID,undefined);
    page.cy.getElementById('Entry').emit('tap');
    await settle();
    const actions=page.elements.get('inspector').children.find(node=>node.className==='action-row');
    actions.children.find(action=>action.textContent===label).fire('click');
    await settle();
    assert.deepEqual(requestedQuery(page),{method,focus:'Entry',depth:2,
      ...(label==='Neighbors'?{direction:'outgoing'}:{}),snapshotID:'snapshot'});
  }
});
test('the live footer shows the full workspace path independently of graph navigation',async t=>{
  const workspaceRoot='/work/Projects & <Examples>/App';
  const page=await render([entity('workspace','workspace')],[],false,{fetch:(raw,view)=>({ok:true,json:async()=>
    new URL(raw,'http://localhost').searchParams.get('method')==='host.context'?{workspaceRoot}:view})});
  t.after(()=>page.cy.destroy());
  const footerPath=page.elements.get('workspace-root-path');
  assert.equal(footerPath.textContent,workspaceRoot);
  assert.equal(footerPath.title,workspaceRoot);
  assert.equal(footerPath.hidden,false);
  assert.equal(footerPath.innerHTML,undefined);
  page.elements.get('level').value='module';page.elements.get('level').onchange();await settle();
  assert.equal(footerPath.textContent,workspaceRoot);
  assert.equal(page.networkRequests.filter(raw=>new URL(raw,'http://localhost').searchParams.get('method')==='host.context').length,1);
});
test('the source toolbar opens the pinned specification before reading, and Back restores the graph',async t=>{
  const specificationReads=[];
  const page=await render([entity('workspace','workspace')],[],false,{fetch:(raw,view)=>{
    const url=new URL(raw,'http://localhost');
    if(url.searchParams.get('method')!=='workspace.specification')return {ok:true,json:async()=>view};
    const params=JSON.parse(url.searchParams.get('params'));
    assert.deepEqual(params,{snapshotID:'snapshot'});
    return new Promise(resolve=>specificationReads.push(result=>resolve({ok:true,json:async()=>result})));
  }});t.after(()=>page.cy.destroy());
  const open=page.elements.get('open-specification'),reader=page.elements.get('specification-reader');
  assert.equal(open.hidden,false);
  open.onclick();
  assert.equal(page.elements.get('view-title').textContent,'Specification');
  assert.equal(page.elements.get('graph').hidden,true);
  assert.equal(specificationReads.length,0);
  await settle();
  const body='# Requirements\n\n<literal text>';
  specificationReads[0]({status:'available',snapshotID:'snapshot',path:'SPEC.md',text:body});
  await settle();
  assert.equal(reader.hidden,false);
  assert.deepEqual(reader.children.map(child=>child.textContent),['SPEC.md',body]);
  assert.equal(reader.children[1].innerHTML,undefined);
  assert.equal(page.history.entries.length,2);
  page.history.back();await settle();
  assert.equal(reader.hidden,true);
  assert.equal(page.cy.getElementById('workspace').length,1);
  page.history.forward();await settle();
  specificationReads[1]({status:'available',snapshotID:'other-snapshot',path:'SPEC.md',text:body});
  await settle();
  assert.equal(reader.hidden,true);
  assert.equal(page.elements.get('counts').textContent,'Unavailable');
  page.elements.get('empty').children.find(child=>child.textContent==='Retry').fire('click');
  await settle();
  specificationReads[2]({status:'missing',snapshotID:'snapshot'});await settle();
  assert.equal(reader.hidden,false);
  assert.equal(reader.children[1].textContent,'No SPEC.md recorded in this workspace.');
  assert.equal(page.history.entries.length,2);
});
test('a source destination clears the old drawing before its read, retains failure and retries without new history',async t=>{
 const requests=[];let intercept=false;
 const page=await render([entity('old','module')],[],false,{fetch:(url,view)=>{
  if(intercept&&new URL(url,'http://localhost').searchParams.get('method')==='graph.overview')return new Promise((resolve,reject)=>requests.push({resolve,reject}));
  return {ok:true,json:async()=>view};
 }});t.after(()=>page.cy.destroy());
 intercept=true;page.elements.get('level').value='function';page.elements.get('level').onchange();
 assert.equal(page.elements.get('view-title').textContent,'Functions & Methods');assert.equal(page.cy.nodes().length,0);
 assert.equal(page.elements.get('graph').hidden,true);assert.equal(page.elements.get('graph')['aria-busy'],'true');
 assert.equal(page.history.entries.length,2);assert.equal(requests.length,0);
 await settle();assert.equal(requests.length,1);requests[0].reject(Error('Reader unavailable'));await settle();
 assert.equal(page.elements.get('counts').textContent,'Unavailable');assert.equal(page.cy.nodes().length,0);
 assert.ok(page.elements.get('inspector').children.some(child=>child.textContent==='Unavailable · Reader unavailable'));
 page.elements.get('empty').children.find(child=>child.textContent==='Retry').fire('click');assert.equal(page.elements.get('counts').textContent,'Loading…');await settle();
 assert.equal(page.history.entries.length,2);assert.equal(requests.length,2);
 requests[1].resolve({ok:true,json:async()=>({...page.view,nodes:[entity('new','function')]})});await settle();
 assert.equal(page.cy.getElementById('new').length,1);assert.equal(page.elements.get('graph')['aria-busy'],'false');
 assert.ok(page.elements.get('inspector').children.some(child=>child.textContent==='No Selection'));
});
test('Canvas navigation commits history before fetching and Back rejects a late imported result',async t=>{
 let release;const page=await render([entity('origin','module')],[],false,{canvasUI:true,fetch:(url,view)=>{
  if(new URL(url,'http://localhost').searchParams.get('method')==='canvas.get')return new Promise(resolve=>{release=resolve;});
  return {ok:true,json:async()=>view};
 }});t.after(()=>page.cy.destroy());
 page.run('importedCanvas.openSession("later",true)');
 assert.equal(page.history.entries.length,2);assert.equal(page.history.state.canvasSessionID,'later');
 assert.equal(page.elements.get('view-title').textContent,'Diagram');assert.equal(page.cy.nodes().length,0);
 await settle();page.history.back();await settle();assert.equal(page.cy.getElementById('origin').length,1);
 release({ok:true,json:async()=>({viewSessionID:'later',revision:1,document:{sourceDigest:'d',kind:'relations',title:'Late',nodes:[{id:'late',label:'Late'}],edges:[]},state:{}})});
 await settle();assert.equal(page.cy.getElementById('late').length,0);assert.equal(page.history.index,0);
});
test('Home supersedes a pending diagram even at the same source query and index invalidation cannot replace it',async t=>{
 let release;const page=await render([entity('origin','module')],[],false,{canvasUI:true,fetch:(url,view)=>{
  if(new URL(url,'http://localhost').searchParams.get('method')==='canvas.get')return new Promise(resolve=>{release=resolve;});
  return {ok:true,json:async()=>view};
 }});t.after(()=>page.cy.destroy());
 page.run('importedCanvas.openSession("pending",true)');await settle();
 const before=page.networkRequests.length;
 page.sockets[0].onmessage({data:JSON.stringify({type:'viewInvalidated',snapshotID:'new-index'})});await settle();
 assert.equal(page.networkRequests.length,before);assert.equal(page.cy.nodes().length,0);
 page.elements.get('workspace-home').onclick({preventDefault(){}});await settle();
 assert.equal(page.cy.getElementById('origin').length,1);assert.equal(page.history.state.canvasSessionID,undefined);
 assert.equal(page.history.entries.at(-1).url,'/');
 release({ok:true,json:async()=>({viewSessionID:'pending',revision:1,document:{sourceDigest:'d',kind:'relations',title:'Late',nodes:[{id:'late',label:'Late'}],edges:[]},state:{}})});
 await settle();assert.equal(page.cy.getElementById('late').length,0);
});
test('browser Back and Forward restore queries and controls; in-app Back shares that history',async t=>{
  const page=await render([entity('module','module')]);t.after(()=>page.cy.destroy());
  assert.equal(page.elements.get('back').disabled,true);assert.equal(page.history.entries.length,1);
  page.elements.get('level').value='function';page.elements.get('level').onchange();await settle();
  assert.equal(requestedQuery(page).level,'function');assert.equal(page.history.entries.length,2);
  page.elements.get('relation').value='calls';page.elements.get('language').value='swift';page.elements.get('direction').value='incoming';page.elements.get('direction').onchange();await settle();
  assert.equal(page.history.entries.length,3);page.history.back();await settle();
  assert.equal(requestedQuery(page).level,'function');assert.deepEqual(requestedQuery(page).kinds,undefined);assert.equal(page.elements.get('relation').value,'');assert.equal(page.elements.get('language').value,'');assert.equal(page.elements.get('direction').value,'outgoing');
  page.elements.get('back').onclick();await settle();assert.equal(page.history.index,0);assert.equal(page.elements.get('level').value,'context');assert.equal(page.elements.get('back').disabled,true);
  page.history.forward();await settle();page.history.forward();await settle();
  assert.deepEqual(requestedQuery(page).kinds,['calls']);assert.equal(page.elements.get('language').value,'swift');assert.equal(page.elements.get('direction').value,'incoming');assert.equal(page.history.entries.length,3);
});
test('search creates one return point per search session and Back cancels pending typing',async t=>{
  const page=await render([entity('module','module')]);t.after(()=>page.cy.destroy());
  const input=page.elements.get('search');input.value='Arch';input.oninput();await new Promise(resolve=>setTimeout(resolve,220));
  assert.equal(requestedQuery(page).text,'Arch');assert.equal(page.history.entries.length,2);
  input.value='Architecture';input.oninput();await new Promise(resolve=>setTimeout(resolve,220));assert.equal(page.history.entries.length,2);assert.equal(requestedQuery(page).text,'Architecture');
  input.value='Pending';input.oninput();page.history.back();await new Promise(resolve=>setTimeout(resolve,220));
  assert.equal(input.value,'');assert.equal(requestedQuery(page).method,'graph.overview');assert.equal(page.history.index,0);
  page.history.forward();await settle();assert.equal(input.value,'Architecture');assert.equal(requestedQuery(page).text,'Architecture');
});
test('pagination is navigable and new navigation after Back drops the abandoned forward branch',async t=>{
  const page=await render([entity('module','module')]);t.after(()=>page.cy.destroy());
  page.view.nextCursor='cursor-2';page.elements.get('more').onclick();await settle();assert.equal(requestedQuery(page).cursor,'cursor-2');assert.equal(requestedQuery(page).snapshotID,'snapshot');
  page.history.back();await settle();assert.equal(requestedQuery(page).cursor,undefined);
  page.elements.get('level').value='file';page.elements.get('level').onchange();await settle();assert.equal(page.history.entries.length,2);page.history.forward();await settle();assert.equal(requestedQuery(page).level,'file');
});

test('traversal restores captured viewport, selection and List mode in both directions',async t=>{
  const page=await render([entity('one','module')]);t.after(()=>page.cy.destroy());
  const finish=()=>page.worker.onmessage({data:{...page.worker.message,nodes:[{id:'one',x:0,y:0}]}});finish();
  page.cy.getElementById('one').emit('tap');await settle();page.run("window.graph.zoom(1.4);window.graph.pan({x:123,y:87});");page.elements.get('list-toggle').onclick();
  page.elements.get('level').value='function';page.elements.get('level').onchange();await settle();finish();
  page.run("window.graph.zoom(.9);window.graph.pan({x:321,y:78});");page.elements.get('list-toggle').onclick();
  page.history.back();await settle();finish();
  assert.equal(page.cy.zoom(),1.4);assert.deepEqual({...page.cy.pan()},{x:123,y:87});assert.equal(page.cy.$(':selected').id(),'one');assert.equal(page.elements.get('node-list').hidden,false);
  page.history.forward();await settle();finish();assert.equal(page.cy.zoom(),.9);assert.deepEqual({...page.cy.pan()},{x:321,y:78});assert.equal(page.elements.get('node-list').hidden,true);
});
test('reload restores the route and initial token removal never stores the token in entries',async t=>{
  const state={architectureExplorer:1,index:2,query:{method:'graph.search',text:'Core',limit:50},level:'component',list:true};
  const restored=await render([entity('Core','module')],[],false,{state});t.after(()=>restored.cy.destroy());
  assert.equal(requestedQuery(restored).text,'Core');assert.equal(restored.elements.get('search').value,'Core');assert.equal(restored.elements.get('level').value,'component');assert.equal(restored.elements.get('node-list').hidden,false);assert.equal(restored.history.entries.length,1);
  const authenticated=await render([entity('module','module')],[],false,{hash:'#token=one-use-token'});t.after(()=>authenticated.cy.destroy());
  assert.equal(authenticated.networkRequests[0],'/session');assert.doesNotMatch(JSON.stringify(authenticated.history.entries),/one-use-token|token=/);assert.equal(authenticated.elements.get('back').disabled,true);
  const saved=await render([entity('Saved','module')],[],true);t.after(()=>saved.cy.destroy());saved.elements.get('level').value='file';saved.elements.get('level').onchange();await settle();assert.equal(saved.history.state,null);assert.equal(saved.history.entries.length,1);assert.equal(saved.networkRequests.length,0);assert.match(terminalMessages(saved),/not bundled/);
});
test('rapid Back ignores stale query success and failure, and foreign state cannot invoke RPC',async t=>{
  const pending=[];
  const page=await render([entity('one','module')],[],false,{fetch:(url,view)=>{const query=JSON.parse(new URL('http://localhost'+url).searchParams.get('params'));if(query.level==='function')return new Promise((resolve,reject)=>pending.push({resolve,reject}));return {ok:true,json:async()=>view};}});t.after(()=>page.cy.destroy());
  page.elements.get('level').value='function';page.elements.get('level').onchange();page.history.back();await settle();
  pending[0].resolve({ok:true,json:async()=>({...page.view,nodes:[entity('obsolete','module')]})});await settle();assert.equal(page.cy.getElementById('obsolete').length,0);assert.equal(page.elements.get('level').value,'context');
  page.history.forward();await settle();page.history.back();await settle();pending[1].reject(Error('Obsolete request failed'));await settle();assert.doesNotMatch(terminalMessages(page),/Obsolete/);
  const count=page.networkRequests.length;page.history.pushState({architectureExplorer:1,index:3,query:{method:'workspace.import'}},'');page.history.back();await settle();const afterBack=page.networkRequests.length;assert.ok(afterBack>=count);page.history.forward();await settle();assert.equal(page.networkRequests.length,afterBack);assert.notEqual(requestedQuery(page).method,'workspace.import');
});

test('a current navigation failure remains visible and Back returns to the previous query',async t=>{
  const page=await render([entity('one','module')],[],false,{fetch:(url,view)=>{const query=JSON.parse(new URL('http://localhost'+url).searchParams.get('params'));if(query.level==='function')return Promise.reject(Error('Provider unavailable'));return {ok:true,json:async()=>view};}});t.after(()=>page.cy.destroy());
  page.elements.get('level').value='function';page.elements.get('level').onchange();await settle();assert.match(terminalMessages(page),/Provider unavailable/);assert.equal(page.history.entries.length,2);
  page.history.back();await settle();assert.equal(requestedQuery(page).level,'context');assert.match(terminalMessages(page),/Provider unavailable[\s\S]*Loaded graph.overview/);
});
test('returning to the same selection cannot append a source response from the abandoned inspection',async t=>{
  for(const failure of [false,true])await t.test(failure?'stale failure':'stale success',async t=>{
    const sources=[];
    const page=await render([entity('one','module')],[],false,{fetch:(url,view)=>{if(new URL('http://localhost'+url).searchParams.get('method')==='source.read')return new Promise((resolve,reject)=>sources.push({resolve,reject}));return {ok:true,json:async()=>view};}});t.after(()=>page.cy.destroy());
    page.worker.onmessage({data:{...page.worker.message,nodes:[{id:'one',x:0,y:0}]}});page.cy.getElementById('one').emit('tap');await settle();
    page.elements.get('level').value='function';page.elements.get('level').onchange();await settle();page.history.back();await settle();assert.equal(sources.length,2);
    sources[1].resolve({ok:true,json:async()=>({text:'Current source'})});await settle();if(failure)sources[0].reject(Error('Stale source failure'));else sources[0].resolve({ok:true,json:async()=>({text:'Stale source body'})});await settle();
    const contents=page.elements.get('inspector').children.map(e=>String(e.textContent)).join(' ');assert.match(contents,/Current source/);assert.doesNotMatch(contents,/Stale source/);
  });
});

test('edge focus follows hover and selection, restores context, and preserves every recorded fact',async t=>{
  const nodes=['a','b','c','d'].map(id=>entity(id,'module'));
  const edges=[['ab','a','b'],['bc','b','c'],['cd','c','d']].map(([id,source,target])=>({id,source,target,kind:'dependsOn'}));
  const page=await render(nodes,edges, true);t.after(()=>page.cy.destroy());
  const opacity=id=>Number(page.cy.getElementById(id).style('opacity')),base=opacity('ab');assert.ok(base>0&&base<1);
  page.run("window.graph.zoom(1.1);window.graph.pan({x:123,y:87});");
  const before=JSON.stringify(page.cy.nodes().map(n=>[n.id(),{...n.position()}]));
  page.cy.getElementById('b').emit('tap');assert.ok(opacity('ab')>base);assert.ok(opacity('bc')>base);assert.ok(opacity('cd')<base);
  page.cy.getElementById('d').emit('mouseover');assert.ok(opacity('cd')>base);assert.ok(opacity('ab')<base);
  page.cy.getElementById('a').emit('mouseout');assert.ok(opacity('cd')>base,'An unrelated mouseout cannot clear the current preview');
  page.cy.getElementById('d').emit('mouseout');assert.ok(opacity('ab')>base);assert.ok(opacity('cd')<base);
  page.cy.getElementById('d').emit('mouseover');page.cy.getElementById('cd').emit('mouseover');page.run('window.graph.panBy({x:1,y:0});');assert.ok(opacity('ab')>base);assert.ok(opacity('cd')<base);assert.equal(page.cy.edges('.hovered').length,0);page.run('window.graph.panBy({x:-1,y:0});');
  page.cy.getElementById('d').emit('mouseover');page.cy.zoom(1.2);assert.ok(opacity('ab')>base);assert.ok(opacity('cd')<base);page.cy.zoom(1.1);
  page.theme.value='dark';page.media.change();assert.ok(opacity('ab')>base);assert.equal(page.cy.$(':selected').id(),'b');
  page.cy.nodes().unselect();for(const edge of page.cy.edges())assert.equal(opacity(edge.id()),base);
  page.cy.getElementById('cd').emit('mouseover');assert.ok(opacity('cd')>base);page.cy.getElementById('cd').emit('mouseout');assert.equal(opacity('cd'),base);
  page.cy.getElementById('b').emit('tap');page.key('Escape');assert.equal(page.cy.$(':selected').length,0);for(const edge of page.cy.edges())assert.equal(opacity(edge.id()),base);assert.ok(page.elements.get('inspector').children.some(n=>n.textContent==='No Selection'));
  assert.equal(JSON.stringify(page.cy.nodes().map(n=>[n.id(),{...n.position()}])),before);assert.ok(page.cy.nodes().every(n=>Number(n.style('opacity'))===1));assert.equal(page.cy.edges().length,3);assert.equal(listRows(page.elements.get('node-list')).filter(e=>e.className==='relation-row').length,3);assert.equal(page.networkRequests.length,0);assert.equal(page.cy.zoom(),1.1);assert.deepEqual({...page.cy.pan()},{x:123,y:87});
});

test('frame hover keeps the overview quiet; explicit frame selection includes descendant connections',async t=>{
  const nodes=[entity('p','package'),...['a','b','c'].map(id=>entity(id,'module'))];
  const edges=[['pa','p','a','contains'],['pb','p','b','contains'],['ab','a','b','dependsOn'],['bc','b','c','dependsOn']].map(([id,source,target,kind])=>({id,source,target,kind}));
  const page=await render(nodes,edges,true);t.after(()=>page.cy.destroy());const opacity=id=>Number(page.cy.getElementById(id).style('opacity')),base=opacity('ab');
  page.cy.getElementById('p').emit('mouseover');assert.equal(opacity('ab'),base);assert.equal(opacity('bc'),base);page.cy.getElementById('p').emit('mouseout');
  page.cy.getElementById('p').emit('tap');assert.ok(opacity('ab')>base);assert.ok(opacity('bc')>base);
  page.cy.getElementById('a').emit('mouseover');assert.ok(opacity('ab')>base);assert.ok(opacity('bc')<base);page.cy.getElementById('a').emit('mouseout');assert.ok(opacity('bc')>base);
  page.cy.emit('tap');assert.equal(page.cy.$(':selected').length,0);assert.equal(opacity('ab'),base);assert.equal(opacity('bc'),base);assert.equal(page.cy.edges().length,2);assert.equal(listRows(page.elements.get('node-list')).filter(e=>e.className==='relation-row').length,4);
});

test('rendered frames match allocated geometry and never overlap unrelated nodes or sibling scopes',async t=>{
  const fixture=JSON.parse(fs.readFileSync(path.join(__dirname,'Fixtures/architecture-layout.json'),'utf8'));
  const page=await render(fixture.nodes,fixture.edges);t.after(()=>page.cy.destroy());
  const model=require(path.join(assets,'layout-model.js')),ELK=require(path.join(assets,'elk.bundled.js'));
  const result=await model.layout(page.worker.message,new ELK());page.worker.onmessage({data:result});
  const elements=[...page.cy.nodes()];
  function verify(){
    for(let i=0;i<elements.length;i++)for(let j=i+1;j<elements.length;j++){
      const a=elements[i],b=elements[j];if(a.ancestors().some(n=>n.id()===b.id())||b.ancestors().some(n=>n.id()===a.id()))continue;
      const x=a.boundingBox({includeLabels:false,includeOverlays:false}),y=b.boundingBox({includeLabels:false,includeOverlays:false});
      assert.equal(x.x1<y.x2&&x.x2>y.x1&&x.y1<y.y2&&x.y2>y.y1,false,`${a.id()} overlaps unrelated ${b.id()}`);
    }
    for(const node of page.cy.nodes(':parent')){
      const width=node.width()+2*Number(node.numericStyle('padding')),height=node.height()+2*Number(node.numericStyle('padding')),top=node.position().y-height/2;
      for(const child of node.children())assert.ok(child.boundingBox({includeLabels:false,includeOverlays:false}).y1-top>=64,'Children leave the complete header unobstructed');
      const image=page.svg(node.id());assert.equal(Number(image.match(/<svg[^>]*width="([^"]+)"/)[1]),width,'Header artwork spans the full frame width');
    }
  }
  verify();
  for(const box of result.nodes.filter(n=>n.group)){
    const element=page.cy.getElementById(box.id),width=element.width()+2*Number(element.numericStyle('padding')),height=element.height()+2*Number(element.numericStyle('padding'));
    assert.ok(Math.abs(width-box.width)<.01&&Math.abs(height-box.height)<.01,'Renderer and layout agree on the frame body size');
  }
  page.theme.value='dark';page.media.change();verify();page.cy.getElementById(fixture.nodes.find(n=>n.kind==='module').id).emit('tap');verify();
});

test('dragged children retain header clearance and resized frame artwork follows their bounds',async t=>{
  const nodes=[entity('p','package'),entity('a','module'),entity('b','module')],edges=['a','b'].map(id=>({id:'owns-'+id,source:'p',target:id,kind:'contains'}));
  const page=await render(nodes,edges,true);t.after(()=>page.cy.destroy());
  page.run("const moving=window.graph.getElementById('a');moving.position({x:moving.position().x+600,y:moving.position().y-200}).emit('drag');");
  const frame=page.cy.getElementById('p'),width=frame.width()+2*Number(frame.numericStyle('padding')),height=frame.height()+2*Number(frame.numericStyle('padding')),top=frame.position().y-height/2;
  assert.equal(Number(page.svg('p').match(/<svg[^>]*width="([^"]+)"/)[1]),width);
  for(const child of frame.children())assert.ok(child.boundingBox({includeLabels:false,includeOverlays:false}).y1-top>=64);
  assert.equal(page.networkRequests.length,0);
});
test('inconsistent frame geometry is a visible layout failure',async t=>{
  const page=await render([entity('p','package'),entity('a','module')],[{id:'owns',source:'p',target:'a',kind:'contains'}]);t.after(()=>page.cy.destroy());
  assert.doesNotThrow(()=>page.worker.onmessage({data:{...page.worker.message,nodes:[{id:'p',x:0,y:0,width:10,height:10,group:true},{id:'a',x:0,y:0,width:264,height:112}]}}));
  assert.match(terminalMessages(page),/does not contain its rendered children/);
});


test('files and nested declarations are real frames with readable basenames',async t=>{
  const nodes=[entity('file','file',{}, {name:'Sources/Session/SessionAuthority.swift',anchor:{path:'Sources/Session/SessionAuthority.swift'}}),entity('actor','actor',{}, {name:'SessionAuthority'}),entity('method','method',{}, {name:'authorize'}),entity('top','function')];
  const edges=[['file','actor'],['actor','method'],['file','top']].map(([source,target])=>({id:source+'-'+target,source,target,kind:'contains'}));
  const page=await render(nodes,edges,true);t.after(()=>page.cy.destroy());
  assert.equal(page.cy.getElementById('actor').parent().id(),'file');assert.equal(page.cy.getElementById('method').parent().id(),'actor');assert.equal(page.cy.getElementById('top').parent().id(),'file');
  assert.match(page.svg('file'),/>SessionAuthority.swift</);assert.equal(listRows(page.elements.get('navigator'))[0].children[1].textContent,'SessionAuthority.swift');assert.match(listRows(page.elements.get('navigator'))[0].title,/Sources\/Session\/SessionAuthority.swift/);
  assert.equal(page.cy.edges().length,0);assert.equal(listRows(page.elements.get('node-list')).filter(n=>n.className==='relation-row').length,3);
  for(const frame of page.cy.nodes(':parent')){
    const box=frame.boundingBox({includeLabels:false,includeOverlays:false});
    for(const child of frame.children()){const rect=child.boundingBox({includeLabels:false,includeOverlays:false});assert.ok(rect.x1>=box.x1&&rect.x2<=box.x2&&rect.y1-box.y1>=64&&rect.y2<=box.y2);}
  }
});

test('Expand requests complete file outlines and reload upgrades legacy direct-child routes',async t=>{
  const page=await render([entity('module','module'),entity('file','file')]);t.after(()=>page.cy.destroy());
  listRows(page.elements.get('navigator'))[0].fire('dblclick');await settle();assert.deepEqual(requestedQuery(page),{method:'graph.children',focus:'module',level:'file',depth:3});
  listRows(page.elements.get('navigator'))[1].fire('dblclick');await settle();assert.deepEqual(requestedQuery(page),{method:'graph.children',focus:'file',level:'file',depth:2});
  const restored=await render([entity('module','module')],[],false,{state:{architectureExplorer:1,index:2,level:'module',query:{method:'graph.children',focus:'module',depth:1},camera:{zoom:.2,pan:{x:1,y:2}}}});t.after(()=>restored.cy.destroy());
  assert.deepEqual(requestedQuery(restored),{method:'graph.children',focus:'module',level:'file',depth:3});assert.equal(restored.history.entries.length,1);assert.equal(restored.history.state.camera,undefined);
});


test('Inspector tokenizes recorded Swift and Rust while preserving literal source safely',async t=>{
  const sources={swift:'public func exchange(_ token: String) throws -> String {\n  // <script> & comment\n  let value = "<img src=x onerror=alert(1)>"\n  return value + "42"\n}',rust:'pub fn exchange(token: &str) -> String {\n  // raw string and lifetime\n  let value = r#"<script>alert(1)</script>"#;\n  let count: u32 = 42;\n  value.to_string()\n}'};
  const decode=html=>html.replace(/<\/?span(?: class="[^"]*")?>/g,'').replace(/&(amp|lt|gt|quot|#x27);/g,(_,entity)=>({amp:'&',lt:'<',gt:'>',quot:'"','#x27':"'"}[entity]));
  for(const language of ['swift','rust']){
    const source=sources[language];
    const page=await render([entity('symbol','function',{'syntax.signature':language==='swift'?'public func exchange(_ token: String) throws -> String':'pub fn exchange(token: &str) -> String'},{language})],[],false,{fetch:(url,view)=>({ok:true,json:async()=>new URL('http://localhost'+url).searchParams.get('method')==='source.read'?{text:source,truncated:true}:view})});t.after(()=>page.cy.destroy());
    page.cy.getElementById('symbol').emit('tap');await settle();
    const blocks=page.elements.get('inspector').children.filter(e=>e.tagName==='pre');assert.equal(blocks.length,2);
    for(const block of blocks){assert.match(block.innerHTML,/class="hljs-keyword"/);assert.match(block.innerHTML,/class="hljs-type"/);assert.equal(block.dataset.language,language);assert.doesNotMatch(block.innerHTML,/<(?:script|img)\b|<[^>]+onerror=/);}
    const preview=blocks[1];assert.equal(decode(preview.innerHTML),source);assert.match(preview.innerHTML,/hljs-string/);assert.match(preview.innerHTML,/hljs-comment/);assert.ok(preview.children.some(n=>n.textContent==='\n… [range truncated]'),'The notice is outside the highlighted source');
    const before=preview.innerHTML,requests=page.networkRequests.length;page.theme.value='dark';page.media.change();assert.equal(preview.innerHTML,before);assert.equal(page.networkRequests.length,requests);assert.equal(page.cy.$(':selected').id(),'symbol');
  }
});

test('unknown language stays literal; missing highlighter and oversized blocks are explicit',async t=>{
  const page=await render([entity('unknown','function',{'syntax.signature':'<unsafe> & literal'},{language:'kotlin'}),entity('large','function',{'syntax.signature':'x'.repeat(16385)}),entity('missing','function',{'syntax.signature':'func missing() {}'})],[],true);t.after(()=>page.cy.destroy());
  page.cy.getElementById('unknown').emit('tap');let pre=page.elements.get('inspector').children.find(e=>e.tagName==='pre');assert.equal(pre.textContent,'<unsafe> & literal');assert.equal(pre.innerHTML,undefined);assert.equal(pre.dataset.language,'plaintext');
  page.cy.getElementById('large').emit('tap');pre=page.elements.get('inspector').children.find(e=>e.tagName==='pre');assert.equal(pre.textContent.length,16385);assert.ok(pre.children.some(n=>/Highlighting limit/.test(n.textContent)));
  page.run('ArchitectureSyntax=undefined;');page.cy.getElementById('missing').emit('tap');pre=page.elements.get('inspector').children.find(e=>e.tagName==='pre');assert.equal(pre.textContent,'func missing() {}');assert.ok(pre.children.some(n=>/Highlighting unavailable/.test(n.textContent)));
});


test('syntax tokens keep readable contrast against both system code surfaces',()=>{
  const css=fs.readFileSync(path.join(assets,'explorer.css'),'utf8');
  const luminance=hex=>{const rgb=hex.slice(1).match(/../g).map(v=>parseInt(v,16)/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4);return rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722;};
  for(const root of css.matchAll(/:root\s*\{([^}]+)\}/g)){
    const background=luminance(root[1].match(/--field:\s*(#[\da-f]{6});/)[1]),tokens=[...root[1].matchAll(/--syntax-[\w-]+:\s*(#[\da-f]{6});/g)];assert.equal(tokens.length,6);
    for(const token of tokens){const color=luminance(token[1]);assert.ok((Math.max(color,background)+.05)/(Math.min(color,background)+.05)>=4.5,token[0]);}
  }
});


test('sidebar toggle restores preferred width and preserves graph state in live and saved views',async t=>{
  for(const saved of [false,true]){
    const page=await render([entity('one','module')],[],saved);t.after(()=>page.cy.destroy());
    const toggle=page.elements.get('sidebar-toggle'),pane=page.elements.get('navigator-pane'),left=page.elements.get('sidebar-resizer'),workspace=page.elements.get('workspace-body');
    left.fire('keydown',{key:'ArrowRight',shiftKey:true});const width=left['aria-valuenow'];
    page.run("window.graph.zoom(1.3);window.graph.pan({x:123,y:87});window.graph.getElementById('one').position({x:111,y:222}).select();");
    const requests=page.networkRequests.length,layout=page.worker?.message,generation=layout?.generation;
    assert.equal(toggle['aria-expanded'],'true');assert.equal(toggle['aria-controls'],'navigator-pane');assert.equal(toggle['aria-label'],'Hide sidebar');
    toggle.fire('click');assert.equal(pane.hidden,true);assert.equal(left.hidden,true);assert.equal(left.tabIndex,-1);assert.equal(workspace.style.getPropertyValue('--sidebar-width'),'0px');assert.equal(toggle['aria-expanded'],'false');assert.equal(toggle['aria-label'],'Show sidebar');assert.equal(toggle.disabled,false);
    page.theme.value='dark';page.media.change();assert.equal(pane.hidden,true);
    page.observers.find(o=>o.target===page.elements.get('graph')).callback();
    toggle.fire('click');assert.equal(pane.hidden,false);assert.equal(left.hidden,false);assert.equal(left['aria-valuenow'],width);assert.equal(toggle['aria-expanded'],'true');assert.equal(toggle.title,'Hide sidebar');
    assert.equal(page.networkRequests.length,requests);assert.equal(page.worker?.message.generation,generation);assert.equal(page.cy.zoom(),1.3);assert.deepEqual({...page.cy.pan()},{x:123,y:87});assert.equal(page.cy.$(':selected').id(),'one');assert.deepEqual({...page.cy.getElementById('one').position()},{x:111,y:222});
  }
});

test('hiding during a drag flushes its width, releases capture, and keeps responsive preference',async t=>{
  const page=await render([entity('one','module')],[],true);t.after(()=>page.cy.destroy());
  const toggle=page.elements.get('sidebar-toggle'),pane=page.elements.get('navigator-pane'),left=page.elements.get('sidebar-resizer'),workspace=page.elements.get('workspace-body'),observer=page.observers.find(o=>o.target===workspace);
  left.fire('pointerdown',{button:0,pointerId:7,clientX:190});left.fire('pointermove',{pointerId:7,clientX:290});assert.equal(page.frames.size,1);
  toggle.fire('click');assert.equal(page.frames.size,0);assert.equal(left.pointer,undefined);assert.equal(workspace.classList.contains('is-resizing'),false);assert.equal(pane.hidden,true);
  workspace.width=700;observer.callback();assert.equal(toggle.disabled,true);assert.equal(toggle['aria-expanded'],'false');toggle.fire('click');
  workspace.width=1400;observer.callback();assert.equal(toggle.disabled,false);assert.equal(pane.hidden,true);
  toggle.fire('click');assert.equal(left['aria-valuenow'],'290');assert.equal(pane.hidden,false);
  workspace.width=700;observer.callback();assert.equal(pane.hidden,true);workspace.width=1400;observer.callback();assert.equal(pane.hidden,false);assert.equal(left['aria-valuenow'],'290');
});

test('sidebar visibility survives hierarchy navigation and native history',async t=>{
  const page=await render([entity('one','module')]);t.after(()=>page.cy.destroy());
  const toggle=page.elements.get('sidebar-toggle'),pane=page.elements.get('navigator-pane');toggle.fire('click');
  page.elements.get('level').value='file';page.elements.get('level').onchange();await settle();assert.equal(pane.hidden,true);
  page.history.back();await settle();assert.equal(pane.hidden,true);assert.equal(toggle['aria-expanded'],'false');
  toggle.fire('click');assert.equal(pane.hidden,false);
});


test('property rows expose access, binding, name and type without card chrome and remain selectable',async t=>{
  const nodes=[entity('owner','type',{'declaration.kind':'struct'}),entity('count','field',{'declaration.access':'public','declaration.setterAccess':'private','declaration.binding':'var','declaration.type':'Int','syntax.signature':'public private(set) var count: Int'}, {anchor:{path:'Counter.swift',startByte:20}}),entity('name','field',{'declaration.access':'private','declaration.binding':'let','declaration.type':'String'}, {anchor:{path:'Counter.swift',startByte:10}}),entity('legacy','field',{'syntax.signature':'public let legacy: [String: Value]'}),entity('unknown','field',{'declaration.binding':'var'}),entity('alias','field',{'declaration.kind':'typeAlias'}),entity('outside','type')];
  const edges=[...nodes.slice(1).filter(n=>n.id!=='outside').map(n=>({id:'owns-'+n.id,source:'owner',target:n.id,kind:'contains'})),{id:'uses-count',source:'count',target:'outside',kind:'usesType'}];
  const page=await render(nodes,edges,true);t.after(()=>page.cy.destroy());
  for(const id of ['count','name','legacy','unknown']){const n=page.cy.getElementById(id);assert.equal(n.width(),640);assert.equal(n.height(),32);assert.equal(n.parent().id(),'owner');assert.match(page.svg(id),/data-presentation="property-row"/);assert.doesNotMatch(page.svg(id),/data-language|data-role|Counter.swift|No source anchor/);}
  assert.match(page.svg('count'),/>public \/ private\(set\)</);assert.match(page.svg('count'),/>var</);assert.match(page.svg('count'),/>count</);assert.match(page.svg('count'),/>: Int</);assert.match(page.svg('name'),/>let</);assert.match(page.svg('legacy'),/public let legacy/);assert.match(page.svg('unknown'),/implicit/);assert.match(page.svg('unknown'),/type not recorded/);assert.equal(page.cy.getElementById('alias').height(),112);
  const columns=[...page.svg('count').matchAll(/<text x="(\d+)" y="(\d+)"/g)].map(match=>[Number(match[1]),Number(match[2])]);
  assert.deepEqual(columns,[[12,21],[184,21],[254,21],[416,21]],'Access, binding, name and type retain the original single-line columns');
  const name=page.cy.getElementById('name'),count=page.cy.getElementById('count');assert.equal(count.position().y-name.position().y,32);
  count.emit('tap');assert.equal(page.cy.$(':selected').id(),'count');assert.ok(page.elements.get('inspector').children.some(e=>e.textContent==='count'));assert.equal(count.height(),32);assert.equal(page.cy.edges().length,1);assert.equal(page.cy.getElementById('uses-count').source().id(),'count');assert.equal(Number(page.cy.getElementById('uses-count').style('opacity')),1);assert.equal(listRows(page.elements.get('node-list')).filter(e=>e.className==='relation-row').length,6);
  const before=page.svg('count');page.theme.value='dark';page.media.change();assert.notEqual(page.svg('count'),before);assert.equal(page.cy.$(':selected').id(),'count');assert.equal(count.height(),32);
});


test('a property with descendants keeps a frame with compact declaration metadata',async t=>{
  const page=await render([entity('computed','property',{'declaration.access':'public','declaration.binding':'var','declaration.type':'View'}),entity('local','function')],[{id:'owns-local',source:'computed',target:'local',kind:'contains'}],true);t.after(()=>page.cy.destroy());
  assert.equal(page.cy.getElementById('local').parent().id(),'computed');assert.equal(page.cy.getElementById('computed').isParent(),true);assert.match(page.svg('computed'),/data-presentation="property-frame"/);assert.match(page.svg('computed'),/public var computed: View/);assert.doesNotMatch(page.svg('computed'),/data-language|data-role|No source anchor/);
});


const hierarchyFixture=()=>{
  const nodes=[entity('workspace','workspace'),entity('package','package'),entity('module','module'),entity('file','file',{}, {name:'Sources/Model.swift'}),entity('type','type',{'declaration.kind':'struct'},{name:'Model'})];
  const edges=[...nodes.slice(1).map((n,i)=>({id:'parent-'+n.id,source:nodes[i].id,target:n.id,kind:'contains'})),{id:'workspace-file',source:'workspace',target:'file',kind:'contains'}];return {nodes,edges};
};
const breadcrumbLinks=page=>page.elements.get('breadcrumb').children.filter(n=>n.className?.startsWith('crumb-item')).map(n=>n.children.find(c=>c.tagName==='button'));
test('breadcrumbs use pinned recorded ancestors outside the visible graph and navigate through browser history',async t=>{
  const fixture=hierarchyFixture(),ancestry=[];
  const page=await render([fixture.nodes.at(-1)],[],false,{fetch:(url,view)=>{const u=new URL('http://localhost'+url),q=JSON.parse(u.searchParams.get('params'));if(u.searchParams.get('method')==='graph.neighbors'&&q.direction==='incoming'){ancestry.push(q);return {ok:true,json:async()=>({...view,...fixture})};}return {ok:true,json:async()=>view};}});t.after(()=>page.cy.destroy());
  listRows(page.elements.get('navigator'))[0].fire('dblclick');await settle();
  assert.deepEqual(breadcrumbLinks(page).map(n=>n.textContent),['package','module','Model.swift']);assert.equal(page.elements.get('view-title').textContent,'Model');assert.equal(page.cy.nodes().length,1,'Ancestor metadata does not expand Canvas elements');assert.equal(page.elements.get('counts').textContent,'1 entities · 0 relations');
  assert.deepEqual(ancestry[0],{focus:'type',snapshotID:'snapshot',kinds:['contains'],direction:'incoming',depth:8,limit:500,edgeLimit:1500});
  const picker=page.elements.get('breadcrumb').children.find(n=>n.tagName==='select');assert.deepEqual(picker.children.slice(1).map(n=>n.value),['package','module','file']);
  breadcrumbLinks(page).at(-1).fire('click');await settle();assert.deepEqual(requestedQuery(page),{method:'graph.children',focus:'file',level:'file',depth:2});assert.equal(page.history.entries.length,3);assert.equal(page.elements.get('view-title').textContent,'Model.swift');
  page.history.back();await settle();assert.equal(page.elements.get('view-title').textContent,'Model');page.history.forward();await settle();assert.equal(page.elements.get('view-title').textContent,'Model.swift');
  page.elements.get('breadcrumb').children[0].fire('click');await settle();assert.deepEqual(requestedQuery(page),{method:'graph.overview',level:'context'});
});

test('breadcrumb ancestor picker preserves snapshot pinning and escapes source names',async t=>{
  const fixture=hierarchyFixture();fixture.nodes[1].name='<img src=x onerror=alert(1)>';
  const state={architectureExplorer:1,index:2,level:'file',query:{method:'graph.children',focus:'type',level:'file',depth:2,snapshotID:'snapshot'}};
  const page=await render([fixture.nodes.at(-1)],[],false,{state,fetch:(url,view)=>({ok:true,json:async()=>new URL('http://localhost'+url).searchParams.get('method')==='graph.neighbors'?{...view,...fixture}:view})});t.after(()=>page.cy.destroy());
  assert.equal(breadcrumbLinks(page)[0].textContent,fixture.nodes[1].name);assert.equal(breadcrumbLinks(page)[0].innerHTML,undefined);
  const picker=page.elements.get('breadcrumb').children.find(n=>n.tagName==='select');picker.value='module';picker.onchange();await settle();assert.deepEqual(requestedQuery(page),{method:'graph.children',focus:'module',level:'file',depth:3,snapshotID:'snapshot'});
  const restored=await render([fixture.nodes.at(-1)],[],false,{state,fetch:(url,view)=>({ok:true,json:async()=>new URL('http://localhost'+url).searchParams.get('method')==='graph.neighbors'?{...view,...fixture}:view})});t.after(()=>restored.cy.destroy());assert.equal(restored.history.entries.length,1);assert.equal(restored.elements.get('view-title').textContent,'Model');assert.equal(breadcrumbLinks(restored).length,3);
});

test('ambiguous, truncated, mismatched and failed ancestry is explicit without inventing parents',async t=>{
  for(const failure of ['ambiguous','truncated','mismatch','failure','cycle']){
    const fixture=hierarchyFixture();if(failure==='ambiguous'){fixture.nodes.push(entity('other','module'));fixture.edges.push({id:'other-owner',source:'other',target:'type',kind:'contains'});}if(failure==='cycle')fixture.edges.push({id:'cycle',source:'type',target:'workspace',kind:'contains'});
    const page=await render([fixture.nodes.at(-1)],[],false,{state:{architectureExplorer:1,index:0,query:{method:'graph.children',focus:'type',level:'file'}},fetch:(url,view)=>{if(new URL('http://localhost'+url).searchParams.get('method')==='graph.neighbors'){if(failure==='failure')return Promise.reject(Error('Backend unavailable'));return {ok:true,json:async()=>({...view,...fixture,truncated:failure==='truncated',snapshotID:failure==='mismatch'?'other':view.snapshotID})};}return {ok:true,json:async()=>view};}});t.after(()=>page.cy.destroy());
    const notice=page.elements.get('breadcrumb').children.find(n=>n.className==='crumb-notice');assert.equal(notice.textContent,'Hierarchy incomplete',failure);assert.equal(breadcrumbLinks(page).length,0,failure);assert.equal(page.cy.nodes().length,1);assert.equal(page.elements.get('view-title').textContent,'Model');
  }
});

test('stale ancestry success and failure cannot overwrite a newer route; saved views stay offline',async t=>{
  for(const failure of [false,true]){
    const fixture=hierarchyFixture(),pending=[];
    const page=await render([fixture.nodes.at(-1)],[],false,{fetch:(url,view)=>new URL('http://localhost'+url).searchParams.get('method')==='graph.neighbors'?new Promise((resolve,reject)=>pending.push({resolve,reject})):({ok:true,json:async()=>view})});t.after(()=>page.cy.destroy());
    listRows(page.elements.get('navigator'))[0].fire('dblclick');await settle();assert.equal(pending.length,1);assert.equal(breadcrumbLinks(page).length,0);
    page.elements.get('level').value='function';page.elements.get('level').onchange();await settle();if(failure)pending[0].reject(Error('Obsolete ancestry'));else pending[0].resolve({ok:true,json:async()=>({...page.view,...fixture})});await settle();assert.equal(page.elements.get('view-title').textContent,'Functions & Methods');assert.equal(breadcrumbLinks(page).length,0);assert.equal(page.elements.get('breadcrumb').children.some(n=>n.className==='crumb-notice'),false);
  }
  const saved=await render([entity('saved','module')],[],true);t.after(()=>saved.cy.destroy());assert.equal(saved.elements.get('breadcrumb').children[0].disabled,true);assert.equal(saved.elements.get('view-title').textContent,'Saved snapshot');assert.equal(saved.networkRequests.length,0);
});


test('deep hierarchy suffix is explicit and a mode breadcrumb links back to its focused scope',async t=>{
  const nodes=Array.from({length:9},(_,i)=>entity('ancestor-'+i,'type')),edges=nodes.slice(1).map((n,i)=>({id:'edge-'+i,source:nodes[i].id,target:n.id,kind:'contains'}));
  const state={architectureExplorer:1,index:0,query:{method:'graph.neighbors',focus:'ancestor-8',depth:2}};
  const page=await render([nodes.at(-1)],[],false,{state,fetch:(url,view)=>{const u=new URL('http://localhost'+url),q=JSON.parse(u.searchParams.get('params'));return {ok:true,json:async()=>q.direction==='incoming'?{...view,nodes,edges}:view};}});t.after(()=>page.cy.destroy());
  assert.equal(page.elements.get('view-title').textContent,'Neighbors');assert.match(page.elements.get('breadcrumb').children.find(n=>n.className==='crumb-notice').title,/eight-level/);assert.equal(breadcrumbLinks(page).length,9);
  breadcrumbLinks(page).at(-1).fire('click');await settle();assert.deepEqual(requestedQuery(page),{method:'graph.children',focus:'ancestor-8',level:'file',depth:2});
});


test('method nodes reserve result space and retain bordered selectable Edge endpoints',async t=>{
  const attrs={'declaration.kind':'method','declaration.access':'public','declaration.parameters':'(_ key: String, transform: (Int) -> Bool, '+ 'argument: LongType, '.repeat(30)+')','declaration.returnType':'[String: Int]','declaration.modifiers':['async','throws'],'syntax.signature':'public func fetch(_ key: String) async throws -> [String: Int]'};
  const page=await render([entity('owner','actor'),entity('fetch','method',attrs),entity('init','method',{'declaration.kind':'initializer','declaration.parameters':'(token: String)','declaration.modifiers':[]}),entity('legacy','method',{'syntax.signature':'private func legacy() -> Value'}),entity('outside','function')],[...['fetch','init','legacy'].map(id=>({id:'owns-'+id,source:'owner',target:id,kind:'contains'})),{id:'call',source:'fetch',target:'outside',kind:'calls'}],true);t.after(()=>page.cy.destroy());
  const svg=page.svg('fetch'),method=page.cy.getElementById('fetch');
  assert.equal(method.width(),264);assert.equal(method.height(),140);assert.match(svg,/data-presentation="callable-node"/);assert.ok(parseFloat(method.style('border-width'))>0);assert.ok(Number(method.style('background-opacity'))>0);
  for(const value of ['public','async throws','→ [String: Int]'])assert.ok(svg.includes('>'+value+'<'),value);
  assert.match(svg,/<text x="12" y="45"[^>]*>fetch\(_ key: String, .*…<\/text>/);
  assert.doesNotMatch(svg,/<text[^>]*>\(_ key:/);
  assert.match(svg,/<text x="12" y="110"[^>]*>→ \[String: Int\]<\/text>/);
  assert.match(svg,/data-role="method"[^>]*translate\(32 3\)/);assert.match(svg,/text-anchor="middle" dominant-baseline="central"/);assert.match(svg,/…/);
  assert.match(svg,/data-language="swift"/);assert.match(svg,/data-logo-part="bird"[^>]*fill="#ffffff"/);assert.doesNotMatch(svg,/No source anchor/);assert.match(page.svg('init'),/>init\(token: String\)</);assert.match(page.svg('init'),/>Initializer</);assert.doesNotMatch(page.svg('init'),/→ Void|→ Self/);assert.match(page.svg('legacy'),/not recorded/);assert.match(page.svg('legacy'),/private func legacy/);
  assert.equal(page.cy.getElementById('outside').height(),140);
  method.emit('tap');assert.equal(page.cy.$(':selected').id(),'fetch');assert.ok(page.elements.get('inspector').children.some(e=>e.textContent==='fetch'));assert.equal(page.cy.getElementById('call').source().id(),'fetch');
  page.theme.value='dark';page.media.change();assert.notEqual(page.svg('fetch'),svg);assert.equal(page.cy.$(':selected').id(),'fetch');assert.equal(method.height(),140);
});

test('module child cards keep compact fixed bounds through compound layout and metadata refresh',async t=>{
  const nodes=[entity('package','package'),entity('short','module'),entity('long','module',{'project.manifest':'Nested/Package.swift'},{name:'LongModuleName'.repeat(20),language:'none'})];
  const edges=[...nodes.slice(1).map(n=>({id:'owns-'+n.id,source:'package',target:n.id,kind:'contains'})),{id:'dependency',source:'short',target:'long',kind:'dependsOn'}];
  const page=await render(nodes,edges);t.after(()=>page.cy.destroy());
  const verify=()=>{for(const id of ['short','long']){const n=page.cy.getElementById(id);assert.equal(n.width(),264);assert.equal(n.height(),112);assert.match(page.svg(id),/<svg[^>]*width="264" height="112"/);}};
  verify();const model=require(path.join(assets,'layout-model.js')),ELK=require(path.join(assets,'elk.bundled.js'));
  page.worker.onmessage({data:await model.layout(page.worker.message,new ELK())});verify();
  const sent=page.worker.message,positions=page.cy.nodes().map(n=>({...n.position()}));
  nodes[1].name='EvenLongerName'.repeat(80);nodes[1].attributes['syntax.signature']='metadata '.repeat(200);page.view.snapshotID='changed-metadata';page.sockets[0].onmessage({data:JSON.stringify({type:'viewInvalidated',snapshotID:'invalidation'})});await settle();verify();
  assert.equal(page.worker.message,sent);assert.deepEqual(page.cy.nodes().map(n=>({...n.position()})),positions);
  page.theme.value='dark';page.media.change();verify();assert.deepEqual(page.cy.nodes().map(n=>({...n.position()})),positions);
  const dependency=page.cy.getElementById('dependency');assert.equal(dependency.source().id(),'short');assert.equal(dependency.target().id(),'long');
});

test('fixed card widths and original property rows survive Swift/Rust metadata, themes and live refresh',async t=>{
  for(const saved of [false,true]){
    const nodes=[entity('owner','type'),entity('field','field',{'declaration.access':'pub(crate)','declaration.binding':'static mut','declaration.type':'Result<Value, Error>'},{language:'rust'}),entity('method','method',{'declaration.access':'public','declaration.parameters':'()','declaration.returnType':'Result<Value, Error>','declaration.modifiers':['async','throws']}),entity('free','function',{'declaration.access':'pub','declaration.parameters':'(value: '+ 'VeryLongType, '.repeat(60)+')','declaration.returnType':'Result<Value, Error>','declaration.modifiers':['async','unsafe']},{language:'rust'}),entity('alias','field',{'declaration.kind':'typeAlias'})];
    const edges=[...nodes.slice(1).map(n=>({id:'owns-'+n.id,source:'owner',target:n.id,kind:'contains'})),{id:'call-free',source:'method',target:'free',kind:'candidateCalls'},{id:'use-field',source:'field',target:'alias',kind:'usesType'}];
    const page=await render(nodes,edges,saved);t.after(()=>page.cy.destroy());
    if(!saved){const model=require(path.join(assets,'layout-model.js')),ELK=require(path.join(assets,'elk.bundled.js'));page.worker.onmessage({data:await model.layout(page.worker.message,new ELK())});}
    for(const id of ['method','free','alias']){assert.equal(page.cy.getElementById(id).width(),264);assert.match(page.svg(id),/<svg[^>]*width="264"/);}assert.equal(page.cy.getElementById('field').width(),640);assert.equal(page.cy.getElementById('field').height(),32);
    assert.match(page.svg('free'),/…/);assert.match(page.svg('free'),/>→ Result&lt;Value, Error&gt;</);assert.match(page.svg('free'),/>async unsafe</);
    assert.match(page.svg('field'),/>pub\(crate\)</);assert.match(page.svg('field'),/>static …</);assert.equal(nodes.find(n=>n.id==='field').attributes['declaration.binding'],'static mut');
    const positions=page.cy.nodes().map(n=>({...n.position()})),frame=page.cy.getElementById('owner').width();assert.ok(frame>264);
    page.theme.value='dark';page.media.change();assert.deepEqual(page.cy.nodes().map(n=>({...n.position()})),positions);
    if(!saved){const sent=page.worker.message;nodes.find(n=>n.id==='method').attributes['declaration.parameters']='(argument: Type, '.repeat(100)+')';page.view.snapshotID='updated';page.sockets[0].onmessage({data:JSON.stringify({type:'viewInvalidated',snapshotID:'invalidation'})});await settle();assert.equal(page.worker.message,sent);assert.equal(page.cy.getElementById('owner').width(),frame);assert.deepEqual(page.cy.nodes().map(n=>({...n.position()})),positions);assert.match(page.svg('method'),/…/);}
    for(const fact of edges.filter(e=>e.kind!=='contains')){const edge=page.cy.getElementById(fact.id);assert.equal(edge.source().id(),fact.source);assert.equal(edge.target().id(),fact.target);}
  }
});

test('methods with children keep readable compact headers and allocated compound bounds',async t=>{
  const page=await render([entity('owner','actor'),entity('request','method',{'declaration.access':'private','declaration.parameters':'()','declaration.returnType':'Response','declaration.modifiers':['async','throws']}),entity('local','field',{'declaration.binding':'let','declaration.type':'String'})],[{id:'method',source:'owner',target:'request',kind:'contains'},{id:'local',source:'request',target:'local',kind:'contains'}],true);t.after(()=>page.cy.destroy());
  const method=page.cy.getElementById('request'),local=page.cy.getElementById('local');
  assert.equal(method.isParent(),true);assert.ok(method.width()>=264);assert.match(page.svg('request'),/data-presentation="callable-frame"/);assert.match(page.svg('request'),/>private</);assert.match(page.svg('request'),/>request\(\)</);assert.match(page.svg('request'),/>→ Response</);
  assert.equal(local.parent().id(),'request');assert.ok(local.boundingBox().y1>=method.boundingBox().y1+140);
});

test('real Swift/Rust source graphs render structured free functions, receivers and original Edge endpoints',{skip:!process.env.AE_CALLABLE_GRAPHS},async t=>{
  const cases=JSON.parse(fs.readFileSync(process.env.AE_CALLABLE_GRAPHS,'utf8'));
  assert.equal(cases.length,4);
  for(const {language,name,view} of cases){
    const page=await render(view.nodes,view.edges,true);t.after(()=>page.cy.destroy());
    for(const leaf of page.cy.nodes().filter(n=>!n.isParent())){const width=leaf.data('presentation')==='property-row'?640:264;assert.equal(leaf.width(),width,'Parsed declarations retain their presentation geometry');assert.ok(page.svg(leaf.id()).includes('width="'+width+'"'));}
    const declaration=view.nodes.find(n=>n.name===name&&['method','function'].includes(n.kind));assert.ok(declaration);
    const node=page.cy.getElementById(declaration.id),svg=page.svg(declaration.id),metadata=declaration.attributes['declaration.callable'];
    assert.equal(metadata.version,1);assert.match(svg,/data-presentation="callable-(?:node|frame)"/);assert.ok(svg.includes(`data-language="${language}"`));assert.ok(svg.includes('→ '));assert.ok(node.width()>=264);assert.ok(node.height()>=140);
    if(node.isParent()){const top=node.boundingBox({includeLabels:false,includeOverlays:false}).y1;for(const child of node.children())assert.ok(child.boundingBox({includeLabels:false,includeOverlays:false}).y1>=top+140,'Callable children clear all declaration lines');}
    if(name==='update'){
      assert.ok(svg.includes(language==='swift'?'inout T':"&amp;&apos;a mut self"));assert.ok(svg.includes(language==='swift'?'where T: Equatable':'where T: Clone'));
      assert.ok(svg.includes(language==='swift'?'mutating async throws':'async unsafe'));
      assert.ok(svg.includes(language==='swift'?'@MainActor':"Result&lt;&amp;&apos;a T, Error&gt;"));
    } else {assert.equal(declaration.kind,'function');assert.equal(metadata.receiver.kind,'none');assert.ok(svg.includes(name+'&lt;T&gt;'));}
    for(const fact of view.edges){
      const edge=page.cy.getElementById(fact.id);
      if(edge.empty()){assert.equal(fact.kind,'contains');assert.equal(page.cy.getElementById(fact.target).parent().id(),fact.source);continue;}
      assert.equal(edge.source().id(),fact.source);assert.equal(edge.target().id(),fact.target);
      if(edge.hasClass('routed')||edge.hasClass('direct')){
        for(const [end,element]of [['routeStart',edge.source()],['routeEnd',edge.target()]]){
          const offset=edge.data(end).split(' ').map(parseFloat),center=element.position(),point={x:center.x+offset[0],y:center.y+offset[1]},box=element.boundingBox({includeLabels:false,includeOverlays:false});
          assert.ok(Number.isFinite(point.x)&&Number.isFinite(point.y));assert.ok(point.x>=box.x1-2&&point.x<=box.x2+2&&point.y>=box.y1-2&&point.y<=box.y2+2,'Recorded route terminates on its original node');
        }
      }
    }
    assert.ok(view.edges.some(e=>e.kind==='usesType'),'Real parser type-reference edges reach the renderer');
    if(name==='update'){assert.ok(view.edges.some(e=>e.kind==='candidateCalls'));assert.ok(!view.edges.some(e=>e.kind==='calls'));}
    node.emit('tap');assert.equal(page.cy.$(':selected').id(),declaration.id);assert.ok(page.elements.get('inspector').children.some(n=>n.textContent===name));
    const before=page.svg(declaration.id);page.theme.value='dark';page.media.change();assert.notEqual(page.svg(declaration.id),before);assert.equal(page.cy.$(':selected').id(),declaration.id);
  }
});

test('the sequence catalogue lists full scenario metadata and opens the selected pinned sequence',async t=>{
  const participants=['macOS Task Workspace','Workspace Ledger'];
  const catalogue=[
    {key:'save',title:'Task save',requirements:['TODO01','TODO04'],participants},
    {key:'retry',title:'Retry same mutation',requirements:['TODO04'],participants}
  ];
  const reads=[];
  const page=await render([entity('workspace','workspace')],[],false,{canvasUI:true,fetch:(raw,view)=>{
    const url=new URL(raw,'http://localhost'),method=url.searchParams.get('method');
    if(method==='workspace.sequences')return {ok:true,json:async()=>({status:'available',snapshotID:'snapshot',sequences:catalogue})};
    if(method==='workspace.sequence'){
      reads.push(JSON.parse(url.searchParams.get('params')));
      return {ok:false,json:async()=>({error:'Scenario no longer available'})};
    }
    return {ok:true,json:async()=>view};
  }});
  t.after(()=>page.cy.destroy());
  page.elements.get('open-sequences').onclick();await settle();
  const reader=page.elements.get('specification-reader'),list=reader.children[1];
  assert.equal(reader.hidden,false);
  assert.equal(list.tagName,'ul');
  assert.equal(list['aria-label'],'Sequences');
  assert.deepEqual(list.children.map(item=>item.tagName),['li','li']);
  const rows=listRows(reader);
  assert.deepEqual(rows.map(row=>row.children.map(child=>child.textContent)),[
    ['Task save','TODO01, TODO04',participants.join(' · ')],
    ['Retry same mutation','TODO04',participants.join(' · ')],
  ]);
  rows[1].fire('click');await settle();
  assert.deepEqual(reads,[{snapshotID:'snapshot',key:'retry'}]);
  assert.equal(page.elements.get('counts').textContent,'Unavailable');
  page.history.back();await settle();
  assert.equal(reader.hidden,false);
  assert.equal(listRows(reader).length,2);
});

test('sequence headers center complete names and preserve directional messages at rest and on selection',async t=>{
  const model=require(path.join(assets,'canvas-model.js'));
  const participant='macOS Task Workspace and Sync';
  const document={kind:'sequence',title:'Messages',format:'json',sourceDigest:'d',
    lanes:[{id:'a',label:participant},{id:'b',label:'Server'}],
    nodes:[
      {id:'send',label:'begin',role:'send',laneID:'a',order:0},
      {id:'receive',label:'begin',role:'receive',laneID:'b',order:0},
      {id:'return',label:'reply',role:'send',laneID:'b',order:1},
      {id:'accept',label:'reply',role:'receive',laneID:'a',order:1},
      {id:'noteLeft',label:'shared',role:'send',laneID:'a',order:2},
      {id:'noteRight',label:'shared',role:'receive',laneID:'b',order:2},
    ],
    edges:[
      {id:'message',source:'send',target:'receive',label:'begin',role:'message',directed:true},
      {id:'reply',source:'return',target:'accept',label:'reply',role:'reply',directed:true},
      {id:'undirected',source:'noteLeft',target:'noteRight',label:'shared',role:'message',directed:false},
    ],
    metadata:{fragments:[{kind:'loop',label:'until complete',start:0,end:1}]}};
  const view=model.view({viewSessionID:'s',document,state:{}}),page=await render(view.nodes,view.edges,true,{diagram:view.canvas});
  t.after(()=>page.cy.destroy());
  const request={nodes:view.nodes,edges:view.edges,canvas:view.canvas};
  const result=await page.run('ArchitectureLayout.layout('+JSON.stringify(request)+',new ELK())');
  const fragment=page.cy.getElementById('__fragment:0'),expected=result.nodes.find(n=>n.id===fragment.id());
  assert.ok(Math.abs(fragment.position().x-(expected.x+expected.width/2))<.01);
  assert.ok(Math.abs(fragment.position().y-(expected.y+expected.height/2))<.01);

  const layout=view.nodes.find(node=>node.id==='__lane:a').canvas;
  for(const [id,label] of [['__lane:a',participant],['__lane:b','Server']]){
    const lane=page.cy.getElementById(id),svg=page.svg(id);
    const labels=[...svg.matchAll(/<text x="([\d.]+)" y="([\d.]+)" text-anchor="middle" dominant-baseline="central">([^<]+)<\/text>/g)];
    assert.equal(labels.map(line=>line[3]).join(' '),label);
    assert.ok(labels.every(line=>Number(line[1])===lane.outerWidth()/2));
    assert.equal((Number(labels[0][2])+Number(labels.at(-1)[2]))/2,layout.headerHeight/2);
    assert.match(svg,/stroke-dasharray="5 5"/);
    assert.match(svg,new RegExp('height="'+(lane.height()+2*Number(lane.numericStyle('padding')))+'"'));
  }
  assert.ok(layout.titleLines.length>1);
  const first=result.nodes.find(node=>node.id==='send');
  const lane=result.nodes.find(node=>node.id==='__lane:a');
  assert.ok(first.y>lane.y+layout.headerHeight);
  page.theme.value='dark';page.media.change();
  for(const [id,sign,pattern] of [['message',1,'solid'],['reply',-1,'dashed']]){
    const edge=page.cy.getElementById(id);
    assert.equal(Math.sign(edge.target().position().x-edge.source().position().x),sign);
    assert.equal(edge.style('line-style'),pattern);
    assert.equal(edge.style('target-arrow-shape'),'triangle');
    assert.ok(Number(edge.style('arrow-scale'))>1);
    assert.ok(Number(edge.numericStyle('target-distance-from-node'))>0);
    assert.equal(Number(edge.style('opacity')),1);
    const arrowScale=edge.style('arrow-scale');
    edge.select();
    assert.equal(edge.style('arrow-scale'),arrowScale);
  }
  assert.equal(page.cy.getElementById('undirected').style('target-arrow-shape'),'none');
});
test('real imported files render on the production Canvas with original semantic endpoints',{skip:!process.env.AE_CANVAS_DOCUMENTS},async t=>{
  const model=require(path.join(assets,'canvas-model.js')),documents=JSON.parse(fs.readFileSync(process.env.AE_CANVAS_DOCUMENTS,'utf8'));
  assert.ok(documents.length>=21);
  for(const document of documents){
    const session={viewSessionID:'import-'+document.sourceName,document,state:{collapsed:[],filter:{},layout:'auto'}},view=model.view(session);
    const page=await render(view.nodes,view.edges,true,{diagram:view.canvas});t.after(()=>page.cy.destroy());
    assert.equal(page.cy.nodes().length,view.nodes.length,document.sourceName);
    for(const fact of document.edges){const edge=page.cy.getElementById(fact.id);if(edge.empty()){assert.equal(fact.role,'contains');continue;}assert.equal(edge.source().id(),fact.source);assert.equal(edge.target().id(),fact.target);assert.equal(edge.data('canvasLabel'),fact.label);}
    const selectable=view.nodes.find(n=>!page.cy.getElementById(n.id).isParent());assert.ok(selectable);page.cy.getElementById(selectable.id).emit('tap');assert.equal(page.cy.$(':selected').id(),selectable.id);assert.ok(page.elements.get('inspector').children.some(n=>n.textContent===selectable.name));
    const positions=page.cy.nodes().map(n=>({...n.position()}));page.theme.value='dark';page.media.change();assert.deepEqual(page.cy.nodes().map(n=>({...n.position()})),positions,document.sourceName);
  }
});

test('imported session navigation clears stale Inspector details and enables browser back',async t=>{
 const page=await render([entity('source','module')],[],false,{canvasUI:true});t.after(()=>page.cy.destroy());
 const document={sourceDigest:'first',kind:'relations',title:'First',format:'json',sourceName:'one.json',nodes:[{id:'one',label:'First node',role:'state'}],edges:[],lanes:[],metadata:{}};
 const first={viewSessionID:'first',revision:1,document,state:{selection:['one'],filter:{},collapsed:[],layout:'auto',geometry:[]}};
 page.run('importedCanvas.present('+JSON.stringify(first)+',true)');assert.equal(page.elements.get('back').disabled,false);assert.ok(page.elements.get('inspector').children.some(e=>e.textContent==='First node'));
 const second={...first,viewSessionID:'second',document:{...document,sourceDigest:'second',title:'Second'},state:{...first.state,selection:[]}};
 page.run('importedCanvas.present('+JSON.stringify(second)+',true)');assert.ok(page.elements.get('inspector').children.some(e=>e.textContent==='No Selection'));assert.ok(!page.elements.get('inspector').children.some(e=>e.textContent==='First node'));
 page.history.back();await new Promise(setImmediate);assert.equal(page.history.state.canvasSessionID,'first');
});

test('whole-project Inspector separates model evidence from incomplete implementation and correspondence',async t=>{
 const page=await render([entity('source','module')],[],false,{canvasUI:true});t.after(()=>page.cy.destroy());
 const requirement={id:'R01',nodeID:'R01',title:'Contract',specification:{outcome:'passed',claims:['proof']},implementation:{outcome:'unsupported',claims:[],detail:'Production source profile unsupported'},correspondence:{outcome:'notVerified',claims:[],detail:'No source certificate'}};
 const document={sourceDigest:'report',kind:'proofDependencies',title:'Project',format:'json',sourceName:'Report.json',nodes:[{id:'R01',label:'R01 · Contract',role:'requirement',details:{condition:'The contract holds',requirement:'SPEC.md:3'}}],edges:[],metadata:{verificationReport:{schemaVersion:1,inventory:['R01'],requirements:[requirement],evidence:[{id:'proof',domain:'specification.lean',outcome:'passed',requirements:['R01'],scope:'Independent specification proof'}],receipts:[{path:'verification/receipt.json'}]}}};
 page.run('importedCanvas.present('+JSON.stringify({viewSessionID:'report',revision:1,document,state:{selection:['R01'],filter:{},collapsed:[],layout:'auto',geometry:[]}})+',true)');
 const contents=page.elements.get('inspector').children.map(element=>element.textContent).join(' ');
 for(const text of ['SPECIFICATION','IMPLEMENTATION','CORRESPONDENCE','Independent specification proof','Production source profile unsupported','No source certificate','SPEC.md:3','verification/receipt.json'])assert.ok(contents.includes(text),text);
 assert.ok(!contents.includes('"verificationReport"'));
 assert.match(page.elements.get('spec-verdict').textContent,/incomplete/);
});

test('imported self transitions use an exterior loop with the original selectable Edge identity',async t=>{
 const model=require(path.join(assets,'canvas-model.js')),document={kind:'stateTransition',title:'Loop',format:'json',sourceDigest:'d',nodes:[{id:'state',label:'Working',role:'state'}],edges:[{id:'tick',source:'state',target:'state',label:'tick',role:'transition'}],lanes:[]};
 const view=model.view({viewSessionID:'s',document,state:{}}),page=await render(view.nodes,view.edges,true,{diagram:view.canvas});t.after(()=>page.cy.destroy());const edge=page.cy.getElementById('tick');
 assert.equal(edge.style('curve-style'),'bezier');assert.ok(Number(edge.numericStyle('control-point-step-size'))>=edge.source().outerWidth());assert.equal(edge.style('loop-direction'),'90deg');edge.emit('tap');assert.equal(page.cy.$(':selected').id(),'tick');assert.ok(page.elements.get('inspector').children.some(e=>e.textContent==='tick'));
});

test('a resolved container opens the scoped component graph and retains its snapshot into code',async t=>{
  const container=entity('runner','application',{'context.owner':'system','context.entryID':'entry'});
  const entry=entity('entry','type');
  const page=await render([container],[],false,{fetch:async(raw,view)=>{
    const url=new URL(raw,'http://localhost'),query=JSON.parse(url.searchParams.get('params')||'{}');
    const result=query.focus==='entry'?{...view,nodes:[entry],extensions:query.level==='component'?{'implementation.scope':'Entry file · Runner.swift'}:{}}:view;
    return {ok:true,json:async()=>result};
  }});
  t.after(()=>page.cy.destroy());
  page.cy.getElementById('runner').emit('tap');
  const inspector=page.elements.get('inspector');
  inspector.children.find(el=>el.textContent==='Open components').fire('click');await settle();
  assert.deepEqual(page.history.state.query,{method:'graph.overview',level:'component',focus:'entry',snapshotID:'snapshot'});
  assert.equal(page.elements.get('c4-surface').hidden,true);
  page.cy.getElementById('entry').emit('tap');
  const actions=inspector.children.find(el=>el.className==='action-row');
  actions.children.find(el=>el.textContent==='Open code').fire('click');await settle();
  assert.equal(page.history.state.query.snapshotID,'snapshot');
  assert.equal(page.history.state.query.focus,'entry');
  assert.equal(page.history.state.query.method,'graph.children');
});

test('Map object inspection follows the source and destination of a declared interaction',async t=>{
  const nodes=['launcher','endpoint'].map(id=>({...entity(id,'softwareSystem'),attributes:{
    'context.areas':[{name:'Payments'}],'context.purpose':id+' purpose','context.containerCount':0
  }}));
  const edge={id:'request',kind:'dependsOn',source:'launcher',target:'endpoint',attributes:{'context.operation':'Creates a session','context.technology':'HTTPS'},evidenceIDs:[]};
  const page=await render(nodes,[edge]);t.after(()=>page.cy.destroy());
  page.cy.getElementById('launcher').emit('tap');
  const inspector=page.elements.get('inspector');
  const row=()=>inspector.children.find(e=>e.tagName==='ul'&&e['aria-label']==='Connections').children[0];
  assert.ok(inspector.children.find(e=>e.tagName==='dl').children.some(e=>e.textContent==='Payments'));
  assert.deepEqual(row().children.map(e=>e.textContent),['To','endpoint','Creates a session · HTTPS']);
  row().children[1].fire('click');
  assert.ok(inspector.children.some(e=>e.textContent==='endpoint purpose'));
  assert.deepEqual(row().children.map(e=>e.textContent),['From','launcher','Creates a session · HTTPS']);
  row().children[2].fire('click');
  assert.ok(inspector.children.some(e=>e.textContent==='launcher → endpoint'));
});

test('System Context exposes typed dependency evidence',async t=>{
  const nodes=['payments','ledger'].map(id=>({...entity(id,'softwareSystem'),identityKey:'system:default/'+id,attributes:{'context.purpose':'Catalog system'}}));
  const edges=[{id:'uses',kind:'dependsOn',source:'payments',target:'ledger',attributes:{'context.operation':'Depends on'},evidenceIDs:['catalog-record']}];
  const page=await render(nodes,edges);
  t.after(()=>page.cy.destroy());
  page.view.evidence=[{id:'catalog-record',anchor:{path:'payments/catalog-info.yaml'},inputDigest:'snapshot-digest'}];
  page.run("graph.getElementById('uses').emit('tap')");
  assert.ok(page.elements.get('inspector').children.some(child=>child.textContent==='payments/catalog-info.yaml'));
  assert.equal(page.cy.getElementById('uses').data('canvasLabel'),'Depends on');
});

test('unresolved System Context opens Modules on startup, home and view selection',async t=>{
  const workspace=entity('workspace','workspace'),file=entity('File.swift','file');
  const fetch=(url,view)=>{
    const query=JSON.parse(new URL(url,'http://localhost').searchParams.get('params')||'{}');
    const nodes=query.level==='context'?[]:query.level==='file'?[file]:[workspace];
    return {ok:true,json:async()=>({...view,nodes,snapshotID:query.snapshotID||view.snapshotID})};
  };
  const page=await render([workspace],[],false,{fetch});
  t.after(()=>page.cy.destroy());
  const assertModules=()=>{
    assert.equal(requestedQuery(page).level,'module');
    assert.equal(page.history.state.query.level,'module');
    assert.equal(page.cy.getElementById('workspace').length,1);
    assert.equal(page.elements.get('empty').hidden,true);
  };
  assertModules();
  assert.equal(page.history.entries.length,1);
  const level=page.elements.get('level');
  level.value='file';level.onchange();await settle();
  assert.equal(page.cy.getElementById('File.swift').length,1);
  page.elements.get('workspace-home').onclick({preventDefault(){}});await settle();
  assertModules();
  assert.equal(page.history.entries.length,3);
  page.history.back();await settle();
  assert.equal(page.cy.getElementById('File.swift').length,1);
  page.history.forward();await settle();
  assertModules();
  level.value='context';level.onchange();await settle();
  assertModules();

  const query={method:'graph.overview',level:'context',snapshotID:'retained'};
  const pinned=await render([workspace],[],false,{fetch,state:{architectureExplorer:1,index:2,query,level:'context',list:false}});
  t.after(()=>pinned.cy.destroy());
  assert.equal(pinned.history.state.index,2);
  assert.equal(pinned.history.state.query.level,'module');
  assert.equal(requestedQuery(pinned).snapshotID,'retained');
});

test('repository selection opens architecture and a service selects its composition',async t=>{
  const scopes=[];
  const page=await render([],[],false,{repository:true,fetch:async raw=>{
    const url=new URL(raw,'http://localhost');
    assert.equal(url.searchParams.get('method'),'repository.browse');
    const params=JSON.parse(url.searchParams.get('params'));scopes.push(params);
    const nodes=!params.repo?[{id:'core',label:'Core',role:'Repository'}]:
      !params.service?[{id:'service:api',label:'api',role:'Compose service',service:'api'}]:
      [{id:'entry',label:'api',role:'Service entry point',language:'typescript'}];
    return {ok:true,json:async()=>({title:'Core',nodes,edges:[]})};
  }});
  t.after(()=>page.cy.destroy());
  assert.match(page.svg('core'),/data-role="repository"/);
  assert.doesNotMatch(page.svg('core'),/data-language=/);
  page.cy.getElementById('core').emit('tap');
  await new Promise(setImmediate);
  listRows(page.elements.get('node-list'))[0].fire('click');
  await new Promise(setImmediate);
  assert.equal(page.cy.nodes().id(),'entry');
  assert.match(page.svg('entry'),/data-language="typescript"/);
  assert.match(page.svg('entry'),/data-role="entryPoint"/);
  assert.deepEqual(scopes,[{},{repo:'core',path:[]},{repo:'core',path:[],service:'api'}]);
  assert.equal(page.sockets.length,0);
});

test('source and diagram cards preserve language aliases and display future languages offline',async t=>{
  const model=require(path.join(assets,'canvas-model.js'));
  const diagram=model.view({viewSessionID:'icons',state:{},document:{nodes:[
    {id:'owner',role:'Class',label:'Service',language:'TSX'},
    {id:'method',role:'Method',label:'run',parentID:'owner',language:'ts'},
    {id:'future',role:'Future Role',label:'Future',details:{language:'Lang<x>'}},
    {id:'network',role:'Network',label:'Private'},
    {id:'repo',role:'npm library',label:'Repo',details:{checkouts:['repo'],evidence:['tsconfig.json']}},
    {id:'ambiguous',role:'Repository',label:'TS',details:{checkouts:['mixed'],manifest:'Package.swift',evidence:['tsconfig.json']}}],edges:[],kind:'relations'}});
  const page=await render(diagram.nodes,diagram.edges,true,{diagram:diagram.canvas});
  t.after(()=>page.cy.destroy());
  for(const theme of ['light','dark']){
    page.theme.value=theme;page.media.change();
    for(const id of ['owner','method']){
      assert.match(page.svg(id),/data-language="typescript".*aria-label="TypeScript"/);
      assert.match(page.svg(id),/fill="#3178c6"/i);
      assert.match(page.svg(id),new RegExp('data-role="'+(id==='owner'?'class':'method')+'"'));
    }
    assert.match(page.svg('future'),/data-language="lang&lt;x&gt;"/);
    assert.match(page.svg('future'),/data-logo-part="monogram"/);
    assert.doesNotMatch(page.svg('network'),/data-language=/);
    assert.match(page.svg('network'),/data-role="network"/);
    assert.match(page.svg('repo'),/data-language="typescript"/);
    assert.doesNotMatch(page.svg('ambiguous'),/data-language=/);
  }
  assert.equal(page.networkRequests.length,0);
});

test('each bundled language has local artwork on a source card and a callable',async t=>{
  const languages=['typescript','javascript','swift','rust','python','go','kotlin','c','cplusplus','terraform'];
  const kinds=['function','class'];
  const page=await render(languages.flatMap(language=>kinds.map(kind=>entity(language+kind,kind,{}, {language}))));
  t.after(()=>page.cy.destroy());
  for(const language of languages)for(const kind of kinds){
    const svg=page.svg(language+kind);
    assert.ok(svg.includes('data-language="'+language+'"'));
    assert.match(svg,/data-logo-part="(?:bird|symbol)"/);
  }
});

test('type-reference edges and relation list open the pinned source expression',async t=>{
  const nodes=[entity('month','type',{}, {anchor:{path:'Month.swift'}}),entity('dates','type')];
  const edge={id:'use',source:'month',target:'dates',kind:'candidateTypeReference',evidenceIDs:['proof'],attributes:{
    'reference.scope':'Sources/Calendar','reference.site':{name:'dates',line:7,startByte:123,endByte:134}}};
  const reads=[];
  const page=await render(nodes,[edge],false,{fetch:async(raw,view)=>{
    const url=new URL(raw,'http://localhost');
    if(url.searchParams.get('method')!=='source.read')return {ok:true,json:async()=>view};
    reads.push(JSON.parse(url.searchParams.get('params')));
    return {ok:true,json:async()=>({text:'Dates.start',truncated:false})};
  }});t.after(()=>page.cy.destroy());
  page.cy.getElementById('use').emit('tap');await settle();
  assert.equal(page.cy.getElementById('use').data('relation'),'candidate-types');
  assert.ok(page.elements.get('inspector').children.some(child=>child.textContent==='Month.swift:7'));
  const row=listRows(page.elements.get('node-list')).find(child=>child.className==='relation-row');
  assert.equal(row.tagName,'button');row.fire('click');await settle();
  assert.deepEqual(reads,[0,1].map(()=>({entityID:'month',snapshotID:'snapshot',startByte:123,endByte:134})));
});

test('file canvas opens on linked declarations inside their files and can reveal the full outline',async t=>{
  const nodes=[entity('A.swift','file'),entity('B.swift','file'),entity('Month','type'),
    entity('Dates','type'),entity('Unused','type')];
  const ownership=[['A.swift','Month'],['B.swift','Dates'],['A.swift','Unused']].map(([source,target])=>({
    id:source+target,kind:'contains',source,target}));
  const use={id:'use',kind:'candidateTypeReference',source:'Month',target:'Dates',attributes:{}};
  const settings={extensions:{'file.outline':true},state:{architectureExplorer:1,index:0,level:'file',query:{method:'graph.overview',level:'file'}}};
  const page=await render(nodes,[...ownership,use],false,settings);
  t.after(()=>page.cy.destroy());
  assert.equal(page.cy.getElementById('Month').parent().id(),'A.swift');
  assert.equal(page.cy.getElementById('Dates').parent().id(),'B.swift');
  assert.equal(page.cy.edges().length,1);
  assert.equal(page.cy.edges().id(),'use');
  assert.equal(page.cy.getElementById('Unused').length,0);
  assert.equal(page.elements.get('counts').textContent,'4 entities on canvas · 1 link');
  page.cy.getElementById('A.swift').emit('tap');
  const inspector=page.elements.get('inspector');
  assert.ok(inspector.children.some(el=>el.textContent==='CROSS-FILE TYPE REFERENCES'));
  inspector.children.flatMap(el=>el.children).find(el=>el.textContent==='Month → Dates').fire('click');
  assert.equal(page.cy.nodes('.reference-endpoint').length,2);
  assert.ok(page.cy.getElementById('use').hasClass('context-focused'));
  const toggle=page.elements.get('file-detail');
  toggle.onclick();
  assert.equal(page.cy.getElementById('Unused').parent().id(),'A.swift');
  toggle.onclick();
  listRows(page.elements.get('navigator')).find(n=>n.dataset.entityId==='Unused').fire('click');
  assert.ok(page.cy.getElementById('Unused').selected());
  const outline=await render(nodes,ownership,false,settings);
  t.after(()=>outline.cy.destroy());
  assert.equal(outline.cy.nodes().length,5);
  assert.equal(outline.cy.edges().length,0);
  assert.equal(outline.elements.get('file-detail').hidden,true);
  assert.match(outline.elements.get('mode-label').textContent,/no links/i);
});

test('the property menu opens an editable annotation during the click and preserves the pinned request until the conversation reads it',async t=>{
  const tools=new Map(),annotations=[],events=[];
  const outcomes=[true,false,new Error('Editor unavailable'),false,true];
  const propertyBrowser={tools,annotate:(target,options)=>{
    annotations.push({target,options});
    events.push('annotation');
    const outcome=outcomes.shift();
    if(outcome instanceof Error)throw outcome;
    return {accepted:outcome};
  }};
  const longName='VeryLongSymbol'.repeat(20);
  const page=await render([entity('Selected','type'),entity('Another','type'),entity(longName,'type'),entity('Selected.swift','file')],[{id:'ownership',kind:'contains',source:'Selected.swift',target:'Selected'}],false,{propertyBrowser,fetch:(url,view,options)=>{
    let data=view;
    if(url.includes('host.context'))data={propertyActions:true,csrf:'csrf'};
    if(url==='/properties'){
      const input=JSON.parse(options.body);
      data={};
      if(!input.connect){
        events.push('context');
        data={workspaceID:view.workspaceID,snapshotID:view.snapshotID,entityID:input.entityID,files:[{path:'Selected.swift',role:'selected',text:'sample'}],relations:[]};
      }
    }
    return {ok:true,json:async()=>data};
  }});
  t.after(()=>page.cy.destroy());
  await tools.get('connect_verification_actions').execute({threadID:'owner'});
  function choose(id){
    page.flushFrames();
    const card=page.elements.get('node-header-menus').children.find(el=>el.dataset.nodeId===id);
    card.children.find(el=>el.title==='Actions for '+id).fire('click');
    const commands=page.elements.get('canvas-picker').children.at(-1).children;
    commands.find(el=>el.textContent==='Define verification conditions').fire('click');
  }
  choose('Selected');
  assert.deepEqual(events,['annotation','context']);
  const {target,options}=annotations[0];
  function checkBounds(target,id){
    const graphNode=page.cy.getElementById(id);
    assert.equal(target.dataset.nodeId,id);
    assert.equal(parseFloat(target.style.width),graphNode.outerWidth());
    assert.equal(parseFloat(target.style.height),graphNode.outerHeight());
    const {x,y}=graphNode.position();
    assert.equal(target.style.transform,'translate('+(x-graphNode.outerWidth()/2)+'px,'+(y-graphNode.outerHeight()/2)+'px)');
  }
  checkBounds(target,'Selected');
  assert.equal(options.omitScreenshot,false);
  await new Promise(setImmediate);
  assert.equal(page.run('document.body.children.length'),0);
  assert.equal(options.metadata.entityID,'Selected');
  assert.equal(options.metadata.snapshotID,'snapshot');
  assert.ok(options.initialComment.length<=240);
  assert.ok(options.initialComment.startsWith('$formal-verification'));
  assert.match(options.initialComment,/Define verification conditions for “Selected”/);
  assert.match(options.initialComment,/read_verification_request/);
  assert.ok(options.initialComment.includes(options.metadata.requestID));
  choose('Another');
  await new Promise(setImmediate);
  const dialog=page.run('document.body.children.at(-1)');
  const close=dialog.children[0].children.find(el=>el['aria-label']==='Close');
  assert.equal(close.textContent,'×');
  close.fire('click');
  assert.equal(dialog.open,false);
  choose('Another');
  await new Promise(setImmediate);
  for(let attempt=0;attempt<2;attempt++){
    const recovery=page.run('document.body.children.at(-1)');
    assert.ok(recovery.open);
    recovery.children[1].children.find(el=>el.textContent==='Open annotation').fire('click');
    await new Promise(setImmediate);
    assert.equal(recovery.open,false);
  }
  assert.equal(page.run('document.body.children.some(el=>el.open)'),false);
  assert.equal(annotations.at(-1).options.metadata.requestID,annotations[2].options.metadata.requestID);
  outcomes.push(true);
  choose(longName);
  const longPrompt=annotations.at(-1).options;
  assert.ok(longPrompt.initialComment.length<=240);
  assert.match(longPrompt.initialComment,/^\$formal-verification/);
  assert.ok(longPrompt.initialComment.endsWith(longPrompt.metadata.requestID));
  const read=tools.get('read_verification_request').execute;
  const input={threadID:'owner',page:0,requestID:options.metadata.requestID};
  const result=await read(input);
  assert.equal(JSON.parse(result.chunk).entityID,'Selected');
  await assert.rejects(read({...input,threadID:'other'}));
  await assert.rejects(read({...input,requestID:'expired'}));
  outcomes.push(true);
  choose('Selected.swift');
  const frame=annotations.at(-1);
  checkBounds(frame.target,'Selected.swift');
  assert.equal(frame.options.metadata.entityID,'Selected.swift');
  assert.equal(page.cy.getElementById('Selected').parent().id(),'Selected.swift');
  assert.ok(parseFloat(frame.target.style.height)>parseFloat(target.style.height));
});

test('source card accessories share artwork, graph hit testing and a keyboard menu command',async t=>{
  const opened=[];
  const accessoryUI=class {
    constructor(context){this.context=context;}
    async refresh(){await Promise.resolve();this.modelView=this.context.view();this.modelPage={};this.nodeAccessories=new Map([
      ['type',[{icon:'bookmark',tone:'accent',label:'Design note'}]],
      ['method',[{icon:'info',tone:'neutral',label:'Documentation'}]],
      ['field',[{icon:'flag',tone:'accent',label:'Observation'}]]]);this.context.onPublicationsChanged();}
    *menuItems(){}
    modelSlot(){} modelCommand(){}
    async openNodeAccessory(id,item){opened.push([id,item.label]);}
  };
  const page=await render([entity('type','type'),entity('method','method'),entity('field','field'),entity('other','type')],[],false,{accessoryUI});
  t.after(()=>page.cy.destroy());
  for(const id of ['type','method','field'])assert.match(page.svg(id),/data-node-accessory="headerTrailing"/);
  assert.doesNotMatch(page.svg('other'),/data-node-accessory/);
  page.run(`{const n=graph.getElementById('type'),center=n.position();
    n.emit({type:'tap',position:{x:center.x+n.outerWidth()/2-42,y:center.y-n.outerHeight()/2+14}});}`);
  const header=page.elements.get('node-header-menus').children.find(el=>el.dataset.nodeId==='type');
  assert.equal(header.children.length,2);
  const result=header.children.find(child=>child.className==='node-result');
  assert.equal(result['aria-label'],'Open Design note · type');result.fire('click');
  header.children[0].fire('click');
  page.cy.emit('resize');
  assert.equal(page.elements.get('canvas-picker').open,true);
  page.elements.get('canvas-picker').children.at(-1).children.find(el=>el.textContent==='Design note').fire('click');
  assert.deepEqual(opened,[['type','Design note'],['type','Design note'],['type','Design note']]);
});

test('source headers keep verification in options and the menu opens its destination without an Inspector interaction',async t=>{
 const calls=[];
 const actions=class {
  constructor(context){this.context=context;}
  async refresh(){} modelSlot(){} *menuItems(){}
  modelCommand(host,entity,closeMenu){
   const command=new Element('button');command.textContent='Verify model';
   command.addEventListener('click',()=>{closeMenu();calls.push({entity:entity.id,snapshot:this.context.view().snapshotID});this.review={panel:new Element('section')};void this.context.enterVerification(this.context.view(),entity);});host.append(command);
  }
 };
 const anchor={path:'Subject.swift',startByte:0,endByte:20,digest:'input'};
 const source=[entity('type','type',{}, {anchor}),entity('method','method',{}, {anchor}),entity('member','field',{}, {anchor}),entity('file','file',{}, {anchor})];
 const page=await render(source,[],false,{accessoryUI:actions});t.after(()=>page.cy.destroy());
 const headers=page.elements.get('node-header-menus').children;
 for(const header of headers){assert.equal(header.children.length,1);assert.equal(header.children[0].textContent,'•••');}
 assert.ok(page.elements.get('inspector').children.some(child=>child.textContent==='No Selection'));
 headers.find(h=>h.dataset.nodeId==='method').children[0].fire('click');
 const picker=page.elements.get('canvas-picker');assert.equal(picker.open,true);
 const command=picker.children.find(child=>child.className==='node-commands').children.find(child=>child.textContent==='Verify model');
 assert.ok(command);command.fire('click');
 assert.equal(picker.open,false);assert.equal(page.elements.get('view-title').textContent,'Verify model');
 assert.equal(page.history.state.verification.entity.id,'method');
 assert.deepEqual(calls,[{entity:'method',snapshot:'snapshot'}]);
});

test('proof cards keep full roles and titles inside the same box used by layout',async t=>{
  const model=require(path.join(assets,'canvas-model.js'));
  const nodes=[
    {id:'internal-condition-id',role:'condition',label:'Expired holds cannot confirm'},
    {id:'internal-result-id',role:'result',label:'TLC · 3,190 states checked'},
    {id:'internal-proof-id',role:'Universal verification condition with a long role',label:'Changed retry payload is rejected '+ 'W'.repeat(48),details:{reportedStatus:'Unverified'}},
  ];
  const document={kind:'proofDependencies',title:'Booking',nodes,edges:[],lanes:[]};
  const view=model.view({viewSessionID:'proof',document});
  const page=await render(view.nodes,view.edges,true,{diagram:view.canvas});t.after(()=>page.cy.destroy());
  const result=await page.run('ArchitectureLayout.layout('+JSON.stringify(view)+',new ELK())');
  for(const node of nodes){
    const element=page.cy.getElementById(node.id),svg=page.svg(node.id);
    assert.equal(element.style('shape'),'round-rectangle');
    const rows=[...svg.matchAll(/<text [^>]*y="([\d.]+)"[^>]*>([^<]*)<\/text>/g)];
    const expected=[node.role,node.label,node.details?.reportedStatus].filter(Boolean).join('');
    assert.equal(rows.map(r=>r[2]).join('').replace(/\s/g,''),expected.replace(/\s/g,''));
    const box=result.nodes.find(n=>n.id===node.id);
    assert.equal(element.height(),box.height);
    assert.ok(rows.every(r=>Number(r[1])<box.height-4));
    assert.ok(!svg.includes(node.id));
  }
});


test('Map report opens from object options without an Inspector prerequisite and multiple reports use a local chooser',async t=>{
 const binding={workspaceID:'workspace',snapshotID:'snapshot',entityID:'system'};
 const report={viewSessionID:'report',revision:1,document:{kind:'proofDependencies',title:'Bound report',format:'json',sourceName:'report.json',sourceDigest:'digest',nodes:[{id:'condition',label:'Condition',role:'condition'}],edges:[],metadata:{specVerification:{mapBinding:binding,checks:[{nodeID:'condition',outcome:'notVerified'}]}}},state:{selection:[],filter:{},collapsed:[],layout:'auto'}};
 let reply;
 const page=await render([entity('system','softwareSystem')],[],false,{mapUI:true,canvasUI:true,accessoryUI:class {async refresh(){} modelSlot(){} modelCommand(){} *menuItems(){}},extensions:{'c4.context':{}},fetch:(url,view)=>{
  if(new URL(url,'http://localhost').searchParams.get('method')==='canvas.get')return new Promise(resolve=>{reply=resolve;});
  return {ok:true,json:async()=>view};
 }});t.after(()=>page.cy?.destroy());
 const entry={id:'report',title:'Bound report',digest:'digest',binding,summary:{title:'Unverified',tone:'neutral',open:[]}};
 page.run('mapTest.reports='+JSON.stringify([entry,{...entry,id:'other',title:'Another report'}]));
 assert.ok(page.elements.get('inspector').children.some(child=>child.textContent==='No Selection'));
 page.run('mapTest.actions.menu(mapTest.targets.get("system"),'+JSON.stringify(page.view.nodes[0])+')');
 const options=page.elements.get('canvas-picker');
 const reportCommand=options.children.find(child=>child.className==='node-commands').children.find(child=>child.textContent==='Open verification report');
 assert.ok(reportCommand);reportCommand.fire('click');
 const picker=page.elements.get('canvas-picker');assert.equal(picker.open,true);assert.equal(picker.children.length,2);
 picker.children.find(child=>child.textContent==='Bound report · Unverified').fire('click');
 assert.equal(page.elements.get('view-title').textContent,'Bound report');assert.equal(page.history.state.canvasSessionID,'report');
 await settle();reply({ok:true,json:async()=>report});await settle();
 assert.equal(page.cy.getElementById('condition').length,1);assert.ok(!page.networkRequests.some(url=>url.includes('source.read')));
});
